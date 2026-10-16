package curation_test

import (
	"errors"
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

func TestParseLink(t *testing.T) {
	const id = "dQw4w9WgXcQ"
	for _, link := range []string{
		"https://www.youtube.com/watch?v=" + id,
		"https://youtube.com/watch?v=" + id + "&t=42s",
		"https://m.youtube.com/watch?v=" + id + "&list=PL1",
		"http://www.youtube.com/watch?feature=share&v=" + id,
		"https://youtu.be/" + id,
		"https://www.youtu.be/" + id,
		"https://youtu.be/" + id + "?si=AbC123",
		"https://youtu.be/" + id + "/",
		"https://www.youtube.com/embed/" + id,
		"https://youtube.com/embed/" + id + "?autoplay=1",
		"https://www.youtube-nocookie.com/embed/" + id,
		"https://youtube-nocookie.com/embed/" + id,
		"  https://WWW.YouTube.com/watch?v=" + id + "  ",
		"youtube.com/watch?v=" + id,
		"youtu.be/" + id,
		"www.youtu.be/" + id,
	} {
		if got, err := curation.ParseLink(link); err != nil || got != id {
			t.Errorf("%q: %q %v", link, got, err)
		}
	}
	for _, link := range []string{
		"",
		"not a link",
		"https://vimeo.com/123456",
		"https://www.youtube.com/watch?v=short",
		"https://www.youtube.com/watch?v=" + id + "x",
		"https://www.youtube.com/watch?v=dQw4w9WgX!Q",
		"https://www.youtube.com/watch",
		"https://youtube.com.evil.example/watch?v=" + id,
		"https://evil.example/?u=youtube.com/watch?v=" + id,
		"https://user@youtube.com/watch?v=" + id,
		"https://youtube.com:8443/watch?v=" + id,
		"ftp://youtube.com/watch?v=" + id,
		"https://www.youtube.com/channel/UC123",
		"https://www.youtube.com/playlist?list=PL1",
		"https://www.youtube-nocookie.com/watch?v=" + id,
		"https://youtu.be/",
		"https://www.youtube.com/shorts/abc",
		"https://www.youtube.com/embed/videoseries?list=PL1",
		"https://www.youtube.com/embed/live_stream?channel=UC123",
	} {
		if got, err := curation.ParseLink(link); !errors.Is(err, curation.ErrInvalidLink) {
			t.Errorf("%q: %q %v, want invalid_link", link, got, err)
		}
	}
	for _, link := range []string{
		"https://www.youtube.com/shorts/" + id,
		"https://youtube.com/shorts/" + id + "?feature=share",
		"https://m.youtube.com/shorts/" + id,
	} {
		var refused *curation.RefusedError
		if _, err := curation.ParseLink(link); !errors.As(err, &refused) || refused.Reason != curation.RefusedShorts {
			t.Errorf("%q: %v, want video_refused shorts", link, err)
		}
	}
}

func TestDisplayRoles(t *testing.T) {
	for _, r := range []curation.DisplayRole{curation.MaePai, curation.Cuidador} {
		if !r.Valid() || r.Professional() {
			t.Errorf("%s: valid=%v professional=%v", r, r.Valid(), r.Professional())
		}
	}
	for _, r := range []curation.DisplayRole{curation.Pedagogo, curation.Psicologo, curation.Educador, curation.Pediatra} {
		if !r.Valid() || !r.Professional() {
			t.Errorf("%s: valid=%v professional=%v", r, r.Valid(), r.Professional())
		}
	}
	for _, r := range []curation.DisplayRole{"", "astronauta", "Pedagogo"} {
		if r.Valid() {
			t.Errorf("%q accepted", r)
		}
	}
}

func TestThemes(t *testing.T) {
	want := []string{"bichos", "musica", "historias", "aprender", "brincar", "natureza"}
	got := curation.Themes()
	if !slices.Equal(got, want) {
		t.Fatalf("got %v", got)
	}
	got[0] = "carros"
	if curation.Themes()[0] != "bichos" {
		t.Fatal("a caller changed the fixed theme set")
	}
}
