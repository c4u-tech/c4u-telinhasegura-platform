package identity_test

import (
	"context"
	"testing"
	"time"
)

func TestSweepEmailTokensDeletesThemSevenDaysAfterExpiry(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	day, m := 24*time.Hour, time.Minute
	seed := func(name, purpose string, newEmail any, expires time.Time, used any) {
		t.Helper()
		if _, err := f.pool.Exec(ctx, `INSERT INTO email_tokens (token_hash, account_id, purpose, new_email, expires_at, used_at, created_at)
			VALUES ($1, $2::uuid, $3, $4, $5, $6, $7)`,
			[]byte(name), id, purpose, newEmail, expires, used, expires.Add(-day)); err != nil {
			t.Fatal(err)
		}
	}
	seed("change expired 7d ago", "change", "novo@example.com", f.now.Add(-7*day-m), nil)
	seed("change used, expired 7d ago", "change", "outro@example.com", f.now.Add(-7*day-m), f.now.Add(-8*day))
	seed("reset expired 7d ago", "reset", nil, f.now.Add(-7*day-m), nil)
	seed("change expired 6d ago", "change", "recente@example.com", f.now.Add(-6*day), nil)
	seed("change used today", "change", "hoje@example.com", f.now.Add(day), f.now)
	seed("change pending", "change", "pendente@example.com", f.now.Add(day), nil)

	if err := f.svc.SweepEmailTokens(ctx); err != nil {
		t.Fatal(err)
	}
	exists := func(name string) bool {
		return f.count(`SELECT count(*) FROM email_tokens WHERE token_hash = $1`, []byte(name)) == 1
	}
	for _, gone := range []string{"change expired 7d ago", "change used, expired 7d ago", "reset expired 7d ago"} {
		if exists(gone) {
			t.Errorf("%s: kept", gone)
		}
	}
	for _, kept := range []string{"change expired 6d ago", "change used today", "change pending"} {
		if !exists(kept) {
			t.Errorf("%s: deleted", kept)
		}
	}
	if f.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid`, id) != 1 {
		t.Fatal("the account went with its tokens")
	}
}
