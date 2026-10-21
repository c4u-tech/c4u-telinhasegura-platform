package family

// The staff directory's reads of a family, kept to the least it needs:
// counts and the caller's role only, never a minor.

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// Membership is an account's family and its role in it.
type Membership struct {
	FamilyID string
	Role     Role
}

// Membership reads the account's family; ok is false without one, or
// for a malformed id.
func (s *Service) Membership(ctx context.Context, accountID string) (Membership, bool, error) {
	if !validID(accountID) {
		return Membership{}, false, nil
	}
	var m Membership
	var role string
	err := s.d.Pool.QueryRow(ctx, `SELECT family_id::text, role FROM family_members WHERE account_id = $1::uuid`,
		accountID).Scan(&m.FamilyID, &role)
	if errors.Is(err, pgx.ErrNoRows) {
		return Membership{}, false, nil
	}
	if err != nil {
		return Membership{}, false, err
	}
	m.Role = Role(role)
	return m, true, nil
}

// MinorCount counts the family's children.
func (s *Service) MinorCount(ctx context.Context, familyID string) (int, error) {
	return s.countRows(ctx, `SELECT count(*) FROM minors WHERE family_id = $1::uuid`, familyID)
}

// CountFamilies counts every family.
func (s *Service) CountFamilies(ctx context.Context) (int, error) {
	return s.countRows(ctx, `SELECT count(*) FROM families`)
}

// CountMinors counts every child profile.
func (s *Service) CountMinors(ctx context.Context) (int, error) {
	return s.countRows(ctx, `SELECT count(*) FROM minors`)
}

func (s *Service) countRows(ctx context.Context, sql string, args ...any) (int, error) {
	var n int
	err := s.d.Pool.QueryRow(ctx, sql, args...).Scan(&n)
	return n, err
}
