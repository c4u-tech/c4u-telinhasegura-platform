package ratelimit_test

import (
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
)

func TestLimiterAllowsUpToLimitPerWindowPerKey(t *testing.T) {
	now := time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC)
	l := ratelimit.New(30, time.Minute, func() time.Time { return now })

	for i := range 30 {
		if ok, _ := l.Allow("1.2.3.4"); !ok {
			t.Fatalf("request %d refused", i+1)
		}
	}
	now = now.Add(20 * time.Second)
	ok, wait := l.Allow("1.2.3.4")
	if ok || wait != 40*time.Second {
		t.Fatalf("31st: ok=%v wait=%v, want refused with 40s", ok, wait)
	}
	if ok, _ := l.Allow("5.6.7.8"); !ok {
		t.Fatal("another key shares the budget")
	}
	now = now.Add(40 * time.Second)
	if ok, _ := l.Allow("1.2.3.4"); !ok {
		t.Fatal("new window still refused")
	}
}
