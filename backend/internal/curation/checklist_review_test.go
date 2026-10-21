package curation_test

import (
	"encoding/json"
	"errors"
	"maps"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

const c15 = "Pede para comprar, pedir aos pais, comentar para ganhar, ou diz preço e loja?"

func TestApprovalStoresEveryAnswer(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	f.now = f.now.Add(time.Minute)
	r, state, err := f.svc.Review(ctx, c, v, approve("bichos", family.Age5To8))
	if err != nil || state != curation.Pending {
		t.Fatalf("approval: %s %v", state, err)
	}
	if r.Decision != curation.Approve || r.ChecklistVersion != "2026-10-21" || !maps.Equal(r.Answers, clean()) ||
		r.FailedItems != nil || r.Reason != "" {
		t.Fatalf("review %+v", r)
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid AND checklist_version = '2026-10-21'
		AND (SELECT count(*) FROM jsonb_object_keys(checklist)) = 23 AND checklist->>'c25' = 'ok'`, v); n != 1 {
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
	former := approve("bichos", family.Age5To8)
	former.ChecklistVersion = "2026-10-20"
	missing := approve("bichos", family.Age5To8)
	delete(missing.Answers, "c13")
	// The version is judged before the shape: an old app hears its list is
	// outdated, even with a note longer than the current one allows.
	outdatedLong := reject(strings.Repeat("a", 501))
	outdatedLong.ChecklistVersion = "2026-01-01"
	outdatedNoDecision := outdated
	outdatedNoDecision.Decision = ""
	with := func(band family.AgeBand, changed map[string]curation.Answer) curation.ReviewInput {
		return approveWith("bichos", band, changed)
	}
	appears := curation.AnswerAppears
	for name, tc := range map[string]struct {
		in   curation.ReviewInput
		want error
	}{
		"an old list":                  {outdated, curation.ErrChecklistOutdated},
		"the former list":              {former, curation.ErrChecklistOutdated},
		"an old list with a long note": {outdatedLong, curation.ErrChecklistOutdated},
		"an old list with no decision": {outdatedNoDecision, curation.ErrValidation},
		"a missing answer":             {missing, curation.ErrValidation},
		"an unknown item":              {with(family.Age5To8, map[string]curation.Answer{"c99": curation.AnswerOK}), curation.ErrValidation},
		"a question the list dropped":  {with(family.Age5To8, map[string]curation.Answer{"c01": curation.AnswerOK}), curation.ErrValidation},
		"a doubt on the tie":           {with(family.Age5To8, map[string]curation.Answer{"c25": curation.AnswerDoubt}), curation.ErrValidation},
		"a doubt on the tie and a Sim": {with(family.Age5To8, map[string]curation.Answer{"c25": curation.AnswerDoubt, "c04": appears}), curation.ErrValidation},
		"an answer that refuses":       {with(family.Age5To8, map[string]curation.Answer{"c15": appears}), curation.ErrChecklistRefuses},
		"no clear story":               {with(family.Age5To8, map[string]curation.Answer{"c23": appears}), curation.ErrChecklistRefuses},
		"a long compilation":           {with(family.Age5To8, map[string]curation.Answer{"c02": appears}), curation.ErrChecklistRefuses},
		"a fast pace for 2 to 4":       {with(family.AgeUpTo4, map[string]curation.Answer{"c22": appears}), curation.ErrChecklistBand},
		"a tie to the channel":         {with(family.Age5To8, map[string]curation.Answer{"c25": appears}), curation.ErrConflictOfInterest},
		"a tie and a refusal":          {with(family.Age5To8, map[string]curation.Answer{"c25": appears, "c04": appears}), curation.ErrConflictOfInterest},
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
	// Without a note, the reason is the questions alone.
	v2 := f.video("secondvideo")
	if state := f.review(c, v2, curation.ReviewInput{Decision: curation.Reject, ChecklistVersion: curation.ChecklistVersion,
		FailedItems: []string{"c23"}}); state != curation.Held {
		t.Fatalf("rejection without a note: %s", state)
	}
	if got := f.detail(v2).Reviews[0].Reason; got != "Falta começo, meio ou fim na história?" {
		t.Fatalf("reason %q", got)
	}
}

// Reviews written under the former list keep their answers and reasons,
// questions since dropped included, and read as they were stored.
func TestReviewsUnderTheFormerListStayReadable(t *testing.T) {
	f := newFixture(t)
	v := f.video(ytID)
	former := map[string]curation.Answer{"c01": curation.AnswerOK, "c21": curation.AnswerOK, "c22": curation.AnswerAppears}
	answers, err := json.Marshal(former)
	if err != nil {
		t.Fatal(err)
	}
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reason,
		reviewed_at, checklist_version, checklist) VALUES
		($1::uuid, 1, NULL, 'pedagogo', 'doubt', 'bichos', '5-8', 'Não sei.', $2, '2026-10-20', $4::text::jsonb),
		($1::uuid, 1, NULL, 'psicologo', 'reject', NULL, NULL, 'Não: Tem começo, meio e fim claros?', $3, '2026-10-20', '["c23"]')`,
		v, f.now, f.now.Add(time.Minute), string(answers))
	d := f.detail(v)
	if len(d.Reviews) != 2 {
		t.Fatalf("reviews %+v", d.Reviews)
	}
	doubt, rejection := d.Reviews[0], d.Reviews[1]
	if doubt.Decision != curation.Doubt || doubt.ChecklistVersion != "2026-10-20" || !maps.Equal(doubt.Answers, former) {
		t.Fatalf("former doubt %+v", doubt)
	}
	if rejection.Reason != "Não: Tem começo, meio e fim claros?" || !slices.Equal(rejection.FailedItems, []string{"c23"}) {
		t.Fatalf("former rejection %+v", rejection)
	}
}

// The flow skips the theme and the band when the answers send the video
// to the team: the moderator who publishes it chooses them.
func TestADoubtMayLeaveTheThemeAndBandToTheModerator(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	doubt := map[string]curation.Answer{"c13": curation.AnswerDoubt}
	for name, tc := range map[string]struct {
		in   curation.ReviewInput
		want error
	}{
		"an approval with neither":  {approve("", ""), curation.ErrValidation},
		"a doubt with a theme only": {approveWith("bichos", "", doubt), curation.ErrValidation},
		"a doubt with a band only":  {approveWith("", family.Age5To8, doubt), curation.ErrValidation},
		"a Sim that refuses":        {approveWith("", "", map[string]curation.Answer{"c04": curation.AnswerAppears}), curation.ErrChecklistRefuses},
	} {
		if _, _, err := f.svc.Review(ctx, c, v, tc.in); !errors.Is(err, tc.want) {
			t.Errorf("%s: %v, want %v", name, err, tc.want)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reviews`); n != 0 {
		t.Fatalf("refused reviews were stored: %d rows", n)
	}
	in := approveWith("", "", map[string]curation.Answer{"c07": curation.AnswerAppears})
	in.Note = "A tristeza é o tema."
	f.now = f.now.Add(time.Minute)
	r, state, err := f.svc.Review(ctx, c, v, in)
	if err != nil || state != curation.Held || r.Decision != curation.Doubt || r.Theme != "" || r.MinAgeBand != "" {
		t.Fatalf("doubt: %+v %s %v", r, state, err)
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid AND decision = 'doubt'
		AND theme IS NULL AND min_age_band IS NULL AND reason = 'A tristeza é o tema.'`, v); n != 1 {
		t.Fatal("the doubt was not stored without a theme and a band")
	}
	list, err := f.svc.HeldVideos(ctx)
	if err != nil || len(list) != 1 || len(list[0].Doubts) != 1 || list[0].Doubts[0].Theme != "" ||
		list[0].Doubts[0].MinAgeBand != "" {
		t.Fatalf("held %+v %v", list, err)
	}
}
