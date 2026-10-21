package curation_test

import (
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// doubted has a new curator answer "doubt" to c13 on a new video, which
// holds it for a moderator, and returns the video.
func (f *fixture) doubted(youtubeID string) string {
	f.t.Helper()
	c := f.curator("d-"+strings.ToLower(youtubeID)+"@example.com", curation.MaePai)
	v := f.video(youtubeID)
	if state := f.review(c, v, approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c13": curation.AnswerDoubt})); state != curation.Held {
		f.t.Fatalf("doubt: %s", state)
	}
	return v
}

// shown reports whether child c's catalogue carries video v.
func (f *fixture) shown(c curation.Child, v string) bool {
	f.t.Helper()
	for _, s := range f.catalog(c) {
		for _, k := range s.Videos {
			if k.ID == v {
				return true
			}
		}
	}
	return false
}

func TestDecideDoubtPublishes(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.doubted(ytID)
	f.now = f.now.Add(time.Hour)
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "  Ninguém se arrisca no vídeo.  "}
	if err := f.svc.DecideDoubt(ctx, m, v, curation.DoubtDecision{Decision: curation.Approve, Theme: "natureza", MinAgeBand: family.AgeUpTo4}); err != nil {
		t.Fatal(err)
	}
	got := f.detail(v).Video
	if got.State != curation.Approved || got.Round != 2 || got.PublishedRound == nil || *got.PublishedRound != 1 ||
		got.Theme != "natureza" || got.MinAgeBand != family.AgeUpTo4 || got.LastReviewedAt == nil || !got.LastReviewedAt.Equal(f.now) ||
		got.ReviewDueAt == nil || !got.ReviewDueAt.Equal(f.now.Add(180*24*time.Hour)) {
		t.Fatalf("published %+v", got)
	}
	if _, held := f.state(v); held != "" {
		t.Fatalf("held reason kept: %q", held)
	}
	want := audit.Action{Actor: mod, ActorRole: "moderator", Event: audit.VideoDoubtDecided, SubjectKind: audit.SubjectVideo,
		SubjectID: v, Reason: "Ninguém se arrisca no vídeo.", Metadata: map[string]string{"decision": "approve"}}
	if a, ok := f.audit.LastAction(audit.VideoDoubtDecided); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
	if !f.shown(lia, v) {
		t.Fatal("the published video is not in the catalogue")
	}
}

func TestDecideDoubtRemoves(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	v := f.doubted(ytID)
	m := curation.Moderation{ActorID: admin, ActorRole: staff.Admin, Reason: "Desafio perigoso."}
	if err := f.svc.DecideDoubt(ctx, m, v, curation.DoubtDecision{Decision: curation.Reject}); err != nil {
		t.Fatal(err)
	}
	if got := f.detail(v).Video.State; got != curation.Removed {
		t.Fatalf("state %s", got)
	}
	if a, _ := f.audit.LastAction(audit.VideoDoubtDecided); a.Actor != admin || a.ActorRole != "admin" ||
		a.Metadata["decision"] != "reject" || a.Reason != "Desafio perigoso." {
		t.Fatalf("action %+v", a)
	}
	f.source.Add(curationtest.Kids(ytID, "Baby Shark"))
	if _, _, err := f.svc.Suggest(ctx, f.account("bia@example.com"), "https://youtu.be/"+ytID); refusal(err) != curation.RefusedRemoved {
		t.Fatalf("suggesting a removed video: %v", err)
	}
}

func TestDecideDoubtOnlyDecidesDoubts(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "Motivo válido."}
	ok := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}
	for name, v := range map[string]string{
		"pending":           f.video("pendingvid1"),
		"held by a refusal": f.heldVideo("refusedvid1"),
		"approved":          f.approvedVideo("approved001", f.now.Add(time.Hour)),
	} {
		if err := f.svc.DecideDoubt(ctx, m, v, ok); !errors.Is(err, curation.ErrStateConflict) {
			t.Errorf("%s: %v", name, err)
		}
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if err := f.svc.DecideDoubt(ctx, m, id, ok); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
	v := f.doubted(ytID)
	for name, tc := range map[string]struct {
		m    curation.Moderation
		d    curation.DoubtDecision
		want error
	}{
		"no reason":              {curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "  "}, ok, staff.ErrReasonRequired},
		"no theme":               {m, curation.DoubtDecision{Decision: curation.Approve, MinAgeBand: family.Age5To8}, curation.ErrValidation},
		"unknown band":           {m, curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: "13-17"}, curation.ErrValidation},
		"a removal with a theme": {m, curation.DoubtDecision{Decision: curation.Reject, Theme: "bichos"}, curation.ErrValidation},
		"no decision":            {m, curation.DoubtDecision{Theme: "bichos", MinAgeBand: family.Age5To8}, curation.ErrValidation},
		"a doubt as a decision":  {m, curation.DoubtDecision{Decision: curation.Doubt}, curation.ErrValidation},
	} {
		if err := f.svc.DecideDoubt(ctx, tc.m, v, tc.d); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if st, held := f.state(v); st != "held" || held != curation.HeldByDoubt {
		t.Fatalf("the doubt moved: %s %s", st, held)
	}
	if n := f.audited(audit.VideoDoubtDecided); n != 0 {
		t.Fatalf("refused decisions were recorded: %d", n)
	}
}

// The moderator sees the reports filed while the video was held, so a
// publication by the moderator restarts the count: only reports after the
// decision can hold the video again.
func TestDecideDoubtRestartsTheReportCount(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	_, owners := f.families(6)
	v := f.doubted(ytID)
	for _, o := range owners[:3] {
		f.report(o, v, curation.ReportOutro, "")
	}
	f.now = f.now.Add(time.Hour)
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "Os avisos não se confirmam."}
	if err := f.svc.DecideDoubt(ctx, m, v, curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}); err != nil {
		t.Fatal(err)
	}
	if st, _ := f.state(v); st != "approved" {
		t.Fatalf("after the decision: %s", st)
	}
	f.report(owners[3], v, curation.ReportOutro, "")
	f.report(owners[4], v, curation.ReportOutro, "")
	if st, _ := f.state(v); st != "approved" {
		t.Fatalf("reports from before the decision still count: %s", st)
	}
	f.report(owners[5], v, curation.ReportOutro, "")
	if st, why := f.state(v); st != "held" || why != curation.HeldByReports {
		t.Fatalf("3 reports since the decision: %s %s", st, why)
	}
}
