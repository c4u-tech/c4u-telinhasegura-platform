package curation_test

import (
	"encoding/json"
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
	f.moderatorWatched(m, v)
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
	f.moderatorWatched(m, v)
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

// No one settles a doubt in a round they reviewed: not the curator who
// doubted, nor one who approved beside them.
func TestNoOneDecidesADoubtInTheirOwnRound(t *testing.T) {
	f := newFixture(t)
	doubter := f.curator("c1@example.com", curation.MaePai)
	approver := f.curator("c2@example.com", curation.Pedagogo)
	v := f.video(ytID)
	f.review(approver, v, approve("bichos", family.Age5To8))
	if state := f.review(doubter, v, approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c13": curation.AnswerDoubt})); state != curation.Held {
		t.Fatalf("doubt: %s", state)
	}
	publish := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}
	for _, who := range []string{doubter, approver} {
		m := curation.Moderation{ActorID: who, ActorRole: staff.Moderator, Reason: "Motivo válido."}
		f.moderatorWatched(m, v)
		for _, d := range []curation.DoubtDecision{publish, {Decision: curation.Reject}} {
			if err := f.svc.DecideDoubt(ctx, m, v, d); !errors.Is(err, curation.ErrOwnReview) {
				t.Errorf("deciding an own round: %v", err)
			}
		}
	}
	if st, why := f.state(v); st != "held" || why != curation.HeldByDoubt || f.audited(audit.VideoDoubtDecided) != 0 {
		t.Fatalf("the doubt moved: %s %s", st, why)
	}
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Motivo válido."}
	f.moderatorWatched(m, v)
	if err := f.svc.DecideDoubt(ctx, m, v, publish); err != nil {
		t.Fatal(err)
	}
}

// A doubt raised in a revisit is a doubt about that round: publishing it
// makes the revisit round the one that published the video.
func TestDecideDoubtRaisedInARevisit(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideo(ytID, f.now)
	if state := f.review(c, v, approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c19": curation.AnswerDoubt})); state != curation.Held {
		t.Fatalf("a doubt in the revisit: %s", state)
	}
	f.now = f.now.Add(time.Hour)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Sem risco no vídeo."}
	f.moderatorWatched(m, v)
	if err := f.svc.DecideDoubt(ctx, m, v, curation.DoubtDecision{Decision: curation.Approve, Theme: "musica", MinAgeBand: family.AgeUpTo4}); err != nil {
		t.Fatal(err)
	}
	got := f.detail(v).Video
	if got.State != curation.Approved || got.Round != 3 || got.PublishedRound == nil || *got.PublishedRound != 2 ||
		got.Theme != "musica" || got.MinAgeBand != family.AgeUpTo4 || !got.LastReviewedAt.Equal(f.now) {
		t.Fatalf("published %+v", got)
	}
}

// A moderator cannot place in the youngest band a video the curators could
// not: one longer than its ceiling, or one a reviewer of the round found
// fast-paced. The next band up takes it.
// The youngest band takes a video of up to 60 minutes, that one included.
func TestDecideDoubtGivesASixtyMinuteVideoTheYoungestBand(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	v := f.doubted(ytID)
	f.exec(`UPDATE videos SET duration_seconds = $2 WHERE id = $1::uuid`, v, int((60 * time.Minute).Seconds()))
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "Motivo válido."}
	f.moderatorWatched(m, v)
	young := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.AgeUpTo4}
	if err := f.svc.DecideDoubt(ctx, m, v, young); err != nil {
		t.Fatalf("2 to 4: %v", err)
	}
	if got := f.detail(v).Video; got.State != curation.Approved || got.MinAgeBand != family.AgeUpTo4 {
		t.Fatalf("published %+v", got)
	}
}

func TestDecideDoubtKeepsALongOrFastVideoFromTheYoungestBand(t *testing.T) {
	for name, held := range map[string]func(f *fixture) string{
		"over 60 minutes": func(f *fixture) string {
			v := f.doubted(ytID)
			f.exec(`UPDATE videos SET duration_seconds = $2 WHERE id = $1::uuid`, v, int((61 * time.Minute).Seconds()))
			return v
		},
		"a fast pace": func(f *fixture) string {
			c := f.curator("d@example.com", curation.MaePai)
			v := f.video(ytID)
			in := approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c13": curation.AnswerDoubt, "c22": curation.AnswerAppears})
			if state := f.review(c, v, in); state != curation.Held {
				f.t.Fatalf("doubt: %s", state)
			}
			return v
		},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			mod := f.account("mia@example.com")
			v := held(f)
			m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "Motivo válido."}
			f.moderatorWatched(m, v)
			young := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.AgeUpTo4}
			if err := f.svc.DecideDoubt(ctx, m, v, young); !errors.Is(err, curation.ErrChecklistBand) {
				t.Fatalf("2 to 4: %v", err)
			}
			if st, reason := f.state(v); st != "held" || reason != curation.HeldByDoubt {
				t.Fatalf("the refusal moved the video: %s %s", st, reason)
			}
			if n := f.audited(audit.VideoDoubtDecided); n != 0 {
				t.Fatalf("a refused decision was recorded: %d", n)
			}
			young.MinAgeBand = family.Age5To8
			if err := f.svc.DecideDoubt(ctx, m, v, young); err != nil {
				t.Fatalf("5 to 8: %v", err)
			}
			if got := f.detail(v).Video; got.State != curation.Approved || got.MinAgeBand != family.Age5To8 {
				t.Fatalf("published %+v", got)
			}
		})
	}
}

// A moderator is held to the band the round's answers allow, whichever
// band that is.
func TestDecideDoubtRefusesABandYoungerThanTheRoundsAnswers(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	c := f.curator("d@example.com", curation.MaePai)
	v := f.video(ytID)
	if state := f.review(c, v, approveWith("", "", map[string]curation.Answer{"c13": curation.AnswerDoubt, "c35": curation.AnswerAppears})); state != curation.Held {
		t.Fatalf("doubt: %s", state)
	}
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "Motivo válido."}
	f.moderatorWatched(m, v)
	d := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}
	if err := f.svc.DecideDoubt(ctx, m, v, d); !errors.Is(err, curation.ErrChecklistBand) {
		t.Fatalf("5 to 8: %v", err)
	}
	if st, why := f.state(v); st != "held" || why != curation.HeldByDoubt || f.audited(audit.VideoDoubtDecided) != 0 {
		t.Fatalf("the refusal moved the video: %s %s", st, why)
	}
	d.MinAgeBand = family.Age9To12
	if err := f.svc.DecideDoubt(ctx, m, v, d); err != nil {
		t.Fatalf("9 to 12: %v", err)
	}
	if got := f.detail(v).Video; got.State != curation.Approved || got.MinAgeBand != family.Age9To12 {
		t.Fatalf("published %+v", got)
	}
}

// heldDoubt inserts a video held by a doubt stored under list version with
// answers, as a review from before the current list would be.
func (f *fixture) heldDoubt(youtubeID, version string, answers map[string]string) string {
	f.t.Helper()
	v := f.video(youtubeID)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'doubt' WHERE id = $1::uuid`, v)
	list, err := json.Marshal(answers)
	if err != nil {
		f.t.Fatal(err)
	}
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, reason, reviewed_at,
		checklist_version, checklist) VALUES ($1::uuid, 1, NULL, 'pedagogo', 'doubt', 'Não sei.', $2, $3, $4::text::jsonb)`,
		v, f.now, version, string(list))
	return v
}

func TestDecideDoubtReadsEachReviewUnderItsOwnList(t *testing.T) {
	f := newFixture(t)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Motivo válido."}
	young := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.AgeUpTo4}
	// c35 was not a band question under that list: only the pace counts.
	v := f.heldDoubt(ytID, "2026-11-11", map[string]string{"c22": "appears", "c35": "appears"})
	f.moderatorWatched(m, v)
	if err := f.svc.DecideDoubt(ctx, m, v, young); !errors.Is(err, curation.ErrChecklistBand) {
		t.Fatalf("2 to 4: %v", err)
	}
	five := young
	five.MinAgeBand = family.Age5To8
	if err := f.svc.DecideDoubt(ctx, m, v, five); err != nil {
		t.Fatalf("5 to 8: %v", err)
	}
	if got := f.detail(v).Video; got.State != curation.Approved || got.MinAgeBand != family.Age5To8 {
		t.Fatalf("published %+v", got)
	}
	first := f.heldDoubt("firstlist01", "2026-10-20", map[string]string{"c01": "ok", "c22": "appears"})
	f.moderatorWatched(m, first)
	if err := f.svc.DecideDoubt(ctx, m, first, young); !errors.Is(err, curation.ErrChecklistBand) {
		t.Fatalf("2 to 4 under the first list: %v", err)
	}
	// Under a former list too, not knowing the pace bars as a fast one.
	unsure := f.heldDoubt("unsurepace1", "2026-11-11", map[string]string{"c22": "doubt"})
	f.moderatorWatched(m, unsure)
	if err := f.svc.DecideDoubt(ctx, m, unsure, young); !errors.Is(err, curation.ErrChecklistBand) {
		t.Fatalf("2 to 4 over an unsure pace: %v", err)
	}
}

// The moderator is held to the band an unsure band answer bars, as the
// curator was.
func TestDecideDoubtRefusesABandAnUnsureAnswerBars(t *testing.T) {
	f := newFixture(t)
	c := f.curator("d@example.com", curation.MaePai)
	v := f.video(ytID)
	if state := f.review(c, v, approveWith("", "", map[string]curation.Answer{"c35": curation.AnswerDoubt})); state != curation.Held {
		t.Fatalf("doubt: %s", state)
	}
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Motivo válido."}
	f.moderatorWatched(m, v)
	d := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}
	if err := f.svc.DecideDoubt(ctx, m, v, d); !errors.Is(err, curation.ErrChecklistBand) {
		t.Fatalf("5 to 8: %v", err)
	}
	d.MinAgeBand = family.Age9To12
	if err := f.svc.DecideDoubt(ctx, m, v, d); err != nil {
		t.Fatalf("9 to 12: %v", err)
	}
	if got := f.detail(v).Video; got.State != curation.Approved || got.MinAgeBand != family.Age9To12 {
		t.Fatalf("published %+v", got)
	}
}

func TestDecideDoubtRefusesToReadAnUnknownList(t *testing.T) {
	f := newFixture(t)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Motivo válido."}
	young := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.AgeUpTo4}
	v := f.heldDoubt(ytID, "2099-01-01", map[string]string{"c22": "appears"})
	f.moderatorWatched(m, v)
	// The held list still loads, with no band for that video.
	held, err := f.svc.HeldVideos(ctx)
	if err != nil || len(held) != 1 || held[0].Video.ID != v || held[0].ComputedBand != "" {
		t.Fatalf("held %+v %v", held, err)
	}
	if err := f.svc.DecideDoubt(ctx, m, v, young); err == nil || errors.Is(err, curation.ErrChecklistBand) {
		t.Fatalf("decided under an unknown list: %v", err)
	}
	if st, why := f.state(v); st != "held" || why != curation.HeldByDoubt || f.audited(audit.VideoDoubtDecided) != 0 {
		t.Fatalf("the refusal moved the video: %s %s", st, why)
	}
	// A review stored before there was any list bars nothing.
	before := f.heldDoubt("beforelist1", "", map[string]string{"c22": "appears"})
	f.moderatorWatched(m, before)
	if err := f.svc.DecideDoubt(ctx, m, before, young); err != nil {
		t.Fatalf("before any list: %v", err)
	}
}
