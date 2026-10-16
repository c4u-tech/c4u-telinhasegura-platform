package httpapi_test

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func corsServer() http.Handler {
	return (&httpapi.Server{AllowedOrigins: []string{"https://app.test"}, Log: slog.New(slog.DiscardHandler)}).Handler()
}

func TestCORSAllowsCredentialsOnlyForListedOrigins(t *testing.T) {
	req := httptest.NewRequest(http.MethodOptions, "/v1/sessions", nil)
	req.Header.Set("Origin", "https://app.test")
	req.Header.Set("Access-Control-Request-Method", "POST")
	rec := httptest.NewRecorder()
	corsServer().ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("preflight status %d, want 204", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://app.test" {
		t.Fatalf("Allow-Origin %q", got)
	}
	if rec.Header().Get("Access-Control-Allow-Credentials") != "true" {
		t.Fatal("credentials not allowed for a listed origin")
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); got != "Content-Type, Authorization, X-CSRF-Token" {
		t.Fatalf("Allow-Headers %q", got)
	}
}

func TestCORSRefusesUnlistedOrigins(t *testing.T) {
	req := httptest.NewRequest(http.MethodOptions, "/v1/sessions", nil)
	req.Header.Set("Origin", "https://evil.test")
	req.Header.Set("Access-Control-Request-Method", "POST")
	rec := httptest.NewRecorder()
	corsServer().ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("preflight status %d, want 403", rec.Code)
	}
	if rec.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatal("unlisted origin received Allow-Origin")
	}
}

func TestUnknownRouteIsAProblem(t *testing.T) {
	rec := httptest.NewRecorder()
	corsServer().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/nope", nil))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/problem+json" {
		t.Fatalf("Content-Type %q", ct)
	}
}

func TestCORSExposesRetryAfterToListedOrigins(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/nope", nil)
	req.Header.Set("Origin", "https://app.test")
	rec := httptest.NewRecorder()
	corsServer().ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Expose-Headers"); got != "Retry-After" {
		t.Fatalf("Expose-Headers %q, want Retry-After", got)
	}
}
