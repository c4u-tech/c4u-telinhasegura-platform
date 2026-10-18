package identity_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

// linkTicket starts a provider sign-in that matches an existing account.
func (f *fixture) linkTicket(c idtoken.Claims) string {
	f.t.Helper()
	_, err := f.svc.ProviderSignIn(context.Background(), idtoken.Google, f.tokens.Issue(idtoken.Google, c))
	return confirmation(f.t, err, "link_required").Ticket
}

func TestLinkWithThePasswordKeepsItAndTheSessions(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)

	got, err := f.svc.ProviderLink(ctx, f.linkTicket(gmail("g-1", "ana@gmail.com")), identity.LinkProof{Password: goodPassword})
	if err != nil || got != id {
		t.Fatalf("link: %q, %v", got, err)
	}
	if _, err := f.svc.Authenticate(ctx, "ana@gmail.com", goodPassword); err != nil {
		t.Fatalf("password lost: %v", err)
	}
	if len(f.sessions.calls) != 0 {
		t.Fatalf("sessions revoked: %+v", f.sessions.calls)
	}
	if !f.audit.Has(id, audit.IdentityLinked) {
		t.Fatal("link not audited")
	}
	if m := f.lastMail("ana@gmail.com"); !strings.Contains(m.Subject, "Google") || strings.Contains(m.Body, "removida") {
		t.Fatalf("notice %q does not name the provider, or claims the password was removed", m.Subject)
	}
	if again, err := f.svc.ProviderSignIn(ctx, idtoken.Google, f.tokens.Issue(idtoken.Google, gmail("g-1", "ana@gmail.com"))); err != nil || again != id {
		t.Fatalf("linked sign-in: %q, %v", again, err)
	}
}

func TestAWrongLinkPasswordCountsAndKeepsTheTicket(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.signUpVerified("ana@gmail.com", goodPassword)
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))

	if _, err := f.svc.ProviderLink(ctx, ticket, identity.LinkProof{Password: otherPassword}); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("wrong password: %v", err)
	}
	if !f.audit.Has(f.accountID("ana@gmail.com"), audit.SignInFailed) {
		t.Fatal("failure not counted")
	}
	if n := f.count(`SELECT failed_sign_ins FROM accounts WHERE email = 'ana@gmail.com'`); n != 1 {
		t.Fatalf("failed_sign_ins = %d, want 1", n)
	}
	if _, err := f.svc.ProviderLink(ctx, ticket, identity.LinkProof{Password: goodPassword}); err != nil {
		t.Fatalf("retry: %v", err)
	}
}

func TestClearPasswordEvictsTheSquatter(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	// A squatter signs up with the victim's address and picks the password;
	// the victim then confirms the squatter's verification mail.
	if err := f.svc.SignUp(ctx, "ana@gmail.com", goodPassword, true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ConfirmEmail(ctx, f.lastToken("ana@gmail.com")); err != nil {
		t.Fatal(err)
	}
	id := f.accountID("ana@gmail.com")
	if err := f.svc.RequestPasswordReset(ctx, "ana@gmail.com"); err != nil { // a pending token the squatter might hold
		t.Fatal(err)
	}
	pendingReset := f.lastToken("ana@gmail.com")

	squatter := f.liveSession(id)

	got, err := f.svc.ProviderLink(ctx, f.linkTicket(gmail("g-1", "ana@gmail.com")), identity.LinkProof{ClearPassword: true})
	if err != nil || got != id {
		t.Fatalf("link: %q, %v", got, err)
	}
	if _, err := f.svc.Authenticate(ctx, "ana@gmail.com", goodPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("squatter password still works: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM sessions WHERE id = $1 AND revoked_at IS NULL`, squatter); n != 0 {
		t.Fatal("the squatter's session survived")
	}
	if err := f.svc.ConfirmPasswordReset(ctx, pendingReset, otherPassword); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("pending reset survived: %v", err)
	}
	if !f.audit.Has(id, audit.ProviderPasswordCleared) || !f.audit.Has(id, audit.IdentityLinked) {
		t.Fatal("clearing not audited")
	}
	m := f.lastMail("ana@gmail.com")
	if !strings.Contains(m.Subject, "Google") {
		t.Fatal("no link notice")
	}
	if !strings.Contains(m.Body, "senha foi removida") || !strings.Contains(m.Body, "todos os aparelhos saíram") {
		t.Fatalf("the notice does not say the password was removed and every device signed out: %q", m.Body)
	}
}

func TestClearPasswordNeedsAnAuthoritativeEmail(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@empresa.com.br", goodPassword)
	c := gmail("g-1", "ana@empresa.com.br")
	c.EmailAuthoritative = false
	ticket := f.linkTicket(c)
	if _, err := f.svc.ProviderLink(context.Background(), ticket, identity.LinkProof{ClearPassword: true}); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("got %v", err)
	}
	if _, err := f.svc.Authenticate(context.Background(), "ana@empresa.com.br", goodPassword); err != nil {
		t.Fatalf("password changed: %v", err)
	}
	if _, err := f.svc.ProviderLink(context.Background(), ticket, identity.LinkProof{Password: goodPassword}); err != nil {
		t.Fatalf("the rejected attempt spent the ticket: %v", err)
	}
}

func TestClearPasswordVerifiesAnUnverifiedAccount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if err := f.svc.SignUp(ctx, "ana@gmail.com", goodPassword, true, identity.TermsVersion); err != nil { // never verified
		t.Fatal(err)
	}
	f.clear(f.linkTicket(gmail("g-1", "ana@gmail.com")), f.accountID("ana@gmail.com"))
	if !f.verified("ana@gmail.com") {
		t.Fatal("the provider proved the mailbox but the account is still unverified")
	}
}

func TestLinkProofMustBeExactlyOne(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@gmail.com", goodPassword)
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))
	for name, proof := range map[string]identity.LinkProof{
		"neither": {},
		"both":    {Password: goodPassword, ClearPassword: true},
	} {
		if _, err := f.svc.ProviderLink(context.Background(), ticket, proof); !errors.Is(err, identity.ErrValidation) {
			t.Errorf("%s: got %v", name, err)
		}
	}
}

func TestOneIdentityPerProviderPerAccount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.signUpVerified("ana@gmail.com", goodPassword)
	if _, err := f.svc.ProviderLink(ctx, f.linkTicket(gmail("g-1", "ana@gmail.com")), identity.LinkProof{Password: goodPassword}); err != nil {
		t.Fatal(err)
	}
	second := f.linkTicket(gmail("g-2", "ana@gmail.com"))
	if _, err := f.svc.ProviderLink(ctx, second, identity.LinkProof{Password: goodPassword}); !errors.Is(err, identity.ErrIdentityConflict) {
		t.Fatalf("got %v", err)
	}
	// The conflict changed nothing: once it is gone, the same ticket links.
	if _, err := f.pool.Exec(ctx, `DELETE FROM external_identities WHERE subject = 'g-1'`); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.ProviderLink(ctx, second, identity.LinkProof{Password: goodPassword}); err != nil {
		t.Fatalf("the rejected attempt spent the ticket: %v", err)
	}
}

func TestReauthenticateWithALinkedProvider(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	ana, err := f.svc.ProviderSignUp(ctx, f.signupTicket("g-ana", "ana@gmail.com"), true, identity.TermsVersion)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.ProviderSignUp(ctx, f.signupTicket("g-bia", "bia@gmail.com"), true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	issue := func(sub string) string { return f.tokens.Issue(idtoken.Google, gmail(sub, sub+"@gmail.com")) }

	if err := f.svc.ReauthenticateWithProvider(ctx, ana, idtoken.Google, issue("g-ana")); err != nil {
		t.Fatalf("own identity: %v", err)
	}
	if err := f.svc.ReauthenticateWithProvider(ctx, ana, idtoken.Google, issue("g-bia")); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("another account's identity: %v", err)
	}
	if err := f.svc.ReauthenticateWithProvider(ctx, ana, idtoken.Google, issue("g-nobody")); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("unlinked identity: %v", err)
	}
}

func TestLinkTicketDiesWhenTheAccountEmailChanges(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))
	if _, err := f.pool.Exec(ctx, "UPDATE accounts SET email = 'other@gmail.com' WHERE id = $1", id); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.ProviderLink(ctx, ticket, identity.LinkProof{ClearPassword: true}); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("got %v", err)
	}
	if _, err := f.svc.Authenticate(ctx, "other@gmail.com", goodPassword); err != nil {
		t.Fatalf("password changed: %v", err)
	}
}
