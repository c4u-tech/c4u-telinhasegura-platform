package curation

import (
	"context"
	"errors"
	"slices"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

const (
	packMinVideos = 3
	packMaxVideos = 5
	maxPackTitle  = 40 // runes, after trimming
)

// PackInput is a composition: the title, the ordered videos, the cover
// ("" is the first video) and an optional theme (packs, Contract).
type PackInput struct {
	Title        string
	VideoIDs     []string
	CoverVideoID string
	Theme        string
}

// composition is a PackInput that passed every rule, its IDs lower-cased.
type composition struct {
	title, cover, theme string
	videoIDs            []string
}

// and answers the first broken one as a PackInvalidError. A theme outside
// the set is ErrValidation. IDs are compared lower-cased, so the same
// video in two letter cases is a repeat, never a unique-index failure.
func (s *Service) checkComposition(ctx context.Context, q querier, in PackInput) (composition, error) {
	if in.Theme != "" && !validTheme(in.Theme) {
		return composition{}, ErrValidation
	}
	invalid := func(reason string) (composition, error) { return composition{}, &PackInvalidError{Reason: reason} }
	if n := len(in.VideoIDs); n < packMinVideos || n > packMaxVideos {
		return invalid(PackInvalidCount)
	}
	ids := make([]string, len(in.VideoIDs))
	for i, id := range in.VideoIDs {
		ids[i] = strings.ToLower(id)
	}
	if len(slices.Compact(slices.Sorted(slices.Values(ids)))) != len(ids) {
		return invalid(PackInvalidRepeat)
	}
	for _, id := range ids {
		if !validID(id) {
			return invalid(PackInvalidNotApproved)
		}
	}
	var approved, seconds int
	if err := q.QueryRow(ctx, `SELECT count(*), coalesce(sum(duration_seconds), 0) FROM videos
		WHERE id = ANY($1::text[]::uuid[]) AND state = 'approved'`, ids).Scan(&approved, &seconds); err != nil {
		return composition{}, err
	}
	if approved != len(ids) {
		return invalid(PackInvalidNotApproved)
	}
	if time.Duration(seconds)*time.Second > s.d.PackMaxDuration {
		return invalid(PackInvalidDuration)
	}
	cover := strings.ToLower(in.CoverVideoID)
	if cover == "" {
		cover = ids[0]
	}
	if !slices.Contains(ids, cover) {
		return invalid(PackInvalidCover)
	}
	title := strings.TrimSpace(in.Title)
	if n := utf8.RuneCountInString(title); n < 1 || n > maxPackTitle || strings.ContainsFunc(title, unicode.IsControl) {
		return invalid(PackInvalidTitle)
	}
	return composition{title: title, cover: cover, theme: in.Theme, videoIDs: ids}, nil
}

// curatorRole is the account's displayed curator role, read FOR SHARE:
// a removal waits for this write, and no write lands for a curator
// removed meanwhile.
func curatorRole(ctx context.Context, tx pgx.Tx, accountID string) (string, error) {
	var role string
	err := tx.QueryRow(ctx, `SELECT display_role FROM platform_roles WHERE account_id = $1::uuid AND role = 'curator' FOR SHARE`,
		accountID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotCurator
	}
	return role, err
}

// writeRound stores a round's composition, with its composer and a
// snapshot of their displayed role. Its outcome starts open.
func writeRound(ctx context.Context, tx pgx.Tx, packID string, round int, composerID, role string, c composition, now time.Time) error {
	if _, err := tx.Exec(ctx, `INSERT INTO pack_rounds (pack_id, round, title, cover_video_id, composer_id, composer_role, composed_at)
		VALUES ($1::uuid, $2, $3, $4::uuid, $5::uuid, $6, $7)`, packID, round, c.title, c.cover, composerID, role, now); err != nil {
		return err
	}
	for i, id := range c.videoIDs {
		if _, err := tx.Exec(ctx, `INSERT INTO pack_items (pack_id, round, position, video_id) VALUES ($1::uuid, $2, $3, $4::uuid)`,
			packID, round, i+1, id); err != nil {
			return err
		}
	}
	return nil
}

// Compose stores a curator's composition as a pending pack in round 1,
// the curator as its composer, and answers its detail. A
// broken rule stores nothing.
func (s *Service) Compose(ctx context.Context, curatorID string, in PackInput) (Pack, error) {
	now := s.now()
	var id string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		c, err := s.checkComposition(ctx, tx, in)
		if err != nil {
			return err
		}
		role, err := curatorRole(ctx, tx, curatorID)
		if err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `INSERT INTO packs (state, theme, created_at, updated_at)
			VALUES ('pending', nullif($1::text, ''), $2, $2) RETURNING id::text`, c.theme, now).Scan(&id); err != nil {
			return err
		}
		return writeRound(ctx, tx, id, 1, curatorID, role, c, now)
	})
	if err != nil {
		return Pack{}, err
	}
	return s.PackDetail(ctx, curatorID, id)
}

// Recompose opens the next round of a pack that is not removed with the
// caller's composition, the caller as its composer. Any
// curator may recompose any pack: pacotinhos belong to the team. A held
// pack becomes pending. An approved pack stays approved and keeps
// serving its published round until the new one publishes. The pack row
// lock comes first, so no review lands on the round being replaced.
func (s *Service) Recompose(ctx context.Context, curatorID, packID string, in PackInput) (Pack, error) {
	if !validID(packID) {
		return Pack{}, ErrNotFound
	}
	now := s.now()
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var round int
		var st string
		err := tx.QueryRow(ctx, `SELECT round, state FROM packs WHERE id = $1::uuid FOR UPDATE`, packID).Scan(&round, &st)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if State(st) == Removed {
			return ErrStateConflict
		}
		c, err := s.checkComposition(ctx, tx, in)
		if err != nil {
			return err
		}
		role, err := curatorRole(ctx, tx, curatorID)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE packs SET round = $2, theme = nullif($3::text, ''), updated_at = $4,
			state = CASE WHEN state = 'held' THEN 'pending' ELSE state END WHERE id = $1::uuid`,
			packID, round+1, c.theme, now); err != nil {
			return err
		}
		return writeRound(ctx, tx, packID, round+1, curatorID, role, c, now)
	})
	if err != nil {
		return Pack{}, err
	}
	return s.PackDetail(ctx, curatorID, packID)
}

// RemovePack takes a pack down for good: no child gets it again, and no
// route reopens it.
func (s *Service) RemovePack(ctx context.Context, adminID, packID string) error {
	if !validID(packID) {
		return ErrNotFound
	}
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var st string
		err := tx.QueryRow(ctx, `SELECT state FROM packs WHERE id = $1::uuid FOR UPDATE`, packID).Scan(&st)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if State(st) == Removed {
			return ErrStateConflict
		}
		_, err = tx.Exec(ctx, `UPDATE packs SET state = 'removed', updated_at = $2 WHERE id = $1::uuid`, packID, s.now())
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, adminID, audit.PackRemoved)
	return nil
}
