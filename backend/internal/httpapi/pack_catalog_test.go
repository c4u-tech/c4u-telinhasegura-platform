package httpapi_test

import (
	"context"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

func (a *api) exec(sql string, args ...any) {
	a.t.Helper()
	if _, err := a.pool.Exec(context.Background(), sql, args...); err != nil {
		a.t.Fatal(err)
	}
}

// publishedPack inserts an approved pack whose published round 1 holds
// videoIDs in order, titled "Pacotinho", the first as cover, composed by
// an erased mae-pai, with one pedagogo approval.
func (a *api) publishedPack(videoIDs ...string) string {
	a.t.Helper()
	var id string
	if err := a.pool.QueryRow(context.Background(), `INSERT INTO packs (state, round, published_round, last_reviewed_at,
		created_at, updated_at) VALUES ('approved', 1, 1, $1, $1, $1) RETURNING id::text`, a.now).Scan(&id); err != nil {
		a.t.Fatal(err)
	}
	a.exec(`INSERT INTO pack_rounds (pack_id, round, title, cover_video_id, composer_role, composed_at, outcome)
		VALUES ($1::uuid, 1, 'Pacotinho', $2::uuid, 'mae-pai', $3, 'published')`, id, videoIDs[0], a.now)
	for i, v := range videoIDs {
		a.exec(`INSERT INTO pack_items (pack_id, round, position, video_id) VALUES ($1::uuid, 1, $2, $3::uuid)`, id, i+1, v)
	}
	a.exec(`INSERT INTO pack_reviews (pack_id, round, display_role, decision, reviewed_at)
		VALUES ($1::uuid, 1, 'pedagogo', 'approve', $2)`, id, a.now)
	return id
}

func TestChildCatalogCarriesPacks(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com") // a 5-8 child
	kid := bearer(tok)
	if r := a.do(http.MethodGet, "/v1/child/catalog", nil, kid...); r.Code != http.StatusOK || !strings.Contains(r.Body.String(), `"packs":[]`) {
		t.Fatalf("no pack: %d %s", r.Code, r.Body)
	}
	v := a.threeVideos()
	id := a.publishedPack(v...)

	r := a.do(http.MethodGet, "/v1/child/catalog", nil, kid...)
	var cat struct {
		Packs []map[string]any `json:"packs"`
	}
	getJSON(t, r, &cat)
	if len(cat.Packs) != 1 {
		t.Fatalf("packs %s", r.Body)
	}
	p := cat.Packs[0]
	if len(p) != 4 || p["id"] != id || p["title"] != "Pacotinho" || p["cover_video_id"] != v[0] {
		t.Fatalf("a child's pack carries %v", p)
	}
	videos, _ := p["videos"].([]any)
	first, _ := videos[0].(map[string]any)
	if len(videos) != 3 || len(first) != 3 || first["id"] != v[0] || first["title"] != "Vídeo aaaaaaaaaaa" ||
		first["duration_seconds"] != float64(300) {
		t.Fatalf("a child's pack videos %v", videos)
	}
	for _, leak := range []string{"pedagogo", "mae-pai", "provenance", "composer"} {
		if strings.Contains(r.Body.String(), leak) {
			t.Errorf("the child's catalogue carries %q", leak)
		}
	}
}

func TestFamilyCatalogCarriesPacks(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	lia := a.addMinor(ana) // 5-8
	bia := a.familyOwner("bia@example.com")
	v := a.threeVideos()
	id := a.publishedPack(v...)
	path := "/v1/family/minors/" + lia
	if r := a.do(http.MethodPut, path+"/hidden/"+v[1], nil, bearer(ana)...); r.Code != http.StatusNoContent {
		t.Fatalf("hide: %d %s", r.Code, r.Body)
	}

	var page struct {
		Packs []struct {
			ID           string `json:"id"`
			Title        string `json:"title"`
			CoverVideoID string `json:"cover_video_id"`
			ComposerRole string `json:"composer_role"`
			Videos       []struct {
				ID              string `json:"id"`
				Title           string `json:"title"`
				DurationSeconds int    `json:"duration_seconds"`
				Hidden          bool   `json:"hidden"`
			} `json:"videos"`
			Provenance struct {
				Approvals      map[string]int `json:"approvals"`
				LastReviewedAt string         `json:"last_reviewed_at"`
			} `json:"provenance"`
		} `json:"packs"`
	}
	getJSON(t, a.do(http.MethodGet, path+"/catalog", nil, bearer(ana)...), &page)
	if len(page.Packs) != 1 {
		t.Fatalf("packs %+v", page)
	}
	p := page.Packs[0]
	if p.ID != id || p.Title != "Pacotinho" || p.CoverVideoID != v[0] || p.ComposerRole != "mae-pai" || len(p.Videos) != 3 ||
		p.Videos[0].Hidden || !p.Videos[1].Hidden || p.Videos[1].ID != v[1] || p.Videos[2].Hidden || p.Videos[2].DurationSeconds != 300 ||
		p.Provenance.Approvals["pedagogo"] != 1 || p.Provenance.LastReviewedAt == "" {
		t.Fatalf("pack %+v", p)
	}
	if r := a.do(http.MethodGet, path+"/catalog?offset=50", nil, bearer(ana)...); r.Code != http.StatusOK ||
		!strings.Contains(r.Body.String(), `"packs":[]`) {
		t.Fatalf("a later page: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodGet, path+"/catalog", nil, bearer(bia)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("another family's minor: %d %q", r.Code, r.problemCode())
	}
}

func TestAPackCoverIsAThumbnailTheChildMayFetch(t *testing.T) {
	a := newAPI(t)
	tok, minor := a.lockedSession("ana@example.com")
	v := a.threeVideos()
	a.publishedPack(v...) // v[0] is the cover
	if err := a.cur.Hide(context.Background(), a.accountID(tok), minor, v[0]); err != nil {
		t.Fatal(err)
	}
	a.thumbs.Add("bbbbbbbbbbb", []byte("jpeg"))

	var cat struct {
		Packs []struct {
			CoverVideoID string           `json:"cover_video_id"`
			Videos       []map[string]any `json:"videos"`
		} `json:"packs"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/child/catalog", nil, bearer(tok)...), &cat)
	if len(cat.Packs) != 1 || cat.Packs[0].CoverVideoID != v[1] || len(cat.Packs[0].Videos) != 2 {
		t.Fatalf("packs %+v", cat.Packs)
	}
	if r := a.do(http.MethodGet, "/v1/child/thumbs/"+cat.Packs[0].CoverVideoID, nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("the served cover's thumbnail: %d %q", r.Code, r.problemCode())
	}
}

func TestGuardianPacksFollowTheFamilysZone(t *testing.T) {
	a := newAPI(t)
	a.now = time.Date(2026, 10, 3, 3, 30, 0, 0, time.UTC) // 00:30 on the 3rd in São Paulo, 23:30 on the 2nd in Manaus
	ana := a.familyOwner("ana@example.com")
	lia := a.addMinor(ana)
	v := a.threeVideos()
	for range 30 {
		a.publishedPack(v...)
	}
	var fam string
	if err := a.pool.QueryRow(context.Background(), `SELECT family_id::text FROM minors WHERE id = $1::uuid`, lia).Scan(&fam); err != nil {
		t.Fatal(err)
	}
	a.exec(`INSERT INTO screentime_families (family_id, time_zone, set_at) VALUES ($1::uuid, 'America/Manaus', $2)`, fam, a.now)
	manaus, _ := time.LoadLocation("America/Manaus")
	saoPaulo, _ := time.LoadLocation("America/Sao_Paulo")
	ids := func(loc *time.Location) []string {
		t.Helper()
		ps, err := a.cur.KidPacks(context.Background(), curation.Child{FamilyID: fam, MinorID: lia}, loc)
		if err != nil {
			t.Fatal(err)
		}
		out := []string{}
		for _, p := range ps {
			out = append(out, p.ID)
		}
		return out
	}

	var page struct {
		Packs []struct {
			ID string `json:"id"`
		} `json:"packs"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/family/minors/"+lia+"/catalog", nil, bearer(ana)...), &page)
	got := []string{}
	for _, p := range page.Packs {
		got = append(got, p.ID)
	}
	if want := ids(manaus); !slices.Equal(got, want) {
		t.Fatalf("guardian %v, the child in Manaus %v", got, want)
	}
	if slices.Equal(got, ids(saoPaulo)) {
		t.Fatal("the guardian's row followed São Paulo's day")
	}
}
