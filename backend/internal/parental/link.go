package parental

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
	"github.com/jackc/pgx/v5"
)

// codeDraws bounds the redraws when a fresh code collides with a stored
// one (one in ~10¹² per stored code).
const codeDraws = 3

// CreateLinkCode issues a 10-minute code that links a device to one child.
// The family needs a PIN, which is what guards the
// device's profile picker.
func (s *Service) CreateLinkCode(ctx context.Context, accountID, minorID string) (LinkCode, error) {
	if ok, wait := s.d.CodeLimiter.Allow(accountID); !ok {
		return LinkCode{}, &ThrottledError{RetryAfter: wait}
	}
	now := s.now()
	lc := LinkCode{MinorID: minorID, ExpiresAt: now.Add(codeTTL)}
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		familyID, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if err := minorOfFamily(ctx, tx, familyID, minorID); err != nil {
			return err
		}
		if err := pinExists(ctx, tx, familyID); err != nil {
			return err
		}
		var live int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM link_codes
			WHERE family_id = $1::uuid AND used_at IS NULL AND expires_at > $2`, familyID, now).Scan(&live); err != nil {
			return err
		}
		if live >= maxLiveCodes {
			return ErrLimitReached
		}
		for range codeDraws {
			if lc.Code, err = NewCode(s.rand()); err != nil {
				return err
			}
			tag, err := tx.Exec(ctx, `INSERT INTO link_codes (code_hash, family_id, minor_id, created_by, expires_at)
				VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5) ON CONFLICT (code_hash) DO NOTHING`,
				secret.Hash(NormalizeCode(lc.Code)), familyID, minorID, accountID, lc.ExpiresAt)
			if err != nil || tag.RowsAffected() == 1 {
				return err
			}
		}
		return errors.New("parental: no free link code after redraws")
	})
	if err != nil {
		return LinkCode{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.LinkCodeCreated)
	return lc, nil
}

// Redeem spends a live code and links a device to its child, answering the
// device's token once. It takes the family lock before the
// code's row lock, the order the family module's minor deletion takes them
// (family lock, then the cascade), so the two cannot deadlock.
func (s *Service) Redeem(ctx context.Context, code, label string) (Redeemed, error) {
	label, err := NormalizeLabel(label)
	if err != nil {
		return Redeemed{}, err
	}
	now := s.now()
	hash := secret.Hash(NormalizeCode(code))
	var out Redeemed
	var createdBy string
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		var familyID, minorID string
		err := tx.QueryRow(ctx, `SELECT family_id::text FROM link_codes WHERE code_hash = $1`, hash).Scan(&familyID)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidCode
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `SELECT 1 FROM families WHERE id = $1::uuid FOR UPDATE`, familyID); err != nil {
			return err
		}
		// Re-read under the lock: a concurrent redemption may have spent it.
		err = tx.QueryRow(ctx, `SELECT minor_id::text, created_by::text FROM link_codes
			WHERE code_hash = $1 AND used_at IS NULL AND expires_at > $2 FOR UPDATE`, hash, now).Scan(&minorID, &createdBy)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidCode
		}
		if err != nil {
			return err
		}
		var devices int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM devices WHERE family_id = $1::uuid AND last_seen_at > $2`,
			familyID, now.Add(-deviceIdle)).Scan(&devices); err != nil {
			return err
		}
		if devices >= maxDevices {
			return ErrLimitReached
		}
		if _, err := tx.Exec(ctx, `UPDATE link_codes SET used_at = $2 WHERE code_hash = $1`, hash, now); err != nil {
			return err
		}
		token, tokenHash := secret.NewToken()
		if _, err := tx.Exec(ctx, `INSERT INTO devices (family_id, minor_id, token_hash, label, linked_at, last_seen_at)
			VALUES ($1::uuid, $2::uuid, $3, $4, $5, $5)`, familyID, minorID, tokenHash, label, now); err != nil {
			return err
		}
		out.Token = token
		out.Profile, err = s.profileOf(ctx, tx, familyID, minorID)
		return err
	})
	if err != nil {
		return Redeemed{}, err
	}
	s.d.Audit.Record(ctx, createdBy, audit.DeviceLinked)
	return out, nil
}

// AuthenticateDevice resolves a device token to its child principal and
// marks it seen, in one statement, so a device cannot expire between the
// check and the update. An unknown token, or one idle for over 180 days, is
// ErrUnauthenticated; the idle device is deleted.
func (s *Service) AuthenticateDevice(ctx context.Context, token string) (Principal, error) {
	now := s.now()
	hash := secret.Hash(token)
	cutoff := now.Add(-deviceIdle)
	var p Principal
	err := s.d.Pool.QueryRow(ctx, `UPDATE devices SET last_seen_at = $2 WHERE token_hash = $1 AND last_seen_at >= $3
		RETURNING id::text, family_id::text, minor_id::text`, hash, now, cutoff).Scan(&p.DeviceID, &p.FamilyID, &p.MinorID)
	if errors.Is(err, pgx.ErrNoRows) {
		if _, err := s.d.Pool.Exec(ctx, `DELETE FROM devices WHERE token_hash = $1 AND last_seen_at < $2`, hash, cutoff); err != nil {
			return Principal{}, err
		}
		return Principal{}, ErrUnauthenticated
	}
	if err != nil {
		return Principal{}, err
	}
	return p, nil
}

// SweepDevices deletes the devices idle for over 180 days. Such a device
// can no longer sign in and no list shows it, so its name and dates go at
// once rather than waiting for it to call again, which it may never do.
// It is idempotent, so every replica may run it.
func (s *Service) SweepDevices(ctx context.Context) error {
	_, err := s.d.Pool.Exec(ctx, `DELETE FROM devices WHERE last_seen_at < $1`, s.now().Add(-deviceIdle))
	return err
}
