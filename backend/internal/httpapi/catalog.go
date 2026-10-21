package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// kidOf is the request's child principal as curation needs it.
func kidOf(r *http.Request) curation.Child {
	p := child(r)
	return curation.Child{FamilyID: p.FamilyID, MinorID: p.MinorID}
}

// kidVideoOut is what a child sees of a video, on a shelf or in a pack:
// no provenance, channel or band.
type kidVideoOut struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	DurationSeconds int    `json:"duration_seconds"`
}

type kidPackOut struct {
	ID           string        `json:"id"`
	Title        string        `json:"title"`
	CoverVideoID string        `json:"cover_video_id"`
	Videos       []kidVideoOut `json:"videos"`
}

func kidPacksBody(ps []curation.KidPack) []kidPackOut {
	out := make([]kidPackOut, 0, len(ps))
	for _, p := range ps {
		vs := make([]kidVideoOut, 0, len(p.Videos))
		for _, v := range p.Videos {
			vs = append(vs, kidVideoOut{v.ID, v.Title, v.DurationSeconds})
		}
		out = append(out, kidPackOut{p.ID, p.Title, p.CoverVideoID, vs})
	}
	return out
}

type familyPackVideoOut struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	DurationSeconds int    `json:"duration_seconds"`
	Hidden          bool   `json:"hidden"`
}

// familyPackOut carries displayed roles, never accounts: a family never
// learns who curated a pack.
type familyPackOut struct {
	ID           string               `json:"id"`
	Title        string               `json:"title"`
	CoverVideoID string               `json:"cover_video_id"`
	ComposerRole string               `json:"composer_role"`
	Videos       []familyPackVideoOut `json:"videos"`
	Provenance   any                  `json:"provenance"`
}

func familyPacksBody(ps []curation.FamilyPack) []familyPackOut {
	out := make([]familyPackOut, 0, len(ps))
	for _, p := range ps {
		vs := make([]familyPackVideoOut, 0, len(p.Videos))
		for _, v := range p.Videos {
			vs = append(vs, familyPackVideoOut{v.Video.ID, v.Video.Title, v.Video.DurationSeconds, v.Hidden})
		}
		out = append(out, familyPackOut{p.ID, p.Title, p.CoverVideoID, string(p.ComposerRole), vs, provenanceBody(&p.Provenance)})
	}
	return out
}

// childCatalog answers the child's shelves and packs, with no
// provenance, channel or band.
func (s *Server) childCatalog(w http.ResponseWriter, r *http.Request) {
	loc, err := s.ScreenTime.Zone(r.Context(), stOf(r))
	if err != nil {
		s.fail(w, err)
		return
	}
	shelves, err := s.Curation.Catalog(r.Context(), kidOf(r), loc)
	if err != nil {
		s.fail(w, err)
		return
	}
	type shelf struct {
		Theme  string        `json:"theme"`
		Videos []kidVideoOut `json:"videos"`
	}
	out := make([]shelf, 0, len(shelves))
	for _, sh := range shelves {
		vs := make([]kidVideoOut, 0, len(sh.Videos))
		for _, v := range sh.Videos {
			vs = append(vs, kidVideoOut{v.ID, v.Title, v.DurationSeconds})
		}
		out = append(out, shelf{sh.Theme, vs})
	}
	packs, err := s.Curation.KidPacks(r.Context(), kidOf(r), loc)
	if err != nil {
		s.fail(w, err)
		return
	}
	t, err := s.ScreenTime.Time(r.Context(), stOf(r))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"themes": out, "packs": kidPacksBody(packs), "time": timeBody(t)})
}

// writeThumb sends a cached thumbnail, a JPEG the fetch checked; the
// browser may keep it a day, never a shared cache.
func writeThumb(w http.ResponseWriter, b []byte) {
	h := w.Header()
	h.Set("Content-Type", "image/jpeg")
	h.Set("Cache-Control", "private, max-age=86400")
	h.Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(b)
}

func (s *Server) childThumb(w http.ResponseWriter, r *http.Request) {
	b, err := s.Curation.ChildThumbnail(r.Context(), kidOf(r), r.PathValue("video"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeThumb(w, b)
}

// play re-checks a video (curation: may this child see it?), then opens
// a play (screentime: may they watch now?).
func (s *Server) play(w http.ResponseWriter, r *http.Request) {
	var in struct {
		VideoID string `json:"video_id"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	youtubeID, err := s.Curation.Play(r.Context(), kidOf(r), in.VideoID)
	if err != nil {
		s.fail(w, err)
		return
	}
	p, err := s.ScreenTime.Open(r.Context(), stOf(r), in.VideoID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"play_id": p.ID, "youtube_id": youtubeID,
		"remaining_seconds": int(p.Time.Remaining / time.Second)})
}

// unavailable answers 202 for any video the child may see: the outcome
// of the check is the server's business.
func (s *Server) unavailable(w http.ResponseWriter, r *http.Request) {
	if err := s.Curation.ReportUnavailable(r.Context(), kidOf(r), r.PathValue("id")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

// minorCatalog lists what one of the caller's children can see, with
// provenance and hides. The packs ride the first page only, on
// the family's day, as the child gets them.
func (s *Server) minorCatalog(w http.ResponseWriter, r *http.Request) {
	offset, err := offsetParam(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	account, minor := current(r).AccountID, r.PathValue("id")
	items, more, err := s.Curation.FamilyCatalog(r.Context(), account, minor, offset)
	if err != nil {
		s.fail(w, err)
		return
	}
	type item struct {
		ID              string `json:"id"`
		YouTubeID       string `json:"youtube_id"`
		Title           string `json:"title"`
		ChannelTitle    string `json:"channel_title"`
		DurationSeconds int    `json:"duration_seconds"`
		Theme           string `json:"theme"`
		MinAgeBand      string `json:"min_age_band"`
		Hidden          bool   `json:"hidden"`
		Provenance      any    `json:"provenance"`
	}
	out := make([]item, 0, len(items))
	for _, x := range items {
		v := x.Video
		out = append(out, item{v.ID, v.YouTubeID, v.Title, v.ChannelTitle, v.DurationSeconds, v.Theme, string(v.MinAgeBand), x.Hidden,
			provenanceBody(x.Provenance)})
	}
	packs := []familyPackOut{}
	if offset == 0 {
		loc, err := s.ScreenTime.GuardianZone(r.Context(), account, minor)
		if err != nil {
			s.fail(w, err)
			return
		}
		fp, err := s.Curation.FamilyPacks(r.Context(), account, minor, loc)
		if err != nil {
			s.fail(w, err)
			return
		}
		packs = familyPacksBody(fp)
	}
	writeJSON(w, http.StatusOK, map[string]any{"videos": out, "packs": packs, "has_more": more})
}

func (s *Server) hide(w http.ResponseWriter, r *http.Request) {
	if err := s.Curation.Hide(r.Context(), current(r).AccountID, r.PathValue("id"), r.PathValue("video")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) unhide(w http.ResponseWriter, r *http.Request) {
	if err := s.Curation.Unhide(r.Context(), current(r).AccountID, r.PathValue("id"), r.PathValue("video")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// report answers 201 for a new report and 200 when the family's earlier
// one stands. The family and the author come from the
// session, never from the body.
func (s *Server) report(w http.ResponseWriter, r *http.Request) {
	var in struct {
		VideoID string `json:"video_id"`
		Reason  string `json:"reason"`
		Note    string `json:"note"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	created, err := s.Curation.Report(r.Context(), current(r).AccountID, in.VideoID, curation.ReportReason(in.Reason), in.Note)
	if err != nil {
		s.fail(w, err)
		return
	}
	if created {
		w.WriteHeader(http.StatusCreated)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (s *Server) familyThumb(w http.ResponseWriter, r *http.Request) {
	b, err := s.Curation.FamilyThumbnail(r.Context(), r.PathValue("video"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeThumb(w, b)
}
