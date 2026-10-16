package privacy_test

import (
	"context"
	"encoding/json"
	"log/slog"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken/idtokentest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail/mailtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

// Seeded string secrets: no export may carry any of them.
const (
	passwordHash    = "$argon2id$v=19$seeded-password-hash"
	csrfToken       = "seeded-csrf-token"
	pinHash         = "$argon2id$v=19$seeded-pin-hash"
	providerSubject = "seeded-google-subject"
)

type fixture struct {
	t       *testing.T
	svc     *privacy.Service
	deps    privacy.Deps
	pool    *pgxpool.Pool
	mail    *mailtest.Recorder
	audit   *audittest.Recorder
	ids     *idtokentest.Fake
	apple   *fakeRevoker
	now     time.Time
	secrets [][]byte // every seeded hash, for the export scan
}

func newFixture(t *testing.T) *fixture {
	f := &fixture{
		t:     t,
		pool:  dbtest.New(t),
		mail:  &mailtest.Recorder{},
		audit: &audittest.Recorder{},
		ids:   &idtokentest.Fake{},
		apple: &fakeRevoker{},
		now:   time.Date(2026, 10, 4, 12, 0, 0, 0, time.UTC),
	}
	clock := func() time.Time { return f.now }
	f.deps = privacy.Deps{
		Pool:          f.pool,
		Mail:          f.mail,
		Audit:         f.audit,
		IDTokens:      f.ids,
		Apple:         f.apple,
		Now:           clock,
		ExportLimiter: ratelimit.New(5, time.Hour, clock),
		Log:           slog.New(slog.DiscardHandler),
	}
	f.svc = privacy.NewService(f.deps)
	return f
}

func (f *fixture) exec(sql string, args ...any) {
	f.t.Helper()
	if _, err := f.pool.Exec(ctx, sql, args...); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

func (f *fixture) id(sql string, args ...any) string {
	f.t.Helper()
	var id string
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// secret returns a distinct seeded hash and remembers it for the scan.
func (f *fixture) secret(name string) []byte {
	b := []byte("seeded-" + name)
	f.secrets = append(f.secrets, b)
	return b
}

// account inserts a verified guardian with a password, as identity would.
func (f *fixture) account(email string) string {
	f.t.Helper()
	return f.id(`INSERT INTO accounts (email, password_hash, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $3, $3, $3) RETURNING id::text`, email, passwordHash, f.now)
}

// bareAccount inserts an unverified account without a password, as a
// provider signup or an abandoned email signup leaves it.
func (f *fixture) bareAccount(email string) string {
	f.t.Helper()
	return f.id(`INSERT INTO accounts (email, adult_declared_at, created_at)
		VALUES ($1, $2, $2) RETURNING id::text`, email, f.now)
}

// session seeds a mobile session of the account and returns its ID.
func (f *fixture) session(accountID, label string) string {
	f.t.Helper()
	return f.id(`INSERT INTO sessions (account_id, client, device_label, secret_hash, refresh_hash, csrf_token,
		reauth_at, created_at, last_seen_at) VALUES ($1::uuid, 'mobile', $2, $3, $4, $5, $6, $6, $6) RETURNING id::text`,
		accountID, label, f.secret("session-"+accountID+label), f.secret("refresh-"+accountID+label), csrfToken, f.now)
}

// family makes ownerID the owner of a new family and returns its ID.
func (f *fixture) family(ownerID string) string {
	f.t.Helper()
	id := f.id(`INSERT INTO families (created_at) VALUES ($1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO family_members (family_id, account_id, role, joined_at) VALUES ($1::uuid, $2::uuid, 'owner', $3)`,
		id, ownerID, f.now)
	return id
}

// join adds accountID to the family as a guardian, a minute later.
func (f *fixture) join(familyID, accountID string) {
	f.t.Helper()
	f.exec(`INSERT INTO family_members (family_id, account_id, role, joined_at) VALUES ($1::uuid, $2::uuid, 'guardian', $3)`,
		familyID, accountID, f.now.Add(time.Minute))
}

// minor adds a child whose consent grantedBy gave now, and returns its ID.
func (f *fixture) minor(familyID, grantedBy, nickname string) string {
	f.t.Helper()
	id := f.id(`INSERT INTO minors (family_id, nickname, avatar, age_band, created_at, updated_at)
		VALUES ($1::uuid, $2, 'fox', '5-8', $3, $3) RETURNING id::text`, familyID, nickname, f.now)
	f.exec(`INSERT INTO minor_consents (minor_id, family_id, granted_by, policy_version, granted_at)
		VALUES ($1::uuid, $2::uuid, $3::uuid, '2026-10-03', $4)`, id, familyID, grantedBy, f.now)
	return id
}

func (f *fixture) device(familyID, minorID, label string) string {
	f.t.Helper()
	return f.id(`INSERT INTO devices (family_id, minor_id, token_hash, label, linked_at, last_seen_at)
		VALUES ($1::uuid, $2::uuid, $3, $4, $5, $5) RETURNING id::text`, familyID, minorID, f.secret("device-"+label), label, f.now)
}

func (f *fixture) pin(familyID string) {
	f.t.Helper()
	f.exec(`INSERT INTO family_pins (family_id, pin_hash, updated_at) VALUES ($1::uuid, $2, $3)`, familyID, pinHash, f.now)
}

func (f *fixture) invitation(familyID, invitedBy, email string) {
	f.t.Helper()
	f.exec(`INSERT INTO family_invitations (token_hash, family_id, email, invited_by, created_at, expires_at)
		VALUES ($1, $2::uuid, $3, $4::uuid, $5, $6)`, f.secret("invite-"+email), familyID, email, invitedBy, f.now, f.now.Add(7*24*time.Hour))
}

func (f *fixture) linkCode(familyID, minorID, createdBy string) {
	f.t.Helper()
	f.exec(`INSERT INTO link_codes (code_hash, family_id, minor_id, created_by, expires_at)
		VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5)`, f.secret("code-"+minorID), familyID, minorID, createdBy, f.now.Add(10*time.Minute))
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

// exportJSON exports accountID and returns the document as JSON text.
func (f *fixture) exportJSON(accountID string) string {
	f.t.Helper()
	e, err := f.svc.Export(ctx, accountID)
	if err != nil {
		f.t.Fatal(err)
	}
	b, err := json.Marshal(e)
	if err != nil {
		f.t.Fatal(err)
	}
	return string(b)
}
