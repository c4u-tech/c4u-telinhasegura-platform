// Package ratelimit is an in-process, fixed-window limiter per key. One
// API instance is deployed today; a shared store is due when there are
// more (hosting trigger).
package ratelimit

import (
	"sync"
	"time"
)

type Limiter struct {
	limit   int
	window  time.Duration
	now     func() time.Time
	mu      sync.Mutex
	windows map[string]window
}

type window struct {
	start time.Time
	count int
}

func New(limit int, w time.Duration, now func() time.Time) *Limiter {
	return &Limiter{limit: limit, window: w, now: now, windows: map[string]window{}}
}

func (l *Limiter) Allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if len(l.windows) > 10_000 {
		l.sweep(now)
	}
	w := l.windows[key]
	if now.Sub(w.start) >= l.window {
		w = window{start: now}
	}
	if w.count >= l.limit {
		return false, w.start.Add(l.window).Sub(now)
	}
	w.count++
	l.windows[key] = w
	return true, 0
}

func (l *Limiter) sweep(now time.Time) {
	for k, w := range l.windows {
		if now.Sub(w.start) >= l.window {
			delete(l.windows, k)
		}
	}
}
