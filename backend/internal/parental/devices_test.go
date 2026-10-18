package parental_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestDevicesAndUnlink(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	guardian := f.member(owner, "bia@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	first := f.linked(owner, lia)
	f.now = f.now.Add(time.Minute)
	second := f.linked(owner, lia)

	list, err := f.svc.Devices(ctx, guardian)
	if err != nil || len(list) != 2 {
		t.Fatalf("list %+v %v", list, err)
	}
	if list[0].Label != "Tablet" || list[0].MinorID != lia || !list[0].LinkedAt.Before(list[1].LinkedAt) {
		t.Fatalf("order or fields %+v", list)
	}
	if err := f.svc.Unlink(ctx, guardian, list[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.AuthenticateDevice(ctx, first.Token); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("unlinked token: %v", err)
	}
	if _, err := f.svc.AuthenticateDevice(ctx, second.Token); err != nil {
		t.Fatalf("the other device: %v", err)
	}
	other := f.owner("teo@example.com")
	for _, id := range []string{list[0].ID, "abc", "00000000-0000-0000-0000-000000000000"} {
		if err := f.svc.Unlink(ctx, guardian, id); !errors.Is(err, parental.ErrNotFound) {
			t.Fatalf("unlink %q: %v", id, err)
		}
	}
	if err := f.svc.Unlink(ctx, other, list[1].ID); !errors.Is(err, parental.ErrNotFound) {
		t.Fatalf("another family's device: %v", err)
	}
	if !f.audit.Has(guardian, audit.DeviceUnlinked) {
		t.Fatal("no device_unlinked audit")
	}
	if _, err := f.svc.Devices(ctx, f.account("lia@example.com")); !errors.Is(err, parental.ErrNoFamily) {
		t.Fatalf("no family: %v", err)
	}
}

func TestDevicesHideIdleExpired(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	f.linked(owner, lia)
	f.now = f.now.Add(181 * 24 * time.Hour)
	if list, err := f.svc.Devices(ctx, owner); err != nil || len(list) != 0 {
		t.Fatalf("list %+v %v", list, err)
	}
}

func TestProfilesAndSwitch(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	teo := f.minor(owner, "Teo")
	foreign := f.minor(f.owner("bia@example.com"), "Davi")
	f.withPIN(owner)
	dev, err := f.svc.AuthenticateDevice(ctx, f.linked(owner, lia).Token)
	if err != nil {
		t.Fatal(err)
	}

	if _, err := f.svc.Profiles(ctx, dev, "1357"); !errors.Is(err, parental.ErrInvalidPIN) {
		t.Fatalf("wrong PIN: %v", err)
	}
	list, err := f.svc.Profiles(ctx, dev, goodPIN)
	if err != nil || len(list) != 2 || list[0].ID != lia || list[1].ID != teo {
		t.Fatalf("profiles %+v %v", list, err)
	}
	if _, err := f.svc.SwitchProfile(ctx, dev, goodPIN, foreign); !errors.Is(err, parental.ErrNotFound) {
		t.Fatalf("foreign minor: %v", err)
	}
	if n := f.count(`SELECT failed_attempts FROM family_pins`); n != 0 {
		t.Fatal("a foreign minor counted as a PIN failure")
	}
	p, err := f.svc.SwitchProfile(ctx, dev, goodPIN, teo)
	if err != nil || p.ID != teo || p.Nickname != "Teo" {
		t.Fatalf("switch %+v %v", p, err)
	}
	if n := f.count(`SELECT count(*) FROM devices WHERE minor_id = $1::uuid`, teo); n != 1 {
		t.Fatal("the device was not re-bound")
	}
	if !f.audit.Has("", audit.DeviceProfileChanged) {
		t.Fatal("no device_profile_changed audit")
	}

	sess := f.session(owner)
	if err := f.svc.EnterKidMode(ctx, owner, sess, lia); err != nil {
		t.Fatal(err)
	}
	locked, _ := f.svc.SessionPrincipal(ctx, sess, owner)
	if _, err := f.svc.Profiles(ctx, locked, goodPIN); !errors.Is(err, parental.ErrNotFound) {
		t.Fatalf("profiles from a locked session: %v", err)
	}
	if _, err := f.svc.SwitchProfile(ctx, locked, goodPIN, teo); !errors.Is(err, parental.ErrNotFound) {
		t.Fatalf("switch from a locked session: %v", err)
	}
}

// A child deleted while a device switches to them: the switch read the
// child before the deletion committed, so its foreign-key check fails
// (23503), which answers ErrNotFound, not a 500.
func TestSwitchToAChildDeletedMeanwhile(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	teo := f.minor(owner, "Teo")
	f.withPIN(owner)
	dev, err := f.svc.AuthenticateDevice(ctx, f.linked(owner, lia).Token)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `DELETE FROM minors WHERE id = $1::uuid`, teo); err != nil {
		t.Fatal(err)
	}
	var deleter int
	if err := tx.QueryRow(ctx, `SELECT pg_backend_pid()`).Scan(&deleter); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := f.svc.SwitchProfile(ctx, dev, goodPIN, teo)
		done <- err
	}()
	// Wait until the switch blocks on the deletion's lock, then commit.
	for deadline := time.Now().Add(5 * time.Second); f.count(`SELECT count(*) FROM pg_stat_activity
		WHERE $1::int = ANY (pg_blocking_pids(pid))`, deleter) == 0; {
		if time.Now().After(deadline) {
			t.Fatal("the switch never waited on the deletion")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, parental.ErrNotFound) {
		t.Fatalf("switch to a child deleted meanwhile: %v", err)
	}
}

func TestDeviceCascades(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	guardian := f.member(owner, "bia@example.com")
	lia := f.minor(owner, "Lia")
	teo := f.minor(owner, "Teo")
	f.withPIN(owner)

	byGuardian := f.linked(guardian, teo)
	liaDevice := f.linked(owner, lia)
	liaCode, _ := f.svc.CreateLinkCode(ctx, owner, lia)

	if err := f.fam.RemoveGuardian(ctx, owner, guardian); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.AuthenticateDevice(ctx, byGuardian.Token); err != nil {
		t.Fatalf("a device outlives the guardian who linked it: %v", err)
	}
	if err := f.fam.DeleteMinor(ctx, owner, lia); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.AuthenticateDevice(ctx, liaDevice.Token); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("the deleted child's device: %v", err)
	}
	if _, err := f.svc.Redeem(ctx, liaCode.Code, "Tablet"); !errors.Is(err, parental.ErrInvalidCode) {
		t.Fatalf("the deleted child's code: %v", err)
	}
	if err := f.fam.Delete(ctx, owner); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"devices", "link_codes", "family_pins"} {
		if n := f.count(`SELECT count(*) FROM ` + table); n != 0 {
			t.Fatalf("%s kept %d rows after the family's deletion", table, n)
		}
	}
}

func TestProfilesReportConsent(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	teo := f.minor(owner, "Teo")
	f.withPIN(owner)
	dev, err := f.svc.AuthenticateDevice(ctx, f.linked(owner, lia).Token)
	if err != nil {
		t.Fatal(err)
	}
	f.pause(teo)

	list, err := f.svc.Profiles(ctx, dev, goodPIN)
	if err != nil || len(list) != 2 {
		t.Fatalf("profiles %+v %v", list, err)
	}
	if list[0].ID != lia || !list[0].ConsentCurrent || list[1].ID != teo || list[1].ConsentCurrent {
		t.Fatalf("consent per profile %+v", list)
	}
}

// Switching to a paused child is refused after the PIN, and the device
// stays on the child it was on.
func TestSwitchToAPausedChild(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	teo := f.minor(owner, "Teo")
	f.withPIN(owner)
	dev, err := f.svc.AuthenticateDevice(ctx, f.linked(owner, lia).Token)
	if err != nil {
		t.Fatal(err)
	}
	f.pause(teo)

	if _, err := f.svc.SwitchProfile(ctx, dev, "1357", teo); !errors.Is(err, parental.ErrInvalidPIN) {
		t.Fatalf("wrong PIN first: %v", err)
	}
	if _, err := f.svc.SwitchProfile(ctx, dev, goodPIN, teo); !errors.Is(err, parental.ErrConsentRequired) {
		t.Fatalf("paused child: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM devices WHERE id = $1::uuid AND minor_id = $2::uuid`, dev.DeviceID, lia); n != 1 {
		t.Fatal("the device left its previous child")
	}
	if f.audit.Has("", audit.DeviceProfileChanged) {
		t.Fatal("a refused switch was audited")
	}
	p, err := f.svc.SwitchProfile(ctx, dev, goodPIN, lia)
	if err != nil || p.ID != lia || !p.ConsentCurrent {
		t.Fatalf("switch to an authorized child %+v %v", p, err)
	}
}
