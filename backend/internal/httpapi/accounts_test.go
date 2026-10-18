package httpapi_test

import (
	"net/http"
	"net/netip"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func TestSignUpAnswersIdenticallyForNewAndExistingEmails(t *testing.T) {
	a := newAPI(t)
	first := a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com"))
	second := a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com"))

	if first.Code != http.StatusAccepted || second.Code != http.StatusAccepted {
		t.Fatalf("statuses %d, %d; want 202, 202", first.Code, second.Code)
	}
	if first.Body.String() != second.Body.String() {
		t.Fatalf("bodies differ: %q vs %q", first.Body, second.Body)
	}
}

func TestSignUpProblems(t *testing.T) {
	a := newAPI(t)
	cases := []struct {
		name   string
		body   any
		status int
		code   string
	}{
		{"no adult declaration", map[string]any{"email": "a@b.co", "password": goodPassword, "adult_declaration": false, "terms_version": "2026-10-17"}, 422, "validation"},
		{"no terms version", map[string]any{"email": "a@b.co", "password": goodPassword, "adult_declaration": true}, 422, "validation"},
		{"outdated terms version", map[string]any{"email": "a@b.co", "password": goodPassword, "adult_declaration": true, "terms_version": "2020-01-01"}, 409, "terms_outdated"},
		{"short password", map[string]any{"email": "a@b.co", "password": "curta", "adult_declaration": true, "terms_version": "2026-10-17"}, 422, "weak_password"},
		{"malformed JSON", `{"email":`, 422, "validation"},
		{"unknown field", `{"email":"a@b.co","password":"uma senha longa o bastante","adult_declaration":true,"terms_version":"2026-10-17","role":"admin"}`, 422, "validation"},
		{"oversized body", `{"email":"` + strings.Repeat("a", 1<<20) + `"}`, 422, "validation"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := a.do(http.MethodPost, "/v1/accounts", c.body)
			if r.Code != c.status || r.problemCode() != c.code {
				t.Fatalf("got %d %q, want %d %q", r.Code, r.problemCode(), c.status, c.code)
			}
			if ct := r.Header().Get("Content-Type"); ct != "application/problem+json" {
				t.Fatalf("Content-Type %q", ct)
			}
		})
	}
}

func TestWeakPasswordProblemCarriesReasons(t *testing.T) {
	a := newAPI(t)
	r := a.do(http.MethodPost, "/v1/accounts", map[string]any{"email": "a@b.co", "password": "curta", "adult_declaration": true, "terms_version": "2026-10-17"})
	if !strings.Contains(r.Body.String(), `"reasons":["too_short"]`) {
		t.Fatalf("body %s", r.Body)
	}
}

func TestEmailVerificationEndpoints(t *testing.T) {
	a := newAPI(t)
	a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com"))

	if r := a.do(http.MethodPost, "/v1/email-verifications", map[string]string{"email": "ghost@example.com"}); r.Code != http.StatusAccepted {
		t.Fatalf("resend for unknown email: %d", r.Code)
	}
	tok := a.lastToken("ana@example.com")
	if r := a.do(http.MethodPost, "/v1/email-verifications/confirm", map[string]string{"token": tok}); r.Code != http.StatusNoContent {
		t.Fatalf("confirm: %d %s", r.Code, r.Body)
	}
	r := a.do(http.MethodPost, "/v1/email-verifications/confirm", map[string]string{"token": tok})
	if r.Code != http.StatusBadRequest || r.problemCode() != "invalid_token" {
		t.Fatalf("reuse: %d %q", r.Code, r.problemCode())
	}
}

func TestUnauthenticatedAuthEndpointsAreLimitedPerIP(t *testing.T) {
	a := newAPI(t)
	for range 30 {
		a.do(http.MethodPost, "/v1/email-verifications", map[string]string{"email": "x@y.co"})
	}
	r := a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com"))
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" {
		t.Fatalf("31st request: %d %q", r.Code, r.problemCode())
	}
	if r.Header().Get("Retry-After") != "60" {
		t.Fatalf("Retry-After %q, want 60", r.Header().Get("Retry-After"))
	}
}

func TestTheIPBudgetFollowsTheClientBehindATrustedProxy(t *testing.T) {
	a := newAPI(t, func(s *httpapi.Server) {
		s.TrustedProxies = []netip.Prefix{netip.MustParsePrefix("192.0.2.0/24")}
	})
	resend := func(xff string) resp {
		return a.do(http.MethodPost, "/v1/email-verifications", map[string]string{"email": "x@y.co"}, "X-Forwarded-For", xff)
	}
	for range 30 {
		resend("203.0.113.7")
	}
	if r := resend("203.0.113.7"); r.Code != http.StatusTooManyRequests {
		t.Fatalf("31st from the same client: %d, want 429", r.Code)
	}
	if r := resend("203.0.113.8"); r.Code != http.StatusAccepted {
		t.Fatalf("another client behind the same proxy: %d, want 202", r.Code)
	}
	if r := resend("198.51.100.1, 203.0.113.7"); r.Code != http.StatusTooManyRequests {
		t.Fatalf("a forged prefix escaped the budget: %d, want 429", r.Code)
	}
}
