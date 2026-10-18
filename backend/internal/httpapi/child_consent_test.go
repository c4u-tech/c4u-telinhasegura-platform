package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

// consentGated are the child routes a paused child cannot reach; the rest
// of the child routes let the device leave the paused profile.
var consentGated = map[string]bool{
	"GET /v1/child/profile":                  true,
	"GET /v1/child/catalog":                  true,
	"GET /v1/child/thumbs/{video}":           true,
	"POST /v1/child/plays":                   true,
	"POST /v1/child/plays/{id}/beat":         true,
	"POST /v1/child/time/extend":             true,
	"POST /v1/child/videos/{id}/unavailable": true,
	"POST /v1/child/unlock":                  false,
	"POST /v1/child/profiles":                false,
	"PUT /v1/child/profile":                  false,
}

// pause leaves minorID's consent on an older policy version, as a child
// authorized before the current terms is.
func (a *api) pause(minorID string) {
	a.t.Helper()
	if _, err := a.pool.Exec(context.Background(), `UPDATE minor_consents SET policy_version = '2026-10-03' WHERE minor_id = $1::uuid`, minorID); err != nil {
		a.t.Fatal(err)
	}
}

type consentProfile struct {
	ID             string `json:"id"`
	ConsentCurrent bool   `json:"consent_current"`
}

func TestPausedChildOnALinkedDevice(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	lia, teo := a.addMinor(tok), a.addMinor(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	dev := devBearer(a.linkedDevice(tok, lia))
	a.pause(lia)

	n := 0
	for _, rt := range a.server.Routes() {
		if rt.Kind != httpapi.ChildRoute {
			continue
		}
		gated, known := consentGated[rt.Pattern]
		if !known {
			t.Errorf("%s: a child route neither gated nor exempt", rt.Pattern)
			continue
		}
		if !gated {
			continue
		}
		n++
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", dev...); r.Code != http.StatusForbidden || r.problemCode() != "consent_required" {
			t.Errorf("%s: %d %q", rt.Pattern, r.Code, r.problemCode())
		}
	}
	if n != 7 {
		t.Fatalf("swept %d gated routes", n)
	}

	// The exempt routes behave as for an authorized child.
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, dev...); r.Code != http.StatusNotFound {
		t.Fatalf("unlock from a device: %d %s", r.Code, r.Body)
	}
	r := a.do(http.MethodPost, "/v1/child/profiles", map[string]string{"pin": "2580"}, dev...)
	var list struct {
		Profiles []consentProfile `json:"profiles"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &list); r.Code != http.StatusOK || err != nil || len(list.Profiles) != 2 {
		t.Fatalf("profiles: %d %s", r.Code, r.Body)
	}
	consent := map[string]bool{}
	for _, p := range list.Profiles {
		consent[p.ID] = p.ConsentCurrent
	}
	if c, ok := consent[lia]; !ok || c {
		t.Fatalf("the paused child: %s", r.Body)
	}
	if c, ok := consent[teo]; !ok || !c {
		t.Fatalf("the authorized child: %s", r.Body)
	}
	r = a.do(http.MethodPut, "/v1/child/profile", map[string]string{"pin": "2580", "minor_id": teo}, dev...)
	var p consentProfile
	if err := json.Unmarshal(r.Body.Bytes(), &p); r.Code != http.StatusOK || err != nil || p.ID != teo || !p.ConsentCurrent {
		t.Fatalf("switch to an authorized child: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, dev...); r.Code != http.StatusOK {
		t.Fatalf("profile after switching: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/child/catalog", nil, dev...); r.Code != http.StatusOK {
		t.Fatalf("catalog after switching: %d %s", r.Code, r.Body)
	}

	// Switching back to the paused child is refused, and the device stays put.
	if r := a.do(http.MethodPut, "/v1/child/profile", map[string]string{"pin": "2580", "minor_id": lia}, dev...); r.Code != http.StatusForbidden || r.problemCode() != "consent_required" {
		t.Fatalf("switch to a paused child: %d %q", r.Code, r.problemCode())
	}
	r = a.do(http.MethodGet, "/v1/child/profile", nil, dev...)
	if err := json.Unmarshal(r.Body.Bytes(), &p); r.Code != http.StatusOK || err != nil || p.ID != teo {
		t.Fatalf("the device left its profile: %d %s", r.Code, r.Body)
	}
}

func TestPausedChildOnALockedSession(t *testing.T) {
	a := newAPI(t)
	tok, minor := a.lockedSession("ana@example.com")
	a.pause(minor)
	for _, path := range []string{"/v1/child/profile", "/v1/child/catalog"} {
		if r := a.do(http.MethodGet, path, nil, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "consent_required" {
			t.Fatalf("%s: %d %q", path, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": "00000000-0000-0000-0000-000000000000"}, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "consent_required" {
		t.Fatalf("play: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/child/unlock", map[string]string{"pin": "2580"}, bearer(tok)...); r.Code != http.StatusNoContent {
		t.Fatalf("unlock: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("guardian again: %d", r.Code)
	}
}

func TestKidModeRefusesAPausedChild(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(tok)...)
	a.pause(minor)
	r := a.do(http.MethodPost, "/v1/parental/kid-mode", map[string]string{"minor_id": minor}, bearer(tok)...)
	if r.Code != http.StatusForbidden || r.problemCode() != "consent_required" {
		t.Fatalf("kid mode for a paused child: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("the session was locked: %d", r.Code)
	}
}
