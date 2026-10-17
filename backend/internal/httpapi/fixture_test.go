package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit/audittest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken/idtokentest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail/mailtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/totp"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
	"github.com/jackc/pgx/v5/pgxpool"
)

const goodPassword = "uma senha longa o bastante"

type api struct {
	t       *testing.T
	handler http.Handler
	mail    *mailtest.Recorder
	now     time.Time
	tokens  *idtokentest.Fake
	apple   *appleFake
	pool    *pgxpool.Pool
	par     *parental.Service
	server  *httpapi.Server
	ids     *identity.Service
	cur     *curation.Service
	team    *staff.Service
	st      *screentime.Service
	videos  *curationtest.Fake
	thumbs  *curationtest.Thumbs
	audit   *hookedAudit
	// onAudit runs once, on the next audit event of its kind, so a test
	// can land a concurrent change in the middle of a request.
	onAudit     func()
	onAuditKind audit.Event
}

// appleFake stands for Apple's token endpoints: Revoke records the
// redirect URI it was given and answers Err.
type appleFake struct {
	Err       error
	Redirects []string
}

func (f *appleFake) Revoke(_ context.Context, _, _, redirectURI string) error {
	f.Redirects = append(f.Redirects, redirectURI)
	return f.Err
}

// hookedAudit records events and runs the api's one-shot audit hook.
type hookedAudit struct {
	audittest.Recorder
	a *api
}

func (h *hookedAudit) Record(ctx context.Context, accountID string, e audit.Event) {
	h.Recorder.Record(ctx, accountID, e)
	h.fire(e)
}

func (h *hookedAudit) RecordAction(ctx context.Context, x audit.Action) {
	h.Recorder.RecordAction(ctx, x)
	h.fire(x.Event)
}

// fire runs the api's one-shot audit hook on its event.
func (h *hookedAudit) fire(e audit.Event) {
	if f := h.a.onAudit; f != nil && e == h.a.onAuditKind {
		h.a.onAudit = nil
		f()
	}
}

func newAPI(t *testing.T, opts ...func(*httpapi.Server)) *api {
	a := &api{t: t, mail: &mailtest.Recorder{}, now: time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC), tokens: &idtokentest.Fake{}, apple: &appleFake{}}
	pool := dbtest.New(t)
	a.pool = pool
	clock := func() time.Time { return a.now }
	log := slog.New(slog.DiscardHandler)
	auditRec := &hookedAudit{a: a}
	a.audit = auditRec
	sessions := &session.Service{Pool: pool, Audit: auditRec, Now: clock}
	ids := identity.NewService(identity.Deps{
		Store:      identity.Store{Pool: pool},
		Policy:     identity.PasswordPolicy{Log: log},
		Hash:       identity.HashParams{Memory: 64, Time: 1, Threads: 1},
		Mail:       a.mail,
		Audit:      auditRec,
		Sessions:   sessions,
		Now:        clock,
		AppBaseURL: "https://app.test",
		IDTokens:   a.tokens,
	})
	a.ids = ids
	fam := family.NewService(family.Deps{
		Pool:          pool,
		Mail:          a.mail,
		Audit:         auditRec,
		Now:           clock,
		AppBaseURL:    "https://app.test",
		InviteLimiter: ratelimit.New(20, 24*time.Hour, clock),
		TokenLimiter:  ratelimit.New(10, time.Minute, clock),
		Log:           log,
	})
	a.par = parental.NewService(parental.Deps{
		Pool:        pool,
		Mail:        a.mail,
		Audit:       auditRec,
		Now:         clock,
		Hash:        identity.HashParams{Memory: 64, Time: 1, Threads: 1},
		AppBaseURL:  "https://app.test",
		CodeLimiter: ratelimit.New(20, time.Hour, clock),
		Log:         log,
	})
	a.videos = &curationtest.Fake{}
	a.thumbs = &curationtest.Thumbs{}
	a.cur = curation.NewService(curation.Deps{
		Pool:              pool,
		Audit:             auditRec,
		Now:               clock,
		Source:            a.videos,
		SuggestLimiter:    ratelimit.New(10, 24*time.Hour, clock),
		MinApprovals:      2,
		MaxDuration:       20 * time.Minute,
		RevisitAfter:      180 * 24 * time.Hour,
		Thumbs:            a.thumbs,
		ShelfSize:         12,
		PackMaxDuration:   20 * time.Minute,
		PackRowSize:       6,
		ReportLimiter:     ratelimit.New(20, 24*time.Hour, clock),
		ReportThreshold:   3,
		CheckVideoLimiter: ratelimit.New(1, time.Hour, clock),
		CheckChildLimiter: ratelimit.New(10, time.Hour, clock),
		Log:               log,
	})
	a.team = staff.NewService(staff.Deps{Pool: pool, Audit: auditRec, Now: clock, MFAKey: testMFAKey, Mail: a.mail, Log: log,
		Accounts: ids, Sessions: sessions, Families: fam, Devices: a.par, Content: a.cur,
		AuditLog:      audit.Store{Pool: pool, Now: clock, Log: log},
		LookupLimiter: ratelimit.New(30, time.Hour, clock), ResetLimiter: ratelimit.New(3, time.Hour, clock)})
	a.st = screentime.NewService(screentime.Deps{Pool: pool, Audit: auditRec, Now: clock, BeatLimiter: ratelimit.New(20, time.Minute, clock), PlayLimiter: ratelimit.New(30, time.Minute, clock)})
	srv := &httpapi.Server{
		Pool:       pool,
		Log:        log,
		Identity:   ids,
		Sessions:   sessions,
		Family:     fam,
		Parental:   a.par,
		Curation:   a.cur,
		Staff:      a.team,
		ScreenTime: a.st,
		Privacy: privacy.NewService(privacy.Deps{
			Pool:          pool,
			Mail:          a.mail,
			Audit:         auditRec,
			Now:           clock,
			ExportLimiter: ratelimit.New(5, time.Hour, clock),
			Log:           log,
			IDTokens:      a.tokens,
			Apple:         a.apple,
		}),
		IPLimiter:     ratelimit.New(30, time.Minute, clock),
		RedeemLimiter: ratelimit.New(10, time.Minute, clock),
	}
	for _, o := range opts {
		o(srv)
	}
	a.server = srv
	a.handler = srv.Handler()
	return a
}

type resp struct {
	*httptest.ResponseRecorder
}

func (r resp) problemCode() string {
	var p struct {
		Code string `json:"code"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &p)
	return p.Code
}

// do sends a JSON body (nil for none) with optional header pairs.
func (a *api) do(method, path string, body any, headers ...string) resp {
	a.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if s, ok := body.(string); ok {
			buf.WriteString(s)
		} else if err := json.NewEncoder(&buf).Encode(body); err != nil {
			a.t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	rec := httptest.NewRecorder()
	a.handler.ServeHTTP(rec, req)
	return resp{rec}
}

var tokenRE = regexp.MustCompile(`token=([A-Za-z0-9_-]+)`)

func (a *api) lastToken(addr string) string {
	a.t.Helper()
	msgs := a.mail.To(addr)
	if len(msgs) == 0 {
		a.t.Fatalf("no mail to %s", addr)
	}
	m := tokenRE.FindStringSubmatch(msgs[len(msgs)-1].Body)
	if m == nil {
		a.t.Fatalf("no token in newest mail to %s", addr)
	}
	return m[1]
}

func signUpBody(email string) map[string]any {
	return map[string]any{"email": email, "password": goodPassword, "adult_declaration": true}
}

type mobileTokens struct {
	SessionID    string `json:"session_id"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

// signUpVerified creates and verifies an account through the API.
func (a *api) signUpVerified(email string) {
	a.t.Helper()
	a.do(http.MethodPost, "/v1/accounts", signUpBody(email))
	if r := a.do(http.MethodPost, "/v1/email-verifications/confirm", map[string]string{"token": a.lastToken(email)}); r.Code != http.StatusNoContent {
		a.t.Fatalf("verify %s: %d", email, r.Code)
	}
}

func (a *api) signInWeb(email string) (cookie, csrf string) {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": email, "password": goodPassword, "client": "web"})
	if r.Code != http.StatusCreated {
		a.t.Fatalf("web sign-in: %d %s", r.Code, r.Body)
	}
	var body struct {
		CSRF string `json:"csrf_token"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &body)
	for _, c := range r.Result().Cookies() {
		if c.Name == "__Host-ts_session" {
			return c.Name + "=" + c.Value, body.CSRF
		}
	}
	a.t.Fatal("no session cookie")
	return "", ""
}

func (a *api) signInMobile(email string) mobileTokens {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": email, "password": goodPassword, "client": "mobile", "device_label": "Pixel 9"})
	if r.Code != http.StatusCreated {
		a.t.Fatalf("mobile sign-in: %d %s", r.Code, r.Body)
	}
	var tok mobileTokens
	_ = json.Unmarshal(r.Body.Bytes(), &tok)
	return tok
}

func decodeTokens(t *testing.T, r resp) mobileTokens {
	t.Helper()
	if r.Code != http.StatusOK && r.Code != http.StatusCreated {
		t.Fatalf("tokens response: %d %s", r.Code, r.Body)
	}
	var tok mobileTokens
	if err := json.Unmarshal(r.Body.Bytes(), &tok); err != nil {
		t.Fatal(err)
	}
	return tok
}

func bearer(tok mobileTokens) []string { return []string{"Authorization", "Bearer " + tok.AccessToken} }

// confirmBody is the 409 body of signup_required and link_required.
type confirmBody struct {
	Code    string   `json:"code"`
	Ticket  string   `json:"ticket"`
	Email   string   `json:"email"`
	Options []string `json:"options"`
}

func decodeConfirm(t *testing.T, r resp, code string) confirmBody {
	t.Helper()
	var b confirmBody
	_ = json.Unmarshal(r.Body.Bytes(), &b)
	if r.Code != http.StatusConflict || b.Code != code || b.Ticket == "" {
		t.Fatalf("want 409 %s with a ticket, got %d %s", code, r.Code, r.Body)
	}
	return b
}

func (a *api) googleToken(sub, email string) string {
	return a.tokens.Issue(idtoken.Google, idtoken.Claims{Subject: sub, Email: email, EmailVerified: true, EmailAuthoritative: true})
}

// providerSignUpMobile signs a new guardian up with Google and returns
// their mobile tokens.
func (a *api) providerSignUpMobile(sub, email string) mobileTokens {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/sessions/provider", map[string]string{"provider": "google", "id_token": a.googleToken(sub, email), "client": "mobile"})
	b := decodeConfirm(a.t, r, "signup_required")
	return decodeTokens(a.t, a.do(http.MethodPost, "/v1/sessions/provider/signup",
		map[string]any{"ticket": b.Ticket, "adult_declaration": true, "client": "mobile"}))
}

// accountID reads the signed-in account's ID.
func (a *api) accountID(tok mobileTokens) string {
	a.t.Helper()
	var body struct {
		Account struct {
			ID string `json:"id"`
		} `json:"account"`
	}
	r := a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...)
	if err := json.Unmarshal(r.Body.Bytes(), &body); err != nil || body.Account.ID == "" {
		a.t.Fatalf("session: %d %s", r.Code, r.Body)
	}
	return body.Account.ID
}

// addMinor registers a child through the API and returns its ID.
func (a *api) addMinor(tok mobileTokens) string {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/family/minors", minorReq(family.ConsentPolicyVersion), bearer(tok)...)
	var m struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &m); r.Code != http.StatusCreated || err != nil {
		a.t.Fatalf("add minor: %d %s", r.Code, r.Body)
	}
	return m.ID
}

// lockedSession makes email a family owner with one child and the PIN
// 2580, and locks their mobile session to that child.
func (a *api) lockedSession(email string) (mobileTokens, string) {
	a.t.Helper()
	tok := a.familyOwner(email)
	minor := a.addMinor(tok)
	id := a.accountID(tok)
	if err := a.par.SetPIN(context.Background(), id, "2580"); err != nil {
		a.t.Fatal(err)
	}
	if err := a.par.EnterKidMode(context.Background(), id, tok.SessionID, minor); err != nil {
		a.t.Fatal(err)
	}
	return tok, minor
}

var wildcard = regexp.MustCompile(`\{[^}]+\}`)

// sweepTarget turns a route pattern into a request line, with every path
// wildcard set to a well-formed but unknown ID.
func sweepTarget(pattern string) (method, path string) {
	method, path, _ = strings.Cut(pattern, " ")
	return method, wildcard.ReplaceAllString(path, "00000000-0000-0000-0000-000000000000")
}

// linkedDevice links a device to minorID through the API and returns its
// token. The family must have a PIN.
func (a *api) linkedDevice(tok mobileTokens, minorID string) string {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/parental/link-codes", map[string]string{"minor_id": minorID}, bearer(tok)...)
	var lc struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &lc); r.Code != http.StatusCreated || err != nil {
		a.t.Fatalf("link code: %d %s", r.Code, r.Body)
	}
	r = a.do(http.MethodPost, "/v1/devices/redeem", map[string]string{"code": lc.Code, "label": "Tablet"})
	var out struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &out); r.Code != http.StatusCreated || err != nil {
		a.t.Fatalf("redeem: %d %s", r.Code, r.Body)
	}
	return out.Token
}

func (a *api) count(sql string, args ...any) int {
	a.t.Helper()
	var n int
	if err := a.pool.QueryRow(context.Background(), sql, args...).Scan(&n); err != nil {
		a.t.Fatal(err)
	}
	return n
}

// testMFAKey seals the TOTP secrets of the API tests.
var testMFAKey = bytes.Repeat([]byte{7}, 32)

// totpCode is secret's TOTP code at the given time.
func totpCode(t *testing.T, secret string, at time.Time) string {
	t.Helper()
	c, err := totp.Code(secret, totp.Step(at))
	if err != nil {
		t.Fatal(err)
	}
	return c
}

// enrollMFA enrolls tok's account through the API, which elevates the
// session, and returns the secret and the recovery codes. It needs the
// session's sign-in re-auth to be fresh (within 5 minutes). The clock
// moves one TOTP step on, so the next code is not the confirm's.
func (a *api) enrollMFA(tok mobileTokens) (string, []string) {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/staff/mfa/enrollment", nil, bearer(tok)...)
	var e struct {
		Secret string `json:"secret"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &e); r.Code != http.StatusCreated || err != nil {
		a.t.Fatalf("enroll: %d %s", r.Code, r.Body)
	}
	r = a.do(http.MethodPost, "/v1/staff/mfa/enrollment/confirm", map[string]string{"code": totpCode(a.t, e.Secret, a.now)}, bearer(tok)...)
	var c struct {
		Codes []string `json:"recovery_codes"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &c); r.Code != http.StatusOK || err != nil {
		a.t.Fatalf("confirm: %d %s", r.Code, r.Body)
	}
	a.now = a.now.Add(totp.Period)
	return e.Secret, c.Codes
}
