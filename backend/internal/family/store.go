package family

import (
	"context"
	"errors"
	"regexp"
	"time"

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

type standing struct {
	FamilyID string
	Role     Role
}

// lockFamily takes the family's row lock. Every write in this package
// takes it before touching the family's other rows, so writes to one
// family serialize and cannot deadlock.
func lockFamily(ctx context.Context, tx pgx.Tx, familyID string) error {
	_, err := tx.Exec(ctx, `SELECT 1 FROM families WHERE id = $1::uuid FOR UPDATE`, familyID)
	return err
}

// lockStanding locks the caller's family, then re-reads the caller's
// membership under that lock: a guardian removed or demoted while this
// request waited sees their new standing.
func lockStanding(ctx context.Context, tx pgx.Tx, accountID string) (standing, error) {
	var familyID string
	err := tx.QueryRow(ctx, `SELECT family_id::text FROM family_members WHERE account_id = $1::uuid`, accountID).Scan(&familyID)
	if errors.Is(err, pgx.ErrNoRows) {
		return standing{}, ErrNoFamily
	}
	if err != nil {
		return standing{}, err
	}
	if err := lockFamily(ctx, tx, familyID); err != nil {
		return standing{}, err
	}
	st := standing{FamilyID: familyID}
	err = tx.QueryRow(ctx, `SELECT role FROM family_members WHERE account_id = $1::uuid AND family_id = $2::uuid`,
		accountID, familyID).Scan(&st.Role)
	if errors.Is(err, pgx.ErrNoRows) {
		return standing{}, ErrNoFamily // removed while waiting for the lock
	}
	return st, err
}

func lockOwner(ctx context.Context, tx pgx.Tx, accountID string) (standing, error) {
	st, err := lockStanding(ctx, tx, accountID)
	if err == nil && st.Role != Owner {
		return standing{}, ErrNotOwner
	}
	return st, err
}

func accountEmail(ctx context.Context, q querier, accountID string) (email string, verified bool, err error) {
	err = q.QueryRow(ctx, `SELECT email, email_verified_at IS NOT NULL FROM accounts WHERE id = $1::uuid`,
		accountID).Scan(&email, &verified)
	return email, verified, err
}

// requireVerified returns the caller's email, or ErrEmailUnverified.
func requireVerified(ctx context.Context, q querier, accountID string) (string, error) {
	email, verified, err := accountEmail(ctx, q, accountID)
	if err != nil {
		return "", err
	}
	if !verified {
		return "", ErrEmailUnverified
	}
	return email, nil
}

// loadFamily reads the family as the caller with the given role sees it.
func loadFamily(ctx context.Context, q querier, familyID string, role Role, now time.Time) (Family, error) {
	f := Family{ID: familyID, Role: role}
	rows, err := q.Query(ctx, `SELECT m.account_id::text, a.email, m.role, m.joined_at
		FROM family_members m JOIN accounts a ON a.id = m.account_id
		WHERE m.family_id = $1::uuid ORDER BY m.role = 'owner' DESC, m.joined_at, m.account_id`, familyID)
	if err != nil {
		return Family{}, err
	}
	if f.Members, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Member, error) {
		var m Member
		return m, r.Scan(&m.AccountID, &m.Email, &m.Role, &m.JoinedAt)
	}); err != nil {
		return Family{}, err
	}
	rows, err = q.Query(ctx, `SELECT id::text, nickname, avatar, age_band, created_at, updated_at
		FROM minors WHERE family_id = $1::uuid ORDER BY created_at, id`, familyID)
	if err != nil {
		return Family{}, err
	}
	if f.Minors, err = pgx.CollectRows(rows, scanMinor); err != nil {
		return Family{}, err
	}
	rows, err = q.Query(ctx, `SELECT id::text, email, expires_at FROM family_invitations
		WHERE family_id = $1::uuid AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > $2
		ORDER BY created_at, id`, familyID, now)
	if err != nil {
		return Family{}, err
	}
	invs, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Invitation, error) {
		var i Invitation
		return i, r.Scan(&i.ID, &i.Email, &i.ExpiresAt)
	})
	if err != nil {
		return Family{}, err
	}
	f.PendingInvitations = len(invs)
	if role == Owner {
		f.Invitations = append([]Invitation{}, invs...)
	}
	return f, nil
}

func scanMinor(r pgx.CollectableRow) (Minor, error) {
	var m Minor
	return m, r.Scan(&m.ID, &m.Nickname, &m.Avatar, &m.AgeBand, &m.CreatedAt, &m.UpdatedAt)
}

var uuidRE = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// validID keeps a malformed path ID away from a ::uuid cast (a 500); the
// caller answers it like an unknown ID.
func validID(v string) bool { return uuidRE.MatchString(v) }

func isUniqueViolation(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && pg.Code == "23505"
}
