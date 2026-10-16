package family

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// CreateMinor writes the profile and its consent row in one transaction.
// policyVersion is the consent text the guardian saw.
func (s *Service) CreateMinor(ctx context.Context, accountID string, in MinorInput, policyVersion string) (Minor, error) {
	now := s.now()
	var m Minor
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := requireVerified(ctx, tx, accountID); err != nil {
			return err
		}
		st, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		// Membership first: a caller outside a family hears 404, not 422.
		in, err := in.normalized()
		if err != nil {
			return err
		}
		if policyVersion == "" {
			return ErrValidation
		}
		if policyVersion != ConsentPolicyVersion {
			return ErrPolicyOutdated
		}
		m = Minor{Nickname: in.Nickname, Avatar: in.Avatar, AgeBand: in.AgeBand, CreatedAt: now, UpdatedAt: now}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM minors WHERE family_id = $1::uuid`, st.FamilyID).Scan(&n); err != nil {
			return err
		}
		if n >= maxMinors {
			return ErrLimitReached
		}
		if err := tx.QueryRow(ctx, `INSERT INTO minors (family_id, nickname, avatar, age_band, created_at, updated_at)
			VALUES ($1::uuid, $2, $3, $4, $5, $5) RETURNING id::text`,
			st.FamilyID, m.Nickname, m.Avatar, string(m.AgeBand), now).Scan(&m.ID); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO minor_consents (minor_id, family_id, granted_by, policy_version, granted_at)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5)`, m.ID, st.FamilyID, accountID, policyVersion, now)
		return err
	})
	if err != nil {
		return Minor{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.MinorCreated)
	return m, nil
}

// UpdateMinor changes the patch's fields only, never the consent.
func (s *Service) UpdateMinor(ctx context.Context, accountID, minorID string, p MinorPatch) (Minor, error) {
	now := s.now()
	var m Minor
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(minorID) {
			return ErrNotFound
		}
		p, err := p.normalized()
		if err != nil {
			return err
		}
		var band *string
		if p.AgeBand != nil {
			b := string(*p.AgeBand)
			band = &b
		}
		rows, err := tx.Query(ctx, `UPDATE minors
			SET nickname = coalesce($3, nickname), avatar = coalesce($4, avatar), age_band = coalesce($5, age_band), updated_at = $6
			WHERE id = $1::uuid AND family_id = $2::uuid
			RETURNING id::text, nickname, avatar, age_band, created_at, updated_at`,
			minorID, st.FamilyID, p.Nickname, p.Avatar, band, now)
		if err != nil {
			return err
		}
		m, err = pgx.CollectExactlyOneRow(rows, scanMinor) // no row: unknown or foreign minor
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	})
	if err != nil {
		return Minor{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.MinorUpdated)
	return m, nil
}

// DeleteMinor hard-deletes the profile and withdraws its consent, in one
// transaction. The ledger row stays.
func (s *Service) DeleteMinor(ctx context.Context, accountID, minorID string) error {
	now := s.now()
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(minorID) {
			return ErrNotFound
		}
		tag, err := tx.Exec(ctx, `DELETE FROM minors WHERE id = $1::uuid AND family_id = $2::uuid`, minorID, st.FamilyID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		_, err = tx.Exec(ctx, `UPDATE minor_consents SET withdrawn_at = $2, withdrawn_by = $3::uuid WHERE minor_id = $1::uuid`,
			minorID, now, accountID)
		return err
	})
	if err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.MinorDeleted)
	return nil
}
