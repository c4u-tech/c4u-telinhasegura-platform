package parental

// The staff directory's reads and one write of a family's devices
// (Scope). A device's label is typed by a guardian
// and often names the child, so it never leaves through here.

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// FamilyDevice is a linked device as staff see it: no label, no child.
type FamilyDevice struct {
	ID         string
	LinkedAt   time.Time
	LastSeenAt time.Time
}

// FamilyDevices lists the family's devices seen within 180 days, oldest
// link first, as Devices does for a guardian; none is an empty list.
func (s *Service) FamilyDevices(ctx context.Context, familyID string) ([]FamilyDevice, error) {
	if !validID(familyID) {
		return []FamilyDevice{}, nil
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT id::text, linked_at, last_seen_at FROM devices
		WHERE family_id = $1::uuid AND last_seen_at > $2 ORDER BY linked_at, id`, familyID, s.now().Add(-deviceIdle))
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (FamilyDevice, error) {
		var d FamilyDevice
		err := r.Scan(&d.ID, &d.LinkedAt, &d.LastSeenAt)
		d.LinkedAt, d.LastSeenAt = d.LinkedAt.UTC(), d.LastSeenAt.UTC()
		return d, err
	})
}

// UnlinkInFamily deletes a device of familyID under the family's row
// lock, the lock every family write takes first; its token
// fails from the next request on. A malformed, unknown or foreign device
// is ErrNotFound. A staff support action calls it and records its own
// audit action, so no guardian event is written here.
func (s *Service) UnlinkInFamily(ctx context.Context, familyID, deviceID string) error {
	if !validID(familyID) || !validID(deviceID) {
		return ErrNotFound
	}
	return s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT 1 FROM families WHERE id = $1::uuid FOR UPDATE`, familyID); err != nil {
			return err
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
}

// CountActiveDevices counts the devices seen within 180 days.
func (s *Service) CountActiveDevices(ctx context.Context) (int, error) {
	var n int
	err := s.d.Pool.QueryRow(ctx, `SELECT count(*) FROM devices WHERE last_seen_at > $1`, s.now().Add(-deviceIdle)).Scan(&n)
	return n, err
}
