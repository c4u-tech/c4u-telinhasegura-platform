package staff

import (
	"strings"
	"unicode/utf8"
)

const maskTail = "•••"

// MaskEmail is an email as the account sheet and the audit log show it,
// enough to tell accounts apart without revealing them: the first character of the local part
// and of the domain's first label, each followed by •••, then the
// domain from its first dot (TestMaskEmail).
func MaskEmail(email string) string {
	at := strings.LastIndex(email, "@")
	if at < 0 {
		return maskPart(email)
	}
	label, rest, dotted := strings.Cut(email[at+1:], ".")
	out := maskPart(email[:at]) + "@" + maskPart(label)
	if dotted {
		out += "." + rest
	}
	return out
}

// maskPart is p's first rune and •••; "" for an empty part.
func maskPart(p string) string {
	r, size := utf8.DecodeRuneInString(p)
	if size == 0 {
		return ""
	}
	return string(r) + maskTail
}
