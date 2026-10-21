package curation_test

import (
	"encoding/json"
	"errors"
	"maps"
	"reflect"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// publishedAt inserts an approved video published in round 1 at at, whose
// round holds one pedagogo approval with every answer "ok".
func (f *fixture) publishedAt(youtubeID string, at time.Time) string {
	f.t.Helper()
	id := f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round, published_round,
		theme, min_age_band, last_reviewed_at, review_due_at, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'approved', 2, 1, 'bichos', '5-8', $2, $3, $2, $2) RETURNING id::text`,
		youtubeID, at, at.Add(180*24*time.Hour))
	answers, err := json.Marshal(clean())
	if err != nil {
		f.t.Fatal(err)
	}
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reviewed_at,
		checklist_version, checklist) VALUES ($1::uuid, 1, NULL, 'pedagogo', 'approve', 'bichos', '5-8', $2, $3, $4::text::jsonb)`,
		id, at, curation.ChecklistVersion, string(answers))
	return id
}

func TestAuditSample(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	recent := map[string]bool{}
	for i := range 12 {
		recent[f.publishedAt(nthID(i), f.now.Add(-time.Duration(i)*24*time.Hour))] = true
	}
	f.publishedAt(nthID(20), f.now.Add(-31*24*time.Hour)) // too old
	audited := f.publishedAt(nthID(21), f.now.Add(-time.Hour))
	f.exec(`INSERT INTO approval_audits (video_id, round, auditor_id, verdict, audited_at) VALUES ($1::uuid, 1, $2::uuid, 'agree', $3)`,
		audited, mod, f.now)
	held := f.publishedAt(nthID(22), f.now.Add(-time.Hour))
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'reports' WHERE id = $1::uuid`, held)
	f.video(nthID(23)) // never published

	sample, err := f.svc.AuditSample(ctx)
	if err != nil || len(sample) != 10 {
		t.Fatalf("sample of %d: %v", len(sample), err)
	}
	seen := map[string]bool{}
	for _, c := range sample {
		if !recent[c.Video.ID] || seen[c.Video.ID] {
			t.Errorf("sampled %s", c.Video.ID)
		}
		seen[c.Video.ID] = true
		if c.Round != 1 || len(c.Approvals) != 1 || c.Approvals[0].DisplayRole != curation.Pedagogo ||
			!maps.Equal(c.Approvals[0].Answers, clean()) {
			t.Errorf("candidate %+v", c)
		}
	}
}

func TestAuditApproval(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	m := func(reason string) curation.Moderation {
		return curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: reason}
	}
	agreed := f.publishedAt(nthID(1), f.now.Add(-time.Hour))
	in := curation.AuditInput{VideoID: agreed, Round: 1, Verdict: curation.Agree}
	if err := f.svc.AuditApproval(ctx, m(""), in); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.AuditApproval(ctx, m(""), in); !errors.Is(err, curation.ErrAlreadyAudited) {
		t.Fatalf("a second audit: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM approval_audits WHERE video_id = $1::uuid AND round = 1 AND verdict = 'agree'
		AND auditor_id = $2::uuid AND reason IS NULL AND audited_at = $3`, agreed, mod, f.now); n != 1 {
		t.Fatal("the agreement was not stored")
	}
	sample, err := f.svc.AuditSample(ctx)
	if err != nil || len(sample) != 0 {
		t.Fatalf("an audited round was sampled again: %+v %v", sample, err)
	}

	disputed := f.publishedAt(nthID(2), f.now.Add(-time.Hour))
	for name, tc := range map[string]struct {
		reason string
		in     curation.AuditInput
		want   error
	}{
		"a disagreement without a reason": {"  ", curation.AuditInput{VideoID: disputed, Round: 1, Verdict: curation.Disagree}, staff.ErrReasonRequired},
		"a hold on an agreement":          {"", curation.AuditInput{VideoID: disputed, Round: 1, Verdict: curation.Agree, Hold: true}, curation.ErrValidation},
		"an unknown verdict":              {"", curation.AuditInput{VideoID: disputed, Round: 1, Verdict: "maybe"}, curation.ErrValidation},
		"another round":                   {"Motivo válido.", curation.AuditInput{VideoID: disputed, Round: 2, Verdict: curation.Disagree}, curation.ErrStateConflict},
		"an unknown video":                {"Motivo válido.", curation.AuditInput{VideoID: "00000000-0000-0000-0000-000000000000", Round: 1, Verdict: curation.Disagree}, curation.ErrNotFound},
		"a malformed id":                  {"Motivo válido.", curation.AuditInput{VideoID: "abc", Round: 1, Verdict: curation.Disagree}, curation.ErrNotFound},
	} {
		if err := f.svc.AuditApproval(ctx, m(tc.reason), tc.in); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM approval_audits WHERE video_id = $1::uuid`, disputed); n != 0 {
		t.Fatalf("refused audits were stored: %d", n)
	}

	if err := f.svc.AuditApproval(ctx, m("  Tem publi no fim.  "), curation.AuditInput{VideoID: disputed, Round: 1,
		Verdict: curation.Disagree, Hold: true}); err != nil {
		t.Fatal(err)
	}
	if st, why := f.state(disputed); st != "held" || why != curation.HeldByAudit {
		t.Fatalf("held %s %s", st, why)
	}
	want := audit.Action{Actor: mod, ActorRole: "moderator", Event: audit.ApprovalAudited, SubjectKind: audit.SubjectVideo,
		SubjectID: disputed, Reason: "Tem publi no fim.", Metadata: map[string]string{"verdict": "disagree", "round": "1", "held": "true"}}
	if a, ok := f.audit.LastAction(audit.ApprovalAudited); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
	if !f.audit.Has(mod, audit.VideoHeld) {
		t.Fatal("no video_held audit")
	}

	// A disagreement without a hold leaves the video in the catalogue.
	kept := f.publishedAt(nthID(3), f.now.Add(-time.Hour))
	if err := f.svc.AuditApproval(ctx, m("Faixa errada."), curation.AuditInput{VideoID: kept, Round: 1, Verdict: curation.Disagree}); err != nil {
		t.Fatal(err)
	}
	if st, _ := f.state(kept); st != "approved" {
		t.Fatalf("kept %s", st)
	}
	// A video held meanwhile stays held as it was.
	gone := f.publishedAt(nthID(4), f.now.Add(-time.Hour))
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'reports' WHERE id = $1::uuid`, gone)
	if err := f.svc.AuditApproval(ctx, m("Tem publi."), curation.AuditInput{VideoID: gone, Round: 1, Verdict: curation.Disagree, Hold: true}); err != nil {
		t.Fatal(err)
	}
	if _, why := f.state(gone); why != curation.HeldByReports {
		t.Fatalf("held reason %s", why)
	}
	if a, _ := f.audit.LastAction(audit.ApprovalAudited); a.Metadata["held"] != "false" {
		t.Fatalf("action %+v", a)
	}
}
