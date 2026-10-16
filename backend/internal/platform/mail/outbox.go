package mail

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrHeaderBreak refuses a recipient or subject that would inject a
// header line.
var ErrHeaderBreak = errors.New("mail: recipient or subject contains a line break")

// keepEnded is how long a message that ended unsent keeps its metadata
// for diagnosis.
const keepEnded = 7 * 24 * time.Hour

// Outbox is the Sender the services use. Send only stores the message,
// so no request waits on the provider and every path costs one insert;
// the Worker delivers it.
type Outbox struct {
	Pool *pgxpool.Pool
	Now  func() time.Time
}

func (o Outbox) Send(ctx context.Context, m Message) error {
	if strings.ContainsAny(m.To, "\r\n") || strings.ContainsAny(m.Subject, "\r\n") {
		return ErrHeaderBreak
	}
	ttl := m.TTL
	if ttl <= 0 {
		ttl = DefaultTTL
	}
	now := o.Now().Truncate(time.Microsecond)
	_, err := o.Pool.Exec(ctx, `INSERT INTO mail_outbox (to_address, subject, body, next_attempt_at, expires_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $4)`, m.To, m.Subject, m.Body, now, now.Add(ttl))
	return err
}

// Cleanup deletes the messages that ended unsent more than keepEnded ago.
func (o Outbox) Cleanup(ctx context.Context) error {
	_, err := o.Pool.Exec(ctx, `DELETE FROM mail_outbox WHERE status <> 'pending' AND ended_at < $1`, o.Now().Add(-keepEnded))
	return err
}

// Purge deletes, inside the caller's transaction, every message to the
// given addresses: an erased account's mail goes with it.
func Purge(ctx context.Context, tx pgx.Tx, addresses ...string) error {
	_, err := tx.Exec(ctx, `DELETE FROM mail_outbox WHERE to_address = ANY($1)`, addresses)
	return err
}
