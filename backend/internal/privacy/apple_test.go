package privacy_test

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/appleid"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
)

type fakeRevoker struct {
	calls [][3]string // clientID, code, redirectURI
	err   error
}

func (r *fakeRevoker) Revoke(_ context.Context, clientID, code, redirectURI string) error {
	r.calls = append(r.calls, [3]string{clientID, code, redirectURI})
	return r.err
}

const appleSubject = "001234.apple-subject"

func (f *fixture) linkApple(id, subject string) {
	f.exec(`INSERT INTO external_identities (provider, subject, account_id, created_at) VALUES ('apple', $1, $2::uuid, $3)`,
		subject, id, f.now)
}

func (f *fixture) appleAccount(email string) string {
	id := f.account(email)
	f.linkApple(id, appleSubject)
	return id
}

// appleAccount2 is a second Apple-linked account (subjects are unique).
func (f *fixture) appleAccount2(email string) string {
	id := f.account(email)
	f.linkApple(id, "001234.other")
	return id
}

func (f *fixture) appleCred(subject string) *privacy.AppleCredential {
	tok := f.ids.Issue(idtoken.Apple, idtoken.Claims{Subject: subject, Audience: "tech.coding4u.telinhasegura"})
	return &privacy.AppleCredential{IdentityToken: tok, AuthorizationCode: "code-1"}
}

func (f *fixture) gone(id string) bool {
	return f.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid`, id) == 0
}

func TestDeleteAppleNeedsACredential(t *testing.T) {
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	if err := f.svc.DeleteAccount(ctx, ana, nil); !errors.Is(err, privacy.ErrAppleReauthRequired) {
		t.Fatalf("err = %v", err)
	}
	if f.gone(ana) || len(f.apple.calls) != 0 {
		t.Fatal("deleted or revoked without a credential")
	}
}

func TestDeleteAppleMismatchKeepsTheAccount(t *testing.T) {
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	err := f.svc.DeleteAccount(ctx, ana, f.appleCred("someone-else"))
	if !errors.Is(err, privacy.ErrAppleIdentityMismatch) || f.gone(ana) || len(f.apple.calls) != 0 {
		t.Fatalf("err = %v, gone %v, calls %v", err, f.gone(ana), f.apple.calls)
	}
	bad := &privacy.AppleCredential{IdentityToken: "forged", AuthorizationCode: "c"}
	if err := f.svc.DeleteAccount(ctx, ana, bad); !errors.Is(err, privacy.ErrAppleIdentityMismatch) || f.gone(ana) {
		t.Fatalf("forged token: %v", err)
	}
	if f.audit.Has(ana, audit.AppleRevocationFailed) {
		t.Fatal("recorded a revocation failure")
	}
}

func TestDeleteAppleRevokesThenErases(t *testing.T) {
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	if err := f.svc.DeleteAccount(ctx, ana, f.appleCred(appleSubject)); err != nil {
		t.Fatal(err)
	}
	if !f.gone(ana) {
		t.Fatal("account kept")
	}
	if want := [][3]string{{"tech.coding4u.telinhasegura", "code-1", ""}}; !slices.Equal(f.apple.calls, want) {
		t.Fatalf("calls %v", f.apple.calls)
	}
	if f.audit.Has(ana, audit.AppleRevocationFailed) {
		t.Fatal("recorded a failure")
	}
}

// A web or Android deletion carries a code from Apple's web flow, issued to
// the Services ID and a redirect URI that differs between the two: its
// exchange takes the one the client says it used.
func TestDeleteAppleSendsTheClientsRedirectURI(t *testing.T) {
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	tok := f.ids.Issue(idtoken.Apple, idtoken.Claims{Subject: appleSubject, Audience: "tech.coding4u.telinhasegura.web"})
	cred := &privacy.AppleCredential{IdentityToken: tok, AuthorizationCode: "code-web", RedirectURI: "https://app.example.test"}
	if err := f.svc.DeleteAccount(ctx, ana, cred); err != nil {
		t.Fatal(err)
	}
	want := [][3]string{{"tech.coding4u.telinhasegura.web", "code-web", "https://app.example.test"}}
	if !f.gone(ana) || !slices.Equal(f.apple.calls, want) {
		t.Fatalf("gone %v, calls %v", f.gone(ana), f.apple.calls)
	}
}

func TestDeleteAppleInvalidGrantKeepsTheAccount(t *testing.T) {
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	f.apple.err = appleid.ErrInvalidGrant
	if err := f.svc.DeleteAccount(ctx, ana, f.appleCred(appleSubject)); !errors.Is(err, privacy.ErrAppleAuthorizationInvalid) || f.gone(ana) {
		t.Fatalf("err = %v", err)
	}
	if f.audit.Has(ana, audit.AppleRevocationFailed) {
		t.Fatal("recorded a revocation failure")
	}
}

func TestDeleteAppleOutageStillErases(t *testing.T) {
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	f.apple.err = errors.New("appleid: token answered 503")
	if err := f.svc.DeleteAccount(ctx, ana, f.appleCred(appleSubject)); err != nil {
		t.Fatal(err)
	}
	if !f.gone(ana) || !f.audit.Has(ana, audit.AppleRevocationFailed) {
		t.Fatalf("gone %v, entries %v", f.gone(ana), f.audit.Entries)
	}
}

func TestDeleteAppleWhenAppleIsOff(t *testing.T) {
	f := newFixture(t)
	f.ids.Disabled = []idtoken.Provider{idtoken.Apple}
	ana := f.appleAccount("ana@example.com")
	if err := f.svc.DeleteAccount(ctx, ana, &privacy.AppleCredential{IdentityToken: "t", AuthorizationCode: "c"}); err != nil {
		t.Fatal(err)
	}
	if !f.gone(ana) || !f.audit.Has(ana, audit.AppleRevocationFailed) {
		t.Fatal("not erased with a recorded failure")
	}
	// With Apple off the API cannot ask for a credential either.
	f.deps.Apple = nil
	f.svc = privacy.NewService(f.deps)
	bia := f.appleAccount2("bia@example.com")
	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil || !f.gone(bia) {
		t.Fatalf("no credential, Apple off: %v", err)
	}
	if !f.audit.Has(bia, audit.AppleRevocationFailed) {
		t.Fatal("Apple off: failure not recorded")
	}
}

func TestDeleteWithoutAppleIgnoresACredential(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	if err := f.svc.DeleteAccount(ctx, ana, f.appleCred("whoever")); err != nil || !f.gone(ana) || len(f.apple.calls) != 0 {
		t.Fatalf("err = %v, calls %v", err, f.apple.calls)
	}
}

func TestDeleteAppleOwnerIsRefusedBeforeRevoking(t *testing.T) { // review: no spent code
	f := newFixture(t)
	ana := f.appleAccount("ana@example.com")
	f.family(ana)
	err := f.svc.DeleteAccount(ctx, ana, f.appleCred(appleSubject))
	if !errors.Is(err, privacy.ErrOwnerMustTransfer) || len(f.apple.calls) != 0 || f.gone(ana) {
		t.Fatalf("err = %v, calls %v, gone %v", err, f.apple.calls, f.gone(ana))
	}
}
