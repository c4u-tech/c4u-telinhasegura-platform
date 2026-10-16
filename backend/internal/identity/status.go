package identity

// The account's status. The request wrapper reads
// it on every session-backed request. Only staff's suspension writes it,
// inside staff's transaction, through the package functions below,
// the way session exports MarkElevated.

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Status is an account's standing on the platform.
type Status string

const (
	StatusActive    Status = "active"
	StatusSuspended Status = "suspended"
)

// ErrStatusChanged is a status write on an account that is not in the
// status the write changes.
var ErrStatusChanged = errors.New("identity: the account is not in the status the change expects")

// Status reads the account's status with one primary-key read and no
// cache, so a suspension or a reinstatement takes effect on the next
// request. A malformed or unknown id is
// ErrNotFound.
func (s *Service) Status(ctx context.Context, accountID string) (Status, error) {
	if !validUUID(accountID) {
		return "", ErrNotFound
	}
	var st string
	err := s.d.Store.Pool.QueryRow(ctx, `SELECT status FROM accounts WHERE id = $1::uuid`, accountID).Scan(&st)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return Status(st), err
}

// LockAccount takes the account row's lock inside the caller's
// transaction and reads the status under it. Suspension, reinstatement
// and every role grant take it, so none of them interleaves with
// another. FOR NO KEY UPDATE makes a sign-in's
// FOR SHARE re-check (credentialVersion) wait for the suspension and
// then see the bumped version. A foreign-key insert
// elsewhere, which only key-shares the row, does not wait.
func LockAccount(ctx context.Context, tx pgx.Tx, accountID string) (Status, error) {
	if !validUUID(accountID) {
		return "", ErrNotFound
	}
	var st string
	err := tx.QueryRow(ctx, `SELECT status FROM accounts WHERE id = $1::uuid FOR NO KEY UPDATE`, accountID).Scan(&st)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return Status(st), err
}

// MarkSuspended suspends an active account at `at` with the staff reason,
// and bumps its credential version, so a write that rests on a check
// made before it fails. It spends the account's
// pending email-change tokens, as clearPasswordAndLink does on an
// eviction: the confirmation locks the account before its token, so one
// waiting on this row then finds its token spent. A pending reset token
// is kept, since the reset stays as it is. The caller revokes the
// sessions in the same transaction. ErrStatusChanged when the account is
// not active.
func MarkSuspended(ctx context.Context, tx pgx.Tx, accountID string, at time.Time, reason string) error {
	if !validUUID(accountID) {
		return ErrNotFound
	}
	tag, err := tx.Exec(ctx, `UPDATE accounts SET status = 'suspended', suspended_at = $2, suspension_reason = $3,
		credential_version = credential_version + 1 WHERE id = $1::uuid AND status = 'active'`, accountID, at, reason)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrStatusChanged
	}
	_, err = tx.Exec(ctx, `UPDATE email_tokens SET used_at = $2
		WHERE account_id = $1::uuid AND purpose = $3 AND used_at IS NULL`, accountID, at, string(purposeChange))
	return err
}

// MarkActive reinstates a suspended account. It moves no credential
// version and touches no session: a session the account holds reaches
// every route again on its next request. ErrStatusChanged
// when the account is not suspended.
func MarkActive(ctx context.Context, tx pgx.Tx, accountID string) error {
	if !validUUID(accountID) {
		return ErrNotFound
	}
	tag, err := tx.Exec(ctx, `UPDATE accounts SET status = 'active', suspended_at = NULL, suspension_reason = NULL
		WHERE id = $1::uuid AND status = 'suspended'`, accountID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrStatusChanged
	}
	return nil
}
