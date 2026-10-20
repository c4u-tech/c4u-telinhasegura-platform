package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

type checklistResp struct {
	Version string `json:"version"`
	Groups  []struct {
		ID    string `json:"id"`
		Title string `json:"title"`
		Items []struct {
			ID       string `json:"id"`
			Text     string `json:"text"`
			Rule     string `json:"rule"`
			Positive bool   `json:"positive"`
		} `json:"items"`
	} `json:"groups"`
}

func TestChecklistOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	mod := a.moderator(admin, "mia@example.com")
	var first string
	for who, tok := range map[string]mobileTokens{"curator": cur, "moderator": mod, "admin": admin} {
		r := a.do(http.MethodGet, "/v1/curation/checklist", nil, bearer(tok)...)
		if r.Code != http.StatusOK {
			t.Fatalf("%s: %d %s", who, r.Code, r.Body)
		}
		if first == "" {
			first = r.Body.String()
		} else if r.Body.String() != first {
			t.Fatalf("%s reads another list", who)
		}
	}
	var body checklistResp
	if err := json.Unmarshal([]byte(first), &body); err != nil {
		t.Fatal(err)
	}
	if body.Version != "2026-10-20" || len(body.Groups) != 6 || body.Groups[0].ID != "antes" || body.Groups[0].Title != "Antes de assistir" {
		t.Fatalf("list %+v", body)
	}
	c01 := body.Groups[0].Items[0]
	if c01.ID != "c01" || c01.Rule != "refuses" || !c01.Positive ||
		c01.Text != "Está marcado como 'feito para crianças' no YouTube e pode ser incorporado?" {
		t.Fatalf("c01 %+v", c01)
	}
	if last := body.Groups[5].Items[2]; last.ID != "c24" || last.Rule != "doubt" || last.Positive {
		t.Fatalf("c24 %+v", last)
	}
	plain := a.familyOwner("caio@example.com")
	if r := a.do(http.MethodGet, "/v1/curation/checklist", nil, bearer(plain)...); r.Code != http.StatusForbidden || r.problemCode() != "not_staff" {
		t.Fatalf("a guardian: %d %q", r.Code, r.problemCode())
	}
}
