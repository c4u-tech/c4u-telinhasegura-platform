package ratelimit_test

import (
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
)

func pacific(t *testing.T) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation("America/Los_Angeles")
	if err != nil {
		t.Fatal(err)
	}
	return loc
}

func TestDailyAllowsLimitThenRefusesUntilMidnight(t *testing.T) {
	loc := pacific(t)
	now := time.Date(2026, 11, 3, 10, 0, 0, 0, loc)
	d := ratelimit.NewDaily(3, loc, func() time.Time { return now })

	for i := range 3 {
		if ok, _ := d.Take(); !ok {
			t.Fatalf("call %d refused", i+1)
		}
	}
	ok, wait := d.Take()
	if ok || wait != 14*time.Hour {
		t.Fatalf("fourth call = %v, %v; want refused, 14h", ok, wait)
	}
	now = time.Date(2026, 11, 4, 0, 0, 0, 0, loc)
	if ok, _ := d.Take(); !ok {
		t.Fatal("budget did not reset at midnight")
	}
}

func TestDailyExhaustBlocksTheRestOfTheDay(t *testing.T) {
	loc := pacific(t)
	now := time.Date(2026, 11, 3, 23, 30, 0, 0, loc)
	d := ratelimit.NewDaily(95, loc, func() time.Time { return now })

	if ok, _ := d.Take(); !ok {
		t.Fatal("first call refused")
	}
	if wait := d.Exhaust(); wait != 30*time.Minute {
		t.Fatalf("Exhaust wait = %v, want 30m", wait)
	}
	if ok, _ := d.Take(); ok {
		t.Fatal("call allowed after Exhaust")
	}
	now = time.Date(2026, 11, 4, 0, 0, 0, 0, loc)
	if ok, _ := d.Take(); !ok {
		t.Fatal("budget did not reset at midnight")
	}
}

func TestDailyResetsAtLocalMidnightAcrossDST(t *testing.T) {
	loc := pacific(t)
	now := time.Date(2026, 10, 31, 23, 0, 0, 0, loc)
	d := ratelimit.NewDaily(1, loc, func() time.Time { return now })

	if ok, _ := d.Take(); !ok {
		t.Fatal("first call refused")
	}
	if ok, wait := d.Take(); ok || wait != time.Hour {
		t.Fatalf("second call = %v, %v; want refused, 1h", ok, wait)
	}
	now = time.Date(2026, 11, 1, 0, 0, 0, 0, loc)
	if ok, _ := d.Take(); !ok {
		t.Fatal("budget did not reset at midnight")
	}
	// 1 November is 25 hours long: the clocks go back at 02:00.
	now = time.Date(2026, 11, 1, 23, 0, 0, 0, loc)
	if ok, wait := d.Take(); ok || wait != time.Hour {
		t.Fatalf("late call = %v, %v; want refused, 1h", ok, wait)
	}
}
