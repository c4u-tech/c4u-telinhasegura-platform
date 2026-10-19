package sweep_test

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/sweep"
)

func TestRunRunsAtStartAndOnEveryTickUntilCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	tick := make(chan time.Time)
	var logs bytes.Buffer
	var good atomic.Int32
	done := make(chan struct{})
	go func() {
		sweep.Run(ctx, tick, slog.New(slog.NewTextHandler(&logs, nil)),
			sweep.Job{Name: "broken", Run: func(context.Context) error { return errors.New("boom") }},
			sweep.Job{Name: "good", Run: func(context.Context) error { good.Add(1); return nil }})
		close(done)
	}()
	tick <- time.Now()
	tick <- time.Now()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not stop on cancel")
	}
	if n := good.Load(); n < 2 || n > 3 {
		t.Fatalf("the good job ran %d times", n)
	}
	if !strings.Contains(logs.String(), "broken") || !strings.Contains(logs.String(), "boom") {
		t.Fatalf("the failure was not logged: %s", logs.String())
	}
}

func TestRunSurvivesAPanickingJob(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	tick := make(chan time.Time)
	var logs bytes.Buffer
	var good atomic.Int32
	done := make(chan struct{})
	go func() {
		sweep.Run(ctx, tick, slog.New(slog.NewTextHandler(&logs, nil)),
			sweep.Job{Name: "bomb", Run: func(context.Context) error { panic("kaboom") }},
			sweep.Job{Name: "good", Run: func(context.Context) error { good.Add(1); return nil }})
		close(done)
	}()
	tick <- time.Now()
	// Wait until the good job has run at least twice (initial run plus second pass after tick).
	// Poll with a short sleep, bounded by a 5-second deadline.
	deadline := time.Now().Add(5 * time.Second)
	for good.Load() < 2 {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for good job to run twice; ran %d times", good.Load())
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not stop on cancel")
	}
	if good.Load() < 2 {
		t.Fatalf("the good job ran %d times", good.Load())
	}
	if !strings.Contains(logs.String(), "sweep: job panicked") || !strings.Contains(logs.String(), "kaboom") {
		t.Fatalf("the panic was not logged: %s", logs.String())
	}
}
