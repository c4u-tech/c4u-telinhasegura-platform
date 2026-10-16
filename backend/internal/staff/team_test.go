package staff_test

import (
	"errors"
	"maps"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func ptr[T any](v T) *T { return &v }

// sameRoles compares held roles field by field, times with Equal. A want
// of none needs an empty, non-nil got.
func sameRoles(got []staff.HeldRole, want ...staff.HeldRole) bool {
	if got == nil || len(got) != len(want) {
		return false
	}
	for i, w := range want {
		g := got[i]
		if g.Role != w.Role || !g.GrantedAt.Equal(w.GrantedAt) || g.DisplayRole != w.DisplayRole ||
			g.VerifiedProfessional != w.VerifiedProfessional {
			return false
		}
	}
	return true
}

func TestGrantAModeratorAndACurator(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	bia := f.account("bia@example.com")

	m, err := f.svc.Grant(ctx, admin, staff.GrantInput{Email: " Bia@Example.com ", Role: staff.Moderator, Reason: "  Cuida dos retidos.  "})
	if err != nil {
		t.Fatal(err)
	}
	if m.AccountID != bia || m.Email != "bia@example.com" || !sameRoles(m.Roles, staff.HeldRole{Role: staff.Moderator, GrantedAt: f.now}) {
		t.Fatalf("member %+v", m)
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid AND role = 'moderator'
		AND display_role IS NULL AND NOT verified_professional AND granted_by = $2::uuid`, bia, admin); n != 1 {
		t.Fatal("the moderator role is not stored with its grantor and no displayed role")
	}
	want := audit.Action{Actor: admin, ActorRole: "admin", Event: audit.ModeratorAppointed,
		SubjectKind: audit.SubjectAccount, SubjectID: bia, Reason: "Cuida dos retidos."}
	if a, ok := f.audit.LastAction(audit.ModeratorAppointed); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}

	f.now = f.now.Add(time.Hour)
	m, err = f.svc.Grant(ctx, admin, staff.GrantInput{Email: "bia@example.com", Role: staff.Curator, DisplayRole: staff.Pedagogo,
		VerifiedProfessional: ptr(true), Reason: "Pedagoga da equipe."})
	if err != nil {
		t.Fatal(err)
	}
	if !sameRoles(m.Roles,
		staff.HeldRole{Role: staff.Curator, GrantedAt: f.now, DisplayRole: staff.Pedagogo, VerifiedProfessional: true},
		staff.HeldRole{Role: staff.Moderator, GrantedAt: f.now.Add(-time.Hour)}) {
		t.Fatalf("roles by name %+v", m.Roles)
	}
	a, _ := f.audit.LastAction(audit.CuratorAppointed)
	if a.SubjectID != bia || a.Actor != admin ||
		!maps.Equal(a.Metadata, map[string]string{"display_role": "pedagogo", "verified_professional": "true"}) {
		t.Fatalf("curator action %+v", a)
	}
}

func TestGrantRefusals(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	f.account("bia@example.com")
	f.unverified("caio@example.com")
	in := func(email string, r staff.Role) staff.GrantInput {
		return staff.GrantInput{Email: email, Role: r, Reason: "Motivo válido."}
	}
	why := func(g staff.GrantInput, reason string) staff.GrantInput { g.Reason = reason; return g }
	as := func(g staff.GrantInput, d staff.DisplayRole, v *bool) staff.GrantInput {
		g.DisplayRole, g.VerifiedProfessional = d, v
		return g
	}
	for name, c := range map[string]struct {
		in   staff.GrantInput
		want error
	}{
		"no reason":                    {why(in("bia@example.com", staff.Moderator), ""), staff.ErrReasonRequired},
		"a blank reason":               {why(in("bia@example.com", staff.Moderator), "   \t "), staff.ErrReasonRequired},
		"two runes":                    {why(in("bia@example.com", staff.Moderator), "  ok  "), staff.ErrReasonRequired},
		"201 runes":                    {why(in("bia@example.com", staff.Moderator), strings.Repeat("é", 201)), staff.ErrReasonRequired},
		"the reason before the role":   {why(in("bia@example.com", staff.Admin), ""), staff.ErrReasonRequired},
		"the reason before the lookup": {why(in("nobody@example.com", staff.Moderator), ""), staff.ErrReasonRequired},
		"admin":                        {in("bia@example.com", staff.Admin), staff.ErrAdminCLIOnly},
		"an unknown role":              {in("bia@example.com", "owner"), staff.ErrValidation},
		"a moderator's displayed role": {as(in("bia@example.com", staff.Moderator), staff.MaePai, nil), staff.ErrValidation},
		"a moderator's verified flag":  {as(in("bia@example.com", staff.Moderator), "", ptr(false)), staff.ErrValidation},
		"an unverified professional":   {as(in("bia@example.com", staff.Curator), staff.Pedagogo, ptr(false)), staff.ErrValidation},
		"an unknown displayed role":    {as(in("bia@example.com", staff.Curator), "astronauta", ptr(true)), staff.ErrValidation},
		"a curator without a role":     {in("bia@example.com", staff.Curator), staff.ErrValidation},
		"an unknown email":             {in("nobody@example.com", staff.Moderator), staff.ErrAccountNotFound},
		"an unverified email":          {in("caio@example.com", staff.Moderator), staff.ErrEmailUnverified},
		"themself, padded":             {in(" ANA@Example.com ", staff.Moderator), staff.ErrSelfAppointment},
		"themself as curator":          {as(in("ana@example.com", staff.Curator), staff.MaePai, nil), staff.ErrSelfAppointment},
	} {
		if _, err := f.svc.Grant(ctx, admin, c.in); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE role <> 'admin'`); n != 0 {
		t.Fatalf("a refused grant stored %d roles", n)
	}
	if len(f.audit.Actions) != 0 {
		t.Fatalf("a refused grant recorded %+v", f.audit.Actions)
	}
	if _, err := f.svc.Grant(ctx, admin, in("bia@example.com", staff.Moderator)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Grant(ctx, admin, in("bia@example.com", staff.Moderator)); !errors.Is(err, staff.ErrAlreadyHasRole) {
		t.Fatalf("a second grant: %v", err)
	}
	if f.audited(audit.ModeratorAppointed) != 1 {
		t.Fatal("moderator_appointed must be recorded once")
	}
}

func TestModeratorIsAnIndependentRole(t *testing.T) {
	f := newFixture(t)
	caio := f.account("caio@example.com")
	if _, err := f.pool.Exec(ctx, `INSERT INTO platform_roles (account_id, role, display_role, granted_at)
		VALUES ($1::uuid, 'moderator', 'mae-pai', now())`, caio); err == nil {
		t.Fatal("a moderator with a displayed role was stored")
	}
	bia := f.moderator("bia@example.com")
	for r, want := range map[staff.Role]bool{staff.Moderator: true, staff.Admin: false, staff.Curator: false} {
		if ok := f.has(bia, r); ok != want {
			t.Errorf("%s: %v", r, ok)
		}
	}
	if roles, err := f.svc.Roles(ctx, bia); err != nil || !slices.Equal(roles, []staff.Role{staff.Moderator}) {
		t.Fatalf("roles %v %v", roles, err)
	}
}

func TestMembersListEveryRoleHolder(t *testing.T) {
	f := newFixture(t)
	if got, err := f.svc.Members(ctx); err != nil || got == nil || len(got) != 0 {
		t.Fatalf("no members: %+v %v", got, err)
	}
	t0 := f.now
	ana := f.admin("ana@example.com")
	f.account("plain@example.com") // no role: not listed
	f.now = t0.Add(time.Hour)
	bia := f.moderator("bia@example.com")
	f.now = t0.Add(2 * time.Hour)
	caio := f.curator("caio@example.com", staff.Pediatra)
	f.now = t0.Add(3 * time.Hour)
	// bia's later curator role does not move her: her earliest grant counts.
	f.exec(`INSERT INTO platform_roles (account_id, role, display_role, granted_at) VALUES ($1::uuid, 'curator', 'mae-pai', $2)`, bia, f.now)
	tied := []string{f.moderator("dani@example.com"), f.moderator("edu@example.com")} // same instant: by account ID
	slices.Sort(tied)

	got, err := f.svc.Members(ctx)
	if err != nil {
		t.Fatal(err)
	}
	ids := make([]string, 0, len(got))
	for _, m := range got {
		ids = append(ids, m.AccountID)
	}
	if want := append([]string{ana, bia, caio}, tied...); !slices.Equal(ids, want) {
		t.Fatalf("order %v, want %v", ids, want)
	}
	if got[1].Email != "bia@example.com" ||
		!sameRoles(got[0].Roles, staff.HeldRole{Role: staff.Admin, GrantedAt: t0}) ||
		!sameRoles(got[1].Roles,
			staff.HeldRole{Role: staff.Curator, GrantedAt: t0.Add(3 * time.Hour), DisplayRole: staff.MaePai},
			staff.HeldRole{Role: staff.Moderator, GrantedAt: t0.Add(time.Hour)}) ||
		!sameRoles(got[2].Roles, staff.HeldRole{Role: staff.Curator, GrantedAt: t0.Add(2 * time.Hour), DisplayRole: staff.Pediatra, VerifiedProfessional: true}) {
		t.Fatalf("members %+v", got)
	}
}

func TestPatchCuratorWithAReason(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	caio := f.moderator("caio@example.com")
	pro, yes := staff.Pedagogo, true
	patch := staff.CuratorPatch{DisplayRole: &pro, VerifiedProfessional: &yes}

	for name, c := range map[string]struct {
		id, reason string
		p          staff.CuratorPatch
		want       error
	}{
		"no reason":                    {bia, "", patch, staff.ErrReasonRequired},
		"the reason before the lookup": {"abc", "x", patch, staff.ErrReasonRequired},
		"a professional unverified":    {bia, "Agora é pedagoga.", staff.CuratorPatch{DisplayRole: &pro}, staff.ErrValidation},
		"an empty patch":               {bia, "Agora é pedagoga.", staff.CuratorPatch{}, staff.ErrValidation},
		"a moderator":                  {caio, "Agora é pedagoga.", patch, staff.ErrNotFound},
		"a malformed id":               {"abc", "Agora é pedagoga.", patch, staff.ErrNotFound},
		"an unknown id":                {"00000000-0000-0000-0000-000000000000", "Agora é pedagoga.", patch, staff.ErrNotFound},
	} {
		if _, err := f.svc.PatchCurator(ctx, admin, c.id, c.p, c.reason); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
	}
	if len(f.audit.Actions) != 0 {
		t.Fatalf("a refused patch recorded %+v", f.audit.Actions)
	}

	m, err := f.svc.PatchCurator(ctx, admin, strings.ToUpper(bia), patch, " Agora é pedagoga. ")
	if err != nil || m.AccountID != bia ||
		!sameRoles(m.Roles, staff.HeldRole{Role: staff.Curator, GrantedAt: f.now, DisplayRole: staff.Pedagogo, VerifiedProfessional: true}) {
		t.Fatalf("patched %+v %v", m, err)
	}
	want := audit.Action{Actor: admin, ActorRole: "admin", Event: audit.CuratorUpdated, SubjectKind: audit.SubjectAccount,
		SubjectID: bia, Reason: "Agora é pedagoga.", Metadata: map[string]string{"display_role": "pedagogo", "verified_professional": "true"}}
	if a, ok := f.audit.LastAction(audit.CuratorUpdated); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
	if _, err := f.svc.PatchCurator(ctx, admin, bia, staff.CuratorPatch{VerifiedProfessional: ptr(false)}, "Não é mais verificada."); !errors.Is(err, staff.ErrValidation) {
		t.Fatalf("unverifying a professional role: %v", err)
	}
	if f.audited(audit.CuratorUpdated) != 1 {
		t.Fatal("curator_updated must be recorded once")
	}
}

func TestPatchCuratorChangesTheDisplayedRole(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	pedro := f.curator("pedro@example.com", staff.Pediatra)
	psi, mae := staff.Psicologo, staff.MaePai
	const why = "Mudou de papel."

	if _, err := f.svc.PatchCurator(ctx, admin, pedro, staff.CuratorPatch{DisplayRole: &psi}, why); !errors.Is(err, staff.ErrValidation) {
		t.Fatalf("pediatra to psicologo without the flag: %v", err)
	}
	m, err := f.svc.PatchCurator(ctx, admin, pedro, staff.CuratorPatch{DisplayRole: &psi, VerifiedProfessional: ptr(true)}, why)
	if err != nil || !sameRoles(m.Roles, staff.HeldRole{Role: staff.Curator, GrantedAt: f.now, DisplayRole: staff.Psicologo, VerifiedProfessional: true}) {
		t.Fatalf("with the flag: %+v %v", m, err)
	}
	m, err = f.svc.PatchCurator(ctx, admin, pedro, staff.CuratorPatch{DisplayRole: &mae}, why)
	if err != nil || !sameRoles(m.Roles, staff.HeldRole{Role: staff.Curator, GrantedAt: f.now, DisplayRole: staff.MaePai}) {
		t.Fatalf("to mae-pai must clear the flag: %+v %v", m, err)
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid AND NOT verified_professional`, pedro); n != 1 {
		t.Fatal("the cleared flag was not stored")
	}
}

func TestRevokeARole(t *testing.T) {
	f := newFixture(t)
	admin := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', $2)`, bia, f.now)

	for name, c := range map[string]struct {
		id     string
		role   staff.Role
		reason string
		want   error
	}{
		"no reason":                    {bia, staff.Moderator, " ", staff.ErrReasonRequired},
		"the reason before the lookup": {"abc", staff.Moderator, "", staff.ErrReasonRequired},
		"admin":                        {admin, staff.Admin, "Saiu da equipe.", staff.ErrAdminCLIOnly},
		"an unknown role":              {bia, "owner", "Saiu da equipe.", staff.ErrValidation},
		"a malformed id":               {"abc", staff.Moderator, "Saiu da equipe.", staff.ErrNotFound},
		"a role not held":              {admin, staff.Moderator, "Saiu da equipe.", staff.ErrNotFound},
	} {
		if _, err := f.svc.Revoke(ctx, admin, c.id, c.role, c.reason); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
	}
	if !f.has(admin, staff.Admin) {
		t.Fatal("a refused revoke took the admin role")
	}
	if len(f.audit.Actions) != 0 {
		t.Fatalf("a refused revoke recorded %+v", f.audit.Actions)
	}

	m, err := f.svc.Revoke(ctx, admin, bia, staff.Moderator, "Não modera mais.")
	if err != nil || !sameRoles(m.Roles, staff.HeldRole{Role: staff.Curator, GrantedAt: f.now, DisplayRole: staff.MaePai}) {
		t.Fatalf("after the moderator role: %+v %v", m, err)
	}
	m, err = f.svc.Revoke(ctx, admin, strings.ToUpper(bia), staff.Curator, "Saiu da equipe.")
	if err != nil || m.AccountID != bia || m.Email != "bia@example.com" || !sameRoles(m.Roles) {
		t.Fatalf("after the last role: %+v %v", m, err)
	}
	for _, e := range []audit.Event{audit.ModeratorRemoved, audit.CuratorRemoved} {
		a, ok := f.audit.LastAction(e)
		if !ok || a.Actor != admin || a.ActorRole != "admin" || a.SubjectKind != audit.SubjectAccount || a.SubjectID != bia || a.Metadata != nil {
			t.Errorf("%s: %+v %v", e, a, ok)
		}
	}
	if members, _ := f.svc.Members(ctx); len(members) != 1 || members[0].AccountID != admin {
		t.Fatalf("an account without roles is still listed: %+v", members)
	}
	if _, err := f.svc.Revoke(ctx, admin, bia, staff.Curator, "Saiu da equipe."); !errors.Is(err, staff.ErrNotFound) {
		t.Fatalf("revoking again: %v", err)
	}
}

func TestPatchCuratorRefusesTheAdminOwnRow(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bob := f.admin("bob@example.com")
	if _, err := f.svc.Grant(ctx, bob, staff.GrantInput{Email: "ana@example.com", Role: staff.Curator, DisplayRole: staff.MaePai,
		Reason: "Entrou na equipe."}); err != nil {
		t.Fatal(err)
	}
	before := len(f.audit.Actions)
	pro, yes := staff.Pediatra, true
	patch := staff.CuratorPatch{DisplayRole: &pro, VerifiedProfessional: &yes}
	for _, id := range []string{ana, strings.ToUpper(ana)} {
		if _, err := f.svc.PatchCurator(ctx, ana, id, patch, "Agora sou pediatra."); !errors.Is(err, staff.ErrSelfAppointment) {
			t.Fatalf("self-patch %q: %v", id, err)
		}
	}
	if _, err := f.svc.PatchCurator(ctx, ana, ana, patch, ""); !errors.Is(err, staff.ErrReasonRequired) {
		t.Fatalf("the reason comes first: %v", err)
	}
	if got := f.id(`SELECT display_role FROM platform_roles WHERE account_id = $1::uuid AND role = 'curator'`, ana); got != "mae-pai" {
		t.Fatalf("a refused self-patch changed the row to %q", got)
	}
	if len(f.audit.Actions) != before {
		t.Fatalf("a refused self-patch recorded %+v", f.audit.Actions[before:])
	}
}
