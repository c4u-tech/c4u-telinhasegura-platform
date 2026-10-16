package family_test

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

const zeroID = "00000000-0000-0000-0000-000000000000"

func TestPendingInvitationsListTheCallersOwn(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	carla := f.owner("carla@example.com")
	dani := f.owner("dani@example.com")
	bia := f.account("bia@example.com", true)

	older, _ := f.svc.Invite(ctx, ana, " BIA@Example.com")
	f.now = f.now.Add(time.Minute)
	newer, _ := f.svc.Invite(ctx, carla, "bia@example.com")
	f.svc.Invite(ctx, carla, "eva@example.com") // someone else's
	revoked, _ := f.svc.Invite(ctx, dani, "bia@example.com")
	if err := f.svc.RevokeInvitation(ctx, dani, revoked.ID); err != nil {
		t.Fatal(err)
	}

	got, err := f.svc.PendingInvitations(ctx, bia)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("invitations: %+v", got)
	}
	if got[0].ID != newer.ID || got[0].InviterEmail != "carla@example.com" || !got[0].ExpiresAt.Equal(newer.ExpiresAt) {
		t.Fatalf("newest first: %+v", got[0])
	}
	if got[1].ID != older.ID || got[1].InviterEmail != "ana@example.com" || !got[1].ExpiresAt.Equal(older.ExpiresAt) {
		t.Fatalf("older: %+v", got[1])
	}
}

func TestPendingInvitationsDropExpiredOnes(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	f.svc.Invite(ctx, ana, "bia@example.com")
	f.now = f.now.Add(7*24*time.Hour + time.Second)

	got, err := f.svc.PendingInvitations(ctx, bia)
	if err != nil || len(got) != 0 {
		t.Fatalf("expired listed: %+v %v", got, err)
	}
}

func TestPendingInvitationsRefusals(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.svc.Invite(ctx, ana, "bia@example.com")
	bia := f.account("bia@example.com", false)
	carla := f.owner("carla@example.com")
	audited := len(f.audit.Entries)

	if _, err := f.svc.PendingInvitations(ctx, bia); !errors.Is(err, family.ErrEmailUnverified) {
		t.Fatalf("unverified: %v", err)
	}
	f.pool.Exec(ctx, `UPDATE accounts SET email_verified_at = now() WHERE id = $1::uuid`, bia)
	if got, err := f.svc.PendingInvitations(ctx, bia); err != nil || len(got) != 1 {
		t.Fatalf("verified: %+v %v", got, err)
	}

	f.pool.Exec(ctx, `UPDATE family_members SET account_id = $1::uuid WHERE account_id = $2::uuid`, bia, carla)
	got, err := f.svc.PendingInvitations(ctx, bia)
	if err != nil || got == nil || len(got) != 0 {
		t.Fatalf("in a family: %#v %v", got, err)
	}
	if n := f.count(`SELECT count(*) FROM family_invitations WHERE accepted_at IS NOT NULL OR revoked_at IS NOT NULL`); n != 0 {
		t.Fatal("the listing changed an invitation")
	}
	if n := len(f.audit.Entries); n != audited {
		t.Fatalf("the listing recorded %d audit events", n-audited)
	}
}

func TestPendingInvitationsSurviveAnErasedInviter(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	inv, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	f.pool.Exec(ctx, `UPDATE family_invitations SET invited_by = gen_random_uuid() WHERE id = $1::uuid`, inv.ID)

	got, err := f.svc.PendingInvitations(ctx, bia)
	if err != nil || len(got) != 1 || got[0].ID != inv.ID || got[0].InviterEmail != "" {
		t.Fatalf("erased inviter: %+v %v", got, err)
	}
}

func TestPendingInvitationsFollowTheCurrentEmail(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	inv, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	f.pool.Exec(ctx, `UPDATE accounts SET email = 'bia2@example.com' WHERE id = $1::uuid`, bia)

	if got, err := f.svc.PendingInvitations(ctx, bia); err != nil || len(got) != 0 {
		t.Fatalf("old address listed: %+v %v", got, err)
	}
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, inv.ID); !errors.Is(err, family.ErrInvitationUnavailable) {
		t.Fatalf("old address accepted: %v", err)
	}
}

func TestAcceptByIDJoinsAsGuardian(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	inv, _ := f.svc.Invite(ctx, ana, "bia@example.com")

	fam, err := f.svc.AcceptInvitationByID(ctx, bia, inv.ID)
	if err != nil {
		t.Fatal(err)
	}
	if fam.Role != family.Guardian || len(fam.Members) != 2 || fam.Members[0].AccountID != ana || fam.Invitations != nil {
		t.Fatalf("family: %+v", fam)
	}
	if n := f.count(`SELECT count(*) FROM family_invitations WHERE id = $1::uuid AND accepted_at IS NOT NULL`, inv.ID); n != 1 {
		t.Fatal("the invitation is still pending")
	}
	if !f.audit.Has(bia, audit.InvitationAccepted) {
		t.Fatal("no invitation_accepted audit")
	}
}

func TestAcceptByIDAnswersAlikeForWhatItCannotTake(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	foreign, _ := f.svc.Invite(ctx, ana, "carla@example.com")
	revoked, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	f.svc.RevokeInvitation(ctx, ana, revoked.ID)
	expiring, _ := f.svc.Invite(ctx, ana, "bia@example.com")

	for name, id := range map[string]string{
		"unknown":   zeroID,
		"malformed": "not-a-uuid",
		"foreign":   foreign.ID,
		"revoked":   revoked.ID,
	} {
		if _, err := f.svc.AcceptInvitationByID(ctx, bia, id); !errors.Is(err, family.ErrInvitationUnavailable) {
			t.Errorf("%s: %v", name, err)
		}
	}
	f.now = f.now.Add(7*24*time.Hour + time.Second)
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, expiring.ID); !errors.Is(err, family.ErrInvitationUnavailable) {
		t.Errorf("expired: %v", err)
	}

	dani := f.owner("dani@example.com")
	used, _ := f.svc.Invite(ctx, dani, "bia@example.com")
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, used.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, used.ID); !errors.Is(err, family.ErrInvitationUnavailable) {
		t.Errorf("used: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM family_invitations WHERE accepted_at IS NOT NULL`); n != 1 {
		t.Fatalf("%d accepted", n)
	}
}

func TestAcceptByIDRefusals(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	inv, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	unspent := func() {
		t.Helper()
		if n := f.count(`SELECT count(*) FROM family_invitations WHERE accepted_at IS NOT NULL`); n != 0 {
			t.Fatal("a refused accept spent the invitation")
		}
	}

	bia := f.account("bia@example.com", false)
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, inv.ID); !errors.Is(err, family.ErrEmailUnverified) {
		t.Fatalf("unverified: %v", err)
	}
	f.pool.Exec(ctx, `UPDATE accounts SET email_verified_at = now() WHERE id = $1::uuid`, bia)

	other := f.owner("dani@example.com")
	f.pool.Exec(ctx, `UPDATE family_members SET account_id = $1::uuid WHERE account_id = $2::uuid`, bia, other)
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, inv.ID); !errors.Is(err, family.ErrAlreadyInFamily) {
		t.Fatalf("in a family: %v", err)
	}
	f.pool.Exec(ctx, `DELETE FROM family_members WHERE account_id = $1::uuid`, bia)
	unspent()

	for _, addr := range []string{"e@example.com", "g@example.com", "h@example.com", "i@example.com", "j@example.com"} {
		f.member(ana, addr) // 6 members, the invitation's seat included
	}
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, inv.ID); !errors.Is(err, family.ErrLimitReached) {
		t.Fatalf("full: %v", err)
	}
	unspent()
}

func TestConcurrentAcceptsByIDJoinOneFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	carla := f.owner("carla@example.com")
	bia := f.account("bia@example.com", true)
	a, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	c, _ := f.svc.Invite(ctx, carla, "bia@example.com")

	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i, id := range []string{a.ID, c.ID} {
		wg.Go(func() { _, errs[i] = f.svc.AcceptInvitationByID(ctx, bia, id) })
	}
	wg.Wait()
	if (errs[0] == nil) == (errs[1] == nil) {
		t.Fatalf("want exactly one success: %v / %v", errs[0], errs[1])
	}
	for _, err := range errs {
		if err != nil && !errors.Is(err, family.ErrAlreadyInFamily) {
			t.Fatalf("the loser: %v", err)
		}
	}
	if n := f.count(`SELECT count(*) FROM family_members WHERE account_id = $1::uuid`, bia); n != 1 {
		t.Fatalf("in %d families", n)
	}
}

func TestAcceptByIDSharesTheTokenThrottle(t *testing.T) {
	f := newFixture(t)
	bia := f.account("bia@example.com", true)
	for range 10 {
		f.svc.LookupInvitation(ctx, bia, "nope")
	}
	var th *family.ThrottledError
	if _, err := f.svc.AcceptInvitationByID(ctx, bia, zeroID); !errors.As(err, &th) || th.RetryAfter <= 0 {
		t.Fatalf("11th: %v", err)
	}
}
