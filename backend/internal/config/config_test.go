package config_test

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"net/netip"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/config"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

// env reads m, with the staff MFA switch off unless m sets it, so the
// tests of other settings need no STAFF_MFA_KEY (the switch is on by
// default).
func env(m map[string]string) func(string) string {
	return func(k string) string {
		if v, ok := m[k]; ok || k != "STAFF_MFA_REQUIRED" {
			return v
		}
		return "false"
	}
}

// raw reads m alone, so an unset key reads as unset.
func raw(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadAppliesDefaultsAndSplitsOrigins(t *testing.T) {
	c, err := config.Load(env(map[string]string{
		"DATABASE_URL":    "postgres://x",
		"APP_BASE_URL":    "https://app.test/",
		"ALLOWED_ORIGINS": "https://app.test, http://localhost:5000 ,",
	}))
	if err != nil {
		t.Fatal(err)
	}
	want := config.Config{
		Addr:                    ":8080",
		DatabaseURL:             "postgres://x",
		AppBaseURL:              "https://app.test",
		AllowedOrigins:          []string{"https://app.test", "http://localhost:5000"},
		MailDir:                 "tmp/mail",
		HIBPEnabled:             true,
		CurationMinApprovals:    2,
		CurationMaxDuration:     20 * time.Minute,
		CurationRevisitDays:     180,
		CatalogShelfSize:        12,
		CurationReportThreshold: 3,
		SweepInterval:           time.Hour,
		PackMaxDuration:         20 * time.Minute,
		PackRowSize:             6,
		MailAllowed:             noMailAllowlist(t),
		MailPollInterval:        5 * time.Second,
	}
	if !reflect.DeepEqual(c, want) {
		t.Fatalf("got %+v, want %+v", c, want)
	}
}

// noMailAllowlist is what Load yields without MAIL_ALLOWED_RECIPIENTS: an
// allowlist built empty, which DeepEqual tells from the zero value.
func noMailAllowlist(t *testing.T) mail.Allowlist {
	t.Helper()
	a, err := mail.ParseAllowlist("")
	if err != nil {
		t.Fatal(err)
	}
	return a
}

func TestLoadRequiresDatabaseAndAppBaseURL(t *testing.T) {
	if _, err := config.Load(env(map[string]string{"APP_BASE_URL": "https://a"})); err == nil {
		t.Fatal("missing DATABASE_URL accepted")
	}
	if _, err := config.Load(env(map[string]string{"DATABASE_URL": "postgres://x"})); err == nil {
		t.Fatal("missing APP_BASE_URL accepted")
	}
}

func TestLoadDisablesHIBPOnlyWhenFalse(t *testing.T) {
	c, err := config.Load(env(map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y", "HIBP_ENABLED": "false"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.HIBPEnabled {
		t.Fatal("HIBP_ENABLED=false left the check enabled")
	}
}

func TestLoadReadsProviderClientIDs(t *testing.T) {
	c, err := config.Load(env(map[string]string{
		"DATABASE_URL": "x", "APP_BASE_URL": "y",
		"GOOGLE_CLIENT_IDS":   "web.apps.googleusercontent.com, ios.apps.googleusercontent.com",
		"APPLE_CLIENT_IDS":    "tech.coding4u.telinhasegura,tech.coding4u.telinhasegura.web",
		"APP_ANDROID_PACKAGE": "tech.coding4u.telinhasegura",
		"APPLE_TEAM_ID":       "TEAM123456", "APPLE_KEY_ID": "KEY1234567", "APPLE_PRIVATE_KEY": appleKeyPEM(t),
	}))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(c.GoogleClientIDs, []string{"web.apps.googleusercontent.com", "ios.apps.googleusercontent.com"}) ||
		!reflect.DeepEqual(c.AppleClientIDs, []string{"tech.coding4u.telinhasegura", "tech.coding4u.telinhasegura.web"}) ||
		c.AndroidPackage != "tech.coding4u.telinhasegura" {
		t.Fatalf("got %+v", c)
	}
}

func TestLoadRequiresTheAndroidPackageWithApple(t *testing.T) {
	_, err := config.Load(env(map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y", "APPLE_CLIENT_IDS": "tech.coding4u.telinhasegura"}))
	if err == nil {
		t.Fatal("Apple without APP_ANDROID_PACKAGE accepted")
	}
}

func TestLoadReadsCurationSettings(t *testing.T) {
	c, err := config.Load(env(map[string]string{
		"DATABASE_URL": "x", "APP_BASE_URL": "y",
		"YOUTUBE_API_KEY":        " AIza-test ",
		"CURATION_MIN_APPROVALS": "3",
		"CURATION_MAX_DURATION":  "15m",
		"CURATION_REVISIT_DAYS":  "90",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.YouTubeAPIKey != "AIza-test" || c.CurationMinApprovals != 3 || c.CurationMaxDuration != 15*time.Minute ||
		c.CurationRevisitDays != 90 {
		t.Fatalf("got %+v", c)
	}
}

func TestLoadRefusesBadCurationSettings(t *testing.T) {
	for name, values := range map[string][]string{
		"CURATION_MIN_APPROVALS": {"0", "-1", "two", "1.5"},
		"CURATION_MAX_DURATION":  {"20", "0s", "-5m", "forever"},
		"CURATION_REVISIT_DAYS":  {"0", "x", "36501"},
	} {
		for _, v := range values {
			_, err := config.Load(env(map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y", name: v}))
			if err == nil || !strings.Contains(err.Error(), name) {
				t.Errorf("%s=%q: %v", name, v, err)
			}
		}
	}
}

func TestLoadReadsCatalogSettings(t *testing.T) {
	c, err := config.Load(env(map[string]string{
		"DATABASE_URL": "x", "APP_BASE_URL": "y",
		"CATALOG_SHELF_SIZE":        "8",
		"CURATION_REPORT_THRESHOLD": "5",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.CatalogShelfSize != 8 || c.CurationReportThreshold != 5 {
		t.Fatalf("got %+v", c)
	}
}

func TestLoadRefusesBadCatalogSettings(t *testing.T) {
	for name, values := range map[string][]string{
		"CATALOG_SHELF_SIZE":        {"0", "51", "doze", "1.5"},
		"CURATION_REPORT_THRESHOLD": {"0", "-1", "três"},
	} {
		for _, v := range values {
			_, err := config.Load(env(map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y", name: v}))
			if err == nil || !strings.Contains(err.Error(), name) {
				t.Errorf("%s=%q: %v", name, v, err)
			}
		}
	}
}

func TestSweepInterval(t *testing.T) {
	base := map[string]string{"DATABASE_URL": "postgres://x", "APP_BASE_URL": "https://app.test", "STAFF_MFA_REQUIRED": "false"}
	get := func(extra map[string]string) func(string) string {
		return func(k string) string {
			if v, ok := extra[k]; ok {
				return v
			}
			return base[k]
		}
	}
	c, err := config.Load(get(nil))
	if err != nil || c.SweepInterval != time.Hour {
		t.Fatalf("default %v %v", c.SweepInterval, err)
	}
	if c, err := config.Load(get(map[string]string{"SWEEP_INTERVAL": "5m"})); err != nil || c.SweepInterval != 5*time.Minute {
		t.Fatalf("5m %v %v", c.SweepInterval, err)
	}
	for _, v := range []string{"30s", "25h", "soon"} {
		if _, err := config.Load(get(map[string]string{"SWEEP_INTERVAL": v})); err == nil || !strings.Contains(err.Error(), "SWEEP_INTERVAL") {
			t.Errorf("%s: %v", v, err)
		}
	}
}

func TestLoadReadsPackSettings(t *testing.T) {
	c, err := config.Load(env(map[string]string{
		"DATABASE_URL": "x", "APP_BASE_URL": "y",
		"PACK_MAX_DURATION": "15m",
		"PACK_ROW_SIZE":     "12",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.PackMaxDuration != 15*time.Minute || c.PackRowSize != 12 {
		t.Fatalf("got %+v", c)
	}
}

func TestLoadRefusesBadPackSettings(t *testing.T) {
	for name, values := range map[string][]string{
		"PACK_MAX_DURATION": {"0", "-5m", "vinte", "20"},
		"PACK_ROW_SIZE":     {"0", "13", "seis", "1.5"},
	} {
		for _, v := range values {
			_, err := config.Load(env(map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y", name: v}))
			if err == nil || !strings.Contains(err.Error(), name) {
				t.Errorf("%s=%q: %v", name, v, err)
			}
		}
	}
}

func TestLoadReadsTheStaffMFASettings(t *testing.T) {
	with := func(kv ...string) map[string]string {
		m := map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y"}
		for i := 0; i+1 < len(kv); i += 2 {
			m[kv[i]] = kv[i+1]
		}
		return m
	}
	bits := bytes.Repeat([]byte{7}, 32)
	key := base64.StdEncoding.EncodeToString(bits)

	// On by default: a key alone turns it on.
	c, err := config.Load(raw(with("STAFF_MFA_KEY", key)))
	if err != nil || !c.StaffMFARequired || !bytes.Equal(c.StaffMFAKey, bits) {
		t.Fatalf("a key alone: required=%v key=%x %v", c.StaffMFARequired, c.StaffMFAKey, err)
	}
	if c, err = config.Load(raw(with("STAFF_MFA_REQUIRED", "false", "STAFF_MFA_KEY", " "+key+" "))); err != nil || c.StaffMFARequired {
		t.Fatalf("the switch off with a key: %v %v", c.StaffMFARequired, err)
	}
	// Only "false" turns it off, so a typo keeps it on.
	for _, v := range []string{"true", "", "0", "FALSE", "no", "off"} {
		if c, err = config.Load(raw(with("STAFF_MFA_REQUIRED", v, "STAFF_MFA_KEY", key))); err != nil || !c.StaffMFARequired {
			t.Errorf("STAFF_MFA_REQUIRED=%q: on=%v %v", v, c.StaffMFARequired, err)
		}
	}
	for _, m := range []map[string]string{with(), with("STAFF_MFA_REQUIRED", "true")} {
		if _, err := config.Load(raw(m)); err == nil || !strings.Contains(err.Error(), "STAFF_MFA_KEY") {
			t.Errorf("the switch on without a key (%v): %v", m, err)
		}
	}
	if c, err = config.Load(raw(with("STAFF_MFA_REQUIRED", "false"))); err != nil || c.StaffMFARequired || c.StaffMFAKey != nil {
		t.Fatalf("the switch off without a key: %v %x %v", c.StaffMFARequired, c.StaffMFAKey, err)
	}
	short := base64.StdEncoding.EncodeToString(bits[:16])
	for _, bad := range []string{short, "not base64!"} {
		_, err := config.Load(raw(with("STAFF_MFA_REQUIRED", "false", "STAFF_MFA_KEY", bad)))
		if err == nil {
			t.Errorf("key %q accepted", bad)
		} else if strings.Contains(err.Error(), bad) {
			t.Errorf("the error echoes the key: %v", err)
		}
	}
}

func TestLoadReadsTrustedProxies(t *testing.T) {
	with := func(v string) map[string]string {
		return map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y", "TRUSTED_PROXIES": v}
	}
	c, err := config.Load(env(with(" 10.0.0.0/8, 172.17.0.1 ,")))
	want := []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8"), netip.MustParsePrefix("172.17.0.1/32")}
	if err != nil || !slices.Equal(c.TrustedProxies, want) {
		t.Fatalf("got %v %v, want %v", c.TrustedProxies, err, want)
	}
	if c, err = config.Load(env(with(""))); err != nil || c.TrustedProxies != nil {
		t.Fatalf("unset: %v %v, want nil", c.TrustedProxies, err)
	}
	_, err = config.Load(env(with("10.0.0.0/8,proxy.local")))
	if err == nil || !strings.Contains(err.Error(), "TRUSTED_PROXIES") || !strings.Contains(err.Error(), "proxy.local") {
		t.Fatalf("bad entry: %v, want an error naming the setting and the entry", err)
	}
}

func smtpEnv(over map[string]string) func(string) string {
	m := map[string]string{
		"DATABASE_URL":  "postgres://x",
		"APP_BASE_URL":  "https://app.test",
		"SMTP_HOST":     "smtp.mailgun.org",
		"SMTP_USERNAME": "postmaster@mail.example.com",
		"SMTP_PASSWORD": "s3cret-pass",
		"MAIL_FROM":     "Telinha Segura <nao-responda@mail.example.com>",
	}
	for k, v := range over {
		m[k] = v
	}
	return env(m)
}

func TestLoadReadsTheSMTPSettings(t *testing.T) {
	c, err := config.Load(smtpEnv(map[string]string{"MAIL_ALLOWED_RECIPIENTS": "qa@example.com,@coding4u.tech"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.SMTPHost != "smtp.mailgun.org" || c.SMTPPort != 587 || c.SMTPUsername != "postmaster@mail.example.com" ||
		c.SMTPPassword != "s3cret-pass" || c.MailFrom != "Telinha Segura <nao-responda@mail.example.com>" ||
		c.MailPollInterval != 5*time.Second || c.MailAllowed.Empty() || !c.MailAllowed.Allows("ana@coding4u.tech") {
		t.Fatalf("config %+v", c)
	}
	c, err = config.Load(env(map[string]string{"DATABASE_URL": "postgres://x", "APP_BASE_URL": "https://app.test"}))
	if err != nil || c.SMTPHost != "" || !c.MailAllowed.Empty() || c.MailDir != "tmp/mail" {
		t.Fatalf("without SMTP_HOST: %+v %v", c, err)
	}
}

func TestLoadRefusesIncompleteOrMalformedMailSettings(t *testing.T) {
	for name, over := range map[string]map[string]string{
		"SMTP_USERNAME":           {"SMTP_USERNAME": ""},
		"SMTP_PASSWORD":           {"SMTP_PASSWORD": ""},
		"MAIL_FROM":               {"MAIL_FROM": ""},
		"MAIL_FROM ":              {"MAIL_FROM": "not a mailbox"},
		"SMTP_PORT":               {"SMTP_PORT": "smtp"},
		"SMTP_PORT ":              {"SMTP_PORT": "70000"},
		"MAIL_POLL_INTERVAL":      {"MAIL_POLL_INTERVAL": "500ms"},
		"MAIL_POLL_INTERVAL ":     {"MAIL_POLL_INTERVAL": "2m"},
		"MAIL_ALLOWED_RECIPIENTS": {"MAIL_ALLOWED_RECIPIENTS": "qa"},
	} {
		_, err := config.Load(smtpEnv(over))
		if err == nil || !strings.Contains(err.Error(), strings.TrimSpace(name)) || strings.Contains(err.Error(), "s3cret-pass") {
			t.Errorf("%s: %v", name, err)
		}
	}
}

// appleKeyPEM generates a P-256 key in PKCS#8 PEM, like an Apple .p8.
func appleKeyPEM(t *testing.T) string {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	b, err := x509.MarshalPKCS8PrivateKey(k)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: b}))
}

func TestLoadRequiresTheAppleKeyWithApple(t *testing.T) {
	der := appleKeyPEM(t)
	base := map[string]string{"DATABASE_URL": "x", "APP_BASE_URL": "y"}
	apple := func(extra map[string]string) map[string]string {
		m := map[string]string{"APPLE_CLIENT_IDS": "br.example.app", "APP_ANDROID_PACKAGE": "br.example.app", "APPLE_TEAM_ID": "TEAM123456", "APPLE_KEY_ID": "KEY1234567", "APPLE_PRIVATE_KEY": der}
		for k, v := range base {
			m[k] = v
		}
		for k, v := range extra {
			if v == "-" {
				delete(m, k)
			} else {
				m[k] = v
			}
		}
		return m
	}
	if c, err := config.Load(env(base)); err != nil || c.AppleKey != nil {
		t.Fatalf("Apple off: %v %+v", err, c.AppleKey)
	}
	for _, name := range []string{"APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY"} {
		if _, err := config.Load(env(apple(map[string]string{name: "-"}))); err == nil || !strings.Contains(err.Error(), name) {
			t.Fatalf("without %s: %v", name, err)
		}
	}
	_, err := config.Load(env(apple(map[string]string{"APPLE_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nc2VjcmV0\n-----END PRIVATE KEY-----"})))
	if err == nil || !strings.Contains(err.Error(), "APPLE_PRIVATE_KEY") || strings.Contains(err.Error(), "c2VjcmV0") {
		t.Fatalf("bad key: %v", err)
	}
	c, err := config.Load(env(apple(nil)))
	if err != nil || c.AppleKey == nil || c.AppleTeamID != "TEAM123456" || c.AppleKeyID != "KEY1234567" {
		t.Fatalf("good key: %v %+v", err, c)
	}
}
