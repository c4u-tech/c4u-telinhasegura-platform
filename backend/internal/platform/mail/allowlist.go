package mail

import (
	"fmt"
	netmail "net/mail"
	"strings"
)

// Allowlist confines delivery to some recipients
// (MAIL_ALLOWED_RECIPIENTS): a staging environment never mails a real
// third party. The zero value allows everyone.
type Allowlist struct {
	addresses map[string]bool
	domains   map[string]bool
}

// ParseAllowlist reads a comma-separated list of exact addresses and
// "@domain" entries, case-insensitively. Blank entries are skipped.
func ParseAllowlist(v string) (Allowlist, error) {
	a := Allowlist{addresses: map[string]bool{}, domains: map[string]bool{}}
	for _, e := range strings.Split(v, ",") {
		e = strings.ToLower(strings.TrimSpace(e))
		switch {
		case e == "":
			continue
		case strings.HasPrefix(e, "@"):
			d := e[1:]
			if d == "" || strings.ContainsAny(d, "@ \t") {
				return Allowlist{}, fmt.Errorf("entry %q is neither an address nor @domain", e)
			}
			a.domains[d] = true
		default:
			p, err := netmail.ParseAddress(e)
			if err != nil || p.Name != "" || strings.ToLower(p.Address) != e {
				return Allowlist{}, fmt.Errorf("entry %q is neither an address nor @domain", e)
			}
			a.addresses[e] = true
		}
	}
	return a, nil
}

func (a Allowlist) Empty() bool { return len(a.addresses) == 0 && len(a.domains) == 0 }

func (a Allowlist) Allows(addr string) bool {
	if a.Empty() {
		return true
	}
	addr = strings.ToLower(strings.TrimSpace(addr))
	if a.addresses[addr] {
		return true
	}
	at := strings.LastIndex(addr, "@")
	return at >= 0 && a.domains[addr[at+1:]]
}
