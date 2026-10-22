package identity_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// The clear_password link evicts a squatter. These tests land it in the
// middle of a squatter's in-flight request and check that nothing the
// squatter started survives it.

func (f *fixture) credentialVersion(id string) int64 {
	f.t.Helper()
	var v int64
	if err := f.pool.QueryRow(context.Background(), `SELECT credential_version FROM accounts WHERE id = $1`, id).Scan(&v); err != nil {
		f.t.Fatal(err)
	}
	return v
}

func (f *fixture) hasPassword(id string) bool {
	f.t.Helper()
	var has bool
	if err := f.pool.QueryRow(context.Background(), `SELECT password_hash IS NOT NULL FROM accounts WHERE id = $1`, id).Scan(&has); err != nil {
		f.t.Fatal(err)
	}
	return has
}

func (f *fixture) count(query string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(context.Background(), query, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

// clear confirms a clear_password link for the victim's Google identity.
func (f *fixture) clear(ticket, wantID string) {
	f.t.Helper()
	got, err := f.svc.ProviderLink(context.Background(), ticket, identity.LinkProof{ClearPassword: true})
	if err != nil || got != wantID {
		f.t.Fatalf("clear: %q, %v", got, err)
	}
}

func TestChangePasswordLosesToAClearThatLandsDuringItsChecks(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword) // the squatter's password
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))
	// The squatter's change passed its password check; the victim's clear
	// lands while the new password is being judged.
	f.onPolicyCheck = func() { f.clear(ticket, id) }

	if err := f.svc.ChangePassword(ctx, id, "squatter-session", goodPassword, newPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("got %v", err)
	}
	if f.hasPassword(id) {
		t.Fatal("the squatter's password landed after the clear")
	}
	for _, c := range f.sessions.calls {
		if c.Except != "" {
			t.Fatalf("the losing change revoked sessions: %+v", f.sessions.calls)
		}
	}
	if f.audit.Has(id, audit.PasswordChanged) {
		t.Fatal("the losing change was audited")
	}
	for _, m := range f.mail.To("ana@gmail.com") {
		if strings.Contains(m.Subject, "foi alterada") {
			t.Fatal("the losing change sent its notice")
		}
	}
}

func TestAStaleEmailChangeRequestIsRefused(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	seen := f.credentialVersion(id) // the squatter's request read the account
	f.clear(f.linkTicket(gmail("g-1", "ana@gmail.com")), id)

	if err := identity.IssueEmailChange(f.svc, ctx, id, f.liveSession(id), "squatter@example.com", seen); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("got %v", err)
	}
	if n := f.count(`SELECT count(*) FROM email_tokens WHERE account_id = $1 AND used_at IS NULL`, id); n != 0 {
		t.Fatalf("%d live tokens after the clear", n)
	}
	if err := identity.IssueEmailChange(f.svc, ctx, id, f.liveSession(id), "nova@example.com", f.credentialVersion(id)); err != nil {
		t.Fatalf("current version: %v", err)
	}
}

// A squatter's email change that passed the re-auth middleware before the
// clear, but reads the account after it, sees the new version; its session
// is what the clear revoked, so the token must not be stored (residual C1).
func TestAnEmailChangeFromARevokedSessionIsRefused(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	squatter := f.liveSession(id)
	f.clear(f.linkTicket(gmail("g-1", "ana@gmail.com")), id)

	if err := f.svc.RequestEmailChange(ctx, id, squatter, "squatter@example.com"); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("got %v", err)
	}
	if n := f.count(`SELECT count(*) FROM email_tokens WHERE account_id = $1 AND purpose = 'change'`, id); n != 0 {
		t.Fatalf("%d change tokens issued to a revoked session", n)
	}
	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "nova@example.com"); err != nil {
		t.Fatalf("live session: %v", err)
	}
}

func TestPasswordSignInIsStaleOnceTheClearLands(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))

	signIn, err := f.svc.Authenticate(ctx, "ana@gmail.com", goodPassword)
	if err != nil || signIn.AccountID != id {
		t.Fatalf("sign-in: %+v, %v", signIn, err)
	}
	if ok, err := f.svc.CredentialStillCurrent(ctx, id, signIn.CredentialVersion); err != nil || !ok {
		t.Fatalf("before the clear: %v, %v", ok, err)
	}
	f.clear(ticket, id)
	if ok, err := f.svc.CredentialStillCurrent(ctx, id, signIn.CredentialVersion); err != nil || ok {
		t.Fatalf("after the clear: %v, %v", ok, err)
	}
}

func TestEveryCredentialChangeBumpsTheVersion(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	bumped := func(step string, do func()) {
		t.Helper()
		before := f.credentialVersion(id)
		do()
		if f.credentialVersion(id) <= before {
			t.Fatalf("%s did not bump the credential version", step)
		}
	}
	bumped("password change", func() {
		if err := f.svc.ChangePassword(ctx, id, "s", goodPassword, newPassword); err != nil {
			t.Fatal(err)
		}
	})
	bumped("password reset", func() {
		_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
		if err := f.svc.ConfirmPasswordReset(ctx, f.lastToken("ana@example.com"), goodPassword); err != nil {
			t.Fatal(err)
		}
	})
	bumped("email change", func() {
		_ = f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "ana@gmail.com")
		if err := f.svc.ConfirmEmail(ctx, f.lastToken("ana@gmail.com")); err != nil {
			t.Fatal(err)
		}
	})
	bumped("clear_password link", func() { f.clear(f.linkTicket(gmail("g-1", "ana@gmail.com")), id) })
}

func TestAnEmailChangeConfirmedDuringTheEvictionStopsTheClear(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "squatter@example.com"); err != nil {
		t.Fatal(err)
	}
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))
	// The squatter's confirmation holds the account while the victim's
	// clear waits on it, and moves the account, as spendEmailToken does.
	err := f.duringClear(id, ticket, func(tx pgx.Tx) {
		if _, err := tx.Exec(ctx, `UPDATE accounts SET email = 'squatter@example.com', credential_version = credential_version + 1 WHERE id = $1`, id); err != nil {
			t.Error(err)
		}
	})

	if !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("got %v", err)
	}
	if n := f.count(`SELECT count(*) FROM external_identities WHERE account_id = $1`, id); n != 0 {
		t.Fatal("the victim's Google was linked to the account the squatter moved")
	}
}

// duringClear runs a clear_password link for ticket while another
// transaction holds the account: inside runs in that transaction once the
// clear waits on it, then it commits. It returns the link's error.
func (f *fixture) duringClear(accountID, ticket string, inside func(pgx.Tx)) error {
	f.t.Helper()
	ctx := context.Background()
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		f.t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var holder int
	if err := tx.QueryRow(ctx, `SELECT pg_backend_pid() FROM accounts WHERE id = $1 FOR UPDATE`, accountID).Scan(&holder); err != nil {
		f.t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := f.svc.ProviderLink(ctx, ticket, identity.LinkProof{ClearPassword: true})
		done <- err
	}()
	waitBlockedOn(f.t, f, holder, done)
	inside(tx)
	if err := tx.Commit(ctx); err != nil {
		f.t.Fatal(err)
	}
	return <-done
}

// The eviction revokes the sessions in the transaction that bumps the
// version, so no session outlives the clear while its re-check still
// sees the old version (sibling of C1).
func TestTheClearRevokesSessionsInItsOwnTransaction(t *testing.T) {
	f := newFixture(t)
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	f.liveSession(id)
	f.liveSession(id)

	f.clear(f.linkTicket(gmail("g-1", "ana@gmail.com")), id)

	if n := f.count(`SELECT count(*) FROM sessions WHERE account_id = $1 AND revoked_at IS NULL`, id); n != 0 {
		t.Fatalf("%d sessions outlived the clear", n)
	}
	if len(f.sessions.calls) != 0 {
		t.Fatalf("the clear revoked outside its transaction: %+v", f.sessions.calls)
	}
	if !f.audit.Has(id, audit.SessionRevoked) {
		t.Fatal("the revocation was not audited")
	}
}

// An email change whose token was taken before the clear must not move
// the account after it: the confirmation waits on the account the clear
// holds, then finds its token spent.
func TestAnInFlightEmailChangeConfirmationLosesToTheClear(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "squatter@example.com"); err != nil {
		t.Fatal(err)
	}
	change := f.lastToken("squatter@example.com")

	// Stand in for the clear's transaction: hold the account, then spend
	// every pending token, as clearPasswordAndLink does.
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var holder int
	if err := tx.QueryRow(ctx, `SELECT pg_backend_pid()`).Scan(&holder); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `UPDATE accounts SET password_hash = NULL, credential_version = credential_version + 1 WHERE id = $1`, id); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- f.svc.ConfirmEmail(ctx, change) }()
	waitBlockedOn(t, f, holder, done)
	if _, err := tx.Exec(ctx, `UPDATE email_tokens SET used_at = now() WHERE account_id = $1 AND used_at IS NULL`, id); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}

	if err := <-done; !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("confirm: %v", err)
	}
	if v, _ := f.svc.Account(ctx, id); v.Email != "ana@gmail.com" {
		t.Fatalf("the account moved to %s after the clear", v.Email)
	}
}

// waitBlockedOn waits until some backend waits on a lock the holder pid
// holds, or fails if the confirmation finished without waiting.
func waitBlockedOn(t *testing.T, f *fixture, holder int, done chan error) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if f.count(`SELECT count(*) FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid))`, holder) > 0 {
			return
		}
		select {
		case err := <-done:
			done <- err
			return // it never touched the held account; the assertions judge it
		case <-time.After(5 * time.Millisecond):
		}
	}
	t.Fatal("the confirmation never waited on the held account")
}

func TestALinkThatLosesTheIdentityRaceKeepsTheTicket(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@gmail.com", goodPassword)
	squatter := f.liveSession(id)
	ticket := f.linkTicket(gmail("g-1", "ana@gmail.com"))
	// Another Google identity reaches the account after the conflict check.
	err := f.duringClear(id, ticket, func(tx pgx.Tx) {
		if _, err := tx.Exec(ctx, `INSERT INTO external_identities (provider, subject, account_id, created_at)
			VALUES ('google', 'g-other', $1, now())`, id); err != nil {
			t.Error(err)
		}
	})

	if !errors.Is(err, identity.ErrIdentityConflict) {
		t.Fatalf("got %v", err)
	}
	// The failed transaction changed nothing: no password cleared, no
	// session revoked.
	if !f.hasPassword(id) {
		t.Fatal("the losing clear removed the password")
	}
	if n := f.count(`SELECT count(*) FROM sessions WHERE id = $1 AND revoked_at IS NULL`, squatter); n != 1 {
		t.Fatal("the losing clear revoked a session")
	}
	if len(f.sessions.calls) != 0 {
		t.Fatalf("the losing clear revoked outside its transaction: %+v", f.sessions.calls)
	}
	if _, err := f.pool.Exec(ctx, `DELETE FROM external_identities WHERE subject = 'g-other'`); err != nil {
		t.Fatal(err)
	}
	f.clear(ticket, id)
}
