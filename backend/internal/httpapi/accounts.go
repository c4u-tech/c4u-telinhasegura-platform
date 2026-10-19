package httpapi

import (
	"math"
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/clientip"
)

// accepted is the one body every enumeration-sensitive endpoint returns.
var accepted = map[string]string{"status": "accepted"}

func (s *Server) signUp(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email            string `json:"email"`
		Password         string `json:"password"`
		AdultDeclaration bool   `json:"adult_declaration"`
		TermsVersion     string `json:"terms_version"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if _, err := s.Identity.SignUp(r.Context(), in.Email, in.Password, in.AdultDeclaration, in.TermsVersion); err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, accepted)
}

func (s *Server) resendVerification(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Identity.ResendVerification(r.Context(), in.Email); err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, accepted)
}

func (s *Server) confirmEmail(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token string `json:"token"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Identity.ConfirmEmail(r.Context(), in.Token); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// clientIP is what the per-IP budgets key on: the peer, or, behind a
// trusted proxy, the client it forwarded for.
func (s *Server) clientIP(r *http.Request) string {
	return clientip.Resolve(r.RemoteAddr, r.Header.Values("X-Forwarded-For"), s.TrustedProxies)
}

// limited applies the per-IP budget of the unauthenticated endpoints.
func (s *Server) limited(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if ok, wait := s.IPLimiter.Allow(s.clientIP(r)); !ok {
			writeRateLimited(w, wait)
			return
		}
		h(w, r)
	}
}

func writeRateLimited(w http.ResponseWriter, d time.Duration) {
	p := newProblem(http.StatusTooManyRequests, "rate_limited")
	p.RetryAfter = int(math.Ceil(d.Seconds()))
	if p.RetryAfter < 1 {
		p.RetryAfter = 1
	}
	writeProblem(w, p)
}

func (s *Server) acceptTerms(w http.ResponseWriter, r *http.Request) {
	var in struct {
		TermsVersion string `json:"terms_version"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Identity.AcceptTerms(r.Context(), current(r).AccountID, in.TermsVersion); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
