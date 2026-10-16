package curation_test

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// thumbs serves h as YouTube's image host, through a client that never
// follows a redirect, as cmd/api wires it.
func thumbs(t *testing.T, h http.HandlerFunc) curation.YouTubeThumbs {
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	client := srv.Client()
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return curation.YouTubeThumbs{Client: client, BaseURL: srv.URL + "/vi/"}
}

func jpegBytes(n int) []byte {
	b := bytes.Repeat([]byte{0xAB}, n)
	b[0], b[1] = 0xFF, 0xD8
	return b
}

func serveJPEG(contentType string, body []byte) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", contentType)
		_, _ = w.Write(body)
	}
}

func TestThumbnailFetchesTheHQImage(t *testing.T) {
	var got string
	y := thumbs(t, func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.String()
		serveJPEG("image/jpeg", jpegBytes(1000))(w, r)
	})
	b, err := y.Thumbnail(ctx, "dQw4w9WgXcQ")
	if err != nil || len(b) != 1000 {
		t.Fatalf("%d bytes, %v", len(b), err)
	}
	if got != "/vi/dQw4w9WgXcQ/hqdefault.jpg" {
		t.Fatalf("requested %q", got)
	}
}

func TestThumbnailAcceptsWhatServersSend(t *testing.T) {
	for _, ct := range []string{"image/jpeg", "Image/JPEG", "image/jpeg; charset=binary"} {
		if _, err := thumbs(t, serveJPEG(ct, jpegBytes(10))).Thumbnail(ctx, "dQw4w9WgXcQ"); err != nil {
			t.Errorf("%q: %v", ct, err)
		}
	}
	if b, err := thumbs(t, serveJPEG("image/jpeg", jpegBytes(256<<10))).Thumbnail(ctx, "dQw4w9WgXcQ"); err != nil || len(b) != 256<<10 {
		t.Errorf("exactly 256 KiB: %d bytes, %v", len(b), err)
	}
}

func TestThumbnailRefusals(t *testing.T) {
	for name, h := range map[string]http.HandlerFunc{
		"not found":   func(w http.ResponseWriter, r *http.Request) { http.NotFound(w, r) },
		"webp":        serveJPEG("image/webp", jpegBytes(10)),
		"octet":       serveJPEG("application/octet-stream", jpegBytes(10)),
		"bad type":    serveJPEG(";;", jpegBytes(10)),
		"too large":   serveJPEG("image/jpeg", jpegBytes(256<<10+1)),
		"empty":       serveJPEG("image/jpeg", nil),
		"redirected":  func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "/elsewhere.jpg", http.StatusFound) },
		"server down": func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusBadGateway) },
	} {
		if _, err := thumbs(t, h).Thumbnail(ctx, "dQw4w9WgXcQ"); !errors.Is(err, curation.ErrThumbnailUnavailable) {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestThumbnailRefusesAMalformedID(t *testing.T) {
	called := false
	y := thumbs(t, func(w http.ResponseWriter, r *http.Request) { called = true })
	if _, err := y.Thumbnail(ctx, "../../x"); !errors.Is(err, curation.ErrThumbnailUnavailable) || called {
		t.Fatalf("err %v, host called %v", err, called)
	}
}

func TestThumbnailTimesOutWithoutTheURL(t *testing.T) {
	y := thumbs(t, func(_ http.ResponseWriter, r *http.Request) { <-r.Context().Done() })
	y.Timeout = 50 * time.Millisecond
	_, err := y.Thumbnail(ctx, "dQw4w9WgXcQ")
	if !errors.Is(err, curation.ErrThumbnailUnavailable) {
		t.Fatalf("err %v", err)
	}
	if msg := err.Error(); strings.Contains(msg, "127.0.0.1") || strings.Contains(msg, "hqdefault") || strings.Contains(msg, "dQw4w9WgXcQ") {
		t.Fatalf("the error carries the URL: %q", msg)
	}
}

func TestThumbnailNeverFollowsARedirect(t *testing.T) {
	hit := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/elsewhere.jpg" {
			hit = true
			serveJPEG("image/jpeg", jpegBytes(100))(w, r)
			return
		}
		http.Redirect(w, r, "/elsewhere.jpg", http.StatusFound)
	}))
	t.Cleanup(srv.Close)
	y := curation.YouTubeThumbs{Client: srv.Client(), BaseURL: srv.URL + "/vi/"}
	if _, err := y.Thumbnail(ctx, "dQw4w9WgXcQ"); !errors.Is(err, curation.ErrThumbnailUnavailable) {
		t.Fatalf("err %v", err)
	}
	if hit {
		t.Fatal("the redirect was followed")
	}
	if srv.Client().CheckRedirect != nil {
		t.Fatal("caller's client mutated")
	}
}
