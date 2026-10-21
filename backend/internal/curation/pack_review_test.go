package curation_test

import (
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func approvePack() curation.PackReviewInput {
	return curation.PackReviewInput{Decision: curation.Approve}
}

func rejectPack(reason string) curation.PackReviewInput {
	return curation.PackReviewInput{Decision: curation.Reject, Reason: reason}
}

// reviewPack records a pack review that must succeed, a minute after the
// clock, and returns the pack's state after it.
func (f *fixture) reviewPack(curatorID, packID string, in curation.PackReviewInput) curation.State {
	f.t.Helper()
	f.now = f.now.Add(time.Minute)
	_, state, err := f.svc.ReviewPack(ctx, curatorID, packID, in)
	if err != nil {
		f.t.Fatalf("pack review: %v", err)
	}
	return state
}

// waitForPackLockWaiters returns once n backends of this database wait on
// ReviewPack's pack row lock, behind the test's own transaction.
func (f *fixture) waitForPackLockWaiters(n int) {
	f.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting int
		if err := f.pool.QueryRow(ctx, `SELECT count(*) FROM pg_stat_activity
			WHERE datname = current_database() AND wait_event_type = 'Lock'
			AND query LIKE 'SELECT state, round FROM packs%'`).Scan(&waiting); err != nil {
			f.t.Fatal(err)
		}
		if waiting >= n {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatalf("fewer than %d pack reviews waited on the pack lock", n)
}

func TestPackApprovalsPublishThePack(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Pedagogo)
	c3 := f.curator("c3@example.com", curation.Cuidador)
	id := f.compose(c1, f.approvedVideos(3)...).ID

	f.now = f.now.Add(time.Minute)
	r, state, err := f.svc.ReviewPack(ctx, c2, id, approvePack())
	if err != nil || state != curation.Pending {
		t.Fatalf("first approval: %s %v", state, err)
	}
	if r.DisplayRole != curation.Pedagogo || r.Decision != curation.Approve || r.Reason != "" || !r.ReviewedAt.Equal(f.now) {
		t.Fatalf("review %+v", r)
	}
	if f.audited(audit.PackPublished) != 0 {
		t.Fatal("published after one approval")
	}
	if state := f.reviewPack(c3, id, approvePack()); state != curation.Approved {
		t.Fatalf("second approval: %s", state)
	}
	p := f.packDetail(c1, id)
	want := map[curation.DisplayRole]int{curation.Pedagogo: 1, curation.Cuidador: 1}
	if p.State != curation.Approved || p.Round != 1 || p.Reviewable || len(p.Reviews) != 2 || p.Provenance == nil ||
		!maps.Equal(p.Provenance.Approvals, want) || !p.Provenance.LastReviewedAt.Equal(f.now) {
		t.Fatalf("published %+v, provenance %+v", p, p.Provenance)
	}
	if n := f.count(`SELECT count(*) FROM packs p JOIN pack_rounds r ON r.pack_id = p.id AND r.round = 1
		WHERE p.id = $1::uuid AND p.published_round = 1 AND r.outcome = 'published'`, id); n != 1 {
		t.Fatal("publishing must set the round's outcome and the published round")
	}
	if !f.audit.Has(c3, audit.PackPublished) || f.audited(audit.PackPublished) != 1 {
		t.Fatal("pack_published must be recorded once, under the last approver")
	}
}

func TestPackMinApprovalsIsConfigurable(t *testing.T) {
	for _, n := range []int{1, 2, 3} {
		t.Run(fmt.Sprintf("N=%d", n), func(t *testing.T) {
			f := newFixture(t)
			f.rebuild(func(d *curation.Deps) { d.MinApprovals = n })
			id := f.compose(f.curator("c0@example.com", curation.MaePai), f.approvedVideos(3)...).ID
			for i := 1; i <= n; i++ {
				c := f.curator(fmt.Sprintf("c%d@example.com", i), curation.MaePai)
				want := curation.Pending
				if i == n {
					want = curation.Approved
				}
				if state := f.reviewPack(c, id, approvePack()); state != want {
					t.Fatalf("approval %d: %s, want %s", i, state, want)
				}
			}
		})
	}
}

func TestTheComposerNeverApprovesTheirRound(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	id := f.compose(c1, v...).ID

	if _, _, err := f.svc.ReviewPack(ctx, c1, id, approvePack()); !errors.Is(err, curation.ErrOwnComposition) {
		t.Fatalf("composer: %v", err)
	}
	if _, err := f.svc.Recompose(ctx, c2, id, curation.PackInput{Title: "Outro", VideoIDs: v}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := f.svc.ReviewPack(ctx, c2, id, approvePack()); !errors.Is(err, curation.ErrOwnComposition) {
		t.Fatalf("recomposer: %v", err)
	}
	if state := f.reviewPack(c1, id, approvePack()); state != curation.Pending {
		t.Fatalf("round 1's composer reviewing round 2: %s", state)
	}
	if n := f.count(`SELECT count(*) FROM pack_reviews`); n != 1 {
		t.Fatalf("refused reviews were stored: %d rows", n)
	}
}

func TestPackReviewRefusals(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	c3 := f.curator("c3@example.com", curation.MaePai)
	v := f.approvedVideos(3)
	pending := f.compose(c1, v...).ID
	f.reviewPack(c2, pending, approvePack())
	if _, _, err := f.svc.ReviewPack(ctx, c2, pending, approvePack()); !errors.Is(err, curation.ErrAlreadyReviewed) {
		t.Fatalf("second review: %v", err)
	}
	held := f.compose(c1, v...).ID
	f.reviewPack(c2, held, rejectPack("Muito longo."))
	removed := f.compose(c1, v...).ID
	if err := f.svc.RemovePack(ctx, admin, removed); err != nil {
		t.Fatal(err)
	}
	approved := f.publishedPack(v...)

	before := f.count(`SELECT count(*) FROM pack_reviews`)
	for name, id := range map[string]string{"held": held, "removed": removed, "approved, no open round": approved} {
		if _, _, err := f.svc.ReviewPack(ctx, c3, id, approvePack()); !errors.Is(err, curation.ErrNotReviewable) {
			t.Errorf("%s: %v", name, err)
		}
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, _, err := f.svc.ReviewPack(ctx, c3, id, approvePack()); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM pack_reviews`); n != before {
		t.Fatalf("refused reviews were stored: %d rows, want %d", n, before)
	}
}

func TestPackReviewValidation(t *testing.T) { // the shape of the review body
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	id := f.compose(c1, f.approvedVideos(3)...).ID
	for name, in := range map[string]curation.PackReviewInput{
		"approval with a reason": {Decision: curation.Approve, Reason: "ok"},
		"blank reason":           rejectPack("   "),
		"reason too long":        rejectPack(strings.Repeat("é", 501)),
		"no decision":            {},
		"unknown decision":       {Decision: "talvez"},
	} {
		if _, _, err := f.svc.ReviewPack(ctx, c2, id, in); !errors.Is(err, curation.ErrValidation) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM pack_reviews`); n != 0 {
		t.Fatalf("invalid reviews were stored: %d rows", n)
	}
	if state := f.reviewPack(c2, id, rejectPack(strings.Repeat("é", 500))); state != curation.Held {
		t.Fatalf("a 500-rune reason: %s", state)
	}
}

func TestARemovedCuratorsPackApprovalDoesNotCount(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	c0 := f.curator("c0@example.com", curation.MaePai)
	a := f.curator("a@example.com", curation.MaePai)
	b := f.curator("b@example.com", curation.MaePai)
	c := f.curator("c@example.com", curation.MaePai)
	id := f.compose(c0, f.approvedVideos(3)...).ID

	f.reviewPack(a, id, approvePack())
	if _, err := f.team.Revoke(ctx, admin, a, staff.Curator, "Saiu da equipe."); err != nil {
		t.Fatal(err)
	}
	if state := f.reviewPack(b, id, approvePack()); state != curation.Pending {
		t.Fatalf("a removed curator's approval counted: %s", state)
	}
	if n := len(f.packDetail(b, id).Reviews); n != 2 {
		t.Fatalf("the removed curator's review must stay in the round: %d", n)
	}
	if state := f.reviewPack(c, id, approvePack()); state != curation.Approved {
		t.Fatalf("second live approval: %s", state)
	}
}

func TestARejectionHoldsAPendingPack(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.Cuidador)
	id := f.compose(c1, f.approvedVideos(3)...).ID

	r, state, err := f.svc.ReviewPack(ctx, c2, id, rejectPack("  Muito longo.  "))
	if err != nil || state != curation.Held || r.Reason != "Muito longo." || r.DisplayRole != curation.Cuidador {
		t.Fatalf("rejection: %+v %s %v", r, state, err)
	}
	if n := f.count(`SELECT count(*) FROM pack_rounds WHERE pack_id = $1::uuid AND round = 1 AND outcome = 'rejected'`, id); n != 1 {
		t.Fatal("the round's outcome must be rejected")
	}
	if !f.audit.Has(c2, audit.PackHeld) {
		t.Fatal("no pack_held under the rejector")
	}
}

func TestARejectionClosesARecomposedRoundUnpublished(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	c3 := f.curator("c3@example.com", curation.MaePai)
	v := f.approvedVideos(6)
	id := f.publishedPack(v[:3]...)
	if _, err := f.svc.Recompose(ctx, c1, id, curation.PackInput{Title: "Outro", VideoIDs: v[3:]}); err != nil {
		t.Fatal(err)
	}

	if state := f.reviewPack(c2, id, rejectPack("Pior que o anterior.")); state != curation.Approved {
		t.Fatalf("a rejected round of an approved pack: %s", state)
	}
	if n := f.count(`SELECT count(*) FROM packs p JOIN pack_rounds r ON r.pack_id = p.id AND r.round = 2
		WHERE p.id = $1::uuid AND p.state = 'approved' AND p.published_round = 1 AND r.outcome = 'rejected'`, id); n != 1 {
		t.Fatal("round 2 must close rejected while round 1 stays published")
	}
	if f.audited(audit.PackHeld) != 0 {
		t.Fatal("an approved pack was recorded as held")
	}
	if _, _, err := f.svc.ReviewPack(ctx, c3, id, approvePack()); !errors.Is(err, curation.ErrNotReviewable) {
		t.Fatalf("the closed round took another review: %v", err)
	}
}

func TestApprovalsPublishARecomposedRound(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	c3 := f.curator("c3@example.com", curation.MaePai)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.approvedVideos(6)
	id := f.publishedPack(v[:3]...)
	if _, err := f.svc.Recompose(ctx, c1, id, curation.PackInput{Title: "Outro", VideoIDs: v[3:]}); err != nil {
		t.Fatal(err)
	}

	if state := f.reviewPack(c2, id, approvePack()); state != curation.Approved {
		t.Fatalf("first approval of round 2: %s", state)
	}
	if state := f.reviewPack(c3, id, approvePack()); state != curation.Approved {
		t.Fatalf("second approval of round 2: %s", state)
	}
	if n := f.count(`SELECT count(*) FROM packs p JOIN pack_rounds r ON r.pack_id = p.id AND r.round = 2
		WHERE p.id = $1::uuid AND p.state = 'approved' AND p.published_round = 2 AND r.outcome = 'published'`, id); n != 1 {
		t.Fatal("round 2 must be published and become the published round")
	}
	got := f.kidPacks(lia)
	if len(got) != 1 || got[0].ID != id || got[0].Title != "Outro" || !slices.Equal(packVideoIDs(got[0]), v[3:]) {
		t.Fatalf("an eligible child after round 2's publication: %+v", got)
	}
}

func TestConcurrentLastPackApprovalsPublishOnce(t *testing.T) {
	f := newFixture(t)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	c3 := f.curator("c3@example.com", curation.MaePai)
	c4 := f.curator("c4@example.com", curation.MaePai)
	id := f.compose(c1, f.approvedVideos(3)...).ID
	f.reviewPack(c2, id, approvePack())

	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT 1 FROM packs WHERE id = $1::uuid FOR UPDATE`, id); err != nil {
		t.Fatal(err)
	}
	errs := make(chan error, 2)
	for _, c := range []string{c3, c4} {
		go func() {
			_, _, err := f.svc.ReviewPack(ctx, c, id, approvePack())
			errs <- err
		}()
	}
	f.waitForPackLockWaiters(2)
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
	if stored != 1 || refused != 1 || f.audited(audit.PackPublished) != 1 {
		t.Fatalf("stored %d, refused %d, published %d times", stored, refused, f.audited(audit.PackPublished))
	}
	if n := f.count(`SELECT count(*) FROM pack_reviews WHERE pack_id = $1::uuid`, id); n != 2 {
		t.Fatalf("%d reviews, want 2", n)
	}
}

func TestAnErasedComposersPackStaysReviewable(t *testing.T) {
	f := newFixture(t)
	c0 := f.curator("c0@example.com", curation.Pedagogo)
	c1 := f.curator("c1@example.com", curation.MaePai)
	c2 := f.curator("c2@example.com", curation.MaePai)
	id := f.compose(c0, f.approvedVideos(3)...).ID
	f.exec(`DELETE FROM accounts WHERE id = $1::uuid`, c0)

	items, _, err := f.svc.PackQueue(ctx, c1, 0)
	if err != nil || len(items) != 1 || !items[0].Reviewable || items[0].ComposerRole != curation.Pedagogo {
		t.Fatalf("queue %+v %v", items, err)
	}
	f.reviewPack(c1, id, approvePack())
	if state := f.reviewPack(c2, id, approvePack()); state != curation.Approved {
		t.Fatalf("an erased composer's pack: %s", state)
	}
}
