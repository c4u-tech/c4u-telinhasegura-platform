package httpapi_test

import (
	"net/http"
	"testing"
	"time"
)

const newPassword = "uma senha nova e comprida"

func TestChangePasswordEndsOtherSessions(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	phone := a.signInMobile("ana@example.com")
	tablet := a.signInMobile("ana@example.com")

	wrong := a.do(http.MethodPost, "/v1/account/password", map[string]string{"current_password": newPassword, "new_password": newPassword}, bearer(phone)...)
	if wrong.Code != http.StatusUnauthorized || wrong.problemCode() != "invalid_credentials" {
		t.Fatalf("wrong current: %d %q", wrong.Code, wrong.problemCode())
	}
	r := a.do(http.MethodPost, "/v1/account/password", map[string]string{"current_password": goodPassword, "new_password": newPassword}, bearer(phone)...)
	if r.Code != http.StatusNoContent {
		t.Fatalf("change: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(phone)...); r.Code != http.StatusOK {
		t.Fatal("the session that changed the password was ended")
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(tablet)...); r.Code != http.StatusUnauthorized {
		t.Fatal("another session survived the password change")
	}
}

func TestEmailChangeRequiresRecentReauth(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	a.now = a.now.Add(6 * time.Minute)
	refreshed := a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken})
	tok = decodeTokens(t, refreshed)

	body := map[string]string{"new_email": "nova@example.com"}
	if r := a.do(http.MethodPost, "/v1/account/email", body, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale session: %d %q", r.Code, r.problemCode())
	}
	a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(tok)...)
	if r := a.do(http.MethodPost, "/v1/account/email", body, bearer(tok)...); r.Code != http.StatusAccepted {
		t.Fatalf("after reauth: %d %s", r.Code, r.Body)
	}
	if len(a.mail.To("nova@example.com")) != 1 {
		t.Fatal("new address got no verification")
	}
}

func TestPasswordResetEndpoints(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	phone := a.signInMobile("ana@example.com")

	known := a.do(http.MethodPost, "/v1/password-resets", map[string]string{"email": "ana@example.com"})
	ghost := a.do(http.MethodPost, "/v1/password-resets", map[string]string{"email": "ghost@example.com"})
	if known.Code != http.StatusAccepted || known.Body.String() != ghost.Body.String() || known.Code != ghost.Code {
		t.Fatalf("responses differ: %d %s / %d %s", known.Code, known.Body, ghost.Code, ghost.Body)
	}
	if r := a.do(http.MethodPost, "/v1/password-resets/confirm", map[string]string{"token": "nope", "new_password": newPassword}); r.Code != http.StatusBadRequest || r.problemCode() != "invalid_token" {
		t.Fatalf("bad token: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodPost, "/v1/password-resets/confirm", map[string]string{"token": a.lastToken("ana@example.com"), "new_password": newPassword})
	if r.Code != http.StatusNoContent {
		t.Fatalf("confirm: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(phone)...); r.Code != http.StatusUnauthorized {
		t.Fatal("a session survived the reset")
	}
}
