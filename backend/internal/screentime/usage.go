package screentime

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// DayUsage is the seconds a child watched on one local date.
type DayUsage struct {
	Date    string // YYYY-MM-DD
	Seconds int
}

// Usage is the child's last seven local days, oldest first, today last,
// with 0 for a day without use.
func (s *Service) Usage(ctx context.Context, accountID, minorID string) ([]DayUsage, error) {
	m, err := guardedMinor(ctx, s.d.Pool, accountID, minorID)
	if err != nil {
		return nil, err
	}
	r, err := rulesOf(ctx, s.d.Pool, m)
	if err != nil {
		return nil, err
	}
	loc, err := r.location()
	if err != nil {
		return nil, err
	}
	today := s.now().In(loc)
	dates := make([]string, 7)
	for i := range dates {
		dates[i] = time.Date(today.Year(), today.Month(), today.Day()-6+i, 12, 0, 0, 0, loc).Format(time.DateOnly)
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT day::text, seconds FROM screentime_days
		WHERE minor_id = $1::uuid AND day BETWEEN $2::date AND $3::date`, m.ID, dates[0], dates[6])
	if err != nil {
		return nil, err
	}
	byDate := map[string]int{}
	var date string
	var secs int
	if _, err := pgx.ForEachRow(rows, []any{&date, &secs}, func() error {
		byDate[date] = secs
		return nil
	}); err != nil {
		return nil, err
	}
	out := make([]DayUsage, 7)
	for i, d := range dates {
		out[i] = DayUsage{Date: d, Seconds: byDate[d]}
	}
	return out, nil
}

// Sweep applies retention: plays after 30 days, day rows and
// extensions after 90. The sweep runs it every SWEEP_INTERVAL; it is
// idempotent, so replicas may each run it.
func (s *Service) Sweep(ctx context.Context) error {
	now := s.now()
	if _, err := s.d.Pool.Exec(ctx, `DELETE FROM plays WHERE started_at < $1`, now.Add(-playRetention)); err != nil {
		return err
	}
	cutoff := now.Add(-dayRetention).Format(time.DateOnly)
	if _, err := s.d.Pool.Exec(ctx, `DELETE FROM screentime_days WHERE day < $1::date`, cutoff); err != nil {
		return err
	}
	_, err := s.d.Pool.Exec(ctx, `DELETE FROM screentime_extensions WHERE day < $1::date`, cutoff)
	return err
}
