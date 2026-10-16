package identity_test

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

func TestProviderSignInAsksForSignupWhenNoAccountMatches(t *testing.T) {
	f := newFixture(t)
	raw := f.tokens.Issue(idtoken.Google, gmail("g-1", "Ana@Gmail.com"))
	_, err := f.svc.ProviderSignIn(context.Background(), idtoken.Google, raw)
	c := confirmation(t, err, "signup_required")
	if c.Email != "ana@gmail.com" || c.Options != nil {
		t.Fatalf("got %+v", c)
	}
	if len(c.Ticket) != 43 { // 256 bits, unpadded base64url
		t.Fatalf("ticket %q is not 256 bits", c.Ticket)
	}
}

func TestProviderSignInAsksToLinkAMatchingAccount(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@gmail.com", goodPassword)
	ctx := context.Background()

	_, err := f.svc.ProviderSignIn(ctx, idtoken.Google, f.tokens.Issue(idtoken.Google, gmail("g-1", " Ana@Gmail.com ")))
	c := confirmation(t, err, "link_required")
	if c.Email != "ana@gmail.com" || !slices.Equal(c.Options, []string{"password", "clear_password"}) {
		t.Fatalf("authoritative: %+v", c)
	}

	f.signUpVerified("ana@empresa.com.br", goodPassword)
	claims := gmail("g-2", "ana@empresa.com.br")
	claims.EmailAuthoritative = false
	_, err = f.svc.ProviderSignIn(ctx, idtoken.Google, f.tokens.Issue(idtoken.Google, claims))
	if c := confirmation(t, err, "link_required"); !slices.Equal(c.Options, []string{"password"}) {
		t.Fatalf("not authoritative: %+v", c)
	}
}

func TestProviderSignInRefusesUnverifiedOrMissingEmails(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@gmail.com", goodPassword)
	ctx := context.Background()
	unverified := gmail("g-1", "ana@gmail.com")
	unverified.EmailVerified = false
	cases := map[string]idtoken.Claims{
		"unverified, account exists": unverified,
		"unverified, no account":     {Subject: "g-2", Email: "bia@gmail.com"},
		"no email":                   {Subject: "g-3", EmailVerified: true},
		"malformed email":            {Subject: "g-4", Email: "not an email", EmailVerified: true},
	}
	for name, c := range cases {
		if _, err := f.svc.ProviderSignIn(ctx, idtoken.Google, f.tokens.Issue(idtoken.Google, c)); !errors.Is(err, identity.ErrProviderEmailUnverified) {
			t.Errorf("%s: got %v", name, err)
		}
	}
}

func TestProviderTokensAreSingleUse(t *testing.T) {
	f := newFixture(t)
	raw := f.tokens.Issue(idtoken.Google, gmail("g-1", "ana@gmail.com"))
	ctx := context.Background()
	if _, err := f.svc.ProviderSignIn(ctx, idtoken.Google, raw); errors.Is(err, identity.ErrInvalidToken) {
		t.Fatal("first use refused")
	}
	if _, err := f.svc.ProviderSignIn(ctx, idtoken.Google, raw); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("replay: got %v", err)
	}
}

func TestProviderSignInMapsVerifierErrors(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if _, err := f.svc.ProviderSignIn(ctx, idtoken.Google, "forged"); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("invalid: got %v", err)
	}
	apple := f.tokens.Issue(idtoken.Apple, gmail("a-1", "x@privaterelay.appleid.com"))
	f.tokens.Disabled = []idtoken.Provider{idtoken.Apple}
	if _, err := f.svc.ProviderSignIn(ctx, idtoken.Apple, apple); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("disabled: got %v", err)
	}
}
