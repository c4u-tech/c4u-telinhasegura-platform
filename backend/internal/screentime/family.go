package screentime

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

const (
	sessionLife      = 10 * time.Minute // a family session must be opened this soon
	sessionRetention = 24 * time.Hour   // a session row, used or not, is kept this long
	endMargin        = 60 * time.Second // a position this close to the end means the work was watched
)

// ErrNoFamilySession refuses the open of a family work without an unused,
// unexpired session for that child and video.
var ErrNoFamilySession = errors.New("screentime: no family session for this video")

// FamilySession is a started session: the open it allows starts the work
// at StartSeconds, where it last stopped.
type FamilySession struct {
	ID           string
	StartSeconds int
}

// StartFamilySession lets one of the account's children open videoID,
// a work the child may watch only with the family, once within ten
// minutes. The caller has checked the work and the family PIN.
//
// The optional extension is granted first, as the guardian's, and in the
// same transaction as the fit check: a work that still does not fit
// leaves no extension behind, and the time left it reports is the day's
// own. What must fit is what is left of the work past its resume point.
func (s *Service) StartFamilySession(ctx context.Context, accountID, minorID, videoID string, extendMinutes int) (FamilySession, error) {
	if extendMinutes != 0 && !ValidMinutes(extendMinutes) {
		return FamilySession{}, ErrValidation
	}
	m, err := guardedMinor(ctx, s.d.Pool, accountID, minorID)
	if err != nil {
		return FamilySession{}, err
	}
	if !validID(videoID) {
		return FamilySession{}, ErrNotFound
	}
	var out FamilySession
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		before, err := s.timeOf(ctx, tx, m)
		if err != nil {
			return err
		}
		t := before
		if extendMinutes != 0 {
			if t, err = s.extendTx(ctx, tx, m, extendMinutes, "guardian", accountID); err != nil {
				return err
			}
		}
		if t.State != OK {
			return &TimeUpError{Reason: t.Reason}
		}
		left, start, err := leftOf(ctx, tx, m.ID, videoID)
		if err != nil {
			return err
		}
		if !Fits(t, left) {
			return &NotFitError{Remaining: before.Remaining}
		}
		now := s.now()
		out.StartSeconds = start
		return tx.QueryRow(ctx, `INSERT INTO family_sessions (minor_id, video_id, account_id, created_at, expires_at)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5) RETURNING id::text`,
			m.ID, videoID, accountID, now, now.Add(sessionLife)).Scan(&out.ID)
	})
	if err != nil {
		return FamilySession{}, err
	}
	if extendMinutes != 0 {
		s.d.Audit.Record(ctx, accountID, audit.ScreenTimeExtended)
	}
	s.d.Audit.Record(ctx, accountID, audit.FamilySessionStarted)
	return out, nil
}

// positionOf is where the child last stopped the work, 0 when unknown.
func positionOf(ctx context.Context, q querier, minorID, videoID string) (int, error) {
	var pos int
	err := q.QueryRow(ctx, `SELECT position_seconds FROM play_positions WHERE minor_id = $1::uuid AND video_id = $2::uuid`,
		minorID, videoID).Scan(&pos)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return pos, err
}

// leftOf is what is left of the work for the child, and where it resumes.
func leftOf(ctx context.Context, q querier, minorID, videoID string) (time.Duration, int, error) {
	start, err := positionOf(ctx, q, minorID, videoID)
	if err != nil {
		return 0, 0, err
	}
	var duration int
	if err := q.QueryRow(ctx, `SELECT duration_seconds FROM videos WHERE id = $1::uuid`, videoID).Scan(&duration); err != nil {
		return 0, 0, err
	}
	return seconds(max(duration-start, 0)), start, nil
}

// useSession consumes the child's oldest unused, unexpired session for
// the video under its row lock, so two opens cannot both use it.
func (s *Service) useSession(ctx context.Context, tx pgx.Tx, minorID, videoID string) error {
	now := s.now()
	var id string
	err := tx.QueryRow(ctx, `SELECT id::text FROM family_sessions
		WHERE minor_id = $1::uuid AND video_id = $2::uuid AND used_at IS NULL AND expires_at > $3
		ORDER BY created_at LIMIT 1 FOR UPDATE`, minorID, videoID, now).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNoFamilySession
	}
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE family_sessions SET used_at = $2 WHERE id = $1::uuid`, id, now)
	return err
}

// keepPosition stores where a family work's play stands: a negative
// position is ignored, one past the length counts as the end, and one
// within a minute of the end clears the resume point.
func (s *Service) keepPosition(ctx context.Context, tx pgx.Tx, minorID, videoID string, duration, position int) error {
	if position < 0 {
		return nil
	}
	position = min(position, duration)
	if position >= duration-int(endMargin/time.Second) {
		_, err := tx.Exec(ctx, `DELETE FROM play_positions WHERE minor_id = $1::uuid AND video_id = $2::uuid`, minorID, videoID)
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO play_positions (minor_id, video_id, position_seconds, updated_at)
		VALUES ($1::uuid, $2::uuid, $3, $4)
		ON CONFLICT (minor_id, video_id) DO UPDATE SET position_seconds = EXCLUDED.position_seconds,
			updated_at = EXCLUDED.updated_at`, minorID, videoID, position, s.now())
	return err
}
