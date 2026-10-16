package family_test

import (
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func (f *fixture) addMinor(accountID string) {
	f.t.Helper()
	if _, err := f.svc.CreateMinor(ctx, accountID,
		family.MinorInput{Nickname: "Lia", Avatar: "fox", AgeBand: family.Age5To8}, family.ConsentPolicyVersion); err != nil {
		f.t.Fatal(err)
	}
}

func TestMembershipAndMinorCount(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")
	f.addMinor(ana)
	f.addMinor(ana)
	teo := f.owner("teo@example.com")

	m, ok, err := f.svc.Membership(ctx, ana)
	if err != nil || !ok || m.Role != family.Owner || m.FamilyID == "" {
		t.Fatalf("owner %+v %v %v", m, ok, err)
	}
	g, ok, err := f.svc.Membership(ctx, bia)
	if err != nil || !ok || g != (family.Membership{FamilyID: m.FamilyID, Role: family.Guardian}) {
		t.Fatalf("guardian %+v %v %v", g, ok, err)
	}
	for _, id := range []string{f.account("caio@example.com", true), "abc"} {
		if _, ok, err := f.svc.Membership(ctx, id); err != nil || ok {
			t.Fatalf("%q without a family: %v %v", id, ok, err)
		}
	}
	if n, err := f.svc.MinorCount(ctx, m.FamilyID); err != nil || n != 2 {
		t.Fatalf("minors %d %v", n, err)
	}
	other, _, _ := f.svc.Membership(ctx, teo)
	if n, err := f.svc.MinorCount(ctx, other.FamilyID); err != nil || n != 0 {
		t.Fatalf("another family's minors %d %v", n, err)
	}
}

func TestCountFamiliesAndMinors(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	teo := f.owner("teo@example.com")
	f.addMinor(ana)
	f.addMinor(teo)
	f.addMinor(teo)
	if n, err := f.svc.CountFamilies(ctx); err != nil || n != 2 {
		t.Fatalf("families %d %v", n, err)
	}
	if n, err := f.svc.CountMinors(ctx); err != nil || n != 3 {
		t.Fatalf("minors %d %v", n, err)
	}
}
