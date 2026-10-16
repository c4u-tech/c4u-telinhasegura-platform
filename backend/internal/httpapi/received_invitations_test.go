package httpapi_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

// inviteID sends an invitation as owner and returns its id.
func (a *api) inviteID(owner mobileTokens, email string) string {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/family/invitations", map[string]string{"email": email}, bearer(owner)...)
	var inv struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &inv); r.Code != http.StatusCreated || err != nil || inv.ID == "" {
		a.t.Fatalf("invite: %d %s", r.Code, r.Body)
	}
	return inv.ID
}

func TestReceivedInvitationsOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	id := a.inviteID(ana, "bia@example.com")
	a.signUpVerified("bia@example.com")
	bia := a.signInMobile("bia@example.com")

	r := a.do(http.MethodGet, "/v1/invitations", nil, bearer(bia)...)
	var body struct {
		Invitations []map[string]any `json:"invitations"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &body); r.Code != http.StatusOK || err != nil || len(body.Invitations) != 1 {
		t.Fatalf("list: %d %s", r.Code, r.Body)
	}
	got := body.Invitations[0]
	if len(got) != 3 || got["id"] != id || got["inviter_email"] != "ana@example.com" || got["expires_at"] == "" {
		t.Fatalf("item: %v", got)
	}

	acc := a.do(http.MethodPost, "/v1/invitations/"+id+"/accept", nil, bearer(bia)...)
	if acc.Code != http.StatusOK || decodeFamily(t, acc).Role != "guardian" {
		t.Fatalf("accept: %d %s", acc.Code, acc.Body)
	}
	after := a.do(http.MethodGet, "/v1/invitations", nil, bearer(bia)...)
	if after.Code != http.StatusOK || !strings.Contains(after.Body.String(), `"invitations":[]`) {
		t.Fatalf("after joining: %d %s", after.Code, after.Body)
	}
}

func TestAcceptByIDAnswersAlikeOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	foreign := a.inviteID(ana, "carla@example.com")
	a.signUpVerified("bia@example.com")
	bia := a.signInMobile("bia@example.com")

	unknown := a.do(http.MethodPost, "/v1/invitations/00000000-0000-0000-0000-000000000000/accept", nil, bearer(bia)...)
	if unknown.Code != http.StatusNotFound || unknown.problemCode() != "invitation_unavailable" {
		t.Fatalf("unknown: %d %s", unknown.Code, unknown.Body)
	}
	for name, path := range map[string]string{
		"foreign":   "/v1/invitations/" + foreign + "/accept",
		"malformed": "/v1/invitations/nope/accept",
	} {
		r := a.do(http.MethodPost, path, nil, bearer(bia)...)
		if r.Code != unknown.Code || r.Body.String() != unknown.Body.String() {
			t.Errorf("%s: %d %s", name, r.Code, r.Body)
		}
	}
}

func TestReceivedInvitationsNeedAVerifiedEmail(t *testing.T) {
	a := newAPI(t)
	a.do(http.MethodPost, "/v1/accounts", signUpBody("bia@example.com"))
	bia := a.signInMobile("bia@example.com")
	if r := a.do(http.MethodGet, "/v1/invitations", nil, bearer(bia)...); r.Code != http.StatusForbidden || r.problemCode() != "email_unverified" {
		t.Fatalf("unverified: %d %s", r.Code, r.Body)
	}
}

func TestAcceptByIDNeedsCSRFOnTheWeb(t *testing.T) { // in-app Security
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	id := a.inviteID(ana, "bia@example.com")
	a.signUpVerified("bia@example.com")
	cookie, csrf := a.signInWeb("bia@example.com")

	if r := a.do(http.MethodGet, "/v1/invitations", nil, "Cookie", cookie); r.Code != http.StatusOK {
		t.Fatalf("list on the web: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/invitations/"+id+"/accept", nil, "Cookie", cookie); r.Code != http.StatusForbidden || r.problemCode() != "csrf_failed" {
		t.Fatalf("no CSRF: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/invitations/"+id+"/accept", nil, "Cookie", cookie, "X-CSRF-Token", csrf); r.Code != http.StatusOK {
		t.Fatalf("with CSRF: %d %s", r.Code, r.Body)
	}
}
