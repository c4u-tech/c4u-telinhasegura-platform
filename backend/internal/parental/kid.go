package parental

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// EnterKidMode locks the calling session to one child of the family
// ("entregar para"). The family must have a PIN, or nothing could
// end the lock.
func (s *Service) EnterKidMode(ctx context.Context, accountID, sessionID, minorID string) error {
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
		_, err = tx.Exec(ctx, `INSERT INTO session_kid_locks (session_id, minor_id, locked_at) VALUES ($1::uuid, $2::uuid, $3)`,
			sessionID, minorID, s.now())
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.KidModeEntered)
	return nil
}

// Lock reports whether the session is in kid mode, and for which child:
// "" once that child was deleted, since the lock outlives it.
func (s *Service) Lock(ctx context.Context, sessionID string) (minorID string, locked bool, err error) {
	var m *string
	err = s.d.Pool.QueryRow(ctx, `SELECT minor_id::text FROM session_kid_locks WHERE session_id = $1::uuid`, sessionID).Scan(&m)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	if m != nil {
		minorID = *m
	}
	return minorID, true, nil
}

// SessionPrincipal turns a locked session into a child principal; an
// unlocked one is ErrNotChild.
func (s *Service) SessionPrincipal(ctx context.Context, sessionID, accountID string) (Principal, error) {
	minorID, locked, err := s.Lock(ctx, sessionID)
	if err != nil {
		return Principal{}, err
	}
	if !locked {
		return Principal{}, ErrNotChild
	}
	familyID, err := familyOf(ctx, s.d.Pool, accountID)
	if errors.Is(err, ErrNoFamily) {
		err = nil // left the family while locked: Unlock ends the session
	}
	return Principal{FamilyID: familyID, MinorID: minorID, SessionID: sessionID, AccountID: accountID}, err
}

// Unlock ends kid mode with the family PIN. A locked session
// whose guardian no longer has a family (removed, or the family deleted)
// has no family PIN to give: whatever PIN was sent, the session is
// ended and its lock deleted, and the answer is ErrUnauthenticated, so the
// device signs out. A lock is never lifted into a guardian account without
// the PIN.
func (s *Service) Unlock(ctx context.Context, p Principal, pin string) error {
	if p.SessionID == "" {
		return ErrNotFound // a device has nothing to unlock
	}
	if p.FamilyID == "" {
		return s.endLockedSession(ctx, p)
	}
	if err := s.checkPIN(ctx, p.FamilyID, p.AccountID, pin); err != nil {
		return err
	}
	tag, err := s.d.Pool.Exec(ctx, `DELETE FROM session_kid_locks WHERE session_id = $1::uuid RETURNING session_id`, p.SessionID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		s.d.Audit.Record(ctx, p.AccountID, audit.KidModeExited)
	}
	return nil
}

// endLockedSession revokes a locked session that has no family PIN left
// and deletes its lock, in one transaction.
func (s *Service) endLockedSession(ctx context.Context, p Principal) error {
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE sessions SET revoked_at = $2 WHERE id = $1::uuid AND revoked_at IS NULL`,
			p.SessionID, s.now()); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `DELETE FROM session_kid_locks WHERE session_id = $1::uuid`, p.SessionID)
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, p.AccountID, audit.SessionRevoked)
	return ErrUnauthenticated
}

// Profile is the child principal's own profile.
func (s *Service) Profile(ctx context.Context, p Principal) (Profile, error) {
	if p.FamilyID == "" || p.MinorID == "" {
		return Profile{}, ErrProfileGone
	}
	return profileOf(ctx, s.d.Pool, p.FamilyID, p.MinorID)
}
