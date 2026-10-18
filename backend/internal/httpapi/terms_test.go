package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

func (a *api) sessionAccount(tok mobileTokens) map[string]any {
	a.t.Helper()
	r := a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...)
	var out struct {
		Account map[string]any `json:"account"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &out); err != nil {
		a.t.Fatal(err)
	}
	return out.Account
}

func TestProviderSignUpNeedsTheCurrentTermsVersion(t *testing.T) {
	a := newAPI(t)
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", map[string]any{"provider": "google", "id_token": a.googleToken("g-1", "ana@gmail.com"), "client": "mobile"}), "signup_required")
	if r := a.do(http.MethodPost, "/v1/sessions/provider/signup", map[string]any{"ticket": b.Ticket, "adult_declaration": true, "client": "mobile"}); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("missing: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/sessions/provider/signup", map[string]any{"ticket": b.Ticket, "adult_declaration": true, "terms_version": "2020-01-01", "client": "mobile"}); r.Code != http.StatusConflict || r.problemCode() != "terms_outdated" {
		t.Fatalf("old: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/sessions/provider/signup", map[string]any{"ticket": b.Ticket, "adult_declaration": true, "terms_version": "2026-10-17", "client": "mobile"}); r.Code != http.StatusCreated {
		t.Fatalf("current: %d", r.Code)
	}
}

func TestAcceptTermsRecordsTheAcceptanceAndTheSessionReportsIt(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	if got := a.sessionAccount(tok)["terms_accepted"]; got != true {
		t.Fatalf("signed up with the terms, terms_accepted = %v", got)
	}
	a.exec(`UPDATE accounts SET terms_version = NULL, terms_accepted_at = NULL`)
	if got := a.sessionAccount(tok)["terms_accepted"]; got != false {
		t.Fatalf("before accepting, terms_accepted = %v", got)
	}
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": "2020-01-01"}, bearer(tok)...); r.Code != http.StatusConflict || r.problemCode() != "terms_outdated" {
		t.Fatalf("old: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{}, bearer(tok)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("empty: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": "2026-10-17"}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("current: %d", r.Code)
	}
	if got := a.sessionAccount(tok)["terms_accepted"]; got != true {
		t.Fatalf("after accepting, terms_accepted = %v", got)
	}
}

func TestASuspendedAccountCanAcceptTheTerms(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("bia@example.com")
	tok := a.signInMobile("bia@example.com")
	a.markSuspended(a.accountID(tok))
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": "2026-10-17"}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("suspended: %d %q", r.Code, r.problemCode())
	}
}
