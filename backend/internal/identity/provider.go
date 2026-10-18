package identity

import (
	"context"
	"errors"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

var (
	ErrProviderEmailUnverified = errors.New("identity: provider email missing or unverified")
	ErrIdentityConflict        = errors.New("identity: the account already has an identity of this provider")
)

const ticketTTL = 10 * time.Minute

// The ways a guardian may confirm a link.
const (
	OptionPassword      = "password"
	OptionClearPassword = "clear_password"
)

// ConfirmationRequiredError asks the guardian to confirm a signup or a
// link with the ticket it carries.
type ConfirmationRequiredError struct {
	Code    string // "signup_required" or "link_required"
	Ticket  string
	Email   string
	Options []string // link only
}

func (e *ConfirmationRequiredError) Error() string { return "identity: " + e.Code }

// ProviderSignIn signs in a linked identity. Otherwise it asks for a
// signup or a link confirmation; it never links on its own, because the
// matching account's password may be a squatter's.
func (s *Service) ProviderSignIn(ctx context.Context, p idtoken.Provider, rawToken string) (string, error) {
	c, err := s.verifyOnce(ctx, p, rawToken)
	if err != nil {
		return "", err
	}
	id, err := s.d.Store.identityAccount(ctx, p, c.Subject)
	if err == nil {
		s.d.Audit.Record(ctx, id, audit.ProviderSignInSucceeded)
		return id, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return "", err
	}
	email := NormalizeEmail(c.Email)
	if !c.EmailVerified || !ValidEmail(email) {
		return "", ErrProviderEmailUnverified
	}
	t := providerTicket{Kind: ticketSignup, Provider: p, Subject: c.Subject, Email: email, Authoritative: c.EmailAuthoritative}
	acc, err := s.d.Store.accountByEmail(ctx, email)
	if errors.Is(err, ErrNotFound) {
		return "", s.confirmationRequired(ctx, t)
	}
	if err != nil {
		return "", err
	}
	t.Kind, t.AccountID = ticketLink, acc.ID
	return "", s.confirmationRequired(ctx, t)
}

// verifyOnce verifies a provider ID token and spends it.
func (s *Service) verifyOnce(ctx context.Context, p idtoken.Provider, raw string) (idtoken.Claims, error) {
	c, err := s.d.IDTokens.Verify(ctx, p, raw)
	switch {
	case errors.Is(err, idtoken.ErrDisabled):
		return idtoken.Claims{}, ErrValidation
	case errors.Is(err, idtoken.ErrInvalid):
		return idtoken.Claims{}, ErrInvalidToken
	case err != nil:
		return idtoken.Claims{}, err
	}
	fresh, err := s.d.Store.useProviderToken(ctx, secret.Hash(raw), c.ExpiresAt, s.d.Now())
	if err != nil {
		return idtoken.Claims{}, err
	}
	if !fresh {
		return idtoken.Claims{}, ErrInvalidToken
	}
	return c, nil
}

func (s *Service) confirmationRequired(ctx context.Context, t providerTicket) error {
	now := s.d.Now()
	plain, hash := secret.NewToken()
	if err := s.d.Store.insertTicket(ctx, hash, t, now.Add(ticketTTL), now); err != nil {
		return err
	}
	e := &ConfirmationRequiredError{Code: "signup_required", Ticket: plain, Email: t.Email}
	if t.Kind == ticketLink {
		e.Code = "link_required"
		e.Options = []string{OptionPassword}
		if t.Authoritative {
			e.Options = append(e.Options, OptionClearPassword)
		}
	}
	return e
}

// ProviderSignUp spends a signup ticket once the guardian declares they
// are an adult. The account has a verified email and no
// password.
func (s *Service) ProviderSignUp(ctx context.Context, ticket string, adultDeclaration bool, termsVersion string) (string, error) {
	now := s.d.Now()
	hash := secret.Hash(ticket)
	t, err := s.d.Store.ticket(ctx, hash, ticketSignup, now)
	if err != nil {
		return "", err
	}
	if !adultDeclaration {
		return "", ErrValidation
	}
	if err := checkTerms(termsVersion); err != nil {
		return "", err
	}
	if err := s.d.Store.consumeTicket(ctx, hash, now); err != nil {
		return "", err
	}
	id, err := s.d.Store.createProviderAccount(ctx, t.Email, t.Provider, t.Subject, termsVersion, now)
	switch {
	case errors.Is(err, ErrEmailTaken):
		acc, err := s.d.Store.accountByEmail(ctx, t.Email)
		if err != nil {
			return "", err
		}
		t.Kind, t.AccountID = ticketLink, acc.ID
		return "", s.confirmationRequired(ctx, t)
	case errors.Is(err, errIdentityTaken): // the same identity signed up concurrently
		return "", ErrIdentityConflict
	case err != nil:
		return "", err
	}
	s.d.Audit.Record(ctx, id, audit.ProviderSignedUp)
	return id, nil
}

// LinkProof is how the guardian confirms a link: the account's password,
// or the choice to clear it. Exactly one is set.
type LinkProof struct {
	Password      string
	ClearPassword bool
}

// ProviderLink spends a link ticket. Every check runs before the ticket is
// spent, and the ticket is spent in the link's own transaction, so a
// rejected confirmation changes nothing.
func (s *Service) ProviderLink(ctx context.Context, ticket string, proof LinkProof) (string, error) {
	if (proof.Password != "") == proof.ClearPassword {
		return "", ErrValidation
	}
	now := s.d.Now()
	hash := secret.Hash(ticket)
	t, err := s.d.Store.ticket(ctx, hash, ticketLink, now)
	if err != nil {
		return "", err
	}
	if proof.ClearPassword && !t.Authoritative {
		return "", ErrValidation
	}
	acc, err := s.d.Store.accountByID(ctx, t.AccountID)
	if err != nil {
		return "", err
	}
	if acc.Email != t.Email {
		return "", ErrInvalidToken
	}
	if proof.Password != "" {
		if err := s.checkPassword(ctx, acc, proof.Password); err != nil {
			return "", err
		}
	}
	if has, err := s.d.Store.hasIdentity(ctx, acc.ID, t.Provider); err != nil {
		return "", err
	} else if has {
		return "", ErrIdentityConflict
	}
	if proof.ClearPassword {
		// The clear writes only on the credential version read above, so
		// a squatter's change that lands first stops it. It revokes every
		// session in its own transaction: if it fails nothing has changed
		// and the guardian can retry with the same ticket.
		err = s.d.Store.clearPasswordAndLink(ctx, hash, acc.ID, acc.CredentialVersion, t.Provider, t.Subject, now)
	} else {
		err = s.d.Store.linkIdentity(ctx, hash, acc.ID, t.Provider, t.Subject, now)
	}
	if errors.Is(err, errIdentityTaken) {
		return "", ErrIdentityConflict
	}
	if err != nil {
		return "", err
	}
	notice := msgIdentityLinked(acc.Email, providerName(t.Provider), s.d.AppBaseURL)
	if proof.ClearPassword {
		// The handler creates the guardian's new session after this.
		s.d.Audit.Record(ctx, acc.ID, audit.SessionRevoked)
		s.d.Audit.Record(ctx, acc.ID, audit.ProviderPasswordCleared)
		notice = msgPasswordClearedAndLinked(acc.Email, providerName(t.Provider), s.d.AppBaseURL)
	}
	s.d.Audit.Record(ctx, acc.ID, audit.IdentityLinked)
	return acc.ID, s.d.Mail.Send(ctx, notice)
}

// ReauthenticateWithProvider accepts a fresh ID token of an identity
// linked to this account.
func (s *Service) ReauthenticateWithProvider(ctx context.Context, accountID string, p idtoken.Provider, rawToken string) error {
	c, err := s.verifyOnce(ctx, p, rawToken)
	if err != nil {
		return err
	}
	id, err := s.d.Store.identityAccount(ctx, p, c.Subject)
	if errors.Is(err, ErrNotFound) || (err == nil && id != accountID) {
		return ErrInvalidCredentials
	}
	return err
}

func providerName(p idtoken.Provider) string {
	if p == idtoken.Apple {
		return "Apple"
	}
	return "Google"
}
