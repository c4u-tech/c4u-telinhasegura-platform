package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// checklist serves the list of questions every review answers. Curators
// answer it; moderators and admins read it to word what curators marked.
// It carries the length from which the long-video questions are asked and
// the longest a video may run for the youngest age band.
func (s *Server) checklist(w http.ResponseWriter, _ *http.Request) {
	type itemOut struct {
		ID       string `json:"id"`
		Text     string `json:"text"`
		Rule     string `json:"rule"`
		LongOnly bool   `json:"long_only,omitempty"`
	}
	type groupOut struct {
		ID    string    `json:"id"`
		Title string    `json:"title"`
		Items []itemOut `json:"items"`
	}
	groups := []groupOut{}
	for _, g := range curation.Checklist() {
		out := groupOut{ID: g.ID, Title: g.Title, Items: []itemOut{}}
		for _, it := range g.Items {
			out.Items = append(out.Items, itemOut{it.ID, it.Text, string(it.Rule), it.LongOnly})
		}
		groups = append(groups, out)
	}
	longFrom, youngestMax := s.Curation.LengthLimits()
	writeJSON(w, http.StatusOK, map[string]any{
		"version":              curation.ChecklistVersion,
		"long_from_seconds":    int(longFrom / time.Second),
		"youngest_max_seconds": int(youngestMax / time.Second),
		"groups":               groups,
	})
}
