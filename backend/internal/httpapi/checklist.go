package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// checklist serves the list of questions every review answers. Curators
// answer it; moderators and admins read it to word what curators marked.
func (s *Server) checklist(w http.ResponseWriter, _ *http.Request) {
	type itemOut struct {
		ID       string `json:"id"`
		Text     string `json:"text"`
		Rule     string `json:"rule"`
		Positive bool   `json:"positive"`
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
			out.Items = append(out.Items, itemOut{it.ID, it.Text, string(it.Rule), it.Positive})
		}
		groups = append(groups, out)
	}
	writeJSON(w, http.StatusOK, map[string]any{"version": curation.ChecklistVersion, "groups": groups})
}
