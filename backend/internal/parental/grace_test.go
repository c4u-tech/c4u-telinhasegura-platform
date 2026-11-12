package parental_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
)

// toPrevious moves every consent row of a profile to the previous text.
func (f *fixture) toPrevious(minorID string) {
	f.t.Helper()
	if _, err := f.pool.Exec(ctx, `UPDATE minor_consents SET policy_version = $2 WHERE minor_id = $1::uuid`,
		minorID, family.PreviousConsentPolicyVersion); err != nil {
		f.t.Fatal(err)
	}
}

// A child on the previous consent text keeps kid mode, the device picker
// and the child routes until the grace ends, and is paused after it.
func TestPreviousConsentKeepsTheChildGoingUntilTheGraceEnds(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	teo := f.minor(owner, "Teo")
	f.withPIN(owner)
	dev, err := f.svc.AuthenticateDevice(ctx, f.linked(owner, teo).Token)
	if err != nil {
		t.Fatal(err)
	}
	f.toPrevious(lia)
	f.now = graceEnd.Add(-time.Second)

	sess := f.session(owner)
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); err != nil {
		t.Fatalf("kid mode before: %v", err)
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, owner)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.RequireConsent(ctx, p); err != nil {
		t.Fatalf("child routes before: %v", err)
	}
	if pr, err := f.svc.Profile(ctx, p); err != nil || !pr.ConsentCurrent {
		t.Fatalf("profile before: %+v, %v", pr, err)
	}
	if list, err := f.svc.Profiles(ctx, dev, goodPIN); err != nil || !consentOf(list, lia) {
		t.Fatalf("picker before: %+v, %v", list, err)
	}
	if _, err := f.svc.SwitchProfile(ctx, dev, goodPIN, lia); err != nil {
		t.Fatalf("switch before: %v", err)
	}

	f.now = graceEnd
	if err := f.svc.RequireConsent(ctx, p); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("child routes after: %v", err)
	}
	if pr, err := f.svc.Profile(ctx, p); err != nil || pr.ConsentCurrent {
		t.Fatalf("profile after: %+v, %v", pr, err)
	}
	if list, err := f.svc.Profiles(ctx, dev, goodPIN); err != nil || consentOf(list, lia) {
		t.Fatalf("picker after: %+v, %v", list, err)
	}
	if _, err := f.svc.SwitchProfile(ctx, dev, goodPIN, lia); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("switch after: %v", err)
	}
	if err := f.svc.EnterKidMode(ctx, owner, f.session(owner), lia); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("kid mode after: %v", err)
	}
}

func consentOf(list []parental.Profile, minorID string) bool {
	for _, p := range list {
		if p.ID == minorID {
			return p.ConsentCurrent
		}
	}
	return false
}

// A family session asks for the current consent text even during the
// grace, so a child on the previous text cannot start one.
func TestConsentedChildNeedsTheCurrentConsentEvenDuringTheGrace(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.now = graceEnd.Add(-time.Second)
	if _, err := f.svc.ConsentedChild(ctx, owner, lia); err != nil {
		t.Fatalf("current: %v", err)
	}
	f.toPrevious(lia)
	if _, err := f.svc.ConsentedChild(ctx, owner, lia); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("previous: %v", err)
	}
}
