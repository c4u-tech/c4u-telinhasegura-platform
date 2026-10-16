package parental

import (
	"io"
	"strings"
	"unicode"
	"unicode/utf8"
)

// codeAlphabet is Crockford's base32: no I, L, O or U, so a code read off
// a screen has no look-alikes.
const codeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const (
	minPIN   = 4
	maxPIN   = 6
	codeLen  = 8
	maxLabel = 40 // runes
)

// ValidatePIN accepts 4 to 6 ASCII digits that are neither all one digit
// nor a straight run up or down.
func ValidatePIN(pin string) error {
	if len(pin) < minPIN || len(pin) > maxPIN {
		return ErrValidation
	}
	for i := 0; i < len(pin); i++ {
		if pin[i] < '0' || pin[i] > '9' {
			return ErrValidation
		}
	}
	same, up, down := true, true, true
	for i := 1; i < len(pin); i++ {
		d := int(pin[i]) - int(pin[i-1])
		same, up, down = same && d == 0, up && d == 1, down && d == -1
	}
	if same || up || down {
		return ErrWeakPIN
	}
	return nil
}

// NewCode draws an 8-character link code from r, formatted XXXX-XXXX.
// 32 symbols divide 256, so a byte's low five bits pick one uniformly.
func NewCode(r io.Reader) (string, error) {
	b := make([]byte, codeLen)
	if _, err := io.ReadFull(r, b); err != nil {
		return "", err
	}
	out := make([]byte, 0, codeLen+1)
	for i, x := range b {
		if i == codeLen/2 {
			out = append(out, '-')
		}
		out = append(out, codeAlphabet[x&31])
	}
	return string(out), nil
}

// NormalizeCode is the form a code is hashed in: upper case, without
// separators, Crockford's look-alikes folded (O→0, I and L→1).
func NormalizeCode(code string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(code) {
		switch r {
		case '-', ' ':
			continue
		case 'O':
			r = '0'
		case 'I', 'L':
			r = '1'
		}
		b.WriteRune(r)
	}
	return b.String()
}

// NormalizeLabel trims a device label and refuses an empty, overlong or
// control-bearing one.
func NormalizeLabel(label string) (string, error) {
	label = strings.TrimSpace(label)
	if !utf8.ValidString(label) {
		return "", ErrValidation
	}
	if n := utf8.RuneCountInString(label); n == 0 || n > maxLabel {
		return "", ErrValidation
	}
	for _, r := range label {
		if unicode.IsControl(r) {
			return "", ErrValidation
		}
	}
	return label, nil
}
