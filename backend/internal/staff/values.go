package staff

import (
	"strings"
	"unicode/utf8"
)

// DisplayRole is how a curator's reviews are shown. The app owns the
// PT-BR labels.
type DisplayRole string

const (
	MaePai    DisplayRole = "mae-pai"
	Cuidador  DisplayRole = "cuidador"
	Pedagogo  DisplayRole = "pedagogo"
	Psicologo DisplayRole = "psicologo"
	Educador  DisplayRole = "educador"
	Pediatra  DisplayRole = "pediatra"
)

func (r DisplayRole) Valid() bool { return r == MaePai || r == Cuidador || r.Professional() }

// Professional roles need the admin's verified flag.
func (r DisplayRole) Professional() bool {
	return r == Pedagogo || r == Psicologo || r == Educador || r == Pediatra
}

// checkDisplayRole refuses an unknown displayed role, and a professional
// one without the verified flag.
func checkDisplayRole(r DisplayRole, verified bool) error {
	if !r.Valid() || r.Professional() && !verified {
		return ErrValidation
	}
	return nil
}

// CheckReason trims a staff write's reason and checks that it holds 3 to
// 200 runes. Every team and moderation write
// checks it before any lookup.
func CheckReason(raw string) (string, error) {
	r := strings.TrimSpace(raw)
	if n := utf8.RuneCountInString(r); n < 3 || n > 200 {
		return "", ErrReasonRequired
	}
	return r, nil
}
