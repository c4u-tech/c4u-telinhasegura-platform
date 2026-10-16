package curation_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func (f *fixture) report(accountID, videoID string, reason curation.ReportReason, note string) bool {
	f.t.Helper()
	f.now = f.now.Add(time.Second) // reports differ in time, so "oldest first" is testable
	created, err := f.svc.Report(ctx, accountID, videoID, reason, note)
	if err != nil {
		f.t.Fatalf("report: %v", err)
	}
	return created
}

func (f *fixture) state(videoID string) (state, heldReason string) {
	f.t.Helper()
	var reason *string
	if err := f.pool.QueryRow(ctx, `SELECT state, held_reason FROM videos WHERE id = $1::uuid`, videoID).Scan(&state, &reason); err != nil {
		f.t.Fatal(err)
	}
	if reason != nil {
		heldReason = *reason
	}
	return state, heldReason
}

// waitForReportLockWaiters returns once n reports wait on a video row lock.
func (f *fixture) waitForReportLockWaiters(n int) {
	f.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting int
		if err := f.pool.QueryRow(ctx, `SELECT count(*) FROM pg_stat_activity
			WHERE datname = current_database() AND wait_event_type = 'Lock'
			AND query LIKE 'SELECT state FROM videos WHERE id = $1::uuid FOR UPDATE%'`).Scan(&waiting); err != nil {
			f.t.Fatal(err)
		}
		if waiting >= n {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatalf("fewer than %d reports waited on the video lock", n)
}

func TestAReportHidesTheVideoForTheWholeFamily(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	lia, teo := f.minor(fam, family.Age5To8), f.minor(fam, family.AgeUpTo4)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)

	if !f.report(ana, v, curation.ReportAssustador, "  Tem um monstro.  ") {
		t.Fatal("not created")
	}
	for _, c := range []curation.Child{lia, teo} {
		if got := f.catalog(c); len(got) != 0 {
			t.Fatalf("still on a shelf: %+v", got)
		}
	}
	if page, _, err := f.svc.FamilyCatalog(ctx, ana, lia.MinorID, 0); err != nil || len(page) != 0 {
		t.Fatalf("guardian catalogue: %+v %v", page, err)
	}
	if n := f.count(`SELECT count(*) FROM video_reports WHERE note = 'Tem um monstro.' AND account_id = $1::uuid`, ana); n != 1 {
		t.Fatalf("%d trimmed reports by ana", n)
	}
	if state, _ := f.state(v); state != "approved" {
		t.Fatalf("one report changed the state to %s", state)
	}
	if !f.audit.Has(ana, audit.VideoReported) {
		t.Fatal("no video_reported")
	}
}

func TestAFamilyReportsAVideoOnce(t *testing.T) {
	f := newFixture(t)
	fam, ana := f.family("ana@example.com")
	bia := f.join(fam, "bia@example.com")
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)

	if !f.report(ana, v, curation.ReportAssustador, "Tem um monstro.") {
		t.Fatal("first not created")
	}
	if f.report(bia, v, curation.ReportOutro, "Outro motivo.") {
		t.Fatal("second created")
	}
	if n := f.count(`SELECT count(*) FROM video_reports WHERE reason = 'assustador' AND account_id = $1::uuid`, ana); n != 1 {
		t.Fatalf("the first report was not kept: %d", n)
	}
	if n := f.audited(audit.VideoReported); n != 1 {
		t.Fatalf("%d video_reported, want 1", n)
	}
}

func TestReportRefusals(t *testing.T) {
	f := newFixture(t)
	_, ana := f.family("ana@example.com")
	lonely := f.account("solo@example.com")
	v1 := f.published(nthID(1), "bichos", family.AgeUpTo4)
	v2 := f.published(nthID(2), "bichos", family.AgeUpTo4)
	removed := f.published(nthID(3), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'removed' WHERE id = $1::uuid`, removed)
	pending := f.video(nthID(4))

	for _, c := range []struct {
		name, account, video string
		reason               curation.ReportReason
		note                 string
		want                 error
	}{
		{"unknown reason", ana, v1, "spam", "", curation.ErrValidation},
		{"501 runes", ana, v1, curation.ReportOutro, strings.Repeat("é", 501), curation.ErrValidation},
		{"no family", lonely, v1, curation.ReportOutro, "", curation.ErrNotFound},
		{"malformed video", ana, "abc", curation.ReportOutro, "", curation.ErrNotFound},
		{"unknown video", ana, "00000000-0000-0000-0000-000000000000", curation.ReportOutro, "", curation.ErrNotFound},
		{"removed video", ana, removed, curation.ReportOutro, "", curation.ErrNotFound},
	} {
		if _, err := f.svc.Report(ctx, c.account, c.video, c.reason, c.note); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", c.name, err, c.want)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reports`); n != 0 {
		t.Fatalf("%d reports stored", n)
	}

	if !f.report(ana, v1, curation.ReportOutro, strings.Repeat("é", 500)) {
		t.Fatal("500 runes refused")
	}
	if !f.report(ana, v2, curation.ReportInadequado, "   ") {
		t.Fatal("blank note refused")
	}
	if n := f.count(`SELECT count(*) FROM video_reports WHERE video_id = $1::uuid AND note IS NULL`, v2); n != 1 {
		t.Fatal("a blank note was stored")
	}
	if !f.report(ana, pending, curation.ReportPublicidade, "") {
		t.Fatal("a pending video refused")
	}
}

func TestReportsHoldAtTheThreshold(t *testing.T) {
	f := newFixture(t)
	_, owners := f.families(3)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	pending := f.video(nthID(2))

	f.report(owners[0], v, curation.ReportAssustador, "Tem um monstro.")
	f.report(owners[1], v, curation.ReportAssustador, "")
	if state, _ := f.state(v); state != "approved" {
		t.Fatalf("held at 2 reports: %s", state)
	}
	f.report(owners[2], v, curation.ReportOutro, "Fala palavrão.")
	if state, reason := f.state(v); state != "held" || reason != curation.HeldByReports {
		t.Fatalf("at 3 reports: %s %s", state, reason)
	}
	if !f.audit.Has(owners[2], audit.VideoHeld) {
		t.Fatal("video_held not under the reporting account")
	}

	held, err := f.svc.HeldVideos(ctx)
	if err != nil || len(held) != 1 {
		t.Fatalf("held %+v %v", held, err)
	}
	r := held[0].Reports
	if len(r.ByReason) != 2 || r.ByReason[curation.ReportAssustador] != 2 || r.ByReason[curation.ReportOutro] != 1 ||
		len(r.Notes) != 2 || r.Notes[0] != "Tem um monstro." || r.Notes[1] != "Fala palavrão." {
		t.Fatalf("reports %+v", r)
	}

	for _, o := range owners {
		f.report(o, pending, curation.ReportOutro, "")
	}
	if state, _ := f.state(pending); state != "pending" {
		t.Fatalf("a pending video was held: %s", state)
	}
}

func TestReopenRestartsTheReportCount(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("adm@example.com")
	ids, owners := f.families(6)
	lia := f.minor(ids[0], family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	for _, o := range owners[:3] {
		f.report(o, v, curation.ReportOutro, "")
	}
	f.now = f.now.Add(time.Hour)
	if err := f.reopen(admin, v); err != nil {
		t.Fatal(err)
	}
	f.exec(`UPDATE videos SET state = 'approved' WHERE id = $1::uuid`, v) // the curators publish it again
	f.now = f.now.Add(time.Hour)

	f.report(owners[3], v, curation.ReportInadequado, "")
	f.report(owners[4], v, curation.ReportInadequado, "")
	if state, _ := f.state(v); state != "approved" {
		t.Fatalf("earlier reports still count: %s", state)
	}
	if got := f.catalog(lia); len(got) != 0 {
		t.Fatalf("the reporting family's hide was lifted: %+v", got)
	}
	f.report(owners[5], v, curation.ReportInadequado, "")
	if state, _ := f.state(v); state != "held" {
		t.Fatalf("3 reports since the reopen: %s", state)
	}
	held, err := f.svc.HeldVideos(ctx)
	if err != nil || len(held) != 1 || len(held[0].Reports.ByReason) != 1 || held[0].Reports.ByReason[curation.ReportInadequado] != 3 {
		t.Fatalf("held %+v %v", held, err)
	}
}

func TestConcurrentLastReportsHoldOnce(t *testing.T) {
	f := newFixture(t)
	f.rebuild(func(d *curation.Deps) { d.ReportThreshold = 2 })
	_, owners := f.families(2)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)

	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT 1 FROM videos WHERE id = $1::uuid FOR UPDATE`, v); err != nil {
		t.Fatal(err)
	}
	errs := make(chan error, 2)
	for _, o := range owners {
		go func() {
			_, err := f.svc.Report(ctx, o, v, curation.ReportOutro, "")
			errs <- err
		}()
	}
	f.waitForReportLockWaiters(2)
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
	}
	if state, _ := f.state(v); state != "held" {
		t.Fatalf("state %s", state)
	}
	if n := f.audited(audit.VideoHeld); n != 1 {
		t.Fatalf("%d video_held, want 1", n)
	}
}

func TestReportLimit(t *testing.T) {
	f := newFixture(t)
	_, ana := f.family("ana@example.com")
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	for range 20 { // refused calls spend the budget too
		if _, err := f.svc.Report(ctx, ana, v, "spam", ""); !errors.Is(err, curation.ErrValidation) {
			t.Fatal(err)
		}
	}
	_, err := f.svc.Report(ctx, ana, v, curation.ReportOutro, "")
	var throttled *curation.ThrottledError
	if !errors.As(err, &throttled) || throttled.RetryAfter <= 0 {
		t.Fatalf("21st: %v", err)
	}
}

func TestReportRefusesControlCharacters(t *testing.T) {
	f := newFixture(t)
	_, ana := f.family("ana@example.com")
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	for _, note := range []string{"a\u0000b", "a\u0007b"} {
		if _, err := f.svc.Report(ctx, ana, v, curation.ReportOutro, note); !errors.Is(err, curation.ErrValidation) {
			t.Errorf("%q: %v, want ErrValidation", note, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_reports`); n != 0 {
		t.Fatalf("%d reports stored", n)
	}
	if !f.report(ana, v, curation.ReportOutro, "linha 1\nlinha 2\tok") {
		t.Fatal("a note with a newline and a tab was refused")
	}
}

func TestPublishingAVideoAlreadyReportedHoldsIt(t *testing.T) {
	for _, c := range []struct {
		reports   int
		wantState curation.State
	}{{3, curation.Held}, {2, curation.Approved}} {
		f := newFixture(t)
		_, owners := f.families(3)
		c1 := f.curator("c1@example.com", curation.MaePai)
		c2 := f.curator("c2@example.com", curation.Pedagogo)
		v := f.video(nthID(1))
		for _, o := range owners[:c.reports] {
			f.report(o, v, curation.ReportOutro, "")
		}
		f.review(c1, v, approve("bichos", family.AgeUpTo4))
		if got := f.review(c2, v, approve("bichos", family.AgeUpTo4)); got != c.wantState {
			t.Fatalf("%d reports: state %s, want %s", c.reports, got, c.wantState)
		}
		state, reason := f.state(v)
		if c.wantState == curation.Held {
			if state != "held" || reason != curation.HeldByReports {
				t.Fatalf("row %s/%s", state, reason)
			}
			if f.audited(audit.VideoHeld) != 1 || f.audited(audit.VideoPublished) != 0 || !f.audit.Has(c2, audit.VideoHeld) {
				t.Fatalf("audit %+v", f.audit.Entries)
			}
			if n := f.count(`SELECT count(*) FROM videos WHERE id = $1::uuid AND published_round = 1 AND round = 2 AND theme = 'bichos'`, v); n != 1 {
				t.Fatal("published fields not kept")
			}
		} else if state != "approved" || f.audited(audit.VideoPublished) != 1 || f.audited(audit.VideoHeld) != 0 {
			t.Fatalf("control: %s %+v", state, f.audit.Entries)
		}
	}
}
