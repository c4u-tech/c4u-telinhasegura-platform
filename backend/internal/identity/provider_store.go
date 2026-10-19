package identity

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

// errIdentityTaken is a unique violation on external_identities: the
// (provider, subject) or the account's slot for that provider is taken.
var errIdentityTaken = errors.New("identity: external identity taken")

type ticketKind string

const (
	ticketSignup ticketKind = "signup"
	ticketLink   ticketKind = "link"
)

type providerTicket struct {
	Kind          ticketKind
	Provider      idtoken.Provider
	Subject       string
	Email         string
	Authoritative bool
	AccountID     string // link tickets only
}

// useProviderToken records an accepted ID token's digest until it
// expires. It reports false if the token was already used.
func (s Store) useProviderToken(ctx context.Context, hash []byte, expires, now time.Time) (bool, error) {
	if _, err := s.Pool.Exec(ctx, `DELETE FROM used_provider_tokens WHERE expires_at <= $1`, now); err != nil {
		return false, err
	}
	tag, err := s.Pool.Exec(ctx, `INSERT INTO used_provider_tokens (token_hash, expires_at) VALUES ($1, $2)
		ON CONFLICT DO NOTHING`, hash, expires)
	return tag.RowsAffected() == 1, err
}

func (s Store) identityAccount(ctx context.Context, p idtoken.Provider, subject string) (string, error) {
	var id string
	err := s.Pool.QueryRow(ctx, `SELECT account_id::text FROM external_identities WHERE provider = $1 AND subject = $2`,
		string(p), subject).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return id, err
}

func (s Store) hasIdentity(ctx context.Context, accountID string, p idtoken.Provider) (bool, error) {
	var has bool
	err := s.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM external_identities WHERE account_id = $1::uuid AND provider = $2)`,
		accountID, string(p)).Scan(&has)
	return has, err
}

func (s Store) insertTicket(ctx context.Context, hash []byte, t providerTicket, expires, now time.Time) error {
	if _, err := s.Pool.Exec(ctx, `DELETE FROM provider_tickets WHERE expires_at <= $1`, now); err != nil {
		return err
	}
	var account any
	if t.AccountID != "" {
		account = t.AccountID
	}
	_, err := s.Pool.Exec(ctx, `INSERT INTO provider_tickets
		(ticket_hash, kind, provider, subject, email, email_authoritative, account_id, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		hash, string(t.Kind), string(t.Provider), t.Subject, t.Email, t.Authoritative, account, expires)
	return err
}

// ticket reads an unused, unexpired ticket of the kind without spending
// it, so a rejected confirmation keeps it.
func (s Store) ticket(ctx context.Context, hash []byte, kind ticketKind, now time.Time) (providerTicket, error) {
	var t providerTicket
	var k, p string
	err := s.Pool.QueryRow(ctx, `SELECT kind, provider, subject, email, email_authoritative, coalesce(account_id::text, '')
		FROM provider_tickets WHERE ticket_hash = $1 AND kind = $2 AND used_at IS NULL AND expires_at > $3`,
		hash, string(kind), now).Scan(&k, &p, &t.Subject, &t.Email, &t.Authoritative, &t.AccountID)
	if errors.Is(err, pgx.ErrNoRows) {
		return providerTicket{}, ErrInvalidToken
	}
	t.Kind, t.Provider = ticketKind(k), idtoken.Provider(p)
	return t, err
}

// consumeTicket spends a ticket; losing a race to another confirmation is
// ErrInvalidToken.
func consumeTicket(ctx context.Context, db execer, hash []byte, now time.Time) error {
	tag, err := db.Exec(ctx, `UPDATE provider_tickets SET used_at = $2
		WHERE ticket_hash = $1 AND used_at IS NULL AND expires_at > $2`, hash, now)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInvalidToken
	}
	return nil
}

func (s Store) consumeTicket(ctx context.Context, hash []byte, now time.Time) error {
	return consumeTicket(ctx, s.Pool, hash, now)
}

// createProviderAccount creates a verified account without a password and
// its identity in one transaction.
func (s Store) createProviderAccount(ctx context.Context, email string, p idtoken.Provider, subject, termsVersion string, now time.Time) (string, error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var id string
	err = tx.QueryRow(ctx, `INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at, terms_version, terms_accepted_at)
		VALUES ($1, $2, $2, $2, $3, $2) RETURNING id::text`, email, now, termsVersion).Scan(&id)
	if isUniqueViolation(err) {
		return "", ErrEmailTaken
	}
	if err != nil {
		return "", err
	}
	if err := insertIdentity(ctx, tx, id, p, subject, now); err != nil {
		return "", err
	}
	return id, tx.Commit(ctx)
}

// linkIdentity spends the link ticket and links the identity in one
// transaction, so losing the identity race keeps the ticket.
func (s Store) linkIdentity(ctx context.Context, ticketHash []byte, accountID string, p idtoken.Provider, subject string, now time.Time) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := consumeTicket(ctx, tx, ticketHash, now); err != nil {
		return err
	}
	if err := insertIdentity(ctx, tx, accountID, p, subject, now); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// clearPasswordAndLink evicts whoever set the account's password: it
// removes the password and every pending email token, marks the email
// verified (the provider proved the mailbox), clears the throttle, links
// the identity and spends the ticket, all in one transaction.
// It locks the account first and writes only if the credentials are still
// the ones the caller checked (seen); otherwise ErrInvalidToken, and the
// ticket is kept.
func (s Store) clearPasswordAndLink(ctx context.Context, ticketHash []byte, accountID string, seen int64, p idtoken.Provider, subject string, now time.Time) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	tag, err := tx.Exec(ctx, `UPDATE accounts SET password_hash = NULL, credential_version = credential_version + 1,
		email_verified_at = coalesce(email_verified_at, $2), failed_sign_ins = 0, sign_in_blocked_until = NULL
		WHERE id = $1::uuid AND credential_version = $3`, accountID, now, seen)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInvalidToken
	}
	if _, err := tx.Exec(ctx, `UPDATE email_tokens SET used_at = $2 WHERE account_id = $1::uuid AND used_at IS NULL`,
		accountID, now); err != nil {
		return err
	}
	// The eviction revokes the sessions in the transaction that bumps the
	// version: a session committed before this is revoked here, and one
	// committed after it fails its re-check (credentialVersion waits on
	// this row lock and then sees the new version).
	if _, err := tx.Exec(ctx, `UPDATE sessions SET revoked_at = $2 WHERE account_id = $1::uuid AND revoked_at IS NULL`,
		accountID, now); err != nil {
		return err
	}
	if err := consumeTicket(ctx, tx, ticketHash, now); err != nil {
		return err
	}
	if err := insertIdentity(ctx, tx, accountID, p, subject, now); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

type execer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

func insertIdentity(ctx context.Context, db execer, accountID string, p idtoken.Provider, subject string, now time.Time) error {
	_, err := db.Exec(ctx, `INSERT INTO external_identities (provider, subject, account_id, created_at)
		VALUES ($1, $2, $3::uuid, $4)`, string(p), subject, accountID, now)
	if isUniqueViolation(err) {
		return errIdentityTaken
	}
	return err
}
