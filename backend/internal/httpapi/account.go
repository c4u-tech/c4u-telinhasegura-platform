package httpapi

import "net/http"

func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	me := current(r)
	if err := s.Identity.ChangePassword(r.Context(), me.AccountID, me.ID, in.CurrentPassword, in.NewPassword); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) changeEmail(w http.ResponseWriter, r *http.Request) {
	var in struct {
		NewEmail string `json:"new_email"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	me := current(r)
	if err := s.Identity.RequestEmailChange(r.Context(), me.AccountID, me.ID, in.NewEmail); err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, accepted)
}

func (s *Server) requestPasswordReset(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Identity.RequestPasswordReset(r.Context(), in.Email); err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, accepted)
}

func (s *Server) confirmPasswordReset(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token       string `json:"token"`
		NewPassword string `json:"new_password"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Identity.ConfirmPasswordReset(r.Context(), in.Token, in.NewPassword); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
