// Package identity owns guardian accounts: credentials, email
// verification, sign-in, and password and email changes.
package identity

import (
	"context"
	"log/slog"
	"strings"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// NIST SP 800-63B-4: 15 minimum when the password is the only factor; the
// maximum bounds Argon2 work, well above the 64 NIST asks to accept.
const (
	MinPasswordLen = 15
	MaxPasswordLen = 128
)

type WeakPasswordError struct{ Reasons []string }

func (e *WeakPasswordError) Error() string {
	return "identity: weak password: " + strings.Join(e.Reasons, ",")
}

type BreachChecker interface {
	IsBreached(ctx context.Context, password string) (bool, error)
}

// NormalizePassword applies NFKC so the same password typed on different
// keyboards hashes alike. Every entry point normalizes before Check,
// HashPassword and VerifyPassword.
func NormalizePassword(p string) string { return norm.NFKC.String(p) }

type PasswordPolicy struct {
	Breaches BreachChecker // nil disables the check
	Log      *slog.Logger
}

// Check judges an already-normalized password. A breach check that cannot
// answer does not block: the length floor still holds.
func (p PasswordPolicy) Check(ctx context.Context, password string) error {
	switch n := utf8.RuneCountInString(password); {
	case n < MinPasswordLen:
		return &WeakPasswordError{Reasons: []string{"too_short"}}
	case n > MaxPasswordLen:
		return &WeakPasswordError{Reasons: []string{"too_long"}}
	}
	if p.Breaches == nil {
		return nil
	}
	breached, err := p.Breaches.IsBreached(ctx, password)
	if err != nil {
		p.Log.Warn("breached-password check unavailable; password accepted on length alone", "err", err)
		return nil
	}
	if breached {
		return &WeakPasswordError{Reasons: []string{"breached"}}
	}
	return nil
}
