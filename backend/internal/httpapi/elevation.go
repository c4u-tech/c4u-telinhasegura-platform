package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// requireElevation refuses a session outside its privileged elevation,
// whatever the switch. It runs after the role check
// and before the re-authentication.
func (s *Server) requireElevation(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.Sessions.Elevated(current(r)) {
			s.fail(w, staff.ErrElevationRequired)
			return
		}
		h(w, r)
	}
}

// requireMFA is the enforcement on admin and moderator routes while
// StaffMFARequired is on, after the role and before the
// re-authentication: an account with no confirmed
// factor must enroll, an enrolled one must pass the challenge. An
// elevated session passes with no read, since staff.ResetMFA clears
// every elevation in the transaction that drops the factor, so an
// elevation always has a confirmed factor behind it.
func (s *Server) requireMFA(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess := current(r)
		if s.Sessions.Elevated(sess) {
			h(w, r)
			return
		}
		enrolled, err := s.Staff.HasConfirmedFactor(r.Context(), sess.AccountID)
		switch {
		case err != nil:
			s.fail(w, err)
		case enrolled:
			s.fail(w, staff.ErrElevationRequired)
		default:
			s.fail(w, staff.ErrMFAEnrollmentRequired)
		}
	}
}
