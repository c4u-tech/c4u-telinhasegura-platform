package totp_test

import (
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/totp"
)

// seed is base32 of "12345678901234567890", the SHA-1 seed of RFC 6238
// Appendix B.
const seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

func TestCodesMatchTheRFC6238Vectors(t *testing.T) {
	// The RFC's eight-digit values, truncated to six.
	for unix, want := range map[int64]string{
		59: "287082", 1111111109: "081804", 1111111111: "050471",
		1234567890: "005924", 2000000000: "279037", 20000000000: "353130",
	} {
		got, err := totp.Code(seed, totp.Step(time.Unix(unix, 0)))
		if err != nil || got != want {
			t.Errorf("T=%d: %q %v, want %q", unix, got, err, want)
		}
	}
}

func TestVerifyAcceptsOneStepEitherSide(t *testing.T) {
	now := time.Date(2026, 10, 7, 12, 0, 10, 0, time.UTC)
	cur := totp.Step(now)
	for d := int64(-2); d <= 2; d++ {
		code, err := totp.Code(seed, cur+d)
		if err != nil {
			t.Fatal(err)
		}
		step, ok := totp.Verify(seed, code, now)
		if want := d >= -1 && d <= 1; ok != want || ok && step != cur+d {
			t.Errorf("step %+d: ok=%v step=%d", d, ok, step)
		}
	}
}

func TestVerifyReadsACodeAsAppsShowIt(t *testing.T) {
	at := time.Unix(59, 0)
	for _, typed := range []string{"287082", "287 082", " 287082 "} {
		if _, ok := totp.Verify(seed, typed, at); !ok {
			t.Errorf("%q refused", typed)
		}
	}
	for _, bad := range []string{"", "28708", "2870820", "28708a", "２８７０８２"} {
		if _, ok := totp.Verify(seed, bad, at); ok {
			t.Errorf("%q accepted", bad)
		}
	}
	if _, ok := totp.Verify("not base32!", "287082", at); ok {
		t.Error("a malformed secret matched")
	}
}

func TestNewSecretIsTwentyRandomBytes(t *testing.T) {
	a, b := totp.NewSecret(), totp.NewSecret()
	if len(a) != 32 || a == b {
		t.Fatalf("secrets %q %q", a, b)
	}
	if _, err := totp.Code(a, 1); err != nil {
		t.Fatalf("a new secret does not decode: %v", err)
	}
}

func TestURI(t *testing.T) { // staff MFA, Contract
	want := "otpauth://totp/Telinha%20Segura:ana@example.com?secret=" + seed +
		"&issuer=Telinha%20Segura&algorithm=SHA1&digits=6&period=30"
	if got := totp.URI("Telinha Segura", "ana@example.com", seed); got != want {
		t.Fatalf("got %s", got)
	}
}
