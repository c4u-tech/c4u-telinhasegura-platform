package httpapi_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestWebSignInSetsAHardenedCookieAndReturnsCSRF(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ana@example.com", "password": goodPassword, "client": "web"})
	if r.Code != http.StatusCreated {
		t.Fatalf("%d %s", r.Code, r.Body)
	}
	set := r.Header().Get("Set-Cookie")
	for _, want := range []string{"__Host-ts_session=", "Path=/", "HttpOnly", "Secure", "SameSite=Lax"} {
		if !strings.Contains(set, want) {
			t.Errorf("Set-Cookie %q lacks %q", set, want)
		}
	}
	if strings.Contains(set, "Domain=") {
		t.Error("__Host- cookie must not carry Domain")
	}
	if !strings.Contains(r.Body.String(), `"csrf_token":"`) {
		t.Fatalf("no CSRF token in %s", r.Body)
	}
}

func TestMobileSignInReturnsTokensAndNoCookie(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ana@example.com", "password": goodPassword, "client": "mobile"})
	if r.Header().Get("Set-Cookie") != "" {
		t.Fatal("mobile sign-in set a cookie")
	}
	for _, field := range []string{`"access_token":"`, `"refresh_token":"`, `"access_expires_at":"2026-10-02T12:15:00Z"`} {
		if !strings.Contains(r.Body.String(), field) {
			t.Errorf("body %s lacks %s", r.Body, field)
		}
	}
}

func TestSignInFailuresAreIndistinguishable(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	wrong := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ana@example.com", "password": "outra senha longa o bastante", "client": "web"})
	ghost := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ghost@example.com", "password": goodPassword, "client": "web"})
	if wrong.Code != http.StatusUnauthorized || wrong.problemCode() != "invalid_credentials" {
		t.Fatalf("wrong password: %d %q", wrong.Code, wrong.problemCode())
	}
	if wrong.Body.String() != ghost.Body.String() || wrong.Code != ghost.Code {
		t.Fatalf("responses differ: %s vs %s", wrong.Body, ghost.Body)
	}
}

func TestSignInRejectsUnknownClients(t *testing.T) {
	a := newAPI(t)
	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "a@b.co", "password": goodPassword, "client": "tv"})
	if r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("%d %q", r.Code, r.problemCode())
	}
}

func TestCurrentSessionReportsUnverifiedEmail(t *testing.T) {
	a := newAPI(t)
	a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com"))
	cookie, csrf := a.signInWeb("ana@example.com")
	r := a.do(http.MethodGet, "/v1/session", nil, "Cookie", cookie)
	if r.Code != http.StatusOK {
		t.Fatalf("%d %s", r.Code, r.Body)
	}
	var body struct {
		Account struct {
			Email         string `json:"email"`
			EmailVerified bool   `json:"email_verified"`
		} `json:"account"`
		Session struct {
			Client string `json:"client"`
			CSRF   string `json:"csrf_token"`
		} `json:"session"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &body)
	if body.Account.Email != "ana@example.com" || body.Account.EmailVerified || body.Session.Client != "web" || body.Session.CSRF != csrf {
		t.Fatalf("body %s", r.Body)
	}
}

func TestUnsafeCookieRequestsNeedTheCSRFHeader(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, csrf := a.signInWeb("ana@example.com")

	if r := a.do(http.MethodDelete, "/v1/session", nil, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("without header: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodDelete, "/v1/session", nil, "Cookie", cookie, "X-CSRF-Token", "wrong"); r.problemCode() != "csrf_failed" {
		t.Fatalf("wrong header: %q", r.problemCode())
	}
	r := a.do(http.MethodDelete, "/v1/session", nil, "Cookie", cookie, "X-CSRF-Token", csrf)
	if r.Code != http.StatusNoContent {
		t.Fatalf("sign-out: %d %s", r.Code, r.Body)
	}
	if !strings.Contains(r.Header().Get("Set-Cookie"), "Max-Age=0") {
		t.Fatalf("cookie not expired: %q", r.Header().Get("Set-Cookie"))
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, "Cookie", cookie); r.Code != http.StatusUnauthorized || r.problemCode() != "unauthenticated" {
		t.Fatalf("after sign-out: %d %q", r.Code, r.problemCode())
	}
}

func TestRefreshRotationAndReuse(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	a.now = a.now.Add(16 * time.Minute)

	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...); r.problemCode() != "unauthenticated" {
		t.Fatalf("expired access token: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken})
	if r.Code != http.StatusOK {
		t.Fatalf("refresh: %d %s", r.Code, r.Body)
	}
	var next mobileTokens
	_ = json.Unmarshal(r.Body.Bytes(), &next)
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(next)...); r.Code != http.StatusOK {
		t.Fatalf("new access token: %d", r.Code)
	}
	reuse := a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken})
	if reuse.Code != http.StatusUnauthorized || reuse.problemCode() != "invalid_token" {
		t.Fatalf("reuse: %d %q", reuse.Code, reuse.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(next)...); r.Code != http.StatusUnauthorized {
		t.Fatal("session survived refresh reuse")
	}
}

func TestSessionListAndRevocation(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	a.signUpVerified("bia@example.com")
	phone := a.signInMobile("ana@example.com")
	tablet := a.signInMobile("ana@example.com")
	bia := a.signInMobile("bia@example.com")

	r := a.do(http.MethodGet, "/v1/sessions", nil, bearer(phone)...)
	body := r.Body.String()
	if r.Code != http.StatusOK || strings.Count(body, `"id":`) != 2 || !strings.Contains(body, `"current":true`) {
		t.Fatalf("list: %d %s", r.Code, body)
	}
	for _, leak := range []string{phone.AccessToken, phone.RefreshToken, "192.0.2"} {
		if strings.Contains(body, leak) {
			t.Fatalf("list leaks %q", leak)
		}
	}

	if r := a.do(http.MethodDelete, "/v1/sessions/"+bia.SessionID, nil, bearer(phone)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("revoking another account's session: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodDelete, "/v1/sessions/"+tablet.SessionID, nil, bearer(phone)...); r.Code != http.StatusNoContent {
		t.Fatalf("revoke: %d", r.Code)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(tablet)...); r.Code != http.StatusUnauthorized {
		t.Fatal("revoked session still works")
	}
	if r := a.do(http.MethodDelete, "/v1/sessions?scope=everything", nil, bearer(phone)...); r.problemCode() != "validation" {
		t.Fatalf("bad scope: %q", r.problemCode())
	}
	if r := a.do(http.MethodDelete, "/v1/sessions?scope=all", nil, bearer(phone)...); r.Code != http.StatusNoContent {
		t.Fatalf("revoke all: %d", r.Code)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(phone)...); r.Code != http.StatusUnauthorized {
		t.Fatal("scope=all spared the current session")
	}
}

func TestFailedSignInsAnswer429WithRetryAfter(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	wrong := map[string]string{"email": "ana@example.com", "password": "outra senha longa o bastante", "client": "web"}
	for range 5 {
		a.do(http.MethodPost, "/v1/sessions", wrong)
	}
	r := a.do(http.MethodPost, "/v1/sessions", wrong)
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") != "1" {
		t.Fatalf("%d %q Retry-After=%q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}
}

func TestReauthEndpoint(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	if r := a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": "outra senha longa o bastante"}, bearer(tok)...); r.problemCode() != "invalid_credentials" {
		t.Fatalf("wrong password: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("reauth: %d %s", r.Code, r.Body)
	}
}

func TestSignInRefusesANonJSONContentType(t *testing.T) { // login CSRF via a text/plain form
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	body := `{"email":"ana@example.com","password":"` + goodPassword + `","client":"web"}`
	r := a.do(http.MethodPost, "/v1/sessions", body, "Content-Type", "text/plain")
	if r.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("%d %s, want 415", r.Code, r.Body)
	}
	if r.problemCode() != "validation" {
		t.Fatalf("code %q", r.problemCode())
	}
	if r.Header().Get("Set-Cookie") != "" {
		t.Fatal("a refused request set a cookie")
	}
}
