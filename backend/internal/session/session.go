// Package session keeps guardian sessions on the server: every credential
// it hands out is an opaque random token stored only as a digest, so a
// revocation takes effect on the next request.
package session

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

type Client string

const (
	Web    Client = "web"
	Mobile Client = "mobile"
)

const (
	day          = 24 * time.Hour
	AccessTTL    = 15 * time.Minute
	ReauthWindow = 5 * time.Minute
	maxLabelLen  = 64
)

type lifetime struct{ idle, absolute time.Duration }

var lifetimes = map[Client]lifetime{
	Web:    {idle: 30 * day, absolute: 90 * day},
	Mobile: {idle: 60 * day, absolute: 180 * day},
}

var (
	ErrUnauthenticated = errors.New("session: unauthenticated")
	ErrInvalidToken    = errors.New("session: invalid refresh token")
	ErrReauthRequired  = errors.New("session: recent re-authentication required")
	ErrNotFound        = errors.New("session: not found")
	ErrInvalidClient   = errors.New("session: unknown client")
)

type Session struct {
	ID            string
	AccountID     string
	Client        Client
	DeviceLabel   string
	CSRFToken     string // web only
	CreatedAt     time.Time
	LastSeenAt    time.Time
	ReauthAt      time.Time
	ElevatedUntil time.Time // epoch until a staff challenge elevates it
}

type Issued struct {
	Session         Session
	Secret          string // web: cookie value; mobile: access token
	AccessExpiresAt time.Time
	RefreshToken    string
}

type Service struct {
	Pool  *pgxpool.Pool
	Audit audit.Recorder
	Now   func() time.Time
}

const cols = `id::text, account_id::text, client, device_label, coalesce(csrf_token, ''),
	created_at, last_seen_at, coalesce(reauth_at, 'epoch'::timestamptz),
	coalesce(access_expires_at, 'epoch'::timestamptz), coalesce(elevated_until, 'epoch'::timestamptz)`

func scan(row pgx.Row) (Session, time.Time, error) {
	var s Session
	var client string
	var accessExp time.Time
	err := row.Scan(&s.ID, &s.AccountID, &client, &s.DeviceLabel, &s.CSRFToken, &s.CreatedAt, &s.LastSeenAt, &s.ReauthAt, &accessExp, &s.ElevatedUntil)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, time.Time{}, ErrNotFound
	}
	s.Client = Client(client)
	return s, accessExp, err
}

func expired(s Session, now time.Time) bool {
	lt := lifetimes[s.Client]
	return now.Sub(s.LastSeenAt) > lt.idle || now.Sub(s.CreatedAt) > lt.absolute
}

// Create starts a session. Signing in proves the password, so the session
// starts inside its re-auth window.
func (s *Service) Create(ctx context.Context, accountID string, c Client, deviceLabel string) (Issued, error) {
	if _, ok := lifetimes[c]; !ok {
		return Issued{}, ErrInvalidClient
	}
	if r := []rune(deviceLabel); len(r) > maxLabelLen {
		deviceLabel = string(r[:maxLabelLen])
	}
	now := s.Now()
	plain, hash := secret.NewToken()
	is := Issued{Secret: plain, Session: Session{AccountID: accountID, Client: c, DeviceLabel: deviceLabel, CreatedAt: now, LastSeenAt: now, ReauthAt: now}}

	var accessExp, csrf any
	var refreshHash []byte
	if c == Mobile {
		is.AccessExpiresAt = now.Add(AccessTTL)
		accessExp = is.AccessExpiresAt
		is.RefreshToken, refreshHash = secret.NewToken()
	} else {
		is.Session.CSRFToken, _ = secret.NewToken()
		csrf = is.Session.CSRFToken
	}
	err := s.Pool.QueryRow(ctx, `INSERT INTO sessions
		(account_id, client, device_label, secret_hash, access_expires_at, refresh_hash, csrf_token, reauth_at, created_at, last_seen_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8, $8) RETURNING id::text`,
		accountID, string(c), deviceLabel, hash, accessExp, refreshHash, csrf, now).Scan(&is.Session.ID)
	return is, err
}

func (s *Service) Authenticate(ctx context.Context, c Client, plain string) (Session, error) {
	now := s.Now()
	sess, accessExp, err := scan(s.Pool.QueryRow(ctx, `SELECT `+cols+` FROM sessions
		WHERE secret_hash = $1 AND revoked_at IS NULL`, secret.Hash(plain)))
	if errors.Is(err, ErrNotFound) {
		return Session{}, ErrUnauthenticated
	}
	if err != nil {
		return Session{}, err
	}
	if sess.Client != c || expired(sess, now) || (c == Mobile && !now.Before(accessExp)) {
		return Session{}, ErrUnauthenticated
	}
	if _, err := s.Pool.Exec(ctx, `UPDATE sessions SET last_seen_at = $2 WHERE id = $1::uuid`, sess.ID, now); err != nil {
		return Session{}, err
	}
	sess.LastSeenAt = now
	return sess, nil
}

// Refresh rotates both mobile tokens. A refresh token presented twice
// revokes its session (RFC 9700 §4.14): one copy was stolen.
func (s *Service) Refresh(ctx context.Context, refresh string) (Issued, error) {
	now := s.Now()
	old := secret.Hash(refresh)
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return Issued{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	sess, _, err := scan(tx.QueryRow(ctx, `SELECT `+cols+` FROM sessions
		WHERE refresh_hash = $1 AND revoked_at IS NULL FOR UPDATE`, old))
	if errors.Is(err, ErrNotFound) {
		_ = tx.Rollback(ctx)
		return Issued{}, s.revokeOnReuse(ctx, old)
	}
	if err != nil {
		return Issued{}, err
	}
	if expired(sess, now) {
		return Issued{}, ErrInvalidToken
	}
	access, accessHash := secret.NewToken()
	next, nextHash := secret.NewToken()
	exp := now.Add(AccessTTL)
	if _, err := tx.Exec(ctx, `INSERT INTO used_refresh_tokens (refresh_hash, session_id) VALUES ($1, $2)`, old, sess.ID); err != nil {
		return Issued{}, err
	}
	if _, err := tx.Exec(ctx, `UPDATE sessions SET secret_hash = $2, access_expires_at = $3, refresh_hash = $4, last_seen_at = $5
		WHERE id = $1::uuid`, sess.ID, accessHash, exp, nextHash, now); err != nil {
		return Issued{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Issued{}, err
	}
	sess.LastSeenAt = now
	return Issued{Session: sess, Secret: access, AccessExpiresAt: exp, RefreshToken: next}, nil
}

func (s *Service) revokeOnReuse(ctx context.Context, hash []byte) error {
	// Every presentation of a used token is audited, even when an earlier
	// one already revoked the session; unknown tokens stay silent.
	var accountID string
	err := s.Pool.QueryRow(ctx, `WITH used AS (
			SELECT s.id, s.account_id FROM used_refresh_tokens u
			JOIN sessions s ON s.id = u.session_id WHERE u.refresh_hash = $1
		), revoked AS (
			UPDATE sessions SET revoked_at = $2
			WHERE id IN (SELECT id FROM used) AND revoked_at IS NULL
		)
		SELECT account_id::text FROM used`, hash, s.Now()).Scan(&accountID)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrInvalidToken
	}
	if err != nil {
		return err
	}
	s.Audit.Record(ctx, accountID, audit.RefreshReused)
	return ErrInvalidToken
}

func (s *Service) SignOut(ctx context.Context, accountID, id string) error {
	return s.revoke(ctx, accountID, id, audit.SignedOut)
}

func (s *Service) Revoke(ctx context.Context, accountID, id string) error {
	return s.revoke(ctx, accountID, id, audit.SessionRevoked)
}

func (s *Service) revoke(ctx context.Context, accountID, id string, e audit.Event) error {
	if !isUUID(id) || !isUUID(accountID) {
		return ErrNotFound
	}
	tag, err := s.Pool.Exec(ctx, `UPDATE sessions SET revoked_at = $3
		WHERE id = $1::uuid AND account_id = $2::uuid AND revoked_at IS NULL`, id, accountID, s.Now())
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	s.Audit.Record(ctx, accountID, e)
	return nil
}

// RevokeAll ends every session of the account except exceptID ("" ends all).
func (s *Service) RevokeAll(ctx context.Context, accountID, exceptID string) error {
	var except any // NULL revokes everything
	if exceptID != "" {
		except = exceptID
	}
	if _, err := s.Pool.Exec(ctx, `UPDATE sessions SET revoked_at = $3
		WHERE account_id = $1::uuid AND revoked_at IS NULL AND ($2::uuid IS NULL OR id <> $2::uuid)`, accountID, except, s.Now()); err != nil {
		return err
	}
	s.Audit.Record(ctx, accountID, audit.SessionRevoked)
	return nil
}

func (s *Service) List(ctx context.Context, accountID string) ([]Session, error) {
	rows, err := s.Pool.Query(ctx, `SELECT `+cols+` FROM sessions
		WHERE account_id = $1::uuid AND revoked_at IS NULL ORDER BY last_seen_at DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	now := s.Now()
	var out []Session
	for rows.Next() {
		sess, _, err := scan(rows)
		if err != nil {
			return nil, err
		}
		if !expired(sess, now) {
			out = append(out, sess)
		}
	}
	return out, rows.Err()
}

func (s *Service) MarkReauth(ctx context.Context, id string) error {
	_, err := s.Pool.Exec(ctx, `UPDATE sessions SET reauth_at = $2 WHERE id = $1::uuid`, id, s.Now())
	return err
}

func (s *Service) RequireRecentReauth(sess Session) error {
	if s.Now().Sub(sess.ReauthAt) > ReauthWindow {
		return ErrReauthRequired
	}
	return nil
}

// Elevated reports whether the session is inside its privileged
// elevation; it ends at the instant elevated_until is reached (TestElevationIsPerSessionAndSurvivesRefresh).
func (s *Service) Elevated(sess Session) bool { return s.Now().Before(sess.ElevatedUntil) }

// MarkElevated elevates a live session of the account inside the
// caller's transaction, so the code that earned it and the elevation
// commit together. ErrNotFound when the session is
// another account's or revoked.
func MarkElevated(ctx context.Context, tx pgx.Tx, id, accountID string, until time.Time) error {
	if !isUUID(id) || !isUUID(accountID) {
		return ErrNotFound
	}
	tag, err := tx.Exec(ctx, `UPDATE sessions SET elevated_until = $3
		WHERE id = $1::uuid AND account_id = $2::uuid AND revoked_at IS NULL`, id, accountID, until)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ClearElevation ends the elevation of every session of the account,
// inside the caller's transaction.
func ClearElevation(ctx context.Context, tx pgx.Tx, accountID string) error {
	_, err := tx.Exec(ctx, `UPDATE sessions SET elevated_until = NULL
		WHERE account_id = $1::uuid AND elevated_until IS NOT NULL`, accountID)
	return err
}

// RevokeAllTx ends every session of the account inside the caller's
// transaction, at at, and answers how many rows it revoked. An eviction
// then revokes in the transaction that bumps the credential version.
// It records no audit
// event: the caller's action is the record.
func RevokeAllTx(ctx context.Context, tx pgx.Tx, accountID string, at time.Time) (int, error) {
	if !isUUID(accountID) {
		return 0, ErrNotFound
	}
	tag, err := tx.Exec(ctx, `UPDATE sessions SET revoked_at = $2
		WHERE account_id = $1::uuid AND revoked_at IS NULL`, accountID, at)
	if err != nil {
		return 0, err
	}
	return int(tag.RowsAffected()), nil
}

func isUUID(v string) bool {
	if len(v) != 36 {
		return false
	}
	for i, r := range v {
		switch {
		case i == 8 || i == 13 || i == 18 || i == 23:
			if r != '-' {
				return false
			}
		case !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f' || r >= 'A' && r <= 'F'):
			return false
		}
	}
	return true
}
