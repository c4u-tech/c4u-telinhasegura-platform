package parental

import (
	"context"
	"errors"
	"regexp"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// querier is satisfied by both the pool and a transaction.
type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

func (s *Service) inTx(ctx context.Context, fn func(tx pgx.Tx) error) error {
	tx, err := s.d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// lockStanding returns the caller's family after taking its row lock, the
// lock every family write takes first, then re-reads the
// membership under it: a guardian removed while this request waited
// finds no family.
func lockStanding(ctx context.Context, tx pgx.Tx, accountID string) (string, error) {
	familyID, err := familyOf(ctx, tx, accountID)
	if err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `SELECT 1 FROM families WHERE id = $1::uuid FOR UPDATE`, familyID); err != nil {
		return "", err
	}
	err = tx.QueryRow(ctx, `SELECT family_id::text FROM family_members WHERE account_id = $1::uuid AND family_id = $2::uuid`,
		accountID, familyID).Scan(&familyID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNoFamily
	}
	return familyID, err
}

// familyOf reads the caller's family without a lock, for reads.
func familyOf(ctx context.Context, q querier, accountID string) (string, error) {
	var familyID string
	err := q.QueryRow(ctx, `SELECT family_id::text FROM family_members WHERE account_id = $1::uuid`, accountID).Scan(&familyID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNoFamily
	}
	return familyID, err
}

// minorOfFamily answers a malformed, unknown or foreign minor alike.
func minorOfFamily(ctx context.Context, q querier, familyID, minorID string) error {
	if !validID(minorID) {
		return ErrNotFound
	}
	var ok bool
	if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM minors WHERE id = $1::uuid AND family_id = $2::uuid)`,
		minorID, familyID).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrNotFound
	}
	return nil
}

func pinExists(ctx context.Context, q querier, familyID string) error {
	var ok bool
	if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM family_pins WHERE family_id = $1::uuid)`, familyID).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrPINNotSet
	}
	return nil
}

// profileOf reads one child of the family; none is ErrProfileGone.
func profileOf(ctx context.Context, q querier, familyID, minorID string) (Profile, error) {
	var p Profile
	err := q.QueryRow(ctx, `SELECT id::text, nickname, avatar, age_band FROM minors
		WHERE id = $1::uuid AND family_id = $2::uuid`, minorID, familyID).Scan(&p.ID, &p.Nickname, &p.Avatar, &p.AgeBand)
	if errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, ErrProfileGone
	}
	return p, err
}

var uuidRE = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// validID keeps a malformed ID away from a ::uuid cast (a 500); the caller
// answers it like an unknown ID.
func validID(v string) bool { return uuidRE.MatchString(v) }

// isFKViolation reports a foreign-key violation: a referenced row (a
// minor) deleted concurrently.
func isFKViolation(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && pg.Code == "23503"
}
