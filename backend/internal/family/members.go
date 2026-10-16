package family

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// Create makes a family with the caller as its owner. The
// database's UNIQUE (account_id) settles a concurrent second create.
func (s *Service) Create(ctx context.Context, accountID string) (Family, error) {
	now := s.now()
	var f Family
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := requireVerified(ctx, tx, accountID); err != nil {
			return err
		}
		var familyID string
		if err := tx.QueryRow(ctx, `INSERT INTO families (created_at) VALUES ($1) RETURNING id::text`, now).Scan(&familyID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO family_members (family_id, account_id, role, joined_at)
			VALUES ($1::uuid, $2::uuid, 'owner', $3)`, familyID, accountID, now)
		if isUniqueViolation(err) {
			return ErrAlreadyInFamily
		}
		if err != nil {
			return err
		}
		f, err = loadFamily(ctx, tx, familyID, Owner, now)
		return err
	})
	if err != nil {
		return Family{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.FamilyCreated)
	return f, nil
}

// Get returns the caller's family.
func (s *Service) Get(ctx context.Context, accountID string) (Family, error) {
	var st standing
	err := s.d.Pool.QueryRow(ctx, `SELECT family_id::text, role FROM family_members WHERE account_id = $1::uuid`,
		accountID).Scan(&st.FamilyID, &st.Role)
	if errors.Is(err, pgx.ErrNoRows) {
		return Family{}, ErrNoFamily
	}
	if err != nil {
		return Family{}, err
	}
	return loadFamily(ctx, s.d.Pool, st.FamilyID, st.Role, s.now())
}

// RemoveGuardian takes a guardian out of the owner's family and tells them.
// The owner's own ID, or anyone else's, answers ErrNotFound.
func (s *Service) RemoveGuardian(ctx context.Context, accountID, guardianID string) error {
	var email string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwner(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(guardianID) {
			return ErrNotFound
		}
		err = tx.QueryRow(ctx, `DELETE FROM family_members m USING accounts a
			WHERE m.family_id = $1::uuid AND m.account_id = $2::uuid AND m.role = 'guardian' AND a.id = m.account_id
			RETURNING a.email`, st.FamilyID, guardianID).Scan(&email)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.GuardianRemoved)
	s.notify(ctx, audit.GuardianRemoved, msgRemoved(email, s.d.AppBaseURL))
	return nil
}

// Leave takes a guardian out of their family; the owner transfers first.
func (s *Service) Leave(ctx context.Context, accountID string) error {
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if st.Role == Owner {
			return ErrOwnerMustTransfer
		}
		_, err = tx.Exec(ctx, `DELETE FROM family_members WHERE account_id = $1::uuid`, accountID)
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.GuardianLeft)
	return nil
}

// TransferOwnership makes a guardian the owner and the caller a guardian,
// in one transaction, and tells both.
func (s *Service) TransferOwnership(ctx context.Context, accountID, newOwnerID string) (Family, error) {
	now := s.now()
	var f Family
	var oldEmail, newEmail string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwner(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(newOwnerID) {
			return ErrNotFound
		}
		// Demote first: the one-owner index is checked per statement.
		if _, err := tx.Exec(ctx, `UPDATE family_members SET role = 'guardian' WHERE account_id = $1::uuid`, accountID); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE family_members SET role = 'owner'
			WHERE family_id = $1::uuid AND account_id = $2::uuid AND account_id <> $3::uuid AND role = 'guardian'`,
			st.FamilyID, newOwnerID, accountID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		if oldEmail, _, err = accountEmail(ctx, tx, accountID); err != nil {
			return err
		}
		if newEmail, _, err = accountEmail(ctx, tx, newOwnerID); err != nil {
			return err
		}
		f, err = loadFamily(ctx, tx, st.FamilyID, Guardian, now)
		return err
	})
	if err != nil {
		return Family{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.OwnershipTransferred)
	s.notify(ctx, audit.OwnershipTransferred,
		msgNowOwner(newEmail, s.d.AppBaseURL), msgNoLongerOwner(oldEmail, s.d.AppBaseURL))
	return f, nil
}

// Delete withdraws every consent of the family's minors, deletes the
// family with its members, invitations and minors, then tells the former
// guardians.
func (s *Service) Delete(ctx context.Context, accountID string) error {
	return s.delete(ctx, accountID, false)
}

// DeleteAsSoleGuardian is Delete for an owner who may only delete a
// family they are alone in: a suspended account. Another guardian answers ErrOtherGuardians, read
// under the family lock, so a join that commits first is seen.
func (s *Service) DeleteAsSoleGuardian(ctx context.Context, accountID string) error {
	return s.delete(ctx, accountID, true)
}

func (s *Service) delete(ctx context.Context, accountID string, soleGuardianOnly bool) error {
	now := s.now()
	var guardians []string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwner(ctx, tx, accountID)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT a.email FROM family_members m JOIN accounts a ON a.id = m.account_id
			WHERE m.family_id = $1::uuid AND m.role = 'guardian' ORDER BY m.joined_at`, st.FamilyID)
		if err != nil {
			return err
		}
		if guardians, err = pgx.CollectRows(rows, pgx.RowTo[string]); err != nil {
			return err
		}
		if soleGuardianOnly && len(guardians) > 0 {
			return ErrOtherGuardians
		}
		if _, err := tx.Exec(ctx, `UPDATE minor_consents SET withdrawn_at = $2, withdrawn_by = $3::uuid
			WHERE family_id = $1::uuid AND withdrawn_at IS NULL`, st.FamilyID, now, accountID); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `DELETE FROM families WHERE id = $1::uuid`, st.FamilyID)
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.FamilyDeleted)
	for _, to := range guardians {
		s.notify(ctx, audit.FamilyDeleted, msgFamilyDeleted(to, s.d.AppBaseURL))
	}
	return nil
}
