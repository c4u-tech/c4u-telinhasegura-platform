package curation_test

import (
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// lowerTo rebuilds the service with a new approval threshold, as a restart
// with another CURATION_MIN_APPROVALS would.
func (f *fixture) lowerTo(n int) {
	f.t.Helper()
	f.rebuild(func(d *curation.Deps) { d.MinApprovals = n })
}

// publishReady runs the pass that must succeed, a minute after the clock.
func (f *fixture) publishReady() {
	f.t.Helper()
	f.now = f.now.Add(time.Minute)
	if err := f.svc.PublishReady(ctx); err != nil {
		f.t.Fatalf("publish ready: %v", err)
	}
}

func TestPublishReadyPublishesAVideoAtTheLoweredThreshold(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	if state := f.review(c1, v, approve("bichos", family.Age5To8)); state != curation.Pending {
		t.Fatalf("first approval: %s", state)
	}

	f.lowerTo(1)
	f.publishReady()
	got := f.detail(v).Video
	if got.State != curation.Approved || got.Round != 2 || got.Theme != "bichos" || got.MinAgeBand != family.Age5To8 ||
		got.LastReviewedAt == nil || !got.LastReviewedAt.Equal(f.now) ||
		got.ReviewDueAt == nil || !got.ReviewDueAt.Equal(f.now.Add(180*24*time.Hour)) {
		t.Fatalf("published %+v", got)
	}
	if !f.audit.Has("", audit.VideoPublished) || f.audited(audit.VideoPublished) != 1 {
		t.Fatalf("video_published must be recorded once, with no actor: %+v", f.audit.Entries)
	}
}

func TestPublishReadyLeavesAVideoBelowTheThreshold(t *testing.T) {
	f := newFixture(t)
	v := f.video(ytID)
	f.review(f.curator("c1@example.com", curation.MaePai), v, approve("bichos", family.Age5To8))

	f.publishReady()
	if got := f.detail(v).Video; got.State != curation.Pending || got.Round != 1 {
		t.Fatalf("published below the threshold: %+v", got)
	}
	if f.audited(audit.VideoPublished) != 0 {
		t.Fatal("video_published recorded")
	}
}

func TestPublishReadyIgnoresARemovedCuratorsApproval(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	a := f.curator("a@example.com", curation.MaePai)
	v := f.video(ytID)
	f.review(a, v, approve("bichos", family.Age5To8))
	if _, err := f.team.Revoke(ctx, admin, a, staff.Curator, "Saiu da equipe."); err != nil {
		t.Fatal(err)
	}

	f.lowerTo(1)
	f.publishReady()
	if got := f.detail(v).Video; got.State != curation.Pending {
		t.Fatalf("a removed curator's approval counted: %s", got.State)
	}
}

func TestPublishReadyLeavesAHeldVideo(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	v := f.video(ytID)
	f.review(c1, v, approve("bichos", family.Age5To8))
	if state := f.review(c2, v, reject("Briga.")); state != curation.Held {
		t.Fatalf("rejection: %s", state)
	}

	f.lowerTo(1)
	f.publishReady()
	if state, _ := f.state(v); state != "held" || f.audited(audit.VideoPublished) != 0 {
		t.Fatalf("a held video moved: %s %+v", state, f.audit.Entries)
	}
}

func TestPublishReadyRunsTwiceAsOnce(t *testing.T) {
	f := newFixture(t)
	v := f.video(ytID)
	f.review(f.curator("c1@example.com", curation.MaePai), v, approve("bichos", family.Age5To8))

	f.lowerTo(1)
	f.publishReady()
	f.publishReady()
	if got := f.detail(v).Video; got.State != curation.Approved || got.Round != 2 || f.audited(audit.VideoPublished) != 1 {
		t.Fatalf("second pass changed the video: %+v %+v", got, f.audit.Entries)
	}
}

func TestPublishReadyRepublishesADueRevisit(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	c3 := f.curator("c3@example.com", curation.Cuidador)
	v := f.video(ytID)
	f.review(c1, v, approve("bichos", family.Age5To8))
	if state := f.review(c2, v, approve("bichos", family.Age5To8)); state != curation.Approved {
		t.Fatalf("second approval: %s", state)
	}
	f.now = f.now.Add(181 * 24 * time.Hour)
	if state := f.review(c3, v, approve("bichos", family.Age5To8)); state != curation.Approved {
		t.Fatalf("revisit approval: %s", state)
	}

	f.lowerTo(1)
	f.publishReady()
	got := f.detail(v).Video
	if got.State != curation.Approved || got.Round != 3 || got.ReviewDueAt == nil || !got.ReviewDueAt.Equal(f.now.Add(180*24*time.Hour)) {
		t.Fatalf("revisit not republished: %+v", got)
	}
	if f.audited(audit.VideoPublished) != 2 {
		t.Fatalf("audit %+v", f.audit.Entries)
	}
}

func TestPublishReadyHoldsAVideoAlreadyReported(t *testing.T) {
	f := newFixture(t)
	_, owners := f.families(3)
	v := f.video(nthID(1))
	for _, o := range owners {
		f.report(o, v, curation.ReportOutro, "")
	}
	f.review(f.curator("c1@example.com", curation.MaePai), v, approve("bichos", family.AgeUpTo4))

	f.lowerTo(1)
	f.publishReady()
	if state, reason := f.state(v); state != "held" || reason != curation.HeldByReports {
		t.Fatalf("row %s/%s", state, reason)
	}
	if !f.audit.Has("", audit.VideoHeld) || f.audited(audit.VideoPublished) != 0 {
		t.Fatalf("audit %+v", f.audit.Entries)
	}
}
