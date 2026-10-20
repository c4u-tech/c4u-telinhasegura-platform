package identity_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestSignUpCreatesAnUnverifiedAccountAndSendsAVerificationLink(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.SignUp(context.Background(), "ana@example.com", goodPassword, true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if f.verified("ana@example.com") {
		t.Fatal("new account is already verified")
	}
	if body := f.lastMail("ana@example.com").Body; !strings.Contains(body, "https://app.test/verificar-email?token=") {
		t.Fatalf("verification link missing: %q", body)
	}
	if !f.audit.Has(f.accountID("ana@example.com"), audit.SignedUp) {
		t.Fatal("signup not audited")
	}
}

func TestSignUpWithAVerifiedEmailNotifiesTheOwnerAndChangesNothing(t *testing.T) {
	f := newFixture(t)
	f.signUpVerified("ana@example.com", goodPassword)
	var before string
	_ = f.pool.QueryRow(context.Background(), `SELECT password_hash FROM accounts`).Scan(&before)

	if _, err := f.svc.SignUp(context.Background(), "ana@example.com", otherPassword, true, identity.TermsVersion); err != nil {
		t.Fatalf("existing email answered differently: %v", err)
	}
	var after string
	_ = f.pool.QueryRow(context.Background(), `SELECT password_hash FROM accounts`).Scan(&after)
	if before != after {
		t.Fatal("existing account's password changed")
	}
	if m := f.lastMail("ana@example.com"); strings.Contains(m.Body, "token=") || !strings.Contains(m.Subject, "tentou criar") {
		t.Fatalf("owner got %q / %q, want the notice without a token", m.Subject, m.Body)
	}
}

// An unverified account may hold a password an attacker chose, so a second
// signup must not verify it: it mails a reset link instead, whose
// confirmation replaces the password and ends every session.
func TestSignUpWithAnUnverifiedEmailSendsAPasswordResetLink(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	_, _ = f.svc.SignUp(ctx, "ana@example.com", otherPassword, true, identity.TermsVersion) // the attacker's
	id := f.accountID("ana@example.com")

	if _, err := f.svc.SignUp(ctx, "ana@example.com", goodPassword, true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(f.lastMail("ana@example.com").Body, "https://app.test/redefinir-senha?token=") {
		t.Fatal("no reset link for the unverified address")
	}
	if err := f.svc.ConfirmPasswordReset(ctx, f.lastToken("ana@example.com"), newPassword); err != nil {
		t.Fatal(err)
	}
	if got := f.sessions.calls; len(got) != 1 || got[0] != (revokeCall{id, ""}) {
		t.Fatalf("revocations %+v, want every session", got)
	}
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", otherPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("attacker password survived: %v", err)
	}
}

func TestSignUpValidatesDeclarationAndEmail(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if _, err := f.svc.SignUp(ctx, "ana@example.com", goodPassword, false, identity.TermsVersion); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("no adult declaration: %v", err)
	}
	for _, bad := range []string{"", "ana", "Ana <ana@example.com>", strings.Repeat("a", 250) + "@x.com"} {
		if _, err := f.svc.SignUp(ctx, bad, goodPassword, true, identity.TermsVersion); !errors.Is(err, identity.ErrValidation) {
			t.Errorf("%q: %v", bad, err)
		}
	}
	if len(f.mail.Sent) != 0 {
		t.Fatal("rejected signups sent mail")
	}
}

func TestSignUpNormalizesTheEmail(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.SignUp(context.Background(), "  Ana@Example.COM ", goodPassword, true, identity.TermsVersion); err != nil {
		t.Fatal(err)
	}
	if len(f.mail.To("ana@example.com")) != 1 {
		t.Fatal("mail not sent to the normalized address")
	}
}

func TestSignUpRejectsAWeakPasswordBeforeCreatingAnything(t *testing.T) {
	f := newFixture(t)
	_, err := f.svc.SignUp(context.Background(), "ana@example.com", "curta", true, identity.TermsVersion)
	var weak *identity.WeakPasswordError
	if !errors.As(err, &weak) {
		t.Fatalf("got %v", err)
	}
	var n int
	_ = f.pool.QueryRow(context.Background(), `SELECT count(*) FROM accounts`).Scan(&n)
	if n != 0 {
		t.Fatal("account created with a weak password")
	}
}

func TestConfirmEmailIsSingleUseAndExpires(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	_, _ = f.svc.SignUp(ctx, "ana@example.com", goodPassword, true, identity.TermsVersion)
	tok := f.lastToken("ana@example.com")

	if err := f.svc.ConfirmEmail(ctx, tok); err != nil {
		t.Fatal(err)
	}
	if !f.verified("ana@example.com") {
		t.Fatal("not verified")
	}
	if !f.audit.Has(f.accountID("ana@example.com"), audit.EmailVerified) {
		t.Fatal("verification not audited")
	}
	if err := f.svc.ConfirmEmail(ctx, tok); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("reused token: %v", err)
	}
	if err := f.svc.ConfirmEmail(ctx, "unknown"); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("unknown token: %v", err)
	}

	_, _ = f.svc.SignUp(ctx, "bia@example.com", goodPassword, true, identity.TermsVersion)
	late := f.lastToken("bia@example.com")
	f.now = f.now.Add(24*time.Hour + time.Second)
	if err := f.svc.ConfirmEmail(ctx, late); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("expired token: %v", err)
	}
}

func TestResendInvalidatesEarlierTokensAndIsSilentForUnknownEmails(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	_, _ = f.svc.SignUp(ctx, "ana@example.com", goodPassword, true, identity.TermsVersion)
	old := f.lastToken("ana@example.com")

	if err := f.svc.ResendVerification(ctx, "ana@example.com"); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ConfirmEmail(ctx, old); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("earlier token still valid: %v", err)
	}
	if err := f.svc.ResendVerification(ctx, "ghost@example.com"); err != nil {
		t.Fatalf("unknown email answered differently: %v", err)
	}
	if len(f.mail.To("ghost@example.com")) != 0 {
		t.Fatal("mail sent to an unknown address")
	}
}

func TestSignUpAnswersTheNewAccountOnly(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id, err := f.svc.SignUp(ctx, "ana@example.com", goodPassword, true, identity.TermsVersion)
	if err != nil || id == "" || id != f.accountID("ana@example.com") {
		t.Fatalf("new account: %q, %v", id, err)
	}
	// An address already taken answers alike, with no account.
	again, err := f.svc.SignUp(ctx, "ana@example.com", otherPassword, true, identity.TermsVersion)
	if err != nil || again != "" {
		t.Fatalf("taken address: %q, %v", again, err)
	}
}
