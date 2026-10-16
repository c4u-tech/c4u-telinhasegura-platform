package parental_test

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail/mailtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

const goodPIN = "2580"

type fixture struct {
	t        *testing.T
	svc      *parental.Service
	deps     parental.Deps
	fam      *family.Service
	sessions *session.Service
	pool     *pgxpool.Pool
	mail     *mailtest.Recorder
	audit    *audittest.Recorder
	now      time.Time
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
	log := slog.New(slog.DiscardHandler)
	f.deps = parental.Deps{
		Pool:        f.pool,
		Mail:        f.mail,
		Audit:       f.audit,
		Now:         clock,
		Hash:        identity.HashParams{Memory: 64, Time: 1, Threads: 1},
		AppBaseURL:  "https://app.test",
		CodeLimiter: ratelimit.New(20, time.Hour, clock),
		Log:         log,
	}
	f.svc = parental.NewService(f.deps)
	f.fam = family.NewService(family.Deps{
		Pool:          f.pool,
		Mail:          f.mail,
		Audit:         f.audit,
		Now:           clock,
		AppBaseURL:    "https://app.test",
		InviteLimiter: ratelimit.New(20, 24*time.Hour, clock),
		TokenLimiter:  ratelimit.New(10, time.Minute, clock),
		Log:           log,
	})
	f.sessions = &session.Service{Pool: f.pool, Audit: f.audit, Now: clock}
	return f
}

// rebuild changes the deps and rebuilds the service under test.
func (f *fixture) rebuild(change func(*parental.Deps)) {
	change(&f.deps)
	f.svc = parental.NewService(f.deps)
}

type failingMail struct{ *mailtest.Recorder }

func (m failingMail) Send(c context.Context, msg mail.Message) error {
	m.Recorder.Send(c, msg)
	return errors.New("smtp down")
}

// failMail makes every send fail; the recorder still sees each attempt.
func (f *fixture) failMail() {
	f.rebuild(func(d *parental.Deps) { d.Mail = failingMail{f.mail} })
}

// account inserts a verified guardian account directly.
func (f *fixture) account(email string) string {
	f.t.Helper()
	var id string
	if err := f.pool.QueryRow(ctx, `INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $2, $2) RETURNING id::text`, email, f.now).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// owner returns an account that owns a new family.
func (f *fixture) owner(email string) string {
	f.t.Helper()
	id := f.account(email)
	if _, err := f.fam.Create(ctx, id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// member adds a guardian to owner's family directly.
func (f *fixture) member(ownerID, email string) string {
	f.t.Helper()
	id := f.account(email)
	if _, err := f.pool.Exec(ctx, `INSERT INTO family_members (family_id, account_id, role, joined_at)
		SELECT family_id, $2::uuid, 'guardian', $3 FROM family_members WHERE account_id = $1::uuid`, ownerID, id, f.now); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// minor registers a child in accountID's family, then moves the clock one
// second on, so children list in the order they were made.
func (f *fixture) minor(accountID, nickname string) string {
	f.t.Helper()
	m, err := f.fam.CreateMinor(ctx, accountID,
		family.MinorInput{Nickname: nickname, Avatar: "fox", AgeBand: family.Age5To8}, family.ConsentPolicyVersion)
	if err != nil {
		f.t.Fatal(err)
	}
	f.now = f.now.Add(time.Second)
	return m.ID
}

func (f *fixture) withPIN(accountID string) {
	f.t.Helper()
	if err := f.svc.SetPIN(ctx, accountID, goodPIN); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) familyID(accountID string) string {
	f.t.Helper()
	var id string
	if err := f.pool.QueryRow(ctx, `SELECT family_id::text FROM family_members WHERE account_id = $1::uuid`, accountID).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// session starts a mobile session and returns its ID.
func (f *fixture) session(accountID string) string {
	f.t.Helper()
	id, _ := f.sessionToken(accountID)
	return id
}

// sessionToken starts a mobile session and returns its ID and access token.
func (f *fixture) sessionToken(accountID string) (id, token string) {
	f.t.Helper()
	is, err := f.sessions.Create(ctx, accountID, session.Mobile, "Pixel 9")
	if err != nil {
		f.t.Fatal(err)
	}
	return is.Session.ID, is.Secret
}

// assertEnded fails unless the session was revoked and its token no longer
// authenticates.
func (f *fixture) assertEnded(sessionID, token string) {
	f.t.Helper()
	if n := f.count(`SELECT count(*) FROM sessions WHERE id = $1::uuid AND revoked_at IS NOT NULL`, sessionID); n != 1 {
		f.t.Fatal("the session was not revoked")
	}
	if _, err := f.sessions.Authenticate(ctx, session.Mobile, token); err == nil {
		f.t.Fatal("the session still authenticates")
	}
}

// audited counts the entries of event e under accountID.
func (f *fixture) audited(accountID string, e audit.Event) int {
	n := 0
	for _, x := range f.audit.Entries {
		if x.AccountID == accountID && x.Event == e {
			n++
		}
	}
	return n
}

func (f *fixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

// linked links a device to minorID through a real code.
func (f *fixture) linked(accountID, minorID string) parental.Redeemed {
	f.t.Helper()
	lc, err := f.svc.CreateLinkCode(ctx, accountID, minorID)
	if err != nil {
		f.t.Fatal(err)
	}
	out, err := f.svc.Redeem(ctx, lc.Code, "Tablet")
	if err != nil {
		f.t.Fatal(err)
	}
	return out
}
