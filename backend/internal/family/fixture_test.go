package family_test

import (
	"context"
	"errors"
	"log/slog"
	"regexp"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail/mailtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

type fixture struct {
	t     *testing.T
	svc   *family.Service
	deps  family.Deps
	pool  *pgxpool.Pool
	mail  *mailtest.Recorder
	audit *audittest.Recorder
	now   time.Time
}

func newFixture(t *testing.T) *fixture {
	f := &fixture{
		t:     t,
		pool:  dbtest.New(t),
		mail:  &mailtest.Recorder{},
		audit: &audittest.Recorder{},
		now:   time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC),
	}
	clock := func() time.Time { return f.now }
	f.deps = family.Deps{
		Pool:          f.pool,
		Mail:          f.mail,
		Audit:         f.audit,
		Now:           clock,
		AppBaseURL:    "https://app.test",
		InviteLimiter: ratelimit.New(20, 24*time.Hour, clock),
		TokenLimiter:  ratelimit.New(10, time.Minute, clock),
		Log:           slog.New(slog.DiscardHandler),
	}
	f.svc = family.NewService(f.deps)
	return f
}

// failingMail records every attempt in its Recorder and fails the sends to
// the listed addresses.
type failingMail struct {
	*mailtest.Recorder
	fail map[string]bool
}

func (m failingMail) Send(c context.Context, msg mail.Message) error {
	m.Recorder.Send(c, msg)
	if m.fail[msg.To] {
		return errors.New("smtp down")
	}
	return nil
}

// failMailTo makes the service's mail fail for the given recipients; the
// recorder still sees every attempt.
func (f *fixture) failMailTo(addrs ...string) {
	f.t.Helper()
	fail := map[string]bool{}
	for _, a := range addrs {
		fail[a] = true
	}
	d := f.deps
	d.Mail = failingMail{Recorder: f.mail, fail: fail}
	f.svc = family.NewService(d)
}

// account inserts a guardian account directly; signup belongs to identity.
func (f *fixture) account(email string, verified bool) string {
	f.t.Helper()
	var verifiedAt any
	if verified {
		verifiedAt = f.now
	}
	var id string
	if err := f.pool.QueryRow(ctx, `INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $3, $3) RETURNING id::text`, email, verifiedAt, f.now).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// owner returns a verified account that owns a new family.
func (f *fixture) owner(email string) string {
	f.t.Helper()
	id := f.account(email, true)
	if _, err := f.svc.Create(ctx, id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

func (f *fixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

var tokenRE = regexp.MustCompile(`token=([A-Za-z0-9_-]+)`)

func (f *fixture) lastToken(addr string) string {
	f.t.Helper()
	msgs := f.mail.To(addr)
	if len(msgs) == 0 {
		f.t.Fatalf("no mail to %s", addr)
	}
	m := tokenRE.FindStringSubmatch(msgs[len(msgs)-1].Body)
	if m == nil {
		f.t.Fatalf("no token in newest mail to %s", addr)
	}
	return m[1]
}

// member adds a verified guardian to owner's family directly, without an
// invitation, for tests about what guardians can do.
func (f *fixture) member(ownerID, email string) string {
	f.t.Helper()
	id := f.account(email, true)
	if _, err := f.pool.Exec(ctx, `INSERT INTO family_members (family_id, account_id, role, joined_at)
		SELECT family_id, $2::uuid, 'guardian', $3 FROM family_members WHERE account_id = $1::uuid`, ownerID, id, f.now); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// guardian joins a new verified account to owner's family through a real
// invitation.
func (f *fixture) guardian(ownerID, email string) string {
	f.t.Helper()
	id := f.account(email, true)
	if _, err := f.svc.Invite(ctx, ownerID, email); err != nil {
		f.t.Fatal(err)
	}
	if _, err := f.svc.AcceptInvitation(ctx, id, f.lastToken(email)); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// waitForLockWaiter returns once a backend of this database is parked on
// the family row lock, i.e. the request under test waits behind the
// test's own transaction.
func (f *fixture) waitForLockWaiter() {
	f.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting bool
		if err := f.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database() AND wait_event_type = 'Lock'
			AND query LIKE 'SELECT 1 FROM families WHERE id = %FOR UPDATE')`).Scan(&waiting); err != nil {
			f.t.Fatal(err)
		}
		if waiting {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatal("no request waited on the family lock")
}
