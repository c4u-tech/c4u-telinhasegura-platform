package identity

// The staff directory's reads of an account, kept to the least it needs.
// staff reaches identity only through these methods.

import (
	"context"
	"errors"
	"regexp"
	"slices"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/jackc/pgx/v5"
)

// StaffAccount is an account as the staff directory reads it: never a
// password hash, a token or a failure count.
type StaffAccount struct {
	ID            string
	Email         string
	EmailVerified bool
	CreatedAt     time.Time
	Providers     []string // "password", "google", "apple", in that order; empty, never nil
	// The suspension: SuspendedAt is zero and
	// SuspensionReason empty unless Status is StatusSuspended.
	Status           Status
	SuspendedAt      time.Time
	SuspensionReason string
}

var uuidRE = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// validUUID keeps a malformed id away from a ::uuid cast (a 500); the
// caller answers it like an unknown id.
func validUUID(v string) bool { return uuidRE.MatchString(v) }

// AccountForStaff reads one account by id. A malformed or unknown id is
// ErrNotFound.
func (s *Service) AccountForStaff(ctx context.Context, id string) (StaffAccount, error) {
	if !validUUID(id) {
		return StaffAccount{}, ErrNotFound
	}
	return s.d.Store.staffAccount(ctx, id)
}

// AccountIDByEmail is the id of the account with that email, after
// NormalizeEmail; ErrNotFound for none.
func (s *Service) AccountIDByEmail(ctx context.Context, email string) (string, error) {
	acc, err := s.d.Store.accountByEmail(ctx, NormalizeEmail(email))
	if err != nil {
		return "", err
	}
	return acc.ID, nil
}

// Emails maps each id that names an account to its email; an unknown or
// malformed id is left out. The audit log reader resolves actors and
// subjects through it.
func (s *Service) Emails(ctx context.Context, ids []string) (map[string]string, error) {
	valid := slices.DeleteFunc(slices.Clone(ids), func(id string) bool { return !validUUID(id) })
	if len(valid) == 0 {
		return map[string]string{}, nil
	}
	return s.d.Store.emails(ctx, valid)
}

// SendPasswordReset mails the account the reset link the public route
// sends: a 30-minute token that invalidates earlier ones, sent even to a
// provider-only account, which gains a password on confirmation.
// A staff support action calls it.
func (s *Service) SendPasswordReset(ctx context.Context, accountID string) error {
	if !validUUID(accountID) {
		return ErrNotFound
	}
	acc, err := s.d.Store.accountByID(ctx, accountID)
	if err != nil {
		return err
	}
	return s.sendReset(ctx, acc)
}

// CountAccounts counts every account.
func (s *Service) CountAccounts(ctx context.Context) (int, error) {
	var n int
	err := s.d.Store.Pool.QueryRow(ctx, `SELECT count(*) FROM accounts`).Scan(&n)
	return n, err
}

func (s Store) staffAccount(ctx context.Context, id string) (StaffAccount, error) {
	var a StaffAccount
	var hasPassword bool
	var status string
	var suspendedAt *time.Time
	err := s.Pool.QueryRow(ctx, `SELECT id::text, email, email_verified_at IS NOT NULL, created_at, coalesce(password_hash, '') <> '',
		status, suspended_at, coalesce(suspension_reason, '')
		FROM accounts WHERE id = $1::uuid`, id).Scan(&a.ID, &a.Email, &a.EmailVerified, &a.CreatedAt, &hasPassword,
		&status, &suspendedAt, &a.SuspensionReason)
	if errors.Is(err, pgx.ErrNoRows) {
		return StaffAccount{}, ErrNotFound
	}
	if err != nil {
		return StaffAccount{}, err
	}
	a.CreatedAt = a.CreatedAt.UTC()
	a.Status = Status(status)
	if suspendedAt != nil {
		a.SuspendedAt = suspendedAt.UTC()
	}
	rows, err := s.Pool.Query(ctx, `SELECT provider FROM external_identities WHERE account_id = $1::uuid`, id)
	if err != nil {
		return StaffAccount{}, err
	}
	linked, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return StaffAccount{}, err
	}
	a.Providers = []string{}
	if hasPassword {
		a.Providers = append(a.Providers, "password")
	}
	for _, p := range []idtoken.Provider{idtoken.Google, idtoken.Apple} {
		if slices.Contains(linked, string(p)) {
			a.Providers = append(a.Providers, string(p))
		}
	}
	return a, nil
}

func (s Store) emails(ctx context.Context, ids []string) (map[string]string, error) {
	rows, err := s.Pool.Query(ctx, `SELECT id::text, email FROM accounts WHERE id = ANY($1::uuid[])`, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var id, email string
		if err := rows.Scan(&id, &email); err != nil {
			return nil, err
		}
		out[id] = email
	}
	return out, rows.Err()
}
