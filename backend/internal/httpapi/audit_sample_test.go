package httpapi_test

import (
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestApprovalAuditOverHTTP(t *testing.T) {
	a := newAPI(t)
	admin := a.admin("ana@example.com")
	mod := a.moderator(admin, "mia@example.com")
	c1 := a.curator(admin, "c1@example.com", "mae-pai")
	c2 := a.curator(admin, "c2@example.com", "pedagogo")
	v := a.suggest(a.familyOwner("gui@example.com"), ytID)
	reviews := "/v1/curation/videos/" + v.ID + "/reviews"
	a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c1)...)
	if r := a.do(http.MethodPost, reviews, approval("bichos", "5-8"), bearer(c2)...); !strings.Contains(r.Body.String(), `"video_state":"approved"`) {
		t.Fatalf("publish: %d %s", r.Code, r.Body)
	}

	var sample struct {
		Videos []struct {
			Video     videoResp `json:"video"`
			Round     int       `json:"round"`
			Approvals []struct {
				DisplayRole string            `json:"display_role"`
				Decision    string            `json:"decision"`
				Answers     map[string]string `json:"answers"`
			} `json:"approvals"`
		} `json:"videos"`
	}
	r := a.do(http.MethodGet, "/v1/moderation/audit-sample", nil, bearer(mod)...)
	getJSON(t, r, &sample)
	if len(sample.Videos) != 1 || sample.Videos[0].Video.ID != v.ID || sample.Videos[0].Round != 1 || len(sample.Videos[0].Approvals) != 2 {
		t.Fatalf("sample %+v", sample)
	}
	var roles []string
	for _, x := range sample.Videos[0].Approvals {
		if x.Decision != "approve" || len(x.Answers) != 25 {
			t.Errorf("approval %+v", x)
		}
		roles = append(roles, x.DisplayRole)
	}
	if slices.Sort(roles); !slices.Equal(roles, []string{"mae-pai", "pedagogo"}) {
		t.Fatalf("roles %v", roles)
	}
	if strings.Contains(r.Body.String(), a.accountID(c1)) || strings.Contains(r.Body.String(), "c1@example.com") {
		t.Fatal("the sample names a curator")
	}

	audits := "/v1/moderation/audits"
	if r := a.do(http.MethodPost, audits, map[string]any{"video_id": v.ID, "round": 1, "verdict": "disagree"}, bearer(mod)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "reason_required" {
		t.Fatalf("no reason: %d %q", r.Code, r.problemCode())
	}
	hold := map[string]any{"video_id": v.ID, "round": 1, "verdict": "disagree", "reason": "Tem publi no fim.", "hold": true}
	if r := a.do(http.MethodPost, audits, hold, bearer(mod)...); r.Code != http.StatusNoContent {
		t.Fatalf("audit: %d %s", r.Code, r.Body)
	}
	if n := a.count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND state = 'held' AND held_reason = 'audit'`, v.ID); n != 1 {
		t.Fatal("the video was not held")
	}
	if r := a.do(http.MethodPost, audits, hold, bearer(mod)...); r.Code != http.StatusConflict || r.problemCode() != "already_audited" {
		t.Fatalf("audit twice: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/moderation/audit-sample", nil, bearer(admin)...); r.Code != http.StatusOK || strings.TrimSpace(r.Body.String()) != `{"videos":[]}` {
		t.Fatalf("empty sample: %d %s", r.Code, r.Body)
	}

	// The audit is a write and needs a fresh re-authentication; the sample
	// is a read and does not.
	a.now = a.now.Add(6 * time.Minute)
	late := a.refresh(mod)
	if r := a.do(http.MethodPost, audits, map[string]any{"video_id": v.ID, "round": 1, "verdict": "agree"}, bearer(late)...); r.Code != http.StatusForbidden || r.problemCode() != "reauth_required" {
		t.Fatalf("a stale re-auth: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodGet, "/v1/moderation/audit-sample", nil, bearer(late)...); r.Code != http.StatusOK {
		t.Fatalf("sample with a stale re-auth: %d", r.Code)
	}
}
