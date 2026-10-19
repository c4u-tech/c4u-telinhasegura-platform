package db_test

import (
	"context"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

func TestMigrationAccessLog(t *testing.T) {
	pool := dbtest.New(t)
	ctx := context.Background()
	const insert = `INSERT INTO access_log (account_id, device_id, session_id, ip, port)
		VALUES ($1::text::uuid, $2::text::uuid, $3::text::uuid, $4::text::inet, $5::integer)`
	const id = "11111111-1111-1111-1111-111111111111"

	// No foreign key: a row may name an account or a device that no longer exists.
	if _, err := pool.Exec(ctx, insert, id, nil, nil, "203.0.113.7", 51234); err != nil {
		t.Fatalf("account row: %v", err)
	}
	if _, err := pool.Exec(ctx, insert, nil, id, nil, "2001:db8::1", nil); err != nil {
		t.Fatalf("device row without a port: %v", err)
	}
	for name, args := range map[string][]any{
		"no account and no device": {nil, nil, nil, "203.0.113.7", nil},
		"port 0":                   {id, nil, nil, "203.0.113.7", 0},
		"port 65536":               {id, nil, nil, "203.0.113.7", 65536},
		"no address":               {id, nil, nil, nil, nil},
	} {
		if _, err := pool.Exec(ctx, insert, args...); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}
	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM access_log WHERE occurred_at IS NOT NULL`).Scan(&n); err != nil || n != 2 {
		t.Fatalf("stamped rows = %d, %v; want 2", n, err)
	}
	for _, idx := range []string{"access_log_occurred", "access_log_account", "access_log_recent",
		"minor_consents_withdrawn", "audit_events_occurred"} {
		var ok bool
		if err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_indexes
			WHERE schemaname = current_schema() AND indexname = $1)`, idx).Scan(&ok); err != nil || !ok {
			t.Errorf("index %s missing (%v)", idx, err)
		}
	}
}
