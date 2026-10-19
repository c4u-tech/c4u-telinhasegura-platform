package identity

import (
	"context"
	"errors"
	netmail "net/mail"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

var (
	ErrValidation         = errors.New("identity: validation failed")
	ErrInvalidCredentials = errors.New("identity: invalid credentials")
	ErrInvalidToken       = errors.New("identity: invalid token")
)

// SessionRevoker ends sessions after a credential change. The session
// module implements it.
type SessionRevoker interface {
	RevokeAll(ctx context.Context, accountID, exceptSessionID string) error
}

type Deps struct {
	Store      Store
	Policy     PasswordPolicy
	Hash       HashParams
	Mail       mail.Sender
	Audit      audit.Recorder
	Sessions   SessionRevoker
	IDTokens   idtoken.Verifier
	Now        func() time.Time
	AppBaseURL string
}

type Service struct {
	d         Deps
	dummyHash string // verified against when no account matches, so timing does not reveal it
}

func NewService(d Deps) *Service {
	return &Service{d: d, dummyHash: HashPassword("timing-equalizer, never a real password", d.Hash)}
}

const (
	verifyTTL   = 24 * time.Hour
	maxEmailLen = 254
)

func NormalizeEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

// ValidEmail accepts a normalized, bare address of at most 254 bytes.
func ValidEmail(e string) bool {
	if len(e) > maxEmailLen {
		return false
	}
	a, err := netmail.ParseAddress(e)
	return err == nil && a.Name == "" && a.Address == e
}

// SignUp creates an unverified account and answers its ID. For an
// address already taken it mails the owner instead and answers "" with no
// error, so the response never tells whether the address exists.
func (s *Service) SignUp(ctx context.Context, email, password string, adultDeclaration bool, termsVersion string) (string, error) {
	email = NormalizeEmail(email)
	if !adultDeclaration || !ValidEmail(email) {
		return "", ErrValidation
	}
	if err := checkTerms(termsVersion); err != nil {
		return "", err
	}
	password = NormalizePassword(password)
	if err := s.d.Policy.Check(ctx, password); err != nil {
		return "", err
	}
	id, err := s.d.Store.createAccount(ctx, email, HashPassword(password, s.d.Hash), termsVersion, s.d.Now())
	if errors.Is(err, ErrEmailTaken) {
		return "", s.signUpExisting(ctx, email)
	}
	if err != nil {
		return "", err
	}
	s.d.Audit.Record(ctx, id, audit.SignedUp)
	return id, s.sendVerification(ctx, id, email)
}

func (s *Service) signUpExisting(ctx context.Context, email string) error {
	acc, err := s.d.Store.accountByEmail(ctx, email)
	if err != nil {
		return err
	}
	if !acc.EmailVerified {
		// Never verify on a signup link: the password on file may be a
		// squatter's. A reset link makes the mailbox owner choose it.
		return s.sendReset(ctx, acc)
	}
	return s.d.Mail.Send(ctx, msgSignUpExisting(acc.Email, s.d.AppBaseURL))
}

func (s *Service) ResendVerification(ctx context.Context, email string) error {
	acc, err := s.d.Store.accountByEmail(ctx, NormalizeEmail(email))
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	if err != nil || acc.EmailVerified {
		return err
	}
	return s.sendVerification(ctx, acc.ID, acc.Email)
}

// ConfirmEmail spends a signup-verification or email-change token.
func (s *Service) ConfirmEmail(ctx context.Context, token string) error {
	now := s.d.Now()
	t, err := s.d.Store.spendEmailToken(ctx, secret.Hash(token), now)
	if errors.Is(err, ErrEmailTaken) {
		return ErrInvalidToken // the address was claimed after the request
	}
	if err != nil {
		return err
	}
	if t.Purpose == purposeChange {
		return s.emailChanged(ctx, t, now)
	}
	if err := s.d.Store.markVerified(ctx, t.AccountID, now); err != nil {
		return err
	}
	s.d.Audit.Record(ctx, t.AccountID, audit.EmailVerified)
	return nil
}

func (s *Service) sendVerification(ctx context.Context, accountID, email string) error {
	token, err := s.issueToken(ctx, accountID, purposeVerify, "", verifyTTL)
	if err != nil {
		return err
	}
	return s.d.Mail.Send(ctx, msgVerify(email, s.link("/verificar-email", token)))
}

// issueToken invalidates earlier tokens of the purpose and stores a new
// one's digest.
func (s *Service) issueToken(ctx context.Context, accountID string, p tokenPurpose, newEmail string, ttl time.Duration) (string, error) {
	now := s.d.Now()
	if err := s.d.Store.invalidateTokens(ctx, accountID, p, now); err != nil {
		return "", err
	}
	plain, hash := secret.NewToken()
	if err := s.d.Store.insertToken(ctx, hash, accountID, p, newEmail, now.Add(ttl), now); err != nil {
		return "", err
	}
	return plain, nil
}

// link builds from the configured base only, never from a request.
func (s *Service) link(path, token string) string {
	return s.d.AppBaseURL + path + "?token=" + token
}

// ThrottledError refuses an attempt inside the account's back-off window.
type ThrottledError struct{ RetryAfter time.Duration }

func (e *ThrottledError) Error() string {
	return "identity: sign-in throttled for " + e.RetryAfter.String()
}

type AccountView struct {
	ID            string
	Email         string
	EmailVerified bool
	Status        Status // GET /v1/session carries it
	TermsAccepted bool   // the account accepted the current terms
}

func (s *Service) Account(ctx context.Context, id string) (AccountView, error) {
	a, err := s.d.Store.accountByID(ctx, id)
	if err != nil {
		return AccountView{}, err
	}
	return AccountView{ID: a.ID, Email: a.Email, EmailVerified: a.EmailVerified, Status: a.Status, TermsAccepted: a.TermsAccepted}, nil
}

// Authenticated is a password sign-in and the credential version its
// check saw.
type Authenticated struct {
	AccountID         string
	CredentialVersion int64
}

// Authenticate answers unknown emails and wrong passwords alike, and
// spends an Argon2 verification either way. The caller
// re-checks the version with CredentialStillCurrent once its session
// exists.
func (s *Service) Authenticate(ctx context.Context, email, password string) (Authenticated, error) {
	acc, err := s.d.Store.accountByEmail(ctx, NormalizeEmail(email))
	if errors.Is(err, ErrNotFound) {
		_, _ = VerifyPassword(NormalizePassword(password), s.dummyHash)
		s.d.Audit.Record(ctx, "", audit.SignInFailed)
		return Authenticated{}, ErrInvalidCredentials
	}
	if err != nil {
		return Authenticated{}, err
	}
	if err := s.checkPassword(ctx, acc, password); err != nil {
		return Authenticated{}, err
	}
	s.d.Audit.Record(ctx, acc.ID, audit.SignInSucceeded)
	return Authenticated{AccountID: acc.ID, CredentialVersion: acc.CredentialVersion}, nil
}

// CredentialStillCurrent reports whether the account's credentials are
// still the version a sign-in checked. A clear_password link revokes every
// session committed before it, in its own transaction; this read waits for
// an in-flight clear, so a session created after that is caught here.
func (s *Service) CredentialStillCurrent(ctx context.Context, accountID string, version int64) (bool, error) {
	v, err := s.d.Store.credentialVersion(ctx, accountID)
	return v == version, err
}

func (s *Service) Reauthenticate(ctx context.Context, accountID, password string) error {
	acc, err := s.d.Store.accountByID(ctx, accountID)
	if err != nil {
		return err
	}
	return s.checkPassword(ctx, acc, password)
}

// checkPassword is the one place a password is compared, so every path
// (sign-in, re-auth, password change) shares the throttle.
func (s *Service) checkPassword(ctx context.Context, acc Account, password string) error {
	now := s.d.Now()
	if now.Before(acc.BlockedUntil) {
		return &ThrottledError{RetryAfter: acc.BlockedUntil.Sub(now)}
	}
	hash := acc.PasswordHash
	if hash == "" {
		hash = s.dummyHash
	}
	ok, err := VerifyPassword(NormalizePassword(password), hash)
	if err != nil {
		return err
	}
	if !ok || acc.PasswordHash == "" {
		if err := s.d.Store.recordSignInFailure(ctx, acc.ID, now); err != nil {
			return err
		}
		s.d.Audit.Record(ctx, acc.ID, audit.SignInFailed)
		return ErrInvalidCredentials
	}
	if acc.FailedSignIns > 0 {
		return s.d.Store.resetSignInFailures(ctx, acc.ID)
	}
	return nil
}
