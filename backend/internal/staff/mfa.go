package staff

// Privileged MFA: one TOTP factor per account, ten
// single-use recovery codes, and a 30-minute elevation of the session
// that passed the challenge. Every confirm and challenge runs under the
// staff_mfa row lock, as parental.checkPIN runs under the PIN's, so
// parallel guesses are counted one after another and a code or a step
// is used once.

import (
	"context"
	"crypto/rand"
	"encoding/base32"
	"errors"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/totp"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/jackc/pgx/v5"
)

const (
	ElevationWindow     = 30 * time.Minute // absolute, from the challenge
	recoveryCodeCount   = 10
	failuresBeforeBlock = 5
	mfaIssuer           = "Telinha Segura"
)

var (
	ErrNotStaff              = errors.New("staff: the account holds no platform role")
	ErrMFAUnavailable        = errors.New("staff: no MFA sealing key is configured")
	ErrMFAAlreadyEnrolled    = errors.New("staff: the account already has a confirmed factor")
	ErrMFANotPending         = errors.New("staff: no pending enrollment to confirm")
	ErrMFANotEnrolled        = errors.New("staff: the account has no confirmed factor")
	ErrMFACodeInvalid        = errors.New("staff: the code is wrong, reused or malformed")
	ErrMFAEnrollmentRequired = errors.New("staff: a confirmed factor is required")
	ErrElevationRequired     = errors.New("staff: the session has not passed the challenge")
)

// ThrottledError refuses a confirm or a challenge while the factor is
// blocked, and a lookup or a reset email over its limit.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string { return "staff: throttled" }

// MFAStatus is what the caller may know of their own factor.
type MFAStatus struct {
	Enrolled          bool
	EnrolledAt        time.Time
	RecoveryCodesLeft int
}

// Enrollment is a pending factor's secret, answered once.
type Enrollment struct{ Secret, URI string }

// Elevation is a passed confirm or challenge. RecoveryCodes is set only
// by a confirm, the one time they are shown.
type Elevation struct {
	Until             time.Time
	RecoveryCodes     []string
	RecoveryCodesLeft int
}

// MFAStatus reports whether the account has a confirmed factor and how
// many recovery codes are left; never the secret or a code.
func (s *Service) MFAStatus(ctx context.Context, accountID string) (MFAStatus, error) {
	var st MFAStatus
	var at *time.Time
	err := s.d.Pool.QueryRow(ctx, `SELECT
			(SELECT confirmed_at FROM staff_mfa WHERE account_id = $1::uuid),
			(SELECT count(*) FROM staff_recovery_codes WHERE account_id = $1::uuid AND used_at IS NULL)`,
		accountID).Scan(&at, &st.RecoveryCodesLeft)
	if err != nil {
		return MFAStatus{}, err
	}
	if at != nil {
		st.Enrolled, st.EnrolledAt = true, at.UTC()
	}
	return st, nil
}

// StartEnrollment stores a new sealed secret as the account's pending
// factor, replacing an earlier pending one, and answers the secret this
// once. A confirmed factor is never replaced: the upsert's
// WHERE leaves it and no row is written. A restart keeps the lockout
// counters, so it cannot lift a block.
func (s *Service) StartEnrollment(ctx context.Context, accountID string) (Enrollment, error) {
	if s.d.MFAKey == nil {
		return Enrollment{}, ErrMFAUnavailable
	}
	var email string
	if err := s.d.Pool.QueryRow(ctx, `SELECT email FROM accounts WHERE id = $1::uuid`, accountID).Scan(&email); err != nil {
		return Enrollment{}, err
	}
	plain := totp.NewSecret()
	sealed, err := secret.Seal(s.d.MFAKey, []byte(plain), []byte(accountID))
	if err != nil {
		return Enrollment{}, err
	}
	tag, err := s.d.Pool.Exec(ctx, `INSERT INTO staff_mfa (account_id, secret_sealed, created_at)
		VALUES ($1::uuid, $2, $3)
		ON CONFLICT (account_id) DO UPDATE SET secret_sealed = EXCLUDED.secret_sealed,
			created_at = EXCLUDED.created_at, last_step = NULL
		WHERE staff_mfa.confirmed_at IS NULL`, accountID, sealed, s.now())
	if err != nil {
		return Enrollment{}, err
	}
	if tag.RowsAffected() == 0 {
		return Enrollment{}, ErrMFAAlreadyEnrolled
	}
	return Enrollment{Secret: plain, URI: totp.URI(mfaIssuer, email, plain)}, nil
}

// ConfirmEnrollment confirms the pending factor with a valid code: it
// records the step, stores ten new recovery codes and elevates the
// session, all in one transaction.
func (s *Service) ConfirmEnrollment(ctx context.Context, accountID, sessionID, code string) (Elevation, error) {
	if s.d.MFAKey == nil {
		return Elevation{}, ErrMFAUnavailable
	}
	now := s.now()
	var out Elevation
	var outcome error // returned after the commit, never as the tx's error
	var blocked bool
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		f, ok, err := s.lockFactor(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !ok || f.confirmed {
			outcome = ErrMFANotPending
			return nil
		}
		if now.Before(f.blockedUntil) { // no verification while blocked
			outcome = &ThrottledError{RetryAfter: f.blockedUntil.Sub(now)}
			return nil
		}
		step, ok := totp.Verify(f.secret, code, now)
		if !ok {
			outcome = ErrMFACodeInvalid
			blocked, err = countFailure(ctx, tx, accountID, now)
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE staff_mfa SET confirmed_at = $2, last_step = $3, failed_attempts = 0, blocked_until = NULL
			WHERE account_id = $1::uuid`, accountID, now, step); err != nil {
			return err
		}
		if out.RecoveryCodes, err = replaceRecoveryCodes(ctx, tx, accountID, now); err != nil {
			return err
		}
		out.RecoveryCodesLeft = recoveryCodeCount
		out.Until = now.Add(ElevationWindow)
		return elevate(ctx, tx, sessionID, accountID, out.Until)
	})
	if err != nil {
		return Elevation{}, err
	}
	s.recordOutcome(ctx, accountID, outcome, blocked, audit.MFAEnrolled)
	if outcome != nil {
		return Elevation{}, outcome
	}
	return out, nil
}

// factor is a staff_mfa row read under its lock, the secret opened.
type factor struct {
	secret       string
	confirmed    bool
	lastStep     int64 // -1 before any step
	blockedUntil time.Time
}

// lockFactor reads and locks the account's factor; false when it has
// none.
func (s *Service) lockFactor(ctx context.Context, tx pgx.Tx, accountID string) (factor, bool, error) {
	var f factor
	var sealed []byte
	var confirmed *time.Time
	err := tx.QueryRow(ctx, `SELECT secret_sealed, confirmed_at, coalesce(last_step, -1),
			coalesce(blocked_until, 'epoch'::timestamptz)
		FROM staff_mfa WHERE account_id = $1::uuid FOR UPDATE`, accountID).
		Scan(&sealed, &confirmed, &f.lastStep, &f.blockedUntil)
	if errors.Is(err, pgx.ErrNoRows) {
		return factor{}, false, nil
	}
	if err != nil {
		return factor{}, false, err
	}
	plain, err := secret.Open(s.d.MFAKey, sealed, []byte(accountID))
	if err != nil {
		return factor{}, false, err
	}
	f.secret, f.confirmed = string(plain), confirmed != nil
	return f, true, nil
}

// countFailure counts a failed confirm or challenge in one statement
// and sets the block from the new count: from the 5th failure 30 s,
// doubling to 15 minutes; the exponent is clamped so power()
// cannot overflow. blocked reports a failure that started a block.
func countFailure(ctx context.Context, tx pgx.Tx, accountID string, now time.Time) (blocked bool, err error) {
	var failed int
	err = tx.QueryRow(ctx, `UPDATE staff_mfa SET
			failed_attempts = failed_attempts + 1,
			blocked_until = CASE WHEN failed_attempts + 1 >= 5
				THEN $2::timestamptz + LEAST(interval '30 seconds' * power(2, LEAST(failed_attempts + 1 - 5, 20)), interval '15 minutes')
				ELSE blocked_until END
		WHERE account_id = $1::uuid RETURNING failed_attempts`, accountID, now).Scan(&failed)
	return failed >= failuresBeforeBlock, err
}

var codeEnc = base32.StdEncoding.WithPadding(base32.NoPadding)

// newRecoveryCode is 50 random bits as ten base32 characters, shown
// XXXXX-XXXXX.
func newRecoveryCode() string {
	b := make([]byte, 7)
	_, _ = rand.Read(b) // crypto/rand.Read never fails since Go 1.24
	c := codeEnc.EncodeToString(b)[:10]
	return c[:5] + "-" + c[5:]
}

// normalizeRecoveryCode is the form a code is stored and matched under:
// upper case, no spaces or dashes.
func normalizeRecoveryCode(raw string) string {
	return strings.NewReplacer("-", "", " ", "").Replace(strings.ToUpper(raw))
}

// replaceRecoveryCodes drops every code of the account and stores ten
// new ones as digests, answering them in plain text.
func replaceRecoveryCodes(ctx context.Context, tx pgx.Tx, accountID string, now time.Time) ([]string, error) {
	if _, err := tx.Exec(ctx, `DELETE FROM staff_recovery_codes WHERE account_id = $1::uuid`, accountID); err != nil {
		return nil, err
	}
	codes := make([]string, recoveryCodeCount)
	for i := range codes {
		codes[i] = newRecoveryCode()
		if _, err := tx.Exec(ctx, `INSERT INTO staff_recovery_codes (account_id, code_hash, created_at) VALUES ($1::uuid, $2, $3)`,
			accountID, secret.Hash(normalizeRecoveryCode(codes[i])), now); err != nil {
			return nil, err
		}
	}
	return codes, nil
}

// elevate writes the elevation to a live session of the caller; a
// session revoked mid-request fails the whole transaction, so the code
// it carried is not consumed.
func elevate(ctx context.Context, tx pgx.Tx, sessionID, accountID string, until time.Time) error {
	err := session.MarkElevated(ctx, tx, sessionID, accountID, until)
	if errors.Is(err, session.ErrNotFound) {
		return session.ErrUnauthenticated
	}
	return err
}

// recordOutcome audits a committed confirm or challenge: its success
// event, or the failure and the block it started. A refusal while
// blocked or with nothing to check records nothing.
func (s *Service) recordOutcome(ctx context.Context, accountID string, outcome error, blocked bool, success audit.Event) {
	switch {
	case outcome == nil:
		s.d.Audit.Record(ctx, accountID, success)
	case errors.Is(outcome, ErrMFACodeInvalid):
		s.d.Audit.Record(ctx, accountID, audit.MFAChallengeFailed)
		if blocked {
			s.d.Audit.Record(ctx, accountID, audit.MFABlocked)
		}
	}
}

// ChallengeInput carries exactly one of a TOTP code and a recovery code.
type ChallengeInput struct{ Code, RecoveryCode string }

// Challenge elevates the session for 30 minutes on a TOTP code of a
// step later than the last one used, or on an unused recovery
// code. Failures count toward the lockout.
func (s *Service) Challenge(ctx context.Context, accountID, sessionID string, in ChallengeInput) (Elevation, error) {
	if s.d.MFAKey == nil {
		return Elevation{}, ErrMFAUnavailable
	}
	if (in.Code == "") == (in.RecoveryCode == "") {
		return Elevation{}, ErrValidation
	}
	now := s.now()
	var out Elevation
	var outcome error
	var blocked bool
	success := audit.MFAChallengeSucceeded
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		f, ok, err := s.lockFactor(ctx, tx, accountID)
		if err != nil {
			return err
		}
		if !ok || !f.confirmed {
			outcome = ErrMFANotEnrolled
			return nil
		}
		if now.Before(f.blockedUntil) {
			outcome = &ThrottledError{RetryAfter: f.blockedUntil.Sub(now)}
			return nil
		}
		passed := false
		if in.Code != "" {
			if step, ok := totp.Verify(f.secret, in.Code, now); ok && step > f.lastStep {
				passed = true
				if _, err := tx.Exec(ctx, `UPDATE staff_mfa SET last_step = $2 WHERE account_id = $1::uuid`, accountID, step); err != nil {
					return err
				}
			}
		} else {
			tag, err := tx.Exec(ctx, `UPDATE staff_recovery_codes SET used_at = $3
				WHERE account_id = $1::uuid AND code_hash = $2 AND used_at IS NULL`,
				accountID, secret.Hash(normalizeRecoveryCode(in.RecoveryCode)), now)
			if err != nil {
				return err
			}
			passed, success = tag.RowsAffected() == 1, audit.MFARecoveryCodeUsed
		}
		if !passed {
			outcome = ErrMFACodeInvalid
			blocked, err = countFailure(ctx, tx, accountID, now)
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE staff_mfa SET failed_attempts = 0, blocked_until = NULL WHERE account_id = $1::uuid`, accountID); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM staff_recovery_codes WHERE account_id = $1::uuid AND used_at IS NULL`,
			accountID).Scan(&out.RecoveryCodesLeft); err != nil {
			return err
		}
		out.Until = now.Add(ElevationWindow)
		return elevate(ctx, tx, sessionID, accountID, out.Until)
	})
	if err != nil {
		return Elevation{}, err
	}
	s.recordOutcome(ctx, accountID, outcome, blocked, success)
	if outcome != nil {
		return Elevation{}, outcome
	}
	return out, nil
}

// RegenerateRecoveryCodes replaces every recovery code of an enrolled
// account with ten new ones, answered once. The route asks for
// the elevation and a re-authentication first.
func (s *Service) RegenerateRecoveryCodes(ctx context.Context, accountID string) ([]string, error) {
	if s.d.MFAKey == nil {
		return nil, ErrMFAUnavailable
	}
	var codes []string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var one int
		err := tx.QueryRow(ctx, `SELECT 1 FROM staff_mfa WHERE account_id = $1::uuid AND confirmed_at IS NOT NULL FOR UPDATE`,
			accountID).Scan(&one)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrMFANotEnrolled
		}
		if err != nil {
			return err
		}
		codes, err = replaceRecoveryCodes(ctx, tx, accountID, s.now())
		return err
	})
	if err != nil {
		return nil, err
	}
	s.d.Audit.Record(ctx, accountID, audit.MFARecoveryCodesRegenerated)
	return codes, nil
}

// HasConfirmedFactor tells the enforcement whether the account must
// enroll or only pass the challenge.
func (s *Service) HasConfirmedFactor(ctx context.Context, accountID string) (bool, error) {
	var ok bool
	err := s.d.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM staff_mfa WHERE account_id = $1::uuid AND confirmed_at IS NOT NULL)`,
		accountID).Scan(&ok)
	return ok, err
}

// ResetMFA deletes the account's factor and recovery codes and ends the
// elevation of all its sessions, in one transaction; only the server
// command calls it, as no route resets a factor. So an
// elevated session always has a confirmed factor behind it, which the
// enforcement relies on (requireMFA in httpapi).
func (s *Service) ResetMFA(ctx context.Context, email string) (string, error) {
	id, _, _, err := s.accountByEmail(ctx, email)
	if err != nil {
		return "", err
	}
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `DELETE FROM staff_mfa WHERE account_id = $1::uuid`, id); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM staff_recovery_codes WHERE account_id = $1::uuid`, id); err != nil {
			return err
		}
		return session.ClearElevation(ctx, tx, id)
	})
	if err != nil {
		return "", err
	}
	s.d.Audit.Record(ctx, id, audit.MFAReset) // no actor: the server command
	return id, nil
}
