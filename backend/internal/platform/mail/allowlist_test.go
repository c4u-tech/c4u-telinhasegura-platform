package mail_test

import (
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

func TestAllowlistMatchesAddressesAndDomainsCaseInsensitively(t *testing.T) {
	a, err := mail.ParseAllowlist(" QA@Example.com , @Coding4U.tech ,")
	if err != nil {
		t.Fatal(err)
	}
	if a.Empty() {
		t.Fatal("a list with entries is empty")
	}
	for addr, want := range map[string]bool{
		"qa@example.com":        true,
		"QA@EXAMPLE.COM":        true,
		"ana@coding4u.tech":     true,
		"ana@sub.coding4u.tech": false,
		"other@example.com":     false,
		"evil@coding4u.tech.x":  false,
	} {
		if got := a.Allows(addr); got != want {
			t.Errorf("Allows(%q) = %v, want %v", addr, got, want)
		}
	}
}

func TestAnEmptyAllowlistAllowsEveryone(t *testing.T) {
	a, err := mail.ParseAllowlist("  ")
	if err != nil || !a.Empty() || !a.Allows("anyone@example.com") || !(mail.Allowlist{}).Allows("x@y.z") {
		t.Fatalf("empty list: %v %v", a, err)
	}
}

func TestParseAllowlistRejectsMalformedEntries(t *testing.T) {
	for _, v := range []string{"@", "qa", "@a@b", "Ana <ana@example.com>", "@exa mple.com", "a@@example.com"} {
		if _, err := mail.ParseAllowlist(v); err == nil {
			t.Errorf("ParseAllowlist(%q) accepted", v)
		}
	}
}
