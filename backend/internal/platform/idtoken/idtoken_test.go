package idtoken_test

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"errors"
	"maps"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

var now = time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC)

// keyServer serves its keys as a JWKS and signs tokens with them, standing
// in for Google's and Apple's key endpoints.
type keyServer struct {
	t    *testing.T
	srv  *httptest.Server
	mu   sync.Mutex
	keys map[string]*rsa.PrivateKey
}

func newKeyServer(t *testing.T) *keyServer {
	ks := &keyServer{t: t, keys: map[string]*rsa.PrivateKey{}}
	ks.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		ks.mu.Lock()
		defer ks.mu.Unlock()
		var set jose.JSONWebKeySet
		for kid, k := range ks.keys {
			set.Keys = append(set.Keys, jose.JSONWebKey{Key: &k.PublicKey, KeyID: kid, Algorithm: string(jose.RS256), Use: "sig"})
		}
		_ = json.NewEncoder(w).Encode(set)
	}))
	t.Cleanup(ks.srv.Close)
	ks.addKey("k1")
	return ks
}

func (ks *keyServer) addKey(kid string) {
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		ks.t.Fatal(err)
	}
	ks.mu.Lock()
	ks.keys[kid] = k
	ks.mu.Unlock()
}

func (ks *keyServer) sign(kid string, claims map[string]any) string {
	ks.t.Helper()
	ks.mu.Lock()
	k := ks.keys[kid]
	ks.mu.Unlock()
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: jose.JSONWebKey{Key: k, KeyID: kid}},
		(&jose.SignerOptions{}).WithType("JWT"))
	if err != nil {
		ks.t.Fatal(err)
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		ks.t.Fatal(err)
	}
	obj, err := signer.Sign(payload)
	if err != nil {
		ks.t.Fatal(err)
	}
	raw, err := obj.CompactSerialize()
	if err != nil {
		ks.t.Fatal(err)
	}
	return raw
}

func newVerifier(ks *keyServer, appleIDs ...string) *idtoken.OIDC {
	if appleIDs == nil {
		appleIDs = []string{"br.com.coding4u.telinhaSegura", "br.com.coding4u.telinhaSegura.web"}
	}
	return idtoken.NewOIDC(ks.srv.Client(), func() time.Time { return now }, map[idtoken.Provider]idtoken.ProviderConfig{
		idtoken.Google: {Issuer: "https://accounts.google.com", JWKSURL: ks.srv.URL, ClientIDs: []string{"web-client"}},
		idtoken.Apple:  {Issuer: "https://appleid.apple.com", JWKSURL: ks.srv.URL, ClientIDs: appleIDs},
	})
}

func googleClaims() map[string]any {
	return map[string]any{
		"iss": "https://accounts.google.com", "aud": "web-client", "sub": "g-123",
		"email": "ana@gmail.com", "email_verified": true,
		"iat": now.Add(-time.Minute).Unix(), "exp": now.Add(time.Hour).Unix(),
	}
}

func appleClaims() map[string]any {
	return map[string]any{
		"iss": "https://appleid.apple.com", "aud": "br.com.coding4u.telinhaSegura", "sub": "a-123",
		"email": "x1y2@privaterelay.appleid.com", "email_verified": "true", "is_private_email": "true",
		"iat": now.Add(-time.Minute).Unix(), "exp": now.Add(time.Hour).Unix(),
	}
}

// with copies c and sets each key/value pair; a nil value deletes the key.
func with(c map[string]any, kv ...any) map[string]any {
	out := maps.Clone(c)
	for i := 0; i+1 < len(kv); i += 2 {
		if kv[i+1] == nil {
			delete(out, kv[i].(string))
		} else {
			out[kv[i].(string)] = kv[i+1]
		}
	}
	return out
}

func TestAcceptsAGoogleToken(t *testing.T) {
	ks := newKeyServer(t)
	c, err := newVerifier(ks).Verify(context.Background(), idtoken.Google, ks.sign("k1", googleClaims()))
	if err != nil {
		t.Fatal(err)
	}
	if !c.ExpiresAt.Equal(now.Add(time.Hour)) {
		t.Fatalf("expiry %v", c.ExpiresAt)
	}
	c.ExpiresAt = time.Time{} // compared above with Equal: go-oidc returns local time
	want := idtoken.Claims{Subject: "g-123", Audience: "web-client", Email: "ana@gmail.com", EmailVerified: true, EmailAuthoritative: true}
	if c != want {
		t.Fatalf("got %+v, want %+v", c, want)
	}
}

func TestRejectsTokensThatFailAnyCheck(t *testing.T) {
	ks := newKeyServer(t)
	stranger := newKeyServer(t)
	good := googleClaims()
	cases := map[string]string{
		"wrong audience":    ks.sign("k1", with(good, "aud", "someone-else")),
		"wrong issuer":      ks.sign("k1", with(good, "iss", "https://evil.example")),
		"expired":           ks.sign("k1", with(good, "exp", now.Add(-time.Second).Unix())),
		"issued 6 min ago":  ks.sign("k1", with(good, "iat", now.Add(-6*time.Minute).Unix())),
		"issued in future":  ks.sign("k1", with(good, "iat", now.Add(2*time.Minute).Unix())),
		"no iat":            ks.sign("k1", with(good, "iat", nil)),
		"no subject":        ks.sign("k1", with(good, "sub", nil)),
		"foreign signature": stranger.sign("k1", good),
		"not a jwt":         "abc.def.ghi",
	}
	v := newVerifier(ks)
	for name, raw := range cases {
		if _, err := v.Verify(context.Background(), idtoken.Google, raw); !errors.Is(err, idtoken.ErrInvalid) {
			t.Errorf("%s: got %v, want ErrInvalid", name, err)
		}
	}
}

func TestAcceptsGoogleIssuerWithoutScheme(t *testing.T) {
	ks := newKeyServer(t)
	raw := ks.sign("k1", with(googleClaims(), "iss", "accounts.google.com"))
	if _, err := newVerifier(ks).Verify(context.Background(), idtoken.Google, raw); err != nil {
		t.Fatal(err)
	}
}

func TestAcceptsAnAudienceListContainingAClientID(t *testing.T) {
	ks := newKeyServer(t)
	raw := ks.sign("k1", with(googleClaims(), "aud", []string{"android-client", "web-client"}))
	if _, err := newVerifier(ks).Verify(context.Background(), idtoken.Google, raw); err != nil {
		t.Fatal(err)
	}
}

func TestReadsAppleBooleansSentAsStrings(t *testing.T) {
	ks := newKeyServer(t)
	v := newVerifier(ks)
	c, err := v.Verify(context.Background(), idtoken.Apple, ks.sign("k1", appleClaims()))
	if err != nil || !c.EmailVerified || !c.EmailAuthoritative {
		t.Fatalf("string true: %+v, %v", c, err)
	}
	raw := ks.sign("k1", with(appleClaims(), "sub", "a-2", "email_verified", "false", "is_private_email", false))
	c, err = v.Verify(context.Background(), idtoken.Apple, raw)
	if err != nil || c.EmailVerified || c.EmailAuthoritative {
		t.Fatalf("false: %+v, %v", c, err)
	}
}

func TestEmailAuthority(t *testing.T) {
	ks := newKeyServer(t)
	v := newVerifier(ks)
	cases := []struct {
		name   string
		p      idtoken.Provider
		claims map[string]any
		want   bool
	}{
		{"gmail", idtoken.Google, googleClaims(), true},
		{"googlemail", idtoken.Google, with(googleClaims(), "email", "ana@googlemail.com"), true},
		{"gmail upper case", idtoken.Google, with(googleClaims(), "email", "Ana@GMAIL.com"), true},
		{"other domain", idtoken.Google, with(googleClaims(), "email", "ana@empresa.com.br"), false},
		{"workspace", idtoken.Google, with(googleClaims(), "email", "ana@empresa.com.br", "hd", "empresa.com.br"), true},
		{"apple relay", idtoken.Apple, appleClaims(), true},
		{"apple own address", idtoken.Apple, with(appleClaims(), "email", "ana@icloud.com", "is_private_email", nil), false},
	}
	for _, tc := range cases {
		c, err := v.Verify(context.Background(), tc.p, ks.sign("k1", tc.claims))
		if err != nil || c.EmailAuthoritative != tc.want {
			t.Errorf("%s: authoritative=%v err=%v, want %v", tc.name, c.EmailAuthoritative, err, tc.want)
		}
	}
}

func TestRefetchesKeysForAnUnknownKid(t *testing.T) {
	ks := newKeyServer(t)
	v := newVerifier(ks)
	if _, err := v.Verify(context.Background(), idtoken.Google, ks.sign("k1", googleClaims())); err != nil {
		t.Fatal(err)
	}
	ks.addKey("k2") // the provider rotates its keys after the first fetch
	if _, err := v.Verify(context.Background(), idtoken.Google, ks.sign("k2", googleClaims())); err != nil {
		t.Fatalf("rotated key: %v", err)
	}
}

func TestProviderWithoutClientIDsIsDisabled(t *testing.T) {
	ks := newKeyServer(t)
	_, err := newVerifier(ks, []string{}...).Verify(context.Background(), idtoken.Apple, ks.sign("k1", appleClaims()))
	if !errors.Is(err, idtoken.ErrDisabled) {
		t.Fatalf("got %v, want ErrDisabled", err)
	}
}

func TestVerifyReportsTheMatchingAudience(t *testing.T) {
	ks := newKeyServer(t)
	v := newVerifier(ks)
	raw := ks.sign("k1", with(appleClaims(), "aud", []string{"other", "br.com.coding4u.telinhaSegura"}))
	c, err := v.Verify(context.Background(), idtoken.Apple, raw)
	if err != nil {
		t.Fatal(err)
	}
	if c.Audience != "br.com.coding4u.telinhaSegura" {
		t.Fatalf("got Audience %q, want %q", c.Audience, "br.com.coding4u.telinhaSegura")
	}
}
