package family

import (
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// normalizeNickname composes (NFC) and trims a nickname, then accepts 1-20
// runes without control characters.
func normalizeNickname(s string) (string, bool) {
	if !utf8.ValidString(s) {
		return "", false
	}
	s = strings.TrimSpace(norm.NFC.String(s))
	if n := utf8.RuneCountInString(s); n < 1 || n > maxNickname {
		return "", false
	}
	if strings.ContainsFunc(s, unicode.IsControl) {
		return "", false
	}
	return s, true
}

func validAvatar(a string) bool { return slices.Contains(Avatars, a) }

func validAgeBand(b AgeBand) bool { return b == AgeUpTo4 || b == Age5To8 || b == Age9To12 }

func (in MinorInput) normalized() (MinorInput, error) {
	nick, ok := normalizeNickname(in.Nickname)
	if !ok || !validAvatar(in.Avatar) || !validAgeBand(in.AgeBand) {
		return MinorInput{}, ErrValidation
	}
	in.Nickname = nick
	return in, nil
}

// normalized refuses an empty patch and any present field that breaks
// the rules.
func (p MinorPatch) normalized() (MinorPatch, error) {
	if p.Nickname == nil && p.Avatar == nil && p.AgeBand == nil {
		return MinorPatch{}, ErrValidation
	}
	if p.Nickname != nil {
		nick, ok := normalizeNickname(*p.Nickname)
		if !ok {
			return MinorPatch{}, ErrValidation
		}
		p.Nickname = &nick
	}
	if p.Avatar != nil && !validAvatar(*p.Avatar) || p.AgeBand != nil && !validAgeBand(*p.AgeBand) {
		return MinorPatch{}, ErrValidation
	}
	return p, nil
}
