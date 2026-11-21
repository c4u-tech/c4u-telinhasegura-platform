package httpapi_test

import (
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// doubtedBy has a new curator, appointed by admin, answer "doubt" on a new
// video, which holds it for a moderator, and returns the video's ID.
func (a *api) doubtedBy(admin mobileTokens, youtubeID string) string {
	a.t.Helper()
	cur := a.curator(admin, "d-"+strings.ToLower(youtubeID)+"@example.com", "mae-pai")
	v := a.suggest(a.familyOwner("h-"+strings.ToLower(youtubeID)+"@example.com"), youtubeID)
	r := a.do(http.MethodPost, "/v1/curation/videos/"+v.ID+"/reviews",
		approvalWith("bichos", "5-8", map[string]string{"c13": "doubt"}), bearer(cur)...)
	if r.Code != http.StatusCreated || !strings.Contains(r.Body.String(), `"video_state":"held"`) {
		a.t.Fatalf("doubt: %d %s", r.Code, r.Body)
	}
	return v.ID
}

// moderatorEnded reports that the held video played to its end for the
// moderator, as publishing a doubt needs; it must succeed.
func (a *api) moderatorEnded(mod mobileTokens, id string) {
	a.t.Helper()
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+id+"/ended", nil, bearer(mod)...); r.Code != http.StatusNoContent {
		a.t.Fatalf("ended: %d %s", r.Code, r.Body)
	}
}

func TestDecideDoubtOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	mod := a.moderator(admin, "mia@example.com")
	modID := a.accountID(mod)
	v := a.doubtedBy(admin, ytID)
	other := a.doubtedBy(admin, "ccccccccccc")
	stale := a.doubtedBy(admin, "ddddddddddd")
	refused := a.heldBy(admin, "bbbbbbbbbbb")
	decide := func(id string) string { return "/v1/moderation/videos/" + id + "/decide" }
	publish := map[string]any{"decision": "approve", "theme": "musica", "min_age_band": "5-8", "reason": "  Sem risco no vídeo.  "}

	if r := a.do(http.MethodPost, decide(v), map[string]any{"decision": "approve", "theme": "musica", "min_age_band": "5-8"}, bearer(mod)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "reason_required" {
		t.Fatalf("no reason: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, decide(v), map[string]any{"decision": "approve", "min_age_band": "5-8", "reason": "Motivo válido."}, bearer(mod)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("no theme: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, decide(v), publish, bearer(mod)...); r.Code != http.StatusConflict || r.problemCode() != "not_watched" {
		t.Fatalf("publish unwatched: %d %q", r.Code, r.problemCode())
	}
	if _, ok := a.audit.LastAction(audit.VideoDoubtDecided); ok {
		t.Fatal("a refused decision was recorded")
	}
	a.moderatorEnded(mod, v)
	if r := a.do(http.MethodPost, decide(v), publish, bearer(mod)...); r.Code != http.StatusNoContent {
		t.Fatalf("publish: %d %s", r.Code, r.Body)
	}
	want := audit.Action{Actor: modID, ActorRole: "moderator", Event: audit.VideoDoubtDecided, SubjectKind: audit.SubjectVideo,
		SubjectID: v, Reason: "Sem risco no vídeo.", Metadata: map[string]string{"decision": "approve"}}
	if x, ok := a.audit.LastAction(audit.VideoDoubtDecided); !ok || !reflect.DeepEqual(x, want) {
		t.Fatalf("action %+v %v", x, ok)
	}
	if n := a.count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND state = 'approved' AND theme = 'musica' AND held_reason IS NULL`, v); n != 1 {
		t.Fatal("the video was not published")
	}
	if r := a.do(http.MethodPost, decide(v), publish, bearer(mod)...); r.Code != http.StatusConflict || r.problemCode() != "state_conflict" {
		t.Fatalf("decide twice: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, decide(refused), publish, bearer(admin)...); r.Code != http.StatusConflict || r.problemCode() != "state_conflict" {
		t.Fatalf("a refusal is not a doubt: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, decide(other), map[string]any{"decision": "reject", "reason": "Desafio perigoso."}, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("remove: %d %s", r.Code, r.Body)
	}
	if n := a.count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND state = 'removed'`, other); n != 1 {
		t.Fatal("the video was not removed")
	}

	// A stolen moderator session cannot publish unnoticed.
	a.moderatorEnded(mod, stale)
	a.now = a.now.Add(6 * time.Minute)
	late := a.refresh(mod)
	if r := a.do(http.MethodPost, decide(stale), publish, bearer(late)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("a stale re-auth: %d %q", r.Code, r.problemCode())
	}
}

func TestDecideDoubtKeepsALongVideoFromTheYoungestBandOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	mod := a.moderator(admin, "mia@example.com")
	v := a.doubtedBy(admin, ytID)
	a.exec(`UPDATE videos SET duration_seconds = $2 WHERE id = $1::uuid`, v, int((61 * time.Minute).Seconds()))
	a.moderatorEnded(mod, v)
	young := map[string]any{"decision": "approve", "theme": "musica", "min_age_band": "ate-4", "reason": "Sem risco no vídeo."}
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+v+"/decide", young, bearer(mod)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "checklist_band" {
		t.Fatalf("2 to 4: %d %q", r.Code, r.problemCode())
	}
}

func TestModeratorEndedOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	mod := a.moderator(admin, "mia@example.com")
	v := a.doubtedBy(admin, ytID)
	ended := func(id string) string { return "/v1/moderation/videos/" + id + "/ended" }
	a.moderatorEnded(mod, v)
	a.moderatorEnded(admin, v)
	if n := a.count(`SELECT count(*) FROM moderator_views WHERE video_id = $1::uuid`, v); n != 2 {
		t.Fatalf("%d viewings, want the moderator's and the admin's", n)
	}
	pending := a.suggest(a.familyOwner("gui@example.com"), "ccccccccccc")
	if r := a.do(http.MethodPost, ended(pending.ID), nil, bearer(mod)...); r.Code != http.StatusConflict || r.problemCode() != "state_conflict" {
		t.Fatalf("a pending video: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, ended("00000000-0000-0000-0000-000000000000"), nil, bearer(mod)...); r.Code != http.StatusNotFound {
		t.Fatalf("an unknown video: %d", r.Code)
	}
}
