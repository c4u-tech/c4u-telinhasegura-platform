package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/accesslog"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

type childKey struct{}

func child(r *http.Request) parental.Principal {
	return r.Context().Value(childKey{}).(parental.Principal)
}

// childAuthed admits a child principal only: a linked device's token, or
// a session locked to a child. A Bearer
// token is tried as a device first, then as a mobile session.
func (s *Server) childAuthed(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		p, err := s.childPrincipal(r)
		if err != nil {
			s.fail(w, err)
			return
		}
		s.recordAccess(r, accesslog.Entry{AccountID: p.AccountID, DeviceID: p.DeviceID, SessionID: p.SessionID})
		h(w, r.WithContext(context.WithValue(r.Context(), childKey{}, p)))
	}
}

// childPrincipal is a linked device, which is never asked about any
// account's status, or else a session, which is refused while its account
// is suspended.
func (s *Server) childPrincipal(r *http.Request) (parental.Principal, error) {
	ctx := r.Context()
	if tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer "); ok {
		p, err := s.Parental.AuthenticateDevice(ctx, tok)
		if !errors.Is(err, parental.ErrUnauthenticated) {
			return p, err
		}
		sess, err := s.Sessions.Authenticate(ctx, session.Mobile, tok)
		if err != nil {
			return parental.Principal{}, err
		}
		if err := s.refuseSuspended(ctx, sess.AccountID); err != nil {
			return parental.Principal{}, err
		}
		return s.Parental.SessionPrincipal(ctx, sess.ID, sess.AccountID)
	}
	c, err := r.Cookie(cookieName)
	if err != nil {
		return parental.Principal{}, session.ErrUnauthenticated
	}
	sess, err := s.Sessions.Authenticate(ctx, session.Web, c.Value)
	if err != nil {
		return parental.Principal{}, err
	}
	if !csrfOK(r, sess) {
		return parental.Principal{}, errCSRF
	}
	if err := s.refuseSuspended(ctx, sess.AccountID); err != nil {
		return parental.Principal{}, err
	}
	return s.Parental.SessionPrincipal(ctx, sess.ID, sess.AccountID)
}

// requireConsent runs after childAuthed: it refuses a child whose consent
// is not current, so a paused profile shows nothing until a guardian
// authorizes it again.
func (s *Server) requireConsent(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := s.Parental.RequireConsent(r.Context(), child(r)); err != nil {
			s.fail(w, err)
			return
		}
		h(w, r)
	}
}

type profileOut struct {
	ID             string `json:"id"`
	Nickname       string `json:"nickname"`
	Avatar         string `json:"avatar"`
	AgeBand        string `json:"age_band"`
	ConsentCurrent bool   `json:"consent_current"`
}

func profileBody(p parental.Profile) profileOut {
	return profileOut{p.ID, p.Nickname, p.Avatar, p.AgeBand, p.ConsentCurrent}
}

type pinIn struct {
	PIN string `json:"pin"`
}

func (s *Server) childProfile(w http.ResponseWriter, r *http.Request) {
	p, err := s.Parental.Profile(r.Context(), child(r))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, profileBody(p))
}

func (s *Server) unlock(w http.ResponseWriter, r *http.Request) {
	var in pinIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Parental.Unlock(r.Context(), child(r), in.PIN); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) childProfiles(w http.ResponseWriter, r *http.Request) {
	var in pinIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	list, err := s.Parental.Profiles(r.Context(), child(r), in.PIN)
	if err != nil {
		s.fail(w, err)
		return
	}
	out := make([]profileOut, 0, len(list))
	for _, p := range list {
		out = append(out, profileBody(p))
	}
	writeJSON(w, http.StatusOK, map[string]any{"profiles": out})
}

func (s *Server) switchProfile(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PIN     string `json:"pin"`
		MinorID string `json:"minor_id"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	p, err := s.Parental.SwitchProfile(r.Context(), child(r), in.PIN, in.MinorID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, profileBody(p))
}

// redeem is public: the child's device has no credential yet. It has its
// own per-IP budget on top of the shared one.
func (s *Server) redeem(w http.ResponseWriter, r *http.Request) {
	if ok, wait := s.RedeemLimiter.Allow(s.clientIP(r)); !ok {
		writeRateLimited(w, wait)
		return
	}
	var in struct {
		Code  string `json:"code"`
		Label string `json:"label"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	out, err := s.Parental.Redeem(r.Context(), in.Code, in.Label)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"token": out.Token, "profile": profileBody(out.Profile)})
}
