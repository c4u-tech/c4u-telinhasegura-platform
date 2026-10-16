package identity_test

import (
	"context"
	"errors"
	"maps"
	"slices"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
)

// providerOnly inserts a verified account with no password, linked to
// provider, as a provider sign-up leaves it.
func (f *fixture) providerOnly(email, provider string) string {
	f.t.Helper()
	ctx := context.Background()
	var id string
	if err := f.pool.QueryRow(ctx, `INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $2, $2) RETURNING id::text`, email, f.now).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	if _, err := f.pool.Exec(ctx, `INSERT INTO external_identities (provider, subject, account_id, created_at)
		VALUES ($1, $2, $3::uuid, $4)`, provider, "sub-"+email, id, f.now); err != nil {
		f.t.Fatal(err)
	}
	return id
}

func TestAccountForStaff(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	ana := f.signUpVerified("ana@example.com", goodPassword)
	if _, err := f.pool.Exec(ctx, `INSERT INTO external_identities (provider, subject, account_id, created_at)
		VALUES ('apple', 'a1', $1::uuid, $2), ('google', 'g1', $1::uuid, $2)`, ana, f.now); err != nil {
		t.Fatal(err)
	}

	got, err := f.svc.AccountForStaff(ctx, strings.ToUpper(ana))
	if err != nil || got.ID != ana || got.Email != "ana@example.com" || !got.EmailVerified || !got.CreatedAt.Equal(f.now) ||
		!slices.Equal(got.Providers, []string{"password", "google", "apple"}) {
		t.Fatalf("account %+v %v", got, err)
	}
	gil := f.providerOnly("gil@example.com", "google")
	if got, err := f.svc.AccountForStaff(ctx, gil); err != nil || !slices.Equal(got.Providers, []string{"google"}) {
		t.Fatalf("a Google-only account: %+v %v", got, err)
	}
	if _, err := f.pool.Exec(ctx, `DELETE FROM external_identities WHERE account_id = $1::uuid`, gil); err != nil {
		t.Fatal(err)
	}
	if got, err := f.svc.AccountForStaff(ctx, gil); err != nil || got.Providers == nil || len(got.Providers) != 0 {
		t.Fatalf("no provider must be an empty, non-nil list: %+v %v", got, err)
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.AccountForStaff(ctx, id); !errors.Is(err, identity.ErrNotFound) {
			t.Errorf("%q: %v, want ErrNotFound", id, err)
		}
	}
}

func TestAccountIDByEmailEmailsAndCount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	ana := f.signUpVerified("ana@example.com", goodPassword)
	bia := f.signUpVerified("bia@example.com", goodPassword)

	if id, err := f.svc.AccountIDByEmail(ctx, "  ANA@example.com "); err != nil || id != ana {
		t.Fatalf("by email: %q %v", id, err)
	}
	if _, err := f.svc.AccountIDByEmail(ctx, "nobody@example.com"); !errors.Is(err, identity.ErrNotFound) {
		t.Fatalf("unknown email: %v", err)
	}
	got, err := f.svc.Emails(ctx, []string{ana, bia, ana, "", "abc", "00000000-0000-0000-0000-000000000000"})
	if err != nil || !maps.Equal(got, map[string]string{ana: "ana@example.com", bia: "bia@example.com"}) {
		t.Fatalf("emails %v %v", got, err)
	}
	if got, err := f.svc.Emails(ctx, nil); err != nil || got == nil || len(got) != 0 {
		t.Fatalf("no ids: %v %v", got, err)
	}
	if n, err := f.svc.CountAccounts(ctx); err != nil || n != 2 {
		t.Fatalf("count %d %v", n, err)
	}
}

func TestSendPasswordResetForStaff(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	gil := f.providerOnly("gil@example.com", "google")

	if err := f.svc.SendPasswordReset(ctx, gil); err != nil {
		t.Fatal(err)
	}
	first := f.lastToken("gil@example.com")
	if err := f.svc.SendPasswordReset(ctx, gil); err != nil {
		t.Fatal(err)
	}
	second := f.lastToken("gil@example.com")
	if err := f.svc.ConfirmPasswordReset(ctx, first, goodPassword); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("an earlier reset link still works: %v", err)
	}
	if err := f.svc.ConfirmPasswordReset(ctx, second, goodPassword); err != nil {
		t.Fatalf("the latest reset link: %v", err)
	}
	if got, _ := f.svc.AccountForStaff(ctx, gil); !slices.Equal(got.Providers, []string{"password", "google"}) {
		t.Fatalf("a Google-only account gains a password on confirmation: %v", got.Providers)
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if err := f.svc.SendPasswordReset(ctx, id); !errors.Is(err, identity.ErrNotFound) {
			t.Errorf("%q: %v, want ErrNotFound", id, err)
		}
	}
}
