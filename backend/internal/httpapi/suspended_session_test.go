package httpapi_test

import (
	"context"
	"maps"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

const suspendReason = "Denúncia de conteúdo impróprio."

// suspend has the staff service suspend accountID as actorID, as the
// admin route does: the account's sessions end and its roles drop.
func (a *api) suspend(actorID, accountID string) {
	a.t.Helper()
	if _, err := a.team.Suspend(context.Background(), actorID, accountID, suspendReason); err != nil {
		a.t.Fatal(err)
	}
}

// markSuspended sets the account's status as a suspension does but leaves
// its sessions and roles. That is how a session the suspension did not
// see (a Google sign-in in flight) finds them.
func (a *api) markSuspended(accountID string) {
	a.t.Helper()
	a.exec(`UPDATE accounts SET status = 'suspended', suspended_at = $2, suspension_reason = $3 WHERE id = $1::uuid`,
		accountID, a.now, suspendReason)
}

// allowList is the suspended allow-list, ordered so the session lasts to the
// end: an owner's erasure is refused while the family stands.
var allowList = []string{
	"GET /v1/session",
	"POST /v1/session/reauth",
	"POST /v1/account/terms",
	"GET /v1/account/export",
	"GET /v1/family",
	"POST /v1/family/owner",
	"DELETE /v1/account",
	"DELETE /v1/family",
	"DELETE /v1/session",
}

func TestEverySessionRouteRefusesASuspendedAccountButTheAllowList(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	a.suspend(root, a.accountID(a.familyOwner("bia@example.com")))
	bia := a.signInMobile("bia@example.com")

	allowed := map[string]bool{}
	for _, p := range allowList {
		allowed[p] = true
	}
	flagged := map[string]bool{}
	kinds := map[httpapi.RouteKind]int{}
	for _, rt := range a.server.Routes() {
		if rt.SuspendedOK {
			flagged[rt.Pattern] = true
		}
		if rt.Kind == httpapi.PublicRoute || allowed[rt.Pattern] {
			continue
		}
		kinds[rt.Kind]++
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", bearer(bia)...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
			t.Errorf("%s: %d %q, want 403 account_suspended", rt.Pattern, r.Code, r.problemCode())
		}
	}
	if !maps.Equal(flagged, allowed) {
		t.Fatalf("the routes flagged suspendedOK are %v, want exactly the allow-list %v", flagged, allowed)
	}
	for _, k := range []httpapi.RouteKind{httpapi.GuardianRoute, httpapi.ChildRoute, httpapi.CuratorRoute, httpapi.AdminRoute,
		httpapi.ModeratorRoute, httpapi.StaffRoute} {
		if kinds[k] == 0 {
			t.Errorf("the sweep reached no %s route", k)
		}
	}
	for _, p := range allowList {
		method, path := sweepTarget(p)
		r := a.do(method, path, "{}", bearer(bia)...)
		if r.problemCode() == "account_suspended" || r.Code == http.StatusUnauthorized || r.Code >= 500 {
			t.Errorf("%s on the allow-list: %d %q", p, r.Code, r.problemCode())
		}
	}
}

func TestSuspendedComesBeforeEveryOtherSessionCheck(t *testing.T) {
	a := newAPI(t, mfaRequired)
	locked, _ := a.lockedSession("bia@example.com")
	plain := a.familyOwner("caio@example.com")
	dani := a.admin("dani@example.com") // the admin role, no MFA factor
	cookie, _ := a.signInWeb("caio@example.com")
	for _, tok := range []mobileTokens{locked, plain, dani} {
		a.markSuspended(a.accountID(tok))
	}

	for _, c := range []struct {
		name, path string
		headers    []string
	}{
		{"a session locked to a child, before kid_mode", "/v1/sessions", bearer(locked)},
		{"an admin without a factor, before mfa_enrollment_required", "/v1/admin/staff", bearer(dani)},
		{"a guardian without the role, before not_admin", "/v1/admin/staff", bearer(plain)},
		{"a web session", "/v1/sessions", []string{"Cookie", cookie}},
	} {
		if r := a.do(http.MethodGet, c.path, nil, c.headers...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
			t.Errorf("%s: %d %q", c.name, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, "Cookie", cookie); r.Code != http.StatusOK ||
		!strings.Contains(r.Body.String(), `"status":"suspended"`) {
		t.Fatalf("a suspended web session's GET /v1/session: %d %s", r.Code, r.Body)
	}

	a.now = a.now.Add(6 * time.Minute)
	plain = a.refresh(plain) // the refresh stays public; its new token is just as restricted
	if r := a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(plain)...); r.Code != http.StatusForbidden ||
		r.problemCode() != "account_suspended" {
		t.Fatalf("a stale re-auth, before reauth_required: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/account/export", nil, bearer(plain)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("the allow-list keeps its own checks: %d %q", r.Code, r.problemCode())
	}
}

func TestTheStatusIsReadOnEveryRequest(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("bia@example.com")
	id := a.accountID(tok)
	sessions := func() resp { return a.do(http.MethodGet, "/v1/sessions", nil, bearer(tok)...) }

	if r := sessions(); r.Code != http.StatusOK {
		t.Fatalf("active: %d %s", r.Code, r.Body)
	}
	a.markSuspended(id)
	if r := sessions(); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
		t.Fatalf("the next request after the suspension: %d %q", r.Code, r.problemCode())
	}
	a.exec(`UPDATE accounts SET status = 'active', suspended_at = NULL, suspension_reason = NULL WHERE id = $1::uuid`, id)
	if r := sessions(); r.Code != http.StatusOK {
		t.Fatalf("the next request after the reinstatement: %d %s", r.Code, r.Body)
	}
}

func TestGetSessionCarriesTheStatus(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.moderator(admin, "bia@example.com")
	type sessionBody struct {
		Account struct {
			Status string `json:"status"`
		} `json:"account"`
		Roles []string `json:"roles"`
	}
	var before sessionBody
	getJSON(t, a.do(http.MethodGet, "/v1/session", nil, bearer(admin)...), &before)
	if before.Account.Status != "active" || !slices.Equal(before.Roles, []string{"admin"}) {
		t.Fatalf("an active admin: %+v", before)
	}
	a.suspend(a.accountID(admin), a.accountID(a.signInMobile("bia@example.com")))
	r := a.do(http.MethodGet, "/v1/session", nil, bearer(a.signInMobile("bia@example.com"))...)
	var after sessionBody
	getJSON(t, r, &after)
	if after.Account.Status != "suspended" || !strings.Contains(r.Body.String(), `"roles":[]`) {
		t.Fatalf("a suspended moderator: %s", r.Body)
	}
}

func TestASuspendedAccountStillSignsIn(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	gil := a.providerSignUpMobile("g-gil", "gil@example.com")
	a.suspend(root, a.accountID(gil))
	again := decodeTokens(t, a.do(http.MethodPost, "/v1/sessions/provider",
		map[string]string{"provider": "google", "id_token": a.googleToken("g-gil", "gil@example.com"), "client": "mobile"}))
	if r := a.do(http.MethodGet, "/v1/sessions", nil, bearer(again)...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
		t.Fatalf("a Google session of a suspended account: %d %q", r.Code, r.problemCode())
	}

	a.signUpVerified("bia@example.com")
	a.suspend(root, a.accountID(a.signInMobile("bia@example.com")))
	bia := a.signInMobile("bia@example.com") // fails the test unless 201
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(bia)...); r.Code != http.StatusOK {
		t.Fatalf("a password session of a suspended account: %d %s", r.Code, r.Body)
	}
	mails := len(a.mail.To("bia@example.com"))
	if r := a.do(http.MethodPost, "/v1/password-resets", map[string]string{"email": "bia@example.com"}); r.Code != http.StatusAccepted ||
		len(a.mail.To("bia@example.com")) != mails+1 {
		t.Fatalf("the password reset of a suspended account: %d", r.Code)
	}
}

func TestASuspendedOwnerTakesTheErasureSteps(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	owner := a.familyOwner("bia@example.com")
	caio := a.joinFamily(owner, "caio@example.com")
	caioID := a.accountID(caio)
	a.suspend(root, a.accountID(owner))
	bia := a.signInMobile("bia@example.com")

	if r := a.do(http.MethodGet, "/v1/sessions", nil, bearer(bia)...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
		t.Fatalf("outside the allow-list: %d %q", r.Code, r.problemCode())
	}
	for _, st := range []struct {
		method, path string
		body         any
		status       int
	}{
		{http.MethodDelete, "/v1/account", nil, http.StatusConflict}, // owner_must_transfer: the owner's step first
		{http.MethodGet, "/v1/family", nil, http.StatusOK},
		{http.MethodPost, "/v1/family/owner", map[string]string{"account_id": caioID}, http.StatusOK},
		{http.MethodGet, "/v1/account/export", nil, http.StatusOK},
		{http.MethodDelete, "/v1/account", nil, http.StatusNoContent},
	} {
		if r := a.do(st.method, st.path, st.body, bearer(bia)...); r.Code != st.status {
			t.Fatalf("%s %s: %d %s", st.method, st.path, r.Code, r.Body)
		}
	}
	if n := a.count(`SELECT count(*) FROM accounts WHERE email = 'bia@example.com'`); n != 0 {
		t.Fatal("the suspended account survived its erasure")
	}
	if msgs := a.mail.To("bia@example.com"); !strings.Contains(msgs[len(msgs)-1].Subject, "excluída") {
		t.Fatal("the erasure notice was not sent")
	}
	if r := a.do(http.MethodGet, "/v1/family", nil, bearer(caio)...); r.Code != http.StatusOK {
		t.Fatalf("the new owner's family: %d %s", r.Code, r.Body)
	}

	// The family's only guardian deletes the family, then the account.
	a.suspend(root, a.accountID(a.familyOwner("dani@example.com")))
	dani := a.signInMobile("dani@example.com")
	for _, p := range []string{"/v1/family", "/v1/account"} {
		if r := a.do(http.MethodDelete, p, nil, bearer(dani)...); r.Code != http.StatusNoContent {
			t.Fatalf("DELETE %s as the only guardian: %d %s", p, r.Code, r.Body)
		}
	}
}

func TestASuspendedOwnerCannotDeleteAFamilyWithOtherGuardians(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	owner := a.familyOwner("bia@example.com")
	caio := a.joinFamily(owner, "caio@example.com")
	a.suspend(root, a.accountID(owner))
	bia := a.signInMobile("bia@example.com") // a fresh sign-in: re-auth is satisfied
	mails := len(a.mail.To("caio@example.com"))

	if r := a.do(http.MethodDelete, "/v1/family", nil, bearer(bia)...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
		t.Fatalf("DELETE /v1/family with a co-guardian: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodGet, "/v1/family", nil, bearer(caio)...)
	if r.Code != http.StatusOK {
		t.Fatalf("the co-guardian's family: %d %s", r.Code, r.Body)
	}
	memberID(t, decodeFamily(t, r), "bia@example.com")
	if len(a.mail.To("caio@example.com")) != mails {
		t.Fatal("the co-guardian was told of a deletion that did not happen")
	}
}

func TestAnEmailChangeTokenDiesWithTheSuspension(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	a.signUpVerified("bia@example.com")
	bia := a.signInMobile("bia@example.com")
	if r := a.do(http.MethodPost, "/v1/account/email", map[string]string{"new_email": "nova@example.com"}, bearer(bia)...); r.Code != http.StatusAccepted {
		t.Fatalf("the email change request: %d %s", r.Code, r.Body)
	}
	change := a.lastToken("nova@example.com")
	if r := a.do(http.MethodPost, "/v1/password-resets", map[string]string{"email": "bia@example.com"}); r.Code != http.StatusAccepted {
		t.Fatalf("the password reset request: %d", r.Code)
	}
	reset := a.lastToken("bia@example.com")
	a.suspend(root, a.accountID(bia))

	if r := a.do(http.MethodPost, "/v1/email-verifications/confirm", map[string]string{"token": change}); r.Code != http.StatusBadRequest ||
		r.problemCode() != "invalid_token" {
		t.Fatalf("an email change token issued before the suspension: %d %q", r.Code, r.problemCode())
	}
	if n := a.count(`SELECT count(*) FROM accounts WHERE email = 'bia@example.com' AND status = 'suspended'`); n != 1 {
		t.Fatal("the suspended account's email changed")
	}
	if r := a.do(http.MethodPost, "/v1/password-resets/confirm", map[string]string{"token": reset, "new_password": newPassword}); r.Code != http.StatusNoContent {
		t.Fatalf("the password reset stays as it is: %d %s", r.Code, r.Body)
	}
}

func TestOtherGuardiansKeepTheFamily(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	owner := a.familyOwner("bia@example.com")
	caio := a.joinFamily(owner, "caio@example.com")
	a.suspend(root, a.accountID(caio))

	r := a.do(http.MethodGet, "/v1/family", nil, bearer(owner)...)
	if r.Code != http.StatusOK {
		t.Fatalf("the other guardian's family: %d %s", r.Code, r.Body)
	}
	memberID(t, decodeFamily(t, r), "caio@example.com") // the suspended guardian is still listed
	a.addMinor(owner)
	if r := a.do(http.MethodGet, "/v1/parental/devices", nil, bearer(owner)...); r.Code != http.StatusOK {
		t.Fatalf("the other guardian's devices: %d %s", r.Code, r.Body)
	}
	caio = a.signInMobile("caio@example.com")
	if r := a.do(http.MethodGet, "/v1/parental/devices", nil, bearer(caio)...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
		t.Fatalf("the suspended guardian: %d %q", r.Code, r.problemCode())
	}
}

func TestASuspendedAccountSignInIsThrottledAsAnActiveOne(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	a.signUpVerified("bia@example.com")
	a.suspend(root, a.accountID(a.signInMobile("bia@example.com")))
	wrong := map[string]string{"email": "bia@example.com", "password": "outra senha longa o bastante", "client": "web"}
	for range 5 {
		if r := a.do(http.MethodPost, "/v1/sessions", wrong); r.problemCode() != "invalid_credentials" {
			t.Fatalf("a wrong password for a suspended account: %d %q", r.Code, r.problemCode())
		}
	}
	r := a.do(http.MethodPost, "/v1/sessions", wrong)
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" {
		t.Fatalf("the sixth wrong password: %d %q", r.Code, r.problemCode())
	}
}

func TestALinkedDeviceOutlivesItsOnlyGuardiansSuspension(t *testing.T) {
	a := newAPI(t)
	root := a.accountID(a.admin("ana@example.com"))
	owner := a.familyOwner("bia@example.com")
	biaID := a.accountID(owner)
	minor := a.addMinor(owner)
	if err := a.par.SetPIN(context.Background(), biaID, "2580"); err != nil {
		t.Fatal(err)
	}
	dev := devBearer(a.linkedDevice(owner, minor))
	a.suspend(root, biaID)

	if r := a.do(http.MethodGet, "/v1/child/profile", nil, dev...); r.Code != http.StatusOK {
		t.Fatalf("the linked device after its only guardian's suspension: %d %s", r.Code, r.Body)
	}
	bia := a.signInMobile("bia@example.com")
	cookie, _ := a.signInWeb("bia@example.com")
	for name, h := range map[string][]string{"bearer": bearer(bia), "cookie": {"Cookie", cookie}} {
		if r := a.do(http.MethodGet, "/v1/child/profile", nil, h...); r.Code != http.StatusForbidden || r.problemCode() != "account_suspended" {
			t.Errorf("a child route through the suspended guardian's %s session: %d %q", name, r.Code, r.problemCode())
		}
	}
}
