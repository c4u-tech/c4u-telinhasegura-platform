package httpapi_test

import (
	"encoding/json"
	"maps"
	"net/http"
	"slices"
	"strings"
	"testing"
)

type reviewResp struct {
	Review struct {
		Decision         string            `json:"decision"`
		Reason           *string           `json:"reason"`
		ChecklistVersion *string           `json:"checklist_version"`
		Answers          map[string]string `json:"answers"`
		FailedItems      []string          `json:"failed_items"`
	} `json:"review"`
	VideoState string `json:"video_state"`
}

func decodeReview(t *testing.T, r resp) reviewResp {
	t.Helper()
	var out reviewResp
	if r.Code != http.StatusCreated {
		t.Fatalf("review: %d %s", r.Code, r.Body)
	}
	if err := json.Unmarshal(r.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// approvalWith is approval with the given answers changed.
func approvalWith(theme, band string, changed map[string]string) map[string]any {
	body := approval(theme, band)
	maps.Copy(body["answers"].(map[string]string), changed)
	return body
}

func TestReviewWithTheChecklistOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "cuidador")
	mod := a.moderator(admin, "mia@example.com")
	v := a.suggest(a.familyOwner("gui@example.com"), ytID)
	reviews := "/v1/curation/videos/" + v.ID + "/reviews"

	outdated := approval("bichos", "5-8")
	outdated["checklist_version"] = "2026-01-01"
	former := approval("bichos", "5-8")
	former["checklist_version"] = "2026-10-20"
	missing := approval("bichos", "5-8")
	delete(missing["answers"].(map[string]string), "c13")
	young := approvalWith("bichos", "ate-4", map[string]string{"c22": "appears"})
	for name, tc := range map[string]struct {
		body   map[string]any
		status int
		code   string
	}{
		"an old list":            {outdated, http.StatusConflict, "checklist_outdated"},
		"the former list":        {former, http.StatusConflict, "checklist_outdated"},
		"a doubt on the tie":     {approvalWith("bichos", "5-8", map[string]string{"c25": "doubt"}), http.StatusUnprocessableEntity, "validation"},
		"no clear story":         {approvalWith("bichos", "5-8", map[string]string{"c23": "appears"}), http.StatusUnprocessableEntity, "checklist_refuses"},
		"a missing answer":       {missing, http.StatusUnprocessableEntity, "validation"},
		"an answer that refuses": {approvalWith("bichos", "5-8", map[string]string{"c15": "appears"}), http.StatusUnprocessableEntity, "checklist_refuses"},
		"a fast pace for 2 to 4": {young, http.StatusUnprocessableEntity, "checklist_band"},
		"a tie to the channel":   {approvalWith("bichos", "5-8", map[string]string{"c25": "appears"}), http.StatusConflict, "conflict_of_interest"},
		"the old body":           {map[string]any{"decision": "reject", "reason": "Tem propaganda."}, http.StatusUnprocessableEntity, "validation"},
		"the old approval":       {map[string]any{"decision": "approve", "theme": "bichos", "min_age_band": "5-8"}, http.StatusConflict, "checklist_outdated"},
	} {
		if r := a.do(http.MethodPost, reviews, tc.body, bearer(c1)...); r.Code != tc.status || r.problemCode() != tc.code {
			t.Errorf("%s: %d %q, want %d %s", name, r.Code, r.problemCode(), tc.status, tc.code)
		}
	}
	if n := a.count(`SELECT count(*) FROM video_reviews`); n != 0 {
		t.Fatalf("refused reviews were stored: %d", n)
	}

	got := decodeReview(t, a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c1)...))
	if got.VideoState != "pending" || got.Review.Decision != "approve" || got.Review.ChecklistVersion == nil ||
		*got.Review.ChecklistVersion != "2026-10-21" || len(got.Review.Answers) != 23 || got.Review.FailedItems != nil {
		t.Fatalf("approval %+v", got)
	}

	doubt := approvalWith("bichos", "5-8", map[string]string{"c13": "doubt"})
	doubt["note"] = "Não sei se é perigoso."
	got = decodeReview(t, a.do(http.MethodPost, reviews, doubt, bearer(c2)...))
	if got.VideoState != "held" || got.Review.Decision != "doubt" || got.Review.Reason == nil || *got.Review.Reason != "Não sei se é perigoso." {
		t.Fatalf("doubt %+v", got)
	}
	var held struct {
		Videos []struct {
			HeldReason string            `json:"held_reason"`
			Rejections []json.RawMessage `json:"rejections"`
			Doubts     []struct {
				DisplayRole string            `json:"display_role"`
				Reason      string            `json:"reason"`
				Answers     map[string]string `json:"answers"`
			} `json:"doubts"`
		} `json:"videos"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(mod)...), &held)
	if len(held.Videos) != 1 || held.Videos[0].HeldReason != "doubt" || len(held.Videos[0].Rejections) != 0 ||
		len(held.Videos[0].Doubts) != 1 || held.Videos[0].Doubts[0].DisplayRole != "cuidador" ||
		held.Videos[0].Doubts[0].Reason != "Não sei se é perigoso." || held.Videos[0].Doubts[0].Answers["c13"] != "doubt" {
		t.Fatalf("held %+v", held)
	}
}

func TestRejectionWithItemsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	gui := a.familyOwner("gui@example.com")
	v := a.suggest(gui, ytID)

	got := decodeReview(t, a.do(http.MethodPost, "/v1/curation/videos/"+v.ID+"/reviews", rejection("Tem propaganda.", "c15", "c03"), bearer(c1)...))
	const c03 = "Aparece 'Inclui promoção paga' ou fala em publi, parceria, patrocínio ou recebido?"
	if got.VideoState != "held" || got.Review.Decision != "reject" || !slices.Equal(got.Review.FailedItems, []string{"c03", "c15"}) ||
		got.Review.Answers != nil || got.Review.Reason == nil || *got.Review.Reason != c03+"\n"+c15+"\nTem propaganda." {
		t.Fatalf("rejection %+v", got)
	}
	other := a.suggest(gui, "bbbbbbbbbbb")
	if r := a.do(http.MethodPost, "/v1/curation/videos/"+other.ID+"/reviews", rejection("", "c07"), bearer(c1)...); r.Code != http.StatusUnprocessableEntity ||
		r.problemCode() != "validation" || strings.Contains(r.Body.String(), "c07") {
		t.Fatalf("a rejection for a doubt question: %d %s", r.Code, r.Body)
	}
}
