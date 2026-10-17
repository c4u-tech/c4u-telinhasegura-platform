package httpapi_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
)

func withApple(s *httpapi.Server) { s.AppleAndroidPackage = "tech.coding4u.telinhasegura" }

func (a *api) postForm(path, form string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(form))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rec := httptest.NewRecorder()
	a.handler.ServeHTTP(rec, req)
	return rec
}

func TestAppleCallbackRelaysTheFormToTheAndroidApp(t *testing.T) {
	a := newAPI(t, withApple)
	r := a.postForm("/v1/oauth/apple/callback", `state=s1&code=c1&id_token=t1&user=%7B%22name%22%3A1%7D`)
	want := `intent://callback?code=c1&id_token=t1&state=s1&user=%7B%22name%22%3A1%7D#Intent;package=tech.coding4u.telinhasegura;scheme=signinwithapple;end`
	if r.Code != http.StatusSeeOther || r.Header().Get("Location") != want {
		t.Fatalf("%d %q", r.Code, r.Header().Get("Location"))
	}
}

func TestAppleCallbackRelaysAnEmptyForm(t *testing.T) {
	a := newAPI(t, withApple)
	r := a.postForm("/v1/oauth/apple/callback", "")
	if r.Code != http.StatusSeeOther || r.Header().Get("Location") != "intent://callback?#Intent;package=tech.coding4u.telinhasegura;scheme=signinwithapple;end" {
		t.Fatalf("%d %q", r.Code, r.Header().Get("Location"))
	}
}

func TestAppleCallbackCannotInjectIntentSyntax(t *testing.T) {
	a := newAPI(t, withApple)
	r := a.postForm("/v1/oauth/apple/callback", `code=x%23Intent%3Bpackage%3Devil%3Bend&state=%3B`)
	want := `intent://callback?code=x%23Intent%3Bpackage%3Devil%3Bend&state=%3B#Intent;package=tech.coding4u.telinhasegura;scheme=signinwithapple;end`
	loc := r.Header().Get("Location")
	if r.Code != http.StatusSeeOther || loc != want {
		t.Fatalf("%d %q", r.Code, loc)
	}
	if _, frag, _ := strings.Cut(loc, "#"); frag != "Intent;package=tech.coding4u.telinhasegura;scheme=signinwithapple;end" {
		t.Fatalf("intent fragment %q", frag)
	}
}

func TestAppleCallbackIsAbsentWithoutApple(t *testing.T) {
	a := newAPI(t)
	if r := a.postForm("/v1/oauth/apple/callback", "code=c1"); r.Code != http.StatusNotFound {
		t.Fatalf("%d", r.Code)
	}
}
