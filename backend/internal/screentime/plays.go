package screentime

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Play is an opened play and the day state it opened in. StartSeconds is
// where a family work resumes; 0 for any other video.
type Play struct {
	ID           string
	Time         Time
	StartSeconds int
}

// Open opens a play when the day allows it. The caller has checked that
// the child may see videoID: alone (curation.Play), or with the family
// (curation.FamilyWork), which family says. A play opens paused: time
// counts from the first beat that says it plays. A video that does not
// fit the time left is refused, unless the open resumes this child's
// recent play of the same video: resuming it is not a new start.
//
// A new start of a family work uses up an unused, unexpired session for
// the child and video, in the same transaction as the play, so a refused
// open leaves the session for a later one. Its fit counts only what is
// left past the resume point.
func (s *Service) Open(ctx context.Context, c Child, videoID, continues string, family bool) (Play, error) {
	if ok, wait := s.d.PlayLimiter.Allow(c.MinorID); !ok {
		return Play{}, &ThrottledError{RetryAfter: wait}
	}
	m, err := childMinor(ctx, s.d.Pool, c)
	if err != nil {
		return Play{}, err
	}
	t, err := s.timeOf(ctx, s.d.Pool, m)
	if err != nil {
		return Play{}, err
	}
	if t.State != OK {
		return Play{}, &TimeUpError{Reason: t.Reason}
	}
	// An app that knows family works names the play it carries on; without
	// one, the open of a family work is a new start.
	resumed := false
	if !family || continues != "" {
		if resumed, err = s.resumes(ctx, m.ID, videoID, continues); err != nil {
			return Play{}, err
		}
	}
	var device any
	if validID(c.DeviceID) {
		device = c.DeviceID
	}
	p := Play{Time: t}
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		var left time.Duration
		if family {
			if left, p.StartSeconds, err = leftOf(ctx, tx, m.ID, videoID); err != nil {
				return err
			}
			if !resumed {
				if err := s.useSession(ctx, tx, m.ID, videoID); err != nil {
					return err
				}
			}
		} else {
			var duration int
			if err := tx.QueryRow(ctx, `SELECT duration_seconds FROM videos WHERE id = $1::uuid`, videoID).Scan(&duration); err != nil {
				return err
			}
			left = seconds(duration)
		}
		if !resumed && !Fits(t, left) {
			return &NotFitError{Remaining: t.Remaining}
		}
		return tx.QueryRow(ctx, `INSERT INTO plays (minor_id, video_id, device_id, started_at, last_beat_at, playing, family)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $4, false, $5) RETURNING id::text`,
			m.ID, videoID, device, s.now(), family).Scan(&p.ID)
	})
	if err != nil {
		return Play{}, err
	}
	return p, nil
}

// resumes tells whether the open carries on a play of this child and
// video that beat recently enough to count as the same viewing. A named
// continues must be that play, or the open is a new start. An app that
// predates the field reopens without it, so without one any such play the
// child has not watched to its end counts.
func (s *Service) resumes(ctx context.Context, minorID, videoID, continues string) (bool, error) {
	since := s.now().Add(-continueWithin)
	var ok bool
	var err error
	switch {
	case continues == "":
		err = s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM plays p JOIN videos v ON v.id = p.video_id
			WHERE p.minor_id = $1::uuid AND p.video_id = $2::uuid AND p.last_beat_at >= $3
			AND p.seconds < v.duration_seconds)`, minorID, videoID, since).Scan(&ok)
	case validID(continues):
		err = s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM plays WHERE id = $1::uuid AND minor_id = $2::uuid
			AND video_id = $3::uuid AND last_beat_at >= $4)`, continues, minorID, videoID, since).Scan(&ok)
	}
	return ok, err
}

// Beat credits an open play: the wall time since the last beat,
// at most creditCap, or nothing after a pause; never past the video's
// length plus overrun. The credit goes to the beat's local date, and to
// outside_seconds when the beat is outside the window. The child's budget
// is spent first. position, when given, is where the playback stands; it
// is kept only for a play opened on a family session.
func (s *Service) Beat(ctx context.Context, c Child, playID string, playing bool, position *int) (Time, error) {
	if ok, wait := s.d.BeatLimiter.Allow(c.MinorID); !ok {
		return Time{}, &ThrottledError{RetryAfter: wait}
	}
	m, err := childMinor(ctx, s.d.Pool, c)
	if err != nil {
		return Time{}, err
	}
	if !validID(playID) {
		return Time{}, ErrNotFound
	}
	var t Time
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		var last time.Time
		var was, family bool
		var credited, duration int
		var videoID string
		err := tx.QueryRow(ctx, `SELECT p.last_beat_at, p.playing, p.seconds, v.duration_seconds, p.family, p.video_id::text
			FROM plays p JOIN videos v ON v.id = p.video_id
			WHERE p.id = $1::uuid AND p.minor_id = $2::uuid FOR UPDATE OF p`,
			playID, m.ID).Scan(&last, &was, &credited, &duration, &family, &videoID)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		now := s.now()
		gap := now.Sub(last)
		if gap >= closeAfter {
			return ErrPlayClosed
		}
		credit := 0
		if was {
			credit = int(min(gap, creditCap).Round(time.Second) / time.Second)
		}
		limit := duration + int(overrun/time.Second)
		credit = min(credit, max(limit-credited, 0))
		r, err := rulesOf(ctx, tx, m)
		if err != nil {
			return err
		}
		loc, err := r.location()
		if err != nil {
			return err
		}
		local := now.In(loc)
		outside := 0
		if !inWindow(r, local) {
			outside = credit
		}
		if _, err := tx.Exec(ctx, `UPDATE plays SET last_beat_at = $2, playing = $3, seconds = seconds + $4
			WHERE id = $1::uuid`, playID, now, playing, credit); err != nil {
			return err
		}
		if family && position != nil {
			if err := s.keepPosition(ctx, tx, m.ID, videoID, duration, *position); err != nil {
				return err
			}
		}
		var d day
		if err := tx.QueryRow(ctx, `INSERT INTO screentime_days (minor_id, day, seconds, outside_seconds)
			VALUES ($1::uuid, $2::date, $3, $4)
			ON CONFLICT (minor_id, day) DO UPDATE SET seconds = screentime_days.seconds + EXCLUDED.seconds,
				outside_seconds = screentime_days.outside_seconds + EXCLUDED.outside_seconds
			RETURNING seconds, outside_seconds, extension_minutes`,
			m.ID, local.Format(time.DateOnly), credit, outside).Scan(&d.Seconds, &d.OutsideSeconds, &d.ExtensionMinutes); err != nil {
			return err
		}
		t = stateAt(r, d, local)
		return nil
	})
	return t, err
}
