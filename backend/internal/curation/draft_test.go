package curation_test

import (
	"errors"
	"maps"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// saveDraft saves curatorID's draft of videoID; it must succeed.
func (f *fixture) saveDraft(curatorID, videoID string, in curation.DraftInput) curation.Draft {
	f.t.Helper()
	d, err := f.svc.SaveDraft(ctx, curatorID, videoID, in)
	if err != nil {
		f.t.Fatalf("save draft: %v", err)
	}
	return d
}

func (f *fixture) draft(curatorID, videoID string) *curation.Draft {
	f.t.Helper()
	d, err := f.svc.Draft(ctx, curatorID, videoID)
	if err != nil {
		f.t.Fatalf("draft: %v", err)
	}
	return d
}

func (f *fixture) drafts(videoID string) int {
	f.t.Helper()
	return f.count(`SELECT count(*) FROM review_drafts WHERE video_id = $1::uuid`, videoID)
}

// someAnswers is a draft that answered two questions.
func someAnswers() curation.DraftInput {
	return curation.DraftInput{ChecklistVersion: curation.ChecklistVersion,
		Answers: map[string]curation.Answer{"c25": curation.AnswerOK, "c04": curation.AnswerOK}}
}

func TestADraftKeepsWhereTheReviewerStopped(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	other := f.curator("c2@example.com", curation.Pedagogo)
	v := f.video(ytID)
	began := f.now
	answers := map[string]curation.Answer{"c25": curation.AnswerOK, "c04": curation.AnswerAppears}
	f.saveDraft(c, v, curation.DraftInput{ChecklistVersion: curation.ChecklistVersion, Answers: answers,
		Theme: "bichos", MinAgeBand: family.Age5To8, Note: "  Vi até 2 min.  "})
	d := f.draft(c, v)
	if d == nil || !maps.Equal(d.Answers, answers) || d.Theme != "bichos" || d.MinAgeBand != family.Age5To8 ||
		d.Note != "Vi até 2 min." || !d.BeganAt.Equal(began) || d.PlayedToEndAt != nil ||
		d.ChecklistVersion != curation.ChecklistVersion {
		t.Fatalf("draft %+v", d)
	}

	f.now = f.now.Add(time.Hour)
	again := map[string]curation.Answer{"c03": curation.AnswerDoubt}
	f.saveDraft(c, v, curation.DraftInput{ChecklistVersion: curation.ChecklistVersion, Answers: again})
	d = f.draft(c, v)
	if d == nil || !maps.Equal(d.Answers, again) || d.Theme != "" || d.MinAgeBand != "" || d.Note != "" || !d.BeganAt.Equal(began) {
		t.Fatalf("second save %+v", d)
	}
	if d := f.draft(other, v); d != nil {
		t.Fatalf("another curator's draft: %+v", d)
	}
}

func TestSavingADraftKeepsThePlayersEnd(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	t0 := f.now
	d, err := f.svc.DraftEnded(ctx, c, v)
	if err != nil || d.PlayedToEndAt == nil || !d.PlayedToEndAt.Equal(t0) || !d.BeganAt.Equal(t0) || d.Answers == nil || len(d.Answers) != 0 {
		t.Fatalf("ended %+v %v", d, err)
	}
	f.now = f.now.Add(time.Minute)
	if d := f.saveDraft(c, v, someAnswers()); d.PlayedToEndAt == nil || !d.PlayedToEndAt.Equal(t0) {
		t.Fatalf("save after the end %+v", d)
	}
	f.now = f.now.Add(time.Minute)
	if d, err := f.svc.DraftEnded(ctx, c, v); err != nil || d.PlayedToEndAt == nil || !d.PlayedToEndAt.Equal(t0) ||
		!maps.Equal(d.Answers, someAnswers().Answers) {
		t.Fatalf("ended again %+v %v", d, err)
	}
	if d := f.draft(c, v); d == nil || !d.PlayedToEndAt.Equal(t0) || !d.BeganAt.Equal(t0) {
		t.Fatalf("read %+v", d)
	}
}

func TestADraftUnderAFormerListKeepsOnlyUnchangedAnswers(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	began := f.now
	f.saveDraft(c, v, curation.DraftInput{ChecklistVersion: curation.ChecklistVersion,
		Answers: map[string]curation.Answer{"c04": curation.AnswerOK, "c07": curation.AnswerOK}})
	f.now = f.now.Add(time.Minute)
	ended, err := f.svc.DraftEnded(ctx, c, v)
	if err != nil {
		t.Fatal(err)
	}
	f.exec(`UPDATE review_drafts SET checklist_version = '2026-11-11',
		questions = jsonb_set(questions, '{c07}', '"Algum personagem fica triste como tema da história?"')
			|| '{"c01": "Uma pergunta que saiu da lista?"}',
		answers = answers || '{"c01": "ok"}'`)
	d := f.draft(c, v)
	if d == nil || !maps.Equal(d.Answers, map[string]curation.Answer{"c04": curation.AnswerOK}) ||
		d.ChecklistVersion != curation.ChecklistVersion || !d.BeganAt.Equal(began) ||
		d.PlayedToEndAt == nil || !d.PlayedToEndAt.Equal(*ended.PlayedToEndAt) {
		t.Fatalf("draft %+v", d)
	}
}

func TestADraftIsRefusedWhereAReviewWouldBe(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	own := f.video(ytID)
	f.suggestedBy(c, own)
	reviewed := f.video("bbbbbbbbbbb")
	f.review(c, reviewed, approve("bichos", family.Age5To8))
	held := f.heldVideo("ccccccccccc")
	for _, x := range []struct {
		name, video string
		want        error
	}{
		{"own suggestion", own, curation.ErrOwnSuggestion},
		{"already reviewed", reviewed, curation.ErrAlreadyReviewed},
		{"held", held, curation.ErrNotReviewable},
		{"unknown", "00000000-0000-0000-0000-000000000000", curation.ErrNotFound},
		{"malformed", "abc", curation.ErrNotFound},
	} {
		if _, err := f.svc.SaveDraft(ctx, c, x.video, someAnswers()); !errors.Is(err, x.want) {
			t.Errorf("save, %s: %v", x.name, err)
		}
		if _, err := f.svc.DraftEnded(ctx, c, x.video); !errors.Is(err, x.want) {
			t.Errorf("ended, %s: %v", x.name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM review_drafts`); n != 0 {
		t.Fatalf("%d drafts stored", n)
	}

	v := f.video("ddddddddddd")
	outdated := someAnswers()
	outdated.ChecklistVersion = "2026-11-11"
	if _, err := f.svc.SaveDraft(ctx, c, v, outdated); !errors.Is(err, curation.ErrChecklistOutdated) {
		t.Errorf("former list: %v", err)
	}
	for name, in := range map[string]curation.DraftInput{
		"unknown question": {ChecklistVersion: curation.ChecklistVersion, Answers: map[string]curation.Answer{"c99": curation.AnswerOK}},
		"unknown answer":   {ChecklistVersion: curation.ChecklistVersion, Answers: map[string]curation.Answer{"c04": "maybe"}},
		"long note":        {Note: strings.Repeat("a", 501)},
		"unknown theme":    {Theme: "x"},
		"unknown band":     {MinAgeBand: "3-5"},
	} {
		if _, err := f.svc.SaveDraft(ctx, c, v, in); !errors.Is(err, curation.ErrValidation) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM review_drafts`); n != 0 {
		t.Fatalf("%d drafts stored", n)
	}
	if d := f.saveDraft(c, v, curation.DraftInput{Note: strings.Repeat("a", 500)}); len(d.Note) != 500 || d.Answers == nil {
		t.Fatalf("a 500-rune note: %+v", d)
	}
}

func TestADraftSaveAfterTheReviewIsRefused(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	f.review(c, v, reject("Não."))
	if _, err := f.svc.SaveDraft(ctx, c, v, someAnswers()); !errors.Is(err, curation.ErrNotReviewable) && !errors.Is(err, curation.ErrAlreadyReviewed) {
		t.Fatalf("save after the review: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM review_drafts`); n != 0 {
		t.Fatalf("%d drafts stored", n)
	}
}

func TestADraftGoesWithTheRoleAndWhenTheRoundCloses(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	c3 := f.curator("c3@example.com", curation.Cuidador)
	mod := f.account("mia@example.com")
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "Motivo válido."}

	v := f.video(ytID)
	f.saveDraft(c1, v, someAnswers())
	f.saveDraft(c2, v, someAnswers())
	f.exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid AND role = 'curator'`, c1)
	if f.count(`SELECT count(*) FROM review_drafts WHERE curator_id = $1::uuid`, c1) != 0 || f.draft(c2, v) == nil {
		t.Fatal("losing the role keeps the draft, or takes another's")
	}

	// A doubt holds the video for a moderator: the drafts wait with it, and
	// go once the doubt is decided either way.
	for i, decision := range []curation.DoubtDecision{
		{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8},
		{Decision: curation.Reject},
	} {
		v := f.video(nthID(i))
		f.saveDraft(c2, v, someAnswers())
		f.review(c3, v, approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c13": curation.AnswerDoubt}))
		if f.drafts(v) != 1 {
			t.Fatalf("%s: a held video lost its drafts", decision.Decision)
		}
		if err := f.svc.DecideDoubt(ctx, m, v, decision); err != nil {
			t.Fatal(err)
		}
		if n := f.drafts(v); n != 0 {
			t.Errorf("%s: %d drafts after the doubt was decided", decision.Decision, n)
		}
	}

	// The last approval publishes the video and moves its round on.
	published := f.video("eeeeeeeeeee")
	f.saveDraft(c2, published, someAnswers())
	f.review(c3, published, approve("bichos", family.Age5To8))
	if f.drafts(published) != 1 {
		t.Fatal("an approval short of publishing took the drafts")
	}
	c4 := f.curator("c4@example.com", curation.MaePai)
	if state := f.review(c4, published, approve("bichos", family.Age5To8)); state != curation.Approved {
		t.Fatalf("state %s", state)
	}
	if n := f.drafts(published); n != 0 {
		t.Errorf("%d drafts after publishing", n)
	}

	// A moderator's removal and reopen of a held video end its round too.
	for i, name := range []string{"remove", "reopen"} {
		act := f.svc.ModerateRemove
		if name == "reopen" {
			act = f.svc.ModerateReopen
		}
		v := f.video(nthID(10 + i))
		f.saveDraft(c2, v, someAnswers())
		f.review(c3, v, reject("Não."))
		if f.drafts(v) != 1 {
			t.Fatalf("%s: a held video lost its drafts", name)
		}
		if err := act(ctx, m, v); err != nil {
			t.Fatal(err)
		}
		if n := f.drafts(v); n != 0 {
			t.Errorf("%s: %d drafts after it", name, n)
		}
	}
}
