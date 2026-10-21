package httpapi_test

import (
	"net/http"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func TestCuratorRoutesWaitForTheCuratorTerms(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	bia := a.undeclaredCurator(admin, "bia@example.com", "mae-pai")
	n := 0
	for _, rt := range a.server.Routes() {
		if rt.Kind != httpapi.CuratorRoute || strings.Contains(rt.Pattern, " /v1/curation/declaration") {
			continue
		}
		n++
		method, path := sweepTarget(rt.Pattern)
		if r := a.do(method, path, "{}", bearer(bia)...); r.Code != http.StatusForbidden || r.problemCode() != "declaration_required" {
			t.Errorf("%s: %d %q", rt.Pattern, r.Code, r.problemCode())
		}
	}
	if n < 10 {
		t.Fatalf("swept only %d curator routes", n)
	}
	// The list of questions is read before the terms are accepted.
	if r := a.do(http.MethodGet, "/v1/curation/checklist", nil, bearer(bia)...); r.Code != http.StatusOK {
		t.Fatalf("checklist: %d %s", r.Code, r.Body)
	}
	var d struct {
		Version  string `json:"version"`
		Text     string `json:"text"`
		Accepted bool   `json:"accepted"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/curation/declaration", nil, bearer(bia)...), &d)
	if d.Version != "2026-10-20" || d.Text != curation.CuratorTermsText || d.Accepted {
		t.Fatalf("declaration %+v", d)
	}
	if r := a.do(http.MethodPost, "/v1/curation/declaration", map[string]string{"version": "2026-01-01"}, bearer(bia)...); r.Code != http.StatusConflict || r.problemCode() != "declaration_outdated" {
		t.Fatalf("an old version: %d %q", r.Code, r.problemCode())
	}
	getJSON(t, a.do(http.MethodPost, "/v1/curation/declaration", map[string]string{"version": d.Version}, bearer(bia)...), &d)
	if !d.Accepted {
		t.Fatalf("accept %+v", d)
	}
	if n := a.count(`SELECT count(*) FROM curator_declarations WHERE account_id = $1::uuid AND version = '2026-10-20'
		AND accepted_at = $2`, a.accountID(bia), a.now); n != 1 {
		t.Fatal("the acceptance was not stored")
	}
	if r := a.do(http.MethodGet, "/v1/curation/queue", nil, bearer(bia)...); r.Code != http.StatusOK {
		t.Fatalf("queue after the terms: %d %s", r.Code, r.Body)
	}
	// The terms are a curator's: anyone else is refused before them.
	plain := a.familyOwner("caio@example.com")
	if r := a.do(http.MethodGet, "/v1/curation/declaration", nil, bearer(plain)...); r.Code != http.StatusForbidden || r.problemCode() != "not_curator" {
		t.Fatalf("a guardian: %d %q", r.Code, r.problemCode())
	}
}
