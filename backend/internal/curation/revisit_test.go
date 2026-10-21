package curation_test

import (
	"errors"
	"maps"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestRevisitFallsDue(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	c3 := f.curator("c3@example.com", curation.Cuidador)
	v := f.video(ytID)
	f.review(c1, v, approve("bichos", family.Age5To8))
	f.review(c2, v, approve("bichos", family.Age5To8))
	published := f.now
	if d := f.detail(v).Video; d.Round != 2 || d.PublishedRound == nil || *d.PublishedRound != 1 {
		t.Fatalf("after round 1: %+v", d)
	}

	f.now = published.Add(180*24*time.Hour - time.Second)
	if items := f.queue(c3); len(items) != 0 {
		t.Fatalf("queued before its revisit: %+v", items)
	}
	if _, _, err := f.svc.Review(ctx, c3, v, approve("bichos", family.Age5To8)); !errors.Is(err, curation.ErrNotReviewable) {
		t.Fatalf("a review before the revisit: %v", err)
	}

	f.now = published.Add(180 * 24 * time.Hour)
	items := f.queue(c1) // c1 reviewed round 1, not round 2
	if len(items) != 1 || items[0].Video.ID != v || !items[0].Revisit || items[0].Video.Round != 2 {
		t.Fatalf("revisit queue %+v", items)
	}
	if state := f.review(c1, v, approve("natureza", family.AgeUpTo4)); state != curation.Approved {
		t.Fatalf("the video left the catalogue during its revisit: %s", state)
	}
	mid := f.detail(v)
	if mid.Video.State != curation.Approved || mid.Video.Round != 2 || *mid.Video.PublishedRound != 1 ||
		mid.Video.Theme != "bichos" || !mid.Video.LastReviewedAt.Equal(published) {
		t.Fatalf("a partial revisit changed the video: %+v", mid.Video)
	}
	if p := mid.Provenance; p == nil || p.Approvals[curation.MaePai] != 1 || p.Approvals[curation.Pedagogo] != 1 ||
		!p.LastReviewedAt.Equal(published) {
		t.Fatalf("provenance must stay round 1's until round 2 completes: %+v", mid.Provenance)
	}
	if f.audited(audit.VideoPublished) != 1 {
		t.Fatalf("a partial revisit published: %d", f.audited(audit.VideoPublished))
	}

	if state := f.review(c3, v, approve("natureza", family.Age5To8)); state != curation.Approved {
		t.Fatalf("revisit completed: %s", state)
	}
	got := f.detail(v)
	if got.Video.Round != 3 || got.Video.PublishedRound == nil || *got.Video.PublishedRound != 2 ||
		got.Video.Theme != "natureza" || got.Video.MinAgeBand != family.Age5To8 ||
		!got.Video.LastReviewedAt.Equal(f.now) || !got.Video.ReviewDueAt.Equal(f.now.Add(180*24*time.Hour)) {
		t.Fatalf("renewed %+v", got.Video)
	}
	if want := map[curation.DisplayRole]int{curation.MaePai: 1, curation.Cuidador: 1}; !maps.Equal(got.Provenance.Approvals, want) ||
		!got.Provenance.LastReviewedAt.Equal(f.now) {
		t.Fatalf("provenance %+v", got.Provenance)
	}
	if f.audited(audit.VideoPublished) != 2 {
		t.Fatalf("video_published recorded %d times, want 2", f.audited(audit.VideoPublished))
	}
}

func TestRevisitRejectionHolds(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.Psicologo)
	v := f.approvedVideo(ytID, f.now.Add(-time.Hour))

	if state := f.review(c, v, reject("O canal mudou de dono.")); state != curation.Held {
		t.Fatalf("revisit rejection: %s", state)
	}
	if !f.audit.Has(c, audit.VideoHeld) {
		t.Fatal("no video_held audit")
	}
	held, err := f.svc.HeldVideos(ctx)
	if err != nil || len(held) != 1 || held[0].Video.ID != v || held[0].Video.Round != 2 || len(held[0].Rejections) != 1 ||
		held[0].Rejections[0].DisplayRole != curation.Psicologo || held[0].Rejections[0].Reason != c04+"\nO canal mudou de dono." {
		t.Fatalf("held %+v %v", held, err)
	}
}

// Every video in the catalogue is reviewed again under the list: a revisit
// due now keeps the video visible until a review refuses it or doubts it.
func TestARevisitUnderTheChecklistKeepsTheVideoUntilARefusal(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideo(ytID, f.now)
	doubted := f.approvedVideo("doubtedvid1", f.now)

	if items := f.queue(c1); len(items) != 2 || !items[0].Revisit || !items[1].Revisit {
		t.Fatalf("revisit queue %+v", items)
	}
	if !f.shown(lia, v) || !f.shown(lia, doubted) {
		t.Fatal("a video due for its revisit left the catalogue")
	}
	if state := f.review(c1, v, approve("bichos", family.Age5To8)); state != curation.Approved || !f.shown(lia, v) {
		t.Fatalf("an approval in the revisit: %s", state)
	}
	if state := f.review(c2, v, reject("Tem publi no fim.")); state != curation.Held || f.shown(lia, v) {
		t.Fatalf("a refusal in the revisit: %s", state)
	}
	if state := f.review(c1, doubted, approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c19": curation.AnswerDoubt})); state != curation.Held {
		t.Fatalf("a doubt in the revisit: %s", state)
	}
	if _, why := f.state(doubted); why != curation.HeldByDoubt || f.shown(lia, doubted) {
		t.Fatalf("a doubted revisit: %s", why)
	}
}
