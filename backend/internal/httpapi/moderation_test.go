package httpapi_test

import (
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// heldBy has a new curator, appointed by admin, reject a new video so it
// is held, and returns the video's ID.
func (a *api) heldBy(admin mobileTokens, youtubeID string) string {
	a.t.Helper()
	cur := a.curator(admin, "c-"+strings.ToLower(youtubeID)+"@example.com", "mae-pai")
	v := a.suggest(a.familyOwner("g-"+strings.ToLower(youtubeID)+"@example.com"), youtubeID)
	r := a.do(http.MethodPost, "/v1/curation/videos/"+v.ID+"/reviews",
		rejection("Tem propaganda no meio.", "c15"), bearer(cur)...)
	if r.Code != http.StatusCreated || !strings.Contains(r.Body.String(), `"video_state":"held"`) {
		a.t.Fatalf("rejection: %d %s", r.Code, r.Body)
	}
	return v.ID
}

// removals counts video_removed entries, events and actions alike.
func (a *api) removals() int {
	n := 0
	for _, e := range a.audit.Entries {
		if e.Event == audit.VideoRemoved {
			n++
		}
	}
	return n
}

func TestModerationOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	adminID := a.accountID(admin)
	mod := a.moderator(admin, "mia@example.com")
	modID := a.accountID(mod)
	v := a.heldBy(admin, ytID)

	held := a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(mod)...)
	if held.Code != http.StatusOK || !strings.Contains(held.Body.String(), v) {
		t.Fatalf("moderator: %d %s", held.Code, held.Body)
	}
	if got := a.do(http.MethodGet, "/v1/moderation/videos?state=held", nil, bearer(admin)...); got.Code != http.StatusOK || got.Body.String() != held.Body.String() {
		t.Fatalf("admin: %d %s, want %s", got.Code, got.Body, held.Body)
	}
	if r := a.do(http.MethodGet, "/v1/moderation/videos", nil, bearer(mod)...); r.Code != http.StatusUnprocessableEntity {
		t.Fatalf("no state filter: %d", r.Code)
	}

	remove := "/v1/moderation/videos/" + v + "/remove"
	if r := a.do(http.MethodPost, remove, map[string]any{}, bearer(mod)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "reason_required" {
		t.Fatalf("no reason: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, remove, map[string]any{"reason": "  Propaganda disfarçada.  "}, bearer(mod)...); r.Code != http.StatusNoContent {
		t.Fatalf("remove: %d %s", r.Code, r.Body)
	}
	want := audit.Action{Actor: modID, ActorRole: "moderator", Event: audit.VideoRemoved,
		SubjectKind: audit.SubjectVideo, SubjectID: v, Reason: "Propaganda disfarçada."}
	if x, ok := a.audit.LastAction(audit.VideoRemoved); !ok || !reflect.DeepEqual(x, want) {
		t.Fatalf("action %+v %v", x, ok)
	}
	if n := a.removals(); n != 1 {
		t.Fatalf("the removal was recorded %d times", n)
	}
	if r := a.do(http.MethodPost, remove, map[string]any{"reason": "De novo."}, bearer(mod)...); r.Code != http.StatusConflict || r.problemCode() != "state_conflict" {
		t.Fatalf("remove twice: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+v+"/reopen", map[string]any{"reason": "Canal corrigiu o vídeo."}, bearer(admin)...); r.Code != http.StatusNoContent {
		t.Fatalf("reopen: %d %s", r.Code, r.Body)
	}
	if x, _ := a.audit.LastAction(audit.VideoReopened); x.Actor != adminID || x.ActorRole != "admin" || x.SubjectID != v || x.Reason != "Canal corrigiu o vídeo." {
		t.Fatalf("reopen action %+v", x)
	}
	if r := a.do(http.MethodPost, "/v1/moderation/videos/abc/reopen", map[string]any{"reason": "Motivo válido."}, bearer(mod)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("malformed id: %d %q", r.Code, r.problemCode())
	}
}

func TestAnAdminWhoAlsoModeratesActsAsModerator(t *testing.T) {
	a := newAPI(t)
	ana := a.admin("ana@example.com")
	bia := a.admin("bia@example.com")
	if r := a.grant(bia, "ana@example.com", "moderator", nil); r.Code != http.StatusCreated {
		t.Fatalf("grant: %d %s", r.Code, r.Body)
	}
	v := a.heldBy(bia, ytID)
	if r := a.do(http.MethodPost, "/v1/moderation/videos/"+v+"/remove", map[string]any{"reason": "Propaganda disfarçada."}, bearer(ana)...); r.Code != http.StatusNoContent {
		t.Fatalf("remove: %d %s", r.Code, r.Body)
	}
	if x, _ := a.audit.LastAction(audit.VideoRemoved); x.Actor != a.accountID(ana) || x.ActorRole != "moderator" {
		t.Fatalf("action %+v", x)
	}
	if n := a.removals(); n != 1 {
		t.Fatalf("the removal was recorded %d times", n)
	}
}

func TestModeratorRoleIsCheckedBeforeReauth(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	cur := a.curator(admin, "bia@example.com", "mae-pai")
	mod := a.moderator(admin, "mia@example.com")
	plain := a.familyOwner("caio@example.com")
	a.now = a.now.Add(6 * time.Minute)
	stale := map[string]mobileTokens{}
	for who, tok := range map[string]mobileTokens{"guardian": plain, "curator only": cur, "moderator": mod, "admin": admin} {
		stale[who] = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}))
	}
	body := map[string]any{"reason": "Propaganda disfarçada."}
	const unknown = "/v1/moderation/videos/00000000-0000-0000-0000-000000000000"
	for who, code := range map[string]string{"guardian": "not_moderator", "curator only": "not_moderator",
		"moderator": "reauth_required", "admin": "reauth_required"} {
		if r := a.do(http.MethodPost, unknown+"/remove", body, bearer(stale[who])...); r.Code != http.StatusForbidden || r.problemCode() != code {
			t.Errorf("%s removing with a stale re-auth: %d %q, want %s", who, r.Code, r.problemCode(), code)
		}
	}
	// Reopening needs no re-authentication: the stale moderator reaches the lookup.
	if r := a.do(http.MethodPost, unknown+"/reopen", body, bearer(stale["moderator"])...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
		t.Fatalf("reopen with a stale re-auth: %d %q", r.Code, r.problemCode())
	}
}
