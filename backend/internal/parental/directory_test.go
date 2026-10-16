package parental_test

import (
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func (f *fixture) seenAt(deviceID string, at time.Time) {
	f.t.Helper()
	if _, err := f.pool.Exec(ctx, `UPDATE devices SET last_seen_at = $2 WHERE id = $1::uuid`, deviceID, at); err != nil {
		f.t.Fatal(err)
	}
}

func TestFamilyDevicesCarryNoLabelAndSkipIdle(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	f.linked(owner, lia)
	f.now = f.now.Add(time.Minute)
	f.linked(owner, lia)
	fam := f.familyID(owner)
	guardian, err := f.svc.Devices(ctx, owner)
	if err != nil || len(guardian) != 2 {
		t.Fatalf("devices %+v %v", guardian, err)
	}

	got, err := f.svc.FamilyDevices(ctx, fam)
	if err != nil || len(got) != 2 {
		t.Fatalf("family devices %+v %v", got, err)
	}
	for i, d := range got {
		if d.ID != guardian[i].ID || !d.LinkedAt.Equal(guardian[i].LinkedAt) || !d.LastSeenAt.Equal(guardian[i].LastSeenAt) {
			t.Fatalf("device %d: %+v, want %+v", i, d, guardian[i])
		}
	}
	f.seenAt(got[0].ID, f.now.Add(-180*24*time.Hour+time.Second))
	f.seenAt(got[1].ID, f.now.Add(-180*24*time.Hour))
	if list, _ := f.svc.FamilyDevices(ctx, fam); len(list) != 1 || list[0].ID != got[0].ID {
		t.Fatalf("a device seen exactly 180 days ago must be left out: %+v", list)
	}
	if n, err := f.svc.CountActiveDevices(ctx); err != nil || n != 1 {
		t.Fatalf("active devices %d %v", n, err)
	}
	if list, err := f.svc.FamilyDevices(ctx, f.familyID(f.owner("teo@example.com"))); err != nil || list == nil || len(list) != 0 {
		t.Fatalf("no device must be an empty, non-nil list: %+v %v", list, err)
	}
}

func TestUnlinkInFamily(t *testing.T) {
	f := newFixture(t)
	owner := f.owner("ana@example.com")
	lia := f.minor(owner, "Lia")
	f.withPIN(owner)
	first := f.linked(owner, lia)
	f.now = f.now.Add(time.Minute) // distinct link times: FamilyDevices lists them in this order
	second := f.linked(owner, lia)
	fam := f.familyID(owner)
	list, _ := f.svc.FamilyDevices(ctx, fam)
	other := f.familyID(f.owner("teo@example.com"))

	if err := f.svc.UnlinkInFamily(ctx, fam, list[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.AuthenticateDevice(ctx, first.Token); !errors.Is(err, parental.ErrUnauthenticated) {
		t.Fatalf("the unlinked token: %v", err)
	}
	if _, err := f.svc.AuthenticateDevice(ctx, second.Token); err != nil {
		t.Fatalf("the other device: %v", err)
	}
	for name, c := range map[string][2]string{
		"already gone":     {fam, list[0].ID},
		"another family":   {other, list[1].ID},
		"malformed device": {fam, "abc"},
		"malformed family": {"abc", list[1].ID},
	} {
		if err := f.svc.UnlinkInFamily(ctx, c[0], c[1]); !errors.Is(err, parental.ErrNotFound) {
			t.Errorf("%s: %v, want ErrNotFound", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM devices WHERE id = $1::uuid`, list[1].ID); n != 1 {
		t.Fatal("a refused unlink deleted a device")
	}
	for _, e := range f.audit.Entries {
		if e.Event == audit.DeviceUnlinked {
			t.Fatal("a staff unlink must not record the guardian's device_unlinked")
		}
	}
}
