package repoconfig

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// renderConfig runs app/deploy/render-config.sh with only the given
// variables (plus PATH) and returns the output directory.
func renderConfig(t *testing.T, env map[string]string) (string, string, error) {
	t.Helper()
	out := filepath.Join(t.TempDir(), "telinha")
	cmd := exec.Command("sh", filepath.Join(Root(), "app", "deploy", "render-config.sh"), out)
	cmd.Env = []string{"PATH=" + os.Getenv("PATH")}
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	err := cmd.Run()
	return out, stderr.String(), err
}

func readConfig(t *testing.T, out string) map[string]string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(out, "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]string
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("config.json is not JSON: %v\n%s", err, b)
	}
	return m
}

func TestRenderConfigWritesEveryField(t *testing.T) {
	out, stderr, err := renderConfig(t, map[string]string{
		"API_BASE_URL":            "https://api.test",
		"GOOGLE_CLIENT_ID":        "g1.apps.googleusercontent.com",
		"GOOGLE_SERVER_CLIENT_ID": "g2",
		"APPLE_SERVICES_ID":       "br.example.web",
		"APPLE_REDIRECT_URI":      "https://app.test",
	})
	if err != nil {
		t.Fatalf("render: %v\n%s", err, stderr)
	}
	want := map[string]string{
		"apiBaseUrl":           "https://api.test",
		"googleClientId":       "g1.apps.googleusercontent.com",
		"googleServerClientId": "g2",
		"appleServicesId":      "br.example.web",
		"appleRedirectUri":     "https://app.test",
	}
	got := readConfig(t, out)
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

func TestRenderConfigLeavesUnsetProvidersEmpty(t *testing.T) {
	out, stderr, err := renderConfig(t, map[string]string{"API_BASE_URL": "http://localhost:8080"})
	if err != nil {
		t.Fatalf("render: %v\n%s", err, stderr)
	}
	got := readConfig(t, out)
	for _, k := range []string{"googleClientId", "googleServerClientId", "appleServicesId", "appleRedirectUri"} {
		if v, ok := got[k]; !ok || v != "" {
			t.Errorf("%s = %q (present %v), want present and empty", k, v, ok)
		}
	}
}

func TestRenderConfigTrimsATrailingSlash(t *testing.T) {
	out, stderr, err := renderConfig(t, map[string]string{"API_BASE_URL": "https://api.test/"})
	if err != nil {
		t.Fatalf("render: %v\n%s", err, stderr)
	}
	if got := readConfig(t, out)["apiBaseUrl"]; got != "https://api.test" {
		t.Errorf("apiBaseUrl = %q, want https://api.test", got)
	}
}

func TestRenderConfigRefusesABadAPIOrigin(t *testing.T) {
	for _, bad := range []string{"", "api.test", "ftp://api.test", "http://api.test", "https://api.test/v1", "https://user@api.test", "https://api.test?x", "https://api test", "https://api.test;x"} {
		t.Run(bad, func(t *testing.T) {
			out, stderr, err := renderConfig(t, map[string]string{"API_BASE_URL": bad})
			if err == nil {
				t.Fatalf("API_BASE_URL=%q rendered", bad)
			}
			if !strings.Contains(stderr, "API_BASE_URL") {
				t.Errorf("stderr %q does not name API_BASE_URL", stderr)
			}
			if _, err := os.Stat(filepath.Join(out, "config.json")); err == nil {
				t.Error("a refused render left a config.json")
			}
		})
	}
}

func TestRenderConfigRefusesAValueThatBreaksTheJSON(t *testing.T) {
	for _, bad := range []string{`a"b`, `a\b`, "a\nb", "a\tb", "a\rb"} {
		t.Run(bad, func(t *testing.T) {
			_, stderr, err := renderConfig(t, map[string]string{"API_BASE_URL": "https://api.test", "GOOGLE_CLIENT_ID": bad})
			if err == nil || !strings.Contains(stderr, "GOOGLE_CLIENT_ID") {
				t.Errorf("err %v, stderr %q; want a refusal naming GOOGLE_CLIENT_ID", err, stderr)
			}
		})
	}
}

func TestRenderConfigWritesTheSecurityHeaders(t *testing.T) {
	out, stderr, err := renderConfig(t, map[string]string{"API_BASE_URL": "https://api.test"})
	if err != nil {
		t.Fatalf("render: %v\n%s", err, stderr)
	}
	b, err := os.ReadFile(filepath.Join(out, "headers.conf"))
	if err != nil {
		t.Fatal(err)
	}
	h := string(b)
	for _, want := range []string{
		`add_header Cache-Control "no-cache" always;`,
		`add_header Strict-Transport-Security "max-age=31536000" always;`,
		`add_header X-Content-Type-Options "nosniff" always;`,
		`add_header Referrer-Policy "strict-origin-when-cross-origin" always;`,
		`add_header Content-Security-Policy "`,
		"default-src 'self'",
		"connect-src 'self' https://api.test ",
		"img-src 'self' data: blob: https://api.test",
		"frame-src https://accounts.google.com/gsi/ https://appleid.apple.com https://www.youtube-nocookie.com https://www.youtube.com",
		"frame-ancestors 'none'",
		"script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://accounts.google.com/gsi/client https://appleid.cdn-apple.com https://www.youtube.com https://s.ytimg.com",
		"object-src 'none'",
	} {
		if !strings.Contains(h, want) {
			t.Errorf("headers.conf lacks %q\n%s", want, h)
		}
	}
}
