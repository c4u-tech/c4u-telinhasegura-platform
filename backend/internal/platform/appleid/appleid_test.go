package appleid_test

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/appleid"
)

func newKey(t *testing.T) (*ecdsa.PrivateKey, string) {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(k)
	if err != nil {
		t.Fatal(err)
	}
	return k, string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
}

var at = time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)

type apple struct {
	srv        *httptest.Server
	forms      map[string][]map[string]string // path -> forms
	tokenCode  int
	tokenBody  string
	revokeCode int
}

func newApple(t *testing.T) *apple {
	a := &apple{forms: map[string][]map[string]string{}, tokenCode: 200,
		tokenBody: `{"access_token":"at","refresh_token":"rt","id_token":"x","token_type":"Bearer","expires_in":3600}`, revokeCode: 200}
	a.srv = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		f := map[string]string{}
		for k := range r.PostForm {
			f[k] = r.PostForm.Get(k)
		}
		a.forms[r.URL.Path] = append(a.forms[r.URL.Path], f)
		switch r.URL.Path {
		case "/auth/token":
			w.WriteHeader(a.tokenCode)
			_, _ = w.Write([]byte(a.tokenBody))
		case "/auth/revoke":
			w.WriteHeader(a.revokeCode)
		}
	}))
	t.Cleanup(a.srv.Close)
	return a
}

func (a *apple) client(k *ecdsa.PrivateKey) *appleid.Client {
	return &appleid.Client{HTTP: a.srv.Client(), BaseURL: a.srv.URL, TeamID: "TEAM123456", KeyID: "KEY1234567", Key: k, Now: func() time.Time { return at }}
}

func TestRevokeExchangesThenRevokes(t *testing.T) {
	k, _ := newKey(t)
	a := newApple(t)
	if err := a.client(k).Revoke(context.Background(), "tech.coding4u.telinhasegura", "the-code", ""); err != nil {
		t.Fatal(err)
	}
	tok := a.forms["/auth/token"][0]
	if tok["grant_type"] != "authorization_code" || tok["code"] != "the-code" || tok["client_id"] != "tech.coding4u.telinhasegura" {
		t.Fatalf("token form %v", tok)
	}
	rev := a.forms["/auth/revoke"][0]
	if rev["token"] != "rt" || rev["token_type_hint"] != "refresh_token" || rev["client_id"] != "tech.coding4u.telinhasegura" {
		t.Fatalf("revoke form %v", rev)
	}
	if _, ok := tok["redirect_uri"]; ok {
		t.Fatalf("a native code was exchanged with a redirect_uri: %v", tok)
	}
	verifySecret(t, &k.PublicKey, tok["client_secret"], "tech.coding4u.telinhasegura")
	verifySecret(t, &k.PublicKey, rev["client_secret"], "tech.coding4u.telinhasegura")
}

// verifySecret checks the ES256 JWT Apple expects (Client secret).
func verifySecret(t *testing.T, pub *ecdsa.PublicKey, jwt, sub string) {
	t.Helper()
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		t.Fatalf("not a JWT: %q", jwt)
	}
	var hdr map[string]string
	var claims map[string]any
	dec := func(s string, v any) {
		b, err := base64.RawURLEncoding.DecodeString(s)
		if err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal(b, v); err != nil {
			t.Fatal(err)
		}
	}
	dec(parts[0], &hdr)
	dec(parts[1], &claims)
	if hdr["alg"] != "ES256" || hdr["kid"] != "KEY1234567" {
		t.Fatalf("header %v", hdr)
	}
	if claims["iss"] != "TEAM123456" || claims["aud"] != "https://appleid.apple.com" || claims["sub"] != sub ||
		claims["iat"].(float64) != float64(at.Unix()) || claims["exp"].(float64) != float64(at.Add(5*time.Minute).Unix()) {
		t.Fatalf("claims %v", claims)
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		t.Fatalf("signature %d bytes, %v", len(sig), err)
	}
	h := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, h[:], r, s) {
		t.Fatal("signature does not verify")
	}
}

func TestRevokeInvalidGrant(t *testing.T) {
	k, _ := newKey(t)
	a := newApple(t)
	a.tokenCode, a.tokenBody = 400, `{"error":"invalid_grant"}`
	err := a.client(k).Revoke(context.Background(), "c", "stale", "")
	if !errors.Is(err, appleid.ErrInvalidGrant) {
		t.Fatalf("err = %v", err)
	}
	if len(a.forms["/auth/revoke"]) != 0 {
		t.Fatal("revoked after a rejected code")
	}
}

func TestRevokeClassifiesFailures(t *testing.T) {
	k, _ := newKey(t)
	a := newApple(t)
	a.tokenCode, a.tokenBody = 503, `oops`
	err := a.client(k).Revoke(context.Background(), "c", "code", "")
	if err == nil || errors.Is(err, appleid.ErrInvalidGrant) || appleid.Class(err) != "apple 5xx" {
		t.Fatalf("err = %v, class %q", err, appleid.Class(err))
	}
	a.tokenCode, a.tokenBody, a.revokeCode = 200, `{"refresh_token":"rt"}`, 400
	err = a.client(k).Revoke(context.Background(), "c", "code", "")
	if err == nil || appleid.Class(err) != "apple 4xx" {
		t.Fatalf("revoke failure: %v, class %q", err, appleid.Class(err))
	}
	a.tokenCode, a.tokenBody = 400, `{"error":"invalid_client"}`
	if err := a.client(k).Revoke(context.Background(), "c", "code", ""); errors.Is(err, appleid.ErrInvalidGrant) || appleid.Class(err) != "apple 4xx" {
		t.Fatalf("invalid_client: %v", err)
	}
	a.srv.Close()
	if err := a.client(k).Revoke(context.Background(), "c", "code", ""); appleid.Class(err) != "network" {
		t.Fatalf("closed server: %v, class %q", err, appleid.Class(err))
	}
}

func TestErrorsNeverCarryTheBody(t *testing.T) { // Security
	k, _ := newKey(t)
	a := newApple(t)
	a.tokenCode, a.tokenBody = 400, `{"error":"invalid_grant","secret":"the-code"}`
	err := a.client(k).Revoke(context.Background(), "c", "the-code", "")
	if strings.Contains(err.Error(), "the-code") {
		t.Fatalf("error leaks: %v", err)
	}
}

func TestParseKey(t *testing.T) {
	_, p := newKey(t)
	if _, err := appleid.ParseKey(p); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{"", "not a pem", strings.Replace(p, "PRIVATE KEY", "PUBLIC KEY", 2)} {
		if _, err := appleid.ParseKey(bad); err == nil {
			t.Fatalf("accepted %q", bad)
		}
	}
	k384, _ := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(k384)
	if _, err := appleid.ParseKey(string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))); err == nil {
		t.Fatal("accepted a P-384 key")
	}
}

func TestParseKeyAcceptsEscapedNewlines(t *testing.T) {
	_, p := newKey(t)
	if _, err := appleid.ParseKey(strings.ReplaceAll(p, "\n", `\n`)); err != nil {
		t.Fatal(err)
	}
}

func TestParseKeyErrorNeverEchoesTheKey(t *testing.T) {
	_, err := appleid.ParseKey("-----BEGIN PRIVATE KEY-----\nc2VjcmV0\n-----END PRIVATE KEY-----")
	if err == nil || strings.Contains(err.Error(), "c2VjcmV0") {
		t.Fatalf("err = %v", err)
	}
}

// A code from Apple's web flow (the Services ID, on the web and through the
// Android relay) is exchanged with the redirect_uri it was issued to; the
// revocation itself takes none.
func TestRevokeSendsTheRedirectURIOfAWebCode(t *testing.T) {
	k, _ := newKey(t)
	a := newApple(t)
	const redirect = "https://api.example.test/v1/oauth/apple/callback"
	if err := a.client(k).Revoke(context.Background(), "tech.coding4u.telinhasegura.web", "the-code", redirect); err != nil {
		t.Fatal(err)
	}
	if tok := a.forms["/auth/token"][0]; tok["redirect_uri"] != redirect || tok["client_id"] != "tech.coding4u.telinhasegura.web" {
		t.Fatalf("token form %v", tok)
	}
	if _, ok := a.forms["/auth/revoke"][0]["redirect_uri"]; ok {
		t.Fatalf("revoke form %v", a.forms["/auth/revoke"][0])
	}
}
