package httpapi

import (
	"context"
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

type roleKey struct{}

// withRole is authed plus one of roles, read from the database on every
// request with no cache: a role removed a moment ago is refused on the
// next call.
// authed runs first, so a device token is 401, a suspended account 403
// account_suspended and a locked session 403 kid_mode before any role
// check (no staff route is on the allow-list). The first of roles the account holds
// is the actor's role for the handler's audit (actorRole).
func (s *Server) withRole(roles []staff.Role, missing error, h http.HandlerFunc) http.HandlerFunc {
	return s.authed(false, func(w http.ResponseWriter, r *http.Request) {
		role, err := s.Staff.FirstRole(r.Context(), current(r).AccountID, roles...)
		if err == nil && role == "" {
			err = missing
		}
		if err != nil {
			s.fail(w, err)
			return
		}
		h(w, r.WithContext(context.WithValue(r.Context(), roleKey{}, role)))
	})
}

// actorRole is the platform role withRole matched for this request; false
// when the route was not wrapped in withRole, which the caller fails as
// an internal error.
func actorRole(r *http.Request) (staff.Role, bool) {
	role, ok := r.Context().Value(roleKey{}).(staff.Role)
	return role, ok && role != ""
}
