package httpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

// admin signs a verified guardian up and in, then grants them the admin
// role as the server command does.
func (a *api) admin(email string) mobileTokens {
	a.t.Helper()
	a.signUpVerified(email)
	tok := a.signInMobile(email)
	if _, err := a.team.GrantAdmin(context.Background(), email); err != nil {
		a.t.Fatal(err)
	}
	return tok
}

// curator has the admin appoint a new verified guardian with the given
// displayed role, signs them in and accepts the curator terms for them.
func (a *api) curator(admin mobileTokens, email, role string) mobileTokens {
	a.t.Helper()
	tok := a.undeclaredCurator(admin, email, role)
	if r := a.do(http.MethodPost, "/v1/curation/declaration", map[string]string{"version": curation.CuratorTermsVersion}, bearer(tok)...); r.Code != http.StatusOK {
		a.t.Fatalf("declare %s: %d %s", email, r.Code, r.Body)
	}
	return tok
}

// undeclaredCurator is curator before the curator terms are accepted.
func (a *api) undeclaredCurator(admin mobileTokens, email, role string) mobileTokens {
	a.t.Helper()
	a.signUpVerified(email)
	extra := map[string]any{"display_role": role, "verified_professional": role != "mae-pai" && role != "cuidador"}
	if r := a.grant(admin, email, "curator", extra); r.Code != http.StatusCreated {
		a.t.Fatalf("appoint %s: %d %s", email, r.Code, r.Body)
	}
	return a.signInMobile(email)
}

func TestRoleRoutesCheckTheRoleOnEveryRequest(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	mod := a.moderator(admin, "mia@example.com")
	plain := a.familyOwner("caio@example.com")
	nc, na, nm := 0, 0, 0
	ns := 0
	for _, rt := range a.server.Routes() {
		method, path := sweepTarget(rt.Pattern)
		var refused map[string]mobileTokens
		var code string
		switch rt.Kind {
		case httpapi.CuratorRoute:
			nc++
			refused, code = map[string]mobileTokens{"guardian": plain, "admin only": admin, "moderator only": mod}, "not_curator"
		case httpapi.AdminRoute:
			na++
			refused, code = map[string]mobileTokens{"guardian": plain, "curator only": cur, "moderator only": mod}, "not_admin"
		case httpapi.ModeratorRoute:
			nm++
			refused, code = map[string]mobileTokens{"guardian": plain, "curator only": cur}, "not_moderator"
		case httpapi.StaffRoute:
			ns++
			refused, code = map[string]mobileTokens{"guardian": plain}, "not_staff"
		default:
			continue
		}
		for who, tok := range refused {
			if r := a.do(method, path, "{}", bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != code {
				t.Errorf("%s as %s: %d %q", rt.Pattern, who, r.Code, r.problemCode())
			}
		}
	}
	if nc == 0 || na != 15 || nm != 6 || ns != 6 { // 7 team and pack routes, 6 directory routes, 2 suspension routes
		t.Fatalf("swept %d curator, %d admin, %d moderator and %d staff routes", nc, na, nm, ns)
	}

	if r := a.do(http.MethodGet, "/v1/curation/themes", nil, bearer(cur)...); r.Code != http.StatusOK {
		t.Fatalf("curator: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/admin/staff/"+a.accountID(cur)+"/roles/curator/revoke",
		map[string]any{"reason": "Saiu da equipe."}, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("revoke: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/curation/themes", nil, bearer(cur)...); r.Code != http.StatusForbidden || r.problemCode() != "not_curator" {
		t.Fatalf("a curator removed a moment ago: %d %q", r.Code, r.problemCode())
	}
	held := "/v1/moderation/videos?state=held"
	for who, tok := range map[string]mobileTokens{"moderator": mod, "admin": admin} {
		if r := a.do(http.MethodGet, held, nil, bearer(tok)...); r.Code != http.StatusOK {
			t.Fatalf("%s on a moderation route: %d %s", who, r.Code, r.Body)
		}
	}
	if r := a.do(http.MethodPost, "/v1/admin/staff/"+a.accountID(mod)+"/roles/moderator/revoke",
		map[string]any{"reason": "Não modera mais."}, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("revoke: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, held, nil, bearer(mod)...); r.Code != http.StatusForbidden || r.problemCode() != "not_moderator" {
		t.Fatalf("a moderator revoked a moment ago: %d %q", r.Code, r.problemCode())
	}
	if _, err := a.team.RevokeAdmin(context.Background(), "ana@example.com"); err != nil {
		t.Fatal(err)
	}
	if r := a.do(http.MethodGet, "/v1/admin/staff", nil, bearer(admin)...); r.Code != http.StatusForbidden || r.problemCode() != "not_admin" {
		t.Fatalf("an admin revoked a moment ago: %d %q", r.Code, r.problemCode())
	}
}

func TestThemesOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	var body struct {
		Themes []string `json:"themes"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/curation/themes", nil, bearer(cur)...), &body)
	if !slices.Equal(body.Themes, []string{"bichos", "musica", "historias", "aprender", "brincar", "natureza"}) {
		t.Fatalf("themes %v", body.Themes)
	}
}

func TestGetSessionReportsRoles(t *testing.T) {
	a := newAPI(t)
	roles := func(tok mobileTokens) []string {
		var body struct {
			Roles []string `json:"roles"`
		}
		getJSON(t, a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...), &body)
		return body.Roles
	}
	plain := a.familyOwner("caio@example.com")
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(plain)...); !strings.Contains(r.Body.String(), `"roles":[]`) {
		t.Fatalf("a guardian's roles must be an empty list: %s", r.Body)
	}
	admin := a.admin("ana@example.com")
	if got := roles(admin); !slices.Equal(got, []string{"admin"}) {
		t.Fatalf("admin: %v", got)
	}
	other := a.admin("bia@example.com")
	if r := a.grant(other, "ana@example.com", "curator", map[string]any{"display_role": "mae-pai"}); r.Code != http.StatusCreated {
		t.Fatalf("appoint ana: %d %s", r.Code, r.Body)
	}
	if got := roles(admin); !slices.Equal(got, []string{"admin", "curator"}) {
		t.Fatalf("admin and curator: %v", got)
	}
	if r := a.grant(other, "ana@example.com", "moderator", nil); r.Code != http.StatusCreated {
		t.Fatalf("grant ana moderator: %d %s", r.Code, r.Body)
	}
	if got := roles(admin); !slices.Equal(got, []string{"admin", "curator", "moderator"}) {
		t.Fatalf("all three, in name order: %v", got)
	}
	if got := roles(a.moderator(other, "mia@example.com")); !slices.Equal(got, []string{"moderator"}) {
		t.Fatalf("a moderator: %v", got)
	}
}

// getJSON decodes a 200 response, failing the test on any other status.
func getJSON(t *testing.T, r resp, v any) {
	t.Helper()
	if r.Code != http.StatusOK {
		t.Fatalf("status %d %s", r.Code, r.Body)
	}
	if err := json.Unmarshal(r.Body.Bytes(), v); err != nil {
		t.Fatalf("body: %v %s", err, r.Body)
	}
}

func TestAdminRoleIsCheckedBeforeReauth(t *testing.T) { // refusal order: not_admin before reauth_required
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	mod := a.moderator(admin, "mia@example.com")
	plain := a.familyOwner("caio@example.com")
	a.now = a.now.Add(6 * time.Minute)
	body := map[string]any{"email": "dani@example.com", "role": "moderator", "reason": "Entrou na equipe."}
	for who, tok := range map[string]mobileTokens{"guardian": plain, "curator only": cur, "moderator only": mod} {
		tok = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}))
		for _, p := range []string{"POST /v1/admin/staff", "PATCH /v1/admin/staff/{account_id}/curator",
			"POST /v1/admin/staff/{account_id}/roles/{role}/revoke", "POST /v1/admin/packs/{id}/remove"} {
			method, path := sweepTarget(p)
			if r := a.do(method, path, body, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "not_admin" {
				t.Errorf("%s on %s with a stale re-auth: %d %q", who, p, r.Code, r.problemCode())
			}
		}
	}
}
