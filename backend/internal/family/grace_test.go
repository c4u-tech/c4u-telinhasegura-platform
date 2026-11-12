package family_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// toPrevious moves every consent row of a profile to the previous text.
func (f *fixture) toPrevious(minorID string) {
	f.t.Helper()
	if _, err := f.pool.Exec(ctx, `UPDATE minor_consents SET policy_version = $2 WHERE minor_id = $1::uuid`,
		minorID, family.PreviousConsentPolicyVersion); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) consentCurrent(accountID, minorID string) bool {
	f.t.Helper()
	fam, err := f.svc.Get(ctx, accountID)
	if err != nil {
		f.t.Fatal(err)
	}
	for _, m := range fam.Minors {
		if m.ID == minorID {
			return m.ConsentCurrent
		}
	}
	f.t.Fatalf("no minor %s", minorID)
	return false
}

func TestPreviousConsentCountsUntilTheGraceEnds(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	m, err := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion)
	if err != nil {
		t.Fatal(err)
	}
	f.toPrevious(m.ID)
	f.now = graceEnd.Add(-time.Second)
	if !f.consentCurrent(ana, m.ID) {
		t.Fatal("the previous consent does not count before the grace ends")
	}
	up, err := f.svc.UpdateMinor(ctx, ana, m.ID, family.MinorPatch{Nickname: ptr("Lua")})
	if err != nil || !up.ConsentCurrent {
		t.Fatalf("update before: %+v, %v", up, err)
	}
	f.now = graceEnd
	if f.consentCurrent(ana, m.ID) {
		t.Fatal("the previous consent still counts after the grace ends")
	}
	up, err = f.svc.UpdateMinor(ctx, ana, m.ID, family.MinorPatch{Nickname: ptr("Lia")})
	if err != nil || up.ConsentCurrent {
		t.Fatalf("update after: %+v, %v", up, err)
	}
}

func TestConsentingUnderThePreviousTextIsTakenBeforeTheGraceEnds(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.now = graceEnd.Add(-time.Second)
	m, err := f.svc.CreateMinor(ctx, ana, lia, family.PreviousConsentPolicyVersion)
	if err != nil {
		t.Fatal(err)
	}
	if !m.ConsentCurrent {
		t.Fatal("a profile created under the previous text is not current")
	}
	if n := f.count(currentConsents, m.ID, family.PreviousConsentPolicyVersion); n != 1 {
		t.Fatalf("%d consents stored as sent", n)
	}
	f.outdate(m.ID)
	if err := f.svc.GrantConsent(ctx, ana, m.ID, family.PreviousConsentPolicyVersion); err != nil {
		t.Fatal(err)
	}
	if n := f.count(currentConsents, m.ID, family.PreviousConsentPolicyVersion); n != 1 {
		t.Fatalf("%d grants stored as sent", n)
	}
}

func TestConsentingUnderThePreviousTextIsRefusedAfterTheGraceEnds(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	m, err := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion)
	if err != nil {
		t.Fatal(err)
	}
	f.outdate(m.ID)
	f.now = graceEnd
	if _, err := f.svc.CreateMinor(ctx, ana, lia, family.PreviousConsentPolicyVersion); !errors.Is(err, family.ErrPolicyOutdated) {
		t.Fatalf("create: %v", err)
	}
	if err := f.svc.GrantConsent(ctx, ana, m.ID, family.PreviousConsentPolicyVersion); !errors.Is(err, family.ErrPolicyOutdated) {
		t.Fatalf("grant: %v", err)
	}
}

func TestNoGraceRefusesThePreviousConsent(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.deps.GraceUntil = time.Time{}
	f.svc = family.NewService(f.deps)
	if _, err := f.svc.CreateMinor(ctx, ana, lia, family.PreviousConsentPolicyVersion); !errors.Is(err, family.ErrPolicyOutdated) {
		t.Fatalf("create: %v", err)
	}
}

func TestConsentVersionCarriesTheGrace(t *testing.T) {
	v := family.ConsentVersion(graceEnd)
	if v.Current != family.ConsentPolicyVersion || v.Previous != family.PreviousConsentPolicyVersion || !v.GraceUntil.Equal(graceEnd) {
		t.Fatalf("%+v", v)
	}
}
