package parental_test

import (
	"bytes"
	"crypto/rand"
	"errors"
	"regexp"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
)

func TestValidatePIN(t *testing.T) {
	for pin, want := range map[string]error{
		"2580":    nil,
		"135790":  nil,
		"1203":    nil,
		"123":     parental.ErrValidation,
		"1234567": parental.ErrValidation,
		"12a4":    parental.ErrValidation,
		"":        parental.ErrValidation,
		" 2580":   parental.ErrValidation,
		"١٢٣٤":    parental.ErrValidation, // Arabic-Indic digits are not ASCII
		"0000":    parental.ErrWeakPIN,
		"777777":  parental.ErrWeakPIN,
		"1234":    parental.ErrWeakPIN,
		"456789":  parental.ErrWeakPIN,
		"98765":   parental.ErrWeakPIN,
		"3210":    parental.ErrWeakPIN,
	} {
		if got := parental.ValidatePIN(pin); !errors.Is(got, want) {
			t.Errorf("ValidatePIN(%q) = %v, want %v", pin, got, want)
		}
	}
}

func TestNewCode(t *testing.T) {
	got, err := parental.NewCode(bytes.NewReader([]byte{0, 1, 2, 3, 4, 5, 6, 7}))
	if err != nil || got != "0123-4567" {
		t.Fatalf("NewCode = %q, %v", got, err)
	}
	// Only the low five bits pick the symbol: 32 → 0, 63 and 255 → Z.
	if got, _ := parental.NewCode(bytes.NewReader([]byte{31, 32, 63, 255, 8, 9, 10, 11})); got != "Z0ZZ-89AB" {
		t.Fatalf("NewCode = %q", got)
	}
	shape := regexp.MustCompile(`^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`)
	for range 200 {
		if c, err := parental.NewCode(rand.Reader); err != nil || !shape.MatchString(c) {
			t.Fatalf("NewCode = %q, %v", c, err)
		}
	}
	if _, err := parental.NewCode(bytes.NewReader([]byte{1, 2, 3})); err == nil {
		t.Fatal("a short reader must fail")
	}
}

func TestNormalizeCode(t *testing.T) {
	for in, want := range map[string]string{
		"ABCD-EFGH":  "ABCDEFGH",
		"abcd efgh":  "ABCDEFGH",
		"o123 4567":  "01234567",
		"iL1O-0000":  "11100000",
		" 0123-4567": "01234567",
	} {
		if got := parental.NormalizeCode(in); got != want {
			t.Errorf("NormalizeCode(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestNormalizeLabel(t *testing.T) {
	if got, err := parental.NormalizeLabel("  Tablet da Lia "); err != nil || got != "Tablet da Lia" {
		t.Fatalf("got %q, %v", got, err)
	}
	if _, err := parental.NormalizeLabel(strings.Repeat("á", 40)); err != nil {
		t.Fatalf("40 runes: %v", err)
	}
	for _, bad := range []string{"", "   ", strings.Repeat("á", 41), "Tab\nlet", "Tablet\x00", "\xff\xfe"} {
		if _, err := parental.NormalizeLabel(bad); !errors.Is(err, parental.ErrValidation) {
			t.Errorf("NormalizeLabel(%q) = %v, want ErrValidation", bad, err)
		}
	}
}
