package identity_test

import (
	"context"
	"errors"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
)

func (f *fixture) accounts() int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(context.Background(), `SELECT count(*) FROM accounts`).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

func (f *fixture) terms(email string) (version string, accepted bool) {
	f.t.Helper()
	var v *string
	if err := f.pool.QueryRow(context.Background(),
		`SELECT terms_version, terms_accepted_at = $2 FROM accounts WHERE email = $1`, email, f.now).Scan(&v, &accepted); err != nil {
		f.t.Fatal(err)
	}
	if v != nil {
		version = *v
	}
	return version, accepted
}

func TestSignUpRecordsTheTermsVersionAndWhen(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.SignUp(context.Background(), "ana@example.com", goodPassword, true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if v, ok := f.terms("ana@example.com"); v != identity.TermsVersion || !ok {
		t.Fatalf("recorded %q, accepted at now: %v", v, ok)
	}
}

func TestSignUpRefusesMissingOrOutdatedTermsAndCreatesNoAccount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if _, err := f.svc.SignUp(ctx, "ana@example.com", goodPassword, true, ""); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("empty: %v", err)
	}
	if _, err := f.svc.SignUp(ctx, "ana@example.com", goodPassword, true, "2020-01-01"); !errors.Is(err, identity.ErrTermsOutdated) {
		t.Fatalf("old: %v", err)
	}
	if n := f.accounts(); n != 0 {
		t.Fatalf("%d accounts created", n)
	}
}

func TestProviderSignUpRecordsTheTermsVersion(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.ProviderSignUp(context.Background(), f.signupTicket("g-1", "ana@gmail.com"), true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if v, ok := f.terms("ana@gmail.com"); v != identity.TermsVersion || !ok {
		t.Fatalf("recorded %q, accepted at now: %v", v, ok)
	}
}

func TestProviderSignUpRefusesBadTermsAndKeepsTheTicket(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	ticket := f.signupTicket("g-1", "ana@gmail.com")
	if _, err := f.svc.ProviderSignUp(ctx, ticket, true, ""); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("empty: %v", err)
	}
	if _, err := f.svc.ProviderSignUp(ctx, ticket, true, "2020-01-01"); !errors.Is(err, identity.ErrTermsOutdated) {
		t.Fatalf("old: %v", err)
	}
	if n := f.accounts(); n != 0 {
		t.Fatalf("%d accounts created", n)
	}
	if _, err := f.svc.ProviderSignUp(ctx, ticket, true, identity.TermsVersion); err != nil {
		t.Fatalf("ticket was spent by a refused request: %v", err)
	}
}

func TestAcceptTermsRecordsTheCurrentVersionOnly(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	// An account that predates the terms has accepted nothing.
	if _, err := f.pool.Exec(ctx, `UPDATE accounts SET terms_version = NULL, terms_accepted_at = NULL WHERE id = $1::uuid`, id); err != nil {
		t.Fatal(err)
	}
	if a, err := f.svc.Account(ctx, id); err != nil || a.TermsAccepted {
		t.Fatalf("before: %+v, %v", a, err)
	}
	if err := f.svc.AcceptTerms(ctx, id, "2020-01-01"); !errors.Is(err, identity.ErrTermsOutdated) {
		t.Fatalf("old: %v", err)
	}
	if err := f.svc.AcceptTerms(ctx, id, ""); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("empty: %v", err)
	}
	if a, _ := f.svc.Account(ctx, id); a.TermsAccepted {
		t.Fatal("a refused acceptance was recorded")
	}
	if err := f.svc.AcceptTerms(ctx, id, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if v, ok := f.terms("ana@example.com"); v != identity.TermsVersion || !ok {
		t.Fatalf("recorded %q, accepted at now: %v", v, ok)
	}
	if a, _ := f.svc.Account(ctx, id); !a.TermsAccepted {
		t.Fatal("not accepted after AcceptTerms")
	}
}

func TestTermsAcceptedIsFalseForAnOlderVersion(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	if _, err := f.pool.Exec(ctx, `UPDATE accounts SET terms_version = '2020-01-01' WHERE id = $1::uuid`, id); err != nil {
		t.Fatal(err)
	}
	if a, _ := f.svc.Account(ctx, id); a.TermsAccepted {
		t.Fatal("an older version counts as accepted")
	}
}
