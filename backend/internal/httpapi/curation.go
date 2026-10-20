package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func (s *Server) themes(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"themes": curation.Themes()})
}

type videoOut struct {
	ID              string     `json:"id"`
	YouTubeID       string     `json:"youtube_id"`
	Title           string     `json:"title"`
	ChannelID       string     `json:"channel_id"`
	ChannelTitle    string     `json:"channel_title"`
	DurationSeconds int        `json:"duration_seconds"`
	State           string     `json:"state"`
	Round           int        `json:"round"`
	Theme           *string    `json:"theme"`
	MinAgeBand      *string    `json:"min_age_band"`
	LastReviewedAt  *time.Time `json:"last_reviewed_at"`
	ReviewDueAt     *time.Time `json:"review_due_at"`
	CreatedAt       time.Time  `json:"created_at"`
}

func videoBody(v curation.Video) videoOut {
	return videoOut{ID: v.ID, YouTubeID: v.YouTubeID, Title: v.Title, ChannelID: v.ChannelID, ChannelTitle: v.ChannelTitle,
		DurationSeconds: v.DurationSeconds, State: string(v.State), Round: v.Round, Theme: orNull(v.Theme),
		MinAgeBand: orNull(string(v.MinAgeBand)), LastReviewedAt: v.LastReviewedAt, ReviewDueAt: v.ReviewDueAt, CreatedAt: v.CreatedAt}
}

// reviewOut never names the reviewer's account.
type reviewOut struct {
	DisplayRole      string            `json:"display_role"`
	Decision         string            `json:"decision"`
	Theme            *string           `json:"theme"`
	MinAgeBand       *string           `json:"min_age_band"`
	Reason           *string           `json:"reason"`
	ChecklistVersion *string           `json:"checklist_version"` // null before the list
	Answers          map[string]string `json:"answers"`           // an approval's or a doubt's
	FailedItems      []string          `json:"failed_items"`      // a rejection's
	ReviewedAt       time.Time         `json:"reviewed_at"`
}

func reviewBody(x curation.Review) reviewOut {
	var answers map[string]string
	if x.Answers != nil {
		answers = make(map[string]string, len(x.Answers))
		for id, a := range x.Answers {
			answers[id] = string(a)
		}
	}
	return reviewOut{DisplayRole: string(x.DisplayRole), Decision: string(x.Decision), Theme: orNull(x.Theme),
		MinAgeBand: orNull(string(x.MinAgeBand)), Reason: orNull(x.Reason), ChecklistVersion: orNull(x.ChecklistVersion),
		Answers: answers, FailedItems: x.FailedItems, ReviewedAt: x.ReviewedAt.UTC()}
}

func reviewsBody(xs []curation.Review) []reviewOut {
	out := make([]reviewOut, 0, len(xs))
	for _, x := range xs {
		out = append(out, reviewBody(x))
	}
	return out
}

// orNull is s, or JSON null when it is empty.
func orNull(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func (s *Server) suggest(w http.ResponseWriter, r *http.Request) {
	var in struct {
		URL string `json:"url"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	v, created, err := s.Curation.Suggest(r.Context(), current(r).AccountID, in.URL)
	if err != nil {
		s.fail(w, err)
		return
	}
	status := http.StatusOK // already in the catalogue
	if created {
		status = http.StatusCreated
	}
	writeJSON(w, status, videoBody(v))
}

func (s *Server) listSuggestions(w http.ResponseWriter, r *http.Request) {
	list, err := s.Curation.Suggestions(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	type item struct {
		VideoID      string    `json:"video_id"`
		Title        string    `json:"title"`
		ChannelTitle string    `json:"channel_title"`
		State        string    `json:"state"`
		SuggestedAt  time.Time `json:"suggested_at"`
	}
	out := make([]item, 0, len(list))
	for _, x := range list {
		out = append(out, item{x.Video.ID, x.Video.Title, x.Video.ChannelTitle, string(x.Video.State), x.SuggestedAt})
	}
	writeJSON(w, http.StatusOK, map[string]any{"suggestions": out})
}

// queue pages by offset. Offsets shift as the caller's reviewed videos
// leave their queue, so a client refetches from offset 0 after reviewing
// rather than resuming at next_offset.
func (s *Server) queue(w http.ResponseWriter, r *http.Request) {
	offset, err := offsetParam(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	items, more, err := s.Curation.Queue(r.Context(), current(r).AccountID, offset)
	if err != nil {
		s.fail(w, err)
		return
	}
	type item struct {
		videoOut
		Revisit bool `json:"revisit"`
	}
	out := make([]item, 0, len(items))
	for _, it := range items {
		out = append(out, item{videoBody(it.Video), it.Revisit})
	}
	var next *int // null on the last page
	if more {
		n := offset + len(items)
		next = &n
	}
	writeJSON(w, http.StatusOK, map[string]any{"videos": out, "next_offset": next})
}

// approvedVideos pages the approved videos of one theme for a curator
// composing a pack; paged like the queue.
func (s *Server) approvedVideos(w http.ResponseWriter, r *http.Request) {
	offset, err := offsetParam(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	vs, more, err := s.Curation.ApprovedVideos(r.Context(), r.URL.Query().Get("theme"), offset)
	if err != nil {
		s.fail(w, err)
		return
	}
	out := make([]videoOut, 0, len(vs))
	for _, v := range vs {
		out = append(out, videoBody(v))
	}
	var next *int // null on the last page
	if more {
		n := offset + len(vs)
		next = &n
	}
	writeJSON(w, http.StatusOK, map[string]any{"videos": out, "next_offset": next})
}

func (s *Server) curationVideo(w http.ResponseWriter, r *http.Request) {
	d, err := s.Curation.VideoDetail(r.Context(), r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"video": videoBody(d.Video), "reviews": reviewsBody(d.Reviews),
		"provenance": provenanceBody(d.Provenance)})
}

func (s *Server) review(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Decision         string            `json:"decision"`
		Theme            string            `json:"theme"`
		MinAgeBand       string            `json:"min_age_band"`
		ChecklistVersion string            `json:"checklist_version"`
		Answers          map[string]string `json:"answers"`
		FailedItems      []string          `json:"failed_items"`
		Note             string            `json:"note"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	var answers map[string]curation.Answer
	if in.Answers != nil {
		answers = make(map[string]curation.Answer, len(in.Answers))
		for id, a := range in.Answers {
			answers[id] = curation.Answer(a)
		}
	}
	rv, state, err := s.Curation.Review(r.Context(), current(r).AccountID, r.PathValue("id"), curation.ReviewInput{
		Decision: curation.Decision(in.Decision), Theme: in.Theme, MinAgeBand: family.AgeBand(in.MinAgeBand),
		ChecklistVersion: in.ChecklistVersion, Answers: answers, FailedItems: in.FailedItems, Note: in.Note})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"review": reviewBody(rv), "video_state": string(state)})
}

// provenanceBody is a video's provenance by displayed role, or null for
// a video never published. Reviewer accounts never
// appear.
func provenanceBody(p *curation.Provenance) any {
	if p == nil {
		return nil
	}
	approvals := map[string]int{}
	for role, n := range p.Approvals {
		approvals[string(role)] = n
	}
	return map[string]any{"approvals": approvals, "last_reviewed_at": p.LastReviewedAt.UTC()}
}
