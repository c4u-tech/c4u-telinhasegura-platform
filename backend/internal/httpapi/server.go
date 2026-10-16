// Package httpapi is the API's HTTP surface: routes, middleware and the
// mapping from domain errors to RFC 9457 problems.
package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"net/netip"
	"slices"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Server struct {
	Pool           *pgxpool.Pool
	AllowedOrigins []string
	Log            *slog.Logger
	Identity       *identity.Service
	IPLimiter      *ratelimit.Limiter
	RedeemLimiter  *ratelimit.Limiter // per IP
	TrustedProxies []netip.Prefix     // whose X-Forwarded-For the IP limiters believe
	Sessions       *session.Service
	Family         *family.Service
	Parental       *parental.Service
	Privacy        *privacy.Service
	Curation       *curation.Service
	Staff          *staff.Service // platform roles
	ScreenTime     *screentime.Service

	StaffMFARequired bool // admin and moderator routes need an elevation

	AppleAndroidPackage string // empty: Apple is off

	Version string // the build, reported by /livez; empty reads as dev
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	for _, r := range s.routes() {
		mux.HandleFunc(r.Pattern, s.wrap(r))
	}
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		writeProblem(w, newProblem(http.StatusNotFound, "not_found"))
	})
	return s.cors(mux)
}

// healthTimeout bounds the database ping of /healthz.
const healthTimeout = 2 * time.Second

// health is for outside monitoring: it reports whether the database answers.
func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), healthTimeout)
	defer cancel()
	if err := s.Pool.Ping(ctx); err != nil {
		writeProblem(w, newProblem(http.StatusServiceUnavailable, "unavailable"))
		return
	}
	w.WriteHeader(http.StatusOK)
}

// live is the container's liveness: the process answers, with no I/O, so a
// database blip never gets the container killed.
func (s *Server) live(w http.ResponseWriter, _ *http.Request) {
	v := s.Version
	if v == "" {
		v = "dev"
	}
	writeJSON(w, http.StatusOK, map[string]string{"version": v})
}

// cors answers credentialed cross-origin requests only for listed origins.
func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		preflight := r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != ""
		if origin != "" && slices.Contains(s.AllowedOrigins, origin) {
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Access-Control-Allow-Credentials", "true")
			h.Add("Vary", "Origin")
			if preflight {
				h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE")
				h.Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-CSRF-Token")
				h.Set("Access-Control-Max-Age", "600")
				w.WriteHeader(http.StatusNoContent)
				return
			}
			// Retry-After is not CORS-safelisted; without this web JS cannot read it.
			h.Set("Access-Control-Expose-Headers", "Retry-After")
		} else if preflight {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}
