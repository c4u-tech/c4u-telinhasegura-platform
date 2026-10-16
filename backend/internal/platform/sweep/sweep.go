// Package sweep runs the API's periodic jobs inside its process: the
// screen-time retention and the YouTube data refresh. Jobs are idempotent, so every replica may run
// them.
package sweep

import (
	"context"
	"log/slog"
	"time"
)

// Job is one named periodic task. A job that returns an error or panics
// is logged and the sweep goes on.
type Job struct {
	Name string
	Run  func(context.Context) error
}

// Run runs every job once at start and again on each tick, in order,
// until ctx is done. A failing job is logged and never stops the others.
func Run(ctx context.Context, tick <-chan time.Time, log *slog.Logger, jobs ...Job) {
	for {
		for _, j := range jobs {
			if ctx.Err() != nil {
				return
			}
			if err := runJob(ctx, j, log); err != nil {
				log.Error("sweep: job failed", "job", j.Name, "err", err)
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-tick:
		}
	}
}

// runJob runs j, recovering a panic so one bad job cannot take the API
// down (it would crash-loop every replica, the sweep runs at start).
func runJob(ctx context.Context, j Job, log *slog.Logger) (err error) {
	defer func() {
		if p := recover(); p != nil {
			log.Error("sweep: job panicked", "job", j.Name, "panic", p)
			err = nil
		}
	}()
	return j.Run(ctx)
}
