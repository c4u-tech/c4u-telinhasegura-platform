// Package db opens the Postgres pool and applies the embedded migrations.
package db

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrations embed.FS

func Open(ctx context.Context, url string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("db: open: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("db: ping: %w", err)
	}
	return pool, nil
}

// MigrationLockKey is the namespace of the advisory lock Migrate holds; the
// second key is the schema, so the migrations of one schema run one at a
// time while parallel test schemas never wait on each other.
const MigrationLockKey int32 = 0x7473 // "ts"

// Migrate applies, in file-name order, each migration not yet recorded in
// schema_migrations, one transaction per file. It holds a session advisory
// lock on one connection for the whole run, so two processes starting
// together migrate one after the other. The lock needs a direct connection:
// a transaction-mode pooler would not keep the session.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("db: acquire: %w", err)
	}
	defer conn.Release()
	// The key is read once: a migration that changed the search path must not
	// make the unlock target another key.
	var schemaKey int32
	if err := conn.QueryRow(ctx, `SELECT hashtext(current_schema())`).Scan(&schemaKey); err != nil {
		return fmt.Errorf("db: migration lock key: %w", err)
	}
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1, $2)`, MigrationLockKey, schemaKey); err != nil {
		return fmt.Errorf("db: migration lock: %w", err)
	}
	defer func() {
		// A session that cannot unlock, or whose unlock finds no lock, is
		// closed: Postgres then releases its locks, and the pool drops the
		// connection.
		bg := context.WithoutCancel(ctx)
		var unlocked bool
		if err := conn.QueryRow(bg, `SELECT pg_advisory_unlock($1, $2)`, MigrationLockKey, schemaKey).Scan(&unlocked); err != nil || !unlocked {
			_ = conn.Conn().Close(bg)
		}
	}()
	return apply(ctx, conn)
}

// apply is the migration run itself, on the locked connection.
func apply(ctx context.Context, conn *pgxpool.Conn) error {
	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
		return fmt.Errorf("db: schema_migrations: %w", err)
	}
	names, err := fs.Glob(migrations, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, name := range names {
		var applied bool
		if err := conn.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, name).Scan(&applied); err != nil {
			return err
		}
		if applied {
			continue
		}
		sql, err := migrations.ReadFile(name)
		if err != nil {
			return err
		}
		tx, err := conn.Begin(ctx)
		if err != nil {
			return err
		}
		// No arguments: pgx uses the simple protocol, which runs every
		// statement in the file.
		if _, err := tx.Exec(ctx, string(sql)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("db: %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, name); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}
