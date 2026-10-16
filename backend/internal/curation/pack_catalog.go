package curation

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// KidPack is what a child's row shows of a pack: its playable videos in
// position order and a cover among them. No provenance, composer, theme
// or band.
type KidPack struct {
	ID           string
	Title        string // for screen readers; never drawn on a child screen
	CoverVideoID string
	Videos       []KidVideo
}

// servedPack is a pack a child gets today: every approved video of its
// published round in position order, each marked playable or not.
type servedPack struct {
	id, title, cover string
	composerRole     DisplayRole
	round            int // the published round
	lastReviewedAt   *time.Time
	videos           []servedVideo
}

type servedVideo struct {
	video    KidVideo
	playable bool
}

// coverOf is the composition's cover when the child may play it, else
// the first playable video.
func (p servedPack) coverOf() string {
	first := ""
	for _, v := range p.videos {
		if !v.playable {
			continue
		}
		if v.video.ID == p.cover {
			return p.cover
		}
		if first == "" {
			first = v.video.ID
		}
	}
	return first
}

// packsFor chooses the packs child c gets today. A pack
// is kept when it is approved, every approved video of its published
// round is within the child's band (rank), and at least two of them are
// playable: eligible for the child (approved, in band, not hidden, not
// reported by the family). Videos that are not approved drop out of the
// pack without blocking the band, and come back in place once approved
// again. A video with no band is out of every band: it blocks the pack
// rather than letting it through (bool_and skips NULLs). At most
// PackRowSize packs, ordered by (child, day, pack), the day in loc, the
// family's zone, as the shelves are. The guardian's view reads through
// here too, so the two cannot disagree.
func (s *Service) packsFor(ctx context.Context, q querier, c Child, rank int, loc *time.Location) ([]servedPack, error) {
	seed := c.MinorID + "/" + s.now().In(loc).Format(time.DateOnly)
	rows, err := q.Query(ctx, `WITH items AS (
			SELECT p.id AS pack_id, p.published_round, p.last_reviewed_at, pr.title AS pack_title, pr.cover_video_id,
				pr.composer_role, it.position, v.id AS video_id, v.title, v.duration_seconds,
				coalesce((`+bandRankSQL+` <= $3), false) AS in_band, coalesce((`+eligible+`), false) AS playable
			FROM packs p
			JOIN pack_rounds pr ON pr.pack_id = p.id AND pr.round = p.published_round
			JOIN pack_items it ON it.pack_id = p.id AND it.round = p.published_round
			JOIN videos v ON v.id = it.video_id
			WHERE p.state = 'approved' AND v.state = 'approved'
		), shown AS (
			SELECT pack_id FROM items GROUP BY pack_id
			HAVING bool_and(in_band) AND count(*) FILTER (WHERE playable) >= 2
			ORDER BY md5($4 || pack_id::text), pack_id LIMIT $5
		)
		SELECT items.pack_id::text, pack_title, cover_video_id::text, composer_role, published_round, last_reviewed_at,
			video_id::text, title, duration_seconds, playable
		FROM items JOIN shown USING (pack_id)
		ORDER BY md5($4 || items.pack_id::text), items.pack_id, position`,
		c.MinorID, c.FamilyID, rank, seed, s.d.PackRowSize)
	if err != nil {
		return nil, err
	}
	out := []servedPack{}
	var packID, title, cover, role string
	var round int
	var last *time.Time
	var v KidVideo
	var playable bool
	_, err = pgx.ForEachRow(rows, []any{&packID, &title, &cover, &role, &round, &last, &v.ID, &v.Title, &v.DurationSeconds, &playable},
		func() error {
			if n := len(out); n == 0 || out[n-1].id != packID {
				out = append(out, servedPack{id: packID, title: title, cover: cover, composerRole: DisplayRole(role),
					round: round, lastReviewedAt: utcp(last)})
			}
			out[len(out)-1].videos = append(out[len(out)-1].videos, servedVideo{video: v, playable: playable})
			return nil
		})
	return out, err
}

// KidPacks returns the packs the child gets today, each with its
// playable videos only. None is an empty, non-nil list.
// A child or family that is gone is ErrProfileGone, as for the shelves.
func (s *Service) KidPacks(ctx context.Context, c Child, loc *time.Location) ([]KidPack, error) {
	rank, err := childBand(ctx, s.d.Pool, c)
	if err != nil {
		return nil, err
	}
	served, err := s.packsFor(ctx, s.d.Pool, c, rank, loc)
	if err != nil {
		return nil, err
	}
	out := make([]KidPack, 0, len(served))
	for _, p := range served {
		k := KidPack{ID: p.id, Title: p.title, CoverVideoID: p.coverOf(), Videos: []KidVideo{}}
		for _, v := range p.videos {
			if v.playable {
				k.Videos = append(k.Videos, v.video)
			}
		}
		out = append(out, k)
	}
	return out, nil
}

// FamilyPackVideo is an approved video of a pack as a guardian sees it.
// Hidden marks a video skipped for the child: hidden for them, or
// reported by the family.
type FamilyPackVideo struct {
	Video  KidVideo
	Hidden bool
}

// FamilyPack is a pack one child gets today, as a guardian sees it: every
// approved video of the published round in position order, the
// composer's displayed role, and the published round's provenance.
// Displayed roles only, never accounts.
type FamilyPack struct {
	ID           string
	Title        string
	CoverVideoID string
	ComposerRole DisplayRole
	Videos       []FamilyPackVideo
	Provenance   Provenance
}

// FamilyPacks returns exactly the packs KidPacks serves one of the
// caller's children today, in one snapshot. A minor outside the caller's
// family is ErrNotFound, as for the rest of the family catalogue.
func (s *Service) FamilyPacks(ctx context.Context, accountID, minorID string, loc *time.Location) ([]FamilyPack, error) {
	tx, err := s.d.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	c, rank, err := guardedChild(ctx, tx, accountID, minorID)
	if err != nil {
		return nil, err
	}
	served, err := s.packsFor(ctx, tx, c, rank, loc)
	if err != nil {
		return nil, err
	}
	out := make([]FamilyPack, 0, len(served))
	for _, p := range served {
		prov, err := roundProvenance(ctx, tx, packLedger, p.id, p.round, p.lastReviewedAt)
		if err != nil {
			return nil, err
		}
		fp := FamilyPack{ID: p.id, Title: p.title, CoverVideoID: p.coverOf(), ComposerRole: p.composerRole,
			Videos: make([]FamilyPackVideo, 0, len(p.videos)), Provenance: *prov}
		for _, v := range p.videos {
			fp.Videos = append(fp.Videos, FamilyPackVideo{Video: v.video, Hidden: !v.playable})
		}
		out = append(out, fp)
	}
	return out, tx.Commit(ctx)
}
