// Package dbtest gives each test its own migrated Postgres schema.
package dbtest

import (
	"context"
	"crypto/rand"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
)

// New returns a pool whose search_path is a fresh, migrated schema that is
// dropped when the test ends. It skips without TEST_DATABASE_URL, except
// in CI, where a silent skip would turn the persistence suite fake-green.
func New(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool := Empty(t)
	if err := db.Migrate(context.Background(), pool); err != nil {
		t.Fatalf("dbtest: migrate: %v", err)
	}
	return pool
}

// Empty is New without the migrations.
func Empty(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		if os.Getenv("CI") != "" {
			t.Fatal("dbtest: TEST_DATABASE_URL must be set in CI")
		}
		t.Skip("dbtest: TEST_DATABASE_URL unset; skipping Postgres test (see backend/README.md)")
	}
	ctx := context.Background()
	admin, err := pgx.Connect(ctx, url)
	if err != nil {
		t.Fatalf("dbtest: connect: %v", err)
	}
	schema := "t_" + strings.ToLower(rand.Text())
	if _, err := admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		t.Fatalf("dbtest: create schema: %v", err)
	}
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		t.Fatalf("dbtest: parse url: %v", err)
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatalf("dbtest: pool: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		_, _ = admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
		_ = admin.Close(ctx)
	})
	return pool
}
