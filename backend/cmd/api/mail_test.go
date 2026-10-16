package main

import (
	"bytes"
	"log/slog"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/config"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

func TestMailSinkIsSMTPWhenConfiguredAndNeverLogsThePassword(t *testing.T) {
	var logs bytes.Buffer
	allowed, _ := mail.ParseAllowlist("@coding4u.tech")
	cfg := config.Config{SMTPHost: "smtp.mailgun.org", SMTPPort: 465, SMTPUsername: "u", SMTPPassword: "s3cret-pass",
		MailFrom: "T <n@mail.example.com>", MailAllowed: allowed}
	s, ok := mailSink(cfg, slog.New(slog.NewTextHandler(&logs, nil))).(mail.SMTPSender)
	if !ok || !s.ImplicitTLS || s.Host != "smtp.mailgun.org" || s.Password != "s3cret-pass" || s.From != cfg.MailFrom {
		t.Fatalf("sink %+v", s)
	}
	out := logs.String()
	if strings.Contains(out, "s3cret-pass") || !strings.Contains(out, "smtp") || !strings.Contains(out, "smtp.mailgun.org") ||
		!strings.Contains(out, "allowlist=true") {
		t.Fatalf("boot log %q", out)
	}
}

func TestMailSinkIsTheFileAdapterWithoutSMTPHost(t *testing.T) {
	var logs bytes.Buffer
	s, ok := mailSink(config.Config{MailDir: "tmp/mail", SMTPPort: 587}, slog.New(slog.NewTextHandler(&logs, nil))).(mail.FileSender)
	if !ok || s.Dir != "tmp/mail" {
		t.Fatalf("sink %+v", s)
	}
	if out := logs.String(); !strings.Contains(out, "file") || !strings.Contains(out, "allowlist=false") {
		t.Fatalf("boot log %q", out)
	}
}
