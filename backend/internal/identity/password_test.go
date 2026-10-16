package identity_test

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"reflect"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
)

type fakeBreaches struct {
	breached map[string]bool
	err      error
	hook     func() // runs inside every check, to interleave a race
}

func (f fakeBreaches) IsBreached(_ context.Context, p string) (bool, error) {
	if f.hook != nil {
		f.hook()
	}
	return f.breached[p], f.err
}

func reasons(t *testing.T, err error) []string {
	t.Helper()
	var weak *identity.WeakPasswordError
	if !errors.As(err, &weak) {
		t.Fatalf("got %v, want *WeakPasswordError", err)
	}
	return weak.Reasons
}

func policy(b identity.BreachChecker) identity.PasswordPolicy {
	return identity.PasswordPolicy{Breaches: b, Log: slog.New(slog.DiscardHandler)}
}

func TestPolicyRejectsShortAndLongPasswords(t *testing.T) {
	p := policy(fakeBreaches{})
	if got := reasons(t, p.Check(context.Background(), strings.Repeat("a", 14))); !reflect.DeepEqual(got, []string{"too_short"}) {
		t.Fatalf("14 chars: %v", got)
	}
	if got := reasons(t, p.Check(context.Background(), strings.Repeat("a", 129))); !reflect.DeepEqual(got, []string{"too_long"}) {
		t.Fatalf("129 chars: %v", got)
	}
}

func TestPolicyCountsCodePointsNotBytes(t *testing.T) {
	fifteenAccented := strings.Repeat("é", 15) // 30 bytes, 15 code points
	if err := policy(fakeBreaches{}).Check(context.Background(), fifteenAccented); err != nil {
		t.Fatalf("15 code points rejected: %v", err)
	}
}

func TestPolicyAcceptsSpacesAndNoCompositionRules(t *testing.T) {
	if err := policy(fakeBreaches{}).Check(context.Background(), "uma frase com espaços"); err != nil {
		t.Fatalf("passphrase rejected: %v", err)
	}
}

func TestPolicyRejectsBreachedPasswords(t *testing.T) {
	pw := "correct horse battery staple"
	got := reasons(t, policy(fakeBreaches{breached: map[string]bool{pw: true}}).Check(context.Background(), pw))
	if !reflect.DeepEqual(got, []string{"breached"}) {
		t.Fatalf("got %v", got)
	}
}

func TestPolicyAcceptsWhenBreachCheckIsDownAndLogsNoPassword(t *testing.T) {
	var logs bytes.Buffer
	p := identity.PasswordPolicy{
		Breaches: fakeBreaches{err: identity.ErrBreachCheckUnavailable},
		Log:      slog.New(slog.NewTextHandler(&logs, nil)),
	}
	pw := "a perfectly long passphrase"
	if err := p.Check(context.Background(), pw); err != nil {
		t.Fatalf("unavailable check rejected the password: %v", err)
	}
	if !strings.Contains(logs.String(), "level=WARN") {
		t.Fatalf("no warning recorded: %q", logs.String())
	}
	if strings.Contains(logs.String(), pw) {
		t.Fatal("the password leaked into the log")
	}
}

func TestNormalizePasswordUsesNFKC(t *testing.T) {
	if identity.NormalizePassword("e\u0301") != "\u00e9" {
		t.Fatal("decomposed é not composed")
	}
}
