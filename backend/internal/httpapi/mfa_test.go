package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// mfaStatus reads GET /v1/staff/mfa as a raw map, so absent keys show.
func (a *api) mfaStatus(tok mobileTokens) map[string]any {
	a.t.Helper()
	var st map[string]any
	getJSON(a.t, a.do(http.MethodGet, "/v1/staff/mfa", nil, bearer(tok)...), &st)
	return st
}

func TestMFAOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	st := a.mfaStatus(admin)
	if st["enrolled"] != false || st["recovery_codes_left"] != 0.0 || st["required"] != false {
		t.Fatalf("status before enrolling: %v", st)
	}
	for _, k := range []string{"enrolled_at", "elevated_until"} {
		if _, ok := st[k]; ok {
			t.Fatalf("status carries %s before enrolling: %v", k, st)
		}
	}
	// The switch is off: an unenrolled admin works as before.
	if r := a.do(http.MethodGet, "/v1/admin/staff", nil, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("admin route with the switch off: %d %s", r.Code, r.Body)
	}

	r := a.do(http.MethodPost, "/v1/staff/mfa/enrollment", nil, bearer(admin)...)
	var e struct {
		Secret string `json:"secret"`
		URI    string `json:"otpauth_uri"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &e); r.Code != http.StatusCreated || err != nil || e.Secret == "" || e.URI == "" {
		t.Fatalf("enroll: %d %s", r.Code, r.Body)
	}
	if cc := r.Header().Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("the secret's answer is cacheable: %q", cc)
	}
	confirm := func(code string) resp {
		return a.do(http.MethodPost, "/v1/staff/mfa/enrollment/confirm", map[string]string{"code": code}, bearer(admin)...)
	}
	if r := confirm("000000"); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "mfa_code_invalid" {
		t.Fatalf("a wrong code: %d %q", r.Code, r.problemCode())
	}
	r = confirm(totpCode(t, e.Secret, a.now))
	var c struct {
		Codes []string `json:"recovery_codes"`
		Until string   `json:"elevated_until"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &c); r.Code != http.StatusOK || err != nil || len(c.Codes) != 10 ||
		c.Until != a.now.Add(30*time.Minute).Format(time.RFC3339) {
		t.Fatalf("confirm: %d %s", r.Code, r.Body)
	}
	if cc := r.Header().Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("the codes' answer is cacheable: %q", cc)
	}
	st = a.mfaStatus(admin)
	if st["enrolled"] != true || st["recovery_codes_left"] != 10.0 || st["enrolled_at"] != a.now.Format(time.RFC3339) ||
		st["elevated_until"] != c.Until {
		t.Fatalf("status after enrolling: %v", st)
	}
	if r := a.do(http.MethodPost, "/v1/staff/mfa/enrollment", nil, bearer(admin)...); r.Code != http.StatusConflict || r.problemCode() != "mfa_already_enrolled" {
		t.Fatalf("enrolling twice: %d %q", r.Code, r.problemCode())
	}

	a.now = a.now.Add(30 * time.Second)
	challenge := func(body any) resp { return a.do(http.MethodPost, "/v1/staff/mfa/challenge", body, bearer(admin)...) }
	for _, bad := range []any{map[string]string{}, map[string]string{"code": "123456", "recovery_code": c.Codes[0]}} {
		if r := challenge(bad); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
			t.Fatalf("%v: %d %q", bad, r.Code, r.problemCode())
		}
	}
	r = challenge(map[string]string{"code": totpCode(t, e.Secret, a.now)})
	var el struct {
		Until string `json:"elevated_until"`
		Left  int    `json:"recovery_codes_left"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &el); r.Code != http.StatusOK || err != nil ||
		el.Until != a.now.Add(30*time.Minute).Format(time.RFC3339) || el.Left != 10 {
		t.Fatalf("challenge: %d %s", r.Code, r.Body)
	}
	if err := json.Unmarshal(challenge(map[string]string{"recovery_code": c.Codes[0]}).Body.Bytes(), &el); err != nil || el.Left != 9 {
		t.Fatalf("recovery code: %+v %v", el, err)
	}

	r = a.do(http.MethodPost, "/v1/staff/mfa/recovery-codes", nil, bearer(admin)...)
	if err := json.Unmarshal(r.Body.Bytes(), &c); r.Code != http.StatusOK || err != nil || len(c.Codes) != 10 || r.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("regenerate: %d %s", r.Code, r.Body)
	}
	a.now = a.now.Add(31 * time.Minute) // the elevation and the re-auth both lapse
	admin = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": admin.RefreshToken}))
	if r := a.do(http.MethodPost, "/v1/staff/mfa/recovery-codes", nil, bearer(admin)...); r.Code != http.StatusForbidden || r.problemCode() != "elevation_required" {
		t.Fatalf("regenerating unelevated, re-auth stale: %d %q", r.Code, r.problemCode())
	}

	// Curators may enroll.
	cur := a.curator(a.admin("bia@example.com"), "caio@example.com", "pediatra")
	a.enrollMFA(cur)
}

func TestMFARoutesRefuseNonStaffBeforeReauth(t *testing.T) {
	a := newAPI(t)
	plain := a.familyOwner("caio@example.com")
	a.now = a.now.Add(6 * time.Minute)
	plain = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": plain.RefreshToken}))
	for _, rt := range a.server.Routes() {
		if rt.Kind != httpapi.StaffRoute {
			continue
		}
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", bearer(plain)...); r.Code != http.StatusForbidden || r.problemCode() != "not_staff" {
			t.Errorf("%s: %d %q", rt.Pattern, r.Code, r.problemCode())
		}
	}
}

func TestMFAChallengeLockoutOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.enrollMFA(admin)
	for i := range 5 {
		r := a.do(http.MethodPost, "/v1/staff/mfa/challenge", map[string]string{"recovery_code": "AAAAA-AAAAA"}, bearer(admin)...)
		if r.Code != http.StatusUnprocessableEntity || r.problemCode() != "mfa_code_invalid" {
			t.Fatalf("failure %d: %d %q", i+1, r.Code, r.problemCode())
		}
	}
	r := a.do(http.MethodPost, "/v1/staff/mfa/challenge", map[string]string{"code": "123456"}, bearer(admin)...)
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") != "30" {
		t.Fatalf("blocked: %d %q Retry-After=%q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}
}

func TestMFAUnavailableWithoutAKey(t *testing.T) {
	a := newAPI(t, func(s *httpapi.Server) {
		s.Staff = staff.NewService(staff.Deps{Pool: s.Pool, Audit: &audittest.Recorder{}, Now: time.Now})
	})
	admin := a.admin("ana@example.com")
	if r := a.do(http.MethodGet, "/v1/staff/mfa", nil, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("status: %d %s", r.Code, r.Body)
	}
	for _, p := range []string{"/v1/staff/mfa/enrollment", "/v1/staff/mfa/enrollment/confirm", "/v1/staff/mfa/challenge"} {
		if r := a.do(http.MethodPost, p, map[string]string{"code": "123456"}, bearer(admin)...); r.Code != http.StatusServiceUnavailable || r.problemCode() != "mfa_unavailable" {
			t.Errorf("%s: %d %q", p, r.Code, r.problemCode())
		}
	}
	// Regeneration checks the elevation first: no session can be elevated without a key.
	if r := a.do(http.MethodPost, "/v1/staff/mfa/recovery-codes", nil, bearer(admin)...); r.Code != http.StatusForbidden || r.problemCode() != "elevation_required" {
		t.Errorf("regenerate: %d %q", r.Code, r.problemCode())
	}
}

func TestMFAWritesNeedAFreshReauth(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.now = a.now.Add(6 * time.Minute)
	admin = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": admin.RefreshToken}))
	if r := a.do(http.MethodPost, "/v1/staff/mfa/enrollment", nil, bearer(admin)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("enrolling with a stale re-auth: %d %q", r.Code, r.problemCode())
	}
	if n := a.count(`SELECT count(*) FROM staff_mfa`); n != 0 {
		t.Fatalf("%d factors stored by a refused enrollment", n)
	}

	other := a.admin("bia@example.com")
	secret, _ := a.enrollMFA(other)
	a.now = a.now.Add(6 * time.Minute)
	other = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": other.RefreshToken}))
	if r := a.do(http.MethodPost, "/v1/staff/mfa/challenge", map[string]string{"code": totpCode(t, secret, a.now)}, bearer(other)...); r.Code != http.StatusOK {
		t.Fatalf("challenge: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/staff/mfa/recovery-codes", nil, bearer(other)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("regenerating with a stale re-auth: %d %q", r.Code, r.problemCode())
	}

	// A moderator-only account reaches the MFA routes too.
	a.enrollMFA(a.moderator(a.admin("cleo@example.com"), "mia@example.com"))
}
