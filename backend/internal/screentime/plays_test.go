package screentime_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

// beat advances the clock by d, then beats.
func (f *fixture) beat(c screentime.Child, playID string, d time.Duration, playing bool) (screentime.Time, error) {
	f.t.Helper()
	f.now = f.now.Add(d)
	return f.svc.Beat(ctx, c, playID, playing)
}

func (f *fixture) open(c screentime.Child, videoID string) screentime.Play {
	f.t.Helper()
	p, err := f.svc.Open(ctx, c, videoID)
	if err != nil {
		f.t.Fatalf("open: %v", err)
	}
	return p
}

func (f *fixture) used(c screentime.Child) (seconds, outside int) {
	f.t.Helper()
	_ = f.pool.QueryRow(ctx, `SELECT coalesce(sum(seconds), 0), coalesce(sum(outside_seconds), 0) FROM screentime_days
		WHERE minor_id = $1::uuid`, c.MinorID).Scan(&seconds, &outside)
	return seconds, outside
}

func TestOpenAndBeat(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 300)

	p := f.open(c, v)
	if p.ID == "" || p.Time.State != screentime.OK || p.Time.Remaining != 90*time.Minute {
		t.Fatalf("play %+v", p)
	}
	// The first beat says it plays: the time before it is not credited.
	if _, err := f.beat(c, p.ID, 5*time.Second, true); err != nil {
		t.Fatal(err)
	}
	tm, err := f.beat(c, p.ID, 30*time.Second, true)
	if err != nil {
		t.Fatal(err)
	}
	if s, _ := f.used(c); s != 30 || tm.Remaining != 90*time.Minute-30*time.Second {
		t.Fatalf("used %d, %+v", s, tm)
	}
	// A pause beat credits the interval before it; nothing after it.
	f.beat(c, p.ID, 10*time.Second, false)
	f.beat(c, p.ID, 20*time.Second, true)
	if s, _ := f.used(c); s != 40 {
		t.Fatalf("after the pause %d", s)
	}
	if n := f.count(`SELECT seconds FROM plays WHERE id = $1::uuid`, p.ID); n != 40 {
		t.Fatalf("the play holds %d", n)
	}
}

func TestBeatAfterAPauseLongerThanTheCloseIsClosed(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	p := f.open(c, f.video("dQw4w9WgXcQ", 300))
	f.beat(c, p.ID, 0, true)
	if _, err := f.beat(c, p.ID, 44*time.Second, true); err != nil {
		t.Fatalf("44 s: %v", err)
	}
	if _, err := f.beat(c, p.ID, 45*time.Second, true); !errors.Is(err, screentime.ErrPlayClosed) {
		t.Fatalf("45 s: %v", err)
	}
	if s, _ := f.used(c); s != 44 {
		t.Fatalf("a closed play credited: %d", s)
	}
}

func TestBeatOnAnotherChildsOrAMalformedPlay(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia, rui := f.minor(fam, "5-8"), f.minor(fam, "5-8")
	p := f.open(lia, f.video("dQw4w9WgXcQ", 300))
	for _, id := range []string{p.ID, "abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.Beat(ctx, rui, id, true); !errors.Is(err, screentime.ErrNotFound) {
			t.Errorf("%s: %v", id, err)
		}
	}
}

func TestTimeUpRefusesAPlayButTheOpenOneFinishes(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	f.svc.SaveRules(ctx, owner, c.MinorID, screentime.RulesInput{DailyMinutes: 15, WindowStart: "08:00",
		WindowEnd: "19:30", TimeZone: "America/Sao_Paulo"})
	v := f.video("dQw4w9WgXcQ", 20*60) // a 20-minute video
	p := f.open(c, v)
	f.beat(c, p.ID, 0, true)
	var tm screentime.Time
	for range 40 { // 20 minutes of beats
		tm, _ = f.beat(c, p.ID, 30*time.Second, true)
	}
	if tm.State != screentime.TimeUp || tm.Reason != screentime.ReasonDaily {
		t.Fatalf("state %+v", tm)
	}
	if s, _ := f.used(c); s != 1200 {
		t.Fatalf("the open play stopped being credited: %d", s)
	}
	// Past the video's length plus a minute, nothing more counts.
	for range 6 {
		f.beat(c, p.ID, 30*time.Second, true)
	}
	if s, _ := f.used(c); s != 1260 {
		t.Fatalf("overrun %d", s)
	}
	var up *screentime.TimeUpError
	if _, err := f.svc.Open(ctx, c, v); !errors.As(err, &up) || up.Reason != screentime.ReasonDaily {
		t.Fatalf("open after time up: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM plays`); n != 1 {
		t.Fatalf("%d plays", n)
	}
}

func TestOutsideTheWindowRefusesAPlay(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	f.at(20, 0)
	var up *screentime.TimeUpError
	if _, err := f.svc.Open(ctx, c, f.video("dQw4w9WgXcQ", 300)); !errors.As(err, &up) || up.Reason != screentime.ReasonWindow {
		t.Fatalf("%v", err)
	}
}

func TestTwoDevicesAddToOneDay(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 300)
	a, b := f.open(c, v), f.open(c, v)
	f.beat(c, a.ID, 0, true)
	f.beat(c, b.ID, 0, true)
	f.beat(c, a.ID, 30*time.Second, true)
	f.beat(c, b.ID, 0, true)
	if s, _ := f.used(c); s != 60 {
		t.Fatalf("used %d", s)
	}
}

func TestBeatCreditsTheLocalDay(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "9-12")
	// Manaus is UTC−4. The widest window, so the play opens late.
	f.svc.SaveRules(ctx, owner, c.MinorID, screentime.RulesInput{DailyMinutes: 120, WindowStart: "00:00",
		WindowEnd: "23:59", TimeZone: "America/Manaus"})
	f.now = time.Date(2026, 10, 6, 3, 58, 50, 0, time.UTC) // 23:58:50 on the 5th in Manaus
	p := f.open(c, f.video("dQw4w9WgXcQ", 600))
	f.beat(c, p.ID, 0, true)
	f.beat(c, p.ID, 30*time.Second, true) // 23:59:20 on the 5th
	f.beat(c, p.ID, 40*time.Second, true) // 00:00:00 on the 6th
	if n := f.count(`SELECT seconds FROM screentime_days WHERE minor_id = $1::uuid AND day = '2026-10-05'`, c.MinorID); n != 30 {
		t.Fatalf("the 5th holds %d", n)
	}
	if n := f.count(`SELECT seconds FROM screentime_days WHERE minor_id = $1::uuid AND day = '2026-10-06'`, c.MinorID); n != 40 {
		t.Fatalf("the 6th holds %d", n)
	}
}

func TestLoweredRulesStopNewPlaysButNotTheOpenOne(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 3600)
	p := f.open(c, v)
	f.beat(c, p.ID, 0, true)
	for range 40 {
		f.beat(c, p.ID, 30*time.Second, true)
	}
	f.svc.SaveRules(ctx, owner, c.MinorID, screentime.RulesInput{DailyMinutes: 15, WindowStart: "08:00",
		WindowEnd: "19:30", TimeZone: "America/Sao_Paulo"})
	if tm, _ := f.svc.Time(ctx, c); tm.State != screentime.TimeUp {
		t.Fatalf("time %+v", tm)
	}
	if _, err := f.beat(c, p.ID, 30*time.Second, true); err != nil {
		t.Fatalf("the open play: %v", err)
	}
	var up *screentime.TimeUpError
	if _, err := f.svc.Open(ctx, c, v); !errors.As(err, &up) {
		t.Fatalf("open: %v", err)
	}
}

func TestBeatLimit(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	p := f.open(c, f.video("dQw4w9WgXcQ", 300))
	for range 20 {
		f.svc.Beat(ctx, c, p.ID, true)
	}
	var th *screentime.ThrottledError
	if _, err := f.svc.Beat(ctx, c, p.ID, true); !errors.As(err, &th) || th.RetryAfter <= 0 {
		t.Fatalf("21st beat: %v", err)
	}
}

func TestOpenLimit(t *testing.T) { // 30 opens per child per minute
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 300)
	for range 30 {
		f.open(c, v)
	}
	var th *screentime.ThrottledError
	if _, err := f.svc.Open(ctx, c, v); !errors.As(err, &th) || th.RetryAfter <= 0 {
		t.Fatalf("31st open: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM plays`); n != 30 {
		t.Fatalf("%d plays", n)
	}
}

func TestOutsideCreditGoesToOutsideSeconds(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	f.at(19, 29)
	p := f.open(c, f.video("dQw4w9WgXcQ", 300))
	f.beat(c, p.ID, 0, true)
	f.beat(c, p.ID, 30*time.Second, true) // 19:29:30, inside
	f.beat(c, p.ID, 40*time.Second, true) // 19:30:10, outside
	if s, out := f.used(c); s != 70 || out != 40 {
		t.Fatalf("used %d, outside %d", s, out)
	}
}
