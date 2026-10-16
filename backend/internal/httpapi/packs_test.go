package httpapi_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

type packResp struct {
	ID           string  `json:"id"`
	State        string  `json:"state"`
	Round        int     `json:"round"`
	Theme        *string `json:"theme"`
	Title        string  `json:"title"`
	CoverVideoID string  `json:"cover_video_id"`
	ComposerRole string  `json:"composer_role"`
	Videos       []struct {
		ID              string `json:"id"`
		Title           string `json:"title"`
		ChannelTitle    string `json:"channel_title"`
		DurationSeconds int    `json:"duration_seconds"`
		State           string `json:"state"`
	} `json:"videos"`
	TotalSeconds int   `json:"total_seconds"`
	Reviews      []any `json:"reviews"`
	Reviewable   bool  `json:"reviewable"`
	Provenance   *struct {
		Approvals      map[string]int `json:"approvals"`
		LastReviewedAt string         `json:"last_reviewed_at"`
	} `json:"provenance"`
}

func decodePack(t *testing.T, r resp, status int) packResp {
	t.Helper()
	var p packResp
	if err := json.Unmarshal(r.Body.Bytes(), &p); err != nil || r.Code != status || p.ID == "" {
		t.Fatalf("pack: want %d, got %d %s", status, r.Code, r.Body)
	}
	return p
}

// threeVideos inserts three approved, 5-minute, under-4 videos.
func (a *api) threeVideos() []string {
	a.t.Helper()
	return []string{a.published("aaaaaaaaaaa", "bichos", "ate-4"), a.published("bbbbbbbbbbb", "musica", "ate-4"),
		a.published("ccccccccccc", "bichos", "ate-4")}
}

func composition(title string, ids ...string) map[string]any {
	return map[string]any{"title": title, "video_ids": ids}
}

func TestComposeAndReviewPacksOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "pedagogo")
	c3 := a.curator(admin, "c3@example.com", "cuidador")
	v := a.threeVideos()

	p := decodePack(t, a.do(http.MethodPost, "/v1/curation/packs", composition("Bichos", v...), bearer(c1)...), http.StatusCreated)
	if p.State != "pending" || p.Round != 1 || p.Theme != nil || p.Title != "Bichos" || p.CoverVideoID != v[0] ||
		p.ComposerRole != "mae-pai" || len(p.Videos) != 3 || p.Videos[1].ID != v[1] || p.Videos[1].State != "approved" ||
		p.Videos[1].DurationSeconds != 300 || p.TotalSeconds != 900 || p.Reviews == nil || len(p.Reviews) != 0 ||
		p.Reviewable || p.Provenance != nil {
		t.Fatalf("composed %+v", p)
	}

	var list struct {
		Packs   []packResp `json:"packs"`
		HasMore bool       `json:"has_more"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/curation/packs", nil, bearer(c2)...), &list)
	if len(list.Packs) != 1 || list.Packs[0].ID != p.ID || !list.Packs[0].Reviewable || list.HasMore {
		t.Fatalf("list %+v", list)
	}
	for _, off := range []string{"-1", "x"} {
		if r := a.do(http.MethodGet, "/v1/curation/packs?offset="+off, nil, bearer(c2)...); r.Code != http.StatusUnprocessableEntity ||
			r.problemCode() != "validation" {
			t.Errorf("offset %s: %d %q", off, r.Code, r.problemCode())
		}
	}

	reviews := "/v1/curation/packs/" + p.ID + "/reviews"
	approve := map[string]string{"decision": "approve"}
	if r := a.do(http.MethodPost, reviews, approve, bearer(c1)...); r.Code != http.StatusForbidden || r.problemCode() != "own_composition" {
		t.Fatalf("composer: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, reviews, map[string]string{"decision": "reject"}, bearer(c2)...); r.Code != http.StatusUnprocessableEntity ||
		r.problemCode() != "validation" {
		t.Fatalf("a rejection without a reason: %d %q", r.Code, r.problemCode())
	}
	var out struct {
		Review struct {
			DisplayRole string  `json:"display_role"`
			Decision    string  `json:"decision"`
			Reason      *string `json:"reason"`
			ReviewedAt  string  `json:"reviewed_at"`
		} `json:"review"`
		State string `json:"state"`
	}
	r := a.do(http.MethodPost, reviews, approve, bearer(c2)...)
	_ = json.Unmarshal(r.Body.Bytes(), &out)
	if r.Code != http.StatusCreated || out.Review.DisplayRole != "pedagogo" || out.Review.Decision != "approve" ||
		out.Review.Reason != nil || out.Review.ReviewedAt == "" || out.State != "pending" {
		t.Fatalf("first approval: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, reviews, approve, bearer(c2)...); r.Code != http.StatusConflict || r.problemCode() != "already_reviewed" {
		t.Fatalf("again: %d %q", r.Code, r.problemCode())
	}
	a.now = a.now.Add(time.Minute)
	r = a.do(http.MethodPost, reviews, approve, bearer(c3)...)
	_ = json.Unmarshal(r.Body.Bytes(), &out)
	if r.Code != http.StatusCreated || out.State != "approved" {
		t.Fatalf("second approval: %d %s", r.Code, r.Body)
	}

	detail := a.do(http.MethodGet, "/v1/curation/packs/"+p.ID, nil, bearer(c1)...)
	got := decodePack(t, detail, http.StatusOK)
	if got.State != "approved" || got.Reviewable || got.Provenance == nil || got.Provenance.Approvals["pedagogo"] != 1 ||
		got.Provenance.Approvals["cuidador"] != 1 || got.Provenance.LastReviewedAt == "" {
		t.Fatalf("detail %s", detail.Body)
	}
	for _, leak := range []string{a.accountID(c1), a.accountID(c2), a.accountID(c3), "c1@example.com", "c2@example.com", "c3@example.com"} {
		if strings.Contains(detail.Body.String(), leak) {
			t.Errorf("the detail exposes a curator: %s", leak)
		}
	}
	if !a.audit.Has(a.accountID(c3), audit.PackPublished) {
		t.Fatal("no pack_published under the last approver")
	}
}

func TestPackCompositionErrorsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c := a.curator(admin, "c1@example.com", "mae-pai")
	v := a.threeVideos()
	unknown := "00000000-0000-0000-0000-000000000000"

	for name, tc := range map[string]struct {
		body         any
		code, reason string
	}{
		"two videos":       {composition("Bichos", v[:2]...), "pack_invalid", "count"},
		"a repeat":         {composition("Bichos", v[0], v[1], v[0]), "pack_invalid", "repeat"},
		"an unknown video": {composition("Bichos", v[0], v[1], unknown), "pack_invalid", "not_approved"},
		"a cover outside":  {map[string]any{"title": "Bichos", "video_ids": v, "cover_video_id": unknown}, "pack_invalid", "cover"},
		"a blank title":    {composition("  ", v...), "pack_invalid", "title"},
		"an unknown theme": {map[string]any{"title": "Bichos", "video_ids": v, "theme": "carros"}, "validation", ""},
		"an unknown field": {map[string]any{"title": "Bichos", "video_ids": v, "band": "5-8"}, "validation", ""},
	} {
		r := a.do(http.MethodPost, "/v1/curation/packs", tc.body, bearer(c)...)
		if r.Code != http.StatusUnprocessableEntity || r.problemCode() != tc.code || r.problemReason() != tc.reason {
			t.Errorf("%s: %d %q %q", name, r.Code, r.problemCode(), r.problemReason())
		}
	}
	if n := a.count(`SELECT count(*) FROM packs`); n != 0 {
		t.Fatalf("refused compositions stored %d packs", n)
	}
	for _, p := range []string{"GET /v1/curation/packs/abc", "PUT /v1/curation/packs/abc", "POST /v1/curation/packs/abc/reviews",
		"GET /v1/curation/packs/" + unknown, "POST /v1/curation/packs/" + unknown + "/reviews"} {
		method, path, _ := strings.Cut(p, " ")
		var body any = composition("Bichos", v...)
		if method == http.MethodPost {
			body = map[string]string{"decision": "approve"}
		}
		if r := a.do(method, path, body, bearer(c)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Errorf("%s: %d %q", p, r.Code, r.problemCode())
		}
	}
}

func TestRecomposeAndRemovePacksOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "pedagogo")
	v := a.threeVideos()
	p := decodePack(t, a.do(http.MethodPost, "/v1/curation/packs", composition("Bichos", v...), bearer(c1)...), http.StatusCreated)

	r := a.do(http.MethodPost, "/v1/curation/packs/"+p.ID+"/reviews", map[string]string{"decision": "reject", "reason": "Muito longo."}, bearer(c2)...)
	if r.Code != http.StatusCreated || !strings.Contains(r.Body.String(), `"state":"held"`) {
		t.Fatalf("rejection: %d %s", r.Code, r.Body)
	}
	if !a.audit.Has(a.accountID(c2), audit.PackHeld) {
		t.Fatal("no pack_held under the rejector")
	}
	got := decodePack(t, a.do(http.MethodPut, "/v1/curation/packs/"+p.ID, composition("Outros bichos", v[2], v[1], v[0]), bearer(c2)...), http.StatusOK)
	if got.State != "pending" || got.Round != 2 || got.ComposerRole != "pedagogo" || got.CoverVideoID != v[2] || got.Reviewable {
		t.Fatalf("recomposed %+v", got)
	}

	remove := "/v1/admin/packs/" + p.ID + "/remove"
	if r := a.do(http.MethodPost, remove, nil, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("remove: %d %s", r.Code, r.Body)
	}
	if !a.audit.Has(a.accountID(admin), audit.PackRemoved) {
		t.Fatal("no pack_removed under the admin")
	}
	if r := a.do(http.MethodPost, remove, nil, bearer(admin)...); r.Code != http.StatusConflict || r.problemCode() != "state_conflict" {
		t.Fatalf("remove twice: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPut, "/v1/curation/packs/"+p.ID, composition("De novo", v...), bearer(c1)...); r.Code != http.StatusConflict ||
		r.problemCode() != "state_conflict" {
		t.Fatalf("recompose a removed pack: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/admin/packs/abc/remove", nil, bearer(admin)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("malformed id: %d %q", r.Code, r.problemCode())
	}
}

func TestPackRemovalNeedsAFreshReauth(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c := a.curator(admin, "c1@example.com", "mae-pai")
	p := decodePack(t, a.do(http.MethodPost, "/v1/curation/packs", composition("Bichos", a.threeVideos()...), bearer(c)...), http.StatusCreated)
	a.now = a.now.Add(6 * time.Minute)
	admin = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": admin.RefreshToken}))
	remove := "/v1/admin/packs/" + p.ID + "/remove"

	if r := a.do(http.MethodPost, remove, nil, bearer(admin)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("stale: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/session/reauth", map[string]string{"password": goodPassword}, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("reauth: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, remove, nil, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("after reauth: %d %s", r.Code, r.Body)
	}
}
