package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

// exportData answers the guardian's export as a download that no cache
// keeps.
func (s *Server) exportData(w http.ResponseWriter, r *http.Request) {
	e, err := s.Privacy.Export(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	h := w.Header()
	h.Set("Content-Disposition", `attachment; filename="telinhasegura-dados-`+e.GeneratedAt.Format("2006-01-02")+`.json"`)
	h.Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, e)
}

// deleteRequest is the optional body of DELETE /v1/account: an Apple
// credential, sent when the API asked for one.
type deleteRequest struct {
	Apple *struct {
		IdentityToken     string `json:"identity_token"`
		AuthorizationCode string `json:"authorization_code"`
	} `json:"apple"`
}

// deleteAccount erases the caller's account; on the web it also expires
// the session cookie. Clients without Apple send no body.
func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request) {
	sess := current(r)
	var apple *privacy.AppleCredential
	if r.ContentLength != 0 {
		var req deleteRequest
		if err := decode(w, r, &req); err != nil {
			s.fail(w, err)
			return
		}
		if req.Apple != nil {
			if req.Apple.IdentityToken == "" || req.Apple.AuthorizationCode == "" {
				s.fail(w, errBadBody)
				return
			}
			apple = &privacy.AppleCredential{IdentityToken: req.Apple.IdentityToken, AuthorizationCode: req.Apple.AuthorizationCode}
		}
	}
	if err := s.Privacy.DeleteAccount(r.Context(), sess.AccountID, apple); err != nil {
		s.fail(w, err)
		return
	}
	if sess.Client == session.Web {
		expireSessionCookie(w)
	}
	w.WriteHeader(http.StatusNoContent)
}
