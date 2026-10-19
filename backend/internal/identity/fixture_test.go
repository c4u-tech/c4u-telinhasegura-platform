package identity_test

import (
	"context"
	"errors"
	"log/slog"
	"regexp"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken/idtokentest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail/mailtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	goodPassword  = "uma senha longa o bastante"
	otherPassword = "outra senha longa o bastante"
)

type revokeCall struct{ AccountID, Except string }

type fakeRevoker struct {
	mu    sync.Mutex
	calls []revokeCall
	err   error
	once  func() // runs, outside the lock, on the next call only
}

func (f *fakeRevoker) RevokeAll(_ context.Context, accountID, except string) error {
	f.mu.Lock()
	f.calls = append(f.calls, revokeCall{accountID, except})
	err, once := f.err, f.once
	f.once = nil
	f.mu.Unlock()
	if once != nil {
		once()
	}
	return err
}

type fixture struct {
	t        *testing.T
	svc      *identity.Service
	pool     *pgxpool.Pool
	mail     *mailtest.Recorder
	audit    *audittest.Recorder
	sessions *fakeRevoker
	tokens   *idtokentest.Fake
	now      time.Time
	// onPolicyCheck runs once, inside the next password policy check, so a
	// test can land a concurrent change between a check and its write.
	onPolicyCheck func()
}

func newFixture(t *testing.T) *fixture {
	f := &fixture{
		t:        t,
		pool:     dbtest.New(t),
		mail:     &mailtest.Recorder{},
		audit:    &audittest.Recorder{},
		sessions: &fakeRevoker{},
		tokens:   &idtokentest.Fake{},
		now:      time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC),
	}
	f.svc = identity.NewService(identity.Deps{
		Store:      identity.Store{Pool: f.pool},
		Policy:     identity.PasswordPolicy{Breaches: fakeBreaches{hook: f.policyHook}, Log: slog.New(slog.DiscardHandler)},
		Hash:       identity.HashParams{Memory: 64, Time: 1, Threads: 1}, // cheap for tests; production uses DefaultHashParams
		Mail:       f.mail,
		Audit:      f.audit,
		Sessions:   f.sessions,
		IDTokens:   f.tokens,
		Now:        func() time.Time { return f.now },
		AppBaseURL: "https://app.test",
	})
	return f
}

func (f *fixture) policyHook() {
	if h := f.onPolicyCheck; h != nil {
		f.onPolicyCheck = nil
		h()
	}
}

var tokenRE = regexp.MustCompile(`token=([A-Za-z0-9_-]+)`)

// lastToken returns the token in the newest message sent to addr.
func (f *fixture) lastToken(addr string) string {
	f.t.Helper()
	msgs := f.mail.To(addr)
	if len(msgs) == 0 {
		f.t.Fatalf("no mail to %s", addr)
	}
	m := tokenRE.FindStringSubmatch(msgs[len(msgs)-1].Body)
	if m == nil {
		f.t.Fatalf("newest mail to %s carries no token: %q", addr, msgs[len(msgs)-1].Body)
	}
	return m[1]
}

func (f *fixture) lastMail(addr string) mail.Message {
	f.t.Helper()
	msgs := f.mail.To(addr)
	if len(msgs) == 0 {
		f.t.Fatalf("no mail to %s", addr)
	}
	return msgs[len(msgs)-1]
}

// signUpVerified creates a verified account and returns its id.
func (f *fixture) signUpVerified(email, password string) string {
	f.t.Helper()
	ctx := context.Background()
	if err := f.svc.SignUp(ctx, email, password, true, identity.TermsVersion); err != nil {
		f.t.Fatal(err)
	}
	if err := f.svc.ConfirmEmail(ctx, f.lastToken(email)); err != nil {
		f.t.Fatal(err)
	}
	return f.accountID(email)
}

// liveSession creates a real session row for the account and returns its
// id, as the handler passes current(r).ID.
func (f *fixture) liveSession(accountID string) string {
	f.t.Helper()
	is, err := f.realSessions().Create(context.Background(), accountID, session.Web, "")
	if err != nil {
		f.t.Fatal(err)
	}
	return is.Session.ID
}

// realSessions is the session service over the fixture's database; the
// identity service itself talks to fakeRevoker.
func (f *fixture) realSessions() *session.Service {
	return &session.Service{Pool: f.pool, Audit: f.audit, Now: func() time.Time { return f.now }}
}

func (f *fixture) accountID(email string) string {
	f.t.Helper()
	var id string
	if err := f.pool.QueryRow(context.Background(), `SELECT id::text FROM accounts WHERE email = $1`, email).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

func (f *fixture) verified(email string) bool {
	f.t.Helper()
	var v bool
	if err := f.pool.QueryRow(context.Background(), `SELECT email_verified_at IS NOT NULL FROM accounts WHERE email = $1`, email).Scan(&v); err != nil {
		f.t.Fatal(err)
	}
	return v
}

// gmail is a verified, authoritative Google identity for email.
func gmail(sub, email string) idtoken.Claims {
	return idtoken.Claims{Subject: sub, Email: email, EmailVerified: true, EmailAuthoritative: true}
}

// confirmation asserts err asks for the given confirmation and returns it.
func confirmation(t *testing.T, err error, code string) *identity.ConfirmationRequiredError {
	t.Helper()
	var c *identity.ConfirmationRequiredError
	if !errors.As(err, &c) || c.Code != code {
		t.Fatalf("got %v, want %s", err, code)
	}
	if c.Ticket == "" {
		t.Fatal("confirmation without a ticket")
	}
	return c
}
