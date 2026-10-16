package httpapi_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

type familyResp struct {
	ID      string `json:"id"`
	Role    string `json:"role"`
	Members []struct {
		AccountID string `json:"account_id"`
		Email     string `json:"email"`
		Role      string `json:"role"`
	} `json:"members"`
	Minors []struct {
		ID       string `json:"id"`
		Nickname string `json:"nickname"`
		Avatar   string `json:"avatar"`
		AgeBand  string `json:"age_band"`
	} `json:"minors"`
	PendingInvitations int `json:"pending_invitations"`
	Invitations        *[]struct {
		ID    string `json:"id"`
		Email string `json:"email"`
	} `json:"invitations"`
}

func decodeFamily(t *testing.T, r resp) familyResp {
	t.Helper()
	var f familyResp
	if err := json.Unmarshal(r.Body.Bytes(), &f); err != nil {
		t.Fatalf("family body: %v %s", err, r.Body)
	}
	return f
}

// familyOwner signs a verified guardian up and in, and creates their family.
func (a *api) familyOwner(email string) mobileTokens {
	a.t.Helper()
	a.signUpVerified(email)
	tok := a.signInMobile(email)
	if r := a.do(http.MethodPost, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusCreated {
		a.t.Fatalf("create family: %d %s", r.Code, r.Body)
	}
	return tok
}

func TestCreateAndGetFamily(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")

	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusNotFound || r.problemCode() != "no_family" {
		t.Fatalf("before: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodPost, "/v1/family", nil, bearer(tok)...)
	if r.Code != http.StatusCreated {
		t.Fatalf("create: %d %s", r.Code, r.Body)
	}
	created := decodeFamily(t, r)
	if created.Role != "owner" || len(created.Members) != 1 || created.Members[0].Email != "ana@example.com" ||
		created.Minors == nil || created.Invitations == nil || len(*created.Invitations) != 0 {
		t.Fatalf("created: %s", r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusConflict || r.problemCode() != "already_in_family" {
		t.Fatalf("second: %d %q", r.Code, r.problemCode())
	}
	got := a.do(http.MethodGet, "/v1/family", nil, bearer(tok)...)
	if got.Code != http.StatusOK || decodeFamily(t, got).ID != created.ID {
		t.Fatalf("get: %d %s", got.Code, got.Body)
	}
}

func TestCreateFamilyNeedsAVerifiedEmail(t *testing.T) {
	a := newAPI(t)
	a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com"))
	tok := a.signInMobile("ana@example.com")
	if r := a.do(http.MethodPost, "/v1/family", nil, bearer(tok)...); r.Code != http.StatusForbidden || r.problemCode() != "email_unverified" {
		t.Fatalf("unverified: %d %q", r.Code, r.problemCode())
	}
}

func TestFamilyWritesNeedCSRFOnTheWeb(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, csrf := a.signInWeb("ana@example.com")
	if r := a.do(http.MethodPost, "/v1/family", nil, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("no token: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/family", nil, "Cookie", cookie, "X-CSRF-Token", csrf); r.Code != http.StatusCreated {
		t.Fatalf("with token: %d %s", r.Code, r.Body)
	}
}

func TestCORSAllowsPatch(t *testing.T) {
	a := newAPI(t, func(s *httpapi.Server) { s.AllowedOrigins = []string{"https://app.test"} })
	r := a.do(http.MethodOptions, "/v1/family/minors/x", nil, "Origin", "https://app.test", "Access-Control-Request-Method", "PATCH")
	if r.Code != http.StatusNoContent || !strings.Contains(r.Header().Get("Access-Control-Allow-Methods"), "PATCH") {
		t.Fatalf("preflight: %d %q", r.Code, r.Header().Get("Access-Control-Allow-Methods"))
	}
}

// joinFamily invites a new verified guardian and accepts for them.
func (a *api) joinFamily(owner mobileTokens, email string) mobileTokens {
	a.t.Helper()
	if r := a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": email}, bearer(owner)...); r.Code != http.StatusCreated {
		a.t.Fatalf("invite: %d %s", r.Code, r.Body)
	}
	tok := a.lastToken(email)
	a.signUpVerified(email)
	g := a.signInMobile(email)
	if r := a.do(http.MethodPost, "/v1/invitations/accept", map[string]string{"token": tok}, bearer(g)...); r.Code != http.StatusOK {
		a.t.Fatalf("accept: %d %s", r.Code, r.Body)
	}
	return g
}

// memberID finds a member by email: joins in one test share the fixed
// clock, so members after the owner have no stable order.
func memberID(t *testing.T, f familyResp, email string) string {
	t.Helper()
	for _, m := range f.Members {
		if m.Email == email {
			return m.AccountID
		}
	}
	t.Fatalf("no member %s", email)
	return ""
}

func TestInvitationFlowOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	r := a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": "bia@example.com"}, bearer(ana)...)
	var inv struct {
		ID, Email string
		ExpiresAt string `json:"expires_at"`
	}
	json.Unmarshal(r.Body.Bytes(), &inv)
	if r.Code != http.StatusCreated || inv.ID == "" || inv.Email != "bia@example.com" || inv.ExpiresAt == "" {
		t.Fatalf("invite: %d %s", r.Code, r.Body)
	}
	tok := a.lastToken("bia@example.com")
	a.signUpVerified("bia@example.com")
	bia := a.signInMobile("bia@example.com")

	look := a.do(http.MethodPost, "/v1/invitations/lookup", map[string]string{"token": tok}, bearer(bia)...)
	var p map[string]string
	json.Unmarshal(look.Body.Bytes(), &p)
	if look.Code != http.StatusOK || p["inviter_email"] != "ana@example.com" || p["invited_email"] != "bia@example.com" || p["expires_at"] == "" {
		t.Fatalf("lookup: %d %s", look.Code, look.Body)
	}
	acc := a.do(http.MethodPost, "/v1/invitations/accept", map[string]string{"token": tok}, bearer(bia)...)
	if acc.Code != http.StatusOK || decodeFamily(t, acc).Role != "guardian" {
		t.Fatalf("accept: %d %s", acc.Code, acc.Body)
	}
	if strings.Contains(acc.Body.String(), `"invitations"`) {
		t.Fatal("a guardian received the invitations list")
	}
	owner := decodeFamily(t, a.do(http.MethodGet, "/v1/family", nil, bearer(ana)...))
	if len(owner.Members) != 2 || owner.Invitations == nil || len(*owner.Invitations) != 0 {
		t.Fatalf("owner view: %+v", owner)
	}
}

func TestInviteDoesNotRevealTheAddress(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	a.do(http.MethodPost, "/v1/accounts", signUpBody("unverified@example.com"))
	a.familyOwner("elsewhere@example.com")
	var shapes []string
	for _, addr := range []string{"nobody@example.com", "unverified@example.com", "elsewhere@example.com"} {
		r := a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": addr}, bearer(ana)...)
		var body map[string]any
		json.Unmarshal(r.Body.Bytes(), &body)
		keys := make([]string, 0, len(body))
		for k := range body {
			keys = append(keys, k)
		}
		slices.Sort(keys)
		shapes = append(shapes, fmt.Sprint(r.Code, keys))
	}
	if shapes[0] != shapes[1] || shapes[1] != shapes[2] {
		t.Fatalf("answers differ: %v", shapes)
	}
}

func TestInvitationErrorsOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	bia := a.joinFamily(ana, "bia@example.com")

	check := func(name string, r resp, status int, code string) {
		t.Helper()
		if r.Code != status || r.problemCode() != code {
			t.Errorf("%s: %d %q, want %d %q", name, r.Code, r.problemCode(), status, code)
		}
	}
	check("not owner", a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": "c@example.com"}, bearer(bia)...), 403, "not_owner")
	check("member", a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": "bia@example.com"}, bearer(ana)...), 409, "already_member")
	check("revoke unknown", a.do(http.MethodDelete, "/v1/family/invitations/not-a-uuid", nil, bearer(ana)...), 404, "not_found")

	a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": "carla@example.com"}, bearer(ana)...)
	tok := a.lastToken("carla@example.com")
	a.signUpVerified("dani@example.com")
	dani := a.signInMobile("dani@example.com")
	check("mismatch", a.do(http.MethodPost, "/v1/invitations/accept", map[string]string{"token": tok}, bearer(dani)...), 403, "invitation_email_mismatch")
	check("bad token", a.do(http.MethodPost, "/v1/invitations/lookup", map[string]string{"token": "nope"}, bearer(dani)...), 400, "invalid_token")
	for range 8 {
		a.do(http.MethodPost, "/v1/invitations/lookup", map[string]string{"token": "nope"}, bearer(dani)...)
	}
	r := a.do(http.MethodPost, "/v1/invitations/lookup", map[string]string{"token": "nope"}, bearer(dani)...)
	check("throttled", r, 429, "rate_limited")
	if r.Header().Get("Retry-After") == "" {
		t.Error("429 without Retry-After")
	}
}

func TestGuardianRoutes(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	bia := a.joinFamily(ana, "bia@example.com")
	carla := a.joinFamily(ana, "carla@example.com")
	biaID := memberID(t, decodeFamily(t, a.do(http.MethodGet, "/v1/family", nil, bearer(ana)...)), "bia@example.com")

	if r := a.do(http.MethodPost, "/v1/family/leave", nil, bearer(ana)...); r.Code != http.StatusConflict || r.problemCode() != "owner_must_transfer" {
		t.Fatalf("owner leaves: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/family/leave", nil, bearer(carla)...); r.Code != http.StatusNoContent {
		t.Fatalf("leave: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodDelete, "/v1/family/members/"+biaID, nil, bearer(ana)...); r.Code != http.StatusNoContent {
		t.Fatalf("remove: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(bia)...); r.Code != http.StatusNotFound || r.problemCode() != "no_family" {
		t.Fatalf("removed guardian: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(bia)...); r.Code != http.StatusOK {
		t.Fatal("removal ended the guardian's session")
	}
}

func TestTransferRequiresReauth(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	a.joinFamily(ana, "bia@example.com")
	biaID := memberID(t, decodeFamily(t, a.do(http.MethodGet, "/v1/family", nil, bearer(ana)...)), "bia@example.com")
	a.now = a.now.Add(6 * time.Minute)
	ana = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": ana.RefreshToken}))

	body := map[string]string{"account_id": biaID}
	if r := a.do(http.MethodPost, "/v1/family/owner", body, bearer(ana)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale: %d %q", r.Code, r.problemCode())
	}
	a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(ana)...)
	r := a.do(http.MethodPost, "/v1/family/owner", body, bearer(ana)...)
	if r.Code != http.StatusOK || decodeFamily(t, r).Role != "guardian" {
		t.Fatalf("transfer: %d %s", r.Code, r.Body)
	}
}

func minorReq(version string) map[string]any {
	return map[string]any{"nickname": "Lia", "avatar": "fox", "age_band": "5-8", "consent": map[string]string{"policy_version": version}}
}

func TestMinorsOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	r := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), bearer(ana)...)
	var m struct {
		ID, Nickname, Avatar string
		AgeBand              string `json:"age_band"`
	}
	json.Unmarshal(r.Body.Bytes(), &m)
	if r.Code != http.StatusCreated || m.ID == "" || m.Nickname != "Lia" || m.AgeBand != "5-8" {
		t.Fatalf("create: %d %s", r.Code, r.Body)
	}
	p := a.do(http.MethodPatch, "/v1/family/minors/"+m.ID, map[string]string{"avatar": "owl"}, bearer(ana)...)
	if p.Code != http.StatusOK || !strings.Contains(p.Body.String(), `"avatar":"owl"`) || !strings.Contains(p.Body.String(), `"nickname":"Lia"`) {
		t.Fatalf("patch: %d %s", p.Code, p.Body)
	}
	if got := decodeFamily(t, a.do(http.MethodGet, "/v1/family", nil, bearer(ana)...)); len(got.Minors) != 1 || got.Minors[0].Avatar != "owl" {
		t.Fatalf("family: %+v", got)
	}
	if d := a.do(http.MethodDelete, "/v1/family/minors/"+m.ID, nil, bearer(ana)...); d.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", d.Code, d.Body)
	}
}

func TestMinorRequestErrors(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	carla := a.familyOwner("carla@example.com")
	r := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), bearer(ana)...)
	var m struct{ ID string }
	json.Unmarshal(r.Body.Bytes(), &m)

	check := func(name string, r resp, status int, code string) {
		t.Helper()
		if r.Code != status || r.problemCode() != code {
			t.Errorf("%s: %d %q, want %d %q", name, r.Code, r.problemCode(), status, code)
		}
	}
	noConsent := map[string]any{"nickname": "Lia", "avatar": "fox", "age_band": "5-8"}
	check("no consent", a.do(http.MethodPost, "/v1/family/minors", noConsent, bearer(ana)...), 422, "validation")
	check("outdated", a.do(http.MethodPost, "/v1/family/minors", minorReq("2025-01-01"), bearer(ana)...), 409, "policy_outdated")
	check("bad avatar", a.do(http.MethodPost, "/v1/family/minors", map[string]any{"nickname": "Lia", "avatar": "dragon", "age_band": "5-8",
		"consent": map[string]string{"policy_version": family.ConsentPolicyVersion}}, bearer(ana)...), 422, "validation")
	check("empty patch", a.do(http.MethodPatch, "/v1/family/minors/"+m.ID, map[string]any{}, bearer(ana)...), 422, "validation")
	check("null patch", a.do(http.MethodPatch, "/v1/family/minors/"+m.ID, `{"nickname":null}`, bearer(ana)...), 422, "validation")
	check("unknown field", a.do(http.MethodPatch, "/v1/family/minors/"+m.ID, map[string]any{"photo": "x"}, bearer(ana)...), 422, "validation")
	check("malformed id", a.do(http.MethodPatch, "/v1/family/minors/abc", map[string]string{"avatar": "owl"}, bearer(ana)...), 404, "not_found")
	check("foreign patch", a.do(http.MethodPatch, "/v1/family/minors/"+m.ID, map[string]string{"avatar": "owl"}, bearer(carla)...), 404, "not_found")
	check("foreign delete", a.do(http.MethodDelete, "/v1/family/minors/"+m.ID, nil, bearer(carla)...), 404, "not_found")
}

func TestDeleteMinorRequiresReauth(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	r := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), bearer(ana)...)
	var m struct{ ID string }
	json.Unmarshal(r.Body.Bytes(), &m)
	a.now = a.now.Add(6 * time.Minute)
	ana = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": ana.RefreshToken}))
	if r := a.do(http.MethodDelete, "/v1/family/minors/"+m.ID, nil, bearer(ana)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale: %d %q", r.Code, r.problemCode())
	}
}

func TestPatchNeedsCSRFOnTheWeb(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, csrf := a.signInWeb("ana@example.com")
	a.do(http.MethodPost, "/v1/family", nil, "Cookie", cookie, "X-CSRF-Token", csrf)
	r := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), "Cookie", cookie, "X-CSRF-Token", csrf)
	var m struct{ ID string }
	json.Unmarshal(r.Body.Bytes(), &m)
	if r := a.do(http.MethodPatch, "/v1/family/minors/"+m.ID, map[string]string{"avatar": "owl"}, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("patch without token: %d %q", r.Code, r.problemCode())
	}
}

func TestDeleteFamilyOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	bia := a.joinFamily(ana, "bia@example.com")
	stale := ana
	a.now = a.now.Add(6 * time.Minute)
	stale = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": stale.RefreshToken}))
	if r := a.do(http.MethodDelete, "/v1/family", nil, bearer(stale)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale: %d %q", r.Code, r.problemCode())
	}
	a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(stale)...)
	if r := a.do(http.MethodDelete, "/v1/family", nil, bearer(stale)...); r.Code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(bia)...); r.Code != http.StatusNotFound || r.problemCode() != "no_family" {
		t.Fatalf("guardian after deletion: %d %q", r.Code, r.problemCode())
	}
}

var uuidRE = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func TestFamilyAuditCarriesIDsOnly(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	r := a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": "x@example.com"}, bearer(ana)...)
	var inv struct{ ID string }
	json.Unmarshal(r.Body.Bytes(), &inv)
	a.do(http.MethodDelete, "/v1/family/invitations/"+inv.ID, nil, bearer(ana)...)
	bia := a.joinFamily(ana, "bia@example.com")
	carla := a.joinFamily(ana, "carla@example.com")
	view := decodeFamily(t, a.do(http.MethodGet, "/v1/family", nil, bearer(ana)...))
	biaID, anaID := memberID(t, view, "bia@example.com"), memberID(t, view, "ana@example.com")
	a.do(http.MethodPost, "/v1/family/leave", nil, bearer(carla)...)
	m := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), bearer(bia)...)
	var minor struct{ ID string }
	json.Unmarshal(m.Body.Bytes(), &minor)
	a.do(http.MethodPatch, "/v1/family/minors/"+minor.ID, map[string]string{"avatar": "owl"}, bearer(bia)...)
	a.do(http.MethodDelete, "/v1/family/minors/"+minor.ID, nil, bearer(bia)...)
	a.do(http.MethodPost, "/v1/family/owner", map[string]string{"account_id": biaID}, bearer(ana)...)
	a.do(http.MethodDelete, "/v1/family/members/"+anaID, nil, bearer(bia)...)
	a.do(http.MethodDelete, "/v1/family", nil, bearer(bia)...)

	want := map[audit.Event]bool{
		audit.FamilyCreated: false, audit.InvitationSent: false, audit.InvitationRevoked: false,
		audit.InvitationAccepted: false, audit.GuardianRemoved: false, audit.GuardianLeft: false,
		audit.OwnershipTransferred: false, audit.MinorCreated: false, audit.MinorUpdated: false,
		audit.MinorDeleted: false, audit.FamilyDeleted: false,
	}
	for _, e := range a.audit.Entries {
		if _, ok := want[e.Event]; !ok {
			continue
		}
		want[e.Event] = true
		if !uuidRE.MatchString(e.AccountID) {
			t.Errorf("%s carries %q, not an account ID", e.Event, e.AccountID)
		}
	}
	for e, seen := range want {
		if !seen {
			t.Errorf("no %s event", e)
		}
	}
}

func TestDeleteMinorNeedsCSRFOnTheWeb(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, csrf := a.signInWeb("ana@example.com")
	a.do(http.MethodPost, "/v1/family", nil, "Cookie", cookie, "X-CSRF-Token", csrf)
	r := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), "Cookie", cookie, "X-CSRF-Token", csrf)
	var m struct{ ID string }
	json.Unmarshal(r.Body.Bytes(), &m)
	if r := a.do(http.MethodDelete, "/v1/family/minors/"+m.ID, nil, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("delete without token: %d %q", r.Code, r.problemCode())
	}
}
