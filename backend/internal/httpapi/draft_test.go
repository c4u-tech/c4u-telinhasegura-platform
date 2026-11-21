package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

type draftResp struct {
	ChecklistVersion string            `json:"checklist_version"`
	Answers          map[string]string `json:"answers"`
	Theme            *string           `json:"theme"`
	MinAgeBand       *string           `json:"min_age_band"`
	Note             *string           `json:"note"`
	BeganAt          *time.Time        `json:"began_at"`
	PlayedToEndAt    *time.Time        `json:"played_to_end_at"`
}

// decodeDraft reads {"draft": ...}; nil is a null draft.
func decodeDraft(t *testing.T, r resp) *draftResp {
	t.Helper()
	var out struct {
		Draft *draftResp `json:"draft"`
	}
	if r.Code != http.StatusOK || json.Unmarshal(r.Body.Bytes(), &out) != nil {
		t.Fatalf("draft body: %d %s", r.Code, r.Body)
	}
	return out.Draft
}

func TestReviewDraftOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "c1@example.com", "mae-pai")
	other := a.curator(admin, "c2@example.com", "pedagogo")
	mod := a.moderator(admin, "mia@example.com")
	v := a.suggest(a.familyOwner("gui@example.com"), ytID)
	path := "/v1/curation/videos/" + v.ID + "/draft"

	if d := decodeDraft(t, a.do(http.MethodGet, path, nil, bearer(cur)...)); d != nil {
		t.Fatalf("no draft yet: %+v", d)
	}
	d := decodeDraft(t, a.do(http.MethodPut, path, map[string]any{}, bearer(cur)...))
	if d == nil || d.Answers == nil || len(d.Answers) != 0 || d.BeganAt == nil || d.PlayedToEndAt != nil ||
		d.Theme != nil || d.MinAgeBand != nil || d.Note != nil || d.ChecklistVersion != curation.ChecklistVersion {
		t.Fatalf("empty draft %+v", d)
	}
	body := map[string]any{"checklist_version": curation.ChecklistVersion, "answers": map[string]string{"c04": "appears"},
		"theme": "bichos", "min_age_band": "5-8", "note": "Vi até 2 min."}
	d = decodeDraft(t, a.do(http.MethodPut, path, body, bearer(cur)...))
	if d == nil || d.Answers["c04"] != "appears" || len(d.Answers) != 1 || d.Theme == nil || *d.Theme != "bichos" ||
		d.MinAgeBand == nil || *d.MinAgeBand != "5-8" || d.Note == nil || *d.Note != "Vi até 2 min." {
		t.Fatalf("saved draft %+v", d)
	}
	body["checklist_version"] = "2026-11-11"
	if r := a.do(http.MethodPut, path, body, bearer(cur)...); r.Code != http.StatusConflict || r.problemCode() != "checklist_outdated" {
		t.Fatalf("former list: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPut, path, map[string]any{"decision": "approve"}, bearer(cur)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("unknown field: %d %q", r.Code, r.problemCode())
	}
	d = decodeDraft(t, a.do(http.MethodPost, path+"/ended", nil, bearer(cur)...))
	if d == nil || d.PlayedToEndAt == nil || d.Answers["c04"] != "appears" {
		t.Fatalf("ended %+v", d)
	}
	if d := decodeDraft(t, a.do(http.MethodGet, path, nil, bearer(cur)...)); d == nil || d.PlayedToEndAt == nil {
		t.Fatalf("read back %+v", d)
	}

	if r := a.do(http.MethodGet, path, nil, bearer(mod)...); r.Code != http.StatusForbidden || r.problemCode() != "not_curator" {
		t.Fatalf("a moderator: %d %q", r.Code, r.problemCode())
	}
	if d := decodeDraft(t, a.do(http.MethodGet, path, nil, bearer(other)...)); d != nil {
		t.Fatalf("another curator's read: %+v", d)
	}
	if r := a.do(http.MethodPut, "/v1/curation/videos/abc/draft", map[string]any{}, bearer(cur)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("unknown video: %d %q", r.Code, r.problemCode())
	}
}
