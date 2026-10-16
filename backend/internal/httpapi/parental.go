package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
)

type deviceOut struct {
	ID         string    `json:"id"`
	Label      string    `json:"label"`
	MinorID    string    `json:"minor_id"`
	LinkedAt   time.Time `json:"linked_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

func deviceBody(d parental.Device) deviceOut {
	return deviceOut{d.ID, d.Label, d.MinorID, d.LinkedAt.UTC(), d.LastSeenAt.UTC()}
}

type minorIDIn struct {
	MinorID string `json:"minor_id"`
}

func (s *Server) getPIN(w http.ResponseWriter, r *http.Request) {
	set, err := s.Parental.PINSet(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"set": set})
}

func (s *Server) setPIN(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PIN string `json:"pin"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Parental.SetPIN(r.Context(), current(r).AccountID, in.PIN); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) verifyPIN(w http.ResponseWriter, r *http.Request) {
	var in pinIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Parental.VerifyPIN(r.Context(), current(r).AccountID, in.PIN); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) enterKidMode(w http.ResponseWriter, r *http.Request) {
	var in minorIDIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	sess := current(r)
	if err := s.Parental.EnterKidMode(r.Context(), sess.AccountID, sess.ID, in.MinorID); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) createLinkCode(w http.ResponseWriter, r *http.Request) {
	var in minorIDIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	lc, err := s.Parental.CreateLinkCode(r.Context(), current(r).AccountID, in.MinorID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"code": lc.Code, "minor_id": lc.MinorID, "expires_at": lc.ExpiresAt.UTC()})
}

func (s *Server) listDevices(w http.ResponseWriter, r *http.Request) {
	list, err := s.Parental.Devices(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	out := make([]deviceOut, 0, len(list))
	for _, d := range list {
		out = append(out, deviceBody(d))
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": out})
}

func (s *Server) unlinkDevice(w http.ResponseWriter, r *http.Request) {
	if err := s.Parental.Unlink(r.Context(), current(r).AccountID, r.PathValue("id")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
