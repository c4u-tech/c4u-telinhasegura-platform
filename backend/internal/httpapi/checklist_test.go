package httpapi_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

type checklistResp struct {
	Version string `json:"version"`
	Groups  []struct {
		ID    string `json:"id"`
		Title string `json:"title"`
		Items []struct {
			ID   string `json:"id"`
			Text string `json:"text"`
			Rule string `json:"rule"`
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
	if strings.Contains(first, `"positive"`) {
		t.Fatal("every question is asked the same way round: no item says otherwise")
	}
	var body checklistResp
	if err := json.Unmarshal([]byte(first), &body); err != nil {
		t.Fatal(err)
	}
	if body.Version != "2026-10-21" || len(body.Groups) != 6 || body.Groups[0].ID != "antes" || body.Groups[0].Title != "Antes de começar" {
		t.Fatalf("list %+v", body)
	}
	if c25 := body.Groups[0].Items[0]; c25.ID != "c25" || c25.Rule != "conflict" ||
		c25.Text != "Você tem vínculo com este canal ou com quem o publica?" {
		t.Fatalf("c25 %+v", c25)
	}
	last := body.Groups[5]
	if c24 := last.Items[len(last.Items)-1]; last.ID != "ritmo" || last.Title != "Ritmo e canal" || c24.ID != "c24" || c24.Rule != "doubt" {
		t.Fatalf("ritmo %+v", last)
	}
	plain := a.familyOwner("caio@example.com")
	if r := a.do(http.MethodGet, "/v1/curation/checklist", nil, bearer(plain)...); r.Code != http.StatusForbidden || r.problemCode() != "not_staff" {
		t.Fatalf("a guardian: %d %q", r.Code, r.problemCode())
	}
}
