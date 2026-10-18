package httpapi

import (
	"context"
	"crypto/subtle"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

const cookieName = "__Host-ts_session"

var errCSRF = errors.New("httpapi: CSRF token missing or wrong")

type ctxKey struct{}

func current(r *http.Request) session.Session {
	return r.Context().Value(ctxKey{}).(session.Session)
}

var errKidMode = errors.New("httpapi: session is locked to a child")

var errSuspended = errors.New("httpapi: the account is suspended")

// sessioned resolves the session from a Bearer token (mobile) or the
// session cookie (web). A cookie-authenticated unsafe request must echo
// the session's CSRF token. Then, unless the route is on
// the allow-list, a suspended account is refused. That check comes
// before every kid-mode, role, elevation and re-auth check.
func (s *Server) sessioned(suspendedOK bool, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var sess session.Session
		var err error
		if tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer "); ok {
			sess, err = s.Sessions.Authenticate(r.Context(), session.Mobile, tok)
		} else if c, cerr := r.Cookie(cookieName); cerr == nil {
			sess, err = s.Sessions.Authenticate(r.Context(), session.Web, c.Value)
		} else {
			err = session.ErrUnauthenticated
		}
		if err == nil && !csrfOK(r, sess) {
			err = errCSRF
		}
		if err == nil && !suspendedOK {
			err = s.refuseSuspended(r.Context(), sess.AccountID)
		}
		if err != nil {
			s.fail(w, err)
			return
		}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, sess)))
	}
}

// refuseSuspended reads the account's status again, one primary-key read
// with no cache. A suspension, or a reinstatement, therefore takes
// effect on the next request.
// An account gone meanwhile is unauthenticated.
func (s *Server) refuseSuspended(ctx context.Context, accountID string) error {
	st, err := s.Identity.Status(ctx, accountID)
	switch {
	case errors.Is(err, identity.ErrNotFound):
		return session.ErrUnauthenticated
	case err != nil:
		return err
	case st != identity.StatusActive:
		return errSuspended
	}
	return nil
}

// authed is sessioned for guardian routes: a session locked to a child is
// refused on every one of them, after the status.
func (s *Server) authed(suspendedOK bool, h http.HandlerFunc) http.HandlerFunc {
	return s.sessioned(suspendedOK, func(w http.ResponseWriter, r *http.Request) {
		_, locked, err := s.Parental.Lock(r.Context(), current(r).ID)
		if err == nil && locked {
			err = errKidMode
		}
		if err != nil {
			s.fail(w, err)
			return
		}
		h(w, r)
	})
}

// csrfOK holds for a mobile session, a safe method, or a web request that
// echoes its session's CSRF token.
func csrfOK(r *http.Request, sess session.Session) bool {
	return sess.Client != session.Web || r.Method == http.MethodGet || r.Method == http.MethodHead ||
		subtle.ConstantTimeCompare([]byte(r.Header.Get("X-CSRF-Token")), []byte(sess.CSRFToken)) == 1
}

func (s *Server) reauthed(suspendedOK bool, h http.HandlerFunc) http.HandlerFunc {
	return s.authed(suspendedOK, s.requireReauth(h))
}

// requireReauth refuses a session not re-authenticated within the last
// 5 minutes. It is the one copy of that rule: reauthed and the admin
// routes both compose it, after their own authentication.
func (s *Server) requireReauth(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := s.Sessions.RequireRecentReauth(current(r)); err != nil {
			s.fail(w, err)
			return
		}
		h(w, r)
	}
}

func setSessionCookie(w http.ResponseWriter, value string, maxAge int) {
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: value, Path: "/", MaxAge: maxAge,
		HttpOnly: true, Secure: true, SameSite: http.SameSiteLaxMode})
}

func expireSessionCookie(w http.ResponseWriter) { setSessionCookie(w, "", -1) }

func tokensBody(is session.Issued) map[string]string {
	return map[string]string{
		"session_id":        is.Session.ID,
		"access_token":      is.Secret,
		"access_expires_at": is.AccessExpiresAt.UTC().Format(time.RFC3339),
		"refresh_token":     is.RefreshToken,
	}
}

func (s *Server) signIn(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email       string         `json:"email"`
		Password    string         `json:"password"`
		Client      session.Client `json:"client"`
		DeviceLabel string         `json:"device_label"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if !validClient(in.Client) {
		s.fail(w, errBadBody)
		return
	}
	signedIn, err := s.Identity.Authenticate(r.Context(), in.Email, in.Password)
	if err != nil {
		s.fail(w, err)
		return
	}
	is, err := s.Sessions.Create(r.Context(), signedIn.AccountID, in.Client, in.DeviceLabel)
	if err != nil {
		s.fail(w, err)
		return
	}
	// A clear_password link that landed after the password check revoked
	// every session committed before it, but may not have seen this one;
	// the re-check waits for an in-flight clear. Drop the session (already
	// gone is fine).
	current, err := s.Identity.CredentialStillCurrent(r.Context(), signedIn.AccountID, signedIn.CredentialVersion)
	if err != nil || !current {
		if rerr := s.Sessions.Revoke(r.Context(), signedIn.AccountID, is.Session.ID); rerr != nil && !errors.Is(rerr, session.ErrNotFound) {
			err = errors.Join(err, rerr)
		}
		if err == nil {
			err = identity.ErrInvalidCredentials
		}
		s.fail(w, err)
		return
	}
	writeSession(w, in.Client, is)
}

func validClient(c session.Client) bool { return c == session.Web || c == session.Mobile }

// startSession answers every successful sign-in alike: tokens for mobile,
// the cookie and CSRF token for web.
func (s *Server) startSession(w http.ResponseWriter, r *http.Request, accountID string, c session.Client, label string) {
	is, err := s.Sessions.Create(r.Context(), accountID, c, label)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeSession(w, c, is)
}

func writeSession(w http.ResponseWriter, c session.Client, is session.Issued) {
	if c == session.Mobile {
		writeJSON(w, http.StatusCreated, tokensBody(is))
		return
	}
	setSessionCookie(w, is.Secret, int((90 * 24 * time.Hour).Seconds()))
	writeJSON(w, http.StatusCreated, map[string]string{"session_id": is.Session.ID, "csrf_token": is.Session.CSRFToken})
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	is, err := s.Sessions.Refresh(r.Context(), in.RefreshToken)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, tokensBody(is))
}

func (s *Server) getSession(w http.ResponseWriter, r *http.Request) {
	sess := current(r)
	acc, err := s.Identity.Account(r.Context(), sess.AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	minorID, locked, err := s.Parental.Lock(r.Context(), sess.ID)
	if err != nil {
		s.fail(w, err)
		return
	}
	var kidMode any // null unless locked; minor_id null once the child is gone
	if locked {
		var m any
		if minorID != "" {
			m = minorID
		}
		kidMode = map[string]any{"minor_id": m}
	}
	type sessionOut struct {
		ID     string `json:"id"`
		Client string `json:"client"`
		CSRF   string `json:"csrf_token,omitempty"`
	}
	roles, err := s.Staff.Roles(r.Context(), sess.AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	names := make([]string, 0, len(roles)) // [] for everyone without a role
	for _, role := range roles {
		names = append(names, string(role))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"account":  map[string]any{"id": acc.ID, "email": acc.Email, "email_verified": acc.EmailVerified, "status": string(acc.Status), "terms_accepted": acc.TermsAccepted},
		"session":  sessionOut{ID: sess.ID, Client: string(sess.Client), CSRF: sess.CSRFToken},
		"kid_mode": kidMode,
		"roles":    names,
	})
}

func (s *Server) signOut(w http.ResponseWriter, r *http.Request) {
	sess := current(r)
	if err := s.Sessions.SignOut(r.Context(), sess.AccountID, sess.ID); err != nil {
		s.fail(w, err)
		return
	}
	if sess.Client == session.Web {
		expireSessionCookie(w)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) reauth(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Password string           `json:"password"`
		Provider idtoken.Provider `json:"provider"`
		IDToken  string           `json:"id_token"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	sess := current(r)
	byPassword, byProvider := in.Password != "", in.Provider != "" || in.IDToken != ""
	var err error
	switch {
	case byPassword == byProvider:
		err = errBadBody
	case byPassword:
		err = s.Identity.Reauthenticate(r.Context(), sess.AccountID, in.Password)
	case !validProvider(in.Provider):
		err = errBadBody
	default:
		err = s.Identity.ReauthenticateWithProvider(r.Context(), sess.AccountID, in.Provider, in.IDToken)
	}
	if err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Sessions.MarkReauth(r.Context(), sess.ID); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listSessions(w http.ResponseWriter, r *http.Request) {
	me := current(r)
	list, err := s.Sessions.List(r.Context(), me.AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	type item struct {
		ID          string    `json:"id"`
		Client      string    `json:"client"`
		DeviceLabel string    `json:"device_label"`
		CreatedAt   time.Time `json:"created_at"`
		LastSeenAt  time.Time `json:"last_seen_at"`
		Current     bool      `json:"current"`
	}
	out := make([]item, 0, len(list))
	for _, x := range list {
		out = append(out, item{x.ID, string(x.Client), x.DeviceLabel, x.CreatedAt.UTC(), x.LastSeenAt.UTC(), x.ID == me.ID})
	}
	writeJSON(w, http.StatusOK, map[string]any{"sessions": out})
}

func (s *Server) revokeSession(w http.ResponseWriter, r *http.Request) {
	me := current(r)
	id := r.PathValue("id")
	if err := s.Sessions.Revoke(r.Context(), me.AccountID, id); err != nil {
		s.fail(w, err)
		return
	}
	if id == me.ID && me.Client == session.Web {
		expireSessionCookie(w)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) revokeSessions(w http.ResponseWriter, r *http.Request) {
	me := current(r)
	var except string
	switch r.URL.Query().Get("scope") {
	case "others":
		except = me.ID
	case "all":
	default:
		s.fail(w, errBadBody)
		return
	}
	if err := s.Sessions.RevokeAll(r.Context(), me.AccountID, except); err != nil {
		s.fail(w, err)
		return
	}
	if except == "" && me.Client == session.Web {
		expireSessionCookie(w)
	}
	w.WriteHeader(http.StatusNoContent)
}
