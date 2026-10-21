package httpapi_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

const ytID = "dQw4w9WgXcQ"

type videoResp struct {
	ID              string  `json:"id"`
	YouTubeID       string  `json:"youtube_id"`
	Title           string  `json:"title"`
	ChannelTitle    string  `json:"channel_title"`
	DurationSeconds int     `json:"duration_seconds"`
	State           string  `json:"state"`
	Round           int     `json:"round"`
	Theme           *string `json:"theme"`
	MinAgeBand      *string `json:"min_age_band"`
	Revisit         bool    `json:"revisit"`
}

func decodeVideo(t *testing.T, r resp) videoResp {
	t.Helper()
	var v videoResp
	if err := json.Unmarshal(r.Body.Bytes(), &v); err != nil || v.ID == "" {
		t.Fatalf("video body: %d %s", r.Code, r.Body)
	}
	return v
}

func (r resp) problemReason() string {
	var p struct {
		Reason string `json:"reason"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &p)
	return p.Reason
}

// suggest has tok suggest a kids' video with the given ID and returns it.
func (a *api) suggest(tok mobileTokens, id string) videoResp {
	a.t.Helper()
	a.videos.Add(curationtest.Kids(id, "Vídeo "+id))
	r := a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": "https://youtu.be/" + id}, bearer(tok)...)
	if r.Code != http.StatusCreated && r.Code != http.StatusOK {
		a.t.Fatalf("suggest %s: %d %s", id, r.Code, r.Body)
	}
	return decodeVideo(a.t, r)
}

// cleanAnswers answers every question of the current list with "ok".
func cleanAnswers() map[string]string {
	out := map[string]string{}
	for _, g := range curation.Checklist() {
		for _, it := range g.Items {
			out[it.ID] = string(curation.AnswerOK)
		}
	}
	return out
}

func approval(theme, band string) map[string]any {
	return map[string]any{"decision": "approve", "theme": theme, "min_age_band": band,
		"checklist_version": curation.ChecklistVersion, "answers": cleanAnswers()}
}

// rejection refuses for items, with note.
func rejection(note string, items ...string) map[string]any {
	return map[string]any{"decision": "reject", "checklist_version": curation.ChecklistVersion,
		"failed_items": items, "note": note}
}

const c15 = "Pede para comprar, pedir aos pais, comentar para ganhar, ou diz preço e loja?"

func TestSuggestOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	bia := a.familyOwner("bia@example.com")
	a.videos.Add(curationtest.Kids(ytID, "Baby Shark"))

	r := a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": "https://www.youtube.com/watch?v=" + ytID}, bearer(ana)...)
	if r.Code != http.StatusCreated {
		t.Fatalf("new: %d %s", r.Code, r.Body)
	}
	v := decodeVideo(t, r)
	if v.YouTubeID != ytID || v.State != "pending" || v.Round != 1 || v.Title != "Baby Shark" || v.DurationSeconds != 300 ||
		v.Theme != nil || v.MinAgeBand != nil {
		t.Fatalf("video %+v", v)
	}
	r = a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": "https://youtu.be/" + ytID}, bearer(bia)...)
	if r.Code != http.StatusOK || decodeVideo(t, r).ID != v.ID {
		t.Fatalf("stored: %d %s", r.Code, r.Body)
	}

	noKids := curationtest.Kids("nokids00000", "Adultos")
	noKids.MadeForKids = false
	a.videos.Add(noKids)
	for link, want := range map[string][2]string{
		"https://vimeo.com/1":                    {"invalid_link", ""},
		"https://www.youtube.com/shorts/" + ytID: {"video_refused", "shorts"},
		"https://youtu.be/nokids00000":           {"video_refused", "not_for_kids"},
		"https://youtu.be/missing0000":           {"video_refused", "not_found"},
	} {
		r := a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": link}, bearer(ana)...)
		if r.Code != http.StatusUnprocessableEntity || r.problemCode() != want[0] || r.problemReason() != want[1] {
			t.Errorf("%s: %d %q %q", link, r.Code, r.problemCode(), r.problemReason())
		}
	}

	a.videos.Err = errors.New("quota")
	if r := a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": "https://youtu.be/another0000"}, bearer(ana)...); r.Code != http.StatusServiceUnavailable || r.problemCode() != "video_source_unavailable" {
		t.Fatalf("source down: %d %q", r.Code, r.problemCode())
	}

	var list struct {
		Suggestions []struct {
			VideoID      string `json:"video_id"`
			Title        string `json:"title"`
			ChannelTitle string `json:"channel_title"`
			State        string `json:"state"`
			SuggestedAt  string `json:"suggested_at"`
		} `json:"suggestions"`
	}
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/suggestions", nil, bearer(ana)...).Body.Bytes(), &list)
	if len(list.Suggestions) != 1 || list.Suggestions[0].VideoID != v.ID || list.Suggestions[0].Title != "Baby Shark" ||
		list.Suggestions[0].ChannelTitle != "Canal Baby Shark" || list.Suggestions[0].State != "pending" || list.Suggestions[0].SuggestedAt == "" {
		t.Fatalf("suggestions %+v", list)
	}
}

func TestSuggestionLimitOverHTTP(t *testing.T) {
	a := newAPI(t)
	ana := a.familyOwner("ana@example.com")
	for i := range 5 {
		a.suggest(ana, fmt.Sprintf("video%06d", i))
	}
	for i := range 5 { // refused calls spend the budget too
		link := fmt.Sprintf("https://vimeo.com/%d", i)
		if r := a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": link}, bearer(ana)...); r.Code != http.StatusUnprocessableEntity {
			t.Fatalf("refused call: %d", r.Code)
		}
	}
	a.videos.Add(curationtest.Kids("video000010", "Mais um"))
	r := a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": "https://youtu.be/video000010"}, bearer(ana)...)
	if r.Code != http.StatusTooManyRequests || r.problemCode() != "rate_limited" || r.Header().Get("Retry-After") == "" {
		t.Fatalf("eleventh: %d %q %q", r.Code, r.problemCode(), r.Header().Get("Retry-After"))
	}
}

func TestReviewOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "pedagogo")
	v := a.suggest(a.familyOwner("gui@example.com"), ytID)

	var q struct {
		Videos     []videoResp `json:"videos"`
		NextOffset *int        `json:"next_offset"`
	}
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/curation/queue", nil, bearer(c1)...).Body.Bytes(), &q)
	if len(q.Videos) != 1 || q.Videos[0].ID != v.ID || q.Videos[0].Revisit || q.NextOffset != nil {
		t.Fatalf("queue %+v", q)
	}
	for _, off := range []string{"-1", "x"} {
		if r := a.do(http.MethodGet, "/v1/curation/queue?offset="+off, nil, bearer(c1)...); r.Code != http.StatusUnprocessableEntity {
			t.Errorf("offset %s: %d", off, r.Code)
		}
	}

	reviews := "/v1/curation/videos/" + v.ID + "/reviews"
	if r := a.do(http.MethodPost, reviews, approval("carros", "5-8"), bearer(c1)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("bad theme: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c1)...)
	var out struct {
		Review struct {
			DisplayRole string `json:"display_role"`
			Decision    string `json:"decision"`
			Theme       string `json:"theme"`
		} `json:"review"`
		VideoState string `json:"video_state"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &out)
	if r.Code != http.StatusCreated || out.Review.DisplayRole != "mae-pai" || out.Review.Decision != "approve" ||
		out.Review.Theme != "bichos" || out.VideoState != "pending" {
		t.Fatalf("first approval: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c1)...); r.Code != http.StatusConflict || r.problemCode() != "already_reviewed" {
		t.Fatalf("again: %d %q", r.Code, r.problemCode())
	}
	a.now = a.now.Add(time.Minute)
	r = a.do(http.MethodPost, reviews, approval("musica", "9-12"), bearer(c2)...)
	_ = json.Unmarshal(r.Body.Bytes(), &out)
	if r.Code != http.StatusCreated || out.VideoState != "approved" {
		t.Fatalf("second approval: %d %s", r.Code, r.Body)
	}

	detail := a.do(http.MethodGet, "/v1/curation/videos/"+v.ID, nil, bearer(c1)...)
	var d struct {
		Video      videoResp `json:"video"`
		Reviews    []any     `json:"reviews"`
		Provenance *struct {
			Approvals      map[string]int `json:"approvals"`
			LastReviewedAt string         `json:"last_reviewed_at"`
		} `json:"provenance"`
	}
	if err := json.Unmarshal(detail.Body.Bytes(), &d); err != nil || detail.Code != http.StatusOK {
		t.Fatalf("detail: %d %s", detail.Code, detail.Body)
	}
	if d.Video.State != "approved" || d.Video.Theme == nil || *d.Video.Theme != "bichos" ||
		d.Video.MinAgeBand == nil || *d.Video.MinAgeBand != "9-12" ||
		d.Reviews == nil || len(d.Reviews) != 0 || d.Provenance == nil ||
		d.Provenance.Approvals["mae-pai"] != 1 || d.Provenance.Approvals["pedagogo"] != 1 || d.Provenance.LastReviewedAt == "" {
		t.Fatalf("detail %s", detail.Body)
	}
	for _, leak := range []string{a.accountID(c1), a.accountID(c2), "c1@example.com", "c2@example.com"} {
		if strings.Contains(detail.Body.String(), leak) {
			t.Errorf("the detail exposes a reviewer: %s", leak)
		}
	}

	c3 := a.curator(admin, "c3@example.com", "cuidador")
	if r := a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c3)...); r.Code != http.StatusConflict || r.problemCode() != "not_reviewable" {
		t.Fatalf("an approved video before its revisit: %d %q", r.Code, r.problemCode())
	}
	for _, p := range []string{"GET /v1/curation/videos/abc", "POST /v1/curation/videos/abc/reviews",
		"GET /v1/curation/videos/00000000-0000-0000-0000-000000000000"} {
		method, path, _ := strings.Cut(p, " ")
		if r := a.do(method, path, approval("bichos", "5-8"), bearer(c1)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Errorf("%s: %d %q", p, r.Code, r.problemCode())
		}
	}
}

func TestCuratorsSuggestWithoutLimitButNeverReviewTheirOwn(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c := a.curator(admin, "c1@example.com", "mae-pai")
	var first videoResp
	for i := range 11 {
		v := a.suggest(c, fmt.Sprintf("video%06d", i))
		if i == 0 {
			first = v
		}
	}
	r := a.do(http.MethodPost, "/v1/curation/videos/"+first.ID+"/reviews", approval("bichos", "5-8"), bearer(c)...)
	if r.Code != http.StatusForbidden || r.problemCode() != "own_suggestion" {
		t.Fatalf("own suggestion: %d %q", r.Code, r.problemCode())
	}
}

func TestHeldVideosOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "cuidador")
	gui := a.familyOwner("gui@example.com")
	v := a.suggest(gui, ytID)
	reviews := "/v1/curation/videos/" + v.ID + "/reviews"
	a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c1)...)
	r := a.do(http.MethodPost, reviews, rejection("Tem propaganda no meio.", "c15"), bearer(c2)...)
	if r.Code != http.StatusCreated || !strings.Contains(r.Body.String(), `"video_state":"held"`) {
		t.Fatalf("rejection: %d %s", r.Code, r.Body)
	}

	var held struct {
		Videos []struct {
			Video      videoResp `json:"video"`
			Rejections []struct {
				DisplayRole string `json:"display_role"`
				Reason      string `json:"reason"`
			} `json:"rejections"`
		} `json:"videos"`
	}
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(admin)...).Body.Bytes(), &held)
	if len(held.Videos) != 1 || held.Videos[0].Video.ID != v.ID || len(held.Videos[0].Rejections) != 1 ||
		held.Videos[0].Rejections[0].DisplayRole != "cuidador" || held.Videos[0].Rejections[0].Reason != c15+"\nTem propaganda no meio." {
		t.Fatalf("held %+v", held)
	}

	why := map[string]any{"reason": "Propaganda disfarçada."}
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+v.ID+"/remove", why, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("remove: %d %s", r.Code, r.Body)
	}
	bia := a.familyOwner("bia@example.com")
	r = a.do(http.MethodPost, "/v1/suggestions", map[string]string{"url": "https://youtu.be/" + ytID}, bearer(bia)...)
	if r.Code != http.StatusUnprocessableEntity || r.problemCode() != "video_refused" || r.problemReason() != "removed" {
		t.Fatalf("suggesting a removed video: %d %q %q", r.Code, r.problemCode(), r.problemReason())
	}
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+v.ID+"/reopen", why, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("reopen: %d %s", r.Code, r.Body)
	}
	var q struct {
		Videos []videoResp `json:"videos"`
	}
	_ = json.Unmarshal(a.do(http.MethodGet, "/v1/curation/queue", nil, bearer(c1)...).Body.Bytes(), &q)
	if len(q.Videos) != 1 || q.Videos[0].ID != v.ID || q.Videos[0].Round != 2 || q.Videos[0].State != "pending" {
		t.Fatalf("queue after reopen %+v", q)
	}
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+v.ID+"/remove", why, bearer(admin)...); r.Code != http.StatusConflict || r.problemCode() != "state_conflict" {
		t.Fatalf("remove a pending video: %d %q", r.Code, r.problemCode())
	}
}

func TestCurationAuditCarriesIDsOnly(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "mae-pai")
	gui := a.familyOwner("gui@example.com")
	published := a.suggest(gui, "aaaaaaaaaaa")
	a.do(http.MethodPost, "/v1/curation/videos/"+published.ID+"/reviews", approval("bichos", "5-8"), bearer(c1)...)
	a.do(http.MethodPost, "/v1/curation/videos/"+published.ID+"/reviews", approval("bichos", "5-8"), bearer(c2)...)
	held := a.suggest(gui, "bbbbbbbbbbb")
	a.do(http.MethodPost, "/v1/curation/videos/"+held.ID+"/reviews", rejection("Não.", "c04"), bearer(c1)...)
	why := map[string]any{"reason": "Motivo válido."}
	a.do(http.MethodPost, "/v1/moderation/videos/"+held.ID+"/remove", why, bearer(admin)...)
	a.do(http.MethodPost, "/v1/moderation/videos/"+held.ID+"/reopen", why, bearer(admin)...)
	c2Path := "/v1/admin/staff/" + a.accountID(c2)
	a.do(http.MethodPatch, c2Path+"/curator", map[string]any{"display_role": "cuidador", "reason": "Mudou de papel."}, bearer(admin)...)
	a.do(http.MethodPost, c2Path+"/roles/curator/revoke", why, bearer(admin)...)
	if _, err := a.team.RevokeAdmin(context.Background(), "ana@example.com"); err != nil {
		t.Fatal(err)
	}

	// Who triggers each event: the last reviewer publishes, the one whose
	// rejection holds is the actor of video_held, the admin removes and reopens.
	actor := map[audit.Event]string{
		audit.VideoPublished: a.accountID(c2), audit.VideoHeld: a.accountID(c1),
		audit.VideoRemoved: adminID, audit.VideoReopened: adminID,
		audit.CuratorAppointed: adminID, audit.CuratorUpdated: adminID, audit.CuratorRemoved: adminID,
	}
	seen := map[audit.Event]int{}
	for _, e := range a.audit.Entries {
		want, ok := actor[e.Event]
		if !ok {
			continue
		}
		seen[e.Event]++
		// An entry is an account ID and an event name, nothing else: no
		// email, link, YouTube ID or title can ride along.
		if !uuidRE.MatchString(e.AccountID) {
			t.Errorf("%s carries %q, not an account ID", e.Event, e.AccountID)
		}
		if e.Event != audit.CuratorAppointed && e.AccountID != want {
			t.Errorf("%s recorded for %s, want the actor %s", e.Event, e.AccountID, want)
		}
	}
	for _, e := range []audit.Event{audit.VideoPublished, audit.VideoHeld, audit.VideoRemoved, audit.VideoReopened,
		audit.CuratorUpdated, audit.CuratorRemoved} {
		if seen[e] != 1 {
			t.Errorf("%s recorded %d times, want 1", e, seen[e])
		}
	}
	if seen[audit.CuratorAppointed] != 2 {
		t.Errorf("curator_appointed recorded %d times, want 2", seen[audit.CuratorAppointed])
	}
	for _, e := range []audit.Event{audit.AdminGranted, audit.AdminRevoked} {
		found := false
		for _, x := range a.audit.Entries {
			found = found || x.Event == e && uuidRE.MatchString(x.AccountID)
		}
		if !found {
			t.Errorf("no %s event with an account ID", e)
		}
	}
}
