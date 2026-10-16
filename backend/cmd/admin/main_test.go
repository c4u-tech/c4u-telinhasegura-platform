package main

import (
	"bytes"
	"context"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

// testDB returns a migrated dbtest schema and an environment whose
// DATABASE_URL reaches it, through the search_path runtime parameter.
func testDB(t *testing.T) (*pgxpool.Pool, func(string) string) {
	t.Helper()
	pool := dbtest.New(t)
	u, err := url.Parse(os.Getenv("TEST_DATABASE_URL"))
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	q.Set("search_path", pool.Config().ConnConfig.RuntimeParams["search_path"])
	u.RawQuery = q.Encode()
	return pool, func(k string) string {
		if k == "DATABASE_URL" {
			return u.String()
		}
		return ""
	}
}

func count(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func account(t *testing.T, pool *pgxpool.Pool, email string) string {
	t.Helper()
	var id string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $2, $2) RETURNING id::text`, email, time.Now()).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func TestGrantAndRevokeAdmin(t *testing.T) {
	pool, env := testDB(t)
	ana := account(t, pool, "ana@example.com")

	var out bytes.Buffer
	if err := run(ctx, []string{"grant-admin", " Ana@Example.com "}, env, &out); err != nil {
		t.Fatal(err)
	}
	if n := count(t, pool, `SELECT count(*) FROM platform_roles WHERE account_id = $1::uuid AND role = 'admin'
		AND granted_by IS NULL`, ana); n != 1 {
		t.Fatal("no admin role")
	}
	if n := count(t, pool, `SELECT count(*) FROM audit_events WHERE account_id = $1::uuid AND event = 'admin_granted'`, ana); n != 1 {
		t.Fatal("no admin_granted audit")
	}
	if !strings.Contains(out.String(), ana) || strings.Contains(strings.ToLower(out.String()), "ana@example.com") {
		t.Fatalf("output %q must name the account ID, never the email", out.String())
	}

	if err := run(ctx, []string{"revoke-admin", "ana@example.com"}, env, &out); err != nil {
		t.Fatal(err)
	}
	if n := count(t, pool, `SELECT count(*) FROM platform_roles`); n != 0 {
		t.Fatal("the admin role survived the revocation")
	}
	if n := count(t, pool, `SELECT count(*) FROM audit_events WHERE account_id = $1::uuid AND event = 'admin_revoked'`, ana); n != 1 {
		t.Fatal("no admin_revoked audit")
	}
}

func TestUnknownEmailChangesNothing(t *testing.T) {
	pool, env := testDB(t)
	account(t, pool, "ana@example.com")
	for _, cmd := range []string{"grant-admin", "revoke-admin"} {
		if err := run(ctx, []string{cmd, "nobody@example.com"}, env, &bytes.Buffer{}); err == nil {
			t.Fatalf("%s of an unknown email succeeded", cmd)
		}
	}
	if n := count(t, pool, `SELECT (SELECT count(*) FROM platform_roles) + (SELECT count(*) FROM audit_events)`); n != 0 {
		t.Fatalf("an unknown email changed %d rows", n)
	}
}

func TestUsage(t *testing.T) {
	env := func(string) string { return "postgres://unused" }
	for _, args := range [][]string{nil, {"grant-admin"}, {"grant-admin", "a@b.c", "extra"}, {"make-admin", "a@b.c"}} {
		if err := run(ctx, args, env, &bytes.Buffer{}); err == nil || !strings.Contains(err.Error(), "usage") {
			t.Errorf("%q: %v", args, err)
		}
	}
	if err := run(ctx, []string{"grant-admin", "a@b.c"}, func(string) string { return "" }, &bytes.Buffer{}); err == nil ||
		!strings.Contains(err.Error(), "DATABASE_URL") {
		t.Fatalf("no DATABASE_URL: %v", err)
	}
}

func TestResetMFA(t *testing.T) {
	pool, env := testDB(t)
	ana := account(t, pool, "ana@example.com")
	for _, sql := range []string{
		`INSERT INTO staff_mfa (account_id, secret_sealed, confirmed_at, created_at) VALUES ($1::uuid, '\x00', now(), now())`,
		`INSERT INTO staff_recovery_codes (account_id, code_hash, created_at) VALUES ($1::uuid, '\x01', now())`,
		`INSERT INTO sessions (account_id, client, secret_hash, csrf_token, created_at, last_seen_at, elevated_until)
			VALUES ($1::uuid, 'web', '\x02', 'csrf', now(), now(), now() + interval '30 minutes')`,
	} {
		if _, err := pool.Exec(ctx, sql, ana); err != nil {
			t.Fatal(err)
		}
	}

	var out bytes.Buffer
	if err := run(ctx, []string{"reset-mfa", " Ana@Example.com "}, env, &out); err != nil {
		t.Fatal(err)
	}
	for _, sql := range []string{
		`SELECT count(*) FROM staff_mfa`,
		`SELECT count(*) FROM staff_recovery_codes`,
		`SELECT count(*) FROM sessions WHERE elevated_until IS NOT NULL`,
	} {
		if n := count(t, pool, sql); n != 0 {
			t.Fatalf("%s: %d after the reset", sql, n)
		}
	}
	if n := count(t, pool, `SELECT count(*) FROM audit_events WHERE account_id = $1::uuid AND event = 'mfa_reset'`, ana); n != 1 {
		t.Fatal("no mfa_reset audit")
	}
	if !strings.Contains(out.String(), "mfa reset for account "+ana) || strings.Contains(strings.ToLower(out.String()), "ana@example.com") {
		t.Fatalf("output %q must name the account ID, never the email", out.String())
	}
	if err := run(ctx, []string{"reset-mfa", "nobody@example.com"}, env, &out); err == nil {
		t.Fatal("an unknown email succeeded")
	}
	if err := run(ctx, []string{"reset-mfa"}, env, &out); err == nil || !strings.Contains(err.Error(), "usage") {
		t.Fatalf("no email: %v", err)
	}
}

func TestGrantAdminRefusesASuspendedAccount(t *testing.T) {
	pool, env := testDB(t)
	ana := account(t, pool, "ana@example.com")
	if _, err := pool.Exec(ctx, `UPDATE accounts SET status = 'suspended', suspended_at = now(),
		suspension_reason = 'Denúncia de abuso.' WHERE id = $1::uuid`, ana); err != nil {
		t.Fatal(err)
	}
	err := run(ctx, []string{"grant-admin", "ana@example.com"}, env, &bytes.Buffer{})
	if err == nil || !strings.Contains(err.Error(), "suspended") {
		t.Fatalf("grant-admin to a suspended account: %v (main exits 1 on any error)", err)
	}
	if n := count(t, pool, `SELECT (SELECT count(*) FROM platform_roles) + (SELECT count(*) FROM audit_events)`); n != 0 {
		t.Fatalf("a refused grant changed %d rows", n)
	}
}
