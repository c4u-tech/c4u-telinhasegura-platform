package staff_test

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail/mailtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/totp"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

// mfaKey seals the TOTP secrets in tests.
var mfaKey = bytes.Repeat([]byte{7}, 32)

const ytID = "dQw4w9WgXcQ"

type fixture struct {
	t        *testing.T
	svc      *staff.Service
	deps     staff.Deps
	pool     *pgxpool.Pool
	audit    *audittest.Recorder // what staff records
	store    audit.Store         // what the directory reads: seed rows through it
	now      time.Time
	sessions *session.Service
	ids      *identity.Service
	fam      *family.Service
	par      *parental.Service
	cur      *curation.Service
	mail     *mailtest.Recorder
}

func newFixture(t *testing.T) *fixture {
	f := &fixture{
		t:     t,
		pool:  dbtest.New(t),
		audit: &audittest.Recorder{},
		mail:  &mailtest.Recorder{},
		now:   time.Date(2026, 10, 7, 12, 0, 0, 0, time.UTC),
	}
	clock := func() time.Time { return f.now }
	log := slog.New(slog.DiscardHandler)
	cheap := identity.HashParams{Memory: 64, Time: 1, Threads: 1}
	f.store = audit.Store{Pool: f.pool, Now: clock, Log: log}
	f.sessions = &session.Service{Pool: f.pool, Audit: f.audit, Now: clock}
	f.ids = identity.NewService(identity.Deps{Store: identity.Store{Pool: f.pool}, Policy: identity.PasswordPolicy{Log: log},
		Hash: cheap, Mail: f.mail, Audit: f.audit, Sessions: f.sessions, Now: clock, AppBaseURL: "https://app.test"})
	f.fam = family.NewService(family.Deps{Pool: f.pool, Mail: f.mail, Audit: f.audit, Now: clock, AppBaseURL: "https://app.test",
		InviteLimiter: ratelimit.New(20, 24*time.Hour, clock), TokenLimiter: ratelimit.New(10, time.Minute, clock), Log: log})
	f.par = parental.NewService(parental.Deps{Pool: f.pool, Mail: f.mail, Audit: f.audit, Now: clock, Hash: cheap,
		AppBaseURL: "https://app.test", CodeLimiter: ratelimit.New(20, time.Hour, clock), Log: log})
	f.cur = curation.NewService(curation.Deps{Pool: f.pool, Audit: f.audit, Now: clock, Log: log})
	f.deps = staff.Deps{Pool: f.pool, Audit: f.audit, Now: clock, MFAKey: mfaKey, Mail: f.mail, Log: log,
		Accounts: f.ids, Sessions: f.sessions, Families: f.fam, Devices: f.par, Content: f.cur, AuditLog: f.store,
		LookupLimiter: ratelimit.New(30, time.Hour, clock), ResetLimiter: ratelimit.New(3, time.Hour, clock)}
	f.svc = staff.NewService(f.deps)
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

// account inserts a verified guardian account.
func (f *fixture) account(email string) string {
	f.t.Helper()
	return f.id(`INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $2, $2) RETURNING id::text`, email, f.now)
}

func (f *fixture) unverified(email string) string {
	f.t.Helper()
	return f.id(`INSERT INTO accounts (email, adult_declared_at, created_at) VALUES ($1, $2, $2) RETURNING id::text`, email, f.now)
}

// admin inserts an account and grants it the admin role, as the server
// command does.
func (f *fixture) admin(email string) string {
	f.t.Helper()
	id := f.account(email)
	if _, err := f.svc.GrantAdmin(ctx, email); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// curator inserts an account holding the curator role directly, granted
// now.
func (f *fixture) curator(email string, role staff.DisplayRole) string {
	f.t.Helper()
	id := f.account(email)
	f.exec(`INSERT INTO platform_roles (account_id, role, display_role, verified_professional, granted_at)
		VALUES ($1::uuid, 'curator', $2, $3, $4)`, id, string(role), role.Professional(), f.now)
	return id
}

// video inserts a pending video in round 1.
func (f *fixture) video(youtubeID string) string {
	f.t.Helper()
	return f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'pending', $2, $2) RETURNING id::text`, youtubeID, f.now)
}

// audited counts the entries of event e, under any account.
func (f *fixture) audited(e audit.Event) int {
	n := 0
	for _, x := range f.audit.Entries {
		if x.Event == e {
			n++
		}
	}
	return n
}

// moderator inserts an account holding the moderator role directly,
// granted now.
func (f *fixture) moderator(email string) string {
	f.t.Helper()
	id := f.account(email)
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'moderator', $2)`, id, f.now)
	return id
}

// has reports whether the account holds the role, read anew from the
// database.
func (f *fixture) has(accountID string, r staff.Role) bool {
	f.t.Helper()
	got, err := f.svc.FirstRole(ctx, accountID, r)
	if err != nil {
		f.t.Fatal(err)
	}
	return got == r
}

// session signs accountID in on a mobile session and returns its ID.
func (f *fixture) session(accountID string) string {
	f.t.Helper()
	is, err := f.sessions.Create(ctx, accountID, session.Mobile, "Pixel 9")
	if err != nil {
		f.t.Fatal(err)
	}
	return is.Session.ID
}

// code is secret's TOTP code at the fixture's clock.
func (f *fixture) code(secret string) string {
	f.t.Helper()
	c, err := totp.Code(secret, totp.Step(f.now))
	if err != nil {
		f.t.Fatal(err)
	}
	return c
}

// wrongCode is a well-formed code outside the ±1 step window.
func (f *fixture) wrongCode(secret string) string {
	f.t.Helper()
	c, err := totp.Code(secret, totp.Step(f.now)+5)
	if err != nil {
		f.t.Fatal(err)
	}
	return c
}

// elevatedUntil reads a session's elevation, the zero time for none.
func (f *fixture) elevatedUntil(sessionID string) time.Time {
	f.t.Helper()
	var at *time.Time
	if err := f.pool.QueryRow(ctx, `SELECT elevated_until FROM sessions WHERE id = $1::uuid`, sessionID).Scan(&at); err != nil {
		f.t.Fatal(err)
	}
	if at == nil {
		return time.Time{}
	}
	return at.UTC()
}

// owner makes accountID own a new family and returns the family's ID.
func (f *fixture) owner(accountID string) string {
	f.t.Helper()
	fam, err := f.fam.Create(ctx, accountID)
	if err != nil {
		f.t.Fatal(err)
	}
	return fam.ID
}

// minor registers a child named Lia in accountID's family.
func (f *fixture) minor(accountID string) string {
	f.t.Helper()
	m, err := f.fam.CreateMinor(ctx, accountID,
		family.MinorInput{Nickname: "Lia", Avatar: "fox", AgeBand: family.Age5To8}, family.ConsentPolicyVersion)
	if err != nil {
		f.t.Fatal(err)
	}
	return m.ID
}

// device inserts a device of familyID playing for minorID, labelled as a
// guardian would label it, linked now and last seen at seen.
func (f *fixture) device(familyID, minorID string, seen time.Time) string {
	f.t.Helper()
	return f.id(`INSERT INTO devices (family_id, minor_id, token_hash, label, linked_at, last_seen_at)
		VALUES ($1::uuid, $2::uuid, sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'Tablet da Lia', $3, $4) RETURNING id::text`,
		familyID, minorID, f.now, seen)
}

// linkGoogle links a Google identity to the account.
func (f *fixture) linkGoogle(accountID string) {
	f.t.Helper()
	f.exec(`INSERT INTO external_identities (provider, subject, account_id, created_at) VALUES ('google', $1, $2::uuid, $3)`,
		"sub-"+accountID, accountID, f.now)
}

// enrollFactor gives the account a confirmed MFA factor directly.
func (f *fixture) enrollFactor(accountID string) {
	f.t.Helper()
	f.exec(`INSERT INTO staff_mfa (account_id, secret_sealed, confirmed_at, created_at) VALUES ($1::uuid, '\x00', $2, $2)`,
		accountID, f.now)
}

// meta decodes stored audit metadata; nil for none.
func meta(t *testing.T, raw json.RawMessage) map[string]string {
	t.Helper()
	if raw == nil {
		return nil
	}
	var m map[string]string
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("metadata %s: %v", raw, err)
	}
	return m
}
