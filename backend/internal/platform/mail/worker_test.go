package mail_test

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/textproto"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

// clock is a settable time shared by the outbox and the worker.
type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) Now() time.Time      { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) Add(d time.Duration) { c.mu.Lock(); defer c.mu.Unlock(); c.t = c.t.Add(d) }

// sender records every message and answers with fail, when set.
type sender struct {
	mu   sync.Mutex
	sent []mail.Message
	fail func(mail.Message) error
}

func (s *sender) Send(_ context.Context, m mail.Message) error {
	s.mu.Lock()
	s.sent = append(s.sent, m)
	fail := s.fail
	s.mu.Unlock()
	if fail != nil {
		return fail(m)
	}
	return nil
}

func (s *sender) count() int { s.mu.Lock(); defer s.mu.Unlock(); return len(s.sent) }

type rig struct {
	pool   *pgxpool.Pool
	clock  *clock
	sender *sender
	logs   *bytes.Buffer
	outbox mail.Outbox
	worker mail.Worker
}

func newRig(t *testing.T) *rig {
	t.Helper()
	r := &rig{pool: dbtest.New(t), clock: &clock{t: base}, sender: &sender{}, logs: &bytes.Buffer{}}
	r.outbox = mail.Outbox{Pool: r.pool, Now: r.clock.Now}
	r.worker = mail.Worker{Pool: r.pool, Sender: r.sender, Now: r.clock.Now,
		Log: slog.New(slog.NewTextHandler(r.logs, nil)), Jitter: func() float64 { return 0.5 }} // factor 1.0
	return r
}

func (r *rig) enqueue(t *testing.T, m mail.Message) {
	t.Helper()
	if err := r.outbox.Send(ctx, m); err != nil {
		t.Fatal(err)
	}
}

func (r *rig) drain(t *testing.T) {
	t.Helper()
	if err := r.worker.Drain(ctx); err != nil {
		t.Fatal(err)
	}
}

type row struct {
	status   string
	body     *string
	attempts int
	due      time.Time
	ended    *time.Time
	lastErr  *string
}

func (r *rig) row(t *testing.T, to string) row {
	t.Helper()
	var x row
	if err := r.pool.QueryRow(ctx, `SELECT status, body, attempts, next_attempt_at, ended_at, last_error
		FROM mail_outbox WHERE to_address = $1`, to).Scan(&x.status, &x.body, &x.attempts, &x.due, &x.ended, &x.lastErr); err != nil {
		t.Fatal(err)
	}
	return x
}

var msg = mail.Message{To: "ana@example.com", Subject: "Crie uma nova senha", Body: "https://app.test/redefinir-senha?token=SECRET"}

func TestDrainSendsADueMessageAndDeletesIt(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, msg)
	r.drain(t)
	if r.sender.count() != 1 {
		t.Fatalf("%d sends, want 1", r.sender.count())
	}
	got := r.sender.sent[0]
	if got.To != msg.To || got.Subject != msg.Subject || got.Body != msg.Body {
		t.Fatalf("sent %+v", got)
	}
	if n := count(t, r.pool, `SELECT count(*) FROM mail_outbox`); n != 0 {
		t.Fatalf("%d rows left after a success", n)
	}
}

func TestDrainRetriesATransientErrorWithBackoff(t *testing.T) {
	r := newRig(t)
	r.sender.fail = func(mail.Message) error { return &textproto.Error{Code: 451, Msg: "4.7.1 try later"} }
	r.enqueue(t, msg)
	for i, wait := range []time.Duration{30 * time.Second, 2 * time.Minute, 10 * time.Minute, time.Hour, time.Hour} {
		r.drain(t)
		x := r.row(t, msg.To)
		if x.status != "pending" || x.attempts != i+1 || !x.due.Equal(r.clock.Now().Add(wait)) || x.body == nil || x.lastErr == nil {
			t.Fatalf("attempt %d: %+v, want due in %s", i+1, x, wait)
		}
		r.drain(t) // not due yet: nothing is sent
		if r.sender.count() != i+1 {
			t.Fatalf("attempt %d: sent before it was due", i+1)
		}
		r.clock.Add(wait)
	}
}

func TestBackoffJitterStaysWithin20Percent(t *testing.T) {
	for jitter, want := range map[float64]time.Duration{0: 24 * time.Second, 0.999999: 36 * time.Second} {
		r := newRig(t)
		r.worker.Jitter = func() float64 { return jitter }
		r.sender.fail = func(mail.Message) error { return errors.New("connection reset") }
		r.enqueue(t, msg)
		r.drain(t)
		d := r.row(t, msg.To).due.Sub(base)
		if d < 24*time.Second || d > 36*time.Second || (jitter == 0 && d != want) {
			t.Errorf("jitter %v: wait %s", jitter, d)
		}
	}
}

func TestDrainFailsAPermanentErrorAndLogsNoAddress(t *testing.T) {
	r := newRig(t)
	r.sender.fail = func(mail.Message) error {
		return mail.Permanent(&textproto.Error{Code: 550, Msg: "5.1.1 <ana@example.com>: user unknown"})
	}
	r.enqueue(t, msg)
	r.drain(t)
	x := r.row(t, msg.To)
	if x.status != "failed" || x.body != nil || x.ended == nil || x.lastErr == nil || !strings.Contains(*x.lastErr, "550") {
		t.Fatalf("row %+v", x)
	}
	r.clock.Add(48 * time.Hour)
	r.drain(t)
	if r.sender.count() != 1 {
		t.Fatal("a failed message was sent again")
	}
	logs := r.logs.String()
	for _, secret := range []string{"ana@example.com", "user unknown", msg.Subject, "SECRET"} {
		if strings.Contains(logs, secret) {
			t.Errorf("logs carry %q: %s", secret, logs)
		}
	}
	if !strings.Contains(logs, "smtp 550") {
		t.Errorf("logs lack the error class: %s", logs)
	}
}

func TestDrainExpiresAMessagePastItsLink(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, mail.Message{To: msg.To, Subject: msg.Subject, Body: msg.Body, TTL: 30 * time.Minute})
	r.clock.Add(30 * time.Minute)
	r.drain(t)
	if r.sender.count() != 0 {
		t.Fatal("an expired message was sent")
	}
	if x := r.row(t, msg.To); x.status != "expired" || x.body != nil || x.ended == nil {
		t.Fatalf("row %+v", x)
	}
}

func TestDrainExpiresWhenTheNextRetryFallsAfterTheLink(t *testing.T) {
	r := newRig(t)
	r.sender.fail = func(mail.Message) error { return errors.New("connection reset") }
	r.enqueue(t, mail.Message{To: msg.To, Subject: msg.Subject, Body: msg.Body, TTL: 20 * time.Second})
	r.drain(t)
	if x := r.row(t, msg.To); x.status != "expired" || x.body != nil || x.ended == nil {
		t.Fatalf("row %+v", x)
	}
}

func TestDrainSuppressesRecipientsOutsideTheAllowlist(t *testing.T) {
	r := newRig(t)
	var err error
	if r.worker.Allowed, err = mail.ParseAllowlist("qa@example.com,@coding4u.tech"); err != nil {
		t.Fatal(err)
	}
	for _, to := range []string{"QA@Example.com", "ana@coding4u.tech", "bob@gmail.com"} {
		r.enqueue(t, mail.Message{To: to, Subject: "s", Body: "b"})
	}
	r.drain(t)
	if r.sender.count() != 2 {
		t.Fatalf("%d sends, want 2", r.sender.count())
	}
	if x := r.row(t, "bob@gmail.com"); x.status != "suppressed" || x.body != nil || x.ended == nil {
		t.Fatalf("row %+v", x)
	}
	if strings.Contains(r.logs.String(), "bob@gmail.com") {
		t.Fatal("the suppressed address was logged")
	}
}

func TestTwoWorkersSendEachMessageOnce(t *testing.T) {
	r := newRig(t)
	r.sender.fail = func(mail.Message) error { time.Sleep(5 * time.Millisecond); return nil } // so the drains overlap
	for i := range 25 {
		r.enqueue(t, mail.Message{To: strings.Repeat("a", i+1) + "@example.com", Subject: "s", Body: "b"})
	}
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := r.worker.Drain(ctx); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	seen := map[string]int{}
	for _, m := range r.sender.sent {
		seen[m.To]++
	}
	if len(seen) != 25 || r.sender.count() != 25 {
		t.Fatalf("%d sends to %d recipients, want 25 each once", r.sender.count(), len(seen))
	}
}

func TestAClaimThatNeverFinishedIsDueAfterTheLease(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, msg)
	crash := &sender{fail: func(mail.Message) error { runtime.Goexit(); return nil }}
	w := r.worker
	w.Sender = crash
	done := make(chan struct{})
	go func() { defer close(done); _ = w.Drain(ctx) }() // dies after the claim, before the outcome
	<-done
	if x := r.row(t, msg.To); x.status != "pending" || x.attempts != 1 || !x.due.Equal(base.Add(2*time.Minute)) {
		t.Fatalf("row after the crash %+v", x)
	}
	r.clock.Add(time.Minute)
	r.drain(t)
	if r.sender.count() != 0 {
		t.Fatal("sent inside the lease")
	}
	r.clock.Add(time.Minute)
	r.drain(t)
	if r.sender.count() != 1 {
		t.Fatal("not sent after the lease")
	}
}

func TestDrainContinuesPastTheFirstBatch(t *testing.T) {
	r := newRig(t)
	for i := range 25 {
		r.enqueue(t, mail.Message{To: strings.Repeat("b", i+1) + "@example.com", Subject: "s", Body: "b"})
	}
	r.drain(t)
	if r.sender.count() != 25 {
		t.Fatalf("%d sends in one drain, want 25", r.sender.count())
	}
}

func TestDrainReleasesARowWhoseSendCouldOutliveItsLease(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, mail.Message{To: "first@example.com", Subject: "s", Body: "b"})
	r.clock.Add(time.Second)
	r.enqueue(t, mail.Message{To: "second@example.com", Subject: "s", Body: "b"})
	calls := 0
	r.sender.fail = func(mail.Message) error {
		if calls++; calls == 1 {
			r.clock.Add(90 * time.Second) // past the 85 s window to start a send, inside the lease
		}
		return nil
	}
	r.drain(t)
	if r.sender.count() != 1 {
		t.Fatalf("%d sends, want only the first of the batch", r.sender.count())
	}
	if x := r.row(t, "second@example.com"); x.status != "pending" || x.attempts != 0 || !x.due.Equal(r.clock.Now()) {
		t.Fatalf("released row %+v, want pending, attempts 0, due now (%v)", x, r.clock.Now())
	}
	r.drain(t) // same clock: the released row is due at once
	if r.sender.count() != 2 || count(t, r.pool, `SELECT count(*) FROM mail_outbox`) != 0 {
		t.Fatal("the released row was not sent on the next drain")
	}
}

func TestDrainStillEndsExpiredAndSuppressedRowsPastTheSendWindow(t *testing.T) {
	r := newRig(t)
	var err error
	if r.worker.Allowed, err = mail.ParseAllowlist("first@example.com,short@example.com"); err != nil {
		t.Fatal(err)
	}
	r.enqueue(t, mail.Message{To: "first@example.com", Subject: "s", Body: "b"})
	r.clock.Add(time.Second)
	r.enqueue(t, mail.Message{To: "short@example.com", Subject: "s", Body: "b", TTL: 30 * time.Second})
	r.clock.Add(time.Second)
	r.enqueue(t, mail.Message{To: "bob@gmail.com", Subject: "s", Body: "b"})
	r.sender.fail = func(mail.Message) error { r.clock.Add(90 * time.Second); return nil }
	r.drain(t)
	if r.sender.count() != 1 {
		t.Fatalf("%d sends, want 1", r.sender.count())
	}
	if x := r.row(t, "short@example.com"); x.status != "expired" || x.attempts != 1 {
		t.Fatalf("expired row %+v", x)
	}
	if x := r.row(t, "bob@gmail.com"); x.status != "suppressed" || x.attempts != 1 {
		t.Fatalf("suppressed row %+v", x)
	}
}

func TestDrainDoesNotTouchARowAnotherWorkerClaimed(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, msg)
	r.sender.fail = func(mail.Message) error {
		_, err := r.pool.Exec(ctx, `UPDATE mail_outbox SET attempts = attempts + 1`) // a re-claim elsewhere
		return err
	}
	r.drain(t)
	if n := count(t, r.pool, `SELECT count(*) FROM mail_outbox WHERE attempts = 2`); n != 1 {
		t.Fatalf("the newer claimant's row was deleted or rewritten (%d rows)", n)
	}
	if !strings.Contains(r.logs.String(), "lease lost") {
		t.Fatalf("logs lack the lost lease: %s", r.logs.String())
	}
}

func TestDrainFinishesTheSendInFlightWhenCancelledThenStops(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, mail.Message{To: "first@example.com", Subject: "s", Body: "b"})
	r.enqueue(t, mail.Message{To: "second@example.com", Subject: "s", Body: "b"})
	cancelled, cancel := context.WithCancel(ctx)
	r.sender.fail = func(mail.Message) error { cancel(); return nil }
	if err := r.worker.Drain(cancelled); err != nil {
		t.Fatalf("a cancelled drain returned %v", err)
	}
	if r.sender.count() != 1 {
		t.Fatalf("%d sends, want 1", r.sender.count())
	}
	if n := count(t, r.pool, `SELECT count(*) FROM mail_outbox`); n != 1 {
		t.Fatalf("%d rows left, want the unsent one only (the sent one deleted)", n)
	}
	if n := count(t, r.pool, `SELECT count(*) FROM mail_outbox WHERE status = 'pending' AND attempts = 1`); n != 1 {
		t.Fatal("the unsent row is not left claimed and pending")
	}
}

func TestDrainStopsClaimingOnceCancelled(t *testing.T) {
	r := newRig(t)
	r.enqueue(t, msg)
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if err := r.worker.Drain(cancelled); err != nil {
		t.Fatalf("a cancelled drain returned %v", err)
	}
	if r.sender.count() != 0 {
		t.Fatal("a cancelled drain claimed")
	}
}
