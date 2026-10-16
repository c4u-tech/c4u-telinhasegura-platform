package screentime_test

import (
	"context"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ctx = context.Background()

type fixture struct {
	t     *testing.T
	svc   *screentime.Service
	pool  *pgxpool.Pool
	audit *audittest.Recorder
	now   time.Time
}

// newFixture's clock starts at 12:00 UTC, 09:00 in São Paulo: inside
// the default window.
func newFixture(t *testing.T) *fixture {
	f := &fixture{t: t, pool: dbtest.New(t), audit: &audittest.Recorder{},
		now: time.Date(2026, 10, 5, 12, 0, 0, 0, time.UTC)}
	clock := func() time.Time { return f.now }
	f.svc = screentime.NewService(screentime.Deps{
		Pool:        f.pool,
		Audit:       f.audit,
		Now:         clock,
		BeatLimiter: ratelimit.New(20, time.Minute, clock),
		PlayLimiter: ratelimit.New(30, time.Minute, clock),
	})
	return f
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

// family inserts a family owned by a new verified account.
func (f *fixture) family(email string) (familyID, ownerID string) {
	f.t.Helper()
	ownerID = f.id(`INSERT INTO accounts (email, email_verified_at, adult_declared_at, created_at)
		VALUES ($1, $2, $2, $2) RETURNING id::text`, email, f.now)
	familyID = f.id(`INSERT INTO families (created_at) VALUES ($1) RETURNING id::text`, f.now)
	f.exec(`INSERT INTO family_members (family_id, account_id, role, joined_at) VALUES ($1::uuid, $2::uuid, 'owner', $3)`,
		familyID, ownerID, f.now)
	return familyID, ownerID
}

// minor inserts a child of the family in band ("ate-4", "5-8", "9-12").
func (f *fixture) minor(familyID, band string) screentime.Child {
	f.t.Helper()
	id := f.id(`INSERT INTO minors (family_id, nickname, avatar, age_band, created_at, updated_at)
		VALUES ($1::uuid, 'Lia', 'fox', $2, $3, $3) RETURNING id::text`, familyID, band, f.now)
	return screentime.Child{FamilyID: familyID, MinorID: id}
}

// video inserts an approved video of the given length in seconds.
func (f *fixture) video(youtubeID string, seconds int) string {
	f.t.Helper()
	return f.id(`INSERT INTO videos (youtube_id, title, channel_id, channel_title, duration_seconds, state, round,
		published_round, theme, min_age_band, created_at, updated_at)
		VALUES ($1, 'Vídeo', 'UC1', 'Canal', $2, 'approved', 2, 1, 'bichos', 'ate-4', $3, $3) RETURNING id::text`,
		youtubeID, seconds, f.now)
}

func (f *fixture) audited(e audit.Event) int {
	n := 0
	for _, x := range f.audit.Entries {
		if x.Event == e {
			n++
		}
	}
	return n
}

// at sets the clock to a wall time in São Paulo (UTC−3) on 2026-10-05.
func (f *fixture) at(hour, minute int) {
	f.now = time.Date(2026, 10, 5, hour+3, minute, 0, 0, time.UTC)
}
