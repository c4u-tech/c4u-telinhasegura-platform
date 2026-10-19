package httpapi_test

import (
	"context"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

func providerBody(token, client string) map[string]string {
	return map[string]string{"provider": "google", "id_token": token, "client": client}
}

func TestProviderSignUpThenSignInOnMobile(t *testing.T) {
	a := newAPI(t)
	r := a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "mobile"))
	b := decodeConfirm(t, r, "signup_required")
	if b.Email != "ana@gmail.com" {
		t.Fatalf("email %q", b.Email)
	}
	if r := a.do(http.MethodPost, "/v1/sessions/provider/signup", map[string]any{"ticket": b.Ticket, "adult_declaration": false, "terms_version": identity.TermsVersion, "client": "mobile"}); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("no declaration: %d %s", r.Code, r.Body)
	}
	tok := decodeTokens(t, a.do(http.MethodPost, "/v1/sessions/provider/signup", map[string]any{"ticket": b.Ticket, "adult_declaration": true, "terms_version": identity.TermsVersion, "client": "mobile", "device_label": "Pixel 9"}))
	if tok.AccessToken == "" || tok.RefreshToken == "" {
		t.Fatalf("tokens %+v", tok)
	}
	again := a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "mobile"))
	if again.Code != http.StatusCreated || !strings.Contains(again.Body.String(), `"access_token":"`) {
		t.Fatalf("linked sign-in: %d %s", again.Code, again.Body)
	}
}

func TestLinkWithPasswordOnTheWeb(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@gmail.com")
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "web")), "link_required")
	if !slices.Equal(b.Options, []string{"password", "clear_password"}) {
		t.Fatalf("options %v", b.Options)
	}
	r := a.do(http.MethodPost, "/v1/sessions/provider/link", map[string]string{"ticket": b.Ticket, "password": goodPassword, "client": "web"})
	if r.Code != http.StatusCreated || !strings.Contains(r.Header().Get("Set-Cookie"), "__Host-ts_session=") || !strings.Contains(r.Body.String(), `"csrf_token":"`) {
		t.Fatalf("link: %d %s", r.Code, r.Body)
	}
}

func TestClearPasswordLinkRevokesEarlierSessions(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@gmail.com")
	old := a.signInMobile("ana@gmail.com")
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "mobile")), "link_required")

	fresh := decodeTokens(t, a.do(http.MethodPost, "/v1/sessions/provider/link", map[string]any{"ticket": b.Ticket, "clear_password": true, "client": "mobile"}))
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(old)...); r.Code != http.StatusUnauthorized {
		t.Fatalf("old session: %d", r.Code)
	}
	if r := a.do(http.MethodGet, "/v1/session", nil, bearer(fresh)...); r.Code != http.StatusOK {
		t.Fatalf("new session: %d %s", r.Code, r.Body)
	}
}

func TestLinkBodyNeedsExactlyOneProof(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@gmail.com")
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "web")), "link_required")
	for name, body := range map[string]map[string]any{
		"empty password": {"ticket": b.Ticket, "password": "", "client": "web"},
		"both":           {"ticket": b.Ticket, "password": goodPassword, "clear_password": true, "client": "web"},
	} {
		if r := a.do(http.MethodPost, "/v1/sessions/provider/link", body); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
			t.Errorf("%s: %d %s", name, r.Code, r.Body)
		}
	}
}

func TestProviderSignInErrors(t *testing.T) {
	a := newAPI(t)
	unverified := a.tokens.Issue(idtoken.Google, idtoken.Claims{Subject: "g-1", Email: "ana@gmail.com"})
	if r := a.do(http.MethodPost, "/v1/sessions/provider", providerBody(unverified, "web")); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "provider_email_unverified" {
		t.Fatalf("unverified: %d %s", r.Code, r.Body)
	}
	reused := a.googleToken("g-2", "bia@gmail.com")
	a.do(http.MethodPost, "/v1/sessions/provider", providerBody(reused, "web"))
	if r := a.do(http.MethodPost, "/v1/sessions/provider", providerBody(reused, "web")); r.Code != http.StatusBadRequest || r.problemCode() != "invalid_token" {
		t.Fatalf("reused: %d %s", r.Code, r.Body)
	}
	if r := a.do(http.MethodPost, "/v1/sessions/provider", map[string]string{"provider": "facebook", "id_token": "x", "client": "web"}); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("unknown provider: %d %s", r.Code, r.Body)
	}
	a.tokens.Disabled = []idtoken.Provider{idtoken.Apple}
	if r := a.do(http.MethodPost, "/v1/sessions/provider", map[string]string{"provider": "apple", "id_token": "x", "client": "web"}); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("disabled provider: %d %s", r.Code, r.Body)
	}
}

func TestSecondIdentityOfTheSameProviderConflicts(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@gmail.com")
	first := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "web")), "link_required")
	a.do(http.MethodPost, "/v1/sessions/provider/link", map[string]string{"ticket": first.Ticket, "password": goodPassword, "client": "web"})
	second := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-2", "ana@gmail.com"), "web")), "link_required")
	r := a.do(http.MethodPost, "/v1/sessions/provider/link", map[string]string{"ticket": second.Ticket, "password": goodPassword, "client": "web"})
	if r.Code != http.StatusConflict || r.problemCode() != "identity_conflict" {
		t.Fatalf("%d %s", r.Code, r.Body)
	}
}

func TestReauthWithAProviderToken(t *testing.T) {
	a := newAPI(t)
	ana := a.providerSignUpMobile("g-ana", "ana@gmail.com")
	a.providerSignUpMobile("g-bia", "bia@gmail.com")
	reauth := func(body any) resp { return a.do(http.MethodPost, "/v1/session/reauth", body, bearer(ana)...) }

	if r := reauth(map[string]string{"provider": "google", "id_token": a.googleToken("g-ana", "ana@gmail.com")}); r.Code != http.StatusNoContent {
		t.Fatalf("own identity: %d %s", r.Code, r.Body)
	}
	if r := reauth(map[string]string{"provider": "google", "id_token": a.googleToken("g-bia", "bia@gmail.com")}); r.Code != http.StatusUnauthorized || r.problemCode() != "invalid_credentials" {
		t.Fatalf("foreign identity: %d %s", r.Code, r.Body)
	}
	both := map[string]string{"password": goodPassword, "provider": "google", "id_token": a.googleToken("g-ana", "ana@gmail.com")}
	for name, body := range map[string]any{"both": both, "neither": map[string]string{}} {
		if r := reauth(body); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
			t.Errorf("%s: %d %s", name, r.Code, r.Body)
		}
	}
}

// A squatter's password sign-in that passed its check before the victim's
// clear_password link must not leave a session behind (final review C1).
func TestAPasswordSignInThatLosesToAClearKeepsNoSession(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@gmail.com")
	b := decodeConfirm(t, a.do(http.MethodPost, "/v1/sessions/provider", providerBody(a.googleToken("g-1", "ana@gmail.com"), "mobile")), "link_required")
	// The clear lands right after the squatter's password check.
	a.onAuditKind = audit.SignInSucceeded
	a.onAudit = func() {
		if _, err := a.ids.ProviderLink(context.Background(), b.Ticket, identity.LinkProof{ClearPassword: true}); err != nil {
			t.Errorf("clear: %v", err)
		}
	}

	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ana@gmail.com", "password": goodPassword, "client": "mobile"})
	if r.Code != http.StatusUnauthorized || r.problemCode() != "invalid_credentials" {
		t.Fatalf("squatter sign-in: %d %s", r.Code, r.Body)
	}
	var live int
	if err := a.pool.QueryRow(context.Background(), `SELECT count(*) FROM sessions WHERE revoked_at IS NULL`).Scan(&live); err != nil {
		t.Fatal(err)
	}
	if live != 0 {
		t.Fatalf("%d live sessions after the clear", live)
	}
}

// A squatter's sign-in whose re-check runs while a clear is in flight
// waits for the clear and then sees its version (sibling of C1): the
// re-check locks the account row instead of reading past the clear.
func TestASignInRecheckWaitsForAnInFlightClear(t *testing.T) {
	a := newAPI(t)
	a.signUpVerified("ana@gmail.com")
	ctx := context.Background()
	waited := make(chan bool, 1)
	// Right after the password check, a clear starts: it bumps the version
	// and holds the account until the re-check waits on it.
	a.onAuditKind = audit.SignInSucceeded
	a.onAudit = func() {
		tx, err := a.pool.Begin(ctx)
		if err != nil {
			t.Error(err)
			waited <- false
			return
		}
		var holder int
		if err := tx.QueryRow(ctx, `UPDATE accounts SET password_hash = NULL, credential_version = credential_version + 1
			WHERE email = 'ana@gmail.com' RETURNING pg_backend_pid()`).Scan(&holder); err != nil {
			t.Error(err)
		}
		go func() {
			blocked := false
			for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline) && !blocked; time.Sleep(5 * time.Millisecond) {
				var n int
				_ = a.pool.QueryRow(ctx, `SELECT count(*) FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid))`, holder).Scan(&n)
				blocked = n > 0
			}
			if err := tx.Commit(ctx); err != nil {
				t.Error(err)
			}
			waited <- blocked
		}()
	}

	r := a.do(http.MethodPost, "/v1/sessions", map[string]string{"email": "ana@gmail.com", "password": goodPassword, "client": "mobile"})
	blocked := <-waited
	if r.Code != http.StatusUnauthorized || r.problemCode() != "invalid_credentials" {
		t.Fatalf("squatter sign-in: %d %s", r.Code, r.Body)
	}
	if !blocked {
		t.Fatal("the re-check never waited on the in-flight clear")
	}
	var live int
	if err := a.pool.QueryRow(ctx, `SELECT count(*) FROM sessions WHERE revoked_at IS NULL`).Scan(&live); err != nil {
		t.Fatal(err)
	}
	if live != 0 {
		t.Fatalf("%d live sessions after the clear", live)
	}
}
