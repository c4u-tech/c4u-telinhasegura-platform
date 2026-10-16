package screentime

import (
	"context"
	"errors"
	"fmt"
	"time"
	_ "time/tzdata" // family zones load on a host without zoneinfo

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// Rules are a child's daily minutes and allowed window [WindowStart,
// WindowEnd), in minutes after local midnight in TimeZone, the family's.
type Rules struct {
	DailyMinutes int
	WindowStart  int
	WindowEnd    int
	TimeZone     string
	IsDefault    bool // no rules saved: the band's default
}

// Today is a child's day as a guardian sees it.
type Today struct {
	UsedSeconds      int
	ExtensionMinutes int
	Time             Time
}

// RulesInput is a guardian's save; the zone comes from their device.
type RulesInput struct {
	DailyMinutes int
	WindowStart  string // "HH:MM"
	WindowEnd    string
	TimeZone     string // IANA
}

// defaults are the Sociedade Brasileira de Pediatria-based defaults.
func defaults(band string) Rules {
	minutes := 90
	if band == "ate-4" {
		minutes = 60
	}
	return Rules{DailyMinutes: minutes, WindowStart: 8 * 60, WindowEnd: 19*60 + 30, IsDefault: true}
}

// minor is a child as screentime reads it.
type minor struct {
	ID       string
	FamilyID string
	Band     string
}

// guardedMinor is a child of the account's family; anything else, a
// malformed ID included, is ErrNotFound.
func guardedMinor(ctx context.Context, q querier, accountID, minorID string) (minor, error) {
	if !validID(accountID) || !validID(minorID) {
		return minor{}, ErrNotFound
	}
	m := minor{ID: minorID}
	err := q.QueryRow(ctx, `SELECT m.family_id::text, m.age_band FROM minors m
		JOIN family_members fm ON fm.family_id = m.family_id
		WHERE m.id = $1::uuid AND fm.account_id = $2::uuid`, minorID, accountID).Scan(&m.FamilyID, &m.Band)
	if errors.Is(err, pgx.ErrNoRows) {
		return minor{}, ErrNotFound
	}
	return m, err
}

// childMinor is the principal's child, read on every request; a child or
// family that is gone is ErrProfileGone.
func childMinor(ctx context.Context, q querier, c Child) (minor, error) {
	if !validID(c.FamilyID) || !validID(c.MinorID) {
		return minor{}, ErrProfileGone
	}
	m := minor{ID: c.MinorID, FamilyID: c.FamilyID}
	err := q.QueryRow(ctx, `SELECT age_band FROM minors WHERE id = $1::uuid AND family_id = $2::uuid`,
		c.MinorID, c.FamilyID).Scan(&m.Band)
	if errors.Is(err, pgx.ErrNoRows) {
		return minor{}, ErrProfileGone
	}
	return m, err
}

// rulesOf is the child's saved rules, else the band's default, with the
// family's zone, else DefaultZone.
func rulesOf(ctx context.Context, q querier, m minor) (Rules, error) {
	r := defaults(m.Band)
	err := q.QueryRow(ctx, `SELECT daily_minutes, window_start, window_end FROM screentime_rules WHERE minor_id = $1::uuid`,
		m.ID).Scan(&r.DailyMinutes, &r.WindowStart, &r.WindowEnd)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		return Rules{}, err
	default:
		r.IsDefault = false
	}
	err = q.QueryRow(ctx, `SELECT time_zone FROM screentime_families WHERE family_id = $1::uuid`, m.FamilyID).Scan(&r.TimeZone)
	if errors.Is(err, pgx.ErrNoRows) {
		r.TimeZone, err = DefaultZone, nil
	}
	return r, err
}

// location loads a zone stored after validZone checked it.
func (r Rules) location() (*time.Location, error) { return time.LoadLocation(r.TimeZone) }

// validZone is an IANA name time.LoadLocation knows ("UTC" is one);
// "" and "Local" stand for no zone, and LoadLocation itself refuses a
// path.
func validZone(name string) bool {
	if name == "" || name == "Local" || len(name) > 64 {
		return false
	}
	_, err := time.LoadLocation(name)
	return err == nil
}

// parseClock reads "HH:MM" as minutes after midnight.
func parseClock(v string) (int, bool) {
	t, err := time.Parse("15:04", v)
	if err != nil || len(v) != 5 {
		return 0, false
	}
	return t.Hour()*60 + t.Minute(), true
}

// FormatClock writes minutes after midnight as "HH:MM".
func FormatClock(m int) string { return fmt.Sprintf("%02d:%02d", m/60, m%60) }

// Zone is the child's family zone, for the catalogue's rotation day.
func (s *Service) Zone(ctx context.Context, c Child) (*time.Location, error) {
	m, err := childMinor(ctx, s.d.Pool, c)
	if err != nil {
		return nil, err
	}
	r, err := rulesOf(ctx, s.d.Pool, m)
	if err != nil {
		return nil, err
	}
	return r.location()
}

// GuardianZone is the zone of the family of one of the account's
// children, for the guardian catalogue's rotation day. A
// minor outside the account's family, a malformed ID included, is
// ErrNotFound.
func (s *Service) GuardianZone(ctx context.Context, accountID, minorID string) (*time.Location, error) {
	m, err := guardedMinor(ctx, s.d.Pool, accountID, minorID)
	if err != nil {
		return nil, err
	}
	r, err := rulesOf(ctx, s.d.Pool, m)
	if err != nil {
		return nil, err
	}
	return r.location()
}

// Rules is a child's rules and today's state, for a guardian of its
// family.
func (s *Service) Rules(ctx context.Context, accountID, minorID string) (Rules, Today, error) {
	m, err := guardedMinor(ctx, s.d.Pool, accountID, minorID)
	if err != nil {
		return Rules{}, Today{}, err
	}
	r, err := rulesOf(ctx, s.d.Pool, m)
	if err != nil {
		return Rules{}, Today{}, err
	}
	local, d, err := s.dayOf(ctx, s.d.Pool, m, r)
	if err != nil {
		return Rules{}, Today{}, err
	}
	return r, Today{UsedSeconds: d.Seconds, ExtensionMinutes: d.ExtensionMinutes, Time: stateAt(r, d, local)}, nil
}

// SaveRules stores a child's rules and, on the family's first save, its
// zone.
func (s *Service) SaveRules(ctx context.Context, accountID, minorID string, in RulesInput) (Rules, Today, error) {
	start, okStart := parseClock(in.WindowStart)
	end, okEnd := parseClock(in.WindowEnd)
	if !okStart || !okEnd || start >= end || in.DailyMinutes < 15 || in.DailyMinutes > MaxDailyMinutes ||
		!validZone(in.TimeZone) {
		return Rules{}, Today{}, ErrValidation
	}
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		m, err := guardedMinor(ctx, tx, accountID, minorID)
		if err != nil {
			return err
		}
		now := s.now()
		if _, err := tx.Exec(ctx, `INSERT INTO screentime_families (family_id, time_zone, set_at)
			VALUES ($1::uuid, $2, $3) ON CONFLICT (family_id) DO NOTHING`, m.FamilyID, in.TimeZone, now); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO screentime_rules (minor_id, daily_minutes, window_start, window_end, updated_by, updated_at)
			VALUES ($1::uuid, $2, $3, $4, $5::uuid, $6)
			ON CONFLICT (minor_id) DO UPDATE SET daily_minutes = EXCLUDED.daily_minutes,
				window_start = EXCLUDED.window_start, window_end = EXCLUDED.window_end,
				updated_by = EXCLUDED.updated_by, updated_at = EXCLUDED.updated_at`,
			m.ID, in.DailyMinutes, start, end, accountID, now)
		return err
	})
	if err != nil {
		return Rules{}, Today{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.ScreenTimeRulesChanged)
	return s.Rules(ctx, accountID, minorID)
}
