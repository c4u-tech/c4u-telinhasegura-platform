package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// draftOut is a curator's own unfinished review of a video.
type draftOut struct {
	ChecklistVersion string            `json:"checklist_version"`
	Answers          map[string]string `json:"answers"`
	Theme            *string           `json:"theme"`
	MinAgeBand       *string           `json:"min_age_band"`
	Note             *string           `json:"note"`
	BeganAt          time.Time         `json:"began_at"`
	PlayedToEndAt    *time.Time        `json:"played_to_end_at"`
}

func draftBody(d curation.Draft) draftOut {
	answers := make(map[string]string, len(d.Answers))
	for id, a := range d.Answers {
		answers[id] = string(a)
	}
	return draftOut{ChecklistVersion: d.ChecklistVersion, Answers: answers, Theme: orNull(d.Theme),
		MinAgeBand: orNull(string(d.MinAgeBand)), Note: orNull(d.Note), BeganAt: d.BeganAt.UTC(), PlayedToEndAt: d.PlayedToEndAt}
}

func (s *Server) reviewDraft(w http.ResponseWriter, r *http.Request) {
	d, err := s.Curation.Draft(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	var out any
	if d != nil {
		out = draftBody(*d)
	}
	writeJSON(w, http.StatusOK, map[string]any{"draft": out})
}

func (s *Server) saveReviewDraft(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ChecklistVersion string            `json:"checklist_version"`
		Answers          map[string]string `json:"answers"`
		Theme            string            `json:"theme"`
		MinAgeBand       string            `json:"min_age_band"`
		Note             string            `json:"note"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	answers := make(map[string]curation.Answer, len(in.Answers))
	for id, a := range in.Answers {
		answers[id] = curation.Answer(a)
	}
	d, err := s.Curation.SaveDraft(r.Context(), current(r).AccountID, r.PathValue("id"), curation.DraftInput{
		ChecklistVersion: in.ChecklistVersion, Answers: answers, Theme: in.Theme,
		MinAgeBand: family.AgeBand(in.MinAgeBand), Note: in.Note})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"draft": draftBody(d)})
}

func (s *Server) reviewDraftEnded(w http.ResponseWriter, r *http.Request) {
	d, err := s.Curation.DraftEnded(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"draft": draftBody(d)})
}
