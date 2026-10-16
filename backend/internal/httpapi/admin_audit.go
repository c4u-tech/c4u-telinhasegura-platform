package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// adminAuditLog pages the staff actions, newest first, in the
// next_offset shape of the curation queue.
func (s *Server) adminAuditLog(w http.ResponseWriter, r *http.Request) {
	offset, err := offsetParam(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	page, err := s.Staff.AuditLog(r.Context(), offset)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"actions": auditActionsBody(page.Actions), "next_offset": page.NextOffset})
}

// adminMetrics answers each total, or null below staff.SuppressedBelow.
func (s *Server) adminMetrics(w http.ResponseWriter, r *http.Request) {
	m, err := s.Staff.Metrics(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accounts":         m.Accounts,
		"families":         m.Families,
		"minors":           m.Minors,
		"active_devices":   m.ActiveDevices,
		"published_videos": m.PublishedVideos,
		"published_packs":  m.PublishedPacks,
		"reports_7d":       m.Reports7d,
		"suppressed_below": staff.SuppressedBelow,
	})
}
