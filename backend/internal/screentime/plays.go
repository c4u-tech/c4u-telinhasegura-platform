package screentime

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Play is an opened play and the day state it opened in.
type Play struct {
	ID   string
	Time Time
}

// Open opens a play when the day allows it. The caller has
// checked that the child may see videoID (curation.Play). A play opens
// paused: time counts from the first beat that says it plays. A video
// that does not fit the time left is refused, unless the open resumes this
// child's recent play of the same video: resuming it is not a new start.
func (s *Service) Open(ctx context.Context, c Child, videoID, continues string) (Play, error) {
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
	resumed, err := s.resumes(ctx, m.ID, videoID, continues)
	if err != nil {
		return Play{}, err
	}
	if !resumed {
		var duration int
		if err := s.d.Pool.QueryRow(ctx, `SELECT duration_seconds FROM videos WHERE id = $1::uuid`, videoID).Scan(&duration); err != nil {
			return Play{}, err
		}
		if !Fits(t, time.Duration(duration)*time.Second) {
			return Play{}, &NotFitError{Remaining: t.Remaining}
		}
	}
	var device any
	if validID(c.DeviceID) {
		device = c.DeviceID
	}
	var id string
	err = s.d.Pool.QueryRow(ctx, `INSERT INTO plays (minor_id, video_id, device_id, started_at, last_beat_at, playing)
		VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $4, false) RETURNING id::text`, m.ID, videoID, device, s.now()).Scan(&id)
	if err != nil {
		return Play{}, err
	}
	return Play{ID: id, Time: t}, nil
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
// is spent first.
func (s *Service) Beat(ctx context.Context, c Child, playID string, playing bool) (Time, error) {
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
		var was bool
		var credited, limit int
		err := tx.QueryRow(ctx, `SELECT p.last_beat_at, p.playing, p.seconds, v.duration_seconds + $3
			FROM plays p JOIN videos v ON v.id = p.video_id
			WHERE p.id = $1::uuid AND p.minor_id = $2::uuid FOR UPDATE OF p`,
			playID, m.ID, int(overrun/time.Second)).Scan(&last, &was, &credited, &limit)
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
