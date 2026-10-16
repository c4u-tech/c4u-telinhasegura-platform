package screentime

import (
	"context"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// ValidMinutes is an extension the API allows: 15, 30 or 60.
func ValidMinutes(m int) bool { return m == 15 || m == 30 || m == 60 }

// Extend grants the child minutes today on its own device, after the
// caller checked the family PIN. accountID is the locked
// session's guardian, "" on a linked device.
func (s *Service) Extend(ctx context.Context, c Child, minutes int, accountID string) (Time, error) {
	m, err := childMinor(ctx, s.d.Pool, c)
	if err != nil {
		return Time{}, err
	}
	return s.extend(ctx, m, minutes, "pin", accountID)
}

// GuardianExtend grants one of the account's children minutes today.
func (s *Service) GuardianExtend(ctx context.Context, accountID, minorID string, minutes int) (Time, error) {
	m, err := guardedMinor(ctx, s.d.Pool, accountID, minorID)
	if err != nil {
		return Time{}, err
	}
	return s.extend(ctx, m, minutes, "guardian", accountID)
}

// extend adds minutes to today's row under its lock, so two grants cannot
// both pass the cap.
func (s *Service) extend(ctx context.Context, m minor, minutes int, via, accountID string) (Time, error) {
	if !ValidMinutes(minutes) {
		return Time{}, ErrValidation
	}
	var t Time
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		r, err := rulesOf(ctx, tx, m)
		if err != nil {
			return err
		}
		loc, err := r.location()
		if err != nil {
			return err
		}
		now := s.now()
		local := now.In(loc)
		date := local.Format(time.DateOnly)
		var d day
		if err := tx.QueryRow(ctx, `INSERT INTO screentime_days (minor_id, day) VALUES ($1::uuid, $2::date)
			ON CONFLICT (minor_id, day) DO UPDATE SET minor_id = EXCLUDED.minor_id
			RETURNING seconds, outside_seconds, extension_minutes`, m.ID, date).Scan(&d.Seconds, &d.OutsideSeconds, &d.ExtensionMinutes); err != nil {
			return err
		}
		if r.DailyMinutes+d.ExtensionMinutes+minutes > MaxDailyMinutes {
			return ErrOverCap
		}
		if _, err := tx.Exec(ctx, `UPDATE screentime_days SET extension_minutes = extension_minutes + $3
			WHERE minor_id = $1::uuid AND day = $2::date`, m.ID, date, minutes); err != nil {
			return err
		}
		var account any
		if validID(accountID) {
			account = accountID
		}
		if _, err := tx.Exec(ctx, `INSERT INTO screentime_extensions (minor_id, day, minutes, via, account_id, created_at)
			VALUES ($1::uuid, $2::date, $3, $4, $5::uuid, $6)`, m.ID, date, minutes, via, account, now); err != nil {
			return err
		}
		d.ExtensionMinutes += minutes
		t = stateAt(r, d, local)
		return nil
	})
	if err != nil {
		return Time{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.ScreenTimeExtended)
	return t, nil
}
