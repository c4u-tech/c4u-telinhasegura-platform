package screentime_test

import (
	"errors"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

func TestDefaultsFollowTheBand(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	for band, minutes := range map[string]int{"ate-4": 60, "5-8": 90, "9-12": 90} {
		c := f.minor(fam, band)
		r, today, err := f.svc.Rules(ctx, owner, c.MinorID)
		if err != nil {
			t.Fatal(err)
		}
		want := screentime.Rules{DailyMinutes: minutes, WindowStart: 480, WindowEnd: 1170,
			TimeZone: "America/Sao_Paulo", IsDefault: true}
		if r != want {
			t.Errorf("%s: %+v", band, r)
		}
		if today.UsedSeconds != 0 || today.Time.State != screentime.OK {
			t.Errorf("%s today: %+v", band, today)
		}
	}
}

func TestSaveRules(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	in := screentime.RulesInput{DailyMinutes: 45, WindowStart: "07:15", WindowEnd: "18:00", TimeZone: "America/Manaus"}
	r, _, err := f.svc.SaveRules(ctx, owner, c.MinorID, in)
	if err != nil {
		t.Fatal(err)
	}
	want := screentime.Rules{DailyMinutes: 45, WindowStart: 435, WindowEnd: 1080, TimeZone: "America/Manaus"}
	if r != want {
		t.Fatalf("saved %+v", r)
	}
	if f.audited(audit.ScreenTimeRulesChanged) != 1 {
		t.Fatal("not audited")
	}
	// The zone is set on the first save only.
	in.TimeZone = "Europe/Lisbon"
	if r, _, _ = f.svc.SaveRules(ctx, owner, c.MinorID, in); r.TimeZone != "America/Manaus" {
		t.Fatalf("zone changed to %s", r.TimeZone)
	}
	if screentime.FormatClock(r.WindowStart) != "07:15" || screentime.FormatClock(r.WindowEnd) != "18:00" {
		t.Fatal("FormatClock")
	}
}

func TestSaveRulesRefusesBadInput(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	good := screentime.RulesInput{DailyMinutes: 60, WindowStart: "08:00", WindowEnd: "19:30", TimeZone: "America/Sao_Paulo"}
	for name, change := range map[string]func(*screentime.RulesInput){
		"14 minutes":   func(in *screentime.RulesInput) { in.DailyMinutes = 14 },
		"241 minutes":  func(in *screentime.RulesInput) { in.DailyMinutes = 241 },
		"bad start":    func(in *screentime.RulesInput) { in.WindowStart = "8:00" },
		"24:00 end":    func(in *screentime.RulesInput) { in.WindowEnd = "24:00" },
		"empty window": func(in *screentime.RulesInput) { in.WindowEnd = "08:00" },
		"inverted":     func(in *screentime.RulesInput) { in.WindowStart, in.WindowEnd = "20:00", "07:00" },
		"no zone":      func(in *screentime.RulesInput) { in.TimeZone = "" },
		"Local":        func(in *screentime.RulesInput) { in.TimeZone = "Local" },
		"traversal":    func(in *screentime.RulesInput) { in.TimeZone = "../etc/passwd" },
		"unknown zone": func(in *screentime.RulesInput) { in.TimeZone = "Mars/Olympus" },
	} {
		in := good
		change(&in)
		if _, _, err := f.svc.SaveRules(ctx, owner, c.MinorID, in); !errors.Is(err, screentime.ErrValidation) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM screentime_rules`) + f.count(`SELECT count(*) FROM screentime_families`); n != 0 {
		t.Fatalf("stored %d rows", n)
	}
}

func TestRulesOfAnotherFamilysChild(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	_, stranger := f.family("bia@example.com")
	c := f.minor(fam, "5-8")
	good := screentime.RulesInput{DailyMinutes: 60, WindowStart: "08:00", WindowEnd: "19:30", TimeZone: "America/Sao_Paulo"}
	if _, _, err := f.svc.Rules(ctx, stranger, c.MinorID); !errors.Is(err, screentime.ErrNotFound) {
		t.Fatalf("rules: %v", err)
	}
	if _, _, err := f.svc.SaveRules(ctx, stranger, c.MinorID, good); !errors.Is(err, screentime.ErrNotFound) {
		t.Fatalf("save: %v", err)
	}
	if _, _, err := f.svc.Rules(ctx, stranger, "abc"); !errors.Is(err, screentime.ErrNotFound) {
		t.Fatalf("malformed: %v", err)
	}
}

func TestZoneAndTimeOfAGoneChild(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	f.exec(`DELETE FROM minors WHERE id = $1::uuid`, c.MinorID)
	if _, err := f.svc.Zone(ctx, c); !errors.Is(err, screentime.ErrProfileGone) {
		t.Fatalf("zone: %v", err)
	}
	if _, err := f.svc.Time(ctx, screentime.Child{}); !errors.Is(err, screentime.ErrProfileGone) {
		t.Fatalf("time: %v", err)
	}
}

func TestSaveRulesAcceptsUTC(t *testing.T) { // a device that reports UTC can save
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	in := screentime.RulesInput{DailyMinutes: 60, WindowStart: "08:00", WindowEnd: "19:30", TimeZone: "UTC"}
	r, _, err := f.svc.SaveRules(ctx, owner, c.MinorID, in)
	if err != nil || r.TimeZone != "UTC" {
		t.Fatalf("%+v %v", r, err)
	}
}

func TestGuardianZone(t *testing.T) {
	f := newFixture(t)
	fam, owner := f.family("ana@example.com")
	c := f.minor(fam, "5-8")
	if loc, err := f.svc.GuardianZone(ctx, owner, c.MinorID); err != nil || loc.String() != screentime.DefaultZone {
		t.Fatalf("no zone saved: %v %v", loc, err)
	}
	f.exec(`INSERT INTO screentime_families (family_id, time_zone, set_at) VALUES ($1::uuid, 'America/Manaus', $2)`, fam, f.now)
	if loc, err := f.svc.GuardianZone(ctx, owner, c.MinorID); err != nil || loc.String() != "America/Manaus" {
		t.Fatalf("the family's zone: %v %v", loc, err)
	}
	_, other := f.family("bia@example.com")
	for name, args := range map[string][2]string{"another family": {other, c.MinorID}, "malformed": {owner, "abc"}} {
		if _, err := f.svc.GuardianZone(ctx, args[0], args[1]); !errors.Is(err, screentime.ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
}
