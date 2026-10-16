package mail_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

var (
	ctx  = context.Background()
	base = time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)
)

func count(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestOutboxStoresAPendingMessageWithItsExpiry(t *testing.T) {
	pool := dbtest.New(t)
	o := mail.Outbox{Pool: pool, Now: func() time.Time { return base }}
	if err := o.Send(ctx, mail.Message{To: "ana@example.com", Subject: "Oi", Body: "link", TTL: 30 * time.Minute}); err != nil {
		t.Fatal(err)
	}
	if err := o.Send(ctx, mail.Message{To: "bia@example.com", Subject: "Aviso", Body: "notice"}); err != nil {
		t.Fatal(err)
	}
	for to, ttl := range map[string]time.Duration{"ana@example.com": 30 * time.Minute, "bia@example.com": 72 * time.Hour} {
		var status, body string
		var attempts int
		var due, expires, created time.Time
		if err := pool.QueryRow(ctx, `SELECT status, body, attempts, next_attempt_at, expires_at, created_at
			FROM mail_outbox WHERE to_address = $1`, to).Scan(&status, &body, &attempts, &due, &expires, &created); err != nil {
			t.Fatal(err)
		}
		if status != "pending" || attempts != 0 || body == "" || !due.Equal(base) || !created.Equal(base) || !expires.Equal(base.Add(ttl)) {
			t.Errorf("%s: status %s attempts %d due %s expires %s", to, status, attempts, due, expires)
		}
	}
}

func TestOutboxRefusesLineBreaksInHeaders(t *testing.T) {
	pool := dbtest.New(t)
	o := mail.Outbox{Pool: pool, Now: func() time.Time { return base }}
	for _, m := range []mail.Message{
		{To: "ana@example.com\r\nBcc: eve@example.com", Subject: "Oi", Body: "x"},
		{To: "ana@example.com", Subject: "Oi\nBcc: eve@example.com", Body: "x"},
	} {
		if err := o.Send(ctx, m); !errors.Is(err, mail.ErrHeaderBreak) {
			t.Errorf("Send(%q, %q) = %v, want ErrHeaderBreak", m.To, m.Subject, err)
		}
	}
	if n := count(t, pool, `SELECT count(*) FROM mail_outbox`); n != 0 {
		t.Fatalf("%d rows stored", n)
	}
}

func TestPurgeDeletesOnlyTheGivenAddresses(t *testing.T) {
	pool := dbtest.New(t)
	o := mail.Outbox{Pool: pool, Now: func() time.Time { return base }}
	for _, to := range []string{"ana@example.com", "ana.nova@example.com", "bia@example.com"} {
		if err := o.Send(ctx, mail.Message{To: to, Subject: "s", Body: "b"}); err != nil {
			t.Fatal(err)
		}
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := mail.Purge(ctx, tx, "ana@example.com", "ana.nova@example.com"); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if n := count(t, pool, `SELECT count(*) FROM mail_outbox`); n != 1 {
		t.Fatalf("%d rows left, want only bia's", n)
	}
	if n := count(t, pool, `SELECT count(*) FROM mail_outbox WHERE to_address = 'bia@example.com'`); n != 1 {
		t.Fatal("bia's row was purged")
	}
}

func TestCleanupDeletesRowsEndedOverAWeekAgo(t *testing.T) {
	pool := dbtest.New(t)
	ins := func(status string, ended *time.Time) {
		t.Helper()
		if _, err := pool.Exec(ctx, `INSERT INTO mail_outbox (to_address, subject, body, status, next_attempt_at, expires_at, created_at, ended_at)
			VALUES ('x@example.com', 's', NULL, $1, $2, $2, $2, $3)`, status, base.Add(-30*24*time.Hour), ended); err != nil {
			t.Fatal(err)
		}
	}
	old, recent := base.Add(-7*24*time.Hour-time.Second), base.Add(-7*24*time.Hour+time.Second)
	ins("failed", &old)
	ins("expired", &old)
	ins("suppressed", &old)
	ins("failed", &recent)
	ins("pending", nil)
	o := mail.Outbox{Pool: pool, Now: func() time.Time { return base }}
	if err := o.Cleanup(ctx); err != nil {
		t.Fatal(err)
	}
	if n := count(t, pool, `SELECT count(*) FROM mail_outbox`); n != 2 {
		t.Fatalf("%d rows left, want the recent failure and the pending row", n)
	}
}
