package session_test

import (
	"context"
	"crypto/rand"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

const day = 24 * time.Hour

type fixture struct {
	pool  *pgxpool.Pool
	svc   *session.Service
	audit *audittest.Recorder
	now   time.Time
	acct  string
	other string
}

func newFixture(t *testing.T) *fixture {
	pool := dbtest.New(t)
	f := &fixture{pool: pool, audit: &audittest.Recorder{}, now: time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC)}
	f.svc = &session.Service{Pool: pool, Audit: f.audit, Now: func() time.Time { return f.now }}
	for _, p := range []*string{&f.acct, &f.other} {
		if err := pool.QueryRow(context.Background(), `INSERT INTO accounts (email, adult_declared_at, created_at)
			VALUES (gen_random_uuid()::text || '@x.co', now(), now()) RETURNING id::text`).Scan(p); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func (f *fixture) create(t *testing.T, c session.Client) session.Issued {
	t.Helper()
	is, err := f.svc.Create(context.Background(), f.acct, c, "Pixel 9")
	if err != nil {
		t.Fatal(err)
	}
	return is
}

func TestWebSessionAuthenticatesByItsCookieSecretOnly(t *testing.T) {
	f := newFixture(t)
	is := f.create(t, session.Web)
	if is.Session.CSRFToken == "" || is.RefreshToken != "" {
		t.Fatalf("web session: csrf=%q refresh=%q", is.Session.CSRFToken, is.RefreshToken)
	}
	got, err := f.svc.Authenticate(context.Background(), session.Web, is.Secret)
	if err != nil || got.ID != is.Session.ID || got.AccountID != f.acct {
		t.Fatalf("got %+v, %v", got, err)
	}
	if _, err := f.svc.Authenticate(context.Background(), session.Mobile, is.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatalf("web secret accepted as a bearer token: %v", err)
	}
}

func TestMobileAccessTokenExpiresAfter15Minutes(t *testing.T) {
	f := newFixture(t)
	is := f.create(t, session.Mobile)
	if is.RefreshToken == "" || !is.AccessExpiresAt.Equal(f.now.Add(15*time.Minute)) {
		t.Fatalf("mobile issue: %+v", is)
	}
	f.now = f.now.Add(15 * time.Minute)
	if _, err := f.svc.Authenticate(context.Background(), session.Mobile, is.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatalf("expired access token accepted: %v", err)
	}
}

func TestIdleAndAbsoluteTimeouts(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	idle := f.create(t, session.Web)
	f.now = f.now.Add(30*day + time.Second)
	if _, err := f.svc.Authenticate(ctx, session.Web, idle.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatalf("idle web session accepted: %v", err)
	}

	busy := f.create(t, session.Web)
	for range 4 { // active every 25 days: never idle, but 100 days old
		f.now = f.now.Add(25 * day)
		_, _ = f.svc.Authenticate(ctx, session.Web, busy.Secret)
	}
	if _, err := f.svc.Authenticate(ctx, session.Web, busy.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatalf("session past its absolute timeout accepted: %v", err)
	}
}

func TestRefreshRotatesBothTokens(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	is := f.create(t, session.Mobile)
	f.now = f.now.Add(20 * time.Minute)

	next, err := f.svc.Refresh(ctx, is.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	if next.Secret == is.Secret || next.RefreshToken == is.RefreshToken || next.Session.ID != is.Session.ID {
		t.Fatalf("not rotated: %+v", next)
	}
	if _, err := f.svc.Authenticate(ctx, session.Mobile, next.Secret); err != nil {
		t.Fatalf("new access token refused: %v", err)
	}
}

func TestRefreshReuseRevokesTheSession(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	is := f.create(t, session.Mobile)
	next, _ := f.svc.Refresh(ctx, is.RefreshToken)

	if _, err := f.svc.Refresh(ctx, is.RefreshToken); !errors.Is(err, session.ErrInvalidToken) {
		t.Fatalf("reused refresh token: %v", err)
	}
	if _, err := f.svc.Authenticate(ctx, session.Mobile, next.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatalf("session survived refresh reuse: %v", err)
	}
	if !f.audit.Has(f.acct, audit.RefreshReused) {
		t.Fatal("reuse not audited")
	}
	if _, err := f.svc.Refresh(ctx, "never-issued"); !errors.Is(err, session.ErrInvalidToken) {
		t.Fatalf("unknown refresh token: %v", err)
	}
}

func TestEveryReuseOfARefreshTokenIsAudited(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	is := f.create(t, session.Mobile)
	_, _ = f.svc.Refresh(ctx, is.RefreshToken)
	for range 2 {
		if _, err := f.svc.Refresh(ctx, is.RefreshToken); !errors.Is(err, session.ErrInvalidToken) {
			t.Fatalf("reused refresh token: %v", err)
		}
	}
	n := 0
	for _, e := range f.audit.Entries {
		if e.AccountID == f.acct && e.Event == audit.RefreshReused {
			n++
		}
	}
	if n != 2 {
		t.Fatalf("RefreshReused audited %d times, want 2", n)
	}
}

func TestListShowsActiveSessionsOfTheAccountOnly(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.create(t, session.Web)
	b := f.create(t, session.Mobile)
	_, _ = f.svc.Create(ctx, f.other, session.Web, "")
	_ = f.svc.Revoke(ctx, f.acct, b.Session.ID)

	list, err := f.svc.List(ctx, f.acct)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != a.Session.ID || list[0].DeviceLabel != "Pixel 9" {
		t.Fatalf("list %+v", list)
	}
}

func TestRevocationIsImmediateAndScopedToTheAccount(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.create(t, session.Web)
	b := f.create(t, session.Web)
	c := f.create(t, session.Mobile)

	if err := f.svc.Revoke(ctx, f.other, a.Session.ID); !errors.Is(err, session.ErrNotFound) {
		t.Fatalf("another account revoked a session: %v", err)
	}
	if err := f.svc.Revoke(ctx, f.acct, "not-a-uuid"); !errors.Is(err, session.ErrNotFound) {
		t.Fatalf("malformed id: %v", err)
	}
	if err := f.svc.RevokeAll(ctx, f.acct, a.Session.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Authenticate(ctx, session.Web, b.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatal("revoked web session still works")
	}
	if _, err := f.svc.Authenticate(ctx, session.Mobile, c.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatal("revoked mobile session still works")
	}
	if _, err := f.svc.Authenticate(ctx, session.Web, a.Secret); err != nil {
		t.Fatalf("excepted session revoked: %v", err)
	}
	if err := f.svc.SignOut(ctx, f.acct, a.Session.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Authenticate(ctx, session.Web, a.Secret); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatal("signed-out session still works")
	}
	if !f.audit.Has(f.acct, audit.SignedOut) || !f.audit.Has(f.acct, audit.SessionRevoked) {
		t.Fatal("sign-out or revocation not audited")
	}
}

func TestReauthWindow(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	is := f.create(t, session.Web) // signing in counts as authenticating

	s, _ := f.svc.Authenticate(ctx, session.Web, is.Secret)
	if err := f.svc.RequireRecentReauth(s); err != nil {
		t.Fatalf("fresh sign-in not recent: %v", err)
	}
	f.now = f.now.Add(5*time.Minute + time.Second)
	s, _ = f.svc.Authenticate(ctx, session.Web, is.Secret)
	if err := f.svc.RequireRecentReauth(s); !errors.Is(err, session.ErrReauthRequired) {
		t.Fatalf("stale session passed: %v", err)
	}
	if err := f.svc.MarkReauth(ctx, s.ID); err != nil {
		t.Fatal(err)
	}
	s, _ = f.svc.Authenticate(ctx, session.Web, is.Secret)
	if err := f.svc.RequireRecentReauth(s); err != nil {
		t.Fatalf("after MarkReauth: %v", err)
	}
}

func TestCreateRejectsUnknownClients(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.Create(context.Background(), f.acct, "tv", ""); !errors.Is(err, session.ErrInvalidClient) {
		t.Fatalf("got %v", err)
	}
}

func TestElevationIsPerSessionAndSurvivesRefresh(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	mob := f.create(t, session.Mobile)
	web := f.create(t, session.Web)
	until := f.now.Add(30 * time.Minute)
	inTx := func(fn func(pgx.Tx) error) error {
		tx, err := f.pool.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		if err := fn(tx); err != nil {
			return err
		}
		return tx.Commit(ctx)
	}
	elevate := func(id, account string) error {
		return inTx(func(tx pgx.Tx) error { return session.MarkElevated(ctx, tx, id, account, until) })
	}

	if err := elevate(mob.Session.ID, f.acct); err != nil {
		t.Fatal(err)
	}
	if err := elevate(mob.Session.ID, f.other); !errors.Is(err, session.ErrNotFound) {
		t.Fatalf("elevating another account's session: %v", err)
	}
	got, err := f.svc.Authenticate(ctx, session.Mobile, mob.Secret)
	if err != nil || !got.ElevatedUntil.Equal(until) || !f.svc.Elevated(got) {
		t.Fatalf("elevated session: %+v %v", got, err)
	}
	w, err := f.svc.Authenticate(ctx, session.Web, web.Secret)
	if err != nil || f.svc.Elevated(w) {
		t.Fatalf("the elevation leaked to the account's other session: %+v %v", w, err)
	}
	next, err := f.svc.Refresh(ctx, mob.RefreshToken)
	if err != nil || !next.Session.ElevatedUntil.Equal(until) {
		t.Fatalf("refresh dropped the elevation: %+v %v", next.Session, err)
	}

	f.now = until.Add(-time.Second)
	if !f.svc.Elevated(got) {
		t.Fatal("not elevated one second before the end")
	}
	f.now = until
	if f.svc.Elevated(got) {
		t.Fatal("still elevated at the instant it ends")
	}

	if err := f.svc.Revoke(ctx, f.acct, web.Session.ID); err != nil {
		t.Fatal(err)
	}
	if err := elevate(web.Session.ID, f.acct); !errors.Is(err, session.ErrNotFound) {
		t.Fatalf("elevating a revoked session: %v", err)
	}
	if err := inTx(func(tx pgx.Tx) error { return session.ClearElevation(ctx, tx, f.acct) }); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := f.pool.QueryRow(ctx, `SELECT count(*) FROM sessions WHERE elevated_until IS NOT NULL`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("%d sessions still elevated (%v)", n, err)
	}
}

func TestRevokeAllTxEndsTheSessionsWithItsTransaction(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	mob := f.create(t, session.Mobile)
	web := f.create(t, session.Web)
	gone := f.create(t, session.Web)
	if err := f.svc.Revoke(ctx, f.acct, gone.Session.ID); err != nil {
		t.Fatal(err)
	}
	theirs, err := f.svc.Create(ctx, f.other, session.Web, "")
	if err != nil {
		t.Fatal(err)
	}
	revokeAll := func(commit bool) int {
		t.Helper()
		tx, err := f.pool.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		n, err := session.RevokeAllTx(ctx, tx, f.acct, f.now)
		if err != nil {
			t.Fatal(err)
		}
		if commit {
			if err := tx.Commit(ctx); err != nil {
				t.Fatal(err)
			}
		}
		return n
	}

	if n := revokeAll(false); n != 2 {
		t.Fatalf("revoked %d sessions, want the 2 live ones", n)
	}
	if _, err := f.svc.Authenticate(ctx, session.Mobile, mob.Secret); err != nil {
		t.Fatalf("a rolled-back revocation ended the session: %v", err)
	}
	if n := revokeAll(true); n != 2 {
		t.Fatalf("revoked %d sessions, want 2", n)
	}
	for _, is := range []session.Issued{mob, web} {
		if _, err := f.svc.Authenticate(ctx, is.Session.Client, is.Secret); !errors.Is(err, session.ErrUnauthenticated) {
			t.Errorf("%s session after the commit: %v", is.Session.Client, err)
		}
	}
	if _, err := f.svc.Authenticate(ctx, session.Web, theirs.Secret); err != nil {
		t.Fatalf("another account's session ended: %v", err)
	}
	n := 0
	for _, e := range f.audit.Entries {
		if e.Event == audit.SessionRevoked {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("%d session_revoked events, want the 1 Revoke wrote: the caller's action is RevokeAllTx's record", n)
	}
	if _, err := session.RevokeAllTx(ctx, nil, "abc", f.now); !errors.Is(err, session.ErrNotFound) {
		t.Fatalf("a malformed id: %v", err)
	}
}

// seed inserts a session of the fixture's account with the given times;
// revoked is nil or a time.Time.
func (f *fixture) seed(t *testing.T, c session.Client, created, lastSeen time.Time, revoked any) string {
	t.Helper()
	var id string
	if err := f.pool.QueryRow(context.Background(), `INSERT INTO sessions
		(account_id, client, secret_hash, created_at, last_seen_at, revoked_at)
		VALUES ($1::uuid, $2, $3, $4, $5, $6) RETURNING id::text`,
		f.acct, string(c), []byte(rand.Text()), created, lastSeen, revoked).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func TestSweepDeletesSessionsEndedNinetyDaysAgo(t *testing.T) {
	f := newFixture(t)
	now, m := f.now, time.Minute
	gone := map[string]string{
		"revoked 90 days ago":                   f.seed(t, session.Web, now.Add(-100*day), now.Add(-95*day), now.Add(-90*day-m)),
		"web idle, expired 90 days ago":         f.seed(t, session.Web, now.Add(-121*day), now.Add(-120*day-m), nil),
		"web past its 90 days, 90 days ago":     f.seed(t, session.Web, now.Add(-180*day-m), now, nil),
		"mobile idle, expired 90 days ago":      f.seed(t, session.Mobile, now.Add(-151*day), now.Add(-150*day-m), nil),
		"mobile past its 180 days, 90 days ago": f.seed(t, session.Mobile, now.Add(-270*day-m), now, nil),
	}
	keep := map[string]string{
		"revoked 89 days ago":           f.seed(t, session.Web, now.Add(-100*day), now.Add(-95*day), now.Add(-89*day)),
		"web idle, expired 89 days ago": f.seed(t, session.Web, now.Add(-119*day), now.Add(-119*day), nil),
		// Idle 149 days: a web session would be gone, a mobile one is not.
		"mobile idle 149 days":    f.seed(t, session.Mobile, now.Add(-149*day), now.Add(-149*day), nil),
		"mobile live at 179 days": f.seed(t, session.Mobile, now.Add(-179*day), now, nil),
	}
	if err := f.svc.Sweep(context.Background()); err != nil {
		t.Fatal(err)
	}
	exists := func(id string) bool {
		var ok bool
		if err := f.pool.QueryRow(context.Background(), `SELECT EXISTS (SELECT 1 FROM sessions WHERE id = $1::uuid)`, id).Scan(&ok); err != nil {
			t.Fatal(err)
		}
		return ok
	}
	for name, id := range gone {
		if exists(id) {
			t.Errorf("%s: kept", name)
		}
	}
	for name, id := range keep {
		if !exists(id) {
			t.Errorf("%s: deleted", name)
		}
	}
}
