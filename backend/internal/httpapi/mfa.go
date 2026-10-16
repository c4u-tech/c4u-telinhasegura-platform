package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// noStore keeps a secret or recovery codes out of every cache.
func noStore(w http.ResponseWriter) { w.Header().Set("Cache-Control", "no-store") }

func (s *Server) mfaStatus(w http.ResponseWriter, r *http.Request) {
	sess := current(r)
	st, err := s.Staff.MFAStatus(r.Context(), sess.AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	required := false
	if s.StaffMFARequired {
		role, err := s.Staff.FirstRole(r.Context(), sess.AccountID, staff.Admin, staff.Moderator)
		if err != nil {
			s.fail(w, err)
			return
		}
		required = role != ""
	}
	out := map[string]any{"enrolled": st.Enrolled, "recovery_codes_left": st.RecoveryCodesLeft, "required": required}
	if st.Enrolled {
		out["enrolled_at"] = st.EnrolledAt.UTC()
	}
	if s.Sessions.Elevated(sess) {
		out["elevated_until"] = sess.ElevatedUntil.UTC()
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) startMFAEnrollment(w http.ResponseWriter, r *http.Request) {
	e, err := s.Staff.StartEnrollment(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	noStore(w)
	writeJSON(w, http.StatusCreated, map[string]string{"secret": e.Secret, "otpauth_uri": e.URI})
}

func (s *Server) confirmMFAEnrollment(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Code string `json:"code"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	sess := current(r)
	el, err := s.Staff.ConfirmEnrollment(r.Context(), sess.AccountID, sess.ID, in.Code)
	if err != nil {
		s.fail(w, err)
		return
	}
	noStore(w)
	writeJSON(w, http.StatusOK, map[string]any{"recovery_codes": el.RecoveryCodes, "elevated_until": el.Until.UTC()})
}

func (s *Server) mfaChallenge(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Code         string `json:"code"`
		RecoveryCode string `json:"recovery_code"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	sess := current(r)
	el, err := s.Staff.Challenge(r.Context(), sess.AccountID, sess.ID, staff.ChallengeInput{Code: in.Code, RecoveryCode: in.RecoveryCode})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"elevated_until": el.Until.UTC(), "recovery_codes_left": el.RecoveryCodesLeft})
}

func (s *Server) regenerateRecoveryCodes(w http.ResponseWriter, r *http.Request) {
	codes, err := s.Staff.RegenerateRecoveryCodes(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	noStore(w)
	writeJSON(w, http.StatusOK, map[string]any{"recovery_codes": codes})
}
