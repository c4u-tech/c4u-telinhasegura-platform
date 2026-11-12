package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
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
	if r := a.do(http.MethodPost, "/v1/sessions/provider/signup", map[string]any{"ticket": b.Ticket, "adult_declaration": true, "terms_version": identity.TermsVersion, "client": "mobile"}); r.Code != http.StatusCreated {
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
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": identity.TermsVersion}, bearer(tok)...); r.Code != http.StatusNoContent {
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
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": identity.TermsVersion}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("suspended: %d %q", r.Code, r.problemCode())
	}
}

// An account on the previous terms counts as accepted, and the previous
// app may still sign up and accept with them, until the grace ends.
func TestPreviousTermsCountUntilTheGraceEndsOverHTTP(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	a.exec(`UPDATE accounts SET terms_version = $1`, identity.PreviousTermsVersion)
	if got := a.sessionAccount(tok)["terms_accepted"]; got != true {
		t.Fatalf("previous terms during the grace, terms_accepted = %v", got)
	}
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": identity.PreviousTermsVersion}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("accept during the grace: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/accounts", map[string]any{"email": "bia@example.com", "password": goodPassword, "adult_declaration": true, "terms_version": identity.PreviousTermsVersion}); r.Code != http.StatusAccepted {
		t.Fatalf("sign-up during the grace: %d %s", r.Code, r.Body)
	}

	a.now = graceEnd
	tok = a.signInMobile("ana@example.com")
	if got := a.sessionAccount(tok)["terms_accepted"]; got != false {
		t.Fatalf("previous terms after the grace, terms_accepted = %v", got)
	}
	if r := a.do(http.MethodPost, "/v1/account/terms", map[string]any{"terms_version": identity.PreviousTermsVersion}, bearer(tok)...); r.Code != http.StatusConflict || r.problemCode() != "terms_outdated" {
		t.Fatalf("accept after the grace: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/accounts", map[string]any{"email": "caio@example.com", "password": goodPassword, "adult_declaration": true, "terms_version": identity.PreviousTermsVersion}); r.Code != http.StatusConflict || r.problemCode() != "terms_outdated" {
		t.Fatalf("sign-up after the grace: %d %s", r.Code, r.Body)
	}
}
