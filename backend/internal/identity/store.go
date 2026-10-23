package identity

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound   = errors.New("identity: not found")
	ErrEmailTaken = errors.New("identity: email taken")
)

// Store is the identity module's SQL. Only this package calls it.
type Store struct{ Pool *pgxpool.Pool }

type Account struct {
	ID            string
	Email         string
	PasswordHash  string // "" for accounts without a password
	EmailVerified bool
	FailedSignIns int
	BlockedUntil  time.Time // epoch when not blocked
	// CredentialVersion changes with every credential change; writes that
	// follow a check are conditional on it.
	CredentialVersion int64
	// Status is read with the account; a suspended account still signs
	// in.
	Status Status
	// TermsAccepted is whether the account accepted the current terms.
	TermsAccepted bool
}

type tokenPurpose string

const (
	purposeVerify tokenPurpose = "verify"
	purposeChange tokenPurpose = "change"
	purposeReset  tokenPurpose = "reset"
)

type emailToken struct {
	AccountID string
	Purpose   tokenPurpose
	NewEmail  string
	OldEmail  string // spendEmailToken only
}

const accountCols = `id::text, email, coalesce(password_hash, ''), email_verified_at IS NOT NULL,
	failed_sign_ins, coalesce(sign_in_blocked_until, 'epoch'::timestamptz), credential_version, status, terms_version`

func scanAccount(row pgx.Row) (Account, error) {
	var a Account
	var status string
	var terms *string
	err := row.Scan(&a.ID, &a.Email, &a.PasswordHash, &a.EmailVerified, &a.FailedSignIns, &a.BlockedUntil, &a.CredentialVersion, &status, &terms)
	if errors.Is(err, pgx.ErrNoRows) {
		return Account{}, ErrNotFound
	}
	a.Status = Status(status)
	a.TermsAccepted = terms != nil && *terms == TermsVersion
	return a, err
}

func isUniqueViolation(err error) bool {
	var pg *pgconn.PgError
	return errors.As(err, &pg) && pg.Code == "23505"
}

func (s Store) createAccount(ctx context.Context, email, hash, termsVersion string, now time.Time) (string, error) {
	var id string
	err := s.Pool.QueryRow(ctx, `INSERT INTO accounts (email, password_hash, adult_declared_at, created_at, terms_version, terms_accepted_at)
		VALUES ($1, $2, $3, $3, $4, $3) RETURNING id::text`, email, hash, now, termsVersion).Scan(&id)
	if isUniqueViolation(err) {
		return "", ErrEmailTaken
	}
	return id, err
}

func (s Store) accountByEmail(ctx context.Context, email string) (Account, error) {
	return scanAccount(s.Pool.QueryRow(ctx, `SELECT `+accountCols+` FROM accounts WHERE email = $1`, email))
}

func (s Store) accountByID(ctx context.Context, id string) (Account, error) {
	return scanAccount(s.Pool.QueryRow(ctx, `SELECT `+accountCols+` FROM accounts WHERE id = $1::uuid`, id))
}

func (s Store) markVerified(ctx context.Context, id string, now time.Time) error {
	_, err := s.Pool.Exec(ctx, `UPDATE accounts SET email_verified_at = coalesce(email_verified_at, $2) WHERE id = $1::uuid`, id, now)
	return err
}

func (s Store) insertToken(ctx context.Context, hash []byte, accountID string, p tokenPurpose, newEmail string, expires, now time.Time) error {
	var ne any
	if newEmail != "" {
		ne = newEmail
	}
	_, err := s.Pool.Exec(ctx, `INSERT INTO email_tokens (token_hash, account_id, purpose, new_email, expires_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)`, hash, accountID, string(p), ne, expires, now)
	return err
}

// invalidateTokens marks every unused token of that purpose as used.
func (s Store) invalidateTokens(ctx context.Context, accountID string, p tokenPurpose, now time.Time) error {
	_, err := s.Pool.Exec(ctx, `UPDATE email_tokens SET used_at = $3
		WHERE account_id = $1::uuid AND purpose = $2 AND used_at IS NULL`, accountID, string(p), now)
	return err
}

// deleteTokensExpiredBefore deletes every email token, used or not, that
// expired before cutoff.
func (s Store) deleteTokensExpiredBefore(ctx context.Context, cutoff time.Time) error {
	_, err := s.Pool.Exec(ctx, `DELETE FROM email_tokens WHERE expires_at < $1`, cutoff)
	return err
}

// recordSignInFailure counts a failure and sets the back-off from the
// incremented counter in one statement, so concurrent failures cannot write
// a stale, shorter block: from the 5th failure on the block doubles
// (1s, 2s, 4s, ...) up to 15 minutes. The exponent is clamped so power()
// cannot overflow.
func (s Store) recordSignInFailure(ctx context.Context, id string, now time.Time) error {
	_, err := s.Pool.Exec(ctx, `UPDATE accounts SET
		failed_sign_ins = failed_sign_ins + 1,
		sign_in_blocked_until = CASE WHEN failed_sign_ins + 1 >= 5
			THEN $2::timestamptz + LEAST(interval '1 second' * power(2, LEAST(failed_sign_ins + 1 - 5, 20)), interval '15 minutes')
			ELSE sign_in_blocked_until END
		WHERE id = $1::uuid`, id, now)
	return err
}

func (s Store) resetSignInFailures(ctx context.Context, id string) error {
	_, err := s.Pool.Exec(ctx, `UPDATE accounts SET failed_sign_ins = 0, sign_in_blocked_until = NULL WHERE id = $1::uuid`, id)
	return err
}

// consumeToken atomically spends an unused, unexpired token of one of the
// purposes; anything else is ErrInvalidToken.
func (s Store) consumeToken(ctx context.Context, hash []byte, now time.Time, purposes ...tokenPurpose) (emailToken, error) {
	ps := make([]string, len(purposes))
	for i, p := range purposes {
		ps[i] = string(p)
	}
	var t emailToken
	var purpose string
	err := s.Pool.QueryRow(ctx, `UPDATE email_tokens SET used_at = $2
		WHERE token_hash = $1 AND purpose = ANY($3) AND used_at IS NULL AND expires_at > $2
		RETURNING account_id::text, purpose, coalesce(new_email, '')`, hash, now, ps).Scan(&t.AccountID, &purpose, &t.NewEmail)
	if errors.Is(err, pgx.ErrNoRows) {
		return emailToken{}, ErrInvalidToken
	}
	t.Purpose = tokenPurpose(purpose)
	return t, err
}

// setPassword writes only if the credentials are still the ones the
// caller checked (seen); otherwise ErrInvalidCredentials.
func (s Store) setPassword(ctx context.Context, id, hash string, seen int64) error {
	tag, err := s.Pool.Exec(ctx, `UPDATE accounts SET password_hash = $2, credential_version = credential_version + 1
		WHERE id = $1::uuid AND credential_version = $3`, id, hash, seen)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInvalidCredentials
	}
	return nil
}

// resetPassword also verifies the email (the reset link proved the
// mailbox) and clears the sign-in throttle. It is unconditional: the
// mailbox is the proof.
func (s Store) resetPassword(ctx context.Context, id, hash string, now time.Time) error {
	_, err := s.Pool.Exec(ctx, `UPDATE accounts SET password_hash = $2, credential_version = credential_version + 1,
		email_verified_at = coalesce(email_verified_at, $3), failed_sign_ins = 0, sign_in_blocked_until = NULL
		WHERE id = $1::uuid`, id, hash, now)
	return err
}

// credentialVersion locks the account row for the read, so it waits for an
// in-flight clear and then sees the version that clear wrote.
func (s Store) credentialVersion(ctx context.Context, id string) (int64, error) {
	var v int64
	err := s.Pool.QueryRow(ctx, `SELECT credential_version FROM accounts WHERE id = $1::uuid FOR SHARE`, id).Scan(&v)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotFound
	}
	return v, err
}

// insertChangeToken stores an email-change token only if the credentials
// are still the ones the caller checked (seen) and the caller's session is
// still live; otherwise ErrInvalidCredentials. It locks the account, so a
// clear_password link either waits for the token and then spends it, or
// commits first and leaves a stale version here. A caller that read the
// account after the clear sees the new version, but its session was
// revoked before the clear took the lock.
func (s Store) insertChangeToken(ctx context.Context, hash []byte, accountID, sessionID, newEmail string, seen int64, expires, now time.Time) error {
	tag, err := s.Pool.Exec(ctx, `INSERT INTO email_tokens (token_hash, account_id, purpose, new_email, expires_at, created_at)
		SELECT $1, a.id, $3, $4, $5, $6 FROM accounts a WHERE a.id = $2::uuid AND a.credential_version = $7
			AND EXISTS (SELECT 1 FROM sessions WHERE id = $8::uuid AND account_id = a.id AND revoked_at IS NULL)
		FOR UPDATE OF a`,
		hash, accountID, string(purposeChange), newEmail, expires, now, seen, sessionID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInvalidCredentials
	}
	return nil
}

// spendEmailToken spends a verify or change token; a change token also
// moves the account to its address, in the same transaction. It locks the
// account before the token, as clearPasswordAndLink does, so a change
// confirmed during a clear either lands first (and the clear fails on the
// credential version) or finds its token spent. An address claimed
// meanwhile still spends the token and answers ErrEmailTaken; OldEmail is
// the address the account had.
func (s Store) spendEmailToken(ctx context.Context, hash []byte, now time.Time) (emailToken, error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return emailToken{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var t emailToken
	err = tx.QueryRow(ctx, `SELECT email FROM accounts
		WHERE id = (SELECT account_id FROM email_tokens WHERE token_hash = $1) FOR UPDATE`, hash).Scan(&t.OldEmail)
	if errors.Is(err, pgx.ErrNoRows) {
		return emailToken{}, ErrInvalidToken
	}
	if err != nil {
		return emailToken{}, err
	}
	var purpose string
	err = tx.QueryRow(ctx, `UPDATE email_tokens SET used_at = $2
		WHERE token_hash = $1 AND purpose = ANY($3) AND used_at IS NULL AND expires_at > $2
		RETURNING account_id::text, purpose, coalesce(new_email, '')`,
		hash, now, []string{string(purposeVerify), string(purposeChange)}).Scan(&t.AccountID, &purpose, &t.NewEmail)
	if errors.Is(err, pgx.ErrNoRows) {
		return emailToken{}, ErrInvalidToken
	}
	if err != nil {
		return emailToken{}, err
	}
	t.Purpose = tokenPurpose(purpose)
	if t.Purpose == purposeChange {
		// A savepoint, so a taken address still spends the token.
		sp, err := tx.Begin(ctx)
		if err != nil {
			return emailToken{}, err
		}
		_, err = sp.Exec(ctx, `UPDATE accounts SET email = $2, email_verified_at = $3, credential_version = credential_version + 1
			WHERE id = $1::uuid`, t.AccountID, t.NewEmail, now)
		switch {
		case isUniqueViolation(err):
			if err := sp.Rollback(ctx); err != nil {
				return emailToken{}, err
			}
			if err := tx.Commit(ctx); err != nil {
				return emailToken{}, err
			}
			return t, ErrEmailTaken
		case err != nil:
			return emailToken{}, err
		}
		if err := sp.Commit(ctx); err != nil {
			return emailToken{}, err
		}
	}
	return t, tx.Commit(ctx)
}

func (s Store) acceptTerms(ctx context.Context, id, termsVersion string, now time.Time) error {
	_, err := s.Pool.Exec(ctx, `UPDATE accounts SET terms_version = $2, terms_accepted_at = $3 WHERE id = $1::uuid`, id, termsVersion, now)
	return err
}
