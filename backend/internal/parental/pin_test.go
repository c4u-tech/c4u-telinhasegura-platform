package parental_test

import (
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestSetPIN(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	guardian := f.member(owner, "bia@example.com")

	if set, err := f.svc.PINSet(ctx, owner); err != nil || set {
		t.Fatalf("before: %v %v", set, err)
	}
	if err := f.svc.SetPIN(ctx, guardian, goodPIN); err != nil { // any guardian, not only the owner
		t.Fatal(err)
	}
	if set, err := f.svc.PINSet(ctx, owner); err != nil || !set {
		t.Fatalf("after: %v %v", set, err)
	}
	var hash string
	if err := f.pool.QueryRow(ctx, `SELECT pin_hash FROM family_pins`).Scan(&hash); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(hash, "$argon2id$") || strings.Contains(hash, goodPIN) {
		t.Fatalf("stored %q", hash)
	}
	if len(f.mail.To("bia@example.com")) != 0 {
		t.Fatal("the guardian who set the PIN got a notice")
	}
	notice := f.mail.To("ana@example.com")
	if len(notice) != 1 || strings.Contains(notice[0].Body, goodPIN) ||
		strings.Contains(notice[0].Body, "bia@example.com") || !strings.Contains(notice[0].Body, "03/10/2026 às 09:00") {
		t.Fatalf("notice: %+v", notice)
	}
	if !f.audit.Has(guardian, audit.PINSet) {
		t.Fatal("no pin_set audit")
	}
}

func TestSetPINErrors(t *testing.T) {
	f := newFixture(t)
	loner := f.account("lia@example.com")
	if err := f.svc.SetPIN(ctx, loner, "1"); !errors.Is(err, parental.ErrNoFamily) {
		t.Fatalf("no family: %v", err) // standing before the body
	}
	if _, err := f.svc.PINSet(ctx, loner); !errors.Is(err, parental.ErrNoFamily) {
		t.Fatalf("PINSet, no family: %v", err)
	}
	owner := f.owner("ana@example.com")
	for pin, want := range map[string]error{"123": parental.ErrValidation, "1111": parental.ErrWeakPIN} {
		if err := f.svc.SetPIN(ctx, owner, pin); !errors.Is(err, want) {
			t.Fatalf("%q: %v", pin, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM family_pins`); n != 0 {
		t.Fatalf("stored %d PINs", n)
	}
}

func TestSetPINNoticeFailureDoesNotFail(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	f.member(owner, "bia@example.com")
	f.failMail()
	if err := f.svc.SetPIN(ctx, owner, goodPIN); err != nil {
		t.Fatal(err)
	}
	if len(f.mail.To("bia@example.com")) != 1 {
		t.Fatal("the notice was not attempted")
	}
}

func retryAfter(t *testing.T, err error) time.Duration {
	t.Helper()
	var th *parental.ThrottledError
	if !errors.As(err, &th) {
		t.Fatalf("want a ThrottledError, got %v", err)
	}
	return th.RetryAfter
}

func TestPINCooldown(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	f.withPIN(owner)
	fam := f.familyID(owner)
	check := func(pin string) error { return parental.CheckPIN(ctx, f.svc, fam, owner, pin) }
	failed := func() int { return f.count(`SELECT failed_attempts FROM family_pins`) }

	for i := 1; i <= 4; i++ {
		if err := check("1357"); !errors.Is(err, parental.ErrInvalidPIN) {
			t.Fatalf("failure %d: %v", i, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM family_pins WHERE blocked_until IS NOT NULL`); n != 0 {
		t.Fatal("blocked before the 5th failure")
	}
	if err := check("1357"); !errors.Is(err, parental.ErrInvalidPIN) {
		t.Fatalf("5th failure: %v", err)
	}
	if !f.audit.Has(owner, audit.PINBlocked) {
		t.Fatal("no pin_failed_blocked audit")
	}
	if d := retryAfter(t, check(goodPIN)); d != 30*time.Second {
		t.Fatalf("right PIN while blocked: retry after %v", d)
	}
	if retryAfter(t, check("1357")); failed() != 5 {
		t.Fatalf("a check while blocked counted: %d", failed())
	}

	wait := 30 * time.Second
	for _, want := range []time.Duration{60, 120, 240, 480, 900, 900} {
		f.now = f.now.Add(wait)
		if err := check("1357"); !errors.Is(err, parental.ErrInvalidPIN) {
			t.Fatalf("after %v: %v", wait, err)
		}
		wait = retryAfter(t, check(goodPIN))
		if wait != want*time.Second {
			t.Fatalf("block = %v, want %vs", wait, want)
		}
	}
	f.now = f.now.Add(wait)
	if err := check(goodPIN); err != nil {
		t.Fatalf("after the block: %v", err)
	}
	if failed() != 0 || f.count(`SELECT count(*) FROM family_pins WHERE blocked_until IS NOT NULL`) != 0 {
		t.Fatal("a success did not reset the counter")
	}
}

func TestPINCooldownHoldsUnderParallelGuesses(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	f.withPIN(owner)
	fam := f.familyID(owner)
	errs := make([]error, 10)
	var wg sync.WaitGroup
	for i := range errs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs[i] = parental.CheckPIN(ctx, f.svc, fam, owner, "1357")
		}()
	}
	wg.Wait()
	invalid, throttled := 0, 0
	for _, err := range errs {
		var th *parental.ThrottledError
		switch {
		case errors.Is(err, parental.ErrInvalidPIN):
			invalid++
		case errors.As(err, &th):
			throttled++
		default:
			t.Fatalf("unexpected: %v", err)
		}
	}
	if invalid != 5 || throttled != 5 {
		t.Fatalf("invalid=%d throttled=%d, want 5 and 5", invalid, throttled)
	}
	if n := f.count(`SELECT failed_attempts FROM family_pins`); n != 5 {
		t.Fatalf("failed_attempts = %d", n)
	}
}

func TestPINNotSet(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	if err := parental.CheckPIN(ctx, f.svc, f.familyID(owner), owner, goodPIN); !errors.Is(err, parental.ErrPINNotSet) {
		t.Fatal(err)
	}
}

func TestSetPINClearsTheCooldown(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	f.withPIN(owner)
	fam := f.familyID(owner)
	for range 5 {
		_ = parental.CheckPIN(ctx, f.svc, fam, owner, "1357")
	}
	if err := f.svc.SetPIN(ctx, owner, "1357"); err != nil {
		t.Fatal(err)
	}
	if err := parental.CheckPIN(ctx, f.svc, fam, owner, "1357"); err != nil {
		t.Fatalf("new PIN right after a reset: %v", err)
	}
}

func TestPINCounterIsPerFamily(t *testing.T) {
	f := newFixture(t)
	ana, bia := f.owner("ana@example.com"), f.owner("bia@example.com")
	f.withPIN(ana)
	f.withPIN(bia)
	for range 5 {
		_ = parental.CheckPIN(ctx, f.svc, f.familyID(ana), ana, "1357")
	}
	if err := parental.CheckPIN(ctx, f.svc, f.familyID(bia), bia, goodPIN); err != nil {
		t.Fatalf("another family was blocked: %v", err)
	}
}

func TestVerifyPIN(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	if err := f.svc.VerifyPIN(ctx, owner, goodPIN); !errors.Is(err, parental.ErrPINNotSet) {
		t.Fatalf("no PIN: %v", err)
	}
	f.withPIN(owner)
	if err := f.svc.VerifyPIN(ctx, owner, goodPIN); err != nil {
		t.Fatalf("right PIN: %v", err)
	}
	if err := f.svc.VerifyPIN(ctx, owner, "1357"); !errors.Is(err, parental.ErrInvalidPIN) {
		t.Fatalf("wrong PIN: %v", err)
	}
	loner := f.account("lia@example.com")
	if err := f.svc.VerifyPIN(ctx, loner, goodPIN); !errors.Is(err, parental.ErrNoFamily) {
		t.Fatalf("no family: %v", err)
	}
}

func TestVerifyPINSharesTheCounter(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	f.withPIN(owner)
	for range 4 {
		_ = f.svc.VerifyPIN(ctx, owner, "1357")
	}
	_ = parental.CheckPIN(ctx, f.svc, f.familyID(owner), owner, "1357")
	if err := f.svc.VerifyPIN(ctx, owner, goodPIN); retryAfter(t, err) <= 0 {
		t.Fatalf("not blocked: %v", err)
	}
}

func TestCheckChildPINSharesTheCounter(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	f.withPIN(owner)
	minor := f.minor(owner, "Lia")
	dev := parental.Principal{FamilyID: f.familyID(owner), MinorID: minor, DeviceID: "d"}
	if err := f.svc.CheckChildPIN(ctx, dev, goodPIN); err != nil {
		t.Fatalf("good PIN: %v", err)
	}
	if err := f.svc.CheckChildPIN(ctx, dev, "1357"); !errors.Is(err, parental.ErrInvalidPIN) {
		t.Fatalf("wrong PIN: %v", err)
	}
	for range 4 { // with the one above, the 5th failure sets the block
		_ = f.svc.VerifyPIN(ctx, owner, "1357")
	}
	if err := f.svc.CheckChildPIN(ctx, dev, goodPIN); retryAfter(t, err) <= 0 {
		t.Fatalf("not blocked after 5 shared failures: %v", err)
	}
	if err := f.svc.CheckChildPIN(ctx, parental.Principal{}, goodPIN); !errors.Is(err, parental.ErrProfileGone) {
		t.Fatalf("gone: %v", err)
	}
}
