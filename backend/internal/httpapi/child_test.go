package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func devBearer(token string) []string { return []string{"Authorization", "Bearer " + token} }

func TestRedeemOverHTTP(t *testing.T) {
	a := newAPI(t)
	owner := a.familyOwner("ana@example.com")
	minor := a.addMinor(owner)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(owner)...)
	r := a.do(http.MethodPost, "/v1/parental/link-codes", map[string]string{"minor_id": minor}, bearer(owner)...)
	var lc struct {
		Code string `json:"code"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &lc)
	redeem := func(code, label string) resp {
		return a.do(http.MethodPost, "/v1/devices/redeem", map[string]string{"code": code, "label": label})
	}
	if r := redeem(lc.Code, ""); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("empty label: %d %q", r.Code, r.problemCode())
	}
	r = redeem(lc.Code, "Tablet")
	var out struct {
		Token   string            `json:"token"`
		Profile map[string]string `json:"profile"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &out); r.Code != http.StatusCreated || err != nil || out.Token == "" ||
		out.Profile["id"] != minor || out.Profile["avatar"] == "" || out.Profile["age_band"] == "" || out.Profile["nickname"] == "" {
		t.Fatalf("redeem: %d %s", r.Code, r.Body)
	}
	for _, code := range []string{lc.Code, "ZZZZ-ZZZZ"} {
		if r := redeem(code, "Tablet"); r.Code != http.StatusBadRequest || r.problemCode() != "invalid_token" {
			t.Fatalf("%s: %d %q", code, r.Code, r.problemCode())
		}
	}
}

func TestRedeemRateLimit(t *testing.T) {
	a := newAPI(t)
	for range 10 {
		a.do(http.MethodPost, "/v1/devices/redeem", map[string]string{"code": "ZZZZ-ZZZZ", "label": "Tablet"})
	}
	r := a.do(http.MethodPost, "/v1/devices/redeem", map[string]string{"code": "ZZZZ-ZZZZ", "label": "Tablet"})
	if r.Code != http.StatusTooManyRequests || r.Header().Get("Retry-After") == "" {
		t.Fatalf("11th: %d %v", r.Code, r.Header())
	}
}

func TestDeviceChildRoutes(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	lia, teo := a.addMinor(tok), a.addMinor(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	dev := devBearer(a.linkedDevice(tok, lia))

	if r := a.do(http.MethodGet, "/v1/child/profile", nil, dev...); r.Code != http.StatusOK {
		t.Fatalf("profile: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/child/profiles", map[string]string{"pin": "1357"}, dev...); r.Code != http.StatusForbidden || r.problemCode() != "invalid_pin" {
		t.Fatalf("wrong PIN: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodPost, "/v1/child/profiles", map[string]string{"pin": "2580"}, dev...)
	var list struct {
		Profiles []map[string]string `json:"profiles"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &list); r.Code != http.StatusOK || err != nil || len(list.Profiles) != 2 {
		t.Fatalf("profiles: %d %s", r.Code, r.Body)
	}
	r = a.do(http.MethodPut, "/v1/child/profile", map[string]string{"pin": "2580", "minor_id": teo}, dev...)
	var p map[string]string
	if err := json.Unmarshal(r.Body.Bytes(), &p); r.Code != http.StatusOK || err != nil || p["id"] != teo {
		t.Fatalf("switch: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, dev...); r.Code != http.StatusNotFound {
		t.Fatalf("unlock from a device: %d", r.Code)
	}
}

func TestLockedSessionChildRoutes(t *testing.T) {
	a := newAPI(t)
	tok, minor := a.lockedSession("ana@example.com")
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("profile: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/child/profiles", map[string]string{"pin": "2580"}, bearer(tok)...); r.Code != http.StatusNotFound {
		t.Fatalf("picker from a locked session: %d", r.Code)
	}
	if r := a.do(http.MethodPut, "/v1/child/profile", map[string]string{"pin": "2580", "minor_id": minor}, bearer(tok)...); r.Code != http.StatusNotFound {
		t.Fatalf("switch from a locked session: %d", r.Code)
	}
	for i := 1; i <= 5; i++ {
		if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "1357"}, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "invalid_pin" {
			t.Fatalf("failure %d: %d %q", i, r.Code, r.problemCode())
		}
	}
	r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, bearer(tok)...)
	if r.Code != http.StatusTooManyRequests || r.Header().Get("Retry-After") != "30" {
		t.Fatalf("during the block: %d %v", r.Code, r.Header())
	}
	a.now = a.now.Add(30 * time.Second)
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("unlock: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("guardian again: %d", r.Code)
	}
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "not_child" {
		t.Fatalf("child route after unlocking: %d %q", r.Code, r.problemCode())
	}
}

func TestUnlockAfterFamilyDeletionSignsOut(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com")
	other := a.signInMobile("ana@example.com")
	if r := a.do(http.MethodDelete, "/v1/family", nil, bearer(other)...); r.Code != http.StatusNoContent {
		t.Fatalf("delete family: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "0000"}, bearer(tok)...); r.Code != http.StatusUnauthorized || r.problemCode() != "unauthenticated" {
		t.Fatalf("unlock with no family: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/sessions", nil, bearer(tok)...); r.Code != http.StatusUnauthorized {
		t.Fatalf("guardian route after unlock: %d", r.Code)
	}
}

func TestProfileGoneOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok, minor := a.lockedSession("ana@example.com")
	other := a.signInMobile("ana@example.com")
	a.do(http.MethodDelete, "/v1/family/minors/"+minor, nil, bearer(other)...)
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, bearer(tok)...); r.Code != http.StatusGone || r.problemCode() != "profile_gone" {
		t.Fatalf("%d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusForbidden {
		t.Fatalf("still locked: %d", r.Code)
	}
}

func TestRevokingALockedSessionEndsIt(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com")
	other := a.signInMobile("ana@example.com")
	if r := a.do(http.MethodDelete, "/v1/sessions/"+tok.SessionID, nil, bearer(other)...); r.Code != http.StatusNoContent {
		t.Fatalf("revoke: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, bearer(tok)...); r.Code != http.StatusUnauthorized {
		t.Fatalf("revoked locked session: %d", r.Code)
	}
}

func TestUnlinkedDeviceIsRefused(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	token := a.linkedDevice(tok, minor)
	list, _ := a.par.Devices(context.Background(), a.accountID(tok))
	a.do(http.MethodDelete, "/v1/parental/devices/"+list[0].ID, nil, bearer(tok)...)
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, devBearer(token)...); r.Code != http.StatusUnauthorized || r.problemCode() != "unauthenticated" {
		t.Fatalf("%d %q", r.Code, r.problemCode())
	}
}

func TestLockedWebSessionNeedsCSRFOnChildRoutes(t *testing.T) { // Contract (CSRF)
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	cookie, csrf := a.signInWeb("ana@example.com")
	id := a.accountID(tok)
	if err := a.par.SetPIN(context.Background(), id, "2580"); err != nil {
		t.Fatal(err)
	}
	var sessionID struct {
		Session struct {
			ID string `json:"id"`
		} `json:"session"`
	}
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/session", nil, "Cookie", cookie).Body.Bytes(), &sessionID)
	if err := a.par.EnterKidMode(context.Background(), id, sessionID.Session.ID, minor); err != nil {
		t.Fatal(err)
	}
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("no CSRF: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, "Cookie", cookie, "X-CSRF-Token", csrf); r.Code != http.StatusNoContent {
		t.Fatalf("with CSRF: %d %s", r.Code, r.Body)
	}
}

func TestGuardianRoutesRefuseADeviceToken(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	dev := devBearer(a.linkedDevice(tok, minor))
	for _, rt := range a.server.Routes() {
		if rt.Kind == httpapi.PublicRoute || rt.Kind == httpapi.ChildRoute {
			continue // every other kind starts from a guardian session
		}
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", dev...); r.Code != http.StatusUnauthorized || r.problemCode() != "unauthenticated" {
			t.Errorf("%s: %d %q", rt.Pattern, r.Code, r.problemCode())
		}
	}
	if n := a.count(`SELECT count(*) FROM families`); n != 1 {
		t.Fatalf("a device token changed something: %d families", n)
	}
}

func TestChildRoutesRefuseAGuardianSession(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	n := 0
	for _, rt := range a.server.Routes() {
		if rt.Kind != httpapi.ChildRoute {
			continue
		}
		n++
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "not_child" {
			t.Errorf("%s: %d %q", rt.Pattern, r.Code, r.problemCode())
		}
	}
	if n != 10 {
		t.Fatalf("swept %d child routes, want 10", n)
	}
}
