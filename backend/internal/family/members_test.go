package family_test

import (
	"errors"
	"sync"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestCreateMakesTheCallerOwner(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com", true)

	fam, err := f.svc.Create(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	if fam.Role != family.Owner || len(fam.Members) != 1 {
		t.Fatalf("family: %+v", fam)
	}
	if m := fam.Members[0]; m.AccountID != ana || m.Email != "ana@example.com" || m.Role != family.Owner || !m.JoinedAt.Equal(f.now) {
		t.Fatalf("member: %+v", m)
	}
	if fam.Invitations == nil || fam.PendingInvitations != 0 || len(fam.Minors) != 0 {
		t.Fatalf("owner view: %+v", fam)
	}
	got, err := f.svc.Get(ctx, ana)
	if err != nil || got.ID != fam.ID || got.Role != family.Owner {
		t.Fatalf("get: %+v %v", got, err)
	}
	if !f.audit.Has(ana, audit.FamilyCreated) {
		t.Fatal("no family_created audit")
	}
}

func TestCreateRefusesAnUnverifiedEmail(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com", false)
	if _, err := f.svc.Create(ctx, ana); !errors.Is(err, family.ErrEmailUnverified) {
		t.Fatalf("got %v", err)
	}
	if n := f.count(`SELECT count(*) FROM families`); n != 0 {
		t.Fatalf("%d families", n)
	}
}

func TestCreateRefusesASecondFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	if _, err := f.svc.Create(ctx, ana); !errors.Is(err, family.ErrAlreadyInFamily) {
		t.Fatalf("got %v", err)
	}
	if n := f.count(`SELECT count(*) FROM families`); n != 1 {
		t.Fatalf("%d families", n)
	}
}

func TestConcurrentCreatesYieldOneFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com", true)
	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i := range errs {
		wg.Go(func() { _, errs[i] = f.svc.Create(ctx, ana) })
	}
	wg.Wait()
	ok, conflict := 0, 0
	for _, err := range errs {
		switch {
		case err == nil:
			ok++
		case errors.Is(err, family.ErrAlreadyInFamily):
			conflict++
		default:
			t.Fatal(err)
		}
	}
	if ok != 1 || conflict != 1 || f.count(`SELECT count(*) FROM family_members`) != 1 {
		t.Fatalf("ok=%d conflict=%d", ok, conflict)
	}
}

func TestTheDatabaseHoldsOneOwnerPerFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.account("bia@example.com", true)
	_, err := f.pool.Exec(ctx, `INSERT INTO family_members (family_id, account_id, role, joined_at)
		SELECT family_id, $2::uuid, 'owner', now() FROM family_members WHERE account_id = $1::uuid`, ana, bia)
	if err == nil {
		t.Fatal("a second owner was accepted")
	}
}

func TestGetWithoutAFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com", true)
	if _, err := f.svc.Get(ctx, ana); !errors.Is(err, family.ErrNoFamily) {
		t.Fatalf("got %v", err)
	}
}

func TestRemoveGuardian(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.guardian(ana, "bia@example.com")
	carla := f.member(ana, "carla@example.com")
	outsider := f.account("dani@example.com", true)

	if err := f.svc.RemoveGuardian(ctx, carla, bia); !errors.Is(err, family.ErrNotOwner) {
		t.Fatalf("guardian removes: %v", err)
	}
	for name, id := range map[string]string{"self": ana, "outsider": outsider, "malformed": "x"} {
		if err := f.svc.RemoveGuardian(ctx, ana, id); !errors.Is(err, family.ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if err := f.svc.RemoveGuardian(ctx, ana, bia); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Get(ctx, bia); !errors.Is(err, family.ErrNoFamily) {
		t.Fatalf("removed guardian still sees the family: %v", err)
	}
	if msgs := f.mail.To("bia@example.com"); len(msgs) != 2 { // invitation + removal notice
		t.Fatalf("mail: %+v", msgs)
	}
	if !f.audit.Has(ana, audit.GuardianRemoved) {
		t.Fatal("no guardian_removed audit")
	}
}

func TestLeave(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")
	if err := f.svc.Leave(ctx, ana); !errors.Is(err, family.ErrOwnerMustTransfer) {
		t.Fatalf("owner leaves: %v", err)
	}
	if err := f.svc.Leave(ctx, bia); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Get(ctx, bia); !errors.Is(err, family.ErrNoFamily) {
		t.Fatalf("after leaving: %v", err)
	}
	if !f.audit.Has(bia, audit.GuardianLeft) {
		t.Fatal("no guardian_left audit")
	}
}

func TestTransferOwnership(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")
	outsider := f.account("dani@example.com", true)

	for name, id := range map[string]string{"self": ana, "outsider": outsider, "malformed": "x"} {
		if _, err := f.svc.TransferOwnership(ctx, ana, id); !errors.Is(err, family.ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if got, _ := f.svc.Get(ctx, ana); got.Role != family.Owner {
		t.Fatal("a refused transfer demoted the owner")
	}
	fam, err := f.svc.TransferOwnership(ctx, ana, bia)
	if err != nil {
		t.Fatal(err)
	}
	if fam.Role != family.Guardian || fam.Invitations != nil || fam.Members[0].AccountID != bia {
		t.Fatalf("returned: %+v", fam)
	}
	if got, _ := f.svc.Get(ctx, bia); got.Role != family.Owner {
		t.Fatalf("new owner: %+v", got)
	}
	if len(f.mail.To("ana@example.com")) != 1 || len(f.mail.To("bia@example.com")) != 1 {
		t.Fatal("both sides must get a notice")
	}
	if !f.audit.Has(ana, audit.OwnershipTransferred) {
		t.Fatal("no ownership_transferred audit")
	}
}

func TestDeleteFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")
	f.svc.CreateMinor(ctx, ana, family.MinorInput{Nickname: "Lia", Avatar: "fox", AgeBand: family.Age5To8}, family.ConsentPolicyVersion)
	f.svc.CreateMinor(ctx, ana, family.MinorInput{Nickname: "Teo", Avatar: "owl", AgeBand: family.AgeUpTo4}, family.ConsentPolicyVersion)
	f.svc.Invite(ctx, ana, "carla@example.com")

	if err := f.svc.Delete(ctx, bia); !errors.Is(err, family.ErrNotOwner) {
		t.Fatalf("guardian deletes: %v", err)
	}
	if err := f.svc.Delete(ctx, ana); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{ana, bia} {
		if _, err := f.svc.Get(ctx, id); !errors.Is(err, family.ErrNoFamily) {
			t.Fatalf("still in a family: %v", err)
		}
	}
	for _, table := range []string{"families", "family_members", "family_invitations", "minors"} {
		if n := f.count(`SELECT count(*) FROM ` + table); n != 0 {
			t.Errorf("%s keeps %d rows", table, n)
		}
	}
	if n := f.count(`SELECT count(*) FROM minor_consents WHERE withdrawn_by = $1::uuid AND withdrawn_at = $2`, ana, f.now); n != 2 {
		t.Fatalf("%d consents withdrawn", n)
	}
	if len(f.mail.To("bia@example.com")) != 1 || len(f.mail.To("ana@example.com")) != 0 {
		t.Fatal("the deletion notice goes to former guardians only")
	}
	if !f.audit.Has(ana, audit.FamilyDeleted) {
		t.Fatal("no family_deleted audit")
	}
	if _, err := f.svc.Create(ctx, ana); err != nil {
		t.Fatalf("a new family after deletion: %v", err)
	}
}

func TestDeleteAsSoleGuardianRefusesAFamilyWithOtherGuardians(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")

	if err := f.svc.DeleteAsSoleGuardian(ctx, ana); !errors.Is(err, family.ErrOtherGuardians) {
		t.Fatalf("with another guardian: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM family_members`); n != 2 {
		t.Fatalf("the refusal changed the family: %d members", n)
	}
	if f.audit.Has(ana, audit.FamilyDeleted) || len(f.mail.To("bia@example.com")) != 0 {
		t.Fatal("the refusal audited or notified a deletion")
	}
	if err := f.svc.Leave(ctx, bia); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.DeleteAsSoleGuardian(ctx, ana); err != nil {
		t.Fatalf("as the only guardian: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM families`); n != 0 {
		t.Fatal("the family survived")
	}
}

func TestNoticesAreBestEffortAfterTheCommit(t *testing.T) {
	t.Run("delete tells every guardian", func(t *testing.T) {
		f := newFixture(t)
		ana := f.owner("ana@example.com")
		f.member(ana, "bia@example.com")
		f.member(ana, "carla@example.com")
		f.failMailTo("bia@example.com")

		if err := f.svc.Delete(ctx, ana); err != nil {
			t.Fatalf("delete: %v", err)
		}
		if len(f.mail.To("carla@example.com")) != 1 {
			t.Fatal("the second guardian was never attempted")
		}
		if n := f.count(`SELECT count(*) FROM families`); n != 0 {
			t.Fatal("the family survived")
		}
	})
	t.Run("transfer tells both owners", func(t *testing.T) {
		f := newFixture(t)
		ana := f.owner("ana@example.com")
		bia := f.member(ana, "bia@example.com")
		f.failMailTo("bia@example.com")

		fam, err := f.svc.TransferOwnership(ctx, ana, bia)
		if err != nil || fam.Role != family.Guardian {
			t.Fatalf("transfer: %+v %v", fam, err)
		}
		if len(f.mail.To("ana@example.com")) != 1 {
			t.Fatal("the old owner was never attempted")
		}
	})
	t.Run("remove succeeds", func(t *testing.T) {
		f := newFixture(t)
		ana := f.owner("ana@example.com")
		bia := f.member(ana, "bia@example.com")
		f.failMailTo("bia@example.com")

		if err := f.svc.RemoveGuardian(ctx, ana, bia); err != nil {
			t.Fatalf("remove: %v", err)
		}
		if n := f.count(`SELECT count(*) FROM family_members WHERE account_id = $1::uuid`, bia); n != 0 {
			t.Fatal("the guardian stayed")
		}
	})
}
