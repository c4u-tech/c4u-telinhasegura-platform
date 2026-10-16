package curation

import (
	"net/url"
	"regexp"
	"slices"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// DisplayRole is staff's: how a curator's reviews are shown.
// The aliases keep curation's names.
type DisplayRole = staff.DisplayRole

const (
	MaePai    = staff.MaePai
	Cuidador  = staff.Cuidador
	Pedagogo  = staff.Pedagogo
	Psicologo = staff.Psicologo
	Educador  = staff.Educador
	Pediatra  = staff.Pediatra
)

var themes = []string{"bichos", "musica", "historias", "aprender", "brincar", "natureza"}

// Themes is the fixed theme set, in display order (Themes).
func Themes() []string { return slices.Clone(themes) }

var (
	videoID    = regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)
	shortHosts = []string{"youtu.be", "www.youtu.be"}
	watchHosts = []string{"youtube.com", "www.youtube.com", "m.youtube.com"}
	embedHosts = []string{"youtube.com", "www.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com"}
)

// ParseLink returns the 11-character video ID of a YouTube link in one of
// the accepted forms. A Shorts link is refused as such;
// anything else is ErrInvalidLink. The server never fetches the link, it
// only reads the ID out of it (SSRF).
func ParseLink(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" && u.Scheme != "http" || u.User != nil || u.Port() != "" {
		return "", ErrInvalidLink
	}
	host := strings.ToLower(u.Hostname())
	path := strings.TrimSuffix(u.Path, "/")
	var id string
	switch {
	case slices.Contains(shortHosts, host):
		id = strings.TrimPrefix(path, "/")
	case slices.Contains(watchHosts, host) && path == "/watch":
		id = u.Query().Get("v")
	case slices.Contains(watchHosts, host) && strings.HasPrefix(path, "/shorts/"):
		if videoID.MatchString(strings.TrimPrefix(path, "/shorts/")) {
			return "", &RefusedError{Reason: RefusedShorts}
		}
	case slices.Contains(embedHosts, host) && strings.HasPrefix(path, "/embed/"):
		id = strings.TrimPrefix(path, "/embed/")
		if id == "videoseries" || id == "live_stream" { // playlist and live embeds, not video ids
			return "", ErrInvalidLink
		}
	}
	if !videoID.MatchString(id) {
		return "", ErrInvalidLink
	}
	return id, nil
}

func validTheme(t string) bool { return slices.Contains(themes, t) }

// bandRank orders the bands by strictness, the oldest being the
// strictest. An unknown band ranks 0.
func bandRank(b family.AgeBand) int {
	switch b {
	case family.AgeUpTo4:
		return 1
	case family.Age5To8:
		return 2
	case family.Age9To12:
		return 3
	}
	return 0
}
