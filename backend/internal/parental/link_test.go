package parental_test

import (
	"bytes"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

func TestRedeem(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *parental.Deps) { d.Rand = bytes.NewReader([]byte{0, 1, 2, 3, 4, 5, 6, 7}) })
	owner := f.owner("ana@example.com")
	guardian := f.member(owner, "bia@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)

	lc, err := f.svc.CreateLinkCode(ctx, guardian, lia)
	if err != nil {
		t.Fatal(err)
	}
	if lc.Code != "0123-4567" || lc.MinorID != lia || !lc.ExpiresAt.Equal(f.now.Add(10*time.Minute)) {
		t.Fatalf("code %+v", lc)
	}
	if n := f.count(`SELECT count(*) FROM link_codes WHERE code_hash = $1`, secret.Hash("01234567")); n != 1 {
		t.Fatal("the code is not stored as the hash of its normal form")
	}
	out, err := f.svc.Redeem(ctx, "o123 4567", "  Tablet da Lia ")
	if err != nil {
		t.Fatal(err)
	}
	if out.Token == "" || out.Profile.ID != lia || out.Profile.Nickname != "Lia" {
		t.Fatalf("redeemed %+v", out)
	}
	if n := f.count(`SELECT count(*) FROM devices WHERE label = 'Tablet da Lia' AND token_hash = $1`, secret.Hash(out.Token)); n != 1 {
		t.Fatal("no device row holding the token's hash")
	}
	p, err := f.svc.AuthenticateDevice(ctx, out.Token)
	if err != nil || p.MinorID != lia || p.FamilyID != f.familyID(owner) || p.DeviceID == "" || p.SessionID != "" {
		t.Fatalf("principal %+v %v", p, err)
	}
	if !f.audit.Has(guardian, audit.LinkCodeCreated) || !f.audit.Has(guardian, audit.DeviceLinked) {
		t.Fatal("link audit missing") // device_linked is under the code's creator
	}
}

func TestCreateLinkCodeErrors(t *testing.T) {
	f := newFixture(t)
	loner := f.account("lia@example.com")
	if _, err := f.svc.CreateLinkCode(ctx, loner, "abc"); !errors.Is(err, parental.ErrNoFamily) {
		t.Fatalf("no family: %v", err)
	}
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	foreign := f.minor(f.owner("bia@example.com"), "Teo")
	if _, err := f.svc.CreateLinkCode(ctx, owner, lia); !errors.Is(err, parental.ErrPINNotSet) {
		t.Fatalf("no PIN: %v", err)
	}
	f.withPIN(owner)
	for _, id := range []string{"abc", foreign} {
		if _, err := f.svc.CreateLinkCode(ctx, owner, id); !errors.Is(err, parental.ErrNotFound) {
			t.Fatalf("minor %q: %v", id, err)
		}
	}
	for i := range 5 {
		if _, err := f.svc.CreateLinkCode(ctx, owner, lia); err != nil {
			t.Fatalf("code %d: %v", i+1, err)
		}
	}
	if _, err := f.svc.CreateLinkCode(ctx, owner, lia); !errors.Is(err, parental.ErrLimitReached) {
		t.Fatalf("6th live code: %v", err)
	}
	f.now = f.now.Add(10 * time.Minute)
	if _, err := f.svc.CreateLinkCode(ctx, owner, lia); err != nil {
		t.Fatalf("expired codes still counted: %v", err)
	}
}

func TestCreateLinkCodeRateLimit(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *parental.Deps) { d.CodeLimiter = ratelimit.New(2, time.Hour, d.Now) })
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	for range 2 {
		if _, err := f.svc.CreateLinkCode(ctx, owner, lia); err != nil {
			t.Fatal(err)
		}
	}
	if d := retryAfter(t, func() error { _, err := f.svc.CreateLinkCode(ctx, owner, lia); return err }()); d <= 0 {
		t.Fatalf("retry after %v", d)
	}
}

func TestRedeemRefusals(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)

	if _, err := f.svc.Redeem(ctx, "ZZZZ-ZZZZ", "Tablet"); !errors.Is(err, parental.ErrInvalidCode) {
		t.Fatalf("unknown: %v", err)
	}
	lc, _ := f.svc.CreateLinkCode(ctx, owner, lia)
	if _, err := f.svc.Redeem(ctx, lc.Code, "Tab\nlet"); !errors.Is(err, parental.ErrValidation) {
		t.Fatalf("bad label: %v", err)
	}
	if _, err := f.svc.Redeem(ctx, lc.Code, "Tablet"); err != nil {
		t.Fatalf("a refused label spent the code: %v", err)
	}
	if _, err := f.svc.Redeem(ctx, lc.Code, "Tablet"); !errors.Is(err, parental.ErrInvalidCode) {
		t.Fatalf("used: %v", err)
	}
	old, _ := f.svc.CreateLinkCode(ctx, owner, lia)
	f.now = f.now.Add(10*time.Minute + time.Second)
	if _, err := f.svc.Redeem(ctx, old.Code, "Tablet"); !errors.Is(err, parental.ErrInvalidCode) {
		t.Fatalf("expired: %v", err)
	}

	for range 9 { // 1 linked above + 9 = 10 devices
		f.linked(owner, lia)
	}
	last, _ := f.svc.CreateLinkCode(ctx, owner, lia)
	if _, err := f.svc.Redeem(ctx, last.Code, "Tablet"); !errors.Is(err, parental.ErrLimitReached) {
		t.Fatalf("11th device: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM link_codes WHERE used_at IS NULL AND expires_at > $1`, f.now); n != 1 {
		t.Fatal("a refused redemption spent the code")
	}
}

func TestRedeemOnceUnderConcurrency(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	lc, _ := f.svc.CreateLinkCode(ctx, owner, lia)

	errs := make([]error, 2)
	var wg sync.WaitGroup
	for i := range errs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, errs[i] = f.svc.Redeem(ctx, lc.Code, "Tablet")
		}()
	}
	wg.Wait()
	ok, invalid := 0, 0
	for _, err := range errs {
		switch {
		case err == nil:
			ok++
		case errors.Is(err, parental.ErrInvalidCode):
			invalid++
		default:
			t.Fatal(err)
		}
	}
	if ok != 1 || invalid != 1 || f.count(`SELECT count(*) FROM devices`) != 1 {
		t.Fatalf("ok %d, invalid %d", ok, invalid)
	}
}

func TestAuthenticateDevice(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	out := f.linked(owner, lia)

	if _, err := f.svc.AuthenticateDevice(ctx, "nope"); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("unknown: %v", err)
	}
	f.now = f.now.Add(180 * 24 * time.Hour)
	if _, err := f.svc.AuthenticateDevice(ctx, out.Token); err != nil {
		t.Fatalf("exactly 180 days idle: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM devices WHERE last_seen_at = $1`, f.now); n != 1 {
		t.Fatal("last_seen_at not updated")
	}
	f.now = f.now.Add(180*24*time.Hour + time.Second)
	if _, err := f.svc.AuthenticateDevice(ctx, out.Token); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("idle-expired: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM devices`); n != 0 {
		t.Fatal("an idle-expired device was kept")
	}
}
