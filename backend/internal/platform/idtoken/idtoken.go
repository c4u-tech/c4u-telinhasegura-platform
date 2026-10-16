// Package idtoken verifies the OpenID Connect ID tokens that Google and
// Apple hand to the app. Every provider-specific rule lives here, so the
// identity module sees only Claims.
package idtoken

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
)

type Provider string

const (
	Google Provider = "google"
	Apple  Provider = "apple"
)

var (
	ErrInvalid  = errors.New("idtoken: invalid token")
	ErrDisabled = errors.New("idtoken: provider not configured")
)

// MaxAge bounds how old an accepted token's iat may be.
const MaxAge = 5 * time.Minute

const maxClockSkew = time.Minute

type Claims struct {
	Subject            string
	Audience           string // the aud entry that matched a client ID: Apple's client_id for a code exchange
	Email              string
	EmailVerified      bool
	EmailAuthoritative bool // the provider controls the mailbox
	ExpiresAt          time.Time
}

type Verifier interface {
	Verify(ctx context.Context, p Provider, raw string) (Claims, error)
}

type ProviderConfig struct {
	Issuer    string
	JWKSURL   string
	ClientIDs []string // accepted aud values; none disables the provider
}

func GoogleConfig(clientIDs []string) ProviderConfig {
	return ProviderConfig{Issuer: "https://accounts.google.com", JWKSURL: "https://www.googleapis.com/oauth2/v3/certs", ClientIDs: clientIDs}
}

func AppleConfig(clientIDs []string) ProviderConfig {
	return ProviderConfig{Issuer: "https://appleid.apple.com", JWKSURL: "https://appleid.apple.com/auth/keys", ClientIDs: clientIDs}
}

// OIDC verifies with go-oidc against fixed JWKS URLs, without discovery.
// Its key sets cache keys and refetch on an unknown kid.
type OIDC struct {
	now       func() time.Time
	providers map[Provider]oidcProvider
}

type oidcProvider struct {
	verifier  *oidc.IDTokenVerifier
	clientIDs []string
}

func NewOIDC(client *http.Client, now func() time.Time, cfgs map[Provider]ProviderConfig) *OIDC {
	o := &OIDC{now: now, providers: map[Provider]oidcProvider{}}
	ctx := oidc.ClientContext(context.Background(), client)
	for p, c := range cfgs {
		if len(c.ClientIDs) == 0 {
			continue
		}
		keys := oidc.NewRemoteKeySet(ctx, c.JWKSURL)
		// aud is checked below against a list: Apple has two client IDs.
		o.providers[p] = oidcProvider{
			verifier:  oidc.NewVerifier(c.Issuer, keys, &oidc.Config{SkipClientIDCheck: true, Now: now}),
			clientIDs: c.ClientIDs,
		}
	}
	return o
}

func (o *OIDC) Verify(ctx context.Context, p Provider, raw string) (Claims, error) {
	pv, ok := o.providers[p]
	if !ok {
		return Claims{}, ErrDisabled
	}
	tok, err := pv.verifier.Verify(ctx, raw)
	if err != nil {
		return Claims{}, ErrInvalid
	}
	i := slices.IndexFunc(tok.Audience, func(a string) bool { return slices.Contains(pv.clientIDs, a) })
	if tok.Subject == "" || i < 0 {
		return Claims{}, ErrInvalid
	}
	now := o.now()
	if tok.IssuedAt.IsZero() || now.Sub(tok.IssuedAt) > MaxAge || tok.IssuedAt.Sub(now) > maxClockSkew {
		return Claims{}, ErrInvalid
	}
	var extra struct {
		Email         string   `json:"email"`
		EmailVerified flexBool `json:"email_verified"`
		PrivateEmail  flexBool `json:"is_private_email"`
		HostedDomain  string   `json:"hd"`
	}
	if err := tok.Claims(&extra); err != nil {
		return Claims{}, ErrInvalid
	}
	return Claims{
		Subject:            tok.Subject,
		Audience:           tok.Audience[i],
		Email:              extra.Email,
		EmailVerified:      bool(extra.EmailVerified),
		EmailAuthoritative: authoritative(p, extra.Email, extra.HostedDomain, bool(extra.PrivateEmail)),
		ExpiresAt:          tok.Expiry,
	}, nil
}

// authoritative follows Google's account-linking guidance: only Gmail and
// Workspace addresses are Google's to vouch for. Apple controls only its
// relay addresses.
func authoritative(p Provider, email, hostedDomain string, private bool) bool {
	switch p {
	case Google:
		e := strings.ToLower(email)
		return hostedDomain != "" || strings.HasSuffix(e, "@gmail.com") || strings.HasSuffix(e, "@googlemail.com")
	case Apple:
		return private
	}
	return false
}

// flexBool reads a JSON boolean that Apple may send as a string.
type flexBool bool

func (b *flexBool) UnmarshalJSON(data []byte) error {
	switch string(data) {
	case `true`, `"true"`:
		*b = true
	case `false`, `"false"`, `null`:
		*b = false
	default:
		return fmt.Errorf("idtoken: not a boolean: %s", data)
	}
	return nil
}
