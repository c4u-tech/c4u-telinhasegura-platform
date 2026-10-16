package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
)

func validProvider(p idtoken.Provider) bool { return p == idtoken.Google || p == idtoken.Apple }

func (s *Server) providerSignIn(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Provider    idtoken.Provider `json:"provider"`
		IDToken     string           `json:"id_token"`
		Client      session.Client   `json:"client"`
		DeviceLabel string           `json:"device_label"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if !validProvider(in.Provider) || !validClient(in.Client) {
		s.fail(w, errBadBody)
		return
	}
	accountID, err := s.Identity.ProviderSignIn(r.Context(), in.Provider, in.IDToken)
	if err != nil {
		s.fail(w, err)
		return
	}
	s.startSession(w, r, accountID, in.Client, in.DeviceLabel)
}

func (s *Server) providerSignUp(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Ticket           string         `json:"ticket"`
		AdultDeclaration bool           `json:"adult_declaration"`
		Client           session.Client `json:"client"`
		DeviceLabel      string         `json:"device_label"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if !validClient(in.Client) {
		s.fail(w, errBadBody)
		return
	}
	accountID, err := s.Identity.ProviderSignUp(r.Context(), in.Ticket, in.AdultDeclaration)
	if err != nil {
		s.fail(w, err)
		return
	}
	s.startSession(w, r, accountID, in.Client, in.DeviceLabel)
}

func (s *Server) providerLink(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Ticket        string         `json:"ticket"`
		Password      string         `json:"password"`
		ClearPassword bool           `json:"clear_password"`
		Client        session.Client `json:"client"`
		DeviceLabel   string         `json:"device_label"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if !validClient(in.Client) {
		s.fail(w, errBadBody)
		return
	}
	accountID, err := s.Identity.ProviderLink(r.Context(), in.Ticket, identity.LinkProof{Password: in.Password, ClearPassword: in.ClearPassword})
	if err != nil {
		s.fail(w, err)
		return
	}
	s.startSession(w, r, accountID, in.Client, in.DeviceLabel)
}
