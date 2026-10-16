package httpapi

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

// A moderation handler reached without withRole (a route registered with
// the wrong kind) fails as a 500, and never acts and never panics.
func TestModerateWithoutWithRoleFailsInternal(t *testing.T) {
	s := &Server{Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	acted := false
	h := s.moderate(func(context.Context, curation.Moderation, string) error { acted = true; return nil })

	r := httptest.NewRequest(http.MethodPost, "/v1/moderation/videos/x/remove", strings.NewReader(`{"reason":"Motivo claro."}`))
	r.Header.Set("Content-Type", "application/json")
	r = r.WithContext(context.WithValue(r.Context(), ctxKey{}, session.Session{AccountID: "a"}))
	w := httptest.NewRecorder()
	h(w, r)

	if w.Code != http.StatusInternalServerError || acted {
		t.Fatalf("status %d, acted %v", w.Code, acted)
	}
}
