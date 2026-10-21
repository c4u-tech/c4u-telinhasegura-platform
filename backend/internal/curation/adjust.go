package curation

import (
	"context"
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// familyPage is the guardian catalogue's page size.
const familyPage = 50

// FamilyVideo is a video as a guardian browses what one child can see,
// with its provenance. Provenance never reaches a child.
type FamilyVideo struct {
	Video      Video
	Hidden     bool
	Provenance *Provenance
}

// familyOf is the account's family; an account in none is ErrNotFound.
// An account belongs to one family at most.
func familyOf(ctx context.Context, q querier, accountID string) (string, error) {
	var id string
	err := q.QueryRow(ctx, `SELECT family_id::text FROM family_members WHERE account_id = $1::uuid`, accountID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return id, err
}

// guardedChild is a child of the caller's family, with its band's rank.
// A malformed, unknown or foreign minor answers as unknown, ErrNotFound.
func guardedChild(ctx context.Context, q querier, accountID, minorID string) (Child, int, error) {
	familyID, err := familyOf(ctx, q, accountID)
	if err != nil {
		return Child{}, 0, err
	}
	c := Child{FamilyID: familyID, MinorID: minorID}
	rank, err := childBand(ctx, q, c)
	if errors.Is(err, ErrProfileGone) {
		return Child{}, 0, ErrNotFound
	}
	return c, rank, err
}

// liveVideo checks that videoID names a stored video that is not
// removed; a malformed ID answers as unknown.
func liveVideo(ctx context.Context, q querier, videoID string) error {
	if !validID(videoID) {
		return ErrNotFound
	}
	var live bool
	err := q.QueryRow(ctx, `SELECT state <> 'removed' FROM videos WHERE id = $1::uuid`, videoID).Scan(&live)
	if errors.Is(err, pgx.ErrNoRows) || err == nil && !live {
		return ErrNotFound
	}
	return err
}

// FamilyCatalog lists, by theme order then title, the approved videos
// whose band fits the child and that the family has not reported, each
// with whether it is hidden for the child and its provenance, in one
// snapshot. more reports a further page at offset + 50.
func (s *Service) FamilyCatalog(ctx context.Context, accountID, minorID string, offset int) ([]FamilyVideo, bool, error) {
	if offset < 0 {
		return nil, false, ErrValidation
	}
	tx, err := s.d.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)
	c, rank, err := guardedChild(ctx, tx, accountID, minorID)
	if err != nil {
		return nil, false, err
	}
	rows, err := tx.Query(ctx, `SELECT `+videoCols+`,
			EXISTS (SELECT 1 FROM video_hides h WHERE h.minor_id = $1::uuid AND h.video_id = v.id)
		FROM videos v WHERE v.state = 'approved' AND `+bandRankSQL+` <= $3
		AND NOT EXISTS (SELECT 1 FROM video_reports r WHERE r.family_id = $2::uuid AND r.video_id = v.id)
		ORDER BY array_position($4::text[], v.theme), v.title, v.id LIMIT $5 OFFSET $6`,
		c.MinorID, c.FamilyID, rank, themes, familyPage+1, offset)
	if err != nil {
		return nil, false, err
	}
	items, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (FamilyVideo, error) {
		var x FamilyVideo
		var err error
		x.Video, err = scanVideo(r, &x.Hidden)
		return x, err
	})
	if err != nil {
		return nil, false, err
	}
	more := len(items) > familyPage
	if more {
		items = items[:familyPage]
	}
	for i := range items {
		if items[i].Video.PublishedRound != nil {
			if items[i].Provenance, err = provenance(ctx, tx, items[i].Video); err != nil {
				return nil, false, err
			}
		}
	}
	return items, more, tx.Commit(ctx)
}

// Hide hides a stored video that is not removed from one of the caller's
// family's children. Hiding a hidden video changes and records nothing.
func (s *Service) Hide(ctx context.Context, accountID, minorID, videoID string) error {
	hid := false
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		c, _, err := guardedChild(ctx, tx, accountID, minorID)
		if err != nil {
			return err
		}
		if err := liveVideo(ctx, tx, videoID); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO video_hides (minor_id, video_id, hidden_by, hidden_at)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4) ON CONFLICT DO NOTHING`, c.MinorID, videoID, accountID, s.now())
		hid = tag.RowsAffected() == 1
		return err
	})
	if err == nil && hid {
		s.d.Audit.Record(ctx, accountID, audit.VideoHidden)
	}
	return err
}

// Unhide lifts a hide. Unhiding a video that is not hidden changes and
// records nothing.
func (s *Service) Unhide(ctx context.Context, accountID, minorID, videoID string) error {
	c, _, err := guardedChild(ctx, s.d.Pool, accountID, minorID)
	if err != nil {
		return err
	}
	if !validID(videoID) {
		return ErrNotFound
	}
	tag, err := s.d.Pool.Exec(ctx, `DELETE FROM video_hides WHERE minor_id = $1::uuid AND video_id = $2::uuid`, c.MinorID, videoID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 1 {
		s.d.Audit.Record(ctx, accountID, audit.VideoUnhidden)
	}
	return nil
}

// ReportReason is why a family reports a video.
type ReportReason string

const (
	ReportInadequado  ReportReason = "inadequado"
	ReportAssustador  ReportReason = "assustador"
	ReportPublicidade ReportReason = "publicidade"
	ReportOutro       ReportReason = "outro"
)

const maxNote = 500 // runes in a report note

func (r ReportReason) valid() bool {
	return r == ReportInadequado || r == ReportAssustador || r == ReportPublicidade || r == ReportOutro
}

// sinceReopen keeps, over video_reports r joined to videos v, the reports
// made after the video's latest reopen: earlier ones count for nothing.
const sinceReopen = `r.reported_at > coalesce(v.reopened_at, '-infinity'::timestamptz)`

// badNoteRune is a control character other than a newline or a tab:
// Postgres refuses NUL, and the rest has no place in a note.
func badNoteRune(r rune) bool { return unicode.IsControl(r) && r != '\n' && r != '\t' }

// reportsSinceReopen counts the video's reports since its latest reopen.
// One row per family (the primary key), so the rows are the distinct
// families. Report and publishing both count here, so they agree.
func reportsSinceReopen(ctx context.Context, q querier, videoID string) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*) FROM video_reports r JOIN videos v ON v.id = r.video_id
		WHERE r.video_id = $1::uuid AND `+sinceReopen, videoID).Scan(&n)
	return n, err
}

// ReportSummary is what the held queue shows of a video's reports since
// its latest reopen: counts by reason and the non-empty notes, oldest
// first, never who reported.
type ReportSummary struct {
	ByReason map[ReportReason]int
	Notes    []string
}

// Report records the caller's family's report of a video. It checks the
// rate limit first, then the reason and the note, then the caller's
// family and the video, so a flood is turned away before any lookup.
// created reports a new report (201) as against the family's earlier
// one, which stands. The
// video row lock comes first, so the reports of one video run one at a
// time: the count sees every earlier report, and two last reports hold
// once.
func (s *Service) Report(ctx context.Context, accountID, videoID string, reason ReportReason, note string) (bool, error) {
	if ok, wait := s.d.ReportLimiter.Allow(accountID); !ok {
		return false, &ThrottledError{RetryAfter: wait}
	}
	note = strings.TrimSpace(note)
	if !reason.valid() || utf8.RuneCountInString(note) > maxNote || strings.ContainsFunc(note, badNoteRune) {
		return false, ErrValidation
	}
	now := s.now()
	var created, held bool
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		familyID, err := familyOf(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(videoID) {
			return ErrNotFound
		}
		var st string
		err = tx.QueryRow(ctx, `SELECT state FROM videos WHERE id = $1::uuid FOR UPDATE`, videoID).Scan(&st)
		if errors.Is(err, pgx.ErrNoRows) || err == nil && State(st) == Removed {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO video_reports (video_id, family_id, account_id, reason, note, reported_at)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4, nullif($5::text, ''), $6) ON CONFLICT DO NOTHING`,
			videoID, familyID, accountID, string(reason), note, now)
		if err != nil {
			return err
		}
		if created = tag.RowsAffected() == 1; !created || State(st) != Approved {
			return nil
		}
		n, err := reportsSinceReopen(ctx, tx, videoID)
		if err != nil {
			return err
		}
		if n < s.d.ReportThreshold {
			return nil
		}
		held = true
		_, err = tx.Exec(ctx, `UPDATE videos SET state = 'held', held_reason = $3, updated_at = $2 WHERE id = $1::uuid`,
			videoID, now, HeldByReports)
		return err
	})
	if err != nil {
		return false, err
	}
	if created {
		s.d.Audit.Record(ctx, accountID, audit.VideoReported)
	}
	if held {
		s.d.Audit.Record(ctx, accountID, audit.VideoHeld)
	}
	return created, nil
}

// reportsOf summarises a video's reports since its latest reopen.
func reportsOf(ctx context.Context, q querier, videoID string) (ReportSummary, error) {
	rows, err := q.Query(ctx, `SELECT r.reason, coalesce(r.note, '') FROM video_reports r JOIN videos v ON v.id = r.video_id
		WHERE r.video_id = $1::uuid AND `+sinceReopen+` ORDER BY r.reported_at, r.family_id`, videoID)
	if err != nil {
		return ReportSummary{}, err
	}
	sum := ReportSummary{ByReason: map[ReportReason]int{}, Notes: []string{}}
	var reason, note string
	_, err = pgx.ForEachRow(rows, []any{&reason, &note}, func() error {
		sum.ByReason[ReportReason(reason)]++
		if note != "" {
			sum.Notes = append(sum.Notes, note)
		}
		return nil
	})
	return sum, err
}
