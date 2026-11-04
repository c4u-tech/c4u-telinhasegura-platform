package ratelimit

import (
	"sync"
	"time"
)

// Daily is a call budget that resets at midnight in a given time zone, for
// upstream quotas that renew on a provider's local day rather than on a
// rolling window.
type Daily struct {
	limit     int
	loc       *time.Location
	now       func() time.Time
	mu        sync.Mutex
	day       time.Time // midnight, in loc, that starts the counted day
	count     int
	exhausted bool
}

func NewDaily(limit int, loc *time.Location, now func() time.Time) *Daily {
	return &Daily{limit: limit, loc: loc, now: now}
}

// Take spends one call of today's budget. When none is left it refuses and
// reports the time until the next midnight.
func (d *Daily) Take() (bool, time.Duration) {
	d.mu.Lock()
	defer d.mu.Unlock()
	now := d.roll()
	if d.exhausted || d.count >= d.limit {
		return false, d.day.AddDate(0, 0, 1).Sub(now)
	}
	d.count++
	return true, 0
}

// Exhaust refuses every Take until the next midnight, for when the upstream
// says its own quota is spent, and returns that wait.
func (d *Daily) Exhaust() time.Duration {
	d.mu.Lock()
	defer d.mu.Unlock()
	now := d.roll()
	d.exhausted = true
	return d.day.AddDate(0, 0, 1).Sub(now)
}

// roll starts a fresh day when the local date has changed and returns the
// current time in the budget's zone. The caller holds the lock.
func (d *Daily) roll() time.Time {
	now := d.now().In(d.loc)
	y, m, day := now.Date()
	start := time.Date(y, m, day, 0, 0, 0, 0, d.loc)
	if !start.Equal(d.day) {
		d.day = start
		d.count = 0
		d.exhausted = false
	}
	return now
}
