package identity_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestAuthenticateWithCorrectAndWrongPasswords(t *testing.T) {
	f := newFixture(t)
	id := f.signUpVerified("ana@example.com", goodPassword)
	ctx := context.Background()

	got, err := f.svc.Authenticate(ctx, "ana@example.com", goodPassword)
	if err != nil || got.AccountID != id {
		t.Fatalf("got %+v, %v", got, err)
	}
	if !f.audit.Has(id, audit.SignInSucceeded) {
		t.Fatal("success not audited")
	}
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", otherPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("wrong password: %v", err)
	}
	if _, err := f.svc.Authenticate(ctx, "ghost@example.com", goodPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("unknown email: %v", err)
	}
	if !f.audit.Has(id, audit.SignInFailed) || !f.audit.Has("", audit.SignInFailed) {
		t.Fatal("failures not audited")
	}
}

func TestUnverifiedAccountsCanSignIn(t *testing.T) {
	f := newFixture(t)
	_ = f.svc.SignUp(context.Background(), "ana@example.com", goodPassword, true, identity.TermsVersion)
	signedIn, err := f.svc.Authenticate(context.Background(), "ana@example.com", goodPassword)
	if err != nil {
		t.Fatal(err)
	}
	v, err := f.svc.Account(context.Background(), signedIn.AccountID)
	if err != nil || v.EmailVerified || v.Email != "ana@example.com" {
		t.Fatalf("view %+v, %v", v, err)
	}
}

func TestSignInMatchesEmailCaseAndUnicodeForms(t *testing.T) {
	f := newFixture(t)
	composed := "minha senha é segura demais"
	decomposed := "minha senha é segura demais"
	id := f.signUpVerified("ana@example.com", composed)

	got, err := f.svc.Authenticate(context.Background(), " Ana@Example.COM ", decomposed)
	if err != nil || got.AccountID != id {
		t.Fatalf("got %+v, %v", got, err)
	}
}

func TestFailedSignInsThrottleProgressively(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@example.com", goodPassword)
	ctx := context.Background()
	fail := func() error { _, err := f.svc.Authenticate(ctx, "ana@example.com", otherPassword); return err }

	for i := range 5 {
		if err := fail(); !errors.Is(err, identity.ErrInvalidCredentials) {
			t.Fatalf("failure %d: %v", i+1, err)
		}
	}
	var throttled *identity.ThrottledError
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", goodPassword); !errors.As(err, &throttled) || throttled.RetryAfter != time.Second {
		t.Fatalf("6th attempt inside the 1s window: %v", err)
	}
	f.now = f.now.Add(time.Second)
	if err := fail(); !errors.Is(err, identity.ErrInvalidCredentials) { // 6th failure: 2s
		t.Fatalf("after window: %v", err)
	}
	if err := fail(); !errors.As(err, &throttled) || throttled.RetryAfter != 2*time.Second {
		t.Fatalf("doubling: %v", err)
	}
	f.now = f.now.Add(2 * time.Second)
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", goodPassword); err != nil {
		t.Fatalf("correct password after window: %v", err)
	}
	if err := fail(); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("success did not reset the count: %v", err)
	}
}

func TestThrottleBackoffIsCappedAtFifteenMinutes(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@example.com", goodPassword)
	ctx := context.Background()

	for i := range 15 { // the 15th failure would block for 1024s uncapped
		f.now = f.now.Add(time.Hour) // past any earlier block
		if _, err := f.svc.Authenticate(ctx, "ana@example.com", otherPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
			t.Fatalf("failure %d: %v", i+1, err)
		}
	}
	var throttled *identity.ThrottledError
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", goodPassword); !errors.As(err, &throttled) || throttled.RetryAfter != 15*time.Minute {
		t.Fatalf("want a 15m cap, got %v", err)
	}
}

func TestReauthenticateChecksThePassword(t *testing.T) {
	f := newFixture(t)
	id := f.signUpVerified("ana@example.com", goodPassword)
	if err := f.svc.Reauthenticate(context.Background(), id, goodPassword); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Reauthenticate(context.Background(), id, otherPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("wrong password: %v", err)
	}
}
