package httpapi

import (
	"net/http"
	"strconv"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

type packVideoOut struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	ChannelTitle    string `json:"channel_title"`
	DurationSeconds int    `json:"duration_seconds"`
	State           string `json:"state"`
}

// packReviewOut never names the reviewer's account (packs, Security).
type packReviewOut struct {
	DisplayRole string    `json:"display_role"`
	Decision    string    `json:"decision"`
	Reason      *string   `json:"reason"`
	ReviewedAt  time.Time `json:"reviewed_at"`
}

type packOut struct {
	ID           string          `json:"id"`
	State        string          `json:"state"`
	Round        int             `json:"round"`
	Theme        *string         `json:"theme"`
	Title        string          `json:"title"`
	CoverVideoID string          `json:"cover_video_id"`
	ComposerRole string          `json:"composer_role"`
	Videos       []packVideoOut  `json:"videos"`
	TotalSeconds int             `json:"total_seconds"`
	Reviews      []packReviewOut `json:"reviews"`
	Reviewable   bool            `json:"reviewable"`
	Provenance   any             `json:"provenance"`
}

func packReviewBody(x curation.PackReview) packReviewOut {
	return packReviewOut{string(x.DisplayRole), string(x.Decision), orNull(x.Reason), x.ReviewedAt.UTC()}
}

// packBody is the pack detail the API answers.
func packBody(p curation.Pack) packOut {
	out := packOut{ID: p.ID, State: string(p.State), Round: p.Round, Theme: orNull(p.Theme), Title: p.Title,
		CoverVideoID: p.CoverVideoID, ComposerRole: string(p.ComposerRole), Videos: make([]packVideoOut, 0, len(p.Videos)),
		TotalSeconds: p.TotalSeconds, Reviews: make([]packReviewOut, 0, len(p.Reviews)), Reviewable: p.Reviewable,
		Provenance: provenanceBody(p.Provenance)}
	for _, v := range p.Videos {
		out.Videos = append(out.Videos, packVideoOut{v.ID, v.Title, v.ChannelTitle, v.DurationSeconds, string(v.State)})
	}
	for _, r := range p.Reviews {
		out.Reviews = append(out.Reviews, packReviewBody(r))
	}
	return out
}

// packIn is the composition body of POST and PUT (packs, Contract).
type packIn struct {
	Title        string   `json:"title"`
	VideoIDs     []string `json:"video_ids"`
	CoverVideoID string   `json:"cover_video_id"`
	Theme        string   `json:"theme"`
}

func (in packIn) input() curation.PackInput {
	return curation.PackInput{Title: in.Title, VideoIDs: in.VideoIDs, CoverVideoID: in.CoverVideoID, Theme: in.Theme}
}

// offsetParam reads ?offset=, 0 when absent. Anything but an integer is a
// validation problem; the services refuse a negative one.
func offsetParam(r *http.Request) (int, error) {
	v := r.URL.Query().Get("offset")
	if v == "" {
		return 0, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return 0, curation.ErrValidation
	}
	return n, nil
}

func (s *Server) composePack(w http.ResponseWriter, r *http.Request) {
	var in packIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	p, err := s.Curation.Compose(r.Context(), current(r).AccountID, in.input())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, packBody(p))
}

func (s *Server) recomposePack(w http.ResponseWriter, r *http.Request) {
	var in packIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	p, err := s.Curation.Recompose(r.Context(), current(r).AccountID, r.PathValue("id"), in.input())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, packBody(p))
}

// listPacks pages by offset; like the video queue, a client refetches from
// offset 0 after reviewing.
func (s *Server) listPacks(w http.ResponseWriter, r *http.Request) {
	offset, err := offsetParam(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	items, more, err := s.Curation.PackQueue(r.Context(), current(r).AccountID, offset)
	if err != nil {
		s.fail(w, err)
		return
	}
	writePacks(w, items, more)
}

// writePacks writes a page of pack details.
func writePacks(w http.ResponseWriter, items []curation.Pack, more bool) {
	out := make([]packOut, 0, len(items))
	for _, p := range items {
		out = append(out, packBody(p))
	}
	writeJSON(w, http.StatusOK, map[string]any{"packs": out, "has_more": more})
}

// packLimits states the composition rules the composer shows against.
func (s *Server) packLimits(w http.ResponseWriter, r *http.Request) {
	l := s.Curation.PackLimits()
	writeJSON(w, http.StatusOK, map[string]int{"min_videos": l.MinVideos, "max_videos": l.MaxVideos,
		"max_seconds": int(l.MaxDuration / time.Second)})
}

func (s *Server) curationPack(w http.ResponseWriter, r *http.Request) {
	p, err := s.Curation.PackDetail(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, packBody(p))
}

func (s *Server) reviewPack(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	rv, state, err := s.Curation.ReviewPack(r.Context(), current(r).AccountID, r.PathValue("id"),
		curation.PackReviewInput{Decision: curation.Decision(in.Decision), Reason: in.Reason})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"review": packReviewBody(rv), "state": string(state)})
}

func (s *Server) removePack(w http.ResponseWriter, r *http.Request) {
	if err := s.Curation.RemovePack(r.Context(), current(r).AccountID, r.PathValue("id")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// adminPacks lets an admin who is not a curator find a pack to remove.
func (s *Server) adminPacks(w http.ResponseWriter, r *http.Request) {
	offset, err := offsetParam(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	items, more, err := s.Curation.AdminPacks(r.Context(), current(r).AccountID, offset)
	if err != nil {
		s.fail(w, err)
		return
	}
	writePacks(w, items, more)
}

func (s *Server) adminPack(w http.ResponseWriter, r *http.Request) {
	p, err := s.Curation.AdminPack(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, packBody(p))
}
