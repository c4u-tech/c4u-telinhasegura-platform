package family_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

var lia = family.MinorInput{Nickname: "Lia", Avatar: "fox", AgeBand: family.Age5To8}

func ptr[T any](v T) *T { return &v }

func TestCreateMinorRecordsConsent(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")

	m, err := f.svc.CreateMinor(ctx, bia, lia, family.ConsentPolicyVersion)
	if err != nil {
		t.Fatal(err)
	}
	if m.ID == "" || m.Nickname != "Lia" || m.Avatar != "fox" || m.AgeBand != family.Age5To8 || !m.CreatedAt.Equal(f.now) {
		t.Fatalf("minor: %+v", m)
	}
	var grantedBy, version string
	var grantedAt time.Time
	if err := f.pool.QueryRow(ctx, `SELECT granted_by::text, policy_version, granted_at FROM minor_consents WHERE minor_id = $1::uuid`,
		m.ID).Scan(&grantedBy, &version, &grantedAt); err != nil {
		t.Fatal(err)
	}
	if grantedBy != bia || version != family.ConsentPolicyVersion || !grantedAt.Equal(f.now) {
		t.Fatalf("consent: %s %s %s", grantedBy, version, grantedAt)
	}
	if fam, _ := f.svc.Get(ctx, ana); len(fam.Minors) != 1 || fam.Minors[0].ID != m.ID {
		t.Fatalf("family: %+v", fam)
	}
	if !f.audit.Has(bia, audit.MinorCreated) {
		t.Fatal("no minor_created audit")
	}
}

func TestCreateMinorNeedsCurrentConsent(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	if _, err := f.svc.CreateMinor(ctx, ana, lia, ""); !errors.Is(err, family.ErrValidation) {
		t.Fatalf("missing: %v", err)
	}
	if _, err := f.svc.CreateMinor(ctx, ana, lia, "2025-01-01"); !errors.Is(err, family.ErrPolicyOutdated) {
		t.Fatalf("outdated: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM minors`) + f.count(`SELECT count(*) FROM minor_consents`); n != 0 {
		t.Fatal("a refused minor left rows")
	}
}

func TestCreateMinorNeedsAVerifiedEmail(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	f.pool.Exec(ctx, `UPDATE accounts SET email_verified_at = NULL WHERE id = $1::uuid`, ana)
	if _, err := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion); !errors.Is(err, family.ErrEmailUnverified) {
		t.Fatalf("got %v", err)
	}
}

func TestMinorValues(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bad := map[string]family.MinorInput{
		"empty nickname": {Nickname: "", Avatar: "fox", AgeBand: family.Age5To8},
		"blank nickname": {Nickname: "   ", Avatar: "fox", AgeBand: family.Age5To8},
		"21 runes":       {Nickname: strings.Repeat("a", 21), Avatar: "fox", AgeBand: family.Age5To8},
		"control char":   {Nickname: "Li\x00a", Avatar: "fox", AgeBand: family.Age5To8},
		"unknown avatar": {Nickname: "Lia", Avatar: "dragon", AgeBand: family.Age5To8},
		"unknown band":   {Nickname: "Lia", Avatar: "fox", AgeBand: "13-17"},
	}
	for name, in := range bad {
		if _, err := f.svc.CreateMinor(ctx, ana, in, family.ConsentPolicyVersion); !errors.Is(err, family.ErrValidation) {
			t.Errorf("%s: %v", name, err)
		}
	}
	decomposed := " João " // "João" typed as NFD, padded
	m, err := f.svc.CreateMinor(ctx, ana, family.MinorInput{Nickname: decomposed, Avatar: "owl", AgeBand: family.AgeUpTo4}, family.ConsentPolicyVersion)
	if err != nil || m.Nickname != "João" {
		t.Fatalf("NFD: %q %v", m.Nickname, err)
	}
	if _, err := f.svc.CreateMinor(ctx, ana, family.MinorInput{Nickname: strings.Repeat("🦊", 20), Avatar: "fox", AgeBand: family.Age9To12}, family.ConsentPolicyVersion); err != nil {
		t.Fatalf("20 emoji: %v", err)
	}
}

func TestMinorCap(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	for i := range 10 {
		if _, err := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion); err != nil {
			t.Fatalf("minor %d: %v", i+1, err)
		}
	}
	if _, err := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion); !errors.Is(err, family.ErrLimitReached) {
		t.Fatalf("11th: %v", err)
	}
}

func TestUpdateMinor(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	m, _ := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion)
	f.now = f.now.Add(time.Hour)

	got, err := f.svc.UpdateMinor(ctx, ana, m.ID, family.MinorPatch{Nickname: ptr("Liazinha")})
	if err != nil {
		t.Fatal(err)
	}
	if got.Nickname != "Liazinha" || got.Avatar != "fox" || got.AgeBand != family.Age5To8 || !got.UpdatedAt.Equal(f.now) || !got.CreatedAt.Equal(m.CreatedAt) {
		t.Fatalf("updated: %+v", got)
	}
	got, err = f.svc.UpdateMinor(ctx, ana, m.ID, family.MinorPatch{AgeBand: ptr(family.Age9To12), Avatar: ptr("owl")})
	if err != nil || got.AgeBand != family.Age9To12 || got.Avatar != "owl" {
		t.Fatalf("band and avatar: %+v %v", got, err)
	}
	var band, avatar string
	f.pool.QueryRow(ctx, `SELECT age_band, avatar FROM minors WHERE id = $1::uuid`, m.ID).Scan(&band, &avatar)
	if band != "9-12" || avatar != "owl" {
		t.Fatalf("stored: %s %s", band, avatar)
	}
	if _, err := f.svc.UpdateMinor(ctx, ana, m.ID, family.MinorPatch{}); !errors.Is(err, family.ErrValidation) {
		t.Fatalf("empty patch: %v", err)
	}
	if _, err := f.svc.UpdateMinor(ctx, ana, m.ID, family.MinorPatch{AgeBand: ptr(family.AgeBand("adult"))}); !errors.Is(err, family.ErrValidation) {
		t.Fatalf("bad band: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM minor_consents WHERE minor_id = $1::uuid AND granted_at = $2`, m.ID, m.CreatedAt); n != 1 {
		t.Fatal("an update touched the consent")
	}
	if !f.audit.Has(ana, audit.MinorUpdated) {
		t.Fatal("no minor_updated audit")
	}
}

func TestDeleteMinorKeepsTheLedger(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")
	m, _ := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion)
	f.now = f.now.Add(time.Hour)

	if err := f.svc.DeleteMinor(ctx, bia, m.ID); err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM minors`); n != 0 {
		t.Fatal("the profile survived")
	}
	var withdrawnBy, version string
	var withdrawnAt time.Time
	if err := f.pool.QueryRow(ctx, `SELECT withdrawn_by::text, withdrawn_at, policy_version FROM minor_consents WHERE minor_id = $1::uuid`,
		m.ID).Scan(&withdrawnBy, &withdrawnAt, &version); err != nil {
		t.Fatal(err)
	}
	if withdrawnBy != bia || !withdrawnAt.Equal(f.now) || version != family.ConsentPolicyVersion {
		t.Fatalf("ledger: %s %s %s", withdrawnBy, withdrawnAt, version)
	}
	if !f.audit.Has(bia, audit.MinorDeleted) {
		t.Fatal("no minor_deleted audit")
	}
}

func TestMinorsOfAnotherFamilyAreNotFound(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	carla := f.owner("carla@example.com")
	m, _ := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion)
	for name, id := range map[string]string{"foreign": m.ID, "malformed": "nope", "unknown": "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.UpdateMinor(ctx, carla, id, family.MinorPatch{Avatar: ptr("owl")}); !errors.Is(err, family.ErrNotFound) {
			t.Errorf("update %s: %v", name, err)
		}
		if err := f.svc.DeleteMinor(ctx, carla, id); !errors.Is(err, family.ErrNotFound) {
			t.Errorf("delete %s: %v", name, err)
		}
	}
}

func TestRemovalWinsOverAnInFlightWrite(t *testing.T) {
	f := newFixture(t)
	ana := f.owner("ana@example.com")
	bia := f.member(ana, "bia@example.com")

	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	// Hold the family lock, as the owner's removal does.
	if _, err := tx.Exec(ctx, `SELECT 1 FROM families fa JOIN family_members m ON m.family_id = fa.id
		WHERE m.account_id = $1::uuid FOR UPDATE OF fa`, ana); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := f.svc.CreateMinor(ctx, bia, lia, family.ConsentPolicyVersion)
		done <- err
	}()
	f.waitForLockWaiter()
	if _, err := tx.Exec(ctx, `DELETE FROM family_members WHERE account_id = $1::uuid`, bia); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, family.ErrNoFamily) {
		t.Fatalf("in-flight write: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM minors`); n != 0 {
		t.Fatal("a removed guardian created a minor")
	}
}

func TestMinorRoutesCheckMembershipBeforeTheBody(t *testing.T) {
	f := newFixture(t)
	bad := family.MinorInput{Nickname: "", Avatar: "dragon", AgeBand: "x"}
	loner := f.account("loner@example.com", true)
	if _, err := f.svc.CreateMinor(ctx, loner, bad, "old"); !errors.Is(err, family.ErrNoFamily) {
		t.Fatalf("create without family: %v", err)
	}
	if _, err := f.svc.UpdateMinor(ctx, loner, "00000000-0000-0000-0000-000000000000", family.MinorPatch{}); !errors.Is(err, family.ErrNoFamily) {
		t.Fatalf("update without family: %v", err)
	}
	ana := f.owner("ana@example.com")
	f.pool.Exec(ctx, `UPDATE accounts SET email_verified_at = NULL WHERE id = $1::uuid`, ana)
	if _, err := f.svc.CreateMinor(ctx, ana, bad, "old"); !errors.Is(err, family.ErrEmailUnverified) {
		t.Fatalf("create unverified: %v", err)
	}
}

func TestReturnedTimesMatchStoredTimes(t *testing.T) {
	f := newFixture(t)
	f.now = time.Date(2026, 10, 3, 12, 0, 0, 123456789, time.UTC)
	ana := f.owner("ana@example.com")
	m, err := f.svc.CreateMinor(ctx, ana, lia, family.ConsentPolicyVersion)
	if err != nil {
		t.Fatal(err)
	}
	inv, err := f.svc.Invite(ctx, ana, "bia@example.com")
	if err != nil {
		t.Fatal(err)
	}
	fam, _ := f.svc.Get(ctx, ana)
	if len(fam.Minors) != 1 || !fam.Minors[0].CreatedAt.Equal(m.CreatedAt) || !fam.Minors[0].UpdatedAt.Equal(m.UpdatedAt) {
		t.Fatalf("minor: posted %+v, read %+v", m, fam.Minors)
	}
	if len(fam.Invitations) != 1 || !fam.Invitations[0].ExpiresAt.Equal(inv.ExpiresAt) {
		t.Fatalf("invitation: posted %v, read %+v", inv.ExpiresAt, fam.Invitations)
	}
}
