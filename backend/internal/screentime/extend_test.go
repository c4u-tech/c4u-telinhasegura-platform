package screentime_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

func TestGuardianExtendOpensTheWindow(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	f.at(20, 0)
	tm, err := f.svc.GuardianExtend(ctx, owner, c.MinorID, 15)
	if err != nil {
		t.Fatal(err)
	}
	if tm.State != screentime.OK || tm.Remaining != 15*time.Minute {
		t.Fatalf("%+v", tm)
	}
	if n := f.count(`SELECT count(*) FROM screentime_extensions WHERE via = 'guardian' AND account_id = $1::uuid AND minutes = 15`,
		owner); n != 1 {
		t.Fatal("not recorded")
	}
	if f.audited(audit.ScreenTimeExtended) != 1 {
		t.Fatal("not audited")
	}
	p := f.open(c, f.video("dQw4w9WgXcQ", 3600))
	f.beat(c, p.ID, 0, true)
	for range 30 {
		f.beat(c, p.ID, 30*time.Second, true)
	}
	if tm, _ := f.svc.Time(ctx, c); tm.State != screentime.OutsideWindow {
		t.Fatalf("after 15 outside minutes: %+v", tm)
	}
}

func TestPINExtendOnALinkedDevice(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	if _, err := f.svc.Extend(ctx, c, 30, ""); err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM screentime_extensions WHERE via = 'pin' AND account_id IS NULL AND minutes = 30`); n != 1 {
		t.Fatal("not recorded")
	}
}

func TestExtensionRefusals(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	_, stranger := f.family("bia@example.com")
	c := f.minor(fam, "5-8")
	for _, m := range []int{0, 10, 45, 120} {
		if _, err := f.svc.GuardianExtend(ctx, owner, c.MinorID, m); !errors.Is(err, screentime.ErrValidation) {
			t.Errorf("%d minutes: %v", m, err)
		}
	}
	if _, err := f.svc.GuardianExtend(ctx, stranger, c.MinorID, 15); !errors.Is(err, screentime.ErrNotFound) {
		t.Fatalf("stranger: %v", err)
	}
	f.svc.SaveRules(ctx, owner, c.MinorID, screentime.RulesInput{DailyMinutes: 240, WindowStart: "08:00",
		WindowEnd: "19:30", TimeZone: "America/Sao_Paulo"})
	if _, err := f.svc.GuardianExtend(ctx, owner, c.MinorID, 15); !errors.Is(err, screentime.ErrOverCap) {
		t.Fatalf("over the cap: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM screentime_extensions`); n != 0 {
		t.Fatalf("recorded %d", n)
	}
	f.svc.SaveRules(ctx, owner, c.MinorID, screentime.RulesInput{DailyMinutes: 180, WindowStart: "08:00",
		WindowEnd: "19:30", TimeZone: "America/Sao_Paulo"})
	if _, err := f.svc.GuardianExtend(ctx, owner, c.MinorID, 60); err != nil {
		t.Fatalf("to exactly 240: %v", err)
	}
	if _, err := f.svc.GuardianExtend(ctx, owner, c.MinorID, 15); !errors.Is(err, screentime.ErrOverCap) {
		t.Fatalf("past 240: %v", err)
	}
}

func TestAnExtensionCountsOnlyToday(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	f.svc.GuardianExtend(ctx, owner, c.MinorID, 60)
	f.now = f.now.Add(24 * time.Hour)
	_, today, _ := f.svc.Rules(ctx, owner, c.MinorID)
	if today.ExtensionMinutes != 0 || today.Time.Remaining != 90*time.Minute {
		t.Fatalf("tomorrow %+v", today)
	}
}
