package curation_test

import (
	"errors"
	"fmt"
	"maps"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func approve(theme string, band family.AgeBand) curation.ReviewInput {
	return curation.ReviewInput{Decision: curation.Approve, Theme: theme, MinAgeBand: band}
}

func reject(reason string) curation.ReviewInput {
	return curation.ReviewInput{Decision: curation.Reject, Reason: reason}
}

// review records a review that must succeed, a minute after the clock,
// and returns the video's state after it.
func (f *fixture) review(curatorID, videoID string, in curation.ReviewInput) curation.State {
	f.t.Helper()
	f.now = f.now.Add(time.Minute)
	_, state, err := f.svc.Review(ctx, curatorID, videoID, in)
	if err != nil {
		f.t.Fatalf("review: %v", err)
	}
	return state
}

func (f *fixture) detail(videoID string) curation.VideoDetail {
	f.t.Helper()
	d, err := f.svc.VideoDetail(ctx, videoID)
	if err != nil {
		f.t.Fatal(err)
	}
	return d
}

func (f *fixture) queue(curatorID string) []curation.QueueItem {
	f.t.Helper()
	items, _, err := f.svc.Queue(ctx, curatorID, 0)
	if err != nil {
		f.t.Fatal(err)
	}
	return items
}

// approvedVideo inserts a video published in round 1 with bichos and
// 5-8, whose revisit (round 2) falls due at due.
func (f *fixture) approvedVideo(youtubeID string, due time.Time) string {
	f.t.Helper()
	return f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round, published_round,
		theme, min_age_band, last_reviewed_at, review_due_at, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'approved', 2, 1, 'bichos', '5-8', $2, $3, $2, $2) RETURNING id::text`,
		youtubeID, f.now, due)
}

// waitForLockWaiters returns once n backends of this database are parked
// on a video row lock, i.e. the reviews under test wait behind the test's
// own transaction.
func (f *fixture) waitForLockWaiters(n int) {
	f.t.Helper()
	f.waitForLockWaitersLike(n, "SELECT state, round, review_due_at FROM videos%")
}

// waitForLockWaitersLike returns once n backends of this database are
// parked on a lock in a query matching the LIKE pattern.
func (f *fixture) waitForLockWaitersLike(n int, pattern string) {
	f.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting int
		if err := f.pool.QueryRow(ctx, `SELECT count(*) FROM pg_stat_activity
			WHERE datname = current_database() AND wait_event_type = 'Lock'
			AND query LIKE $1`, pattern).Scan(&waiting); err != nil {
			f.t.Fatal(err)
		}
		if waiting >= n {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatalf("fewer than %d backends waited on a lock in %q", n, pattern)
}

func TestApprovalsPublishTheVideo(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	v := f.video(ytID)

	f.now = f.now.Add(time.Minute)
	r, state, err := f.svc.Review(ctx, c1, v, approve("bichos", family.Age5To8))
	if err != nil || state != curation.Pending {
		t.Fatalf("first approval: %s %v", state, err)
	}
	if r.DisplayRole != curation.MaePai || r.Decision != curation.Approve || r.Theme != "bichos" ||
		r.MinAgeBand != family.Age5To8 || r.Reason != "" || !r.ReviewedAt.Equal(f.now) {
		t.Fatalf("review %+v", r)
	}
	if f.audited(audit.VideoPublished) != 0 {
		t.Fatal("published after one approval")
	}

	if state := f.review(c2, v, approve("musica", family.Age9To12)); state != curation.Approved {
		t.Fatalf("second approval: %s", state)
	}
	got := f.detail(v).Video
	// A tie between bichos and musica goes to the earliest approval; the
	// band is the strictest.
	if got.State != curation.Approved || got.Round != 2 || got.Theme != "bichos" || got.MinAgeBand != family.Age9To12 ||
		got.LastReviewedAt == nil || !got.LastReviewedAt.Equal(f.now) ||
		got.ReviewDueAt == nil || !got.ReviewDueAt.Equal(f.now.Add(180*24*time.Hour)) {
		t.Fatalf("published %+v", got)
	}
	if !f.audit.Has(c2, audit.VideoPublished) || f.audited(audit.VideoPublished) != 1 {
		t.Fatal("video_published must be recorded once, under the last approver")
	}
}

func TestMinApprovalsIsConfigurable(t *testing.T) {
	for _, n := range []int{1, 2, 3} {
		t.Run(fmt.Sprintf("N=%d", n), func(t *testing.T) {
			f := newFixture(t)
			f.rebuild(func(d *curation.Deps) { d.MinApprovals = n })
			v := f.video(ytID)
			for i := 1; i <= n; i++ {
				c := f.curator(fmt.Sprintf("c%d@example.com", i), curation.MaePai)
				want := curation.Pending
				if i == n {
					want = curation.Approved
				}
				if state := f.review(c, v, approve("bichos", family.Age5To8)); state != want {
					t.Fatalf("approval %d: %s, want %s", i, state, want)
				}
			}
		})
	}
}

func TestRemovedCuratorsApprovalDoesNotCount(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	a := f.curator("a@example.com", curation.MaePai)
	b := f.curator("b@example.com", curation.MaePai)
	c := f.curator("c@example.com", curation.MaePai)
	v := f.video(ytID)

	f.review(a, v, approve("bichos", family.Age5To8))
	if _, err := f.team.Revoke(ctx, admin, a, staff.Curator, "Saiu da equipe."); err != nil {
		t.Fatal(err)
	}
	if state := f.review(b, v, approve("bichos", family.Age5To8)); state != curation.Pending {
		t.Fatalf("a removed curator's approval counted: %s", state)
	}
	if n := len(f.detail(v).Reviews); n != 2 {
		t.Fatalf("the removed curator's review must stay in the round: %d", n)
	}
	if state := f.review(c, v, approve("bichos", family.Age5To8)); state != curation.Approved {
		t.Fatalf("second live approval: %s", state)
	}
}

func TestPublishedThemeAndBand(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.MinApprovals = 3 })
	v := f.video(ytID)
	for i, in := range []curation.ReviewInput{
		approve("musica", family.AgeUpTo4),
		approve("bichos", family.Age5To8),
		approve("bichos", family.AgeUpTo4),
	} {
		f.review(f.curator(fmt.Sprintf("c%d@example.com", i), curation.MaePai), v, in)
	}
	if got := f.detail(v).Video; got.Theme != "bichos" || got.MinAgeBand != family.Age5To8 {
		t.Fatalf("published %s %s, want bichos 5-8", got.Theme, got.MinAgeBand)
	}
}

func TestRejectionHolds(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	v := f.video(ytID)
	f.review(c1, v, approve("bichos", family.Age5To8))

	r, state, err := f.svc.Review(ctx, c2, v, reject("  Tem propaganda no meio.  "))
	if err != nil || state != curation.Held || r.Reason != "Tem propaganda no meio." || r.DisplayRole != curation.Cuidador {
		t.Fatalf("rejection: %+v %s %v", r, state, err)
	}
	if got := f.detail(v).Video; got.State != curation.Held || got.Round != 1 {
		t.Fatalf("held %+v", got)
	}
	if !f.audit.Has(c2, audit.VideoHeld) {
		t.Fatal("no video_held audit")
	}
}

func TestReviewRefusals(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	v := f.video(ytID)
	f.suggestedBy(c1, v)
	ok := approve("bichos", family.Age5To8)

	if _, _, err := f.svc.Review(ctx, c1, v, ok); !errors.Is(err, curation.ErrOwnSuggestion) {
		t.Fatalf("own suggestion: %v", err)
	}
	f.review(c2, v, ok)
	if _, _, err := f.svc.Review(ctx, c2, v, ok); !errors.Is(err, curation.ErrAlreadyReviewed) {
		t.Fatalf("second review: %v", err)
	}
	held := f.video("heldvideo01")
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)
	removed := f.video("removedvid1")
	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, removed)
	notDue := f.approvedVideo("approved001", f.now.Add(time.Hour))
	for name, id := range map[string]string{"held": held, "removed": removed, "approved, not due": notDue} {
		if _, _, err := f.svc.Review(ctx, c2, id, ok); !errors.Is(err, curation.ErrNotReviewable) {
			t.Errorf("%s: %v", name, err)
		}
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, _, err := f.svc.Review(ctx, c2, id, ok); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reviews`); n != 1 {
		t.Fatalf("refused reviews were stored: %d rows", n)
	}
}

func TestReviewValidation(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	for name, in := range map[string]curation.ReviewInput{
		"no theme":               approve("", family.Age5To8),
		"unknown theme":          approve("carros", family.Age5To8),
		"no band":                approve("bichos", ""),
		"unknown band":           approve("bichos", "13-17"),
		"approval with a reason": {Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8, Reason: "ok"},
		"blank reason":           reject("   "),
		"reason too long":        reject(strings.Repeat("é", 501)),
		"rejection with a theme": {Decision: curation.Reject, Reason: "x", Theme: "bichos"},
		"no decision":            {Theme: "bichos", MinAgeBand: family.Age5To8},
	} {
		if _, _, err := f.svc.Review(ctx, c, v, in); !errors.Is(err, curation.ErrValidation) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reviews`); n != 0 {
		t.Fatalf("invalid reviews were stored: %d rows", n)
	}
	if state := f.review(c, v, reject(strings.Repeat("é", 500))); state != curation.Held {
		t.Fatalf("a 500-character reason: %s", state)
	}
}

func TestReviewByARemovedCurator(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.video(ytID)
	f.exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid`, c)
	if _, _, err := f.svc.Review(ctx, c, v, approve("bichos", family.Age5To8)); !errors.Is(err, curation.ErrNotCurator) {
		t.Fatalf("removed curator: %v", err)
	}
}

// The review is paused after it took the role row FOR SHARE: the test holds
// the curator's account row FOR UPDATE, and the review's insert wants a KEY
// SHARE lock on it for the foreign key. The staff package cannot import
// curation, so this is where the revoke meets the real review.
func TestRevokingACuratorWaitsForTheirReviewInFlight(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", curation.MaePai)
	v := f.video(ytID)

	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT 1 FROM accounts WHERE id = $1::uuid FOR UPDATE`, bia); err != nil {
		t.Fatal(err)
	}
	reviewed := make(chan error, 1)
	go func() {
		_, _, err := f.svc.Review(ctx, bia, v, approve("bichos", family.Age5To8))
		reviewed <- err
	}()
	f.waitForLockWaitersLike(1, "INSERT INTO video_reviews%") // the review holds the role row now
	revoked := make(chan error, 1)
	go func() {
		_, err := f.team.Revoke(ctx, admin, bia, staff.Curator, "Saiu da equipe.")
		revoked <- err
	}()
	f.waitForLockWaitersLike(1, "DELETE FROM platform_roles%")
	if err := tx.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-reviewed; err != nil {
		t.Fatalf("review: %v", err)
	}
	if err := <-revoked; err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE curator_id = $1::uuid`, bia); n != 1 {
		t.Fatalf("%d reviews stored, want the one in flight", n)
	}
	if roles, err := f.team.Roles(ctx, bia); err != nil || len(roles) != 0 {
		t.Fatalf("roles after the revoke: %v %v", roles, err)
	}
}

func TestConcurrentLastApprovalsPublishOnce(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	c3 := f.curator("c3@example.com", curation.MaePai)
	v := f.video(ytID)
	f.review(c1, v, approve("bichos", family.Age5To8))

	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT 1 FROM videos WHERE id = $1::uuid FOR UPDATE`, v); err != nil {
		t.Fatal(err)
	}
	errs := make(chan error, 2)
	for _, c := range []string{c2, c3} {
		go func() {
			_, _, err := f.svc.Review(ctx, c, v, approve("musica", family.Age5To8))
			errs <- err
		}()
	}
	f.waitForLockWaiters(2)
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	var stored, refused int
	for range 2 {
		switch err := <-errs; {
		case err == nil:
			stored++
		case errors.Is(err, curation.ErrNotReviewable):
			refused++
		default:
			t.Fatalf("concurrent approval: %v", err)
		}
	}
	if stored != 1 || refused != 1 || f.audited(audit.VideoPublished) != 1 {
		t.Fatalf("stored %d, refused %d, published %d times", stored, refused, f.audited(audit.VideoPublished))
	}
	if n := f.count(`SELECT count(*) FROM video_reviews WHERE video_id = $1::uuid`, v); n != 2 {
		t.Fatalf("%d reviews, want 2", n)
	}
}

func TestQueue(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	due := f.approvedVideo("duevideo001", f.now.Add(-24*time.Hour))
	f.approvedVideo("notdue00001", f.now.Add(time.Hour))
	first := f.video("aaaaaaaaaaa")
	f.now = f.now.Add(time.Minute)
	own := f.video("bbbbbbbbbbb")
	f.suggestedBy(c1, own)
	f.now = f.now.Add(time.Minute)
	done := f.video("ccccccccccc")
	f.review(c1, done, approve("bichos", family.Age5To8))
	held := f.video("ddddddddddd")
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, held)

	ids := func(items []curation.QueueItem) []string {
		var out []string
		for _, it := range items {
			out = append(out, it.Video.ID)
		}
		return out
	}
	items := f.queue(c1)
	if got := ids(items); len(got) != 2 || got[0] != due || got[1] != first {
		t.Fatalf("c1's queue %v, want [%s %s]", got, due, first)
	}
	if !items[0].Revisit || items[1].Revisit {
		t.Fatalf("revisit flags %+v", items)
	}
	if got := ids(f.queue(c2)); len(got) != 4 || got[0] != due || got[1] != first || got[2] != own || got[3] != done {
		t.Fatalf("c2's queue %v", got)
	}
}

func TestQueuePages(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	for i := range 51 {
		f.video(fmt.Sprintf("video%06d", i))
		f.now = f.now.Add(time.Second)
	}
	page, more, err := f.svc.Queue(ctx, c, 0)
	if err != nil || len(page) != 50 || !more || page[0].Video.YouTubeID != "video000000" {
		t.Fatalf("first page: %d %v %v", len(page), more, err)
	}
	page, more, err = f.svc.Queue(ctx, c, 50)
	if err != nil || len(page) != 1 || more || page[0].Video.YouTubeID != "video000050" {
		t.Fatalf("second page: %d %v %v", len(page), more, err)
	}
	if _, _, err := f.svc.Queue(ctx, c, -1); !errors.Is(err, curation.ErrValidation) {
		t.Fatalf("negative offset: %v", err)
	}
}

func TestVideoDetail(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	v := f.video(ytID)
	f.review(c1, v, approve("bichos", family.Age5To8))

	d := f.detail(v)
	if d.Video.State != curation.Pending || d.Provenance != nil || len(d.Reviews) != 1 ||
		d.Reviews[0].DisplayRole != curation.MaePai || d.Reviews[0].Theme != "bichos" || d.Reviews[0].MinAgeBand != family.Age5To8 {
		t.Fatalf("pending detail %+v", d)
	}

	f.review(c2, v, approve("bichos", family.Age9To12))
	d = f.detail(v)
	if d.Reviews == nil || len(d.Reviews) != 0 {
		t.Fatalf("the revisit round has reviews: %+v", d.Reviews)
	}
	want := map[curation.DisplayRole]int{curation.MaePai: 1, curation.Pedagogo: 1}
	if d.Provenance == nil || !maps.Equal(d.Provenance.Approvals, want) || !d.Provenance.LastReviewedAt.Equal(f.now) {
		t.Fatalf("provenance %+v", d.Provenance)
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.VideoDetail(ctx, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
}

func TestProvenanceOutlivesAHold(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	c3 := f.curator("c3@example.com", curation.Cuidador)
	v := f.video(ytID)
	if d := f.detail(v); d.Provenance != nil {
		t.Fatalf("a never-published video has provenance %+v", d.Provenance)
	}
	f.review(c1, v, approve("bichos", family.Age5To8))
	f.review(c2, v, approve("bichos", family.Age5To8))
	published := f.now
	f.exec(`UPDATE videos SET review_due_at = $2 WHERE id = $1::uuid`, v, f.now)
	if state := f.review(c3, v, reject("Mudou.")); state != curation.Held {
		t.Fatalf("revisit rejection: %s", state)
	}
	d := f.detail(v)
	want := map[curation.DisplayRole]int{curation.MaePai: 1, curation.Pedagogo: 1}
	if d.Video.State != curation.Held || d.Provenance == nil || !maps.Equal(d.Provenance.Approvals, want) ||
		!d.Provenance.LastReviewedAt.Equal(published) {
		t.Fatalf("held detail %+v provenance %+v", d.Video, d.Provenance)
	}
	if len(d.Reviews) != 1 || d.Reviews[0].Decision != curation.Reject {
		t.Fatalf("held round's reviews %+v", d.Reviews)
	}
}
