package curation_test

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

var saoPaulo, _ = time.LoadLocation("America/Sao_Paulo")

type fixture struct {
	t      *testing.T
	svc    *curation.Service
	team   *staff.Service // the role writes curation reads
	deps   curation.Deps
	pool   *pgxpool.Pool
	audit  *audittest.Recorder
	source *curationtest.Fake
	thumbs *curationtest.Thumbs
	logs   *bytes.Buffer // every log line of the service
	now    time.Time
}

func newFixture(t *testing.T) *fixture {
	f := &fixture{
		t:      t,
		pool:   dbtest.New(t),
		audit:  &audittest.Recorder{},
		source: &curationtest.Fake{},
		thumbs: &curationtest.Thumbs{},
		logs:   &bytes.Buffer{},
		now:    time.Date(2026, 10, 4, 12, 0, 0, 0, time.UTC),
	}
	clock := func() time.Time { return f.now }
	f.deps = curation.Deps{
		Pool:              f.pool,
		Audit:             f.audit,
		Now:               clock,
		Source:            f.source,
		Thumbs:            f.thumbs,
		SuggestLimiter:    ratelimit.New(10, 24*time.Hour, clock),
		ReportLimiter:     ratelimit.New(20, 24*time.Hour, clock),
		ReportThreshold:   3,
		CheckVideoLimiter: ratelimit.New(1, time.Hour, clock),
		CheckChildLimiter: ratelimit.New(10, time.Hour, clock),
		MinApprovals:      2,
		MaxDuration:       20 * time.Minute,
		RevisitAfter:      180 * 24 * time.Hour,
		ShelfSize:         12,
		PackMaxDuration:   20 * time.Minute,
		PackRowSize:       6,
		Log:               slog.New(slog.NewTextHandler(f.logs, nil)),
	}
	f.svc = curation.NewService(f.deps)
	f.team = staff.NewService(staff.Deps{Pool: f.pool, Audit: f.audit, Now: clock})
	return f
}

// rebuild changes the deps and rebuilds the service under test.
func (f *fixture) rebuild(change func(*curation.Deps)) {
	change(&f.deps)
	f.svc = curation.NewService(f.deps)
}

func (f *fixture) exec(sql string, args ...any) {
	f.t.Helper()
	if _, err := f.pool.Exec(ctx, sql, args...); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

func (f *fixture) id(sql string, args ...any) string {
	f.t.Helper()
	var id string
	if err := f.pool.QueryRow(ctx, sql, args...).Scan(&id); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// account inserts a verified guardian account.
func (f *fixture) account(email string) string {
	f.t.Helper()
	return f.id(`INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $2, $2) RETURNING id::text`, email, f.now)
}

func (f *fixture) unverified(email string) string {
	f.t.Helper()
	return f.id(`INSERT INTO accounts (email, adult_declared_at, created_at) VALUES ($1, $2, $2) RETURNING id::text`, email, f.now)
}

// admin inserts an account and grants it the admin role, as the server
// command does.
func (f *fixture) admin(email string) string {
	f.t.Helper()
	id := f.account(email)
	if _, err := f.team.GrantAdmin(ctx, email); err != nil {
		f.t.Fatal(err)
	}
	return id
}

// curator inserts an account holding the curator role directly.
func (f *fixture) curator(email string, role curation.DisplayRole) string {
	f.t.Helper()
	id := f.account(email)
	f.exec(`INSERT INTO platform_roles (account_id, role, display_role, verified_professional, granted_at)
		VALUES ($1::uuid, 'curator', $2, $3, $4)`, id, string(role), role.Professional(), f.now)
	return id
}

// video inserts a pending video in round 1, queued now.
func (f *fixture) video(youtubeID string) string {
	f.t.Helper()
	return f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', 300, 'pending', $2, $2) RETURNING id::text`, youtubeID, f.now)
}

func (f *fixture) suggestedBy(accountID, videoID string) {
	f.t.Helper()
	f.exec(`INSERT INTO video_suggestions (video_id, account_id, suggested_at) VALUES ($1::uuid, $2::uuid, $3)`,
		videoID, accountID, f.now)
}

// audited counts the entries of event e, under any account.
func (f *fixture) audited(e audit.Event) int {
	n := 0
	for _, x := range f.audit.Entries {
		if x.Event == e {
			n++
		}
	}
	return n
}

// family inserts a family owned by a new verified account.
func (f *fixture) family(email string) (familyID, ownerID string) {
	f.t.Helper()
	ownerID = f.account(email)
	familyID = f.id(`INSERT INTO families (created_at) VALUES ($1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO family_members (family_id, account_id, role, joined_at) VALUES ($1::uuid, $2::uuid, 'owner', $3)`,
		familyID, ownerID, f.now)
	return familyID, ownerID
}

// join adds a new verified account to the family as a guardian.
func (f *fixture) join(familyID, email string) string {
	f.t.Helper()
	id := f.account(email)
	f.exec(`INSERT INTO family_members (family_id, account_id, role, joined_at) VALUES ($1::uuid, $2::uuid, 'guardian', $3)`,
		familyID, id, f.now)
	return id
}

// minor inserts a child of the family in band.
func (f *fixture) minor(familyID string, band family.AgeBand) curation.Child {
	f.t.Helper()
	id := f.id(`INSERT INTO minors (family_id, nickname, avatar, age_band, created_at, updated_at)
		VALUES ($1::uuid, 'Lia', 'fox', $2, $3, $3) RETURNING id::text`, familyID, string(band), f.now)
	return curation.Child{FamilyID: familyID, MinorID: id}
}

// published inserts an approved video in theme and band, titled
// "Vídeo <youtubeID>", whose published round 1 holds one mae-pai
// approval (its provenance).
func (f *fixture) published(youtubeID, theme string, band family.AgeBand) string {
	f.t.Helper()
	id := f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round, published_round,
		theme, min_age_band, last_reviewed_at, review_due_at, created_at, updated_at)
		VALUES ($1, 'Vídeo ' || $1, 'UC1', 'Canal', 300, 'approved', 2, 1, $2, $3, $4, $5, $4, $4) RETURNING id::text`,
		youtubeID, theme, string(band), f.now, f.now.Add(180*24*time.Hour))
	f.exec(`INSERT INTO video_reviews (video_id, round, curator_id, display_role, decision, theme, min_age_band, reviewed_at)
		VALUES ($1::uuid, 1, NULL, 'mae-pai', 'approve', $2, $3, $4)`, id, theme, string(band), f.now)
	return id
}

func (f *fixture) catalog(c curation.Child) []curation.Shelf {
	f.t.Helper()
	shelves, err := f.svc.Catalog(ctx, c, saoPaulo)
	if err != nil {
		f.t.Fatalf("catalog: %v", err)
	}
	return shelves
}

// nthID is a well-formed, distinct YouTube ID: "vid" and 8 digits.
func nthID(i int) string { return fmt.Sprintf("vid%08d", i) }

// families inserts n families, each with an owner, and returns their
// IDs and owners.
func (f *fixture) families(n int) (ids, owners []string) {
	f.t.Helper()
	for i := range n {
		id, owner := f.family(fmt.Sprintf("dono%d@example.com", i))
		ids, owners = append(ids, id), append(owners, owner)
	}
	return ids, owners
}

// approvedVideos inserts n approved, 5-minute, under-4 videos in bichos,
// titled "Vídeo vidNNNNNNNN", numbered after the videos already stored.
func (f *fixture) approvedVideos(n int) []string {
	f.t.Helper()
	base := f.count(`SELECT count(*) FROM videos`)
	ids := make([]string, n)
	for i := range n {
		ids[i] = f.published(nthID(base+i), "bichos", family.AgeUpTo4)
	}
	return ids
}

// packRound inserts round of packID titled "Pacotinho", composed by
// composerID ("" for an erased composer) as mae-pai, with videoIDs in
// order, the first as cover, and the given outcome.
func (f *fixture) packRound(packID string, round int, composerID, outcome string, videoIDs ...string) {
	f.t.Helper()
	f.exec(`INSERT INTO pack_rounds (pack_id, round, title, cover_video_id, composer_id, composer_role, composed_at, outcome)
		VALUES ($1::uuid, $2, 'Pacotinho', $3::uuid, nullif($4::text, '')::uuid, 'mae-pai', $5, $6)`,
		packID, round, videoIDs[0], composerID, f.now, outcome)
	for i, v := range videoIDs {
		f.exec(`INSERT INTO pack_items (pack_id, round, position, video_id) VALUES ($1::uuid, $2, $3, $4::uuid)`,
			packID, round, i+1, v)
	}
}

// pendingPack inserts a pending pack whose open round 1 composerID
// composed.
func (f *fixture) pendingPack(composerID string, videoIDs ...string) string {
	f.t.Helper()
	id := f.id(`INSERT INTO packs (state, created_at, updated_at) VALUES ('pending', $1, $1) RETURNING id::text`, f.now)
	f.packRound(id, 1, composerID, "open", videoIDs...)
	return id
}

// publishedPack inserts an approved pack whose published round 1 holds
// videoIDs in order, composed by an erased mae-pai, with one pedagogo
// approval: its provenance.
func (f *fixture) publishedPack(videoIDs ...string) string {
	f.t.Helper()
	id := f.id(`INSERT INTO packs (state, round, published_round, last_reviewed_at, created_at, updated_at)
		VALUES ('approved', 1, 1, $1, $1, $1) RETURNING id::text`, f.now)
	f.packRound(id, 1, "", "published", videoIDs...)
	f.exec(`INSERT INTO pack_reviews (pack_id, round, curator_id, display_role, decision, reviewed_at)
		VALUES ($1::uuid, 1, NULL, 'pedagogo', 'approve', $2)`, id, f.now)
	return id
}

func (f *fixture) packDetail(curatorID, id string) curation.Pack {
	f.t.Helper()
	p, err := f.svc.PackDetail(ctx, curatorID, id)
	if err != nil {
		f.t.Fatalf("pack detail: %v", err)
	}
	return p
}

// compose has curatorID compose a pack of videoIDs titled "Pacotinho"; it
// must succeed.
func (f *fixture) compose(curatorID string, videoIDs ...string) curation.Pack {
	f.t.Helper()
	p, err := f.svc.Compose(ctx, curatorID, curation.PackInput{Title: "Pacotinho", VideoIDs: videoIDs})
	if err != nil {
		f.t.Fatalf("compose: %v", err)
	}
	return p
}

func (f *fixture) kidPacks(c curation.Child) []curation.KidPack {
	f.t.Helper()
	ps, err := f.svc.KidPacks(ctx, c, saoPaulo)
	if err != nil {
		f.t.Fatalf("kid packs: %v", err)
	}
	return ps
}

// packVideoIDs is the IDs of a served pack's videos, in order.
func packVideoIDs(p curation.KidPack) []string {
	ids := []string{}
	for _, v := range p.Videos {
		ids = append(ids, v.ID)
	}
	return ids
}
