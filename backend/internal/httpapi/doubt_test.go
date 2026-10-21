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
	a.now = a.now.Add(6 * time.Minute)
	late := a.refresh(mod)
	if r := a.do(http.MethodPost, decide(stale), publish, bearer(late)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("a stale re-auth: %d %q", r.Code, r.problemCode())
	}
}
