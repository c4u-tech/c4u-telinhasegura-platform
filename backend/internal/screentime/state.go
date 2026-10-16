package screentime

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// day is a child's row for one local date.
type day struct {
	Seconds          int
	OutsideSeconds   int
	ExtensionMinutes int
}

// inWindow says whether local, a clock in the family zone, falls in the
// window [start, end).
func inWindow(r Rules, local time.Time) bool {
	m := local.Hour()*60 + local.Minute()
	return m >= r.WindowStart && m < r.WindowEnd
}

// stateAt is the day state at local: the one definition every
// play, beat, extension and read uses. Outside the window only extension
// minutes may be spent. The day's total is clamped to
// MaxDailyMinutes, so rules saved after an extension cannot breach it.
func stateAt(r Rules, d day, local time.Time) Time {
	total := min(r.DailyMinutes+d.ExtensionMinutes, MaxDailyMinutes) * 60
	left := total - d.Seconds
	extLeft := max(d.ExtensionMinutes*60-d.OutsideSeconds, 0)
	if left <= 0 {
		return Time{State: TimeUp, Reason: ReasonDaily}
	}
	if !inWindow(r, local) {
		if extLeft == 0 {
			return Time{State: OutsideWindow, Reason: ReasonWindow}
		}
		return Time{State: OK, Remaining: seconds(min(left, extLeft))}
	}
	toEnd := r.WindowEnd*60 - (local.Hour()*3600 + local.Minute()*60 + local.Second())
	return Time{State: OK, Remaining: seconds(min(left, toEnd+extLeft))}
}

func seconds(n int) time.Duration { return time.Duration(n) * time.Second }

// readDay is the child's row for date (YYYY-MM-DD), zero when absent.
func readDay(ctx context.Context, q querier, minorID, date string) (day, error) {
	var d day
	err := q.QueryRow(ctx, `SELECT seconds, outside_seconds, extension_minutes FROM screentime_days
		WHERE minor_id = $1::uuid AND day = $2::date`, minorID, date).Scan(&d.Seconds, &d.OutsideSeconds, &d.ExtensionMinutes)
	if errors.Is(err, pgx.ErrNoRows) {
		return day{}, nil
	}
	return d, err
}

// dayOf is the clock in the family zone and the child's row for today.
func (s *Service) dayOf(ctx context.Context, q querier, m minor, r Rules) (time.Time, day, error) {
	loc, err := r.location()
	if err != nil {
		return time.Time{}, day{}, err
	}
	local := s.now().In(loc)
	d, err := readDay(ctx, q, m.ID, local.Format(time.DateOnly))
	return local, d, err
}

// Time is the child's day state now, for the catalogue.
func (s *Service) Time(ctx context.Context, c Child) (Time, error) {
	m, err := childMinor(ctx, s.d.Pool, c)
	if err != nil {
		return Time{}, err
	}
	return s.timeOf(ctx, s.d.Pool, m)
}

func (s *Service) timeOf(ctx context.Context, q querier, m minor) (Time, error) {
	r, err := rulesOf(ctx, q, m)
	if err != nil {
		return Time{}, err
	}
	local, d, err := s.dayOf(ctx, q, m, r)
	if err != nil {
		return Time{}, err
	}
	return stateAt(r, d, local), nil
}
