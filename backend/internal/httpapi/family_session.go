package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

// startFamilySession lets a guardian hand one long work to a child, behind
// the family PIN. The child must be the guardian's, with a current
// consent, and the video a work that child may watch only with the
// family, all before the PIN is spent; screen time then grants the
// optional extension and checks that the work fits.
func (s *Server) startFamilySession(w http.ResponseWriter, r *http.Request) {
	var in struct {
		VideoID       string `json:"video_id"`
		PIN           string `json:"pin"`
		ExtendMinutes int    `json:"extend_minutes"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if in.ExtendMinutes != 0 && !screentime.ValidMinutes(in.ExtendMinutes) {
		s.fail(w, screentime.ErrValidation)
		return
	}
	ctx, account, minor := r.Context(), current(r).AccountID, r.PathValue("id")
	familyID, err := s.Parental.ConsentedChild(ctx, account, minor)
	if err != nil {
		s.fail(w, err)
		return
	}
	if _, err := s.Curation.FamilyWork(ctx, curation.Child{FamilyID: familyID, MinorID: minor}, in.VideoID); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Parental.VerifyPIN(ctx, account, in.PIN); err != nil {
		s.fail(w, err)
		return
	}
	fs, err := s.ScreenTime.StartFamilySession(ctx, account, minor, in.VideoID, in.ExtendMinutes)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"session_id": fs.ID, "start_seconds": fs.StartSeconds})
}
