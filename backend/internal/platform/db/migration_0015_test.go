package db_test

import (
	"context"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

func TestMigrationConsentHistoryAndTermsColumns(t *testing.T) {
	pool := dbtest.New(t)
	ctx := context.Background()

	const insertConsent = `INSERT INTO minor_consents (minor_id, family_id, granted_by, policy_version, granted_at)
		VALUES ($1, gen_random_uuid(), gen_random_uuid(), $2, now())`
	const minor = "11111111-1111-1111-1111-111111111111"
	for _, version := range []string{"2026-10-03", "2026-10-17"} {
		if _, err := pool.Exec(ctx, insertConsent, minor, version); err != nil {
			t.Fatalf("consent %s for the same minor: %v", version, err)
		}
	}
	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM minor_consents WHERE minor_id = $1`, minor).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Fatalf("consents kept for the minor = %d, want 2", n)
	}

	const insertAccount = `INSERT INTO accounts (email, adult_declared_at, created_at, terms_version, terms_accepted_at)
		VALUES ($1, now(), now(), $2, $3)`
	if _, err := pool.Exec(ctx, insertAccount, "both@example.com", "2026-10-17", "2026-10-17T10:00:00Z"); err != nil {
		t.Fatalf("account with both terms fields: %v", err)
	}
	if _, err := pool.Exec(ctx, insertAccount, "none@example.com", nil, nil); err != nil {
		t.Fatalf("account with neither terms field: %v", err)
	}
	if _, err := pool.Exec(ctx, insertAccount, "version@example.com", "2026-10-17", nil); err == nil {
		t.Error("account with only terms_version was accepted")
	}
	if _, err := pool.Exec(ctx, insertAccount, "at@example.com", nil, "2026-10-17T10:00:00Z"); err == nil {
		t.Error("account with only terms_accepted_at was accepted")
	}
}
