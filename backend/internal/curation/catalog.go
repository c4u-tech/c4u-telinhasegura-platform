package curation

import (
	"context"
	"errors"
	"time"
	_ "time/tzdata" // the rotation's zone loads on a host without zoneinfo

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/jackc/pgx/v5"
)

// Child is a child principal as curation needs it: the family and the
// child it acts for (parental.Principal). An empty field means
// the child or its family is gone.
type Child struct {
	FamilyID string
	MinorID  string
}

// KidVideo is what a child's shelf shows of a video: no provenance, no
// channel, no band.
type KidVideo struct {
	ID              string
	Title           string
	DurationSeconds int
}

// Shelf is one theme's videos for a child, at most Deps.ShelfSize.
type Shelf struct {
	Theme  string
	Videos []KidVideo
}

// bandRankSQL is bandRank over videos v.
const bandRankSQL = `CASE v.min_age_band WHEN 'ate-4' THEN 1 WHEN '5-8' THEN 2 WHEN '9-12' THEN 3 END`

// eligible is the condition of a video a child may see, over
// videos v, with $1 the child, $2 its family and $3 its band's rank.
// Every child-facing read uses it, so they cannot disagree.
const eligible = `v.state = 'approved' AND ` + bandRankSQL + ` <= $3
	AND NOT EXISTS (SELECT 1 FROM video_hides h WHERE h.minor_id = $1::uuid AND h.video_id = v.id)
	AND NOT EXISTS (SELECT 1 FROM video_reports r WHERE r.family_id = $2::uuid AND r.video_id = v.id)`

// childBand is the rank of the child's band, read on every request so a
// changed band applies at once. A child or family that
// is gone, or a child of another family, is ErrProfileGone.
func childBand(ctx context.Context, q querier, c Child) (int, error) {
	if !validID(c.FamilyID) || !validID(c.MinorID) {
		return 0, ErrProfileGone
	}
	var band string
	err := q.QueryRow(ctx, `SELECT age_band FROM minors WHERE id = $1::uuid AND family_id = $2::uuid`,
		c.MinorID, c.FamilyID).Scan(&band)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrProfileGone
	}
	return bandRank(family.AgeBand(band)), err
}

// Catalog returns the child's shelves: the themes with eligible videos,
// in the fixed order, each with at most ShelfSize videos chosen by a
// deterministic order of (child, day, video), the day in loc, the
// family's zone.
func (s *Service) Catalog(ctx context.Context, c Child, loc *time.Location) ([]Shelf, error) {
	rank, err := childBand(ctx, s.d.Pool, c)
	if err != nil {
		return nil, err
	}
	seed := c.MinorID + "/" + s.now().In(loc).Format(time.DateOnly)
	rows, err := s.d.Pool.Query(ctx, `SELECT theme, id, title, duration_seconds FROM (
			SELECT v.theme, v.id::text AS id, v.title, v.duration_seconds,
				row_number() OVER (PARTITION BY v.theme ORDER BY md5($4 || v.id::text), v.id) AS n
			FROM videos v WHERE `+eligible+`) x
		WHERE n <= $5 ORDER BY n`, c.MinorID, c.FamilyID, rank, seed, s.d.ShelfSize)
	if err != nil {
		return nil, err
	}
	byTheme := map[string][]KidVideo{}
	var theme string
	var v KidVideo
	if _, err := pgx.ForEachRow(rows, []any{&theme, &v.ID, &v.Title, &v.DurationSeconds}, func() error {
		byTheme[theme] = append(byTheme[theme], v)
		return nil
	}); err != nil {
		return nil, err
	}
	shelves := []Shelf{}
	for _, t := range themes {
		if vs := byTheme[t]; len(vs) > 0 {
			shelves = append(shelves, Shelf{Theme: t, Videos: vs})
		}
	}
	return shelves, nil
}

// eligibleVideo is the video when the child may see it. Anything else,
// a malformed ID included, is ErrVideoNotAllowed, so the answer never
// says why.
func (s *Service) eligibleVideo(ctx context.Context, c Child, videoID string) (Video, error) {
	rank, err := childBand(ctx, s.d.Pool, c)
	if err != nil {
		return Video{}, err
	}
	if !validID(videoID) {
		return Video{}, ErrVideoNotAllowed
	}
	v, err := scanVideo(s.d.Pool.QueryRow(ctx, `SELECT `+videoCols+` FROM videos v WHERE v.id = $4::uuid AND `+eligible,
		c.MinorID, c.FamilyID, rank, videoID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Video{}, ErrVideoNotAllowed
	}
	return v, err
}

// Play re-checks a video before the child plays it and answers its
// YouTube ID. It stores nothing: plays storage arrives with screen time.
func (s *Service) Play(ctx context.Context, c Child, videoID string) (string, error) {
	v, err := s.eligibleVideo(ctx, c, videoID)
	if err != nil {
		return "", err
	}
	return v.YouTubeID, nil
}
