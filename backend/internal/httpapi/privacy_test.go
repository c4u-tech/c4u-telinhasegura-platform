package httpapi_test

import (
	"encoding/json"
	"net/http"
	"slices"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/appleid"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

func TestExportOverHTTP(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")

	r := a.do(http.MethodGet, "/v1/account/export", nil, bearer(tok)...)
	if r.Code != http.StatusOK {
		t.Fatalf("export: %d %s", r.Code, r.Body)
	}
	h := r.Header()
	if h.Get("Content-Type") != "application/json" || h.Get("Cache-Control") != "no-store" ||
		h.Get("Content-Disposition") != `attachment; filename="telinhasegura-dados-2026-10-02.json"` {
		t.Fatalf("headers: %v", h)
	}
	var doc struct {
		Format  string `json:"format"`
		Account struct {
			Email string `json:"email"`
		} `json:"account"`
		Family any `json:"family"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &doc); err != nil || doc.Format != "telinhasegura.export/1" ||
		doc.Account.Email != "ana@example.com" || doc.Family != nil {
		t.Fatalf("document: %+v %v", doc, err)
	}
	for range 4 {
		a.do(http.MethodGet, "/v1/account/export", nil, bearer(tok)...)
	}
	if r := a.do(http.MethodGet, "/v1/account/export", nil, bearer(tok)...); r.Code != http.StatusTooManyRequests ||
		r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") == "" {
		t.Fatalf("sixth export: %d %q", r.Code, r.problemCode())
	}
}

func TestPrivacyRoutesNeedAFreshReauth(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	a.now = a.now.Add(6 * time.Minute)
	tok = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}))
	for _, m := range []string{http.MethodGet + " /v1/account/export", http.MethodDelete + " /v1/account"} {
		method, path := sweepTarget(m)
		if r := a.do(method, path, nil, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
			t.Errorf("%s stale: %d %q", m, r.Code, r.problemCode())
		}
	}
	a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(tok)...)
	if r := a.do(http.MethodGet, "/v1/account/export", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("after reauth: %d %s", r.Code, r.Body)
	}
}

func TestDeleteAccountOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	bia := a.joinFamily(ana, "bia@example.com")
	oldID := a.accountID(bia)

	if r := a.do(http.MethodDelete, "/v1/account", nil, bearer(ana)...); r.Code != http.StatusConflict || r.problemCode() != "owner_must_transfer" {
		t.Fatalf("owner: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodDelete, "/v1/account", nil, bearer(bia)...); r.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(bia)...); r.Code != http.StatusUnauthorized || r.problemCode() != "unauthenticated" {
		t.Fatalf("old access token: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": bia.RefreshToken}); r.Code != http.StatusUnauthorized || r.problemCode() != "invalid_token" {
		t.Fatalf("old refresh token: %d %q", r.Code, r.problemCode())
	}
	view := decodeFamily(t, a.do(http.MethodGet, "/v1/family", nil, bearer(ana)...))
	if len(view.Members) != 1 {
		t.Fatalf("the family keeps %d members", len(view.Members))
	}
	a.signUpVerified("bia@example.com")
	if id := a.accountID(a.signInMobile("bia@example.com")); id == oldID {
		t.Fatal("a new signup reused the deleted account")
	}
}

func TestDeleteAccountOnTheWeb(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, csrf := a.signInWeb("ana@example.com")
	if r := a.do(http.MethodDelete, "/v1/account", nil, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("without CSRF: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodDelete, "/v1/account", nil, "Cookie", cookie, "X-CSRF-Token", csrf)
	if r.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Code, r.Body)
	}
	expired := false
	for _, c := range r.Result().Cookies() {
		if c.Name == "__Host-ts_session" && c.MaxAge < 0 {
			expired = true
		}
	}
	if !expired {
		t.Fatal("the session cookie was not expired")
	}
}

func TestPrivacyAuditCarriesIDsOnly(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	a.do(http.MethodGet, "/v1/account/export", nil, bearer(tok)...)
	a.do(http.MethodDelete, "/v1/account", nil, bearer(tok)...)
	want := map[audit.Event]bool{audit.DataExported: false, audit.AccountDeleted: false}
	for _, e := range a.audit.Entries {
		if _, ok := want[e.Event]; !ok {
			continue
		}
		want[e.Event] = true
		if !uuidRE.MatchString(e.AccountID) {
			t.Errorf("%s carries %q, not an account ID", e.Event, e.AccountID)
		}
	}
	for e, seen := range want {
		if !seen {
			t.Errorf("no %s event", e)
		}
	}
}

func TestDeleteAccountWithoutBodyStillWorks(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	if r := a.do(http.MethodDelete, "/v1/account", nil, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Code, r.Body)
	}
}

func TestDeleteAppleAccountOverHTTP(t *testing.T) {
	a := newAPI(t)
	signUp := a.tokens.Issue(idtoken.Apple, idtoken.Claims{Subject: "a-ana", Email: "ana@icloud.com", EmailVerified: true, EmailAuthoritative: true})
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", map[string]string{"provider": "apple", "id_token": signUp, "client": "mobile"}), "signup_required")
	tok := decodeTokens(t, a.do(http.MethodPost, "/v1/sessions/provider/signup",
		map[string]any{"ticket": b.Ticket, "adult_declaration": true, "client": "mobile"}))
	id := a.accountID(tok)
	del := func(body any) resp { return a.do(http.MethodDelete, "/v1/account", body, bearer(tok)...) }
	cred := func(sub string) map[string]any {
		return map[string]any{"apple": map[string]string{
			"identity_token":     a.tokens.Issue(idtoken.Apple, idtoken.Claims{Subject: sub, Audience: "br.example.app"}),
			"authorization_code": "c",
		}}
	}

	if r := del(nil); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "apple_reauthorization_required" {
		t.Fatalf("no body: %d %q", r.Code, r.problemCode())
	}
	if r := del(cred("a-other")); r.Code != http.StatusForbidden || r.problemCode() != "apple_identity_mismatch" {
		t.Fatalf("mismatch: %d %q", r.Code, r.problemCode())
	}
	a.apple.Err = appleid.ErrInvalidGrant
	if r := del(cred("a-ana")); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "apple_authorization_invalid" {
		t.Fatalf("invalid grant: %d %q", r.Code, r.problemCode())
	}
	a.apple.Err = nil
	if r := del(map[string]any{"apple": map[string]string{"identity_token": "", "authorization_code": ""}}); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("empty credential: %d %q", r.Code, r.problemCode())
	}
	if r := del(cred("a-ana")); r.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Code, r.Body)
	}
	if n := a.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid`, id); n != 0 {
		t.Fatalf("the account remains (%d)", n)
	}
}

// A web-flow code carries the redirect URI it was issued to; the API passes
// an https one on to Apple and refuses anything else.
func TestDeleteAppleAccountSendsTheRedirectURI(t *testing.T) {
	a := newAPI(t)
	signUp := a.tokens.Issue(idtoken.Apple, idtoken.Claims{Subject: "a-ana", Email: "ana@icloud.com", EmailVerified: true, EmailAuthoritative: true})
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", map[string]string{"provider": "apple", "id_token": signUp, "client": "mobile"}), "signup_required")
	tok := decodeTokens(t, a.do(http.MethodPost, "/v1/sessions/provider/signup",
		map[string]any{"ticket": b.Ticket, "adult_declaration": true, "client": "mobile"}))
	del := func(redirect string) resp {
		return a.do(http.MethodDelete, "/v1/account", map[string]any{"apple": map[string]string{
			"identity_token":     a.tokens.Issue(idtoken.Apple, idtoken.Claims{Subject: "a-ana", Audience: "br.example.app.web"}),
			"authorization_code": "c",
			"redirect_uri":       redirect,
		}}, bearer(tok)...)
	}

	for _, bad := range []string{"http://api.example.test/v1/oauth/apple/callback", "app.example.test", "https://"} {
		if r := del(bad); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
			t.Fatalf("%q: %d %q", bad, r.Code, r.problemCode())
		}
	}
	if len(a.apple.Redirects) != 0 {
		t.Fatalf("revoked with a refused redirect: %v", a.apple.Redirects)
	}
	if r := del("https://api.example.test/v1/oauth/apple/callback"); r.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Code, r.Body)
	}
	if want := []string{"https://api.example.test/v1/oauth/apple/callback"}; !slices.Equal(a.apple.Redirects, want) {
		t.Fatalf("redirects %v", a.apple.Redirects)
	}
}
