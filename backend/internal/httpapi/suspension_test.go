package httpapi_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// suspensionMails counts the suspension notices sent to addr.
func (a *api) suspensionMails(addr string) int {
	n := 0
	for _, m := range a.mail.To(addr) {
		if strings.Contains(m.Subject, "suspensa") {
			n++
		}
	}
	return n
}

func TestSuspendAndReinstateOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	bia := a.moderator(admin, "bia@example.com")
	biaID := a.accountID(bia)
	base := "/v1/admin/accounts/" + biaID

	r := a.do(http.MethodPost, base+"/suspend", map[string]any{"reason": suspendReason}, bearer(admin)...)
	sh := decodeSheet(t, r)
	if r.Code != http.StatusOK || sh.Suspension == nil || sh.Suspension.Reason != suspendReason ||
		sh.Suspension.Since != "2026-10-02T12:00:00Z" || len(sh.Roles) != 0 || len(sh.Sessions) != 0 || len(sh.Actions) != 1 {
		t.Fatalf("suspend: %d %s", r.Code, r.Body)
	}
	var first struct {
		Event string `json:"event"`
	}
	if err := json.Unmarshal(sh.Actions[0], &first); err != nil || first.Event != "account_suspended" {
		t.Fatalf("the sheet's action %s %v", sh.Actions[0], err)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(bia)...); r.Code != http.StatusUnauthorized {
		t.Fatalf("a session from before the suspension lives on: %d", r.Code)
	}
	if n := a.count(`SELECT count(*) FROM audit_events WHERE event = 'account_suspended' AND account_id = $1::uuid
		AND actor_role = 'admin' AND subject_kind = 'account' AND subject_id = $2::uuid AND reason = $3
		AND metadata = '{"sessions": "1", "roles": "moderator"}'::jsonb`, adminID, biaID, suspendReason); n != 1 {
		t.Fatal("no audited suspension with its metadata")
	}
	msgs := a.mail.To("bia@example.com")
	if a.suspensionMails("bia@example.com") != 1 || strings.Contains(msgs[len(msgs)-1].Body, suspendReason) {
		t.Fatal("the notice is missing or carries the reason")
	}
	var page auditPageResp
	getJSON(t, a.do(http.MethodGet, "/v1/admin/audit", nil, bearer(admin)...), &page)
	if len(page.Actions) == 0 || page.Actions[0].Event != "account_suspended" {
		t.Fatalf("the staff audit log %+v", page.Actions)
	}

	bia = a.signInMobile("bia@example.com")
	if r := a.do(http.MethodGet, "/v1/sessions", nil, bearer(bia)...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
		t.Fatalf("a suspended session: %d %q", r.Code, r.problemCode())
	}
	const why = "Revisão: denúncia improcedente."
	r = a.do(http.MethodPost, base+"/reinstate", map[string]any{"reason": why}, bearer(admin)...)
	sh = decodeSheet(t, r)
	if r.Code != http.StatusOK || sh.Suspension != nil || !strings.Contains(r.Body.String(), `"suspension":null`) ||
		len(sh.Roles) != 0 || len(sh.Sessions) != 1 {
		t.Fatalf("reinstate: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/sessions", nil, bearer(bia)...); r.Code != http.StatusOK {
		t.Fatalf("a reinstated session's next request: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(bia)...); r.Code != http.StatusForbidden ||
		r.problemCode() != "not_moderator" {
		t.Fatalf("the reinstatement restored a role: %d %q", r.Code, r.problemCode())
	}
	msgs = a.mail.To("bia@example.com")
	if last := msgs[len(msgs)-1]; !strings.Contains(last.Subject, "reativada") || strings.Contains(last.Body, why) {
		t.Fatalf("reinstatement notice %+v", last)
	}
	if n := a.count(`SELECT count(*) FROM audit_events WHERE event = 'account_reinstated' AND subject_id = $1::uuid AND reason = $2`,
		biaID, why); n != 1 {
		t.Fatal("no audited reinstatement")
	}
}

func TestSuspensionRefusalsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	otherID := a.accountID(a.admin("dani@example.com"))
	a.signUpVerified("bia@example.com")
	biaID := a.accountID(a.signInMobile("bia@example.com"))
	const unknown = "00000000-0000-0000-0000-000000000000"
	good := map[string]any{"reason": suspendReason}
	for _, c := range []struct {
		path   string
		body   any
		status int
		code   string
	}{
		{"/v1/admin/accounts/" + adminID + "/suspend", good, http.StatusForbidden, "self_action"},
		{"/v1/admin/accounts/" + otherID + "/suspend", good, http.StatusForbidden, "subject_is_admin"},
		{"/v1/admin/accounts/" + unknown + "/suspend", good, http.StatusNotFound, "account_not_found"},
		{"/v1/admin/accounts/abc/suspend", good, http.StatusNotFound, "account_not_found"},
		{"/v1/admin/accounts/" + biaID + "/suspend", map[string]any{"reason": "ok"}, http.StatusUnprocessableEntity, "reason_required"},
		{"/v1/admin/accounts/" + biaID + "/suspend", `{"reason": 1}`, http.StatusUnprocessableEntity, "validation"},
		{"/v1/admin/accounts/" + biaID + "/reinstate", good, http.StatusConflict, "not_suspended"},
		{"/v1/admin/accounts/" + adminID + "/reinstate", good, http.StatusForbidden, "self_action"},
	} {
		if r := a.do(http.MethodPost, c.path, c.body, bearer(admin)...); r.Code != c.status || r.problemCode() != c.code {
			t.Errorf("%s: %d %q, want %d %s", c.path, r.Code, r.problemCode(), c.status, c.code)
		}
	}
	if n := a.count(`SELECT count(*) FROM audit_events`); n != 0 ||
		a.suspensionMails("bia@example.com")+a.suspensionMails("dani@example.com") != 0 {
		t.Fatal("a refused suspension was audited or mailed")
	}
	suspend := func() resp {
		return a.do(http.MethodPost, "/v1/admin/accounts/"+biaID+"/suspend", good, bearer(admin)...)
	}
	if r := suspend(); r.Code != http.StatusOK {
		t.Fatalf("suspend: %d %s", r.Code, r.Body)
	}
	if r := suspend(); r.Code != http.StatusConflict || r.problemCode() != "already_suspended" {
		t.Fatalf("a second suspension: %d %q", r.Code, r.problemCode())
	}
	if n := a.count(`SELECT count(*) FROM audit_events WHERE event = 'account_suspended'`); n != 1 || a.suspensionMails("bia@example.com") != 1 {
		t.Fatal("a second suspension audited or mailed again")
	}
	// The kind's checks come first: a stale re-auth refuses before the body.
	a.now = a.now.Add(6 * time.Minute)
	admin = a.refresh(admin)
	if r := a.do(http.MethodPost, "/v1/admin/accounts/"+biaID+"/reinstate", map[string]any{"reason": "ok"}, bearer(admin)...); r.Code != http.StatusForbidden ||
		r.problemCode() != "reauth_required" {
		t.Fatalf("stale re-auth: %d %q", r.Code, r.problemCode())
	}
}

func TestGrantToASuspendedAccountOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.signUpVerified("bia@example.com")
	biaID := a.accountID(a.signInMobile("bia@example.com"))
	if r := a.do(http.MethodPost, "/v1/admin/accounts/"+biaID+"/suspend", map[string]any{"reason": suspendReason}, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("suspend: %d %s", r.Code, r.Body)
	}
	if r := a.grant(admin, "bia@example.com", "moderator", nil); r.Code != http.StatusConflict || r.problemCode() != "account_suspended" {
		t.Fatalf("a grant to a suspended account: %d %q", r.Code, r.problemCode())
	}
	if n := a.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid`, biaID); n != 0 {
		t.Fatal("the grant inserted a role")
	}
}

// TestASignInInFlightLosesToASuspension pins the race end to end. Its
// mechanism is the account lock and the credential version bump.
func TestASignInInFlightLosesToASuspension(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	a.signUpVerified("bia@example.com")
	biaID := a.accountID(a.signInMobile("bia@example.com"))
	a.onAuditKind = audit.SignInSucceeded
	a.onAudit = func() { a.suspend(root, biaID) } // past the password check, before the session exists
	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "bia@example.com", "password": goodPassword, "client": "mobile"})
	if r.Code != http.StatusUnauthorized || r.problemCode() != "invalid_credentials" {
		t.Fatalf("a sign-in past its check when the suspension commits: %d %s", r.Code, r.Body)
	}
	if n := a.count(`SELECT count(*) FROM sessions WHERE account_id = $1::uuid AND revoked_at IS NULL`, biaID); n != 0 {
		t.Fatalf("%d sessions survived", n)
	}
}
