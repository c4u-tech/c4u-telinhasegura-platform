package family

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
	"github.com/jackc/pgx/v5"
)

// Invite mails a single-use invitation valid for 7 days. Its
// answer does not depend on the invited address's account.
func (s *Service) Invite(ctx context.Context, accountID, email string) (Invitation, error) {
	email = identity.NormalizeEmail(email)
	now := s.now()
	plain, hash := secret.NewToken()
	var inv Invitation
	var inviter string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwner(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !identity.ValidEmail(email) {
			return ErrValidation
		}
		if ok, wait := s.d.InviteLimiter.Allow(st.FamilyID); !ok {
			return &ThrottledError{RetryAfter: wait}
		}
		var member bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_members m JOIN accounts a ON a.id = m.account_id
			WHERE m.family_id = $1::uuid AND a.email = $2)`, st.FamilyID, email).Scan(&member); err != nil {
			return err
		}
		if member {
			return ErrAlreadyMember
		}
		if _, err := tx.Exec(ctx, `UPDATE family_invitations SET revoked_at = $3
			WHERE family_id = $1::uuid AND email = $2 AND accepted_at IS NULL AND revoked_at IS NULL`, st.FamilyID, email, now); err != nil {
			return err
		}
		var seats int
		if err := tx.QueryRow(ctx, `SELECT (SELECT count(*) FROM family_members WHERE family_id = $1::uuid)
			+ (SELECT count(*) FROM family_invitations WHERE family_id = $1::uuid
			   AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > $2)`, st.FamilyID, now).Scan(&seats); err != nil {
			return err
		}
		if seats >= maxSeats {
			return ErrLimitReached
		}
		inv = Invitation{Email: email, ExpiresAt: now.Add(invitationTTL)}
		if err := tx.QueryRow(ctx, `INSERT INTO family_invitations (token_hash, family_id, email, invited_by, created_at, expires_at)
			VALUES ($1, $2::uuid, $3, $4::uuid, $5, $6) RETURNING id::text`,
			hash, st.FamilyID, email, accountID, now, inv.ExpiresAt).Scan(&inv.ID); err != nil {
			return err
		}
		inviter, _, err = accountEmail(ctx, tx, accountID)
		return err
	})
	if err != nil {
		return Invitation{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.InvitationSent)
	// The link is built from the configured base only, never a request.
	if err := s.d.Mail.Send(ctx, msgInvitation(email, inviter, s.d.AppBaseURL+"/convite?token="+plain)); err != nil {
		return Invitation{}, err
	}
	return inv, nil
}

// RevokeInvitation cancels a pending invitation of the owner's family;
// any other ID answers like an unknown one.
func (s *Service) RevokeInvitation(ctx context.Context, accountID, invitationID string) error {
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwner(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(invitationID) {
			return ErrNotFound
		}
		tag, err := tx.Exec(ctx, `UPDATE family_invitations SET revoked_at = $3
			WHERE id = $1::uuid AND family_id = $2::uuid AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > $3`,
			invitationID, st.FamilyID, s.now())
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.InvitationRevoked)
	return nil
}

type invitationRow struct {
	ID, FamilyID, Email, InvitedBy string
	ExpiresAt                      time.Time
}

// pendingInvitation finds a spendable invitation by its token's digest;
// unknown, expired, revoked and accepted tokens look alike.
func pendingInvitation(ctx context.Context, q querier, hash []byte, now time.Time) (invitationRow, error) {
	var inv invitationRow
	err := q.QueryRow(ctx, `SELECT id::text, family_id::text, email, invited_by::text, expires_at FROM family_invitations
		WHERE token_hash = $1 AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > $2`, hash, now).
		Scan(&inv.ID, &inv.FamilyID, &inv.Email, &inv.InvitedBy, &inv.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return invitationRow{}, ErrInvalidToken
	}
	return inv, err
}

// pendingInvitationFor finds a pending invitation by id among those sent
// to email; another's invitation looks like an unknown one.
func pendingInvitationFor(ctx context.Context, q querier, id, email string, now time.Time) (invitationRow, error) {
	var inv invitationRow
	err := q.QueryRow(ctx, `SELECT id::text, family_id::text, email, invited_by::text, expires_at FROM family_invitations
		WHERE id = $1::uuid AND email = $2 AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > $3`, id, email, now).
		Scan(&inv.ID, &inv.FamilyID, &inv.Email, &inv.InvitedBy, &inv.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return invitationRow{}, ErrInvitationUnavailable
	}
	return inv, err
}

// PendingInvitations lists the pending invitations to the caller's
// verified email, from any family, newest first. An
// account already in a family has none it could take.
func (s *Service) PendingInvitations(ctx context.Context, accountID string) ([]ReceivedInvitation, error) {
	email, err := requireVerified(ctx, s.d.Pool, accountID)
	if err != nil {
		return nil, err
	}
	out := []ReceivedInvitation{}
	var inFamily bool
	if err := s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_members WHERE account_id = $1::uuid)`,
		accountID).Scan(&inFamily); err != nil || inFamily {
		return out, err
	}
	// The inviter's account may be gone: invited_by has no foreign key.
	rows, err := s.d.Pool.Query(ctx, `SELECT i.id::text, coalesce(a.email, ''), i.expires_at
		FROM family_invitations i LEFT JOIN accounts a ON a.id = i.invited_by
		WHERE i.email = $1 AND i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > $2
		ORDER BY i.created_at DESC, i.id`, email, s.now())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var inv ReceivedInvitation
		if err := rows.Scan(&inv.ID, &inv.InviterEmail, &inv.ExpiresAt); err != nil {
			return nil, err
		}
		out = append(out, inv)
	}
	return out, rows.Err()
}

// checkAcceptance applies the acceptance checks in order. None of them spends the token.
func checkAcceptance(ctx context.Context, q querier, inv invitationRow, accountID, email string) error {
	if inv.Email != email {
		return ErrInvitationEmailMismatch
	}
	var inFamily bool
	if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_members WHERE account_id = $1::uuid)`, accountID).Scan(&inFamily); err != nil {
		return err
	}
	if inFamily {
		return ErrAlreadyInFamily
	}
	var members int
	if err := q.QueryRow(ctx, `SELECT count(*) FROM family_members WHERE family_id = $1::uuid`, inv.FamilyID).Scan(&members); err != nil {
		return err
	}
	if members >= maxSeats {
		return ErrLimitReached
	}
	return nil
}

func (s *Service) throttleToken(accountID string) error {
	if ok, wait := s.d.TokenLimiter.Allow(accountID); !ok {
		return &ThrottledError{RetryAfter: wait}
	}
	return nil
}

// LookupInvitation runs every acceptance check and changes nothing.
func (s *Service) LookupInvitation(ctx context.Context, accountID, token string) (Preview, error) {
	if err := s.throttleToken(accountID); err != nil {
		return Preview{}, err
	}
	email, err := requireVerified(ctx, s.d.Pool, accountID)
	if err != nil {
		return Preview{}, err
	}
	inv, err := pendingInvitation(ctx, s.d.Pool, secret.Hash(token), s.now())
	if err != nil {
		return Preview{}, err
	}
	if err := checkAcceptance(ctx, s.d.Pool, inv, accountID, email); err != nil {
		return Preview{}, err
	}
	p := Preview{InvitedEmail: inv.Email, ExpiresAt: inv.ExpiresAt}
	err = s.d.Pool.QueryRow(ctx, `SELECT coalesce((SELECT email FROM accounts WHERE id = $1::uuid), '')`,
		inv.InvitedBy).Scan(&p.InviterEmail)
	return p, err
}

// AcceptInvitation spends the token and adds the caller as a guardian, in
// one transaction.
func (s *Service) AcceptInvitation(ctx context.Context, accountID, token string) (Family, error) {
	hash := secret.Hash(token)
	return s.accept(ctx, accountID, func(q querier, _ string, now time.Time) (invitationRow, error) {
		return pendingInvitation(ctx, q, hash, now)
	})
}

// AcceptInvitationByID takes a pending invitation to the caller's own
// email. Every id it cannot take answers
// ErrInvitationUnavailable alike.
func (s *Service) AcceptInvitationByID(ctx context.Context, accountID, invitationID string) (Family, error) {
	return s.accept(ctx, accountID, func(q querier, email string, now time.Time) (invitationRow, error) {
		if !validID(invitationID) {
			return invitationRow{}, ErrInvitationUnavailable
		}
		return pendingInvitationFor(ctx, q, invitationID, email, now)
	})
}

// accept runs one acceptance. find names the invitation for the caller's
// verified email; it runs before the family lock and again under it,
// since a concurrent accept or revoke may have spent it.
func (s *Service) accept(ctx context.Context, accountID string,
	find func(q querier, email string, now time.Time) (invitationRow, error)) (Family, error) {
	if err := s.throttleToken(accountID); err != nil {
		return Family{}, err
	}
	now := s.now()
	var f Family
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		email, err := requireVerified(ctx, tx, accountID)
		if err != nil {
			return err
		}
		inv, err := find(tx, email, now)
		if err != nil {
			return err
		}
		if err := lockFamily(ctx, tx, inv.FamilyID); err != nil {
			return err
		}
		if inv, err = find(tx, email, now); err != nil {
			return err
		}
		if err := checkAcceptance(ctx, tx, inv, accountID, email); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE family_invitations SET accepted_at = $2 WHERE id = $1::uuid`, inv.ID, now); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO family_members (family_id, account_id, role, joined_at)
			VALUES ($1::uuid, $2::uuid, 'guardian', $3)`, inv.FamilyID, accountID, now)
		if isUniqueViolation(err) {
			return ErrAlreadyInFamily // joined another family concurrently
		}
		if err != nil {
			return err
		}
		f, err = loadFamily(ctx, tx, inv.FamilyID, Guardian, now)
		return err
	})
	if err != nil {
		return Family{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.InvitationAccepted)
	return f, nil
}
