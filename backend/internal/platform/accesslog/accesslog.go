// Package accesslog keeps the record of when, and from which address and
// port, each account and each linked device used the service. Brazilian
// law requires an application provider to keep that record for six
// months, in confidence, and to hand it over only under a court order, so
// a row outlives the account, session and device it names; the hourly
// sweep deletes it once the six months are over.
package accesslog

import (
	"context"
	"errors"
	"net/netip"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// retentionMonths is how long the law asks for the record to be kept.
const retentionMonths = 6

// dedupWindow is how long the same session (else device, else account)
// seen from the same address adds no new row: the record says when the
// service was used, not every request.
const dedupWindow = time.Hour

// ErrInvalid is an entry without a parseable address, or naming neither
// an account nor a device. Its message never carries the address.
var ErrInvalid = errors.New("accesslog: an entry needs an address and an account or a device")

// Entry is one use of the service.
type Entry struct {
	AccountID string // "" for a linked device
	DeviceID  string // "" for a guardian's session
	SessionID string // "" for a linked device or a sign-up
	IP        string
	Port      int // 0 when the front proxy did not forward it
}

// Store writes and purges the record.
type Store struct {
	Pool *pgxpool.Pool
	Now  func() time.Time
}

// seenSQL and insertSQL key a row on its session, else its device, else
// its account, as first does.
const seenSQL = `SELECT EXISTS (SELECT 1 FROM access_log
	WHERE coalesce(session_id, device_id, account_id) = $1::uuid
	AND ip = $2::text::inet AND occurred_at > $3::timestamptz)`

const insertSQL = `INSERT INTO access_log (account_id, device_id, session_id, ip, port, occurred_at)
	SELECT nullif($1::text, '')::uuid, nullif($2::text, '')::uuid, nullif($3::text, '')::uuid,
		$4::text::inet, $5::integer, $6::timestamptz
	WHERE NOT EXISTS (SELECT 1 FROM access_log
		WHERE coalesce(session_id, device_id, account_id) =
			coalesce(nullif($3::text, '')::uuid, nullif($2::text, '')::uuid, nullif($1::text, '')::uuid)
		AND ip = $4::text::inet AND occurred_at > $7::timestamptz)`

// Record adds the entry unless the same session (else device, else
// account) was already recorded from the same address within the hour.
// Most requests stop at the first read. Otherwise a transaction-scoped
// lock on that pair makes concurrent requests, on one replica or several,
// add one row between them.
func (s Store) Record(ctx context.Context, e Entry) error {
	addr, err := netip.ParseAddr(e.IP)
	if err != nil || (e.AccountID == "" && e.DeviceID == "") {
		return ErrInvalid
	}
	ip := addr.Unmap().String()
	var port any // NULL unless a valid port came with the request
	if e.Port >= 1 && e.Port <= 65535 {
		port = e.Port
	}
	key := first(e.SessionID, e.DeviceID, e.AccountID)
	now := s.Now()
	since := now.Add(-dedupWindow)
	// The row is written even if the client hangs up: the use happened.
	ctx = context.WithoutCancel(ctx)
	var seen bool
	if err := s.Pool.QueryRow(ctx, seenSQL, key, ip, since).Scan(&seen); err != nil || seen {
		return err
	}
	return pgx.BeginFunc(ctx, s.Pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "access_log/"+key+"/"+ip); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, insertSQL, e.AccountID, e.DeviceID, e.SessionID, ip, port, now, since)
		return err
	})
}

// Sweep deletes the rows older than six months. It is idempotent, so every
// replica may run it.
func (s Store) Sweep(ctx context.Context) error {
	_, err := s.Pool.Exec(ctx, `DELETE FROM access_log WHERE occurred_at < $1`, s.Now().AddDate(0, -retentionMonths, 0))
	return err
}

func first(vs ...string) string {
	for _, v := range vs {
		if v != "" {
			return v
		}
	}
	return ""
}
