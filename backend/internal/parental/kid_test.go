package parental_test

import (
	"errors"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestEnterKidModeAndUnlock(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	guardian := f.member(owner, "bia@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	sess := f.session(guardian)

	if err := f.svc.EnterKidMode(ctx, guardian, sess, lia); err != nil {
		t.Fatal(err)
	}
	if m, locked, err := f.svc.Lock(ctx, sess); err != nil || !locked || m != lia {
		t.Fatalf("Lock = %q %v %v", m, locked, err)
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, guardian)
	if err != nil || p.MinorID != lia || p.FamilyID != f.familyID(owner) || p.SessionID != sess || p.DeviceID != "" {
		t.Fatalf("principal %+v %v", p, err)
	}
	if pr, err := f.svc.Profile(ctx, p); err != nil || pr.ID != lia || pr.Nickname != "Lia" || pr.Avatar != "fox" || pr.AgeBand != "5-8" {
		t.Fatalf("profile %+v %v", pr, err)
	}
	if err := f.svc.Unlock(ctx, p, "1357"); !errors.Is(err, parental.ErrInvalidPIN) {
		t.Fatalf("wrong PIN: %v", err)
	}
	if _, locked, _ := f.svc.Lock(ctx, sess); !locked {
		t.Fatal("a wrong PIN unlocked")
	}
	if err := f.svc.Unlock(ctx, p, goodPIN); err != nil {
		t.Fatal(err)
	}
	if _, locked, _ := f.svc.Lock(ctx, sess); locked {
		t.Fatal("still locked")
	}
	if _, err := f.svc.SessionPrincipal(ctx, sess, guardian); !errors.Is(err, parental.ErrNotChild) {
		t.Fatalf("unlocked session as a child: %v", err)
	}
	if !f.audit.Has(guardian, audit.KidModeEntered) || !f.audit.Has(guardian, audit.KidModeExited) {
		t.Fatal("kid mode audit missing")
	}
}

func TestEnterKidModeErrors(t *testing.T) {
	f := newFixture(t)
	loner := f.account("lia@example.com")
	if err := f.svc.EnterKidMode(ctx, loner, f.session(loner), "abc"); !errors.Is(err, parental.ErrNoFamily) {
		t.Fatalf("no family: %v", err)
	}
	owner := f.owner("ana@example.com")
	sess := f.session(owner)
	lia := f.minor(owner, "Lia")
	other := f.owner("bia@example.com")
	foreign := f.minor(other, "Teo")
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000", foreign} {
		if err := f.svc.EnterKidMode(ctx, owner, sess, id); !errors.Is(err, parental.ErrNotFound) {
			t.Fatalf("minor %q: %v", id, err)
		}
	}
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); !errors.Is(err, parental.ErrPINNotSet) {
		t.Fatalf("no PIN: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM session_kid_locks`); n != 0 {
		t.Fatalf("%d locks", n)
	}
}

func TestUnlockIsForLockedSessionsOnly(t *testing.T) {
	f := newFixture(t)
	if err := f.svc.Unlock(ctx, parental.Principal{DeviceID: "d", FamilyID: "f", MinorID: "m"}, goodPIN); !errors.Is(err, parental.ErrNotFound) {
		t.Fatal(err)
	}
}

func TestLockSurvivesTheChildsDeletion(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	sess := f.session(owner)
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); err != nil {
		t.Fatal(err)
	}
	if err := f.fam.DeleteMinor(ctx, owner, lia); err != nil {
		t.Fatal(err)
	}
	if m, locked, err := f.svc.Lock(ctx, sess); err != nil || !locked || m != "" {
		t.Fatalf("Lock = %q %v %v", m, locked, err)
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, owner)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Profile(ctx, p); !errors.Is(err, parental.ErrProfileGone) {
		t.Fatalf("profile: %v", err)
	}
	if err := f.svc.Unlock(ctx, p, goodPIN); err != nil {
		t.Fatalf("unlock without a profile: %v", err)
	}
}

func TestUnlockAfterLeavingTheFamily(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	guardian := f.member(owner, "bia@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	sess, token := f.sessionToken(guardian)
	if err := f.svc.EnterKidMode(ctx, guardian, sess, lia); err != nil {
		t.Fatal(err)
	}
	if err := f.fam.RemoveGuardian(ctx, owner, guardian); err != nil {
		t.Fatal(err)
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, guardian)
	if err != nil || p.FamilyID != "" {
		t.Fatalf("principal %+v %v", p, err)
	}
	if _, err := f.svc.Profile(ctx, p); !errors.Is(err, parental.ErrProfileGone) {
		t.Fatalf("profile of a former family: %v", err)
	}
	if err := f.svc.Unlock(ctx, p, ""); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("no family PIN to give: %v", err)
	}
	f.assertEnded(sess, token)
	if n := f.count(`SELECT count(*) FROM session_kid_locks`); n != 0 {
		t.Fatalf("%d locks left", n)
	}
	if !f.audit.Has(guardian, audit.SessionRevoked) || f.audit.Has(guardian, audit.KidModeExited) {
		t.Fatalf("audit %+v", f.audit.Entries)
	}
}

func TestFamilyDeletionKeepsTheLock(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	sess, token := f.sessionToken(owner)
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); err != nil {
		t.Fatal(err)
	}
	if err := f.fam.Delete(ctx, owner); err != nil {
		t.Fatal(err)
	}
	if m, locked, _ := f.svc.Lock(ctx, sess); !locked || m != "" {
		t.Fatalf("Lock = %q %v", m, locked)
	}
	if n := f.count(`SELECT count(*) FROM family_pins`); n != 0 {
		t.Fatal("the PIN outlived the family")
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, owner)
	if err != nil || p.FamilyID != "" {
		t.Fatalf("principal %+v %v", p, err)
	}
	if err := f.svc.Unlock(ctx, p, "0000"); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("unlock with no family: %v", err)
	}
	f.assertEnded(sess, token)
	if _, locked, _ := f.svc.Lock(ctx, sess); locked {
		t.Fatal("the lock outlived the session")
	}
}

func TestDoubleUnlockAuditsOnce(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	sess := f.session(owner)
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); err != nil {
		t.Fatal(err)
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, owner)
	if err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if err := f.svc.Unlock(ctx, p, goodPIN); err != nil {
			t.Fatal(err)
		}
	}
	if n := f.audited(owner, audit.KidModeExited); n != 1 {
		t.Fatalf("kid_mode_exited recorded %d times", n)
	}
}

// A child whose consent is on an older policy version is paused: the
// guardian cannot hand the session over until they authorize again.
func TestEnterKidModeRefusesAPausedChild(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	f.pause(lia)
	sess := f.session(owner)

	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("paused child: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM session_kid_locks`); n != 0 {
		t.Fatalf("%d locks", n)
	}
	if f.audited(owner, audit.KidModeEntered) != 0 {
		t.Fatal("a refused hand-over was audited")
	}
}

// A withdrawn consent pauses the child as an outdated one does.
func TestEnterKidModeRefusesAWithdrawnConsent(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	if _, err := f.pool.Exec(ctx, `UPDATE minor_consents SET withdrawn_at = $2, withdrawn_by = granted_by WHERE minor_id = $1::uuid`,
		lia, f.now); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.EnterKidMode(ctx, owner, f.session(owner), lia); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("withdrawn consent: %v", err)
	}
}

func TestRequireConsent(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	sess := f.session(owner)
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); err != nil {
		t.Fatal(err)
	}
	p, err := f.svc.SessionPrincipal(ctx, sess, owner)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.RequireConsent(ctx, p); err != nil {
		t.Fatalf("current consent: %v", err)
	}
	f.pause(lia)
	if err := f.svc.RequireConsent(ctx, p); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("paused child: %v", err)
	}
	// A lock whose child was deleted has no consent to check; the route
	// answers profile_gone instead.
	if err := f.svc.RequireConsent(ctx, parental.Principal{SessionID: sess, AccountID: owner, FamilyID: p.FamilyID}); err != nil {
		t.Fatalf("no child: %v", err)
	}
}
