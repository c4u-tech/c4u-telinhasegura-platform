package db_test

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

func TestMigrateCreatesTheSchemaAndIsIdempotent(t *testing.T) {
	pool := dbtest.New(t) // already migrated once
	ctx := context.Background()

	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatalf("second Migrate: %v", err)
	}
	for _, table := range []string{"accounts", "email_tokens", "sessions", "used_refresh_tokens", "audit_events"} {
		var exists bool
		if err := pool.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, table).Scan(&exists); err != nil {
			t.Fatal(err)
		}
		if !exists {
			t.Errorf("table %s missing after Migrate", table)
		}
	}
}

// otherSession opens a connection outside the pool, on the pool's schema:
// advisory locks are re-entrant within one session, so a check made on a
// pooled connection could be fooled by Migrate's own.
func otherSession(t *testing.T, pool *pgxpool.Pool) *pgx.Conn {
	t.Helper()
	c, err := pgx.ConnectConfig(context.Background(), pool.Config().ConnConfig.Copy())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c.Close(context.Background()) })
	return c
}

func lock(t *testing.T, c *pgx.Conn, fn string) bool {
	t.Helper()
	var ok bool
	sql := `SELECT ` + fn + `($1, hashtext(current_schema()))`
	if fn == "pg_advisory_lock" {
		sql = `SELECT true FROM (SELECT pg_advisory_lock($1, hashtext(current_schema()))) l`
	}
	if err := c.QueryRow(context.Background(), sql, db.MigrationLockKey).Scan(&ok); err != nil {
		t.Fatal(err)
	}
	return ok
}

func migrated(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	var rows, versions int
	var accounts bool
	if err := pool.QueryRow(context.Background(), `SELECT count(*), count(DISTINCT version),
		to_regclass('accounts') IS NOT NULL FROM schema_migrations`).Scan(&rows, &versions, &accounts); err != nil {
		t.Fatal(err)
	}
	if rows == 0 || rows != versions || !accounts {
		t.Fatalf("schema_migrations: %d rows for %d versions, accounts=%v", rows, versions, accounts)
	}
}

func TestMigrateWaitsForTheLock(t *testing.T) {
	pool := dbtest.Empty(t)
	holder := otherSession(t, pool)
	lock(t, holder, "pg_advisory_lock")

	done := make(chan error, 1)
	go func() { done <- db.Migrate(context.Background(), pool) }()
	select {
	case err := <-done:
		t.Fatalf("Migrate finished while another session held the lock: %v", err)
	case <-time.After(300 * time.Millisecond):
	}
	if !lock(t, holder, "pg_advisory_unlock") {
		t.Fatal("unlock: the holder did not hold the lock")
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(30 * time.Second):
		t.Fatal("Migrate never finished after the lock was released")
	}
	migrated(t, pool)
}

func TestConcurrentMigrateRecordsEachVersionOnce(t *testing.T) {
	pool := dbtest.Empty(t)
	errs := make(chan error, 2)
	for range 2 {
		go func() { errs <- db.Migrate(context.Background(), pool) }()
	}
	for range 2 {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
	}
	migrated(t, pool)
}

func TestMigrateReleasesTheLockWhenItFails(t *testing.T) {
	pool := dbtest.Empty(t)
	if _, err := pool.Exec(context.Background(), `CREATE TABLE accounts (x int)`); err != nil {
		t.Fatal(err)
	}
	if err := db.Migrate(context.Background(), pool); err == nil {
		t.Fatal("Migrate succeeded over a conflicting accounts table")
	}
	if !lock(t, otherSession(t, pool), "pg_try_advisory_lock") {
		t.Fatal("the lock is still held after a failed Migrate")
	}
}

func TestMigrateGivesUpWhenItsContextEnds(t *testing.T) {
	pool := dbtest.Empty(t)
	holder := otherSession(t, pool)
	lock(t, holder, "pg_advisory_lock")

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	if err := db.Migrate(ctx, pool); err == nil {
		t.Fatalf("Migrate while locked with a 200ms deadline: %v, want an error", err)
	}
	lock(t, holder, "pg_advisory_unlock")
	if err := db.Migrate(context.Background(), pool); err != nil {
		t.Fatalf("Migrate after the give-up: %v", err)
	}
	migrated(t, pool)
}
