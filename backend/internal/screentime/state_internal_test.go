package screentime

import (
	"testing"
	"time"
)

func TestStateAt(t *testing.T) {
	r := Rules{DailyMinutes: 60, WindowStart: 8 * 60, WindowEnd: 19*60 + 30, TimeZone: DefaultZone}
	sp, _ := time.LoadLocation(DefaultZone)
	at := func(h, m int) time.Time { return time.Date(2026, 10, 5, h, m, 0, 0, sp) }
	for _, c := range []struct {
		name  string
		d     day
		local time.Time
		want  Time
	}{
		{"fresh morning", day{}, at(9, 0), Time{State: OK, Remaining: 60 * time.Minute}},
		{"window start is inside", day{}, at(8, 0), Time{State: OK, Remaining: 60 * time.Minute}},
		{"one second before start", day{}, at(7, 59), Time{State: OutsideWindow, Reason: ReasonWindow}},
		{"window end is outside", day{}, at(19, 30), Time{State: OutsideWindow, Reason: ReasonWindow}},
		{"near the end, the window caps", day{}, at(19, 10), Time{State: OK, Remaining: 20 * time.Minute}},
		{"quota spent", day{Seconds: 3600}, at(10, 0), Time{State: TimeUp, Reason: ReasonDaily}},
		{"quota overrun", day{Seconds: 3700}, at(10, 0), Time{State: TimeUp, Reason: ReasonDaily}},
		{"extension inside the window", day{Seconds: 3600, ExtensionMinutes: 15}, at(10, 0),
			Time{State: OK, Remaining: 15 * time.Minute}},
		{"extension outside the window", day{Seconds: 600, ExtensionMinutes: 15}, at(20, 0),
			Time{State: OK, Remaining: 15 * time.Minute}},
		{"outside, the extension spent", day{Seconds: 1500, OutsideSeconds: 900, ExtensionMinutes: 15}, at(20, 30),
			Time{State: OutsideWindow, Reason: ReasonWindow}},
		{"outside, the total spent first", day{Seconds: 4500, OutsideSeconds: 300, ExtensionMinutes: 15}, at(20, 30),
			Time{State: TimeUp, Reason: ReasonDaily}},
		{"near the end, an extension carries past it", day{ExtensionMinutes: 15}, at(19, 20),
			Time{State: OK, Remaining: 25 * time.Minute}},
	} {
		if got := stateAt(r, c.d, c.local); got != c.want {
			t.Errorf("%s: %+v, want %+v", c.name, got, c.want)
		}
	}
}

func TestStateAtClampsTheDayToTheCap(t *testing.T) { // rules saved after an extension
	r := Rules{DailyMinutes: 240, WindowStart: 8 * 60, WindowEnd: 19*60 + 30, TimeZone: DefaultZone}
	sp, _ := time.LoadLocation(DefaultZone)
	at := time.Date(2026, 10, 5, 9, 0, 0, 0, sp)
	if got, want := stateAt(r, day{Seconds: 14400, ExtensionMinutes: 60}, at), (Time{State: TimeUp, Reason: ReasonDaily}); got != want {
		t.Errorf("spent: %+v, want %+v", got, want)
	}
	if got, want := stateAt(r, day{ExtensionMinutes: 60}, at), (Time{State: OK, Remaining: 240 * time.Minute}); got != want {
		t.Errorf("fresh: %+v, want %+v", got, want)
	}
}
