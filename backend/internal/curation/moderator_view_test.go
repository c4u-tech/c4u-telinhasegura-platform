package curation_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// moderatorWatched records that the held video played to its end for the
// moderator, as publishing a doubt needs, giving the account the role m
// acts under first if it does not hold it yet; it must succeed.
func (f *fixture) moderatorWatched(m curation.Moderation, videoID string) {
	f.t.Helper()
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, $2, $3)
		ON CONFLICT (account_id, role) DO NOTHING`, m.ActorID, string(m.ActorRole), f.now)
	if err := f.svc.ModeratorWatched(ctx, m, videoID); err != nil {
		f.t.Fatalf("moderator ended: %v", err)
	}
}

// views counts the moderators' viewings recorded for a video.
func (f *fixture) views(videoID string) int {
	f.t.Helper()
	return f.count(`SELECT count(*) FROM moderator_views WHERE video_id = $1::uuid`, videoID)
}

func TestADoubtIsPublishedOnlyAfterItPlayedToTheEndForTheModerator(t *testing.T) {
	f := newFixture(t)
	v := f.doubted(ytID)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Sem risco no vídeo."}
	publish := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}
	if err := f.svc.DecideDoubt(ctx, m, v, publish); !errors.Is(err, curation.ErrNotWatched) {
		t.Fatalf("publishing unwatched: %v", err)
	}
	if st, why := f.state(v); st != "held" || why != curation.HeldByDoubt || f.audited(audit.VideoDoubtDecided) != 0 {
		t.Fatalf("the refusal moved the video: %s %s", st, why)
	}
	// Another moderator's viewing is not this one's.
	other := curation.Moderation{ActorID: f.account("bia@example.com"), ActorRole: staff.Moderator, Reason: "Motivo válido."}
	f.moderatorWatched(other, v)
	if err := f.svc.DecideDoubt(ctx, m, v, publish); !errors.Is(err, curation.ErrNotWatched) {
		t.Fatalf("publishing on another's viewing: %v", err)
	}
	f.moderatorWatched(m, v)
	if err := f.svc.DecideDoubt(ctx, m, v, publish); err != nil {
		t.Fatal(err)
	}
	if st, _ := f.state(v); st != "approved" {
		t.Fatalf("state %s", st)
	}
	if n := f.views(v); n != 0 {
		t.Fatalf("%d viewings outlived the round", n)
	}
}

// Removing a doubted video, by its decision or by a moderator's removal,
// needs no viewing: holding a video back never does.
func TestRemovingADoubtNeedsNoViewing(t *testing.T) {
	f := newFixture(t)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Desafio perigoso."}
	v := f.doubted(ytID)
	if err := f.svc.DecideDoubt(ctx, m, v, curation.DoubtDecision{Decision: curation.Reject}); err != nil {
		t.Fatalf("decide to remove: %v", err)
	}
	w := f.doubted("removedvid1")
	if err := f.svc.ModerateRemove(ctx, m, w); err != nil {
		t.Fatalf("remove: %v", err)
	}
}

// A viewing counts for the round it was recorded in: one from an earlier
// round of the same video never lets a later round's doubt be published.
func TestAViewingFromAnEarlierRoundDoesNotCount(t *testing.T) {
	f := newFixture(t)
	c := f.curator("c1@example.com", curation.MaePai)
	v := f.approvedVideo(ytID, f.now)
	if state := f.review(c, v, approveWith("bichos", family.Age5To8, map[string]curation.Answer{"c19": curation.AnswerDoubt})); state != curation.Held {
		t.Fatalf("a doubt in the revisit: %s", state)
	}
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Sem risco no vídeo."}
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', $2)`, m.ActorID, f.now)
	f.exec(`INSERT INTO moderator_views (moderator_id, role, video_id, round, played_to_end_at)
		VALUES ($1::uuid, 'moderator', $2::uuid, 1, $3)`, m.ActorID, v, f.now)
	publish := curation.DoubtDecision{Decision: curation.Approve, Theme: "bichos", MinAgeBand: family.Age5To8}
	if err := f.svc.DecideDoubt(ctx, m, v, publish); !errors.Is(err, curation.ErrNotWatched) {
		t.Fatalf("publishing on the first round's viewing: %v", err)
	}
	f.moderatorWatched(m, v)
	if n := f.count(`SELECT count(*) FROM moderator_views WHERE video_id = $1::uuid AND round = 2`, v); n != 1 {
		t.Fatalf("%d viewings of the round under way", n)
	}
	if err := f.svc.DecideDoubt(ctx, m, v, publish); err != nil {
		t.Fatal(err)
	}
}

func TestAModeratorViewingKeepsTheFirstEnd(t *testing.T) {
	f := newFixture(t)
	v := f.doubted(ytID)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator}
	first := f.now
	f.moderatorWatched(m, v)
	f.now = f.now.Add(time.Hour)
	f.moderatorWatched(m, v)
	var at time.Time
	var role string
	if err := f.pool.QueryRow(ctx, `SELECT played_to_end_at, role FROM moderator_views WHERE video_id = $1::uuid`, v).
		Scan(&at, &role); err != nil {
		t.Fatal(err)
	}
	if !at.Equal(first) || role != "moderator" {
		t.Fatalf("viewing %s under %q, want %s under moderator", at, role, first)
	}
	// An admin without the moderator role is recorded under the admin role.
	admin := curation.Moderation{ActorID: f.admin("ana@example.com"), ActorRole: staff.Admin}
	f.moderatorWatched(admin, v)
	if n := f.count(`SELECT count(*) FROM moderator_views WHERE moderator_id = $1::uuid AND role = 'admin'`, admin.ActorID); n != 1 {
		t.Fatal("the admin's viewing was not recorded under the admin role")
	}
}

// Only a held video is viewed this way, and only by an account holding
// the role it acts under.
func TestAModeratorViewingIsRefusedOutsideAHold(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', $2)`, mod, f.now)
	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator}
	for name, v := range map[string]string{
		"pending":  f.video("pendingvid1"),
		"approved": f.approvedVideo("approved001", f.now.Add(time.Hour)),
	} {
		if err := f.svc.ModeratorWatched(ctx, m, v); !errors.Is(err, curation.ErrStateConflict) {
			t.Errorf("%s: %v", name, err)
		}
	}
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if err := f.svc.ModeratorWatched(ctx, m, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%q: %v", id, err)
		}
	}
	// A held video of any kind may be watched: the held screen plays them all.
	if err := f.svc.ModeratorWatched(ctx, m, f.heldVideo("refusedvid1")); err != nil {
		t.Errorf("held by a refusal: %v", err)
	}
	v := f.doubted(ytID)
	lost := curation.Moderation{ActorID: f.account("bia@example.com"), ActorRole: staff.Moderator}
	if err := f.svc.ModeratorWatched(ctx, lost, v); !errors.Is(err, staff.ErrNotModerator) {
		t.Fatalf("without the role: %v", err)
	}
	if n := f.views(v); n != 0 {
		t.Fatalf("%d viewings stored", n)
	}
}

// A viewing goes when the round closes, whichever way, and with the role.
func TestAModeratorViewingGoesWithTheRoundAndTheRole(t *testing.T) {
	f := newFixture(t)
	m := curation.Moderation{ActorID: f.account("mia@example.com"), ActorRole: staff.Moderator, Reason: "Motivo válido."}
	for name, act := range map[string]func(string) error{
		"remove": func(v string) error { return f.svc.ModerateRemove(ctx, m, v) },
		"reopen": func(v string) error { return f.svc.ModerateReopen(ctx, m, v) },
		"decide to remove": func(v string) error {
			return f.svc.DecideDoubt(ctx, m, v, curation.DoubtDecision{Decision: curation.Reject})
		},
	} {
		v := f.doubted("v" + name[:3] + "0000000")
		f.moderatorWatched(m, v)
		if err := act(v); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if n := f.views(v); n != 0 {
			t.Errorf("%s: %d viewings after it", name, n)
		}
	}
	v := f.doubted(ytID)
	f.moderatorWatched(m, v)
	f.exec(`DELETE FROM platform_roles WHERE account_id = $1::uuid AND role = 'moderator'`, m.ActorID)
	if n := f.views(v); n != 0 {
		t.Fatalf("%d viewings outlived the role", n)
	}
}
