package staff_test

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"maps"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

const suspendReason = "Denúncia de conteúdo impróprio."

// failingMail fails every send.
type failingMail struct{}

func (failingMail) Send(context.Context, mail.Message) error { return errors.New("smtp down") }

// actionsAbout reads the staff actions about the account from the
// database, newest first. The suspension writes them inside its
// transaction, not through the recorder.
func (f *fixture) actionsAbout(accountID string) []audit.Recorded {
	f.t.Helper()
	rows, err := f.store.ActionsAbout(ctx, audit.SubjectAccount, accountID, 20)
	if err != nil {
		f.t.Fatal(err)
	}
	return rows
}

// liveSessions counts the account's sessions not revoked.
func (f *fixture) liveSessions(accountID string) int {
	f.t.Helper()
	return f.count(`SELECT count(*) FROM sessions WHERE account_id = $1::uuid AND revoked_at IS NULL`, accountID)
}

func TestSuspendInOneTransaction(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', $2)`, bia, f.now)
	f.session(bia)
	f.session(bia)
	f.session(ana)
	version := f.count(`SELECT credential_version FROM accounts WHERE id = $1::uuid`, bia)

	sh, err := f.svc.Suspend(ctx, ana, strings.ToUpper(bia), "  "+suspendReason+"  ")
	if err != nil || sh.AccountID != bia || sh.Suspension == nil || !sh.Suspension.Since.Equal(f.now) ||
		sh.Suspension.Reason != suspendReason || len(sh.Roles) != 0 || len(sh.Sessions) != 0 {
		t.Fatalf("refreshed sheet %+v %v", sh, err)
	}
	if n := f.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid AND status = 'suspended' AND suspended_at = $2
		AND suspension_reason = $3 AND credential_version = $4`, bia, f.now, suspendReason, version+1); n != 1 {
		t.Fatal("the account is not suspended as written, or its credential version did not move by one")
	}
	if f.liveSessions(bia) != 0 || f.liveSessions(ana) != 1 {
		t.Fatal("the subject's sessions must end, and only theirs")
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid`, bia); n != 0 {
		t.Fatalf("%d roles survived the suspension", n)
	}
	rows := f.actionsAbout(bia)
	if len(rows) != 1 || rows[0].Event != audit.AccountSuspended || rows[0].ActorID != ana || rows[0].ActorRole != "admin" ||
		rows[0].Reason != suspendReason || !rows[0].OccurredAt.Equal(f.now) ||
		!maps.Equal(meta(t, rows[0].Metadata), map[string]string{"sessions": "2", "roles": "curator,moderator"}) {
		t.Fatalf("audit rows %+v", rows)
	}
	if len(sh.Actions) != 1 || sh.Actions[0].Event != string(audit.AccountSuspended) {
		t.Fatalf("the sheet's actions %+v", sh.Actions)
	}
	if len(f.audit.Actions) != 0 {
		t.Fatal("the suspension was recorded outside its transaction")
	}
	msgs := f.mail.To("bia@example.com")
	if len(msgs) != 1 {
		t.Fatalf("%d notices, want 1", len(msgs))
	}
	notice := msgs[0].Subject + "\n" + msgs[0].Body
	for _, want := range []string{"suspensa", "baixar", "excluir", "sair", "responda"} {
		if !strings.Contains(notice, want) {
			t.Errorf("the notice lacks %q: %s", want, notice)
		}
	}
	if strings.Contains(notice, "Denúncia") {
		t.Fatal("the notice carries the reason")
	}
}

func TestSuspendRefusals(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	dani := f.admin("dani@example.com")
	f.session(dani)
	bia := f.account("bia@example.com") // no session, no role
	const unknown = "00000000-0000-0000-0000-000000000000"
	for _, c := range []struct {
		id, reason string
		want       error
	}{
		{bia, "ab", staff.ErrReasonRequired},
		{bia, strings.Repeat("a", 201), staff.ErrReasonRequired},
		{strings.ToUpper(ana), suspendReason, staff.ErrSelfAction},
		{unknown, suspendReason, staff.ErrAccountNotFound},
		{"not-an-id", suspendReason, staff.ErrAccountNotFound},
		{dani, suspendReason, staff.ErrSubjectIsAdmin},
	} {
		if _, err := f.svc.Suspend(ctx, ana, c.id, c.reason); !errors.Is(err, c.want) {
			t.Errorf("suspend %q: %v, want %v", c.id, err, c.want)
		}
	}
	if f.count(`SELECT count(*) FROM accounts WHERE status = 'suspended'`) != 0 || f.count(`SELECT count(*) FROM audit_events`) != 0 ||
		len(f.mail.Sent) != 0 || f.liveSessions(dani) != 1 || !f.has(dani, staff.Admin) {
		t.Fatal("a refused suspension changed something, audited or mailed")
	}

	if _, err := f.svc.Suspend(ctx, ana, bia, suspendReason); err != nil {
		t.Fatalf("a bare account: %v", err)
	}
	if rows := f.actionsAbout(bia); len(rows) != 1 ||
		!maps.Equal(meta(t, rows[0].Metadata), map[string]string{"sessions": "0", "roles": ""}) {
		t.Fatalf("a bare account's suspension: %+v", rows)
	}
	if _, err := f.svc.Suspend(ctx, dani, bia, suspendReason); !errors.Is(err, staff.ErrAlreadySuspended) {
		t.Fatalf("a second suspension: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE event = 'account_suspended'`); n != 1 || len(f.mail.To("bia@example.com")) != 1 {
		t.Fatalf("a second suspension audited or mailed again: %d rows", n)
	}
}

func TestReinstate(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	if _, err := f.svc.Suspend(ctx, ana, bia, suspendReason); err != nil {
		t.Fatal(err)
	}
	version := f.count(`SELECT credential_version FROM accounts WHERE id = $1::uuid`, bia)
	f.session(bia) // signed in while suspended
	const why = "Revisão: denúncia improcedente."

	sh, err := f.svc.Reinstate(ctx, ana, bia, why)
	if err != nil || sh.Suspension != nil || len(sh.Roles) != 0 || len(sh.Sessions) != 1 {
		t.Fatalf("refreshed sheet %+v %v: no role restored, no session revoked", sh, err)
	}
	if len(sh.Actions) == 0 || sh.Actions[0].Event != string(audit.AccountReinstated) {
		t.Fatalf("the sheet's actions %+v lack the reinstatement", sh.Actions)
	}
	if n := f.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid AND status = 'active' AND suspended_at IS NULL
		AND suspension_reason IS NULL AND credential_version = $2`, bia, version); n != 1 {
		t.Fatal("the account is not reinstated as written, or its version moved")
	}
	rows := f.actionsAbout(bia)
	if len(rows) != 2 || rows[0].Event != audit.AccountReinstated || rows[0].ActorID != ana || rows[0].Reason != why ||
		meta(t, rows[0].Metadata) != nil {
		t.Fatalf("audit rows %+v", rows)
	}
	msgs := f.mail.To("bia@example.com")
	if len(msgs) != 2 || !strings.Contains(msgs[1].Subject, "reativada") || strings.Contains(msgs[1].Body, why) {
		t.Fatalf("reinstatement notice %+v", msgs)
	}
	for _, c := range []struct {
		id, reason string
		want       error
	}{
		{bia, why, staff.ErrNotSuspended},
		{strings.ToUpper(ana), why, staff.ErrSelfAction},
		{"00000000-0000-0000-0000-000000000000", why, staff.ErrAccountNotFound},
		{bia, "ab", staff.ErrReasonRequired},
	} {
		if _, err := f.svc.Reinstate(ctx, ana, c.id, c.reason); !errors.Is(err, c.want) {
			t.Errorf("reinstate %q: %v, want %v", c.id, err, c.want)
		}
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE event = 'account_reinstated'`); n != 1 || len(f.mail.To("bia@example.com")) != 2 {
		t.Fatalf("a refused reinstatement audited or mailed: %d rows", n)
	}
}

func TestAFailedSuspensionChangesNothing(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	f.session(bia)
	version := f.count(`SELECT credential_version FROM accounts WHERE id = $1::uuid`, bia)
	f.exec(`CREATE FUNCTION refuse_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced'; END $$`)
	f.exec(`CREATE TRIGGER refuse_suspension_audit BEFORE INSERT ON audit_events FOR EACH ROW
		WHEN (NEW.event = 'account_suspended') EXECUTE FUNCTION refuse_audit()`)

	if _, err := f.svc.Suspend(ctx, ana, bia, suspendReason); err == nil || !strings.Contains(err.Error(), "forced") {
		t.Fatalf("a suspension whose audit failed: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid AND status = 'active' AND credential_version = $2`, bia, version); n != 1 ||
		f.liveSessions(bia) != 1 || !f.has(bia, staff.Curator) || len(f.mail.Sent) != 0 {
		t.Fatal("a suspension whose audit failed left a change, or sent its notice")
	}
}

func TestTwoAdminsSuspendOnce(t *testing.T) {
	f := newFixture(t)
	admins := []string{f.admin("ana@example.com"), f.admin("dani@example.com")}
	bia := f.account("bia@example.com")
	errs := make([]error, len(admins))
	var wg sync.WaitGroup
	for i, admin := range admins {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, errs[i] = f.svc.Suspend(ctx, admin, bia, suspendReason)
		}()
	}
	wg.Wait()
	won, lost := 0, 0
	for _, err := range errs {
		switch {
		case err == nil:
			won++
		case errors.Is(err, staff.ErrAlreadySuspended):
			lost++
		}
	}
	if won != 1 || lost != 1 {
		t.Fatalf("two concurrent suspensions: %v", errs)
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE event = 'account_suspended'`); n != 1 || len(f.mail.To("bia@example.com")) != 1 {
		t.Fatalf("suspended once must audit and mail once: %d rows", n)
	}
}

func TestAFailedNoticeIsLoggedOnly(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.account("bia@example.com")
	var logs bytes.Buffer
	d := f.deps
	d.Mail = failingMail{}
	d.Log = slog.New(slog.NewTextHandler(&logs, nil))
	svc := staff.NewService(d)

	if _, err := svc.Suspend(ctx, ana, bia, suspendReason); err != nil {
		t.Fatalf("a failed notice failed the suspension: %v", err)
	}
	if _, err := svc.Reinstate(ctx, ana, bia, "Revisão concluída."); err != nil {
		t.Fatalf("a failed notice failed the reinstatement: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE event IN ('account_suspended', 'account_reinstated')`); n != 2 {
		t.Fatalf("%d actions, want both", n)
	}
	out := logs.String()
	if strings.Count(out, "notice not sent") != 2 || strings.Contains(out, "bia@example.com") || strings.Contains(out, "Denúncia") {
		t.Fatalf("the log: %s", out)
	}
}

// waitForAccountLock returns once a backend of this database waits on an
// account-row lock (identity.LockAccount): the call under test is parked
// behind the test's own transaction.
func (f *fixture) waitForAccountLock() {
	f.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting bool
		if err := f.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database() AND pid <> pg_backend_pid() AND wait_event_type = 'Lock'
			AND query LIKE 'SELECT status FROM accounts WHERE id = %FOR NO KEY UPDATE')`).Scan(&waiting); err != nil {
			f.t.Fatal(err)
		}
		if waiting {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatal("no call waited on the account-row lock")
}

func TestNoRoleForASuspendedAccount(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.account("bia@example.com")
	if _, err := f.svc.Suspend(ctx, ana, bia, suspendReason); err != nil {
		t.Fatal(err)
	}
	granted := f.audited(audit.AdminGranted)
	in := staff.GrantInput{Email: "bia@example.com", Role: staff.Moderator, Reason: "Vai moderar."}

	if _, err := f.svc.Grant(ctx, ana, in); !errors.Is(err, staff.ErrAccountSuspended) {
		t.Fatalf("a team grant to a suspended account: %v", err)
	}
	if _, err := f.svc.GrantAdmin(ctx, "bia@example.com"); !errors.Is(err, staff.ErrAccountSuspended) {
		t.Fatalf("grant-admin to a suspended account: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid`, bia); n != 0 ||
		f.audited(audit.ModeratorAppointed) != 0 || f.audited(audit.AdminGranted) != granted {
		t.Fatal("a refused grant inserted a role or was audited")
	}
	if _, err := f.svc.Reinstate(ctx, ana, bia, "Revisão concluída."); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Grant(ctx, ana, in); err != nil {
		t.Fatalf("a reinstated account can be appointed again: %v", err)
	}
}

func TestAGrantWaitsForASuspensionInFlight(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.account("bia@example.com")
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := identity.LockAccount(ctx, tx, bia); err != nil {
		t.Fatal(err)
	}
	if err := identity.MarkSuspended(ctx, tx, bia, f.now, suspendReason); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := f.svc.Grant(ctx, ana, staff.GrantInput{Email: "bia@example.com", Role: staff.Moderator, Reason: "Vai moderar."})
		done <- err
	}()
	f.waitForAccountLock()
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, staff.ErrAccountSuspended) {
		t.Fatalf("a grant behind a suspension in flight: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid`, bia); n != 0 {
		t.Fatal("the grant landed on a suspended account")
	}
}
