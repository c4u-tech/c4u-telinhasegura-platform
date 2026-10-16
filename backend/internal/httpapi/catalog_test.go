package httpapi_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
)

// published inserts an approved video titled "Vídeo <youtubeID>" in theme
// and band, whose published round holds one mae-pai approval.
func (a *api) published(youtubeID, theme, band string) string {
	a.t.Helper()
	var id string
	if err := a.pool.QueryRow(context.Background(), `INSERT INTO videos (youtube_id, title, channel_id, channel_title,
		duration_seconds, state, round, published_round, theme, min_age_band, last_reviewed_at, review_due_at, created_at, updated_at)
		VALUES ($1, 'Vídeo ' || $1, 'UC1', 'Canal', 300, 'approved', 2, 1, $2, $3, $4, $4, $4, $4) RETURNING id::text`,
		youtubeID, theme, band, a.now).Scan(&id); err != nil {
		a.t.Fatal(err)
	}
	if _, err := a.pool.Exec(context.Background(), `INSERT INTO video_reviews (video_id, round, curator_id, display_role,
		decision, theme, min_age_band, reviewed_at) VALUES ($1::uuid, 1, NULL, 'mae-pai', 'approve', $2, $3, $4)`,
		id, theme, band, a.now); err != nil {
		a.t.Fatal(err)
	}
	return id
}

func TestChildCatalogOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com") // a 5-8 child
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	strict := a.published("aaaaaaaaaaa", "musica", "9-12")
	noThumb := a.published("bbbbbbbbbbb", "musica", "5-8")
	a.thumbs.Add("dQw4w9WgXcQ", []byte("jpeg"))
	kid := bearer(tok)

	r := a.do(http.MethodGet, "/v1/child/catalog", nil, kid...)
	var cat struct {
		Themes []struct {
			Theme  string           `json:"theme"`
			Videos []map[string]any `json:"videos"`
		} `json:"themes"`
	}
	getJSON(t, r, &cat)
	if len(cat.Themes) != 2 || cat.Themes[0].Theme != "bichos" || cat.Themes[1].Theme != "musica" {
		t.Fatalf("themes %s", r.Body)
	}
	first := cat.Themes[0].Videos[0]
	if len(first) != 3 || first["id"] != v || first["title"] != "Vídeo dQw4w9WgXcQ" || first["duration_seconds"] != float64(300) {
		t.Fatalf("a child's video carries %v", first)
	}

	r = a.do(http.MethodGet, "/v1/child/thumbs/"+v, nil, kid...)
	if r.Code != http.StatusOK || r.Body.String() != "jpeg" || r.Header().Get("Content-Type") != "image/jpeg" ||
		r.Header().Get("Cache-Control") != "private, max-age=86400" || r.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("thumb: %d %v %q", r.Code, r.Header(), r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/child/thumbs/"+noThumb, nil, kid...); r.Code != http.StatusServiceUnavailable || r.problemCode() != "thumbnail_unavailable" {
		t.Fatalf("missing thumb: %d %q", r.Code, r.problemCode())
	}

	r = a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": v}, kid...)
	var play map[string]any
	_ = json.Unmarshal(r.Body.Bytes(), &play) // a 201: getJSON wants a 200
	if r.Code != http.StatusCreated || play["youtube_id"] != "dQw4w9WgXcQ" || play["play_id"] == "" || len(play) != 3 {
		t.Fatalf("play %d %v", r.Code, play)
	}

	a.videos.Add(curationtest.Kids("dQw4w9WgXcQ", "Baby Shark"))
	if r := a.do(http.MethodPost, "/v1/child/videos/"+v+"/unavailable", nil, kid...); r.Code != http.StatusAccepted {
		t.Fatalf("unavailable: %d %s", r.Code, r.Body)
	}

	for _, c := range []struct{ method, path string }{
		{http.MethodGet, "/v1/child/thumbs/" + strict},
		{http.MethodGet, "/v1/child/thumbs/abc"},
		{http.MethodPost, "/v1/child/videos/" + strict + "/unavailable"},
		{http.MethodPost, "/v1/child/videos/abc/unavailable"},
	} {
		if r := a.do(c.method, c.path, nil, kid...); r.Code != http.StatusForbidden || r.problemCode() != "video_not_allowed" {
			t.Errorf("%s %s: %d %q", c.method, c.path, r.Code, r.problemCode())
		}
	}
	for _, id := range []string{strict, "abc"} {
		if r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": id}, kid...); r.Code != http.StatusForbidden || r.problemCode() != "video_not_allowed" {
			t.Errorf("play %s: %d %q", id, r.Code, r.problemCode())
		}
	}
}

func TestChildCatalogOnALinkedDevice(t *testing.T) {
	a := newAPI(t)
	owner := a.familyOwner("ana@example.com")
	minor := a.addMinor(owner)
	a.do(http.MethodPut, "/v1/parental/pin", map[string]string{"pin": "2580"}, bearer(owner)...)
	dev := devBearer(a.linkedDevice(owner, minor))
	a.published("dQw4w9WgXcQ", "bichos", "ate-4")

	r := a.do(http.MethodGet, "/v1/child/catalog", nil, dev...)
	if r.Code != http.StatusOK || !strings.Contains(r.Body.String(), `"theme":"bichos"`) {
		t.Fatalf("%d %s", r.Code, r.Body)
	}
}

func TestChildCatalogOnceTheChildIsGone(t *testing.T) {
	a := newAPI(t)
	tok, minor := a.lockedSession("ana@example.com")
	if _, err := a.pool.Exec(context.Background(), `DELETE FROM minors WHERE id = $1::uuid`, minor); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"/v1/child/profile", "/v1/child/catalog"} {
		if r := a.do(http.MethodGet, path, nil, bearer(tok)...); r.Code != http.StatusGone || r.problemCode() != "profile_gone" {
			t.Errorf("%s: %d %q", path, r.Code, r.problemCode())
		}
	}
}

func TestFamilyCatalogOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	lia := a.addMinor(ana) // 5-8
	bia := a.familyOwner("bia@example.com")
	teo := a.addMinor(bia)
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	path := "/v1/family/minors/" + lia + "/catalog"

	type item struct {
		ID              string         `json:"id"`
		YouTubeID       string         `json:"youtube_id"`
		Title           string         `json:"title"`
		ChannelTitle    string         `json:"channel_title"`
		DurationSeconds int            `json:"duration_seconds"`
		Theme           string         `json:"theme"`
		MinAgeBand      string         `json:"min_age_band"`
		Hidden          bool           `json:"hidden"`
		Provenance      map[string]any `json:"provenance"`
	}
	var page struct {
		Videos  []item `json:"videos"`
		HasMore bool   `json:"has_more"`
	}
	getJSON(t, a.do(http.MethodGet, path, nil, bearer(ana)...), &page)
	if len(page.Videos) != 1 || page.HasMore {
		t.Fatalf("page %+v", page)
	}
	got := page.Videos[0]
	if got.ID != v || got.YouTubeID != "dQw4w9WgXcQ" || got.Title != "Vídeo dQw4w9WgXcQ" || got.ChannelTitle != "Canal" || got.DurationSeconds != 300 ||
		got.Theme != "bichos" || got.MinAgeBand != "ate-4" || got.Hidden {
		t.Fatalf("item %+v", got)
	}
	if approvals, _ := got.Provenance["approvals"].(map[string]any); approvals["mae-pai"] != float64(1) || got.Provenance["last_reviewed_at"] == nil {
		t.Fatalf("provenance %v", got.Provenance)
	}

	hidden := "/v1/family/minors/" + lia + "/hidden/" + v
	for range 2 {
		if r := a.do(http.MethodPut, hidden, nil, bearer(ana)...); r.Code != http.StatusNoContent {
			t.Fatalf("hide: %d %s", r.Code, r.Body)
		}
	}
	getJSON(t, a.do(http.MethodGet, path, nil, bearer(ana)...), &page)
	if !page.Videos[0].Hidden {
		t.Fatal("not hidden")
	}
	if r := a.do(http.MethodDelete, hidden, nil, bearer(ana)...); r.Code != http.StatusNoContent {
		t.Fatalf("unhide: %d %s", r.Code, r.Body)
	}

	for _, c := range []struct{ method, path string }{
		{http.MethodGet, "/v1/family/minors/abc/catalog"},
		{http.MethodGet, "/v1/family/minors/" + teo + "/catalog"},
		{http.MethodPut, "/v1/family/minors/" + lia + "/hidden/xyz"},
		{http.MethodPut, "/v1/family/minors/" + teo + "/hidden/" + v},
		{http.MethodDelete, "/v1/family/minors/abc/hidden/" + v},
	} {
		if r := a.do(c.method, c.path, nil, bearer(ana)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Errorf("%s %s: %d %q", c.method, c.path, r.Code, r.problemCode())
		}
	}
	for _, q := range []string{"-1", "x"} {
		if r := a.do(http.MethodGet, path+"?offset="+q, nil, bearer(ana)...); r.Code != http.StatusUnprocessableEntity {
			t.Errorf("offset %s: %d", q, r.Code)
		}
	}
}

func TestReportOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	body := map[string]string{"video_id": v, "reason": "assustador", "note": "Tem um monstro."}

	if r := a.do(http.MethodPost, "/v1/reports", body, bearer(ana)...); r.Code != http.StatusCreated {
		t.Fatalf("first: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/reports", body, bearer(ana)...); r.Code != http.StatusOK {
		t.Fatalf("again: %d %s", r.Code, r.Body)
	}
	for name, c := range map[string]struct {
		body   map[string]string
		status int
		code   string
	}{
		"unknown reason": {map[string]string{"video_id": v, "reason": "spam"}, http.StatusUnprocessableEntity, "validation"},
		"long note":      {map[string]string{"video_id": v, "reason": "outro", "note": strings.Repeat("é", 501)}, http.StatusUnprocessableEntity, "validation"},
		"unknown video":  {map[string]string{"video_id": "00000000-0000-0000-0000-000000000000", "reason": "outro"}, http.StatusNotFound, "not_found"},
	} {
		if r := a.do(http.MethodPost, "/v1/reports", c.body, bearer(ana)...); r.Code != c.status || r.problemCode() != c.code {
			t.Errorf("%s: %d %q", name, r.Code, r.problemCode())
		}
	}
	a.signUpVerified("solo@example.com")
	solo := a.signInMobile("solo@example.com")
	if r := a.do(http.MethodPost, "/v1/reports", body, bearer(solo)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("no family: %d %q", r.Code, r.problemCode())
	}
}

func TestReportLimitOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	bad := map[string]string{"video_id": v, "reason": "spam"}
	for range 20 {
		a.do(http.MethodPost, "/v1/reports", bad, bearer(ana)...)
	}
	r := a.do(http.MethodPost, "/v1/reports", map[string]string{"video_id": v, "reason": "outro"}, bearer(ana)...)
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") == "" {
		t.Fatalf("21st: %d %q %v", r.Code, r.problemCode(), r.Header())
	}
}

func TestFamilyThumbOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	v := a.published("dQw4w9WgXcQ", "bichos", "9-12")
	a.thumbs.Add("dQw4w9WgXcQ", []byte("jpeg"))
	if r := a.do(http.MethodGet, "/v1/family/thumbs/"+v, nil, bearer(ana)...); r.Code != http.StatusOK || r.Body.String() != "jpeg" ||
		r.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("approved: %d %q", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, "/v1/family/thumbs/abc", nil, bearer(ana)...); r.Code != http.StatusNotFound {
		t.Fatalf("malformed: %d", r.Code)
	}
}

func TestHeldQueueShowsWhyAndTheReports(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("adm@example.com")
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	var reporters []string
	for i, reason := range []string{"assustador", "assustador", "outro"} {
		tok := a.familyOwner(fmt.Sprintf("dono%d@example.com", i))
		reporters = append(reporters, a.accountID(tok))
		note := ""
		if i == 0 {
			note = "Tem um monstro."
		}
		if r := a.do(http.MethodPost, "/v1/reports", map[string]string{"video_id": v, "reason": reason, "note": note}, bearer(tok)...); r.Code != http.StatusCreated {
			t.Fatalf("report %d: %d %s", i, r.Code, r.Body)
		}
	}

	r := a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(admin)...)
	var body struct {
		Videos []struct {
			Video      map[string]any `json:"video"`
			HeldReason string         `json:"held_reason"`
			Reports    struct {
				ByReason map[string]int `json:"by_reason"`
				Notes    []string       `json:"notes"`
			} `json:"reports"`
		} `json:"videos"`
	}
	getJSON(t, r, &body)
	if len(body.Videos) != 1 || body.Videos[0].HeldReason != "reports" {
		t.Fatalf("held %s", r.Body)
	}
	rep := body.Videos[0].Reports
	if rep.ByReason["assustador"] != 2 || rep.ByReason["outro"] != 1 || len(rep.Notes) != 1 || rep.Notes[0] != "Tem um monstro." {
		t.Fatalf("reports %+v", rep)
	}
	for _, id := range reporters {
		if strings.Contains(r.Body.String(), id) {
			t.Fatal("the held queue names a reporter")
		}
	}
}
