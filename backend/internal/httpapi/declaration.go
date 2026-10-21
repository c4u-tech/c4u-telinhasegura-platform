package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

type declarationOut struct {
	Version  string `json:"version"`
	Text     string `json:"text"`
	Accepted bool   `json:"accepted"`
}

func declarationBody(d curation.Declaration) declarationOut {
	return declarationOut{Version: d.Version, Text: d.Text, Accepted: d.Accepted}
}

func (s *Server) declaration(w http.ResponseWriter, r *http.Request) {
	d, err := s.Curation.Declaration(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, declarationBody(d))
}

// acceptDeclaration takes the version the curator was shown, so the
// record names the words they agreed to.
func (s *Server) acceptDeclaration(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Version string `json:"version"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	d, err := s.Curation.AcceptDeclaration(r.Context(), current(r).AccountID, in.Version)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, declarationBody(d))
}

// requireDeclaration refuses a curator who has not accepted the curator
// terms in force: they promise to apply the criteria and to stay away from
// videos they have a tie to, so no review happens before that promise.
func (s *Server) requireDeclaration(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ok, err := s.Curation.Declared(r.Context(), current(r).AccountID)
		if err == nil && !ok {
			err = curation.ErrDeclarationRequired
		}
		if err != nil {
			s.fail(w, err)
			return
		}
		h(w, r)
	}
}
