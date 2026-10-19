package accesslog_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/accesslog"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

var ctx = context.Background()

const (
	account = "11111111-1111-1111-1111-111111111111"
	sess    = "22222222-2222-2222-2222-222222222222"
	device  = "33333333-3333-3333-3333-333333333333"
)

type fixture struct {
	t     *testing.T
	pool  *pgxpool.Pool
	now   time.Time
	store accesslog.Store
}

func newFixture(t *testing.T) *fixture {
	f := &fixture{t: t, pool: dbtest.New(t), now: time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC)}
	f.store = accesslog.Store{Pool: f.pool, Now: func() time.Time { return f.now }}
	return f
}

func (f *fixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

func (f *fixture) record(e accesslog.Entry) {
	f.t.Helper()
	if err := f.store.Record(ctx, e); err != nil {
		f.t.Fatal(err)
	}
}

func TestRecordKeepsOneRowPerSessionAndAddressPerHour(t *testing.T) {
	f := newFixture(t)
	e := accesslog.Entry{AccountID: account, SessionID: sess, IP: "203.0.113.7"}
	f.record(e)
	f.record(e)
	f.now = f.now.Add(59 * time.Minute)
	f.record(e)
	if n := f.count(`SELECT count(*) FROM access_log`); n != 1 {
		t.Fatalf("within the hour: %d rows, want 1", n)
	}
	f.record(accesslog.Entry{AccountID: account, SessionID: sess, IP: "198.51.100.9"})
	if n := f.count(`SELECT count(*) FROM access_log`); n != 2 {
		t.Fatalf("another address: %d rows, want 2", n)
	}
	f.now = f.now.Add(2 * time.Minute) // 61 minutes after the first row
	f.record(e)
	if n := f.count(`SELECT count(*) FROM access_log WHERE host(ip) = '203.0.113.7'`); n != 2 {
		t.Fatalf("an hour later: %d rows from the first address, want 2", n)
	}
}

func TestRecordKeepsTheOwnerAndAValidPort(t *testing.T) {
	f := newFixture(t)
	f.record(accesslog.Entry{DeviceID: device, IP: "::ffff:203.0.113.7", Port: 51234})
	f.record(accesslog.Entry{AccountID: account, SessionID: sess, IP: "2001:db8::1", Port: 0})
	f.record(accesslog.Entry{AccountID: account, IP: "192.0.2.1", Port: 70000}) // a sign-up: no session yet
	for _, c := range []struct {
		q    string
		args []any
	}{
		{`SELECT count(*) FROM access_log WHERE device_id = $1::uuid AND account_id IS NULL AND session_id IS NULL
			AND host(ip) = '203.0.113.7' AND port = 51234 AND occurred_at = $2`, []any{device, f.now}},
		{`SELECT count(*) FROM access_log WHERE session_id = $1::uuid AND host(ip) = '2001:db8::1' AND port IS NULL`, []any{sess}},
		{`SELECT count(*) FROM access_log WHERE account_id = $1::uuid AND session_id IS NULL AND port IS NULL`, []any{account}},
	} {
		if n := f.count(c.q, c.args...); n != 1 {
			t.Errorf("%s: %d rows, want 1", c.q, n)
		}
	}
}

func TestRecordRefusesAnEntryWithoutAddressOrOwner(t *testing.T) {
	f := newFixture(t)
	for name, e := range map[string]accesslog.Entry{
		"no address":   {AccountID: account},
		"bad address":  {AccountID: account, IP: "not-an-address"},
		"no one named": {SessionID: sess, IP: "203.0.113.7"},
	} {
		if err := f.store.Record(ctx, e); !errors.Is(err, accesslog.ErrInvalid) {
			t.Errorf("%s: %v, want ErrInvalid", name, err)
		}
	}
	if n := f.count(`SELECT count(*) FROM access_log`); n != 0 {
		t.Fatalf("%d rows written", n)
	}
}

// The app opens with several requests at once, possibly on different replicas.
func TestRecordIsOneRowUnderConcurrency(t *testing.T) {
	f := newFixture(t)
	e := accesslog.Entry{AccountID: account, SessionID: sess, IP: "203.0.113.7"}
	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- f.store.Record(ctx, e)
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if n := f.count(`SELECT count(*) FROM access_log`); n != 1 {
		t.Fatalf("%d rows, want 1", n)
	}
}

func TestSweepKeepsSixMonths(t *testing.T) {
	f := newFixture(t)
	cutoff := f.now.AddDate(0, -6, 0)
	for _, at := range []time.Time{cutoff.Add(-time.Minute), cutoff.Add(time.Minute)} {
		if _, err := f.pool.Exec(ctx, `INSERT INTO access_log (account_id, ip, occurred_at) VALUES ($1::uuid, '203.0.113.7', $2)`, account, at); err != nil {
			t.Fatal(err)
		}
	}
	if err := f.store.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	if err := f.store.Sweep(ctx); err != nil { // idempotent
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM access_log`); n != 1 || f.count(`SELECT count(*) FROM access_log WHERE occurred_at = $1`, cutoff.Add(time.Minute)) != 1 {
		t.Fatalf("after the sweep: %d rows, want the newer one only", n)
	}
}

// A stalled database must not hold the request up: the write gives up.
func TestRecordGivesUpWhenItCannotFinishInTime(t *testing.T) {
	f := newFixture(t)
	defer accesslog.SetRecordTimeout(200 * time.Millisecond)()
	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "access_log/"+sess+"/203.0.113.7"); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	err = f.store.Record(ctx, accesslog.Entry{AccountID: account, SessionID: sess, IP: "203.0.113.7"})
	if err == nil {
		t.Fatal("Record returned nil while the lock was held")
	}
	if d := time.Since(start); d > 2*time.Second {
		t.Fatalf("Record took %s, want it bounded", d)
	}
	_ = tx.Rollback(ctx)
	if n := f.count(`SELECT count(*) FROM access_log`); n != 0 {
		t.Fatalf("%d rows written", n)
	}
}
