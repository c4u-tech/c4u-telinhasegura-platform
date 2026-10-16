package parental

import (
	"context"
	"errors"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// Devices lists the family's linked devices, oldest first, leaving out
// idle-expired ones; never a token.
func (s *Service) Devices(ctx context.Context, accountID string) ([]Device, error) {
	familyID, err := familyOf(ctx, s.d.Pool, accountID)
	if err != nil {
		return nil, err
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT id::text, label, minor_id::text, linked_at, last_seen_at FROM devices
		WHERE family_id = $1::uuid AND last_seen_at > $2 ORDER BY linked_at, id`, familyID, s.now().Add(-deviceIdle))
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Device, error) {
		var d Device
		return d, r.Scan(&d.ID, &d.Label, &d.MinorID, &d.LinkedAt, &d.LastSeenAt)
	})
}

// Unlink deletes a device of the caller's family; its token fails from the
// next request on.
func (s *Service) Unlink(ctx context.Context, accountID, deviceID string) error {
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		familyID, err := lockStanding(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !validID(deviceID) {
			return ErrNotFound
		}
		tag, err := tx.Exec(ctx, `DELETE FROM devices WHERE id = $1::uuid AND family_id = $2::uuid`, deviceID, familyID)
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
	s.d.Audit.Record(ctx, accountID, audit.DeviceUnlinked)
	return nil
}

// Profiles is a linked device's profile picker, behind the PIN.
func (s *Service) Profiles(ctx context.Context, p Principal, pin string) ([]Profile, error) {
	if p.DeviceID == "" {
		return nil, ErrNotFound // a locked session picks in the guardian area
	}
	if err := s.checkPIN(ctx, p.FamilyID, "", pin); err != nil {
		return nil, err
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT id::text, nickname, avatar, age_band FROM minors
		WHERE family_id = $1::uuid ORDER BY created_at, id`, p.FamilyID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Profile, error) {
		var pr Profile
		return pr, r.Scan(&pr.ID, &pr.Nickname, &pr.Avatar, &pr.AgeBand)
	})
}

// SwitchProfile re-binds a linked device to another child of its family,
// behind the PIN. The PIN is checked first, so a wrong PIN counts
// whatever the minor; a foreign minor after the right PIN counts nothing.
func (s *Service) SwitchProfile(ctx context.Context, p Principal, pin, minorID string) (Profile, error) {
	if p.DeviceID == "" {
		return Profile{}, ErrNotFound
	}
	if err := s.checkPIN(ctx, p.FamilyID, "", pin); err != nil {
		return Profile{}, err
	}
	if !validID(minorID) {
		return Profile{}, ErrNotFound
	}
	var pr Profile
	err := s.d.Pool.QueryRow(ctx, `UPDATE devices d SET minor_id = m.id FROM minors m
		WHERE d.id = $1::uuid AND m.id = $2::uuid AND m.family_id = d.family_id
		RETURNING m.id::text, m.nickname, m.avatar, m.age_band`, p.DeviceID, minorID).Scan(&pr.ID, &pr.Nickname, &pr.Avatar, &pr.AgeBand)
	if errors.Is(err, pgx.ErrNoRows) || isFKViolation(err) {
		return Profile{}, ErrNotFound // a foreign minor, or one deleted meanwhile
	}
	if err != nil {
		return Profile{}, err
	}
	s.d.Audit.Record(ctx, "", audit.DeviceProfileChanged)
	return pr, nil
}
