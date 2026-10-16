package httpapi_test

import (
	"encoding/json"
	"maps"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

type heldRoleResp struct {
	Role                 string  `json:"role"`
	GrantedAt            string  `json:"granted_at"`
	DisplayRole          *string `json:"display_role"`
	VerifiedProfessional *bool   `json:"verified_professional"`
}

type memberResp struct {
	AccountID string         `json:"account_id"`
	Email     string         `json:"email"`
	Roles     []heldRoleResp `json:"roles"`
}

func decodeMember(t *testing.T, r resp) memberResp {
	t.Helper()
	var m memberResp
	if err := json.Unmarshal(r.Body.Bytes(), &m); err != nil {
		t.Fatalf("member body: %v %d %s", err, r.Code, r.Body)
	}
	return m
}

// grant has admin grant role to email through the team route, with the
// reason "Entrou na equipe." unless extra sets another.
func (a *api) grant(admin mobileTokens, email, role string, extra map[string]any) resp {
	a.t.Helper()
	body := map[string]any{"email": email, "role": role, "reason": "Entrou na equipe."}
	maps.Copy(body, extra)
	return a.do(http.MethodPost, "/v1/admin/staff", body, bearer(admin)...)
}

// moderator has admin make a new verified guardian a moderator, and signs
// them in.
func (a *api) moderator(admin mobileTokens, email string) mobileTokens {
	a.t.Helper()
	a.signUpVerified(email)
	if r := a.grant(admin, email, "moderator", nil); r.Code != http.StatusCreated {
		a.t.Fatalf("grant moderator %s: %d %s", email, r.Code, r.Body)
	}
	return a.signInMobile(email)
}

func TestTeamOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	a.signUpVerified("bia@example.com")
	a.signUpVerified("caio@example.com")

	a.now = a.now.Add(time.Minute)
	r := a.grant(admin, " Bia@Example.com ", "moderator", map[string]any{"reason": "  Cuida dos retidos.  "})
	if r.Code != http.StatusCreated {
		t.Fatalf("grant moderator: %d %s", r.Code, r.Body)
	}
	bia := decodeMember(t, r)
	if bia.Email != "bia@example.com" || !uuidRE.MatchString(bia.AccountID) || len(bia.Roles) != 1 ||
		bia.Roles[0].Role != "moderator" || bia.Roles[0].GrantedAt == "" || strings.Contains(r.Body.String(), "display_role") {
		t.Fatalf("moderator %s", r.Body)
	}
	a.now = a.now.Add(time.Minute)
	r = a.grant(admin, "caio@example.com", "curator", map[string]any{"display_role": "pedagogo", "verified_professional": true})
	caio := decodeMember(t, r)
	if r.Code != http.StatusCreated || len(caio.Roles) != 1 || caio.Roles[0].DisplayRole == nil || *caio.Roles[0].DisplayRole != "pedagogo" ||
		caio.Roles[0].VerifiedProfessional == nil || !*caio.Roles[0].VerifiedProfessional {
		t.Fatalf("grant curator: %d %s", r.Code, r.Body)
	}

	var list struct {
		Staff []memberResp `json:"staff"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/admin/staff", nil, bearer(admin)...), &list)
	if len(list.Staff) != 3 || list.Staff[0].AccountID != adminID || list.Staff[0].Roles[0].Role != "admin" ||
		list.Staff[0].Roles[0].DisplayRole != nil || list.Staff[1].AccountID != bia.AccountID || list.Staff[2].AccountID != caio.AccountID {
		t.Fatalf("staff %+v", list.Staff)
	}

	r = a.do(http.MethodPatch, "/v1/admin/staff/"+caio.AccountID+"/curator",
		map[string]any{"display_role": "mae-pai", "reason": "Mudou de papel."}, bearer(admin)...)
	if p := decodeMember(t, r); r.Code != http.StatusOK || *p.Roles[0].DisplayRole != "mae-pai" || *p.Roles[0].VerifiedProfessional {
		t.Fatalf("patch: %d %s", r.Code, r.Body)
	}
	revoke := "/v1/admin/staff/" + bia.AccountID + "/roles/moderator/revoke"
	r = a.do(http.MethodPost, revoke, map[string]any{"reason": "Não modera mais."}, bearer(admin)...)
	if r.Code != http.StatusOK || !strings.Contains(r.Body.String(), `"roles":[]`) {
		t.Fatalf("revoke the last role: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, revoke, map[string]any{"reason": "Não modera mais."}, bearer(admin)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("revoke again: %d %q", r.Code, r.problemCode())
	}
	getJSON(t, a.do(http.MethodGet, "/v1/admin/staff", nil, bearer(admin)...), &list)
	if len(list.Staff) != 2 || list.Staff[1].AccountID != caio.AccountID {
		t.Fatalf("an account without roles is still listed: %+v", list.Staff)
	}

	for _, c := range []struct {
		e               audit.Event
		subject, reason string
	}{
		{audit.ModeratorAppointed, bia.AccountID, "Cuida dos retidos."},
		{audit.CuratorAppointed, caio.AccountID, "Entrou na equipe."},
		{audit.CuratorUpdated, caio.AccountID, "Mudou de papel."},
		{audit.ModeratorRemoved, bia.AccountID, "Não modera mais."},
	} {
		x, ok := a.audit.LastAction(c.e)
		if !ok || x.Actor != adminID || x.ActorRole != "admin" || x.SubjectKind != audit.SubjectAccount ||
			x.SubjectID != c.subject || x.Reason != c.reason {
			t.Errorf("%s: %+v %v", c.e, x, ok)
		}
	}
}

func TestTeamCodesOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	a.signUpVerified("bia@example.com")
	a.do(http.MethodPost, "/v1/accounts", signUpBody("caio@example.com")) // never verified
	revoke := func(id, role string, body any) resp {
		return a.do(http.MethodPost, "/v1/admin/staff/"+id+"/roles/"+role+"/revoke", body, bearer(admin)...)
	}
	why := map[string]any{"reason": "Saiu da equipe."}
	for _, c := range []struct {
		name   string
		r      resp
		status int
		code   string
	}{
		{"no reason", a.grant(admin, "bia@example.com", "moderator", map[string]any{"reason": nil}), 422, "reason_required"},
		{"a short reason", a.grant(admin, "bia@example.com", "moderator", map[string]any{"reason": " ab "}), 422, "reason_required"},
		{"the reason before the lookup", a.grant(admin, "nobody@example.com", "moderator", map[string]any{"reason": ""}), 422, "reason_required"},
		{"a malformed body", a.do(http.MethodPost, "/v1/admin/staff", "{", bearer(admin)...), 422, "validation"},
		{"an unknown field", a.grant(admin, "bia@example.com", "moderator", map[string]any{"granted_by": adminID}), 422, "validation"},
		{"admin", a.grant(admin, "bia@example.com", "admin", nil), 403, "admin_cli_only"},
		{"an unknown role", a.grant(admin, "bia@example.com", "owner", nil), 422, "validation"},
		{"a moderator's displayed role", a.grant(admin, "bia@example.com", "moderator", map[string]any{"display_role": "mae-pai"}), 422, "validation"},
		{"an unknown email", a.grant(admin, "nobody@example.com", "moderator", nil), 404, "account_not_found"},
		{"an unverified email", a.grant(admin, "caio@example.com", "moderator", nil), 409, "email_unverified"},
		{"themself", a.grant(admin, " ANA@example.com", "moderator", nil), 403, "self_appointment"},
		{"revoking admin", revoke(adminID, "admin", why), 403, "admin_cli_only"},
		{"revoking without a reason", revoke(adminID, "moderator", map[string]any{}), 422, "reason_required"},
		{"revoking a malformed id", revoke("abc", "moderator", why), 404, "not_found"},
		{"patching a malformed id", a.do(http.MethodPatch, "/v1/admin/staff/abc/curator",
			map[string]any{"display_role": "cuidador", "reason": "Mudou de papel."}, bearer(admin)...), 404, "not_found"},
	} {
		if c.r.Code != c.status || c.r.problemCode() != c.code {
			t.Errorf("%s: %d %q, want %d %s", c.name, c.r.Code, c.r.problemCode(), c.status, c.code)
		}
	}
	if n := a.count(`SELECT count(*) FROM platform_roles WHERE role <> 'admin'`); n != 0 {
		t.Fatalf("a refused write stored %d roles", n)
	}
	if r := a.grant(admin, "bia@example.com", "moderator", nil); r.Code != http.StatusCreated {
		t.Fatalf("grant: %d %s", r.Code, r.Body)
	}
	if r := a.grant(admin, "bia@example.com", "moderator", nil); r.Code != http.StatusConflict || r.problemCode() != "already_has_role" {
		t.Fatalf("grant again: %d %q", r.Code, r.problemCode())
	}
}

func TestTeamWritesNeedAFreshReauth(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.now = a.now.Add(6 * time.Minute)
	admin = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": admin.RefreshToken}))
	for _, p := range []string{"POST /v1/admin/staff", "PATCH /v1/admin/staff/{account_id}/curator",
		"POST /v1/admin/staff/{account_id}/roles/{role}/revoke"} {
		method, path := sweepTarget(p)
		if r := a.do(method, path, map[string]any{"reason": "Motivo válido."}, bearer(admin)...); r.Code != http.StatusForbidden ||
			r.problemCode() != "reauth_required" {
			t.Errorf("%s stale: %d %q", p, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodGet, "/v1/admin/staff", nil, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("listing needs no re-authentication: %d", r.Code)
	}
	if r := a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("reauth: %d %s", r.Code, r.Body)
	}
	a.signUpVerified("bia@example.com")
	if r := a.grant(admin, "bia@example.com", "moderator", nil); r.Code != http.StatusCreated {
		t.Fatalf("after reauth: %d %s", r.Code, r.Body)
	}
}

func TestNoSelfPatchOverTheTeamRoute(t *testing.T) {
	a := newAPI(t)
	ana := a.admin("ana@example.com")
	anaID := a.accountID(ana)
	bob := a.admin("bob@example.com")
	if r := a.grant(bob, "ana@example.com", "curator", map[string]any{"display_role": "mae-pai"}); r.Code != http.StatusCreated {
		t.Fatalf("bob appoints ana: %d %s", r.Code, r.Body)
	}
	r := a.do(http.MethodPatch, "/v1/admin/staff/"+anaID+"/curator",
		map[string]any{"display_role": "pediatra", "verified_professional": true, "reason": "Agora sou pediatra."}, bearer(ana)...)
	if r.Code != http.StatusForbidden || r.problemCode() != "self_appointment" {
		t.Fatalf("self-patch: %d %q", r.Code, r.problemCode())
	}
	if n := a.count(`SELECT count(*) FROM platform_roles WHERE role = 'curator' AND display_role = 'mae-pai' AND NOT verified_professional`); n != 1 {
		t.Fatalf("a refused self-patch changed the row (%d unchanged)", n)
	}
}

func TestTheOldAdminRoutesAreGone(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.signUpVerified("bia@example.com")
	const id = "/00000000-0000-0000-0000-000000000000"
	body := map[string]any{"email": "bia@example.com", "display_role": "mae-pai", "reason": "Motivo válido."}
	for _, p := range []string{"GET /v1/admin/curators", "POST /v1/admin/curators",
		"PATCH /v1/admin/curators" + id, "DELETE /v1/admin/curators" + id, "GET /v1/admin/videos?state=held",
		"POST /v1/admin/videos" + id + "/remove", "POST /v1/admin/videos" + id + "/reopen"} {
		method, path, _ := strings.Cut(p, " ")
		if r := a.do(method, path, body, bearer(admin)...); r.Code != http.StatusNotFound {
			t.Errorf("%s: %d %s", p, r.Code, r.Body)
		}
	}
	for _, rt := range a.server.Routes() {
		if strings.Contains(rt.Pattern, " /v1/admin/curators") || strings.Contains(rt.Pattern, " /v1/admin/videos") {
			t.Errorf("still registered: %s", rt.Pattern)
		}
	}
}
