package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// livez serves h on 127.0.0.1 and returns an env whose HTTP_ADDR is
// addr with the server's port in place of PORT.
func livez(t *testing.T, addr string, h http.HandlerFunc) func(string) string {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	a := strings.Replace(addr, "PORT", u.Port(), 1)
	return func(k string) string {
		if k == "HTTP_ADDR" {
			return a
		}
		return "" // nothing else is read, not even DATABASE_URL
	}
}

func ok(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/livez" {
		http.NotFound(w, r)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func TestHealthcheckPassesOnALiveAPI(t *testing.T) {
	for _, addr := range []string{":PORT", "0.0.0.0:PORT", "[::]:PORT", "127.0.0.1:PORT"} {
		if err := healthcheck(context.Background(), livez(t, addr, ok)); err != nil {
			t.Errorf("HTTP_ADDR %s: %v", addr, err)
		}
	}
}

func TestHealthcheckFails(t *testing.T) {
	down := livez(t, ":PORT", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusServiceUnavailable) })
	if err := healthcheck(context.Background(), down); err == nil {
		t.Error("503: no error")
	}

	srv := httptest.NewServer(http.HandlerFunc(ok))
	port := strings.TrimPrefix(srv.URL, "http://127.0.0.1:")
	srv.Close()
	refused := func(k string) string {
		if k == "HTTP_ADDR" {
			return ":" + port
		}
		return ""
	}
	if err := healthcheck(context.Background(), refused); err == nil {
		t.Error("connection refused: no error")
	}

	release := make(chan struct{})
	slow := livez(t, ":PORT", func(w http.ResponseWriter, _ *http.Request) { <-release })
	defer close(release)
	start := time.Now()
	if err := healthcheck(context.Background(), slow); err == nil || time.Since(start) > 3*time.Second {
		t.Errorf("slow API: %v after %s, want an error within about 2s", err, time.Since(start))
	}
}

func TestHealthcheckDefaultsToPort8080(t *testing.T) {
	if got := probeURL(func(string) string { return "" }); got != "http://127.0.0.1:8080/livez" {
		t.Fatalf("probe URL %q", got)
	}
}

func TestCommand(t *testing.T) {
	if c, err := command(nil); c != "serve" || err != nil {
		t.Fatalf("no argument: %q %v", c, err)
	}
	if c, err := command([]string{"healthcheck"}); c != "healthcheck" || err != nil {
		t.Fatalf("healthcheck: %q %v", c, err)
	}
	for _, args := range [][]string{{"migrate"}, {"healthcheck", "x"}, {""}} {
		if _, err := command(args); err == nil || !strings.Contains(err.Error(), "usage:") {
			t.Errorf("%q: %v, want the usage", args, err)
		}
	}
}
