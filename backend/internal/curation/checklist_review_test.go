package curation_test

import (
	"errors"
	"maps"
	"slices"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

const c15 = "Pede para comprar, pedir aos pais, comentar para ganhar ou diz preço e loja?"

func TestApprovalStoresEveryAnswer(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	f.now = f.now.Add(time.Minute)
	r, state, err := f.svc.Review(ctx, c, v, approve("bichos", family.Age5To8))
	if err != nil || state != curation.Pending {
		t.Fatalf("approval: %s %v", state, err)
	}
	if r.Decision != curation.Approve || r.ChecklistVersion != "2026-10-20" || !maps.Equal(r.Answers, clean()) ||
		r.FailedItems != nil || r.Reason != "" {
		t.Fatalf("review %+v", r)
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid AND checklist_version = '2026-10-20'
		AND (SELECT count(*) FROM jsonb_object_keys(checklist)) = 25 AND checklist->>'c01' = 'ok'`, v); n != 1 {
		t.Fatal("the answers were not stored")
	}
	d := f.detail(v)
	if len(d.Reviews) != 1 || !maps.Equal(d.Reviews[0].Answers, clean()) || d.Reviews[0].ChecklistVersion != curation.ChecklistVersion {
		t.Fatalf("detail %+v", d.Reviews)
	}
}

func TestChecklistRefusalsStoreNothing(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	outdated := approve("bichos", family.Age5To8)
	outdated.ChecklistVersion = "2026-01-01"
	missing := approve("bichos", family.Age5To8)
	delete(missing.Answers, "c13")
	with := func(band family.AgeBand, changed map[string]curation.Answer) curation.ReviewInput {
		return approveWith("bichos", band, changed)
	}
	appears := curation.AnswerAppears
	for name, tc := range map[string]struct {
		in   curation.ReviewInput
		want error
	}{
		"an old list":                     {outdated, curation.ErrChecklistOutdated},
		"a missing answer":                {missing, curation.ErrValidation},
		"an unknown item":                 {with(family.Age5To8, map[string]curation.Answer{"c99": curation.AnswerOK}), curation.ErrValidation},
		"an answer that refuses":          {with(family.Age5To8, map[string]curation.Answer{"c15": appears}), curation.ErrChecklistRefuses},
		"a positive question answered no": {with(family.Age5To8, map[string]curation.Answer{"c01": appears}), curation.ErrChecklistRefuses},
		"no clear story":                  {with(family.Age5To8, map[string]curation.Answer{"c23": appears}), curation.ErrChecklistRefuses},
		"a fast pace for 2 to 4":          {with(family.AgeUpTo4, map[string]curation.Answer{"c22": appears}), curation.ErrChecklistBand},
		"an invalid reason":               {with(family.Age5To8, map[string]curation.Answer{"c21": appears}), curation.ErrChecklistInvalidReason},
		"a tie to the channel":            {with(family.Age5To8, map[string]curation.Answer{"c25": appears}), curation.ErrConflictOfInterest},
		"a tie and a refusal":             {with(family.Age5To8, map[string]curation.Answer{"c25": appears, "c04": appears}), curation.ErrConflictOfInterest},
	} {
		if _, _, err := f.svc.Review(ctx, c, v, tc.in); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v, want %v", name, err, tc.want)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reviews`); n != 0 {
		t.Fatalf("refused reviews were stored: %d rows", n)
	}
	if got := f.detail(v).Video.State; got != curation.Pending {
		t.Fatalf("state %s", got)
	}
	// A fast pace only rules out the youngest band.
	if state := f.review(c, v, with(family.Age5To8, map[string]curation.Answer{"c22": appears})); state != curation.Pending {
		t.Fatalf("a fast pace for 5 to 8: %s", state)
	}
}

func TestADoubtHoldsTheVideoForAModerator(t *testing.T) {
	for name, changed := range map[string]map[string]curation.Answer{
		"a doubt":                       {"c13": curation.AnswerDoubt},
		"a sad character":               {"c07": curation.AnswerAppears},
		"a channel with other refusals": {"c24": curation.AnswerAppears},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			c := f.curator("c1@example.com", curation.MaePai)
			v := f.video(ytID)
			in := approveWith("bichos", family.Age5To8, changed)
			in.Note = "  Não sei se pode.  "
			f.now = f.now.Add(time.Minute)
			r, state, err := f.svc.Review(ctx, c, v, in)
			if err != nil || state != curation.Held || r.Decision != curation.Doubt || r.Reason != "Não sei se pode." {
				t.Fatalf("doubt: %+v %s %v", r, state, err)
			}
			if st, held := f.state(v); st != "held" || held != curation.HeldByDoubt {
				t.Fatalf("held %s %s", st, held)
			}
			if !f.audit.Has(c, audit.VideoHeld) {
				t.Fatal("no video_held audit")
			}
			list, err := f.svc.HeldVideos(ctx)
			if err != nil || len(list) != 1 || list[0].HeldReason != curation.HeldByDoubt || len(list[0].Rejections) != 0 ||
				len(list[0].Doubts) != 1 || list[0].Doubts[0].Reason != "Não sei se pode." ||
				!maps.Equal(list[0].Doubts[0].Answers, in.Answers) {
				t.Fatalf("held list %+v %v", list, err)
			}
		})
	}
}

func TestARejectionNamesItsItemsAndComposesTheReason(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	in := curation.ReviewInput{Decision: curation.Reject, ChecklistVersion: curation.ChecklistVersion,
		FailedItems: []string{"c15", "c04"}, Note: "  Pede para comprar no fim.  "}
	f.now = f.now.Add(time.Minute)
	r, state, err := f.svc.Review(ctx, c, v, in)
	want := c04 + "\n" + c15 + "\nPede para comprar no fim."
	if err != nil || state != curation.Held || r.Reason != want || !slices.Equal(r.FailedItems, []string{"c04", "c15"}) ||
		r.Answers != nil || r.ChecklistVersion != curation.ChecklistVersion {
		t.Fatalf("rejection %+v %s %v", r, state, err)
	}
	if _, held := f.state(v); held != curation.HeldByReview {
		t.Fatalf("held for %q", held)
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid AND decision = 'reject'
		AND checklist = '["c04", "c15"]'::jsonb AND reason = $2`, v, want); n != 1 {
		t.Fatal("the rejection was not stored with its items")
	}
	// Without a note; a question asked in the positive reads as its "no".
	v2 := f.video("secondvideo")
	if state := f.review(c, v2, curation.ReviewInput{Decision: curation.Reject, ChecklistVersion: curation.ChecklistVersion,
		FailedItems: []string{"c23"}}); state != curation.Held {
		t.Fatalf("rejection without a note: %s", state)
	}
	if got := f.detail(v2).Reviews[0].Reason; got != "Não: Tem começo, meio e fim claros?" {
		t.Fatalf("reason %q", got)
	}
}
