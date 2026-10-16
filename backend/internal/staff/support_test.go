package staff_test

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

const supportReason = "Pedido do titular."

func TestRevokeAccountSessions(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	dani := f.admin("dani@example.com") // acting on another admin is allowed
	f.session(dani)
	f.session(dani)
	mine := f.session(ana)

	sh, err := f.svc.RevokeAccountSessions(ctx, ana, dani, supportReason)
	if err != nil || sh.AccountID != dani || len(sh.Sessions) != 0 {
		t.Fatalf("refreshed sheet %+v %v", sh, err)
	}
	if n := f.count(`SELECT count(*) FROM sessions WHERE account_id = $1::uuid AND revoked_at IS NULL`, dani); n != 0 {
		t.Fatalf("%d sessions still live", n)
	}
	if n := f.count(`SELECT count(*) FROM sessions WHERE id = $1::uuid AND revoked_at IS NULL`, mine); n != 1 {
		t.Fatal("the admin's own session ended")
	}
	want := audit.Action{Actor: ana, ActorRole: "admin", Event: audit.AccountSessionsRevoked, SubjectKind: audit.SubjectAccount,
		SubjectID: dani, Reason: supportReason, Metadata: map[string]string{"sessions": "2"}}
	if a, ok := f.audit.LastAction(audit.AccountSessionsRevoked); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
}

func TestUnlinkAccountDevice(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	caio := f.account("caio@example.com")
	fam := f.owner(caio)
	lia := f.minor(caio)
	bia := f.account("bia@example.com")
	f.exec(`INSERT INTO family_members (family_id, account_id, role, joined_at) VALUES ($1::uuid, $2::uuid, 'guardian', $3)`, fam, bia, f.now)
	first := f.device(fam, lia, f.now)
	second := f.device(fam, lia, f.now)
	teo := f.account("teo@example.com")
	foreign := f.device(f.owner(teo), f.minor(teo), f.now)

	sh, err := f.svc.UnlinkAccountDevice(ctx, ana, bia, strings.ToUpper(first), supportReason)
	if err != nil || len(sh.Devices) != 1 || sh.Devices[0].ID != second || sh.Family == nil ||
		*sh.Family != (staff.SheetFamily{Role: family.Guardian, Minors: 1, Devices: 1}) {
		t.Fatalf("refreshed sheet %+v %v", sh, err)
	}
	if n := f.count(`SELECT count(*) FROM devices WHERE id = $1::uuid`, first); n != 0 {
		t.Fatal("the device is still linked")
	}
	want := audit.Action{Actor: ana, ActorRole: "admin", Event: audit.AccountDeviceUnlinked, SubjectKind: audit.SubjectAccount,
		SubjectID: bia, Reason: supportReason, Metadata: map[string]string{"device_id": first}}
	if a, ok := f.audit.LastAction(audit.AccountDeviceUnlinked); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
	n := len(f.audit.Actions)
	for _, d := range []string{first, foreign, "abc"} {
		if _, err := f.svc.UnlinkAccountDevice(ctx, ana, bia, d, supportReason); !errors.Is(err, staff.ErrDeviceNotFound) {
			t.Errorf("device %q: %v, want ErrDeviceNotFound", d, err)
		}
	}
	if c := f.count(`SELECT count(*) FROM devices WHERE id = $1::uuid`, foreign); c != 1 {
		t.Fatal("another family's device was deleted")
	}
	if _, err := f.svc.UnlinkAccountDevice(ctx, ana, f.account("gil@example.com"), second, supportReason); !errors.Is(err, staff.ErrDeviceNotFound) {
		t.Fatalf("a subject without a family: %v", err)
	}
	if len(f.audit.Actions) != n {
		t.Fatal("a refused unlink was audited")
	}
}

func TestSendAccountPasswordReset(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	gil := f.account("gil@example.com") // no password: a Google-only account
	f.linkGoogle(gil)

	for i := range 3 {
		if _, err := f.svc.SendAccountPasswordReset(ctx, ana, gil, supportReason); err != nil {
			t.Fatalf("reset %d: %v", i+1, err)
		}
	}
	msgs := f.mail.To("gil@example.com")
	if len(msgs) != 3 || !strings.Contains(msgs[2].Body, "https://app.test/redefinir-senha?token=") {
		t.Fatalf("reset mail %+v", msgs)
	}
	want := audit.Action{Actor: ana, ActorRole: "admin", Event: audit.AccountPasswordResetSent, SubjectKind: audit.SubjectAccount,
		SubjectID: gil, Reason: supportReason}
	if a, ok := f.audit.LastAction(audit.AccountPasswordResetSent); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
	var throttled *staff.ThrottledError
	if _, err := f.svc.SendAccountPasswordReset(ctx, ana, gil, supportReason); !errors.As(err, &throttled) || throttled.RetryAfter <= 0 {
		t.Fatalf("the 4th reset in an hour: %v", err)
	}
	if len(f.mail.To("gil@example.com")) != 3 || f.audited(audit.AccountPasswordResetSent) != 3 {
		t.Fatal("the refused 4th reset sent mail or was audited")
	}
	if _, err := f.svc.SendAccountPasswordReset(ctx, ana, f.account("bia@example.com"), supportReason); err != nil {
		t.Fatalf("another subject shares the budget: %v", err)
	}
}

func TestSupportRefusalOrder(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	f.session(ana)
	bia := f.account("bia@example.com")
	const unknown = "00000000-0000-0000-0000-000000000000"
	reset := func(id, reason string) error {
		_, err := f.svc.SendAccountPasswordReset(ctx, ana, id, reason)
		return err
	}
	actions := map[string]func(id, reason string) error{
		"revoke": func(id, reason string) error {
			_, err := f.svc.RevokeAccountSessions(ctx, ana, id, reason)
			return err
		},
		"unlink": func(id, reason string) error {
			_, err := f.svc.UnlinkAccountDevice(ctx, ana, id, unknown, reason)
			return err
		},
		"reset": reset,
	}
	for name, act := range actions {
		for _, c := range []struct {
			id, reason string
			want       error
		}{
			{ana, "ab", staff.ErrReasonRequired},                       // the body before self
			{strings.ToUpper(ana), supportReason, staff.ErrSelfAction}, // self, however the id is typed
			{unknown, supportReason, staff.ErrAccountNotFound},
			{"not-an-id", supportReason, staff.ErrAccountNotFound},
		} {
			if err := act(c.id, c.reason); !errors.Is(err, c.want) {
				t.Errorf("%s on %q: %v, want %v", name, c.id, err, c.want)
			}
		}
	}
	if len(f.audit.Actions) != 0 || len(f.mail.To("ana@example.com")) != 0 ||
		f.count(`SELECT count(*) FROM sessions WHERE account_id = $1::uuid AND revoked_at IS NULL`, ana) != 1 {
		t.Fatal("a refused support action changed something")
	}
	// The limiter comes after the body and the account: refusals do not
	// spend the subject's budget.
	for range 5 {
		if err := reset(bia, "ab"); !errors.Is(err, staff.ErrReasonRequired) {
			t.Fatalf("short reason: %v", err)
		}
	}
	for i := range 3 {
		if err := reset(bia, supportReason); err != nil {
			t.Fatalf("reset %d after refusals: %v", i+1, err)
		}
	}
}
