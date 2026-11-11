package screentime_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

// spent records seconds already watched today (2026-10-05) by the child.
func (f *fixture) spent(c screentime.Child, seconds int) {
	f.t.Helper()
	f.exec(`INSERT INTO screentime_days (minor_id, day, seconds) VALUES ($1::uuid, '2026-10-05', $2)
		ON CONFLICT (minor_id, day) DO UPDATE SET seconds = EXCLUDED.seconds`, c.MinorID, seconds)
}

func (f *fixture) start(owner string, c screentime.Child, videoID string, extend int) screentime.FamilySession {
	f.t.Helper()
	s, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, videoID, extend)
	if err != nil {
		f.t.Fatalf("start: %v", err)
	}
	return s
}

func (f *fixture) openFamily(c screentime.Child, videoID, continues string) screentime.Play {
	f.t.Helper()
	p, err := f.svc.Open(ctx, c, videoID, continues, true)
	if err != nil {
		f.t.Fatalf("open: %v", err)
	}
	return p
}

func (f *fixture) position(c screentime.Child, videoID string) int {
	f.t.Helper()
	return f.count(`SELECT coalesce(max(position_seconds), -1) FROM play_positions WHERE minor_id = $1::uuid AND video_id = $2::uuid`,
		c.MinorID, videoID)
}

func at(n int) *int { return &n }

// A 50-minute work with 40 minutes left does not fit; with 15 more
// minutes, granted first, it does, and the session waits ten minutes.
func TestStartFamilySessionFitsAfterTheExtension(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8") // 90 minutes a day
	v := f.video("dQw4w9WgXcQ", 50*60)
	f.spent(c, 50*60)

	var nf *screentime.NotFitError
	if _, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, v, 0); !errors.As(err, &nf) || nf.Remaining != 40*time.Minute {
		t.Fatalf("without the extension: %v", err)
	}
	if f.count(`SELECT count(*) FROM family_sessions`) != 0 {
		t.Fatal("a refused start stored a session")
	}
	s := f.start(owner, c, v, 15)
	if s.ID == "" || s.StartSeconds != 0 {
		t.Fatalf("session %+v", s)
	}
	if n := f.count(`SELECT count(*) FROM family_sessions WHERE id = $1::uuid AND minor_id = $2::uuid AND video_id = $3::uuid
		AND account_id = $4::uuid AND used_at IS NULL AND expires_at = $5`, s.ID, c.MinorID, v, owner, f.now.Add(10*time.Minute)); n != 1 {
		t.Fatal("the session row")
	}
	if f.count(`SELECT count(*) FROM screentime_extensions WHERE via = 'guardian' AND account_id = $1::uuid AND minutes = 15`, owner) != 1 {
		t.Fatal("the extension was not the guardian's")
	}
	if f.audited(audit.FamilySessionStarted) != 1 || f.audited(audit.ScreenTimeExtended) != 1 {
		t.Fatal("audit")
	}
}

// The extension and the fit commit together: a work that still does not
// fit leaves no extension behind, and the time left is the day's own.
func TestStartFamilySessionThatStillDoesNotFitKeepsNoExtension(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 120*60)
	f.spent(c, 50*60)
	var nf *screentime.NotFitError
	if _, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, v, 15); !errors.As(err, &nf) || nf.Remaining != 40*time.Minute {
		t.Fatalf("start: %v", err)
	}
	if f.count(`SELECT count(*) FROM screentime_extensions`) != 0 || f.count(`SELECT extension_minutes FROM screentime_days`) != 0 ||
		f.count(`SELECT count(*) FROM family_sessions`) != 0 {
		t.Fatal("a refused start left rows")
	}
	if f.audited(audit.ScreenTimeExtended) != 0 || f.audited(audit.FamilySessionStarted) != 0 {
		t.Fatal("a refused start was audited")
	}
}

func TestStartFamilySessionRefusals(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	_, stranger := f.family("bia@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)

	for name, ids := range map[string][2]string{
		"another family": {stranger, c.MinorID}, "malformed child": {owner, "abc"}, "malformed account": {"abc", c.MinorID},
	} {
		if _, err := f.svc.StartFamilySession(ctx, ids[0], ids[1], v, 0); !errors.Is(err, screentime.ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if _, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, v, 45); !errors.Is(err, screentime.ErrValidation) {
		t.Errorf("45 minutes: %v", err)
	}
	f.exec(`INSERT INTO screentime_rules (minor_id, daily_minutes, window_start, window_end, updated_at)
		VALUES ($1::uuid, 240, 480, 1170, $2)`, c.MinorID, f.now)
	if _, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, v, 15); !errors.Is(err, screentime.ErrOverCap) {
		t.Errorf("over the cap: %v", err)
	}
	f.spent(c, 240*60)
	var up *screentime.TimeUpError
	if _, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, v, 0); !errors.As(err, &up) || up.Reason != screentime.ReasonDaily {
		t.Errorf("time up: %v", err)
	}
	if f.count(`SELECT count(*) FROM family_sessions`) != 0 || f.count(`SELECT count(*) FROM screentime_extensions`) != 0 {
		t.Fatal("a refused start stored something")
	}
}

// A family work opens once on a session, within its ten minutes; a
// reopen of that play needs none.
func TestOpenAFamilyWorkNeedsASession(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)

	if _, err := f.svc.Open(ctx, c, v, "", true); !errors.Is(err, screentime.ErrNoFamilySession) {
		t.Fatalf("without a session: %v", err)
	}
	s := f.start(owner, c, v, 0)
	f.now = f.now.Add(9 * time.Minute)
	p := f.openFamily(c, v, "")
	if p.ID == "" || p.StartSeconds != 0 {
		t.Fatalf("play %+v", p)
	}
	if f.count(`SELECT count(*) FROM family_sessions WHERE id = $1::uuid AND used_at = $2`, s.ID, f.now) != 1 ||
		f.count(`SELECT count(*) FROM plays WHERE id = $1::uuid AND family`, p.ID) != 1 {
		t.Fatal("the session was not used, or the play is not marked")
	}
	// A second open is a new start, even right after the first one.
	if _, err := f.svc.Open(ctx, c, v, "", true); !errors.Is(err, screentime.ErrNoFamilySession) {
		t.Fatalf("second open: %v", err)
	}
	// A reopen of the play within half an hour needs no session.
	f.beat(c, p.ID, 0, true)
	f.now = f.now.Add(20 * time.Minute)
	if _, err := f.svc.Open(ctx, c, v, p.ID, true); err != nil {
		t.Fatalf("reopen: %v", err)
	}
	// Another child's play is no reopen.
	rui := f.minor(fam, "5-8")
	if _, err := f.svc.Open(ctx, rui, v, p.ID, true); !errors.Is(err, screentime.ErrNoFamilySession) {
		t.Fatalf("another child: %v", err)
	}
}

func TestASessionExpiresAfterTenMinutes(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)
	f.start(owner, c, v, 0)
	f.now = f.now.Add(10 * time.Minute)
	if _, err := f.svc.Open(ctx, c, v, "", true); !errors.Is(err, screentime.ErrNoFamilySession) {
		t.Fatalf("after ten minutes: %v", err)
	}
	// A session is bound to its video and child.
	other := f.video("aaaaaaaaaaa", 50*60)
	f.start(owner, c, other, 0)
	if _, err := f.svc.Open(ctx, c, v, "", true); !errors.Is(err, screentime.ErrNoFamilySession) {
		t.Fatalf("another video's session: %v", err)
	}
	if _, err := f.svc.Open(ctx, f.minor(fam, "5-8"), other, "", true); !errors.Is(err, screentime.ErrNoFamilySession) {
		t.Fatalf("another child's session: %v", err)
	}
}

// The day's time runs out between the start and the open: the open is
// refused for time and the session stays unused until it expires.
func TestTimeUpBeforeTheOpenKeepsTheSession(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)
	s := f.start(owner, c, v, 0)
	f.spent(c, 90*60)
	var up *screentime.TimeUpError
	if _, err := f.svc.Open(ctx, c, v, "", true); !errors.As(err, &up) || up.Reason != screentime.ReasonDaily {
		t.Fatalf("open: %v", err)
	}
	if f.count(`SELECT count(*) FROM family_sessions WHERE id = $1::uuid AND used_at IS NULL`, s.ID) != 1 {
		t.Fatal("a refused open used the session")
	}
}

func TestAnOpenThatDoesNotFitKeepsTheSession(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)
	s := f.start(owner, c, v, 0)
	f.spent(c, 60*60) // 30 minutes left
	var nf *screentime.NotFitError
	if _, err := f.svc.Open(ctx, c, v, "", true); !errors.As(err, &nf) || nf.Remaining != 30*time.Minute {
		t.Fatalf("open: %v", err)
	}
	if f.count(`SELECT count(*) FROM family_sessions WHERE id = $1::uuid AND used_at IS NULL`, s.ID) != 1 ||
		f.count(`SELECT count(*) FROM plays`) != 0 {
		t.Fatal("a refused open used the session or stored a play")
	}
}

// The position a family work's beats carry is where the next session
// starts, and what is left of the work is what must fit.
func TestAFamilyWorkResumesWhereItStopped(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)
	f.start(owner, c, v, 0)
	p := f.openFamily(c, v, "")
	for _, pos := range []int{600, 1200} {
		if _, err := f.svc.Beat(ctx, c, p.ID, true, at(pos)); err != nil {
			t.Fatal(err)
		}
		f.now = f.now.Add(30 * time.Second)
	}
	// A negative position is ignored, and does not fail the beat.
	if _, err := f.svc.Beat(ctx, c, p.ID, true, at(-5)); err != nil {
		t.Fatalf("negative: %v", err)
	}
	if got := f.position(c, v); got != 1200 {
		t.Fatalf("position %d", got)
	}
	// 70 minutes used: 20 left, and 50 − 20 = 30 minutes of the work do not
	// fit; 40 left do fit the 30 + the tolerance.
	f.spent(c, 70*60)
	var nf *screentime.NotFitError
	if _, err := f.svc.StartFamilySession(ctx, owner, c.MinorID, v, 0); !errors.As(err, &nf) {
		t.Fatalf("20 minutes left: %v", err)
	}
	f.spent(c, 60*60)
	s := f.start(owner, c, v, 0)
	if s.StartSeconds != 1200 {
		t.Fatalf("start_seconds %d", s.StartSeconds)
	}
	if p := f.openFamily(c, v, ""); p.StartSeconds != 1200 {
		t.Fatalf("open start_seconds %d", p.StartSeconds)
	}
}

func TestAPositionNearTheEndClearsTheResume(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 50*60)
	f.start(owner, c, v, 0)
	p := f.openFamily(c, v, "")
	f.svc.Beat(ctx, c, p.ID, true, at(50*60-61))
	if got := f.position(c, v); got != 50*60-61 {
		t.Fatalf("61 s before the end: %d", got)
	}
	f.now = f.now.Add(10 * time.Second)
	f.svc.Beat(ctx, c, p.ID, true, at(50*60-60))
	if got := f.position(c, v); got != -1 {
		t.Fatalf("60 s before the end: %d", got)
	}
	// Past the length, a position is clamped to it: the end, so cleared.
	f.now = f.now.Add(10 * time.Second)
	f.svc.Beat(ctx, c, p.ID, true, at(600))
	f.now = f.now.Add(10 * time.Second)
	if _, err := f.svc.Beat(ctx, c, p.ID, true, at(99*60)); err != nil {
		t.Fatalf("over the length: %v", err)
	}
	if got := f.position(c, v); got != -1 {
		t.Fatalf("over the length: %d", got)
	}
	if s := f.start(owner, c, v, 0); s.StartSeconds != 0 {
		t.Fatalf("start_seconds %d", s.StartSeconds)
	}
}

func TestASoloVideoKeepsNoPosition(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	v := f.video("dQw4w9WgXcQ", 20*60)
	p := f.open(c, v)
	if p.StartSeconds != 0 {
		t.Fatalf("start_seconds %d", p.StartSeconds)
	}
	if _, err := f.svc.Beat(ctx, c, p.ID, true, at(300)); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM play_positions`) != 0 {
		t.Fatal("a solo video's position was stored")
	}
}
