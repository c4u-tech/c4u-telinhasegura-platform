package identity_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

const suspendReason = "Denúncia de conteúdo impróprio."

// inTx runs fn in a transaction of the fixture's database and commits
// it, unless fn fails.
func (f *fixture) inTx(fn func(tx pgx.Tx) error) error {
	f.t.Helper()
	ctx := context.Background()
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		f.t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// waitForLockWaiter returns once a backend of this database waits on a
// lock in a statement like query (a LIKE pattern): the call under test
// is parked behind the test's own transaction.
func (f *fixture) waitForLockWaiter(query string) {
	f.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting bool
		if err := f.pool.QueryRow(context.Background(), `SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database() AND pid <> pg_backend_pid() AND wait_event_type = 'Lock' AND query LIKE $1)`, query).Scan(&waiting); err != nil {
			f.t.Fatal(err)
		}
		if waiting {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatalf("no statement like %q waited on a lock", query)
}

func TestSuspendAndReinstateTheStatus(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	bia := f.signUpVerified("bia@example.com", goodPassword)
	if st, err := f.svc.Status(ctx, bia); err != nil || st != identity.StatusActive {
		t.Fatalf("a new account: %q %v", st, err)
	}
	v := f.credentialVersion(bia)
	at := f.now.Add(time.Minute)

	if err := f.inTx(func(tx pgx.Tx) error {
		st, err := identity.LockAccount(ctx, tx, bia)
		if err != nil {
			return err
		}
		if st != identity.StatusActive {
			t.Errorf("locked status %q, want active", st)
		}
		return identity.MarkSuspended(ctx, tx, bia, at, suspendReason)
	}); err != nil {
		t.Fatal(err)
	}
	if st, err := f.svc.Status(ctx, bia); err != nil || st != identity.StatusSuspended {
		t.Fatalf("after the suspension: %q %v", st, err)
	}
	if got := f.credentialVersion(bia); got != v+1 {
		t.Fatalf("credential version %d, want %d: the suspension must move it", got, v+1)
	}
	acc, err := f.svc.AccountForStaff(ctx, bia)
	if err != nil || acc.Status != identity.StatusSuspended || !acc.SuspendedAt.Equal(at) || acc.SuspensionReason != suspendReason {
		t.Fatalf("staff account %+v %v", acc, err)
	}
	if view, err := f.svc.Account(ctx, bia); err != nil || view.Status != identity.StatusSuspended {
		t.Fatalf("account view %+v %v", view, err)
	}
	if err := f.inTx(func(tx pgx.Tx) error {
		st, err := identity.LockAccount(ctx, tx, bia)
		if err != nil {
			return err
		}
		if st != identity.StatusSuspended {
			t.Errorf("locked status %q, want suspended", st)
		}
		return identity.MarkSuspended(ctx, tx, bia, at, suspendReason)
	}); !errors.Is(err, identity.ErrStatusChanged) {
		t.Fatalf("suspending a suspended account: %v", err)
	}
	if got := f.credentialVersion(bia); got != v+1 {
		t.Fatalf("a refused suspension moved the version to %d", got)
	}

	if err := f.inTx(func(tx pgx.Tx) error { return identity.MarkActive(ctx, tx, bia) }); err != nil {
		t.Fatal(err)
	}
	acc, err = f.svc.AccountForStaff(ctx, bia)
	if err != nil || acc.Status != identity.StatusActive || !acc.SuspendedAt.IsZero() || acc.SuspensionReason != "" {
		t.Fatalf("reinstated staff account %+v %v", acc, err)
	}
	if got := f.credentialVersion(bia); got != v+1 {
		t.Fatalf("reinstating moved the version to %d", got)
	}
	if err := f.inTx(func(tx pgx.Tx) error { return identity.MarkActive(ctx, tx, bia) }); !errors.Is(err, identity.ErrStatusChanged) {
		t.Fatalf("reinstating an active account: %v", err)
	}
}

func TestStatusRefusesAnUnknownAccount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	for _, id := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.Status(ctx, id); !errors.Is(err, identity.ErrNotFound) {
			t.Errorf("Status(%q): %v, want ErrNotFound", id, err)
		}
		if err := f.inTx(func(tx pgx.Tx) error {
			_, err := identity.LockAccount(ctx, tx, id)
			return err
		}); !errors.Is(err, identity.ErrNotFound) {
			t.Errorf("LockAccount(%q): %v, want ErrNotFound", id, err)
		}
	}
}

func TestTheSuspensionColumnsHoldTogether(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	bia := f.signUpVerified("bia@example.com", goodPassword)
	for name, sql := range map[string]string{
		"an unknown status":          `UPDATE accounts SET status = 'banned' WHERE id = $1::uuid`,
		"suspended without a time":   `UPDATE accounts SET status = 'suspended', suspension_reason = 'x' WHERE id = $1::uuid`,
		"suspended without a reason": `UPDATE accounts SET status = 'suspended', suspended_at = now() WHERE id = $1::uuid`,
		"active with a reason":       `UPDATE accounts SET suspension_reason = 'x' WHERE id = $1::uuid`,
		"active with a time":         `UPDATE accounts SET suspended_at = now() WHERE id = $1::uuid`,
	} {
		_, err := f.pool.Exec(ctx, sql, bia)
		var pg *pgconn.PgError
		if !errors.As(err, &pg) || pg.Code != "23514" {
			t.Errorf("%s: %v, want a check violation", name, err)
		}
	}
	if _, err := f.pool.Exec(ctx, `UPDATE accounts SET status = 'suspended', suspended_at = now(), suspension_reason = 'x'
		WHERE id = $1::uuid`, bia); err != nil {
		t.Fatalf("a whole suspension was refused: %v", err)
	}
}

func TestLockAccountHoldsASignInRecheck(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	bia := f.signUpVerified("bia@example.com", goodPassword)
	signedIn, err := f.svc.Authenticate(ctx, "bia@example.com", goodPassword)
	if err != nil {
		t.Fatal(err)
	}
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
	type recheck struct {
		current bool
		err     error
	}
	done := make(chan recheck, 1)
	go func() {
		current, err := f.svc.CredentialStillCurrent(ctx, bia, signedIn.CredentialVersion)
		done <- recheck{current, err}
	}()
	f.waitForLockWaiter(`SELECT credential_version FROM accounts WHERE id = %FOR SHARE`)
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if got := <-done; got.err != nil || got.current {
		t.Fatalf("a sign-in checked before the suspension still passes its re-check: %+v", got)
	}
}
