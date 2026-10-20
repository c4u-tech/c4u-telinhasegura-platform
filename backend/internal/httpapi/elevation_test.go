package httpapi_test

import (
	"net/http"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func mfaRequired(s *httpapi.Server) { s.StaffMFARequired = true }

// refresh trades tok for fresh mobile tokens after the clock moved past
// the access token's 15 minutes.
func (a *api) refresh(tok mobileTokens) mobileTokens {
	a.t.Helper()
	return decodeTokens(a.t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}))
}

func TestEnforcementGuardsEveryAdminAndModeratorRoute(t *testing.T) {
	a := newAPI(t, mfaRequired)
	admin := a.admin("ana@example.com")
	a.enrollMFA(admin) // elevated, so it can appoint
	mod := a.moderator(admin, "mia@example.com")
	other := a.admin("bia@example.com")

	sweep := func(want string, who map[httpapi.RouteKind]map[string]mobileTokens) {
		t.Helper()
		na, nm := 0, 0
		for _, rt := range a.server.Routes() {
			toks, ok := who[rt.Kind]
			if !ok {
				continue
			}
			if rt.Kind == httpapi.AdminRoute {
				na++
			} else {
				nm++
			}
			method, path := sweepTarget(rt.Pattern)
			for name, tok := range toks {
				if r := a.do(method, path, "{}", bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != want {
					t.Errorf("%s as %s: %d %q, want %s", rt.Pattern, name, r.Code, r.problemCode(), want)
				}
			}
		}
		if na == 0 || nm != 4 {
			t.Fatalf("swept %d admin and %d moderator routes", na, nm)
		}
	}

	sweep("mfa_enrollment_required", map[httpapi.RouteKind]map[string]mobileTokens{
		httpapi.AdminRoute:     {"unenrolled admin": other},
		httpapi.ModeratorRoute: {"unenrolled admin": other, "unenrolled moderator": mod},
	})

	a.enrollMFA(mod)
	a.enrollMFA(other)
	a.now = a.now.Add(31 * time.Minute) // every elevation lapses
	admin, mod, other = a.refresh(admin), a.refresh(mod), a.refresh(other)
	sweep("elevation_required", map[httpapi.RouteKind]map[string]mobileTokens{
		httpapi.AdminRoute:     {"admin": admin, "other admin": other},
		httpapi.ModeratorRoute: {"admin": admin, "moderator": mod},
	})
}

func TestEnforcementLetsAnElevatedModeratorModerate(t *testing.T) {
	a := newAPI(t, mfaRequired)
	admin := a.admin("ana@example.com")
	a.enrollMFA(admin)
	mod := a.moderator(admin, "mia@example.com")
	a.enrollMFA(mod)
	if r := a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(mod)...); r.Code != http.StatusOK {
		t.Fatalf("an elevated moderator with the switch on: %d %s", r.Code, r.Body)
	}
}

func TestEnforcementChecksRoleThenElevationThenReauth(t *testing.T) {
	a := newAPI(t, mfaRequired)
	admin := a.admin("ana@example.com")
	sec, _ := a.enrollMFA(admin)
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	plain := a.familyOwner("caio@example.com")

	a.now = a.now.Add(31 * time.Minute) // the elevation and the re-auth both lapse
	admin, cur, plain = a.refresh(admin), a.refresh(cur), a.refresh(plain)
	grant := func(tok mobileTokens) resp {
		return a.do(http.MethodPost, "/v1/admin/staff",
			map[string]any{"email": "dani@example.com", "role": "moderator", "reason": "Entrou na equipe."}, bearer(tok)...)
	}
	for who, tok := range map[string]mobileTokens{"guardian": plain, "curator": cur} {
		if r := grant(tok); r.Code != http.StatusForbidden || r.problemCode() != "not_admin" {
			t.Errorf("%s: %d %q, want not_admin before the elevation", who, r.Code, r.problemCode())
		}
	}
	if r := grant(admin); r.Code != http.StatusForbidden || r.problemCode() != "elevation_required" {
		t.Fatalf("admin: %d %q, want elevation_required before reauth_required", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/staff/mfa/challenge", map[string]string{"code": totpCode(t, sec, a.now)}, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("challenge: %d %s", r.Code, r.Body)
	}
	if r := grant(admin); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("elevated, re-auth stale: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("reauth: %d %s", r.Code, r.Body)
	}
	a.signUpVerified("dani@example.com")
	if r := grant(admin); r.Code != http.StatusCreated {
		t.Fatalf("elevated and re-authenticated: %d %s", r.Code, r.Body)
	}

	// Curator routes never ask for the elevation.
	if r := a.do(http.MethodGet, "/v1/curation/themes", nil, bearer(cur)...); r.Code != http.StatusOK {
		t.Fatalf("an unenrolled curator with the switch on: %d %s", r.Code, r.Body)
	}
	if a.mfaStatus(admin)["required"] != true || a.mfaStatus(cur)["required"] != false {
		t.Fatal("required must be true for admin and moderator only")
	}
}
