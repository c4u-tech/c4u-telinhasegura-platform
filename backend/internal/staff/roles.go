package staff

import (
	"context"
	"errors"
	"slices"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// Roles lists the account's platform roles in name order; none is an
// empty, non-nil list.
func (s *Service) Roles(ctx context.Context, accountID string) ([]Role, error) {
	rows, err := s.d.Pool.Query(ctx, `SELECT role FROM platform_roles WHERE account_id = $1::uuid ORDER BY role`, accountID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Role, error) {
		var role string
		err := r.Scan(&role)
		return Role(role), err
	})
}

// GrantAdmin makes the account with that email an admin. Only the server
// command calls it; no route can. A second
// grant changes nothing. A suspended account is refused under the
// account-row lock.
func (s *Service) GrantAdmin(ctx context.Context, email string) (string, error) {
	id, _, _, err := s.accountByEmail(ctx, email)
	if err != nil {
		return "", err
	}
	var granted bool
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		if err := lockActive(ctx, tx, id); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `INSERT INTO platform_roles (account_id, role, granted_at)
			VALUES ($1::uuid, 'admin', $2) ON CONFLICT DO NOTHING`, id, s.now())
		granted = tag.RowsAffected() == 1
		return err
	})
	if err != nil {
		return "", err
	}
	if granted {
		s.d.Audit.Record(ctx, id, audit.AdminGranted) // no actor: the server command
	}
	return id, nil
}

// RevokeAdmin removes the admin role.
func (s *Service) RevokeAdmin(ctx context.Context, email string) (string, error) {
	id, _, _, err := s.accountByEmail(ctx, email)
	if err != nil {
		return "", err
	}
	tag, err := s.d.Pool.Exec(ctx, `DELETE FROM platform_roles WHERE account_id = $1::uuid AND role = 'admin'`, id)
	if err != nil {
		return "", err
	}
	if tag.RowsAffected() == 0 {
		return "", ErrNotAdmin
	}
	s.d.Audit.Record(ctx, id, audit.AdminRevoked)
	return id, nil
}

// accountByEmail finds an account by its normalized email.
func (s *Service) accountByEmail(ctx context.Context, email string) (id, normalized string, verified bool, err error) {
	err = s.d.Pool.QueryRow(ctx, `SELECT id::text, email, email_verified_at IS NOT NULL FROM accounts WHERE email = $1`,
		identity.NormalizeEmail(email)).Scan(&id, &normalized, &verified)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", false, ErrAccountNotFound
	}
	return id, normalized, verified, err
}

// FirstRole is the first of roles the account holds, "" for none. It
// reads the database on every call, with no cache, so a removal takes
// effect on the next request.
func (s *Service) FirstRole(ctx context.Context, accountID string, roles ...Role) (Role, error) {
	held, err := s.Roles(ctx, accountID)
	if err != nil {
		return "", err
	}
	for _, r := range roles {
		if slices.Contains(held, r) {
			return r, nil
		}
	}
	return "", nil
}
