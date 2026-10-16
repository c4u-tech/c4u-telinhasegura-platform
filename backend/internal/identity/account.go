package identity

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

const resetTTL = 30 * time.Minute

// ChangePassword keeps the caller's session and ends every other.
func (s *Service) ChangePassword(ctx context.Context, accountID, sessionID, current, next string) error {
	acc, err := s.d.Store.accountByID(ctx, accountID)
	if err != nil {
		return err
	}
	if err := s.checkPassword(ctx, acc, current); err != nil {
		return err
	}
	next = NormalizePassword(next)
	if err := s.d.Policy.Check(ctx, next); err != nil {
		return err
	}
	// The policy check can take seconds; a clear_password link that lands
	// meanwhile makes this write, and so everything after it, fail.
	if err := s.d.Store.setPassword(ctx, accountID, HashPassword(next, s.d.Hash), acc.CredentialVersion); err != nil {
		return err
	}
	// A change requested with the old credential must not outlive it.
	if err := s.d.Store.invalidateTokens(ctx, accountID, purposeChange, s.d.Now()); err != nil {
		return err
	}
	if err := s.d.Sessions.RevokeAll(ctx, accountID, sessionID); err != nil {
		return err
	}
	s.d.Audit.Record(ctx, accountID, audit.PasswordChanged)
	return s.d.Mail.Send(ctx, msgPasswordChanged(acc.Email, s.d.AppBaseURL))
}

// RequestEmailChange mails a token to the new address; the account keeps
// its email until that token is confirmed. The caller enforces
// recent re-authentication; the token is stored only while the caller's
// session (sessionID) is still live.
func (s *Service) RequestEmailChange(ctx context.Context, accountID, sessionID, newEmail string) error {
	newEmail = NormalizeEmail(newEmail)
	acc, err := s.d.Store.accountByID(ctx, accountID)
	if err != nil {
		return err
	}
	if !ValidEmail(newEmail) || newEmail == acc.Email {
		return ErrValidation
	}
	if _, err := s.d.Store.accountByEmail(ctx, newEmail); err == nil {
		return s.d.Mail.Send(ctx, msgEmailInUse(newEmail, s.d.AppBaseURL))
	} else if !errors.Is(err, ErrNotFound) {
		return err
	}
	token, err := s.issueChangeToken(ctx, accountID, sessionID, newEmail, acc.CredentialVersion)
	if err != nil {
		return err
	}
	return s.d.Mail.Send(ctx, msgEmailChangeVerify(newEmail, s.link("/verificar-email", token)))
}

// issueChangeToken is issueToken for an email change, stored only if the
// credentials are still the ones the caller checked (seen) and the
// caller's session is still live.
func (s *Service) issueChangeToken(ctx context.Context, accountID, sessionID, newEmail string, seen int64) (string, error) {
	now := s.d.Now()
	if err := s.d.Store.invalidateTokens(ctx, accountID, purposeChange, now); err != nil {
		return "", err
	}
	plain, hash := secret.NewToken()
	if err := s.d.Store.insertChangeToken(ctx, hash, accountID, sessionID, newEmail, seen, now.Add(verifyTTL), now); err != nil {
		return "", err
	}
	return plain, nil
}

// emailChanged follows a change token that spendEmailToken applied.
func (s *Service) emailChanged(ctx context.Context, t emailToken, now time.Time) error {
	// Links mailed to the old address must not work any more.
	for _, p := range []tokenPurpose{purposeReset, purposeVerify} {
		if err := s.d.Store.invalidateTokens(ctx, t.AccountID, p, now); err != nil {
			return err
		}
	}
	s.d.Audit.Record(ctx, t.AccountID, audit.EmailChanged)
	return s.d.Mail.Send(ctx, msgEmailChanged(t.OldEmail, s.d.AppBaseURL))
}

func (s *Service) RequestPasswordReset(ctx context.Context, email string) error {
	acc, err := s.d.Store.accountByEmail(ctx, NormalizeEmail(email))
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	return s.sendReset(ctx, acc)
}

// sendReset mails a password-reset link. It is also the answer to a signup
// on an unverified address, so that address's owner replaces whatever
// password a squatter set.
func (s *Service) sendReset(ctx context.Context, acc Account) error {
	token, err := s.issueToken(ctx, acc.ID, purposeReset, "", resetTTL)
	if err != nil {
		return err
	}
	return s.d.Mail.Send(ctx, msgReset(acc.Email, s.link("/redefinir-senha", token)))
}

// ConfirmPasswordReset judges the new password before spending the token,
// so a weak first try does not cost the guardian their link.
func (s *Service) ConfirmPasswordReset(ctx context.Context, token, newPassword string) error {
	newPassword = NormalizePassword(newPassword)
	if err := s.d.Policy.Check(ctx, newPassword); err != nil {
		return err
	}
	now := s.d.Now()
	t, err := s.d.Store.consumeToken(ctx, secret.Hash(token), now, purposeReset)
	if err != nil {
		return err
	}
	acc, err := s.d.Store.accountByID(ctx, t.AccountID)
	if err != nil {
		return err
	}
	if err := s.d.Store.resetPassword(ctx, acc.ID, HashPassword(newPassword, s.d.Hash), now); err != nil {
		return err
	}
	if err := s.d.Store.invalidateTokens(ctx, acc.ID, purposeChange, now); err != nil {
		return err
	}
	if err := s.d.Sessions.RevokeAll(ctx, acc.ID, ""); err != nil {
		return err
	}
	s.d.Audit.Record(ctx, acc.ID, audit.PasswordReset)
	return s.d.Mail.Send(ctx, msgResetDone(acc.Email, s.d.AppBaseURL))
}
