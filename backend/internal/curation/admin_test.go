package curation_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestHeldVideosListTheHeldRoundsRejections(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	v := f.video(ytID)
	f.video("stillpendin")
	f.review(c1, v, approve("bichos", family.Age5To8))
	f.review(c2, v, reject("Assustador para os pequenos."))

	held, err := f.svc.HeldVideos(ctx)
	if err != nil || len(held) != 1 || held[0].Video.ID != v {
		t.Fatalf("held %+v %v", held, err)
	}
	if r := held[0].Rejections; len(r) != 1 || r[0].Decision != curation.Reject || r[0].DisplayRole != curation.Cuidador ||
		r[0].Reason != "Assustador para os pequenos." {
		t.Fatalf("rejections %+v", r)
	}
	f.exec(`UPDATE videos SET state = 'removed'`)
	if held, err := f.svc.HeldVideos(ctx); err != nil || held == nil || len(held) != 0 {
		t.Fatalf("none held: %+v %v", held, err)
	}
}

func TestRemoveAndReopen(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	f.source.Add(curationtest.Kids(ytID, "Baby Shark"))
	v, _, err := f.svc.Suggest(ctx, f.account("gui@example.com"), "https://youtu.be/"+ytID)
	if err != nil {
		t.Fatal(err)
	}
	f.review(c1, v.ID, approve("bichos", family.Age5To8))
	f.review(c2, v.ID, reject("Tem propaganda."))

	if err := f.remove(admin, v.ID); err != nil {
		t.Fatal(err)
	}
	if got := f.detail(v.ID).Video; got.State != curation.Removed || !f.audit.Has(admin, audit.VideoRemoved) {
		t.Fatalf("removed %+v", got)
	}
	if _, _, err := f.svc.Suggest(ctx, f.account("bia@example.com"), "https://www.youtube.com/watch?v="+ytID); refusal(err) != curation.RefusedRemoved {
		t.Fatalf("suggesting a removed video: %v", err)
	}
	if len(f.source.Calls()) != 1 {
		t.Fatal("a removed video reached YouTube again")
	}

	if err := f.reopen(admin, v.ID); err != nil {
		t.Fatal(err)
	}
	if got := f.detail(v.ID); got.Video.State != curation.Pending || got.Video.Round != 2 || len(got.Reviews) != 0 ||
		!f.audit.Has(admin, audit.VideoReopened) {
		t.Fatalf("reopened %+v", got)
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid`, v.ID); n != 2 {
		t.Fatalf("the earlier round's reviews: %d, want 2 kept", n)
	}
	// c1's round-1 approval does not count towards round 2.
	if state := f.review(c1, v.ID, approve("musica", family.Age5To8)); state != curation.Pending {
		t.Fatalf("first approval of the new round: %s", state)
	}
	if state := f.review(c2, v.ID, approve("musica", family.Age5To8)); state != curation.Approved {
		t.Fatalf("second approval of the new round: %s", state)
	}
}

func TestReopenKeepsTheLastPublishingRoundsProvenance(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	v := f.approvedVideo(ytID, f.now.Add(-time.Hour)) // published in round 1, revisit due in round 2
	f.review(c1, v, reject("O canal mudou."))
	if err := f.remove(admin, v); err != nil {
		t.Fatal(err)
	}
	if err := f.reopen(admin, v); err != nil {
		t.Fatal(err)
	}
	got := f.detail(v)
	if got.Video.State != curation.Pending || got.Video.Round != 3 || got.Video.PublishedRound == nil || *got.Video.PublishedRound != 1 {
		t.Fatalf("reopened %+v", got.Video)
	}
	if got.Provenance == nil {
		t.Fatal("a reopened video lost its provenance before publishing again")
	}
	f.review(c1, v, approve("musica", family.Age5To8))
	f.review(c2, v, approve("musica", family.Age5To8))
	got = f.detail(v)
	if *got.Video.PublishedRound != 3 || got.Provenance.Approvals[curation.MaePai] != 1 || got.Provenance.Approvals[curation.Pedagogo] != 1 {
		t.Fatalf("republished %+v %+v", got.Video, got.Provenance)
	}
}

func TestRemoveAndReopenCheckTheState(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	pending := f.video(ytID)
	approved := f.approvedVideo("approved001", f.now)
	for name, id := range map[string]string{"pending": pending, "approved": approved} {
		if err := f.remove(admin, id); !errors.Is(err, curation.ErrStateConflict) {
			t.Errorf("remove %s: %v", name, err)
		}
		if err := f.reopen(admin, id); !errors.Is(err, curation.ErrStateConflict) {
			t.Errorf("reopen %s: %v", name, err)
		}
	}
	removed := f.video("removedvid1")
	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, removed)
	if err := f.remove(admin, removed); !errors.Is(err, curation.ErrStateConflict) {
		t.Errorf("remove removed: %v", err)
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if err := f.remove(admin, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("remove %q: %v", id, err)
		}
		if err := f.reopen(admin, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("reopen %q: %v", id, err)
		}
	}
	if f.audited(audit.VideoRemoved)+f.audited(audit.VideoReopened) != 0 {
		t.Fatal("a refused decision was audited")
	}

	held := f.video("heldvideo01")
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)
	if err := f.reopen(admin, held); err != nil {
		t.Fatal(err)
	}
	if got := f.detail(held).Video; got.State != curation.Pending || got.Round != 2 {
		t.Fatalf("reopened from held %+v", got)
	}
}

func TestHeldVideosSayWhyTheyAreHeld(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	f.review(c1, v, reject("Tem propaganda."))

	held, err := f.svc.HeldVideos(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(held) != 1 || held[0].HeldReason != curation.HeldByReview {
		t.Fatalf("held %+v", held)
	}
}

func TestReopenClearsTheHoldAndMarksTheReopen(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	c1 := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	f.review(c1, v, reject("Tem propaganda."))
	f.now = f.now.Add(time.Hour)

	if err := f.reopen(admin, v); err != nil {
		t.Fatal(err)
	}
	var reason *string
	var reopened *time.Time
	if err := f.pool.QueryRow(ctx, `SELECT held_reason, reopened_at FROM videos WHERE id = $1::uuid`, v).
		Scan(&reason, &reopened); err != nil {
		t.Fatal(err)
	}
	if reason != nil || reopened == nil || !reopened.Equal(f.now) {
		t.Fatalf("held_reason %v, reopened_at %v", reason, reopened)
	}
}

func TestAHeldVideoAlwaysHasAReason(t *testing.T) {
	f := newFixture(t)
	v := f.video(ytID)
	if _, err := f.pool.Exec(ctx, `UPDATE videos SET state = 'held' WHERE id = $1::uuid`, v); err == nil {
		t.Fatal("a held video without a reason was stored")
	}
}
