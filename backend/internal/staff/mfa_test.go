package staff_test

import (
	"bytes"
	"errors"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/totp"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

var recoveryRE = regexp.MustCompile(`^[A-Z2-7]{5}-[A-Z2-7]{5}$`)

func TestEnrollmentStoresASealedPendingFactor(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	e, err := f.svc.StartEnrollment(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	wantURI := "otpauth://totp/Telinha%20Segura:ana@example.com?secret=" + e.Secret +
		"&issuer=Telinha%20Segura&algorithm=SHA1&digits=6&period=30"
	if len(e.Secret) != 32 || e.URI != wantURI {
		t.Fatalf("enrollment %+v", e)
	}
	var sealed []byte
	var confirmed *time.Time
	if err := f.pool.QueryRow(ctx, `SELECT secret_sealed, confirmed_at FROM staff_mfa WHERE account_id = $1::uuid`, ana).
		Scan(&sealed, &confirmed); err != nil {
		t.Fatal(err)
	}
	if confirmed != nil || bytes.Contains(sealed, []byte(e.Secret)) {
		t.Fatalf("pending factor: confirmed=%v, the secret shows in the row", confirmed)
	}
	if plain, err := secret.Open(mfaKey, sealed, []byte(ana)); err != nil || string(plain) != e.Secret {
		t.Fatalf("the row does not open to the secret: %v", err)
	}

	again, err := f.svc.StartEnrollment(ctx, ana)
	if err != nil || again.Secret == e.Secret || f.count(`SELECT count(*) FROM staff_mfa`) != 1 {
		t.Fatalf("a restart must replace the pending secret: %v", err)
	}
	if _, err := f.svc.ConfirmEnrollment(ctx, ana, f.session(ana), f.code(again.Secret)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.StartEnrollment(ctx, ana); !errors.Is(err, staff.ErrMFAAlreadyEnrolled) {
		t.Fatalf("enrolling over a confirmed factor: %v", err)
	}
	var after []byte
	if err := f.pool.QueryRow(ctx, `SELECT secret_sealed FROM staff_mfa WHERE account_id = $1::uuid`, ana).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if plain, _ := secret.Open(mfaKey, after, []byte(ana)); string(plain) != again.Secret {
		t.Fatal("a refused enrollment changed the confirmed secret")
	}
}

func TestConfirmElevatesAndHandsTenRecoveryCodesOnce(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	if _, err := f.svc.ConfirmEnrollment(ctx, ana, sess, "123456"); !errors.Is(err, staff.ErrMFANotPending) {
		t.Fatalf("confirm with nothing pending: %v", err)
	}
	e, err := f.svc.StartEnrollment(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.ConfirmEnrollment(ctx, ana, sess, f.wrongCode(e.Secret)); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatalf("a wrong code: %v", err)
	}
	if !f.audit.Has(ana, audit.MFAChallengeFailed) || f.count(`SELECT failed_attempts FROM staff_mfa`) != 1 {
		t.Fatal("a wrong confirm code must be counted and audited")
	}

	el, err := f.svc.ConfirmEnrollment(ctx, ana, sess, f.code(e.Secret))
	if err != nil {
		t.Fatal(err)
	}
	if want := f.now.Add(30 * time.Minute); !el.Until.Equal(want) || !f.elevatedUntil(sess).Equal(want) {
		t.Fatalf("elevation %v, session %v", el.Until, f.elevatedUntil(sess))
	}
	if len(el.RecoveryCodes) != 10 || el.RecoveryCodesLeft != 10 {
		t.Fatalf("codes %v left %d", el.RecoveryCodes, el.RecoveryCodesLeft)
	}
	seen := map[string]bool{}
	for _, c := range el.RecoveryCodes {
		if !recoveryRE.MatchString(c) || seen[c] {
			t.Fatalf("recovery code %q (repeat %v)", c, seen[c])
		}
		seen[c] = true
		if n := f.count(`SELECT count(*) FROM staff_recovery_codes WHERE account_id = $1::uuid AND code_hash = $2`,
			ana, secret.Hash(strings.ReplaceAll(c, "-", ""))); n != 1 {
			t.Fatalf("%q is not stored as its digest", c)
		}
	}
	if n := f.count(`SELECT count(*) FROM staff_mfa WHERE confirmed_at = $1 AND failed_attempts = 0 AND last_step IS NOT NULL`, f.now); n != 1 {
		t.Fatal("the factor is not confirmed with its step and a clean count")
	}
	if !f.audit.Has(ana, audit.MFAEnrolled) {
		t.Fatal("no mfa_enrolled")
	}
	st, err := f.svc.MFAStatus(ctx, ana)
	if err != nil || !st.Enrolled || !st.EnrolledAt.Equal(f.now) || st.RecoveryCodesLeft != 10 {
		t.Fatalf("status %+v %v", st, err)
	}
	if _, err := f.svc.ConfirmEnrollment(ctx, ana, sess, f.code(e.Secret)); !errors.Is(err, staff.ErrMFANotPending) {
		t.Fatalf("a second confirm: %v", err)
	}
	if st, err := f.svc.MFAStatus(ctx, f.account("bia@example.com")); err != nil || st.Enrolled || st.RecoveryCodesLeft != 0 {
		t.Fatalf("status of an account with no factor: %+v %v", st, err)
	}
}

func TestRestartingAnEnrollmentKeepsTheLockout(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	e, err := f.svc.StartEnrollment(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	for i := range 5 {
		if _, err := f.svc.ConfirmEnrollment(ctx, ana, sess, f.wrongCode(e.Secret)); !errors.Is(err, staff.ErrMFACodeInvalid) {
			t.Fatalf("failure %d: %v", i+1, err)
		}
	}
	if !f.audit.Has(ana, audit.MFABlocked) {
		t.Fatal("the 5th failure must audit mfa_blocked")
	}
	e, err = f.svc.StartEnrollment(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	var th *staff.ThrottledError
	if _, err := f.svc.ConfirmEnrollment(ctx, ana, sess, f.code(e.Secret)); !errors.As(err, &th) || th.RetryAfter != 30*time.Second {
		t.Fatalf("a restarted enrollment lifted the block: %v", err)
	}
}

// enrolled gives accountID a confirmed factor through sessionID, which
// it elevates, and returns the secret and the recovery codes. The clock
// moves one step on, so the next code is not the confirm's.
func (f *fixture) enrolled(accountID, sessionID string) (string, []string) {
	f.t.Helper()
	e, err := f.svc.StartEnrollment(ctx, accountID)
	if err != nil {
		f.t.Fatal(err)
	}
	el, err := f.svc.ConfirmEnrollment(ctx, accountID, sessionID, f.code(e.Secret))
	if err != nil {
		f.t.Fatal(err)
	}
	f.now = f.now.Add(totp.Period)
	return e.Secret, el.RecoveryCodes
}

func TestChallengeElevatesOnceForEachStep(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{Code: "123456"}); !errors.Is(err, staff.ErrMFANotEnrolled) {
		t.Fatalf("a challenge with no factor: %v", err)
	}
	for _, in := range []staff.ChallengeInput{{}, {Code: "123456", RecoveryCode: "AAAAA-AAAAA"}} {
		if _, err := f.svc.Challenge(ctx, ana, sess, in); !errors.Is(err, staff.ErrValidation) {
			t.Fatalf("%+v: %v", in, err)
		}
	}
	sec, _ := f.enrolled(ana, sess)
	other := f.session(ana)
	code := f.code(sec)
	el, err := f.svc.Challenge(ctx, ana, other, staff.ChallengeInput{Code: code})
	if want := f.now.Add(30 * time.Minute); err != nil || !el.Until.Equal(want) || !f.elevatedUntil(other).Equal(want) || el.RecoveryCodesLeft != 10 {
		t.Fatalf("challenge %+v %v", el, err)
	}
	if !f.audit.Has(ana, audit.MFAChallengeSucceeded) {
		t.Fatal("no mfa_challenge_succeeded")
	}
	if _, err := f.svc.Challenge(ctx, ana, other, staff.ChallengeInput{Code: code}); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatalf("a replayed code: %v", err)
	}
	prev, _ := totp.Code(sec, totp.Step(f.now)-1) // the confirm's step: in the window, not later
	if _, err := f.svc.Challenge(ctx, ana, other, staff.ChallengeInput{Code: prev}); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatalf("an earlier step: %v", err)
	}
	f.now = f.now.Add(totp.Period)
	if _, err := f.svc.Challenge(ctx, ana, other, staff.ChallengeInput{Code: f.code(sec)}); err != nil {
		t.Fatalf("the next step: %v", err)
	}
	if f.count(`SELECT failed_attempts FROM staff_mfa`) != 0 {
		t.Fatal("a success must reset the failure count")
	}
}

func TestARecoveryCodeElevatesOnce(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	_, codes := f.enrolled(ana, sess)
	typed := strings.ToLower(strings.ReplaceAll(codes[3], "-", " "))
	el, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{RecoveryCode: typed})
	if err != nil || el.RecoveryCodesLeft != 9 {
		t.Fatalf("recovery code %q: %+v %v", typed, el, err)
	}
	if !f.audit.Has(ana, audit.MFARecoveryCodeUsed) {
		t.Fatal("no mfa_recovery_code_used")
	}
	if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{RecoveryCode: codes[3]}); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatalf("a used code: %v", err)
	}
	if st, _ := f.svc.MFAStatus(ctx, ana); st.RecoveryCodesLeft != 9 {
		t.Fatalf("left %d", st.RecoveryCodesLeft)
	}
}

func TestFailedChallengesBlockTheFactorWithBackoff(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	sec, _ := f.enrolled(ana, sess)
	wrong := func() error {
		_, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{RecoveryCode: "AAAAA-AAAAA"})
		return err
	}
	throttled := func(want time.Duration) {
		t.Helper()
		var th *staff.ThrottledError
		if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{Code: f.code(sec)}); !errors.As(err, &th) || th.RetryAfter != want {
			t.Fatalf("want a %v block, got %v", want, err)
		}
	}
	for i := range 4 {
		if err := wrong(); !errors.Is(err, staff.ErrMFACodeInvalid) {
			t.Fatalf("failure %d: %v", i+1, err)
		}
	}
	if f.audit.Has(ana, audit.MFABlocked) {
		t.Fatal("blocked before the 5th failure")
	}
	if err := wrong(); !errors.Is(err, staff.ErrMFACodeInvalid) || !f.audit.Has(ana, audit.MFABlocked) {
		t.Fatalf("the 5th failure: %v", err)
	}
	throttled(30 * time.Second) // even the right code, before it is checked
	f.now = f.now.Add(30 * time.Second)
	if err := wrong(); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatalf("the 6th failure: %v", err)
	}
	throttled(time.Minute)
	f.exec(`UPDATE staff_mfa SET failed_attempts = 30, blocked_until = NULL`)
	if err := wrong(); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatal(err)
	}
	throttled(15 * time.Minute)
	f.now = f.now.Add(15 * time.Minute)
	if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{Code: f.code(sec)}); err != nil {
		t.Fatalf("after the block: %v", err)
	}
	if f.count(`SELECT count(*) FROM staff_mfa WHERE failed_attempts = 0 AND blocked_until IS NULL`) != 1 {
		t.Fatal("a success must clear the count and the block")
	}
}

func TestConcurrentChallengesUseACodeOnce(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	sec, _ := f.enrolled(ana, sess)
	code := f.code(sec)
	errs := make(chan error, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Go(func() {
			_, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{Code: code})
			errs <- err
		})
	}
	wg.Wait()
	close(errs)
	ok, invalid := 0, 0
	for err := range errs {
		switch {
		case err == nil:
			ok++
		case errors.Is(err, staff.ErrMFACodeInvalid):
			invalid++
		default:
			t.Fatal(err)
		}
	}
	if ok != 1 || invalid != 1 {
		t.Fatalf("%d passed and %d refused, want one each", ok, invalid)
	}
}

func TestAChallengeOnARevokedSessionElevatesNothing(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	live := f.session(ana)
	sec, _ := f.enrolled(ana, live)
	gone := f.session(ana)
	f.exec(`UPDATE sessions SET revoked_at = $2 WHERE id = $1::uuid`, gone, f.now)
	if _, err := f.svc.Challenge(ctx, ana, gone, staff.ChallengeInput{Code: f.code(sec)}); !errors.Is(err, session.ErrUnauthenticated) {
		t.Fatalf("a revoked session: %v", err)
	}
	if !f.elevatedUntil(gone).IsZero() {
		t.Fatal("the revoked session was elevated")
	}
	if _, err := f.svc.Challenge(ctx, ana, live, staff.ChallengeInput{Code: f.code(sec)}); err != nil {
		t.Fatalf("the code must not have been consumed: %v", err)
	}
}

func TestRegenerationReplacesEveryRecoveryCode(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	_, old := f.enrolled(ana, sess)
	if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{RecoveryCode: old[0]}); err != nil {
		t.Fatal(err)
	}
	codes, err := f.svc.RegenerateRecoveryCodes(ctx, ana)
	if err != nil || len(codes) != 10 {
		t.Fatalf("codes %v %v", codes, err)
	}
	if n := f.count(`SELECT count(*) FROM staff_recovery_codes WHERE used_at IS NULL`); n != 10 || f.count(`SELECT count(*) FROM staff_recovery_codes`) != 10 {
		t.Fatalf("%d unused codes; the old ones must be gone", n)
	}
	if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{RecoveryCode: old[1]}); !errors.Is(err, staff.ErrMFACodeInvalid) {
		t.Fatalf("an old code: %v", err)
	}
	if _, err := f.svc.Challenge(ctx, ana, sess, staff.ChallengeInput{RecoveryCode: codes[0]}); err != nil {
		t.Fatalf("a new code: %v", err)
	}
	if !f.audit.Has(ana, audit.MFARecoveryCodesRegenerated) {
		t.Fatal("no mfa_recovery_codes_regenerated")
	}
	if _, err := f.svc.RegenerateRecoveryCodes(ctx, f.account("bia@example.com")); !errors.Is(err, staff.ErrMFANotEnrolled) {
		t.Fatalf("no factor: %v", err)
	}
}

func TestResetDeletesTheFactorAndEndsEveryElevation(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	s1, s2 := f.session(ana), f.session(ana)
	sec, _ := f.enrolled(ana, s1)
	if _, err := f.svc.Challenge(ctx, ana, s2, staff.ChallengeInput{Code: f.code(sec)}); err != nil {
		t.Fatal(err)
	}
	bia := f.account("bia@example.com")
	bs := f.session(bia)
	f.enrolled(bia, bs)
	if ok, err := f.svc.HasConfirmedFactor(ctx, ana); err != nil || !ok {
		t.Fatalf("before the reset: %v %v", ok, err)
	}

	id, err := f.svc.ResetMFA(ctx, " Ana@Example.com ")
	if err != nil || id != ana {
		t.Fatalf("reset: %q %v", id, err)
	}
	if f.count(`SELECT count(*) FROM staff_mfa WHERE account_id = $1::uuid`, ana) != 0 ||
		f.count(`SELECT count(*) FROM staff_recovery_codes WHERE account_id = $1::uuid`, ana) != 0 {
		t.Fatal("the factor or its codes survived the reset")
	}
	if !f.elevatedUntil(s1).IsZero() || !f.elevatedUntil(s2).IsZero() {
		t.Fatal("a session stayed elevated through the reset")
	}
	if ok, _ := f.svc.HasConfirmedFactor(ctx, ana); ok {
		t.Fatal("still a confirmed factor")
	}
	if f.elevatedUntil(bs).IsZero() || f.count(`SELECT count(*) FROM staff_mfa WHERE account_id = $1::uuid`, bia) != 1 {
		t.Fatal("the reset touched another account")
	}
	if !f.audit.Has(ana, audit.MFAReset) {
		t.Fatal("no mfa_reset")
	}
	if _, err := f.svc.ResetMFA(ctx, "nobody@example.com"); !errors.Is(err, staff.ErrAccountNotFound) {
		t.Fatalf("an unknown email: %v", err)
	}
}

func TestWithoutAKeyMFAIsUnavailable(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	sess := f.session(ana)
	noKey := staff.NewService(staff.Deps{Pool: f.pool, Audit: f.audit, Now: func() time.Time { return f.now }})
	calls := map[string]func() error{
		"start":   func() error { _, err := noKey.StartEnrollment(ctx, ana); return err },
		"confirm": func() error { _, err := noKey.ConfirmEnrollment(ctx, ana, sess, "123456"); return err },
		"challenge": func() error {
			_, err := noKey.Challenge(ctx, ana, sess, staff.ChallengeInput{Code: "123456"})
			return err
		},
		"regenerate": func() error { _, err := noKey.RegenerateRecoveryCodes(ctx, ana); return err },
	}
	for name, call := range calls {
		if err := call(); !errors.Is(err, staff.ErrMFAUnavailable) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if _, err := noKey.MFAStatus(ctx, ana); err != nil {
		t.Fatalf("status needs no key: %v", err)
	}
}
