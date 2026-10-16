package parental

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/jackc/pgx/v5"
)

// PINSet answers whether the caller's family has a PIN, and nothing else
// about it.
func (s *Service) PINSet(ctx context.Context, accountID string) (bool, error) {
	familyID, err := familyOf(ctx, s.d.Pool, accountID)
	if err != nil {
		return false, err
	}
	var set bool
	err = s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_pins WHERE family_id = $1::uuid)`, familyID).Scan(&set)
	return set, err
}

// SetPIN sets or replaces the family PIN and clears its cooldown.
// The route requires a recent re-authentication; the other
// guardians get a notice.
func (s *Service) SetPIN(ctx context.Context, accountID, pin string) error {
	now := s.now()
	// Standing, then the body (a caller outside a family hears 404, not
	// 422); the slow hash runs before the family row is locked.
	if _, err := familyOf(ctx, s.d.Pool, accountID); err != nil {
		return err
	}
	if err := ValidatePIN(pin); err != nil {
		return err
	}
	pinHash := identity.HashPassword(pin, s.d.Hash)
	var others []string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		familyID, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO family_pins (family_id, pin_hash, failed_attempts, blocked_until, updated_at)
			VALUES ($1::uuid, $2, 0, NULL, $3)
			ON CONFLICT (family_id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash,
				failed_attempts = 0, blocked_until = NULL, updated_at = EXCLUDED.updated_at`,
			familyID, pinHash, now); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT a.email FROM family_members m JOIN accounts a ON a.id = m.account_id
			WHERE m.family_id = $1::uuid AND m.account_id <> $2::uuid ORDER BY a.email`, familyID, accountID)
		if err != nil {
			return err
		}
		others, err = pgx.CollectRows(rows, pgx.RowTo[string])
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.PINSet)
	msgs := make([]mail.Message, 0, len(others))
	for _, to := range others {
		msgs = append(msgs, msgPINChanged(to, now, s.d.AppBaseURL))
	}
	s.notify(ctx, audit.PINSet, msgs...)
	return nil
}

// VerifyPIN checks a PIN for a member with an unlocked session, through the
// same checkPIN as unlock and the picker, so the family's counter and
// cooldown are shared.
func (s *Service) VerifyPIN(ctx context.Context, accountID, pin string) error {
	familyID, err := familyOf(ctx, s.d.Pool, accountID)
	if err != nil {
		return err
	}
	return s.checkPIN(ctx, familyID, accountID, pin)
}

// CheckChildPIN checks the family PIN on a child's device, for a gate a
// guardian opens there (the screen-time extension), through the same checkPIN, so the family's counter and block
// are shared.
func (s *Service) CheckChildPIN(ctx context.Context, p Principal, pin string) error {
	if p.FamilyID == "" || p.MinorID == "" {
		return ErrProfileGone
	}
	actor := ""
	if p.SessionID != "" {
		actor = p.AccountID
	}
	return s.checkPIN(ctx, p.FamilyID, actor, pin)
}

// checkPIN is the one place a PIN is compared, so every gate shares the
// family's cooldown. actorID is the account a block is audited
// under; "" for a device.
//
// The whole check runs in one transaction under the family_pins row lock,
// so parallel guesses are counted one after another and a success cannot
// wipe a block a concurrent failure wrote. Only that row is locked: SetPIN
// and family deletion take families, then family_pins, so the lock order
// never inverts.
func (s *Service) checkPIN(ctx context.Context, familyID, actorID, pin string) error {
	now := s.now()
	var outcome error // returned after the commit, never as the tx's error
	var blocked bool
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var hash string
		var failed int
		var blockedUntil time.Time
		err := tx.QueryRow(ctx, `SELECT pin_hash, failed_attempts, coalesce(blocked_until, 'epoch'::timestamptz)
			FROM family_pins WHERE family_id = $1::uuid FOR UPDATE`, familyID).Scan(&hash, &failed, &blockedUntil)
		if errors.Is(err, pgx.ErrNoRows) {
			outcome = ErrPINNotSet
			return nil
		}
		if err != nil {
			return err
		}
		if now.Before(blockedUntil) { // no verification while blocked
			outcome = &ThrottledError{RetryAfter: blockedUntil.Sub(now)}
			return nil
		}
		ok, err := identity.VerifyPassword(pin, hash)
		if err != nil {
			return err
		}
		if ok {
			if failed > 0 {
				_, err = tx.Exec(ctx, `UPDATE family_pins SET failed_attempts = 0, blocked_until = NULL WHERE family_id = $1::uuid`, familyID)
			}
			return err
		}
		// One statement counts the failure and sets the block from the new
		// count: from the 5th failure 30 s, doubling to 15 minutes. The
		// exponent is clamped so power() cannot overflow.
		err = tx.QueryRow(ctx, `UPDATE family_pins SET
			failed_attempts = failed_attempts + 1,
			blocked_until = CASE WHEN failed_attempts + 1 >= 5
				THEN $2::timestamptz + LEAST(interval '30 seconds' * power(2, LEAST(failed_attempts + 1 - 5, 20)), interval '15 minutes')
				ELSE blocked_until END
			WHERE family_id = $1::uuid RETURNING failed_attempts`, familyID, now).Scan(&failed)
		if err != nil {
			return err
		}
		blocked = failed == failuresBeforeBlock
		outcome = ErrInvalidPIN
		return nil
	})
	if err != nil {
		return err
	}
	if blocked {
		s.d.Audit.Record(ctx, actorID, audit.PINBlocked)
	}
	return outcome
}
