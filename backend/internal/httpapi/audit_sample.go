package httpapi

import (
	"errors"
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// auditSample serves a fresh random sample on every read.
func (s *Server) auditSample(w http.ResponseWriter, r *http.Request) {
	list, err := s.Curation.AuditSample(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	type item struct {
		Video     videoOut    `json:"video"`
		Round     int         `json:"round"`
		Approvals []reviewOut `json:"approvals"` // by displayed role, never by account
	}
	out := make([]item, 0, len(list))
	for _, c := range list {
		out = append(out, item{videoBody(c.Video), c.Round, reviewsBody(c.Approvals)})
	}
	writeJSON(w, http.StatusOK, map[string]any{"videos": out})
}

func (s *Server) auditApproval(w http.ResponseWriter, r *http.Request) {
	var in struct {
		VideoID string `json:"video_id"`
		Round   int    `json:"round"`
		Verdict string `json:"verdict"`
		Reason  string `json:"reason"`
		Hold    bool   `json:"hold"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	role, ok := actorRole(r)
	if !ok {
		s.fail(w, errors.New("httpapi: moderation route without withRole"))
		return
	}
	m := curation.Moderation{ActorID: current(r).AccountID, ActorRole: role, Reason: in.Reason}
	err := s.Curation.AuditApproval(r.Context(), m, curation.AuditInput{VideoID: in.VideoID, Round: in.Round,
		Verdict: curation.Verdict(in.Verdict), Hold: in.Hold})
	if err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
