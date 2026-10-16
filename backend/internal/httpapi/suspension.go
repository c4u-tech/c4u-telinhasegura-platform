package httpapi

import "net/http"

// The suspension routes. Both are of kind admin,
// with a fresh re-authentication and a reason, and each answers the
// refreshed sheet.

func (s *Server) suspendAccount(w http.ResponseWriter, r *http.Request) {
	reason, ok := s.supportReason(w, r)
	if !ok {
		return
	}
	sh, err := s.Staff.Suspend(r.Context(), current(r).AccountID, r.PathValue("account_id"), reason)
	s.writeSheet(w, sh, err)
}

func (s *Server) reinstateAccount(w http.ResponseWriter, r *http.Request) {
	reason, ok := s.supportReason(w, r)
	if !ok {
		return
	}
	sh, err := s.Staff.Reinstate(r.Context(), current(r).AccountID, r.PathValue("account_id"), reason)
	s.writeSheet(w, sh, err)
}
