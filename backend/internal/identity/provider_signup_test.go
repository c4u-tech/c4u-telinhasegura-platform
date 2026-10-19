package identity_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

// signupTicket starts a provider sign-in that needs a signup.
func (f *fixture) signupTicket(sub, email string) string {
	f.t.Helper()
	_, err := f.svc.ProviderSignIn(context.Background(), idtoken.Google, f.tokens.Issue(idtoken.Google, gmail(sub, email)))
	return confirmation(f.t, err, "signup_required").Ticket
}

func TestProviderSignUpCreatesAVerifiedPasswordlessAccount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id, err := f.svc.ProviderSignUp(ctx, f.signupTicket("g-1", "ana@gmail.com"), true, identity.TermsVersion)
	if err != nil {
		t.Fatal(err)
	}
	if !f.verified("ana@gmail.com") || f.accountID("ana@gmail.com") != id {
		t.Fatal("account not created verified")
	}
	if !f.audit.Has(id, audit.ProviderSignedUp) {
		t.Fatal("signup not audited")
	}
	if _, err := f.svc.Authenticate(ctx, "ana@gmail.com", goodPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("password sign-in on a passwordless account: %v", err)
	}
	// The identity now signs in directly, whatever email the token carries.
	again, err := f.svc.ProviderSignIn(ctx, idtoken.Google, f.tokens.Issue(idtoken.Google, gmail("g-1", "renamed@gmail.com")))
	if err != nil || again != id {
		t.Fatalf("linked sign-in: %q, %v", again, err)
	}
	if !f.audit.Has(id, audit.ProviderSignInSucceeded) {
		t.Fatal("sign-in not audited")
	}
}

func TestProviderSignUpNeedsTheAdultDeclarationAndKeepsTheTicket(t *testing.T) {
	f := newFixture(t)
	ticket := f.signupTicket("g-1", "ana@gmail.com")
	if _, err := f.svc.ProviderSignUp(context.Background(), ticket, false, identity.TermsVersion); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("got %v", err)
	}
	if _, err := f.svc.ProviderSignUp(context.Background(), ticket, true, identity.TermsVersion); err != nil {
		t.Fatalf("ticket lost: %v", err)
	}
}

func TestSignupTicketsAreSingleUseAndExpire(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	ticket := f.signupTicket("g-1", "ana@gmail.com")
	if _, err := f.svc.ProviderSignUp(ctx, ticket, true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.ProviderSignUp(ctx, ticket, true, identity.TermsVersion); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("second use: %v", err)
	}
	late := f.signupTicket("g-2", "bia@gmail.com")
	f.now = f.now.Add(10*time.Minute + time.Second)
	if _, err := f.svc.ProviderSignUp(ctx, late, true, identity.TermsVersion); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("expired: %v", err)
	}
	if _, err := f.svc.ProviderSignUp(ctx, "made-up", true, identity.TermsVersion); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("unknown: %v", err)
	}
}

func TestALinkTicketCannotSignUp(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@gmail.com", goodPassword)
	_, err := f.svc.ProviderSignIn(context.Background(), idtoken.Google, f.tokens.Issue(idtoken.Google, gmail("g-1", "ana@gmail.com")))
	link := confirmation(t, err, "link_required").Ticket
	if _, err := f.svc.ProviderSignUp(context.Background(), link, true, identity.TermsVersion); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("got %v", err)
	}
}

func TestProviderSignUpTurnsIntoALinkWhenTheEmailWasTakenMeanwhile(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	ticket := f.signupTicket("g-1", "ana@gmail.com")
	f.signUpVerified("ana@gmail.com", goodPassword)

	_, err := f.svc.ProviderSignUp(ctx, ticket, true, identity.TermsVersion)
	confirmation(t, err, "link_required")
	if _, err := f.svc.ProviderSignUp(ctx, ticket, true, identity.TermsVersion); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("old ticket still usable: %v", err)
	}
}

func TestPasswordlessAccountsGetAPasswordOnlyThroughRecovery(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id, err := f.svc.ProviderSignUp(ctx, f.signupTicket("g-1", "ana@gmail.com"), true, identity.TermsVersion)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ChangePassword(ctx, id, "", "", otherPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("change without a password: %v", err)
	}
	if err := f.svc.RequestPasswordReset(ctx, "ana@gmail.com"); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ConfirmPasswordReset(ctx, f.lastToken("ana@gmail.com"), goodPassword); err != nil {
		t.Fatal(err)
	}
	if got, err := f.svc.Authenticate(ctx, "ana@gmail.com", goodPassword); err != nil || got.AccountID != id {
		t.Fatalf("after recovery: %+v, %v", got, err)
	}
}
