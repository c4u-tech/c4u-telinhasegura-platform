package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"maps"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

type sheetResp struct {
	AccountID     string   `json:"account_id"`
	EmailMasked   string   `json:"email_masked"`
	EmailVerified bool     `json:"email_verified"`
	CreatedAt     string   `json:"created_at"`
	Providers     []string `json:"providers"`
	Roles         []string `json:"roles"`
	MFAEnrolled   bool     `json:"mfa_enrolled"`
	Suspension    *struct {
		Since  string `json:"since"`
		Reason string `json:"reason"`
	} `json:"suspension"`
	Family *struct {
		Role    string `json:"role"`
		Minors  int    `json:"minors"`
		Devices int    `json:"devices"`
	} `json:"family"`
	Devices []struct {
		ID         string `json:"id"`
		LinkedAt   string `json:"linked_at"`
		LastSeenAt string `json:"last_seen_at"`
	} `json:"devices"`
	Sessions []struct {
		Client     string `json:"client"`
		CreatedAt  string `json:"created_at"`
		LastSeenAt string `json:"last_seen_at"`
	} `json:"sessions"`
	Actions []json.RawMessage `json:"actions"`
}

func decodeSheet(t *testing.T, r resp) sheetResp {
	t.Helper()
	var sh sheetResp
	if err := json.Unmarshal(r.Body.Bytes(), &sh); err != nil {
		t.Fatalf("sheet body: %v %d %s", err, r.Code, r.Body)
	}
	return sh
}

const supportReason = "Pedido do titular."

// lookup posts body to the lookup route, with the reason "Pedido de
// suporte." unless body sets one.
func (a *api) lookup(admin mobileTokens, body map[string]any) resp {
	a.t.Helper()
	if _, ok := body["reason"]; !ok {
		body["reason"] = "Pedido de suporte."
	}
	return a.do(http.MethodPost, "/v1/admin/accounts/lookup", body, bearer(admin)...)
}

// resetMails counts the reset links sent to addr.
func (a *api) resetMails(addr string) int {
	n := 0
	for _, m := range a.mail.To(addr) {
		if strings.Contains(m.Body, "/redefinir-senha?token=") {
			n++
		}
	}
	return n
}

func TestLookupOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	bia := a.familyOwner("bia@example.com")
	biaID := a.accountID(bia)
	minor := a.addMinor(bia)
	if err := a.par.SetPIN(context.Background(), biaID, "2580"); err != nil {
		t.Fatal(err)
	}
	deviceToken := a.linkedDevice(bia, minor)

	r := a.lookup(admin, map[string]any{"email": "BIA@example.com"})
	sh := decodeSheet(t, r)
	if r.Code != http.StatusOK || sh.AccountID != biaID || sh.EmailMasked != "b•••@e•••.com" || !sh.EmailVerified ||
		sh.MFAEnrolled || len(sh.Providers) != 1 || sh.Providers[0] != "password" || len(sh.Roles) != 0 ||
		sh.Family == nil || sh.Family.Role != "owner" || sh.Family.Minors != 1 || sh.Family.Devices != 1 ||
		len(sh.Devices) != 1 || len(sh.Sessions) != 1 || sh.Sessions[0].Client != "mobile" {
		t.Fatalf("sheet %d %s", r.Code, r.Body)
	}
	body := r.Body.String()
	for _, leak := range []string{"bia@example.com", "Tablet", "Lia", minor, bia.SessionID, deviceToken, "label", "nickname", "token"} {
		if strings.Contains(body, leak) {
			t.Errorf("the sheet carries %q: %s", leak, body)
		}
	}
	for _, key := range []string{`"roles":[]`, `"actions":[]`, `"mfa_enrolled":false`} {
		if !strings.Contains(body, key) {
			t.Errorf("missing %s in %s", key, body)
		}
	}
	r = a.lookup(admin, map[string]any{"account_id": biaID})
	if sh := decodeSheet(t, r); r.Code != http.StatusOK || sh.AccountID != biaID {
		t.Fatalf("by id: %d %s", r.Code, r.Body)
	}
}

func TestLookupRefusalsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	a.signUpVerified("bia@example.com")

	if r := a.lookup(admin, map[string]any{"email": "nobody@example.com"}); r.Code != http.StatusNotFound || r.problemCode() != "account_not_found" {
		t.Fatalf("miss: %d %s", r.Code, r.Body)
	}
	for name, c := range map[string]struct {
		body map[string]any
		code string
	}{
		"both":          {map[string]any{"email": "bia@example.com", "account_id": "00000000-0000-0000-0000-000000000000"}, "validation"},
		"neither":       {map[string]any{}, "validation"},
		"bad id":        {map[string]any{"account_id": "abc"}, "validation"},
		"bad email":     {map[string]any{"email": "bia"}, "validation"},
		"unknown field": {map[string]any{"email": "bia@example.com", "name": "Bia"}, "validation"},
		"short reason":  {map[string]any{"email": "bia@example.com", "reason": "ok"}, "reason_required"},
	} {
		if r := a.lookup(admin, c.body); r.Code != http.StatusUnprocessableEntity || r.problemCode() != c.code {
			t.Errorf("%s: %d %q, want %s", name, r.Code, r.problemCode(), c.code)
		}
	}
	for i := 2; i <= 30; i++ { // the miss above was the 1st
		if r := a.lookup(admin, map[string]any{"email": "bia@example.com"}); r.Code != http.StatusOK {
			t.Fatalf("lookup %d: %d %s", i, r.Code, r.Body)
		}
	}
	r := a.lookup(admin, map[string]any{"email": "bia@example.com"})
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") == "" {
		t.Fatalf("31st lookup: %d %s %v", r.Code, r.Body, r.Header())
	}
}

func TestLookupKeepsTheEmailOutOfLogsAndAudit(t *testing.T) {
	var logs bytes.Buffer
	a := newAPI(t, func(s *httpapi.Server) { s.Log = slog.New(slog.NewTextHandler(&logs, nil)) })
	admin := a.admin("ana@example.com")
	a.signUpVerified("bia@example.com")
	if r := a.lookup(admin, map[string]any{"email": "bia@example.com"}); r.Code != http.StatusOK {
		t.Fatalf("hit: %d %s", r.Code, r.Body)
	}
	if r := a.lookup(admin, map[string]any{"email": "nobody@example.com"}); r.Code != http.StatusNotFound {
		t.Fatalf("miss: %d %s", r.Code, r.Body)
	}
	for _, email := range []string{"bia@example.com", "nobody@example.com"} {
		if strings.Contains(logs.String(), email) {
			t.Errorf("%s reached the log: %s", email, logs.String())
		}
		if strings.Contains(fmt.Sprintf("%+v", a.audit.Actions), email) {
			t.Errorf("%s reached the audit", email)
		}
	}
}

func TestSupportActionsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	bia := a.familyOwner("bia@example.com")
	biaID := a.accountID(bia)
	minor := a.addMinor(bia)
	if err := a.par.SetPIN(context.Background(), biaID, "2580"); err != nil {
		t.Fatal(err)
	}
	a.linkedDevice(bia, minor)
	dev := decodeSheet(t, a.lookup(admin, map[string]any{"account_id": biaID})).Devices[0].ID
	base := "/v1/admin/accounts/" + biaID
	reason := map[string]any{"reason": supportReason}

	r := a.do(http.MethodPost, base+"/devices/"+dev+"/unlink", reason, bearer(admin)...)
	if sh := decodeSheet(t, r); r.Code != http.StatusOK || len(sh.Devices) != 0 || sh.Family == nil || sh.Family.Devices != 0 {
		t.Fatalf("unlink: %d %s", r.Code, r.Body)
	}
	r = a.do(http.MethodPost, base+"/password-reset", reason, bearer(admin)...)
	if r.Code != http.StatusOK || a.resetMails("bia@example.com") != 1 {
		t.Fatalf("reset: %d %s", r.Code, r.Body)
	}
	r = a.do(http.MethodPost, base+"/sessions/revoke", reason, bearer(admin)...)
	if sh := decodeSheet(t, r); r.Code != http.StatusOK || len(sh.Sessions) != 0 {
		t.Fatalf("revoke: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(bia)...); r.Code != http.StatusUnauthorized {
		t.Fatalf("bia is still signed in: %d", r.Code)
	}
	if r := a.do(http.MethodGet, "/v1/admin/staff", nil, bearer(admin)...); r.Code != http.StatusOK {
		t.Fatalf("the admin's own session ended: %d", r.Code)
	}
	for _, c := range []struct {
		e    audit.Event
		meta map[string]string
	}{
		{audit.AccountDeviceUnlinked, map[string]string{"device_id": dev}},
		{audit.AccountPasswordResetSent, nil},
		{audit.AccountSessionsRevoked, map[string]string{"sessions": "1"}},
	} {
		x, ok := a.audit.LastAction(c.e)
		if !ok || x.ActorRole != "admin" || x.SubjectID != biaID || x.Reason != supportReason || !maps.Equal(x.Metadata, c.meta) {
			t.Errorf("%s: %+v %v", c.e, x, ok)
		}
	}
	for i := 2; i <= 3; i++ {
		if r := a.do(http.MethodPost, base+"/password-reset", reason, bearer(admin)...); r.Code != http.StatusOK {
			t.Fatalf("reset %d: %d %s", i, r.Code, r.Body)
		}
	}
	r = a.do(http.MethodPost, base+"/password-reset", reason, bearer(admin)...)
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || a.resetMails("bia@example.com") != 3 {
		t.Fatalf("4th reset in an hour: %d %s", r.Code, r.Body)
	}
}

func TestSupportActionRefusalsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	a.signUpVerified("bia@example.com")
	biaID := a.accountID(a.signInMobile("bia@example.com"))
	const unknown = "00000000-0000-0000-0000-000000000000"
	good := map[string]any{"reason": supportReason}
	for _, c := range []struct {
		path   string
		body   any
		status int
		code   string
	}{
		{"/v1/admin/accounts/" + adminID + "/sessions/revoke", good, http.StatusForbidden, "self_action"},
		{"/v1/admin/accounts/" + adminID + "/devices/" + unknown + "/unlink", good, http.StatusForbidden, "self_action"},
		{"/v1/admin/accounts/" + adminID + "/password-reset", map[string]any{"reason": "ok"}, http.StatusUnprocessableEntity, "reason_required"},
		{"/v1/admin/accounts/" + unknown + "/password-reset", good, http.StatusNotFound, "account_not_found"},
		{"/v1/admin/accounts/abc/sessions/revoke", good, http.StatusNotFound, "account_not_found"},
		{"/v1/admin/accounts/" + biaID + "/devices/" + unknown + "/unlink", good, http.StatusNotFound, "device_not_found"},
		{"/v1/admin/accounts/" + biaID + "/sessions/revoke", `{"reason": 1}`, http.StatusUnprocessableEntity, "validation"},
	} {
		if r := a.do(http.MethodPost, c.path, c.body, bearer(admin)...); r.Code != c.status || r.problemCode() != c.code {
			t.Errorf("%s: %d %q, want %d %s", c.path, r.Code, r.problemCode(), c.status, c.code)
		}
	}
	if len(a.audit.Actions) != 0 || a.resetMails("ana@example.com") != 0 {
		t.Fatal("a refused support action was audited or mailed")
	}
	// The kind's checks come first: a stale re-auth refuses before the body.
	a.now = a.now.Add(6 * time.Minute)
	admin = a.refresh(admin)
	if r := a.do(http.MethodPost, "/v1/admin/accounts/"+adminID+"/sessions/revoke", map[string]any{"reason": "ok"}, bearer(admin)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale re-auth: %d %q", r.Code, r.problemCode())
	}
	if r := a.lookup(admin, map[string]any{"account_id": biaID}); r.Code != http.StatusOK {
		t.Fatalf("the lookup needs no re-auth: %d %s", r.Code, r.Body)
	}
}
