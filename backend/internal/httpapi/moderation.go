package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func (s *Server) heldVideos(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("state") != "held" { // the only listing served
		s.fail(w, curation.ErrValidation)
		return
	}
	list, err := s.Curation.HeldVideos(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	type reports struct {
		ByReason map[string]int `json:"by_reason"`
		Notes    []string       `json:"notes"`
	}
	type heldAudit struct {
		Verdict   string    `json:"verdict"`
		Reason    string    `json:"reason"`
		AuditedAt time.Time `json:"audited_at"`
	}
	type item struct {
		Video      videoOut    `json:"video"`
		Rejections []reviewOut `json:"rejections"`
		Doubts     []reviewOut `json:"doubts"` // a curator's doubt, with the answers and the note
		HeldReason string      `json:"held_reason"`
		Reports    reports     `json:"reports"`         // since the latest reopen, never who reported
		Audit      *heldAudit  `json:"audit,omitempty"` // the audit that held the video, never who audited
	}
	out := make([]item, 0, len(list))
	for _, h := range list {
		by := map[string]int{}
		for reason, n := range h.Reports.ByReason {
			by[string(reason)] = n
		}
		var audit *heldAudit
		if h.Audit != nil {
			audit = &heldAudit{string(h.Audit.Verdict), h.Audit.Reason, h.Audit.AuditedAt.UTC()}
		}
		out = append(out, item{videoBody(h.Video), reviewsBody(h.Rejections), reviewsBody(h.Doubts), h.HeldReason,
			reports{by, h.Reports.Notes}, audit})
	}
	writeJSON(w, http.StatusOK, map[string]any{"videos": out})
}

// moderate serves a moderation write: the body's reason, the caller and
// the role their route matched.
func (s *Server) moderate(do func(context.Context, curation.Moderation, string) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Reason string `json:"reason"`
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
		if err := do(r.Context(), m, r.PathValue("id")); err != nil {
			s.fail(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// decideDoubt serves a moderator's decision on a video a curator's doubt
// holds: the body's decision, theme, band and reason, the caller and the
// role their route matched.
func (s *Server) decideDoubt(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Decision   string `json:"decision"`
		Theme      string `json:"theme"`
		MinAgeBand string `json:"min_age_band"`
		Reason     string `json:"reason"`
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
	d := curation.DoubtDecision{Decision: curation.Decision(in.Decision), Theme: in.Theme, MinAgeBand: family.AgeBand(in.MinAgeBand)}
	if err := s.Curation.DecideDoubt(r.Context(), m, r.PathValue("id"), d); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
