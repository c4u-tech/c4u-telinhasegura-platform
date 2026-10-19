package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/accesslog"
)

type accessRow struct {
	account, device, session, ip string
	port                         *int
}

func (a *api) accessRows() []accessRow {
	a.t.Helper()
	rows, err := a.pool.Query(context.Background(), `SELECT coalesce(account_id::text, ''), coalesce(device_id::text, ''),
		coalesce(session_id::text, ''), host(ip), port FROM access_log ORDER BY id`)
	if err != nil {
		a.t.Fatal(err)
	}
	out, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (accessRow, error) {
		var x accessRow
		err := r.Scan(&x.account, &x.device, &x.session, &x.ip, &x.port)
		return x, err
	})
	if err != nil {
		a.t.Fatal(err)
	}
	return out
}

// doFrom is do from the peer address remote.
func (a *api) doFrom(remote, method, path string, body any, headers ...string) resp {
	a.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			a.t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.RemoteAddr = remote
	req.Header.Set("Content-Type", "application/json")
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	rec := httptest.NewRecorder()
	a.handler.ServeHTTP(rec, req)
	return resp{rec}
}

func TestAccessIsRecordedOnSignUpSignInAndRefresh(t *testing.T) {
	a := newAPI(t)
	if r := a.do(http.MethodPost, "/v1/accounts", signUpBody("ana@example.com")); r.Code != http.StatusAccepted {
		t.Fatalf("sign-up: %d", r.Code)
	}
	rows := a.accessRows()
	if len(rows) != 1 || rows[0].account == "" || rows[0].session != "" || rows[0].ip != "192.0.2.1" || rows[0].port != nil {
		t.Fatalf("after sign-up: %+v", rows)
	}
	a.do(http.MethodPost, "/v1/email-verifications/confirm", map[string]string{"token": a.lastToken("ana@example.com")})
	tok := a.signInMobile("ana@example.com")
	if rows = a.accessRows(); len(rows) != 2 || rows[1].session != tok.SessionID || rows[1].account != rows[0].account {
		t.Fatalf("after sign-in: %+v", rows)
	}
	a.now = a.now.Add(10 * time.Minute)
	tok = decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}))
	if n := len(a.accessRows()); n != 2 {
		t.Fatalf("a refresh within the hour added a row: %d", n)
	}
	a.now = a.now.Add(time.Hour)
	decodeTokens(t, a.do(http.MethodPost, "/v1/session/refresh", map[string]string{"refresh_token": tok.RefreshToken}))
	if rows = a.accessRows(); len(rows) != 3 || rows[2].session != tok.SessionID {
		t.Fatalf("a refresh an hour later: %+v", rows)
	}
}

func TestAccessIsRecordedOnProviderSignUp(t *testing.T) {
	a := newAPI(t)
	tok := a.providerSignUpMobile("g-1", "bia@example.com")
	if rows := a.accessRows(); len(rows) != 1 || rows[0].session != tok.SessionID || rows[0].account == "" {
		t.Fatalf("%+v", rows)
	}
}

func TestAccessIsRecordedOncePerHourOnGuardianRoutes(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@example.com")
	cookie, _ := a.signInWeb("ana@example.com")
	base := len(a.accessRows()) // the sign-up and the sign-in
	if r := a.do(http.MethodGet, "/v1/session", nil, "Cookie", cookie); r.Code != http.StatusOK {
		t.Fatalf("session: %d", r.Code)
	}
	if n := len(a.accessRows()); n != base {
		t.Fatalf("same session and address within the hour added a row: %d", n)
	}
	a.doFrom("198.51.100.9:5000", http.MethodGet, "/v1/session", nil, "Cookie", cookie)
	if rows := a.accessRows(); len(rows) != base+1 || rows[base].ip != "198.51.100.9" {
		t.Fatalf("another address: %+v", rows)
	}
	a.now = a.now.Add(2 * time.Hour)
	a.do(http.MethodGet, "/v1/session", nil, "Cookie", cookie)
	if n := len(a.accessRows()); n != base+2 {
		t.Fatalf("two hours later: %d rows, want %d", n, base+2)
	}
}

func TestAccessIsRecordedForALinkedDevice(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	if err := a.par.SetPIN(context.Background(), a.accountID(tok), "2580"); err != nil {
		t.Fatal(err)
	}
	dev := a.linkedDevice(tok, minor)
	if r := a.do(http.MethodGet, "/v1/child/profile", nil, "Authorization", "Bearer "+dev); r.Code != http.StatusOK {
		t.Fatalf("child profile: %d %s", r.Code, r.Body)
	}
	var found bool
	for _, row := range a.accessRows() {
		found = found || (row.device != "" && row.account == "" && row.session == "")
	}
	if !found {
		t.Fatalf("no device row: %+v", a.accessRows())
	}
}

func TestAccessIsRecordedForASessionLockedToAChild(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com")
	base := len(a.accessRows())
	if r := a.doFrom("198.51.100.9:5000", http.MethodGet, "/v1/child/profile", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("child profile: %d %s", r.Code, r.Body)
	}
	rows := a.accessRows()
	if len(rows) != base+1 || rows[base].session != tok.SessionID || rows[base].account == "" || rows[base].device != "" {
		t.Fatalf("%+v", rows)
	}
}

func TestAccessPortComesOnlyFromATrustedProxy(t *testing.T) {
	trusted := func(s *httpapi.Server) { s.TrustedProxies = []netip.Prefix{netip.MustParsePrefix("192.0.2.0/24")} }
	signIn := func(a *api, port string) {
		a.t.Helper()
		r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ana@example.com", "password": goodPassword, "client": "mobile"},
			"X-Real-Port", port)
		if r.Code != http.StatusCreated {
			a.t.Fatalf("sign-in: %d", r.Code)
		}
	}
	a := newAPI(t, trusted)
	a.signUpVerified("ana@example.com")
	signIn(a, "51234")
	signIn(a, "70000")
	rows := a.accessRows()
	if p := rows[len(rows)-2].port; p == nil || *p != 51234 {
		t.Fatalf("trusted proxy's port: %v", p)
	}
	if p := rows[len(rows)-1].port; p != nil {
		t.Fatalf("an invalid port was kept: %d", *p)
	}
	b := newAPI(t) // the peer is not a trusted proxy: anyone could send the header
	b.signUpVerified("ana@example.com")
	signIn(b, "51234")
	if rows := b.accessRows(); rows[len(rows)-1].port != nil {
		t.Fatalf("an untrusted peer's port was kept: %d", *rows[len(rows)-1].port)
	}
}

type failingAccess struct{ calls int }

func (f *failingAccess) Record(context.Context, accesslog.Entry) error {
	f.calls++
	return errors.New("database unavailable")
}

func TestAccessRecordFailureNeverChangesTheResponse(t *testing.T) {
	var logs bytes.Buffer
	fa := &failingAccess{}
	a := newAPI(t, func(s *httpapi.Server) {
		s.Access = fa
		s.Log = slog.New(slog.NewTextHandler(&logs, nil))
	})
	a.signUpVerified("ana@example.com")
	tok := a.signInMobile("ana@example.com")
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(tok)...); r.Code != http.StatusOK {
		t.Fatalf("session: %d", r.Code)
	}
	if fa.calls < 3 {
		t.Fatalf("recorder called %d times, want 3 or more", fa.calls)
	}
	if !strings.Contains(logs.String(), "access log: record failed") || strings.Contains(logs.String(), "192.0.2.1") {
		t.Fatalf("log: %s", logs.String())
	}
}
