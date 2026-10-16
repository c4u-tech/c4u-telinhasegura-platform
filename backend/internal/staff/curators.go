package staff

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/jackc/pgx/v5"
)

// CuratorProfile is a curator's role row, as updateCurator leaves it.
type CuratorProfile struct {
	AccountID            string
	Email                string
	DisplayRole          DisplayRole
	VerifiedProfessional bool
	GrantedAt            time.Time
}

// CuratorPatch changes what it sets; nil fields stay as they are.
type CuratorPatch struct {
	DisplayRole          *DisplayRole
	VerifiedProfessional *bool
}

// The helpers below serve the team writes (team.go).

// insertRole grants role to the account with that email, granted by
// adminID at at, and returns the account ID and normalized email. The
// account must have a verified email and must
// not be suspended. The status is read under the account-row lock in the
// insert's transaction. A second grant of
// the role is ErrAlreadyHasRole. It records nothing: each caller records
// its own action.
func (s *Service) insertRole(ctx context.Context, adminID, email string, role Role, display DisplayRole, verified bool, at time.Time) (string, string, error) {
	id, normalized, ok, err := s.accountByEmail(ctx, email)
	if err != nil {
		return "", "", err
	}
	if id == adminID {
		return "", "", ErrSelfAppointment // on every route
	}
	if !ok {
		return "", "", ErrEmailUnverified
	}
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		if err := lockActive(ctx, tx, id); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO platform_roles (account_id, role, display_role, verified_professional, granted_by, granted_at)
			VALUES ($1::uuid, $2, nullif($3, ''), $4, $5::uuid, $6) ON CONFLICT DO NOTHING`,
			id, string(role), string(display), verified, adminID, at)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrAlreadyHasRole
		}
		return nil
	})
	if err != nil {
		return "", "", err
	}
	return id, normalized, nil
}

// lockActive takes the account-row lock a suspension takes and refuses
// any account that is not active, failing closed as refuseSuspended
// does, so a grant and a suspension never interleave.
func lockActive(ctx context.Context, tx pgx.Tx, id string) error {
	st, err := lockAccount(ctx, tx, id)
	if err != nil {
		return err
	}
	if st != identity.StatusActive {
		return ErrAccountSuspended
	}
	return nil
}

// updateCurator applies p to the curator's role row, checking the result
// as an appointment would.
func (s *Service) updateCurator(ctx context.Context, accountID string, p CuratorPatch) (CuratorProfile, error) {
	if !validID(accountID) {
		return CuratorProfile{}, ErrNotFound
	}
	if p.DisplayRole == nil && p.VerifiedProfessional == nil {
		return CuratorProfile{}, ErrValidation
	}
	var c CuratorProfile
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var err error
		c, err = scanCurator(tx.QueryRow(ctx, `SELECT a.id::text, a.email, r.display_role, r.verified_professional, r.granted_at
			FROM platform_roles r JOIN accounts a ON a.id = r.account_id
			WHERE r.account_id = $1::uuid AND r.role = 'curator' FOR UPDATE OF r`, accountID))
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if p.DisplayRole != nil && *p.DisplayRole != c.DisplayRole {
			// A new displayed role is checked as an appointment: a
			// professional one needs the flag in this same patch, a
			// non-professional one drops it.
			c.DisplayRole = *p.DisplayRole
			c.VerifiedProfessional = false
		}
		if p.VerifiedProfessional != nil {
			c.VerifiedProfessional = *p.VerifiedProfessional
		}
		if err := checkDisplayRole(c.DisplayRole, c.VerifiedProfessional); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE platform_roles SET display_role = $2, verified_professional = $3
			WHERE account_id = $1::uuid AND role = 'curator'`, accountID, string(c.DisplayRole), c.VerifiedProfessional)
		return err
	})
	if err != nil {
		return CuratorProfile{}, err
	}
	return c, nil
}

// deleteRole takes role away. A curator's reviews stay, with their
// displayed-role snapshots; a review in flight holds the role row FOR
// SHARE (curation's read seam), so the delete waits for it.
func (s *Service) deleteRole(ctx context.Context, accountID string, role Role) error {
	if !validID(accountID) {
		return ErrNotFound
	}
	tag, err := s.d.Pool.Exec(ctx, `DELETE FROM platform_roles WHERE account_id = $1::uuid AND role = $2`, accountID, string(role))
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func scanCurator(row scanner) (CuratorProfile, error) {
	var c CuratorProfile
	var role string
	err := row.Scan(&c.AccountID, &c.Email, &role, &c.VerifiedProfessional, &c.GrantedAt)
	c.DisplayRole, c.GrantedAt = DisplayRole(role), c.GrantedAt.UTC()
	return c, err
}
