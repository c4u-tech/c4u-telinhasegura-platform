package httpapi_test

import (
	"net/http"
	"testing"
)

func TestApprovedVideosOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	v := a.threeVideos() // two in bichos, one in musica

	var page struct {
		Videos []struct {
			ID           string  `json:"id"`
			ChannelTitle string  `json:"channel_title"`
			Theme        *string `json:"theme"`
			MinAgeBand   *string `json:"min_age_band"`
		} `json:"videos"`
		NextOffset *int `json:"next_offset"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/curation/videos?theme=bichos", nil, bearer(cur)...), &page)
	if len(page.Videos) != 2 || page.Videos[0].ID != v[0] || page.Videos[1].ID != v[2] || page.NextOffset != nil ||
		page.Videos[0].ChannelTitle != "Canal" || *page.Videos[0].Theme != "bichos" || *page.Videos[0].MinAgeBand != "ate-4" {
		t.Fatalf("bichos %+v", page)
	}
	for _, q := range []string{"", "?theme=", "?theme=esportes", "?theme=bichos&offset=-1", "?theme=bichos&offset=x"} {
		if r := a.do(http.MethodGet, "/v1/curation/videos"+q, nil, bearer(cur)...); r.Code != http.StatusUnprocessableEntity ||
			r.problemCode() != "validation" {
			t.Errorf("%q: %d %q", q, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodGet, "/v1/curation/videos/"+v[0], nil, bearer(cur)...); r.Code != http.StatusOK {
		t.Fatalf("the video detail: %d %s", r.Code, r.Body)
	}
}

func TestPackCurationReadsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")

	var limits map[string]int
	getJSON(t, a.do(http.MethodGet, "/v1/curation/packs/limits", nil, bearer(cur)...), &limits)
	if limits["min_videos"] != 3 || limits["max_videos"] != 5 || limits["max_seconds"] != 1200 || len(limits) != 3 {
		t.Fatalf("limits %v", limits)
	}

	p := decodePack(t, a.do(http.MethodPost, "/v1/curation/packs", composition("Bichos", a.threeVideos()...), bearer(cur)...),
		http.StatusCreated)
	if p.Videos[0].ChannelTitle != "Canal" {
		t.Fatalf("composed %+v", p)
	}
	if got := decodePack(t, a.do(http.MethodGet, "/v1/curation/packs/"+p.ID, nil, bearer(cur)...), http.StatusOK); got.Videos[2].ChannelTitle != "Canal" {
		t.Fatalf("detail %+v", got)
	}
}

func TestAdminPackReadsOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com") // an admin, not a curator
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	p := decodePack(t, a.do(http.MethodPost, "/v1/curation/packs", composition("Bichos", a.threeVideos()...), bearer(cur)...),
		http.StatusCreated)

	var list struct {
		Packs   []packResp `json:"packs"`
		HasMore bool       `json:"has_more"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/admin/packs", nil, bearer(admin)...), &list)
	if len(list.Packs) != 1 || list.Packs[0].ID != p.ID || list.Packs[0].Reviewable || list.HasMore ||
		list.Packs[0].ComposerRole != "mae-pai" {
		t.Fatalf("admin list %+v", list)
	}
	if r := a.do(http.MethodGet, "/v1/admin/packs?offset=x", nil, bearer(admin)...); r.Code != http.StatusUnprocessableEntity {
		t.Fatalf("bad offset: %d", r.Code)
	}

	got := decodePack(t, a.do(http.MethodGet, "/v1/admin/packs/"+p.ID, nil, bearer(admin)...), http.StatusOK)
	if got.ID != p.ID || got.Reviewable || got.Videos[0].ChannelTitle != "Canal" {
		t.Fatalf("admin detail %+v", got)
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if r := a.do(http.MethodGet, "/v1/admin/packs/"+id, nil, bearer(admin)...); r.Code != http.StatusNotFound ||
			r.problemCode() != "not_found" {
			t.Errorf("%q: %d %q", id, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodGet, "/v1/admin/packs", nil, bearer(cur)...); r.Code != http.StatusForbidden ||
		r.problemCode() != "not_admin" {
		t.Fatalf("a curator who is not an admin: %d %q", r.Code, r.problemCode())
	}
}
