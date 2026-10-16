package staff_test

import (
	"errors"
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func TestGrantAndRevokeAdmin(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")

	id, err := f.svc.GrantAdmin(ctx, " Ana@Example.com ")
	if err != nil || id != ana {
		t.Fatalf("grant: %q %v", id, err)
	}
	if roles, err := f.svc.Roles(ctx, ana); err != nil || !slices.Equal(roles, []staff.Role{staff.Admin}) {
		t.Fatalf("roles %v %v", roles, err)
	}
	if _, err := f.svc.GrantAdmin(ctx, "ana@example.com"); err != nil {
		t.Fatalf("a second grant: %v", err)
	}
	if !f.audit.Has(ana, audit.AdminGranted) || f.audited(audit.AdminGranted) != 1 {
		t.Fatal("admin_granted must be recorded once, under the account")
	}
	if _, err := f.svc.GrantAdmin(ctx, "nobody@example.com"); !errors.Is(err, staff.ErrAccountNotFound) {
		t.Fatalf("unknown email: %v", err)
	}

	if id, err := f.svc.RevokeAdmin(ctx, "ana@example.com"); err != nil || id != ana {
		t.Fatalf("revoke: %q %v", id, err)
	}
	if roles, err := f.svc.Roles(ctx, ana); err != nil || roles == nil || len(roles) != 0 {
		t.Fatalf("roles after revoke %v %v", roles, err)
	}
	if !f.audit.Has(ana, audit.AdminRevoked) {
		t.Fatal("no admin_revoked audit")
	}
	if _, err := f.svc.RevokeAdmin(ctx, "ana@example.com"); !errors.Is(err, staff.ErrNotAdmin) {
		t.Fatalf("revoking a non-admin: %v", err)
	}
	if _, err := f.svc.RevokeAdmin(ctx, "nobody@example.com"); !errors.Is(err, staff.ErrAccountNotFound) {
		t.Fatalf("unknown email: %v", err)
	}
}

func TestRolesAreIndependent(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	caio := f.account("caio@example.com")
	for _, c := range []struct {
		id   string
		role staff.Role
		want bool
	}{
		{admin, staff.Admin, true}, {admin, staff.Curator, false},
		{bia, staff.Curator, true}, {bia, staff.Admin, false},
		{caio, staff.Curator, false},
	} {
		if ok := f.has(c.id, c.role); ok != c.want {
			t.Errorf("%s %s: %v", c.id, c.role, ok)
		}
	}
	if roles, _ := f.svc.Roles(ctx, bia); !slices.Equal(roles, []staff.Role{staff.Curator}) {
		t.Fatalf("curator roles %v", roles)
	}
	if roles, _ := f.svc.Roles(ctx, caio); roles == nil || len(roles) != 0 {
		t.Fatalf("plain guardian roles %v", roles)
	}
}

func TestFirstRoleFollowsTheGivenOrder(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', $2)`, ana, f.now)
	bia := f.curator("bia@example.com", staff.MaePai)
	for _, c := range []struct {
		id    string
		roles []staff.Role
		want  staff.Role
	}{
		{ana, []staff.Role{staff.Moderator, staff.Admin}, staff.Moderator},
		{ana, []staff.Role{staff.Admin, staff.Moderator}, staff.Admin},
		{ana, []staff.Role{staff.Curator}, ""},
		{bia, []staff.Role{staff.Moderator, staff.Admin}, ""},
	} {
		if got, err := f.svc.FirstRole(ctx, c.id, c.roles...); err != nil || got != c.want {
			t.Errorf("%s %v: %q %v, want %q", c.id, c.roles, got, err, c.want)
		}
	}
}
