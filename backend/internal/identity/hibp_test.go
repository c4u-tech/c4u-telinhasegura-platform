package identity_test

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
)

// SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
func hibpServer(t *testing.T, status int, body string) identity.HIBP {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/range/5BAA6" {
			t.Errorf("requested %s: only the 5-char prefix may leave the server", r.URL.Path)
		}
		if r.Header.Get("Add-Padding") != "true" {
			t.Error("Add-Padding header missing")
		}
		w.WriteHeader(status)
		fmt.Fprint(w, body)
	}))
	t.Cleanup(srv.Close)
	return identity.HIBP{Client: srv.Client(), BaseURL: srv.URL + "/range/"}
}

func TestHIBPFindsABreachedSuffix(t *testing.T) {
	h := hibpServer(t, 200, "0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n1E4C9B93F3F0682250B6CF8331B7EE68FD8:9545824\r\n")
	if breached, err := h.IsBreached(context.Background(), "password"); err != nil || !breached {
		t.Fatalf("breached=%v err=%v", breached, err)
	}
}

func TestHIBPIgnoresPaddingEntries(t *testing.T) {
	h := hibpServer(t, 200, "1E4C9B93F3F0682250B6CF8331B7EE68FD8:0\r\n")
	if breached, err := h.IsBreached(context.Background(), "password"); err != nil || breached {
		t.Fatalf("padding counted as breach: breached=%v err=%v", breached, err)
	}
}

func TestHIBPReportsUnavailability(t *testing.T) {
	h := hibpServer(t, 503, "")
	if _, err := h.IsBreached(context.Background(), "password"); !errors.Is(err, identity.ErrBreachCheckUnavailable) {
		t.Fatalf("got %v", err)
	}
}
