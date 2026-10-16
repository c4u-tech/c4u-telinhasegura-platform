// Package config reads the API's settings from the environment.
package config

import (
	"crypto/ecdsa"
	"encoding/base64"
	"errors"
	"fmt"
	"math"
	netmail "net/mail"
	"net/netip"
	"strconv"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/appleid"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/clientip"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

type Config struct {
	Addr                    string
	DatabaseURL             string
	AppBaseURL              string // links in emails are built only from this
	AllowedOrigins          []string
	GoogleClientIDs         []string
	AppleClientIDs          []string
	AndroidPackage          string
	MailDir                 string
	HIBPEnabled             bool
	YouTubeAPIKey           string // empty: a suggestion needing YouTube answers 503
	CurationMinApprovals    int
	CurationMaxDuration     time.Duration
	CurationRevisitDays     int
	CatalogShelfSize        int            // videos per theme on a child's shelf
	CurationReportThreshold int            // distinct families' reports that hold a video
	SweepInterval           time.Duration  // how often the sweep runs
	PackMaxDuration         time.Duration  // the longest total of a pack's videos
	PackRowSize             int            // packs in a child's row
	StaffMFARequired        bool           // admin and moderator routes need an elevation
	StaffMFAKey             []byte         // seals TOTP secrets; nil: the MFA routes answer 503
	TrustedProxies          []netip.Prefix // peers whose X-Forwarded-For is believed

	SMTPHost         string // empty: mail goes to .eml files under MAIL_DIR
	SMTPPort         int    // 465 means implicit TLS
	SMTPUsername     string
	SMTPPassword     string         // never logged nor echoed in an error
	MailFrom         string         // a mailbox, e.g. "Telinha Segura <nao-responda@mail.example>"
	MailAllowed      mail.Allowlist // empty: everyone (staging confines it)
	MailPollInterval time.Duration  // how often the worker drains the outbox

	// Sign Apple client secrets; required with APPLE_CLIENT_IDS.
	AppleTeamID string
	AppleKeyID  string
	AppleKey    *ecdsa.PrivateKey
}

func Load(getenv func(string) string) (Config, error) {
	c := Config{
		Addr:           orDefault(getenv("HTTP_ADDR"), ":8080"),
		DatabaseURL:    getenv("DATABASE_URL"),
		AppBaseURL:     strings.TrimRight(getenv("APP_BASE_URL"), "/"),
		MailDir:        orDefault(getenv("MAIL_DIR"), "tmp/mail"),
		HIBPEnabled:    getenv("HIBP_ENABLED") != "false",
		AndroidPackage: strings.TrimSpace(getenv("APP_ANDROID_PACKAGE")),
		YouTubeAPIKey:  strings.TrimSpace(getenv("YOUTUBE_API_KEY")),
	}
	c.AllowedOrigins = csv(getenv("ALLOWED_ORIGINS"))
	c.GoogleClientIDs = csv(getenv("GOOGLE_CLIENT_IDS"))
	c.AppleClientIDs = csv(getenv("APPLE_CLIENT_IDS"))
	if c.DatabaseURL == "" {
		return Config{}, errors.New("config: DATABASE_URL is required")
	}
	if c.AppBaseURL == "" {
		return Config{}, errors.New("config: APP_BASE_URL is required")
	}
	if len(c.AppleClientIDs) > 0 && c.AndroidPackage == "" {
		return Config{}, errors.New("config: APP_ANDROID_PACKAGE is required when APPLE_CLIENT_IDS is set")
	}
	var err error
	if len(c.AppleClientIDs) > 0 {
		c.AppleTeamID = strings.TrimSpace(getenv("APPLE_TEAM_ID"))
		c.AppleKeyID = strings.TrimSpace(getenv("APPLE_KEY_ID"))
		for _, kv := range []struct{ name, v string }{
			{"APPLE_TEAM_ID", c.AppleTeamID}, {"APPLE_KEY_ID", c.AppleKeyID}, {"APPLE_PRIVATE_KEY", getenv("APPLE_PRIVATE_KEY")},
		} {
			if strings.TrimSpace(kv.v) == "" {
				return Config{}, fmt.Errorf("config: %s is required when APPLE_CLIENT_IDS is set", kv.name)
			}
		}
		if c.AppleKey, err = appleid.ParseKey(getenv("APPLE_PRIVATE_KEY")); err != nil {
			return Config{}, fmt.Errorf("config: APPLE_PRIVATE_KEY: %w", err) // ParseKey never quotes the key
		}
	}
	if c.TrustedProxies, err = clientip.ParseList(getenv("TRUSTED_PROXIES")); err != nil {
		return Config{}, fmt.Errorf("config: TRUSTED_PROXIES: %w", err)
	}
	if c.CurationMinApprovals, err = intSetting(getenv, "CURATION_MIN_APPROVALS", 2, 1, math.MaxInt32); err != nil {
		return Config{}, err
	}
	// The upper bound keeps days * 24h inside a time.Duration.
	if c.CurationRevisitDays, err = intSetting(getenv, "CURATION_REVISIT_DAYS", 180, 1, 36500); err != nil {
		return Config{}, err
	}
	if c.CurationMaxDuration, err = durationSetting(getenv, "CURATION_MAX_DURATION", 20*time.Minute); err != nil {
		return Config{}, err
	}
	if c.CatalogShelfSize, err = intSetting(getenv, "CATALOG_SHELF_SIZE", 12, 1, 50); err != nil {
		return Config{}, err
	}
	if c.CurationReportThreshold, err = intSetting(getenv, "CURATION_REPORT_THRESHOLD", 3, 1, math.MaxInt32); err != nil {
		return Config{}, err
	}
	if c.SweepInterval, err = durationSetting(getenv, "SWEEP_INTERVAL", time.Hour); err != nil {
		return Config{}, err
	}
	if c.SweepInterval < time.Minute || c.SweepInterval > 24*time.Hour {
		return Config{}, fmt.Errorf("config: SWEEP_INTERVAL must be from 1m to 24h, got %s", c.SweepInterval)
	}
	if c.PackMaxDuration, err = durationSetting(getenv, "PACK_MAX_DURATION", 20*time.Minute); err != nil {
		return Config{}, err
	}
	if c.PackRowSize, err = intSetting(getenv, "PACK_ROW_SIZE", 6, 1, 12); err != nil {
		return Config{}, err
	}
	// The switch is off only when spelled "false", so a typo keeps admin
	// power behind the second factor. On without a
	// key would lock every admin out, so boot refuses it.
	c.StaffMFARequired = getenv("STAFF_MFA_REQUIRED") != "false"
	if c.StaffMFAKey, err = keySetting(getenv, "STAFF_MFA_KEY"); err != nil {
		return Config{}, err
	}
	if c.StaffMFARequired && c.StaffMFAKey == nil {
		return Config{}, errors.New("config: STAFF_MFA_KEY is required when STAFF_MFA_REQUIRED is true")
	}
	if c.MailAllowed, err = mail.ParseAllowlist(getenv("MAIL_ALLOWED_RECIPIENTS")); err != nil {
		return Config{}, fmt.Errorf("config: MAIL_ALLOWED_RECIPIENTS: %w", err)
	}
	if c.MailPollInterval, err = durationSetting(getenv, "MAIL_POLL_INTERVAL", 5*time.Second); err != nil {
		return Config{}, err
	}
	if c.MailPollInterval < time.Second || c.MailPollInterval > time.Minute {
		return Config{}, fmt.Errorf("config: MAIL_POLL_INTERVAL must be from 1s to 1m, got %s", c.MailPollInterval)
	}
	if c.SMTPHost = strings.TrimSpace(getenv("SMTP_HOST")); c.SMTPHost != "" {
		if err := c.loadSMTP(getenv); err != nil {
			return Config{}, err
		}
	}
	return c, nil
}

// loadSMTP reads the settings SMTP_HOST requires. No error carries
// SMTP_PASSWORD: it is a secret.
func (c *Config) loadSMTP(getenv func(string) string) error {
	var err error
	if c.SMTPPort, err = intSetting(getenv, "SMTP_PORT", 587, 1, 65535); err != nil {
		return err
	}
	c.SMTPUsername = strings.TrimSpace(getenv("SMTP_USERNAME"))
	c.SMTPPassword = getenv("SMTP_PASSWORD")
	c.MailFrom = strings.TrimSpace(getenv("MAIL_FROM"))
	for name, v := range map[string]string{"SMTP_USERNAME": c.SMTPUsername, "SMTP_PASSWORD": c.SMTPPassword, "MAIL_FROM": c.MailFrom} {
		if v == "" {
			return fmt.Errorf("config: %s is required when SMTP_HOST is set", name)
		}
	}
	if _, err := netmail.ParseAddress(c.MailFrom); err != nil {
		return fmt.Errorf("config: MAIL_FROM must be a mailbox such as \"Telinha Segura <nao-responda@mail.example.com>\", got %q", c.MailFrom)
	}
	return nil
}

func orDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}

// csv splits a comma-separated list, dropping blanks.
func csv(v string) []string {
	var out []string
	for _, s := range strings.Split(v, ",") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// intSetting reads an integer setting in [lo, hi], or def when unset.
func intSetting(getenv func(string) string, name string, def, lo, hi int) (int, error) {
	v := strings.TrimSpace(getenv(name))
	if v == "" {
		return def, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < lo || n > hi {
		return 0, fmt.Errorf("config: %s must be an integer from %d to %d, got %q", name, lo, hi, v)
	}
	return n, nil
}

// durationSetting reads a positive Go duration ("20m"), or def when unset.
func durationSetting(getenv func(string) string, name string, def time.Duration) (time.Duration, error) {
	v := strings.TrimSpace(getenv(name))
	if v == "" {
		return def, nil
	}
	d, err := time.ParseDuration(v)
	if err != nil || d <= 0 {
		return 0, fmt.Errorf("config: %s must be a positive duration such as 20m, got %q", name, v)
	}
	return d, nil
}

// keySetting reads a 32-byte key in standard base64, or nil when unset.
// A set but malformed key stops the API from starting, even with the
// switch off, so a mistyped secret surfaces at deploy rather than as a
// quiet 503. The error never
// carries the value: it is a secret.
func keySetting(getenv func(string) string, name string) ([]byte, error) {
	v := strings.TrimSpace(getenv(name))
	if v == "" {
		return nil, nil
	}
	k, err := base64.StdEncoding.DecodeString(v)
	if err != nil || len(k) != 32 {
		return nil, fmt.Errorf("config: %s must be 32 bytes in standard base64 (openssl rand -base64 32)", name)
	}
	return k, nil
}
