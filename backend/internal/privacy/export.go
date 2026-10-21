package privacy

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// Export is the document of `GET /v1/account/export`: its JSON tags are
// the format (Export document). Every list is non-nil, so it
// encodes as [] when empty.
type Export struct {
	Format      string    `json:"format"`
	GeneratedAt time.Time `json:"generated_at"`
	Account     Account   `json:"account"`
	Family      *Family   `json:"family"`
}

type Account struct {
	ID                  string               `json:"id"`
	Email               string               `json:"email"`
	EmailVerifiedAt     *time.Time           `json:"email_verified_at"`
	AdultDeclaredAt     time.Time            `json:"adult_declared_at"`
	TermsVersion        *string              `json:"terms_version"`
	TermsAcceptedAt     *time.Time           `json:"terms_accepted_at"`
	CreatedAt           time.Time            `json:"created_at"`
	HasPassword         bool                 `json:"has_password"`
	MFAEnrolledAt       *time.Time           `json:"mfa_enrolled_at"` // a confirmed staff factor, never its secret or codes
	LinkedProviders     []LinkedProvider     `json:"linked_providers"`
	Sessions            []Session            `json:"sessions"`
	AccessLog           []AccessEntry        `json:"access_log"`
	Events              []Event              `json:"events"`
	SubjectActions      []Event              `json:"subject_actions"` // staff actions about the account
	PlatformRoles       []PlatformRole       `json:"platform_roles"`
	CuratorDeclarations []CuratorDeclaration `json:"curator_declarations"`
	Suggestions         []Suggestion         `json:"suggestions"`
	Reviews             []Review             `json:"reviews"`
	PackReviews         []PackReview         `json:"pack_reviews"`
	PackCompositions    []PackComposition    `json:"pack_compositions"`
}

// LinkedProvider never carries the provider's subject.
type LinkedProvider struct {
	Provider string    `json:"provider"`
	LinkedAt time.Time `json:"linked_at"`
}

type Session struct {
	Client      string     `json:"client"`
	DeviceLabel string     `json:"device_label"`
	CreatedAt   time.Time  `json:"created_at"`
	LastSeenAt  time.Time  `json:"last_seen_at"`
	RevokedAt   *time.Time `json:"revoked_at"`
}

// AccessEntry is one row of the account's access record: when, and from
// which address and port. Rows of sessions already ended are included.
type AccessEntry struct {
	OccurredAt time.Time `json:"occurred_at"`
	IP         string    `json:"ip"`
	Port       *int      `json:"port"` // null when the port was not known
}

type Event struct {
	Event      string    `json:"event"`
	OccurredAt time.Time `json:"occurred_at"`
}

// PlatformRole is one of the account's platform roles; display_role is null for the admin role.
type PlatformRole struct {
	Role                 string    `json:"role"`
	DisplayRole          *string   `json:"display_role"`
	VerifiedProfessional bool      `json:"verified_professional"`
	GrantedAt            time.Time `json:"granted_at"`
}

type Suggestion struct {
	YouTubeID   string    `json:"youtube_id"`
	VideoTitle  string    `json:"video_title"`
	SuggestedAt time.Time `json:"suggested_at"`
}

// CuratorDeclaration is one acceptance of the curator terms.
type CuratorDeclaration struct {
	Version    string    `json:"version"`
	AcceptedAt time.Time `json:"accepted_at"`
}

// Review is one of the account's curation reviews, with the displayed
// role it was given under.
type Review struct {
	YouTubeID        string          `json:"youtube_id"`
	VideoTitle       string          `json:"video_title"`
	Round            int             `json:"round"`
	DisplayRole      string          `json:"display_role"`
	Decision         string          `json:"decision"`
	Theme            *string         `json:"theme"`
	MinAgeBand       *string         `json:"min_age_band"`
	Reason           *string         `json:"reason"`
	ChecklistVersion *string         `json:"checklist_version"` // null before the list
	Checklist        json.RawMessage `json:"checklist"`         // the answers, or a rejection's questions
	ReviewedAt       time.Time       `json:"reviewed_at"`
}

// PackReview is one of the account's pack reviews.
type PackReview struct {
	PackID      string    `json:"pack_id"`
	Round       int       `json:"round"`
	DisplayRole string    `json:"display_role"`
	Decision    string    `json:"decision"`
	Reason      *string   `json:"reason"`
	ReviewedAt  time.Time `json:"reviewed_at"`
}

// PackComposition is a pack round the account composed.
type PackComposition struct {
	PackID     string    `json:"pack_id"`
	Round      int       `json:"round"`
	Title      string    `json:"title"`
	ComposedAt time.Time `json:"composed_at"`
}

// Family is the caller's family as the family screens show it:
// invitations only for the owner, and no other guardian's account ID.
type Family struct {
	ID                   string                `json:"id"`
	Role                 string                `json:"role"`
	JoinedAt             time.Time             `json:"joined_at"`
	CreatedAt            time.Time             `json:"created_at"`
	PINSet               bool                  `json:"pin_set"`
	Guardians            []Guardian            `json:"guardians"`
	Invitations          []Invitation          `json:"invitations"`
	Minors               []Minor               `json:"minors"`
	Consents             []Consent             `json:"consents"`
	Devices              []Device              `json:"devices"`
	Hides                []Hide                `json:"hides"`
	Reports              []Report              `json:"reports"`
	TimeZone             *string               `json:"time_zone"` // null until the first screen-time save
	ScreenTimeRules      []ScreenTimeRules     `json:"screen_time_rules"`
	ScreenTimeDays       []ScreenTimeDay       `json:"screen_time_days"`
	ScreenTimeExtensions []ScreenTimeExtension `json:"screen_time_extensions"`
	Plays                []Play                `json:"plays"`
}

type Guardian struct {
	Email    string    `json:"email"`
	Role     string    `json:"role"`
	JoinedAt time.Time `json:"joined_at"`
}

type Invitation struct {
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

type Minor struct {
	ID        string    `json:"id"`
	Nickname  string    `json:"nickname"`
	Avatar    string    `json:"avatar"`
	AgeBand   string    `json:"age_band"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Consent is one ledger row; GrantedByMe stands in for the granting
// guardian's ID.
type Consent struct {
	MinorID       string     `json:"minor_id"`
	PolicyVersion string     `json:"policy_version"`
	GrantedAt     time.Time  `json:"granted_at"`
	GrantedByMe   bool       `json:"granted_by_me"`
	WithdrawnAt   *time.Time `json:"withdrawn_at"`
}

type Device struct {
	ID         string    `json:"id"`
	MinorID    string    `json:"minor_id"`
	Label      string    `json:"label"`
	LinkedAt   time.Time `json:"linked_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

// Hide is a video hidden for one of the family's children. Who hid it is another account's ID: not exported.
type Hide struct {
	MinorID    string    `json:"minor_id"`
	YouTubeID  string    `json:"youtube_id"`
	VideoTitle string    `json:"video_title"`
	HiddenAt   time.Time `json:"hidden_at"`
}

// Report is the family's report of a video; who wrote it is not exported.
type Report struct {
	YouTubeID  string    `json:"youtube_id"`
	VideoTitle string    `json:"video_title"`
	Reason     string    `json:"reason"`
	Note       *string   `json:"note"`
	ReportedAt time.Time `json:"reported_at"`
}

// ScreenTimeRules are a child's saved rules. Who saved them is another account's ID: not exported.
type ScreenTimeRules struct {
	MinorID      string    `json:"minor_id"`
	DailyMinutes int       `json:"daily_minutes"`
	WindowStart  string    `json:"window_start"`
	WindowEnd    string    `json:"window_end"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type ScreenTimeDay struct {
	MinorID          string `json:"minor_id"`
	Date             string `json:"date"`
	Seconds          int    `json:"seconds"`
	OutsideSeconds   int    `json:"outside_seconds"`
	ExtensionMinutes int    `json:"extension_minutes"`
}

// ScreenTimeExtension is one grant; who granted it is not exported.
type ScreenTimeExtension struct {
	MinorID   string    `json:"minor_id"`
	Date      string    `json:"date"`
	Minutes   int       `json:"minutes"`
	Via       string    `json:"via"`
	CreatedAt time.Time `json:"created_at"`
}

type Play struct {
	MinorID    string    `json:"minor_id"`
	YouTubeID  string    `json:"youtube_id"`
	VideoTitle string    `json:"video_title"`
	StartedAt  time.Time `json:"started_at"`
	Seconds    int       `json:"seconds"`
}

// Export reads everything the platform holds about the account and its
// family in one consistent snapshot, then audits it.
func (s *Service) Export(ctx context.Context, accountID string) (Export, error) {
	if ok, wait := s.d.ExportLimiter.Allow(accountID); !ok {
		return Export{}, &ThrottledError{RetryAfter: wait}
	}
	tx, err := s.d.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return Export{}, err
	}
	defer tx.Rollback(ctx)
	e := Export{Format: Format, GeneratedAt: s.now()}
	if e.Account, err = readAccount(ctx, tx, accountID); err != nil {
		return Export{}, err
	}
	if err := readCuration(ctx, tx, &e.Account); err != nil {
		return Export{}, err
	}
	if e.Family, err = readFamily(ctx, tx, accountID, e.GeneratedAt); err != nil {
		return Export{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Export{}, err
	}
	s.d.Audit.Record(ctx, accountID, audit.DataExported)
	return e, nil
}

func readAccount(ctx context.Context, tx pgx.Tx, id string) (Account, error) {
	a := Account{ID: id}
	err := tx.QueryRow(ctx, `SELECT email, email_verified_at, adult_declared_at, created_at, password_hash IS NOT NULL,
			terms_version, terms_accepted_at,
			(SELECT confirmed_at FROM staff_mfa WHERE account_id = accounts.id)
		FROM accounts WHERE id = $1::uuid`, id).Scan(&a.Email, &a.EmailVerifiedAt, &a.AdultDeclaredAt, &a.CreatedAt, &a.HasPassword, &a.TermsVersion, &a.TermsAcceptedAt, &a.MFAEnrolledAt)
	if err != nil {
		return Account{}, err
	}
	a.EmailVerifiedAt, a.AdultDeclaredAt, a.CreatedAt = utcp(a.EmailVerifiedAt), a.AdultDeclaredAt.UTC(), a.CreatedAt.UTC()
	a.MFAEnrolledAt = utcp(a.MFAEnrolledAt)
	a.TermsAcceptedAt = utcp(a.TermsAcceptedAt)

	rows, err := tx.Query(ctx, `SELECT provider, created_at FROM external_identities
		WHERE account_id = $1::uuid ORDER BY created_at, provider`, id)
	if err != nil {
		return Account{}, err
	}
	if a.LinkedProviders, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (LinkedProvider, error) {
		var p LinkedProvider
		err := r.Scan(&p.Provider, &p.LinkedAt)
		p.LinkedAt = p.LinkedAt.UTC()
		return p, err
	}); err != nil {
		return Account{}, err
	}

	rows, err = tx.Query(ctx, `SELECT client, device_label, created_at, last_seen_at, revoked_at FROM sessions
		WHERE account_id = $1::uuid ORDER BY created_at, id`, id)
	if err != nil {
		return Account{}, err
	}
	if a.Sessions, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Session, error) {
		var x Session
		err := r.Scan(&x.Client, &x.DeviceLabel, &x.CreatedAt, &x.LastSeenAt, &x.RevokedAt)
		x.CreatedAt, x.LastSeenAt, x.RevokedAt = x.CreatedAt.UTC(), x.LastSeenAt.UTC(), utcp(x.RevokedAt)
		return x, err
	}); err != nil {
		return Account{}, err
	}

	rows, err = tx.Query(ctx, `SELECT occurred_at, host(ip), port FROM access_log
		WHERE account_id = $1::uuid ORDER BY occurred_at, id`, id)
	if err != nil {
		return Account{}, err
	}
	if a.AccessLog, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (AccessEntry, error) {
		var x AccessEntry
		err := r.Scan(&x.OccurredAt, &x.IP, &x.Port)
		x.OccurredAt = x.OccurredAt.UTC()
		return x, err
	}); err != nil {
		return Account{}, err
	}

	rows, err = tx.Query(ctx, `SELECT event, occurred_at FROM audit_events
		WHERE account_id = $1::uuid ORDER BY occurred_at, id`, id)
	if err != nil {
		return Account{}, err
	}
	if a.Events, err = pgx.CollectRows(rows, scanEvent); err != nil {
		return Account{}, err
	}
	// The staff actions about the account: the event and its time only,
	// never the actor, the role, the reason or the metadata.
	rows, err = tx.Query(ctx, `SELECT event, occurred_at FROM audit_events
		WHERE subject_kind = 'account' AND subject_id = $1::uuid ORDER BY occurred_at, id`, id)
	if err != nil {
		return Account{}, err
	}
	a.SubjectActions, err = pgx.CollectRows(rows, scanEvent)
	return a, err
}

func scanEvent(r pgx.CollectableRow) (Event, error) {
	var x Event
	err := r.Scan(&x.Event, &x.OccurredAt)
	x.OccurredAt = x.OccurredAt.UTC()
	return x, err
}

// utcp is t in UTC, keeping nil.
func utcp(t *time.Time) *time.Time {
	if t == nil {
		return nil
	}
	u := t.UTC()
	return &u
}

// readFamily returns nil when the account belongs to no family.
func readFamily(ctx context.Context, tx pgx.Tx, accountID string, now time.Time) (*Family, error) {
	var f Family
	err := tx.QueryRow(ctx, `SELECT m.family_id::text, m.role, m.joined_at, fa.created_at,
			EXISTS (SELECT 1 FROM family_pins p WHERE p.family_id = m.family_id)
		FROM family_members m JOIN families fa ON fa.id = m.family_id
		WHERE m.account_id = $1::uuid`, accountID).Scan(&f.ID, &f.Role, &f.JoinedAt, &f.CreatedAt, &f.PINSet)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	f.JoinedAt, f.CreatedAt = f.JoinedAt.UTC(), f.CreatedAt.UTC()

	rows, err := tx.Query(ctx, `SELECT a.email, m.role, m.joined_at
		FROM family_members m JOIN accounts a ON a.id = m.account_id
		WHERE m.family_id = $1::uuid ORDER BY m.role = 'owner' DESC, m.joined_at, m.account_id`, f.ID)
	if err != nil {
		return nil, err
	}
	if f.Guardians, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Guardian, error) {
		var g Guardian
		err := r.Scan(&g.Email, &g.Role, &g.JoinedAt)
		g.JoinedAt = g.JoinedAt.UTC()
		return g, err
	}); err != nil {
		return nil, err
	}

	f.Invitations = []Invitation{}
	if f.Role == "owner" { // only the owner sees invitations
		// Pending only, as GET /v1/family lists them.
		rows, err = tx.Query(ctx, `SELECT email, created_at, expires_at
			FROM family_invitations WHERE family_id = $1::uuid
			AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > $2
			ORDER BY created_at, id`, f.ID, now)
		if err != nil {
			return nil, err
		}
		if f.Invitations, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Invitation, error) {
			var i Invitation
			err := r.Scan(&i.Email, &i.CreatedAt, &i.ExpiresAt)
			i.CreatedAt, i.ExpiresAt = i.CreatedAt.UTC(), i.ExpiresAt.UTC()
			return i, err
		}); err != nil {
			return nil, err
		}
	}

	rows, err = tx.Query(ctx, `SELECT id::text, nickname, avatar, age_band, created_at, updated_at
		FROM minors WHERE family_id = $1::uuid ORDER BY created_at, id`, f.ID)
	if err != nil {
		return nil, err
	}
	if f.Minors, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Minor, error) {
		var m Minor
		err := r.Scan(&m.ID, &m.Nickname, &m.Avatar, &m.AgeBand, &m.CreatedAt, &m.UpdatedAt)
		m.CreatedAt, m.UpdatedAt = m.CreatedAt.UTC(), m.UpdatedAt.UTC()
		return m, err
	}); err != nil {
		return nil, err
	}

	rows, err = tx.Query(ctx, `SELECT minor_id::text, policy_version, granted_at, granted_by = $2::uuid, withdrawn_at
		FROM minor_consents WHERE family_id = $1::uuid ORDER BY granted_at, minor_id`, f.ID, accountID)
	if err != nil {
		return nil, err
	}
	if f.Consents, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Consent, error) {
		var c Consent
		err := r.Scan(&c.MinorID, &c.PolicyVersion, &c.GrantedAt, &c.GrantedByMe, &c.WithdrawnAt)
		c.GrantedAt, c.WithdrawnAt = c.GrantedAt.UTC(), utcp(c.WithdrawnAt)
		return c, err
	}); err != nil {
		return nil, err
	}

	rows, err = tx.Query(ctx, `SELECT id::text, minor_id::text, label, linked_at, last_seen_at
		FROM devices WHERE family_id = $1::uuid ORDER BY linked_at, id`, f.ID)
	if err != nil {
		return nil, err
	}
	if f.Devices, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Device, error) {
		var d Device
		err := r.Scan(&d.ID, &d.MinorID, &d.Label, &d.LinkedAt, &d.LastSeenAt)
		d.LinkedAt, d.LastSeenAt = d.LinkedAt.UTC(), d.LastSeenAt.UTC()
		return d, err
	}); err != nil {
		return nil, err
	}

	rows, err = tx.Query(ctx, `SELECT h.minor_id::text, v.youtube_id, v.title, h.hidden_at
		FROM video_hides h JOIN minors m ON m.id = h.minor_id JOIN videos v ON v.id = h.video_id
		WHERE m.family_id = $1::uuid ORDER BY h.hidden_at, h.minor_id, v.id`, f.ID)
	if err != nil {
		return nil, err
	}
	if f.Hides, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Hide, error) {
		var h Hide
		err := r.Scan(&h.MinorID, &h.YouTubeID, &h.VideoTitle, &h.HiddenAt)
		h.HiddenAt = h.HiddenAt.UTC()
		return h, err
	}); err != nil {
		return nil, err
	}

	rows, err = tx.Query(ctx, `SELECT v.youtube_id, v.title, r.reason, r.note, r.reported_at
		FROM video_reports r JOIN videos v ON v.id = r.video_id
		WHERE r.family_id = $1::uuid ORDER BY r.reported_at, v.id`, f.ID)
	if err != nil {
		return nil, err
	}
	if f.Reports, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Report, error) {
		var x Report
		err := r.Scan(&x.YouTubeID, &x.VideoTitle, &x.Reason, &x.Note, &x.ReportedAt)
		x.ReportedAt = x.ReportedAt.UTC()
		return x, err
	}); err != nil {
		return nil, err
	}
	if err := readScreenTime(ctx, tx, &f); err != nil {
		return nil, err
	}
	return &f, nil
}

// readCuration adds the account's platform roles, suggestions and
// reviews. It never reads who granted a
// role: that is another account's ID.
func readCuration(ctx context.Context, tx pgx.Tx, a *Account) error {
	rows, err := tx.Query(ctx, `SELECT role, display_role, verified_professional, granted_at FROM platform_roles
		WHERE account_id = $1::uuid ORDER BY role`, a.ID)
	if err != nil {
		return err
	}
	if a.PlatformRoles, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (PlatformRole, error) {
		var p PlatformRole
		err := r.Scan(&p.Role, &p.DisplayRole, &p.VerifiedProfessional, &p.GrantedAt)
		p.GrantedAt = p.GrantedAt.UTC()
		return p, err
	}); err != nil {
		return err
	}

	rows, err = tx.Query(ctx, `SELECT version, accepted_at FROM curator_declarations
		WHERE account_id = $1::uuid ORDER BY accepted_at, id`, a.ID)
	if err != nil {
		return err
	}
	if a.CuratorDeclarations, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (CuratorDeclaration, error) {
		var x CuratorDeclaration
		err := r.Scan(&x.Version, &x.AcceptedAt)
		x.AcceptedAt = x.AcceptedAt.UTC()
		return x, err
	}); err != nil {
		return err
	}

	rows, err = tx.Query(ctx, `SELECT v.youtube_id, v.title, s.suggested_at
		FROM video_suggestions s JOIN videos v ON v.id = s.video_id
		WHERE s.account_id = $1::uuid ORDER BY s.suggested_at, v.youtube_id`, a.ID)
	if err != nil {
		return err
	}
	if a.Suggestions, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Suggestion, error) {
		var x Suggestion
		err := r.Scan(&x.YouTubeID, &x.VideoTitle, &x.SuggestedAt)
		x.SuggestedAt = x.SuggestedAt.UTC()
		return x, err
	}); err != nil {
		return err
	}

	rows, err = tx.Query(ctx, `SELECT v.youtube_id, v.title, r.round, r.display_role, r.decision, r.theme,
			r.min_age_band, r.reason, r.checklist_version, r.checklist, r.reviewed_at
		FROM video_reviews r JOIN videos v ON v.id = r.video_id
		WHERE r.curator_id = $1::uuid ORDER BY r.reviewed_at, r.id`, a.ID)
	if err != nil {
		return err
	}
	if a.Reviews, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Review, error) {
		var x Review
		var list []byte
		err := r.Scan(&x.YouTubeID, &x.VideoTitle, &x.Round, &x.DisplayRole, &x.Decision, &x.Theme,
			&x.MinAgeBand, &x.Reason, &x.ChecklistVersion, &list, &x.ReviewedAt)
		x.Checklist, x.ReviewedAt = list, x.ReviewedAt.UTC()
		return x, err
	}); err != nil {
		return err
	}
	return readPacks(ctx, tx, a)
}

// readPacks adds the pack reviews the account wrote and the pack rounds
// it composed. Neither names another account.
func readPacks(ctx context.Context, tx pgx.Tx, a *Account) error {
	rows, err := tx.Query(ctx, `SELECT pack_id::text, round, display_role, decision, reason, reviewed_at FROM pack_reviews
		WHERE curator_id = $1::uuid ORDER BY reviewed_at, id`, a.ID)
	if err != nil {
		return err
	}
	if a.PackReviews, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (PackReview, error) {
		var x PackReview
		err := r.Scan(&x.PackID, &x.Round, &x.DisplayRole, &x.Decision, &x.Reason, &x.ReviewedAt)
		x.ReviewedAt = x.ReviewedAt.UTC()
		return x, err
	}); err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT pack_id::text, round, title, composed_at FROM pack_rounds
		WHERE composer_id = $1::uuid ORDER BY composed_at, pack_id, round`, a.ID)
	if err != nil {
		return err
	}
	a.PackCompositions, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (PackComposition, error) {
		var x PackComposition
		err := r.Scan(&x.PackID, &x.Round, &x.Title, &x.ComposedAt)
		x.ComposedAt = x.ComposedAt.UTC()
		return x, err
	})
	return err
}

// readScreenTime adds the family's zone and its children's screen-time
// rows.
func readScreenTime(ctx context.Context, tx pgx.Tx, f *Family) error {
	var zone string
	err := tx.QueryRow(ctx, `SELECT time_zone FROM screentime_families WHERE family_id = $1::uuid`, f.ID).Scan(&zone)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		return err
	default:
		f.TimeZone = &zone
	}
	clock := func(m int) string { return fmt.Sprintf("%02d:%02d", m/60, m%60) }
	rows, err := tx.Query(ctx, `SELECT r.minor_id::text, r.daily_minutes, r.window_start, r.window_end, r.updated_at
		FROM screentime_rules r JOIN minors m ON m.id = r.minor_id WHERE m.family_id = $1::uuid ORDER BY m.created_at, m.id`, f.ID)
	if err != nil {
		return err
	}
	if f.ScreenTimeRules, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (ScreenTimeRules, error) {
		var x ScreenTimeRules
		var start, end int
		err := r.Scan(&x.MinorID, &x.DailyMinutes, &start, &end, &x.UpdatedAt)
		x.WindowStart, x.WindowEnd, x.UpdatedAt = clock(start), clock(end), x.UpdatedAt.UTC()
		return x, err
	}); err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT d.minor_id::text, d.day::text, d.seconds, d.outside_seconds, d.extension_minutes
		FROM screentime_days d JOIN minors m ON m.id = d.minor_id WHERE m.family_id = $1::uuid ORDER BY d.day, d.minor_id`, f.ID)
	if err != nil {
		return err
	}
	if f.ScreenTimeDays, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (ScreenTimeDay, error) {
		var x ScreenTimeDay
		return x, r.Scan(&x.MinorID, &x.Date, &x.Seconds, &x.OutsideSeconds, &x.ExtensionMinutes)
	}); err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT e.minor_id::text, e.day::text, e.minutes, e.via, e.created_at
		FROM screentime_extensions e JOIN minors m ON m.id = e.minor_id WHERE m.family_id = $1::uuid ORDER BY e.created_at, e.id`, f.ID)
	if err != nil {
		return err
	}
	if f.ScreenTimeExtensions, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (ScreenTimeExtension, error) {
		var x ScreenTimeExtension
		err := r.Scan(&x.MinorID, &x.Date, &x.Minutes, &x.Via, &x.CreatedAt)
		x.CreatedAt = x.CreatedAt.UTC()
		return x, err
	}); err != nil {
		return err
	}
	rows, err = tx.Query(ctx, `SELECT p.minor_id::text, v.youtube_id, v.title, p.started_at, p.seconds
		FROM plays p JOIN minors m ON m.id = p.minor_id JOIN videos v ON v.id = p.video_id
		WHERE m.family_id = $1::uuid ORDER BY p.started_at, p.id`, f.ID)
	if err != nil {
		return err
	}
	f.Plays, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (Play, error) {
		var x Play
		err := r.Scan(&x.MinorID, &x.YouTubeID, &x.VideoTitle, &x.StartedAt, &x.Seconds)
		x.StartedAt = x.StartedAt.UTC()
		return x, err
	})
	return err
}
