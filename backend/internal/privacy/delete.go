package privacy

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/appleid"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/jackc/pgx/v5"
)

// errMembershipMoved means the caller joined or left a family between the
// unlocked read and the account lock; the transaction is retried.
var errMembershipMoved = errors.New("privacy: membership changed while locking")

// DeleteAccount erases the account at once. It refuses an
// owner. An account linked to Apple first revokes its Apple
// authorization with a fresh credential; Apple's
// availability never blocks the erasure. Everything the
// account owns goes through the schema's cascades; the rows that keep
// its ID hold no personal data.
func (s *Service) DeleteAccount(ctx context.Context, accountID string, apple *AppleCredential) error {
	// An unlocked pre-check, so a refused owner never spends the single-use
	// Apple code; the check under the locks in deleteAccount stays the
	// authority.
	var owner bool
	if err := s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_members
		WHERE account_id = $1::uuid AND role = 'owner')`, accountID).Scan(&owner); err != nil {
		return err
	}
	if owner {
		return ErrOwnerMustTransfer
	}
	revocationFailed, err := s.revokeApple(ctx, accountID, apple)
	if err != nil {
		return err
	}
	var email string
	for range 3 {
		email, err = s.deleteAccount(ctx, accountID)
		if !errors.Is(err, errMembershipMoved) {
			break
		}
	}
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.AccountDeleted)
	if revocationFailed {
		s.d.Audit.Record(ctx, accountID, audit.AppleRevocationFailed)
	}
	// Best effort: the erasure already took effect.
	if err := s.d.Mail.Send(ctx, msgAccountDeleted(email)); err != nil {
		s.d.Log.Error("privacy: deletion notice not sent", "err", err)
	}
	return nil
}

// revokeApple runs before the erasure, outside its transaction. It
// answers whether a revocation was due and failed; an error stops the
// deletion.
func (s *Service) revokeApple(ctx context.Context, accountID string, apple *AppleCredential) (bool, error) {
	var subject string
	err := s.d.Pool.QueryRow(ctx, `SELECT subject FROM external_identities
		WHERE account_id = $1::uuid AND provider = 'apple'`, accountID).Scan(&subject)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil // a credential, if any, is ignored
	}
	if err != nil {
		return false, err
	}
	if s.d.Apple == nil {
		s.d.Log.Error("privacy: Apple revocation skipped", "class", "unconfigured")
		return true, nil
	}
	if apple == nil {
		return false, ErrAppleReauthRequired
	}
	c, err := s.d.IDTokens.Verify(ctx, idtoken.Apple, apple.IdentityToken)
	if errors.Is(err, idtoken.ErrDisabled) {
		s.d.Log.Error("privacy: Apple revocation skipped", "class", "unconfigured")
		return true, nil
	}
	if err != nil || c.Subject != subject {
		return false, ErrAppleIdentityMismatch
	}
	err = s.d.Apple.Revoke(ctx, c.Audience, apple.AuthorizationCode, apple.RedirectURI)
	switch {
	case err == nil:
		return false, nil
	case errors.Is(err, appleid.ErrInvalidGrant):
		return false, ErrAppleAuthorizationInvalid
	default:
		s.d.Log.Error("privacy: Apple revocation failed", "class", appleid.Class(err))
		return true, nil
	}
}

// deleteAccount takes the family row lock first, the order every family
// write uses, then the account row. Holding the account row blocks any
// new membership of it (an insert must key-share the row), and holding
// the family row blocks any transfer, so the owner check below stays
// true until the commit.
func (s *Service) deleteAccount(ctx context.Context, accountID string) (string, error) {
	tx, err := s.d.Pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	locked, err := familyOf(ctx, tx, accountID)
	if err != nil {
		return "", err
	}
	if locked != "" {
		if _, err := tx.Exec(ctx, `SELECT 1 FROM families WHERE id = $1::uuid FOR UPDATE`, locked); err != nil {
			return "", err
		}
	}
	var email string
	if err := tx.QueryRow(ctx, `SELECT email FROM accounts WHERE id = $1::uuid FOR UPDATE`, accountID).Scan(&email); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrAccountGone
		}
		return "", err
	}
	current, err := familyOf(ctx, tx, accountID)
	if err != nil {
		return "", err
	}
	if current != locked {
		return "", errMembershipMoved
	}
	var owner bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_members
		WHERE account_id = $1::uuid AND role = 'owner')`, accountID).Scan(&owner); err != nil {
		return "", err
	}
	if owner {
		return "", ErrOwnerMustTransfer
	}
	// Pending provider signups for this email hold it with no account row,
	// so no cascade reaches them.
	if _, err := tx.Exec(ctx, `DELETE FROM provider_tickets WHERE account_id IS NULL AND email = $1`, email); err != nil {
		return "", err
	}
	// Every non-owner joined by accepting an invitation to this email. An
	// accepted row is never written again and seats count only pending
	// ones, so no other family's lock is needed. Pending and revoked ones
	// stay: they are the inviting family's record.
	if _, err := tx.Exec(ctx, `DELETE FROM family_invitations WHERE email = $1 AND accepted_at IS NOT NULL`, email); err != nil {
		return "", err
	}
	// A report outlives its author so the family's count holds, but its
	// note is the author's own words. The
	// cascade then sets account_id and hidden_by to NULL.
	if _, err := tx.Exec(ctx, `UPDATE video_reports SET note = NULL WHERE account_id = $1::uuid`, accountID); err != nil {
		return "", err
	}
	// An action about the account keeps its ids, but its reason may
	// describe the person.
	if _, err := tx.Exec(ctx, `UPDATE audit_events SET reason = NULL
		WHERE subject_kind = 'account' AND subject_id = $1::uuid`, accountID); err != nil {
		return "", err
	}
	// Mail still queued for the person goes with them, at the
	// account's address and at any address a change token would move it
	// to; the tokens cascade with the account, so read them first. The
	// deletion notice is enqueued after the commit and still goes out.
	var changeTo []string
	if err := tx.QueryRow(ctx, `SELECT coalesce(array_agg(new_email), '{}') FROM email_tokens
		WHERE account_id = $1::uuid AND new_email IS NOT NULL`, accountID).Scan(&changeTo); err != nil {
		return "", err
	}
	if err := mail.Purge(ctx, tx, append(changeTo, email)...); err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM accounts WHERE id = $1::uuid`, accountID); err != nil {
		return "", err
	}
	return email, tx.Commit(ctx)
}

// familyOf is the account's family ID, or "" for none.
func familyOf(ctx context.Context, tx pgx.Tx, accountID string) (string, error) {
	var id string
	err := tx.QueryRow(ctx, `SELECT family_id::text FROM family_members WHERE account_id = $1::uuid`, accountID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	return id, err
}
