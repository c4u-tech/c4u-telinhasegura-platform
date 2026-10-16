package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestHealthzIsOKWhenTheDatabaseAnswers(t *testing.T) {
	srv := &httpapi.Server{Pool: dbtest.New(t), Log: slog.New(slog.DiscardHandler)}

	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200", rec.Code)
	}
}

// silentPool is a pool whose server accepts connections and never answers,
// so a ping waits until its context ends: a database that hangs.
func silentPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	var conns []net.Conn
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			mu.Lock()
			conns = append(conns, c)
			mu.Unlock()
		}
	}()
	pool, err := pgxpool.New(context.Background(), "postgres://u@"+ln.Addr().String()+"/db?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = ln.Close()
		mu.Lock()
		for _, c := range conns {
			_ = c.Close()
		}
		mu.Unlock()
		pool.Close()
	})
	return pool
}

func get(h http.Handler, path string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestLivezReportsTheVersionWithoutTheDatabase(t *testing.T) {
	srv := &httpapi.Server{Pool: silentPool(t), Log: slog.New(slog.DiscardHandler), Version: "abc123"}
	start := time.Now()
	rec := get(srv.Handler(), "/livez")
	if rec.Code != http.StatusOK || time.Since(start) > 500*time.Millisecond {
		t.Fatalf("status %d after %s, want 200 at once", rec.Code, time.Since(start))
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || len(body) != 1 || body["version"] != "abc123" {
		t.Fatalf("body %s, want {\"version\":\"abc123\"}", rec.Body)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("Content-Type %q", ct)
	}
	srv.Version = ""
	if rec := get(srv.Handler(), "/livez"); !bytes.Contains(rec.Body.Bytes(), []byte(`"version":"dev"`)) {
		t.Fatalf("unset version: %s, want dev", rec.Body)
	}
}

func TestHealthzGivesUpOnAHangingDatabase(t *testing.T) {
	srv := &httpapi.Server{Pool: silentPool(t), Log: slog.New(slog.DiscardHandler)}
	start := time.Now()
	rec := get(srv.Handler(), "/healthz")
	if took := time.Since(start); took < 1500*time.Millisecond || took > 3*time.Second {
		t.Fatalf("answered after %s, want about 2s", took)
	}
	if rec.Code != http.StatusServiceUnavailable || !bytes.Contains(rec.Body.Bytes(), []byte(`"unavailable"`)) {
		t.Fatalf("status %d %s, want 503 unavailable", rec.Code, rec.Body)
	}
}
