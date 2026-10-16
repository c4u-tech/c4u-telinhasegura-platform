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

const newPassword = "uma senha nova e comprida"

func TestChangePassword(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)

	if err := f.svc.ChangePassword(ctx, id, "sess-1", otherPassword, newPassword); !errors.Is(err, identity.ErrInvalidCredentials) {
		t.Fatalf("wrong current password: %v", err)
	}
	if len(f.sessions.calls) != 0 {
		t.Fatal("sessions revoked on a failed change")
	}
	var weak *identity.WeakPasswordError
	if err := f.svc.ChangePassword(ctx, id, "sess-1", goodPassword, "curta"); !errors.As(err, &weak) {
		t.Fatalf("weak new password: %v", err)
	}
	if err := f.svc.ChangePassword(ctx, id, "sess-1", goodPassword, newPassword); err != nil {
		t.Fatal(err)
	}
	if got := f.sessions.calls; len(got) != 1 || got[0] != (revokeCall{id, "sess-1"}) {
		t.Fatalf("revocations %+v, want all but sess-1", got)
	}
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", newPassword); err != nil {
		t.Fatalf("new password refused: %v", err)
	}
	if !strings.Contains(f.lastMail("ana@example.com").Subject, "foi alterada") {
		t.Fatal("no notice email")
	}
	if !f.audit.Has(id, audit.PasswordChanged) {
		t.Fatal("not audited")
	}
}

func TestEmailChangeSwitchesOnlyAfterTheNewAddressConfirms(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)

	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), " Ana.Nova@Example.com "); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", goodPassword); err != nil {
		t.Fatalf("email switched before confirmation: %v", err)
	}
	if err := f.svc.ConfirmEmail(ctx, f.lastToken("ana.nova@example.com")); err != nil {
		t.Fatal(err)
	}
	v, _ := f.svc.Account(ctx, id)
	if v.Email != "ana.nova@example.com" || !v.EmailVerified {
		t.Fatalf("view %+v", v)
	}
	if !strings.Contains(f.lastMail("ana@example.com").Subject, "e-mail da sua conta mudou") {
		t.Fatal("old address not notified")
	}
	if !f.audit.Has(id, audit.EmailChanged) {
		t.Fatal("not audited")
	}
}

func TestEmailChangeToATakenAddressNotifiesThatAddress(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	f.signUpVerified("bia@example.com", goodPassword)
	before := len(f.mail.To("bia@example.com"))

	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "bia@example.com"); err != nil {
		t.Fatalf("taken address answered differently: %v", err)
	}
	msgs := f.mail.To("bia@example.com")
	if len(msgs) != before+1 || strings.Contains(msgs[len(msgs)-1].Body, "token=") {
		t.Fatal("taken address got a token, or nothing")
	}
	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "ana@example.com"); !errors.Is(err, identity.ErrValidation) {
		t.Fatalf("same address: %v", err)
	}
}

func TestPasswordResetFlow(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)

	if err := f.svc.RequestPasswordReset(ctx, "ghost@example.com"); err != nil {
		t.Fatalf("unknown email answered differently: %v", err)
	}
	if len(f.mail.To("ghost@example.com")) != 0 {
		t.Fatal("mail sent to an unknown address")
	}

	_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
	first := f.lastToken("ana@example.com")
	_ = f.svc.RequestPasswordReset(ctx, "ANA@example.com")
	body := f.lastMail("ana@example.com").Body
	if !strings.Contains(body, "https://app.test/redefinir-senha?token=") {
		t.Fatalf("link not built from APP_BASE_URL: %q", body)
	}
	tok := f.lastToken("ana@example.com")
	if err := f.svc.ConfirmPasswordReset(ctx, first, newPassword); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("superseded token: %v", err)
	}

	if err := f.svc.ConfirmPasswordReset(ctx, tok, newPassword); err != nil {
		t.Fatal(err)
	}
	if got := f.sessions.calls; len(got) != 1 || got[0] != (revokeCall{id, ""}) {
		t.Fatalf("revocations %+v, want every session", got)
	}
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", newPassword); err != nil {
		t.Fatalf("new password refused: %v", err)
	}
	if !strings.Contains(f.lastMail("ana@example.com").Subject, "senha foi redefinida") || !f.audit.Has(id, audit.PasswordReset) {
		t.Fatal("no notice or no audit")
	}
	if err := f.svc.ConfirmPasswordReset(ctx, tok, newPassword); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("reused token: %v", err)
	}
}

func TestResetTokenExpiresAfter30Minutes(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.signUpVerified("ana@example.com", goodPassword)
	_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
	tok := f.lastToken("ana@example.com")
	f.now = f.now.Add(30*time.Minute + time.Second)
	if err := f.svc.ConfirmPasswordReset(ctx, tok, newPassword); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("expired token: %v", err)
	}
}

func TestResetWithAWeakPasswordKeepsTheToken(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.signUpVerified("ana@example.com", goodPassword)
	_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
	tok := f.lastToken("ana@example.com")

	var weak *identity.WeakPasswordError
	if err := f.svc.ConfirmPasswordReset(ctx, tok, "curta"); !errors.As(err, &weak) {
		t.Fatalf("weak password: %v", err)
	}
	if err := f.svc.ConfirmPasswordReset(ctx, tok, newPassword); err != nil {
		t.Fatalf("token spent by the weak attempt: %v", err)
	}
}

func TestResetVerifiesTheEmailAndLiftsTheThrottle(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	_ = f.svc.SignUp(ctx, "ana@example.com", goodPassword, true) // unverified
	for range 6 {
		_, _ = f.svc.Authenticate(ctx, "ana@example.com", otherPassword)
	}
	_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
	if err := f.svc.ConfirmPasswordReset(ctx, f.lastToken("ana@example.com"), newPassword); err != nil {
		t.Fatal(err)
	}
	if !f.verified("ana@example.com") {
		t.Fatal("reset did not verify the email it was delivered to")
	}
	if _, err := f.svc.Authenticate(ctx, "ana@example.com", newPassword); err != nil {
		t.Fatalf("throttle survived the reset: %v", err)
	}
}

func TestPasswordResetCancelsAPendingEmailChange(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	_ = f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "attacker@example.com")
	change := f.lastToken("attacker@example.com")
	_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
	if err := f.svc.ConfirmPasswordReset(ctx, f.lastToken("ana@example.com"), newPassword); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ConfirmEmail(ctx, change); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("change token survived the reset: %v", err)
	}
	if v, _ := f.svc.Account(ctx, id); v.Email != "ana@example.com" {
		t.Fatalf("email changed to %s", v.Email)
	}
}

func TestPasswordChangeCancelsAPendingEmailChange(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	_ = f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "attacker@example.com")
	change := f.lastToken("attacker@example.com")
	if err := f.svc.ChangePassword(ctx, id, "sess-1", goodPassword, newPassword); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ConfirmEmail(ctx, change); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("change token survived the password change: %v", err)
	}
	if v, _ := f.svc.Account(ctx, id); v.Email != "ana@example.com" {
		t.Fatalf("email changed to %s", v.Email)
	}
}

func TestEmailChangeCancelsResetTokensSentToTheOldAddress(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	id := f.signUpVerified("ana@example.com", goodPassword)
	_ = f.svc.RequestPasswordReset(ctx, "ana@example.com")
	oldReset := f.lastToken("ana@example.com")
	_ = f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "nova@example.com")
	if err := f.svc.ConfirmEmail(ctx, f.lastToken("nova@example.com")); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ConfirmPasswordReset(ctx, oldReset, newPassword); !errors.Is(err, identity.ErrInvalidToken) {
		t.Fatalf("reset token to the old address survived: %v", err)
	}
}

func TestTokenMailsExpireWithTheirLink(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if err := f.svc.SignUp(ctx, "ana@example.com", goodPassword, true); err != nil {
		t.Fatal(err)
	}
	if got := f.lastMail("ana@example.com").TTL; got != 24*time.Hour {
		t.Errorf("verification TTL %s, want 24h", got)
	}
	if err := f.svc.RequestPasswordReset(ctx, "ana@example.com"); err != nil {
		t.Fatal(err)
	}
	if got := f.lastMail("ana@example.com").TTL; got != 30*time.Minute {
		t.Errorf("reset TTL %s, want 30m", got)
	}
	id := f.signUpVerified("bia@example.com", goodPassword)
	if err := f.svc.RequestEmailChange(ctx, id, f.liveSession(id), "bia.nova@example.com"); err != nil {
		t.Fatal(err)
	}
	if got := f.lastMail("bia.nova@example.com").TTL; got != 24*time.Hour {
		t.Errorf("email-change TTL %s, want 24h", got)
	}
	// A notice without a link keeps the default (zero).
	if err := f.svc.SignUp(ctx, "bia@example.com", goodPassword, true); err != nil {
		t.Fatal(err)
	}
	if got := f.lastMail("bia@example.com").TTL; got != 0 {
		t.Errorf("notice TTL %s, want 0 (the default)", got)
	}
}
