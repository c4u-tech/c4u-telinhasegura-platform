package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func TestPINOverHTTP(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("lia@example.com")
	loner := a.signInMobile("lia@example.com")
	if r := a.do(http.MethodGet, "/v1/parental/pin", nil, bearer(loner)...); r.Code != http.StatusNotFound || r.problemCode() != "no_family" {
		t.Fatalf("no family: %d %q", r.Code, r.problemCode())
	}
	tok := a.familyOwner("ana@example.com")
	if r := a.do(http.MethodGet, "/v1/parental/pin", nil, bearer(tok)...); r.Code != http.StatusOK || strings.TrimSpace(r.Body.String()) != `{"set":false}` {
		t.Fatalf("before: %d %s", r.Code, r.Body)
	}
	for pin, code := range map[string]string{"12": "validation", "1111": "weak_pin"} {
		if r := a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": pin}, bearer(tok)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != code {
			t.Fatalf("%q: %d %q", pin, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("set: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/parental/pin", nil, bearer(tok)...); strings.TrimSpace(r.Body.String()) != `{"set":true}` {
		t.Fatalf("after: %s", r.Body)
	}
	a.now = a.now.Add(6 * time.Minute) // the access token lives 15 minutes
	if r := a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "1357"}, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale re-auth: %d %q", r.Code, r.problemCode())
	}
}

func TestVerifyPINOverHTTP(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("lia@example.com")
	loner := a.signInMobile("lia@example.com")
	verify := func(tok mobileTokens, pin string) resp {
		return a.do(http.MethodPost, "/v1/parental/pin/verify", map[string]string{"pin": pin}, bearer(tok)...)
	}
	if r := verify(loner, "2580"); r.Code != http.StatusNotFound || r.problemCode() != "no_family" {
		t.Fatalf("no family: %d %q", r.Code, r.problemCode())
	}
	tok := a.familyOwner("ana@example.com")
	if r := verify(tok, "2580"); r.Code != http.StatusConflict || r.problemCode() != "pin_not_set" {
		t.Fatalf("no PIN: %d %q", r.Code, r.problemCode())
	}
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	if r := verify(tok, "1357"); r.Code != http.StatusForbidden || r.problemCode() != "invalid_pin" {
		t.Fatalf("wrong: %d %q", r.Code, r.problemCode())
	}
	if r := verify(tok, "2580"); r.Code != http.StatusNoContent {
		t.Fatalf("right: %d %s", r.Code, r.Body)
	}
	for range 5 {
		verify(tok, "1357")
	}
	if r := verify(tok, "2580"); r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") == "" {
		t.Fatalf("blocked: %d %q %q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}
}

func TestKidModeOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	enter := func(id string) resp {
		return a.do(http.MethodPost, "/v1/parental/kid-mode", map[string]string{"minor_id": id}, bearer(tok)...)
	}
	if r := enter(minor); r.Code != http.StatusConflict || r.problemCode() != "pin_not_set" {
		t.Fatalf("no PIN: %d %q", r.Code, r.problemCode())
	}
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if r := enter(id); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Fatalf("minor %q: %d %q", id, r.Code, r.problemCode())
		}
	}
	if r := enter(minor); r.Code != http.StatusNoContent {
		t.Fatalf("enter: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "kid_mode" {
		t.Fatalf("guardian route while locked: %d %q", r.Code, r.problemCode())
	}
}

var codeRE = regexp.MustCompile(`^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`)

func TestLinkCodesOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	create := func() resp {
		return a.do(http.MethodPost, "/v1/parental/link-codes", map[string]string{"minor_id": minor}, bearer(tok)...)
	}
	r := create()
	var lc struct {
		Code      string    `json:"code"`
		MinorID   string    `json:"minor_id"`
		ExpiresAt time.Time `json:"expires_at"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &lc); r.Code != http.StatusCreated || err != nil ||
		!codeRE.MatchString(lc.Code) || lc.MinorID != minor || !lc.ExpiresAt.Equal(a.now.Add(10*time.Minute)) {
		t.Fatalf("create: %d %s", r.Code, r.Body)
	}
	for range 4 {
		create()
	}
	if r := create(); r.Code != http.StatusConflict || r.problemCode() != "limit_reached" {
		t.Fatalf("6th: %d %q", r.Code, r.problemCode())
	}
	for range 14 { // 20 calls in the hour so far
		create()
	}
	if r := create(); r.Code != http.StatusTooManyRequests || r.Header().Get("Retry-After") == "" {
		t.Fatalf("21st: %d %v", r.Code, r.Header())
	}
}

func TestDevicesOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	id := a.accountID(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	lc, err := a.par.CreateLinkCode(context.Background(), id, minor)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := a.par.Redeem(context.Background(), lc.Code, "Tablet"); err != nil {
		t.Fatal(err)
	}

	r := a.do(http.MethodGet, "/v1/parental/devices", nil, bearer(tok)...)
	var body struct {
		Devices []map[string]any `json:"devices"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &body); r.Code != http.StatusOK || err != nil || len(body.Devices) != 1 {
		t.Fatalf("list: %d %s", r.Code, r.Body)
	}
	d := body.Devices[0]
	if d["label"] != "Tablet" || d["minor_id"] != minor || d["linked_at"] == nil || d["last_seen_at"] == nil || len(d) != 5 {
		t.Fatalf("device %v", d) // id, label, minor_id, linked_at, last_seen_at; never a token
	}
	path := "/v1/parental/devices/" + d["id"].(string)
	if r := a.do(http.MethodDelete, path, nil, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("unlink: %d %s", r.Code, r.Body)
	}
	for _, p := range []string{path, "/v1/parental/devices/abc"} {
		if r := a.do(http.MethodDelete, p, nil, bearer(tok)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Fatalf("%s: %d %q", p, r.Code, r.problemCode())
		}
	}
}

func TestParentalWritesNeedCSRFOnTheWeb(t *testing.T) { // Contract (CSRF)
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, _ := a.signInWeb("ana@example.com")
	if r := a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("%d %q", r.Code, r.problemCode())
	}
}

func TestCORSAllowsPut(t *testing.T) { // Global Constraints (CORS)
	a := newAPI(t, func(s *httpapi.Server) { s.AllowedOrigins = []string{"https://app.test"} })
	r := a.do(http.MethodOptions, "/v1/parental/pin", nil, "Origin", "https://app.test", "Access-Control-Request-Method", "PUT")
	if !strings.Contains(r.Header().Get("Access-Control-Allow-Methods"), "PUT") {
		t.Fatalf("allow methods: %q", r.Header().Get("Access-Control-Allow-Methods"))
	}
}
