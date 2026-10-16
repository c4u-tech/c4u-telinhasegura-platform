package family_test

import (
	"bytes"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

func TestInviteMailsASingleUseLink(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")

	inv, err := f.svc.Invite(ctx, ana, " Bia@Example.com")
	if err != nil {
		t.Fatal(err)
	}
	if inv.Email != "bia@example.com" || !inv.ExpiresAt.Equal(f.now.Add(7*24*time.Hour)) || inv.ID == "" {
		t.Fatalf("invitation: %+v", inv)
	}
	msgs := f.mail.To("bia@example.com")
	if len(msgs) != 1 || !strings.Contains(msgs[0].Body, "https://app.test/convite?token=") || !strings.Contains(msgs[0].Body, "ana@example.com") {
		t.Fatalf("mail: %+v", msgs)
	}
	if msgs[0].TTL != 7*24*time.Hour {
		t.Fatalf("invitation TTL %s, want 7 days", msgs[0].TTL)
	}
	var stored []byte
	if err := f.pool.QueryRow(ctx, `SELECT token_hash FROM family_invitations WHERE id = $1::uuid`, inv.ID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(stored, secret.Hash(f.lastToken("bia@example.com"))) {
		t.Fatal("the stored value is not the token's digest")
	}
	fam, _ := f.svc.Get(ctx, ana)
	if fam.PendingInvitations != 1 || len(fam.Invitations) != 1 || fam.Invitations[0].Email != "bia@example.com" {
		t.Fatalf("family: %+v", fam)
	}
	if !f.audit.Has(ana, audit.InvitationSent) {
		t.Fatal("no invitation_sent audit")
	}
}

func TestInviteAnswersAlikeWhateverTheAddress(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.account("unverified@example.com", false)
	f.owner("elsewhere@example.com")
	for _, addr := range []string{"nobody@example.com", "unverified@example.com", "elsewhere@example.com"} {
		if _, err := f.svc.Invite(ctx, ana, addr); err != nil {
			t.Fatalf("%s: %v", addr, err)
		}
		if len(f.mail.To(addr)) != 1 {
			t.Fatalf("%s got no mail", addr)
		}
	}
}

func TestInviteRefusals(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")
	if _, err := f.svc.Invite(ctx, bia, "carla@example.com"); !errors.Is(err, family.ErrNotOwner) {
		t.Fatalf("guardian invites: %v", err)
	}
	if _, err := f.svc.Invite(ctx, ana, "BIA@example.com"); !errors.Is(err, family.ErrAlreadyMember) {
		t.Fatalf("member: %v", err)
	}
	if _, err := f.svc.Invite(ctx, ana, "ana@example.com"); !errors.Is(err, family.ErrAlreadyMember) {
		t.Fatalf("self: %v", err)
	}
	if _, err := f.svc.Invite(ctx, ana, "not an email"); !errors.Is(err, family.ErrValidation) {
		t.Fatalf("bad email: %v", err)
	}
	if len(f.mail.Sent) != 0 {
		t.Fatalf("mail sent: %+v", f.mail.Sent)
	}
}

func TestReinviteRevokesTheEarlierInvitation(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	first, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	second, err := f.svc.Invite(ctx, ana, "bia@example.com")
	if err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM family_invitations WHERE id = $1::uuid AND revoked_at IS NOT NULL`, first.ID); n != 1 {
		t.Fatal("the first invitation is still pending")
	}
	fam, _ := f.svc.Get(ctx, ana)
	if fam.PendingInvitations != 1 || fam.Invitations[0].ID != second.ID {
		t.Fatalf("family: %+v", fam)
	}
}

func TestInviteCap(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.member(ana, "bia@example.com")
	for _, addr := range []string{"c@example.com", "d@example.com", "e@example.com", "g@example.com"} {
		if _, err := f.svc.Invite(ctx, ana, addr); err != nil {
			t.Fatalf("%s: %v", addr, err)
		}
	}
	sent := len(f.mail.Sent)
	if _, err := f.svc.Invite(ctx, ana, "h@example.com"); !errors.Is(err, family.ErrLimitReached) {
		t.Fatalf("seventh seat: %v", err)
	}
	if len(f.mail.Sent) != sent {
		t.Fatal("a refused invitation was mailed")
	}
	f.now = f.now.Add(7*24*time.Hour + time.Second) // the four invitations expire
	if _, err := f.svc.Invite(ctx, ana, "h@example.com"); err != nil {
		t.Fatalf("after expiry: %v", err)
	}
}

func TestRevokeInvitation(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	carla := f.owner("carla@example.com")
	inv, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	foreign, _ := f.svc.Invite(ctx, carla, "dani@example.com")

	if err := f.svc.RevokeInvitation(ctx, ana, foreign.ID); !errors.Is(err, family.ErrNotFound) {
		t.Fatalf("foreign: %v", err)
	}
	if err := f.svc.RevokeInvitation(ctx, ana, "not-a-uuid"); !errors.Is(err, family.ErrNotFound) {
		t.Fatalf("malformed: %v", err)
	}
	if err := f.svc.RevokeInvitation(ctx, ana, inv.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.RevokeInvitation(ctx, ana, inv.ID); !errors.Is(err, family.ErrNotFound) {
		t.Fatalf("twice: %v", err)
	}
	if fam, _ := f.svc.Get(ctx, ana); fam.PendingInvitations != 0 {
		t.Fatalf("still pending: %+v", fam)
	}
	if !f.audit.Has(ana, audit.InvitationRevoked) {
		t.Fatal("no invitation_revoked audit")
	}
}

func TestInviteThrottle(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	for i := range 20 {
		if _, err := f.svc.Invite(ctx, ana, "bia@example.com"); err != nil {
			t.Fatalf("invite %d: %v", i+1, err)
		}
	}
	var th *family.ThrottledError
	if _, err := f.svc.Invite(ctx, ana, "bia@example.com"); !errors.As(err, &th) || th.RetryAfter <= 0 {
		t.Fatalf("21st: %v", err)
	}
}

func TestAcceptJoinsAsGuardian(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	inv, _ := f.svc.Invite(ctx, ana, "bia@example.com")
	tok := f.lastToken("bia@example.com")

	p, err := f.svc.LookupInvitation(ctx, bia, tok)
	if err != nil {
		t.Fatal(err)
	}
	if p.InviterEmail != "ana@example.com" || p.InvitedEmail != "bia@example.com" || !p.ExpiresAt.Equal(inv.ExpiresAt) {
		t.Fatalf("preview: %+v", p)
	}
	if n := f.count(`SELECT count(*) FROM family_members`); n != 1 {
		t.Fatal("lookup changed the family")
	}
	fam, err := f.svc.AcceptInvitation(ctx, bia, tok)
	if err != nil {
		t.Fatal(err)
	}
	if fam.Role != family.Guardian || len(fam.Members) != 2 || fam.Members[0].AccountID != ana || fam.Invitations != nil {
		t.Fatalf("family: %+v", fam)
	}
	if owner, _ := f.svc.Get(ctx, ana); owner.PendingInvitations != 0 {
		t.Fatalf("still pending: %+v", owner)
	}
	if !f.audit.Has(bia, audit.InvitationAccepted) {
		t.Fatal("no invitation_accepted audit")
	}
}

func TestAcceptMatchesTheNormalizedEmail(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	f.svc.Invite(ctx, ana, "  BIA@Example.com ")
	if _, err := f.svc.AcceptInvitation(ctx, bia, f.lastToken("bia@example.com")); err != nil {
		t.Fatal(err)
	}
}

func TestAcceptRefusesSpentOrStaleTokens(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	carla := f.account("carla@example.com", true)

	f.svc.Invite(ctx, ana, "bia@example.com")
	used := f.lastToken("bia@example.com")
	if _, err := f.svc.AcceptInvitation(ctx, bia, used); err != nil {
		t.Fatal(err)
	}
	revoked, _ := f.svc.Invite(ctx, ana, "carla@example.com")
	revokedTok := f.lastToken("carla@example.com")
	f.svc.RevokeInvitation(ctx, ana, revoked.ID)
	f.svc.Invite(ctx, ana, "carla@example.com")
	expiredTok := f.lastToken("carla@example.com")
	f.now = f.now.Add(7*24*time.Hour + time.Second)

	for name, tc := range map[string]struct{ who, tok string }{
		"unknown": {carla, "nope"},
		"used":    {bia, used},
		"revoked": {carla, revokedTok},
		"expired": {carla, expiredTok},
	} {
		if _, err := f.svc.LookupInvitation(ctx, tc.who, tc.tok); !errors.Is(err, family.ErrInvalidToken) {
			t.Errorf("lookup %s: %v", name, err)
		}
		if _, err := f.svc.AcceptInvitation(ctx, tc.who, tc.tok); !errors.Is(err, family.ErrInvalidToken) {
			t.Errorf("accept %s: %v", name, err)
		}
	}
}

func TestAcceptRefusals(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.svc.Invite(ctx, ana, "bia@example.com")
	tok := f.lastToken("bia@example.com")
	unspent := func() {
		t.Helper()
		if n := f.count(`SELECT count(*) FROM family_invitations WHERE accepted_at IS NOT NULL`); n != 0 {
			t.Fatal("a refused accept spent the token")
		}
	}

	carla := f.account("carla@example.com", true)
	for _, call := range []func() error{
		func() error { _, err := f.svc.LookupInvitation(ctx, carla, tok); return err },
		func() error { _, err := f.svc.AcceptInvitation(ctx, carla, tok); return err },
	} {
		if err := call(); !errors.Is(err, family.ErrInvitationEmailMismatch) {
			t.Fatalf("mismatch: %v", err)
		}
	}
	unspent()

	bia := f.account("bia@example.com", false)
	if _, err := f.svc.AcceptInvitation(ctx, bia, tok); !errors.Is(err, family.ErrEmailUnverified) {
		t.Fatalf("unverified: %v", err)
	}
	f.pool.Exec(ctx, `UPDATE accounts SET email_verified_at = now() WHERE id = $1::uuid`, bia)

	other := f.owner("dani@example.com")
	f.pool.Exec(ctx, `UPDATE family_members SET account_id = $1::uuid WHERE account_id = $2::uuid`, bia, other)
	if _, err := f.svc.AcceptInvitation(ctx, bia, tok); !errors.Is(err, family.ErrAlreadyInFamily) {
		t.Fatalf("in a family: %v", err)
	}
	f.pool.Exec(ctx, `DELETE FROM family_members WHERE account_id = $1::uuid`, bia)
	unspent()

	for _, addr := range []string{"e@example.com", "g@example.com", "h@example.com", "i@example.com", "j@example.com"} {
		f.member(ana, addr) // 6 members, the invitation's seat included
	}
	if _, err := f.svc.AcceptInvitation(ctx, bia, tok); !errors.Is(err, family.ErrLimitReached) {
		t.Fatalf("full: %v", err)
	}
	unspent()
}

func TestConcurrentAcceptsAddOneGuardian(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	f.svc.Invite(ctx, ana, "bia@example.com")
	tok := f.lastToken("bia@example.com")
	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i := range errs {
		wg.Go(func() { _, errs[i] = f.svc.AcceptInvitation(ctx, bia, tok) })
	}
	wg.Wait()
	if (errs[0] == nil) == (errs[1] == nil) {
		t.Fatalf("want exactly one success: %v / %v", errs[0], errs[1])
	}
	if n := f.count(`SELECT count(*) FROM family_members`); n != 2 {
		t.Fatalf("%d members", n)
	}
}

func TestTokenThrottle(t *testing.T) {
	f := newFixture(t)
	bia := f.account("bia@example.com", true)
	for range 10 {
		f.svc.LookupInvitation(ctx, bia, "nope")
	}
	var th *family.ThrottledError
	if _, err := f.svc.AcceptInvitation(ctx, bia, "nope"); !errors.As(err, &th) {
		t.Fatalf("11th: %v", err)
	}
}
