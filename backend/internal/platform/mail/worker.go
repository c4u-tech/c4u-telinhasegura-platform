package mail

import (
	"context"
	"errors"
	"log/slog"
	"math/rand/v2"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	claimBatch   = 10
	lease        = 2 * time.Minute // a claimed row is due again after this, if its outcome never landed
	sendTimeout  = 30 * time.Second
	writeTimeout = 5 * time.Second

	// ShutdownGrace is how long a shutdown waits for the worker: the
	// longest a send in flight plus the write of its outcome can take.
	ShutdownGrace = sendTimeout + writeTimeout
)

// errTooLate marks a row whose send could outlive its lease.
var errTooLate = errors.New("mail: send could outlive its lease")

// backoffSteps is the wait after the n-th failed attempt; later attempts
// wait the last step.
var backoffSteps = []time.Duration{30 * time.Second, 2 * time.Minute, 10 * time.Minute, time.Hour}

// Worker delivers the outbox through Sender. Drain runs as a
// sweep job; several workers may drain at once, as every claim is
// FOR UPDATE SKIP LOCKED (the curation/refresh.go pattern). Delivery is
// at least once: a crash between the provider's acceptance and the
// delete resends after the lease.
type Worker struct {
	Pool    *pgxpool.Pool
	Sender  Sender
	Now     func() time.Time
	Log     *slog.Logger
	Allowed Allowlist      // empty: everyone (MAIL_ALLOWED_RECIPIENTS)
	Jitter  func() float64 // in [0, 1); nil: math/rand/v2
}

type claimed struct {
	id, to, subject, body string
	attempts              int
	expires               time.Time
}

// Drain claims due messages in batches and settles each, until a claim
// comes back short. A row is settled only while its send and outcome
// write still fit inside its lease; when one no longer does, the rest of
// the batch is released for the next drain. A cancelled ctx stops the claiming and
// the start of further sends, never a send in flight or the write of its
// outcome.
func (w Worker) Drain(ctx context.Context) error {
	for ctx.Err() == nil {
		claimedAt := w.Now()
		batch, err := w.claim(ctx, claimedAt)
		if ctx.Err() != nil {
			return nil
		}
		if err != nil {
			return err
		}
		for i, m := range batch {
			if ctx.Err() != nil {
				return nil
			}
			err := w.settle(context.WithoutCancel(ctx), m, claimedAt)
			if errors.Is(err, errTooLate) {
				return w.release(context.WithoutCancel(ctx), batch[i:])
			}
			if err != nil {
				return err
			}
		}
		if len(batch) < claimBatch {
			return nil
		}
	}
	return nil
}

// claim takes up to claimBatch due rows and leases them, in one
// statement, so the lock lasts only as long as the update.
func (w Worker) claim(ctx context.Context, now time.Time) ([]claimed, error) {
	now = now.Truncate(time.Microsecond)
	rows, err := w.Pool.Query(ctx, `UPDATE mail_outbox SET attempts = attempts + 1, next_attempt_at = $2
		WHERE id IN (SELECT id FROM mail_outbox WHERE status = 'pending' AND next_attempt_at <= $1
			ORDER BY next_attempt_at, id LIMIT $3 FOR UPDATE SKIP LOCKED)
		RETURNING id::text, to_address, subject, coalesce(body, ''), attempts, expires_at`, now, now.Add(lease), claimBatch)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (claimed, error) {
		var m claimed
		return m, r.Scan(&m.id, &m.to, &m.subject, &m.body, &m.attempts, &m.expires)
	})
}

// settle sends one claimed message, or ends it unsent, and records the
// outcome. Logs carry the row ID and an error class, never the address,
// subject, body or reply text.
func (w Worker) settle(ctx context.Context, m claimed, claimedAt time.Time) error {
	switch {
	case !w.Now().Before(m.expires):
		return w.end(ctx, m, "expired", nil)
	case !w.Allowed.Allows(m.to):
		return w.end(ctx, m, "suppressed", nil)
	}
	// A send that could outlive the lease may be another worker's by the
	// time it ends; expiring and suppressing never send.
	if w.Now().Sub(claimedAt)+sendTimeout+writeTimeout >= lease {
		return errTooLate
	}
	sendCtx, cancel := context.WithTimeout(ctx, sendTimeout)
	defer cancel()
	err := w.Sender.Send(sendCtx, Message{To: m.to, Subject: m.subject, Body: m.body})
	if err == nil {
		return w.write(ctx, m, func() { w.Log.Info("mail: sent", "id", m.id, "attempts", m.attempts) },
			`DELETE FROM mail_outbox WHERE id = $1::uuid AND status = 'pending' AND attempts = $2`)
	}
	if IsPermanent(err) {
		return w.end(ctx, m, "failed", err)
	}
	next := w.Now().Add(w.backoff(m.attempts)).Truncate(time.Microsecond)
	if !next.Before(m.expires) {
		return w.end(ctx, m, "expired", err)
	}
	return w.write(ctx, m, func() {
		w.Log.Warn("mail: send failed, will retry", "id", m.id, "attempts", m.attempts, "error_class", Class(err))
	}, `UPDATE mail_outbox SET next_attempt_at = $3, last_error = $4 WHERE id = $1::uuid AND status = 'pending' AND attempts = $2`,
		next, err.Error())
}

// release hands claimed rows back unsent: the claim's attempt is undone and
// the row is due at once, fenced like every outcome write.
func (w Worker) release(ctx context.Context, rows []claimed) error {
	ctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	now := w.Now().Truncate(time.Microsecond)
	for _, m := range rows {
		if _, err := w.Pool.Exec(ctx, `UPDATE mail_outbox SET attempts = attempts - 1, next_attempt_at = $3
			WHERE id = $1::uuid AND status = 'pending' AND attempts = $2`, m.id, m.attempts, now); err != nil {
			return err
		}
	}
	return nil
}

// write records an outcome only while the row is still the claim m made:
// a row another worker has re-claimed is not touched, and the outcome is
// logged as a lost lease instead.
func (w Worker) write(ctx context.Context, m claimed, logged func(), query string, args ...any) error {
	ctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	tag, err := w.Pool.Exec(ctx, query, append([]any{m.id, m.attempts}, args...)...)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		w.Log.Warn("mail: lease lost", "id", m.id, "attempts", m.attempts)
		return nil
	}
	logged()
	return nil
}

// end settles a message that will not be sent: its body goes, ended_at
// starts the 7-day cleanup.
func (w Worker) end(ctx context.Context, m claimed, status string, cause error) error {
	var lastErr *string
	if cause != nil {
		s := cause.Error()
		lastErr = &s
	}
	return w.write(ctx, m, func() {
		attrs := []any{"id", m.id, "status", status, "attempts", m.attempts}
		if cause != nil {
			attrs = append(attrs, "error_class", Class(cause))
		}
		w.Log.Warn("mail: message ended unsent", attrs...)
	}, `UPDATE mail_outbox SET status = $3, body = NULL, ended_at = $4,
		last_error = coalesce($5::text, last_error) WHERE id = $1::uuid AND status = 'pending' AND attempts = $2`,
		status, w.Now().Truncate(time.Microsecond), lastErr)
}

func (w Worker) backoff(attempt int) time.Duration {
	step := backoffSteps[min(attempt, len(backoffSteps))-1]
	j := rand.Float64
	if w.Jitter != nil {
		j = w.Jitter
	}
	return time.Duration(float64(step) * (0.8 + 0.4*j()))
}
