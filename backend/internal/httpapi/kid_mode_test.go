package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func TestGuardianRoutesRefuseALockedSession(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com")
	n := 0
	for _, rt := range a.server.Routes() {
		switch rt.Kind {
		case httpapi.GuardianRoute, httpapi.CuratorRoute, httpapi.AdminRoute, httpapi.ModeratorRoute, httpapi.StaffRoute:
		default:
			continue
		}
		n++
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "kid_mode" {
			t.Errorf("%s: %d %q", rt.Pattern, r.Code, r.problemCode())
		}
	}
	if n < 20 {
		t.Fatalf("swept only %d guardian routes", n)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("GET /v1/session while locked: %d", r.Code)
	}
	if r := a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}); r.Code != http.StatusOK {
		t.Fatalf("refresh while locked: %d %s", r.Code, r.Body)
	}
}

func TestRoutesDeclareKnownKinds(t *testing.T) {
	a := newAPI(t)
	seen := map[string]bool{}
	for _, rt := range a.server.Routes() {
		switch rt.Kind {
		case httpapi.PublicRoute, httpapi.SessionRoute, httpapi.GuardianRoute, httpapi.ChildRoute,
			httpapi.CuratorRoute, httpapi.AdminRoute, httpapi.ModeratorRoute, httpapi.StaffRoute:
		default:
			t.Errorf("%s: kind %q", rt.Pattern, rt.Kind)
		}
		if seen[rt.Pattern] {
			t.Errorf("%s registered twice", rt.Pattern)
		}
		seen[rt.Pattern] = true
	}
	if !seen["GET /v1/session"] || !seen["POST /v1/family"] {
		t.Fatal("the registry misses existing routes")
	}
}

type kidModeBody struct {
	KidMode *struct {
		MinorID *string `json:"minor_id"`
	} `json:"kid_mode"`
}

func TestGetSessionReportsKidMode(t *testing.T) {
	a := newAPI(t)
	free := a.familyOwner("bia@example.com")
	var body kidModeBody
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/session", nil, bearer(free)...).Body.Bytes(), &body)
	if body.KidMode != nil {
		t.Fatalf("unlocked session reports kid mode")
	}

	tok, minor := a.lockedSession("ana@example.com")
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...).Body.Bytes(), &body)
	if body.KidMode == nil || body.KidMode.MinorID == nil || *body.KidMode.MinorID != minor {
		t.Fatalf("locked: %+v", body.KidMode)
	}
	other := a.signInMobile("ana@example.com") // a second device, fresh re-auth
	if r := a.do(http.MethodDelete, "/v1/family/minors/"+minor, nil, bearer(other)...); r.Code != http.StatusNoContent {
		t.Fatalf("delete minor: %d %s", r.Code, r.Body)
	}
	body = kidModeBody{}
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...).Body.Bytes(), &body)
	if body.KidMode == nil || body.KidMode.MinorID != nil {
		t.Fatalf("after the child's deletion: %+v", body.KidMode)
	}
}
