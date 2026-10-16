package main

import (
	"log/slog"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/config"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

// mailSink is where the outbox worker delivers: SMTP when SMTP_HOST is
// set, .eml files under MAIL_DIR otherwise.
// The boot log names it, never the credential.
func mailSink(cfg config.Config, log *slog.Logger) mail.Sender {
	allowlist := !cfg.MailAllowed.Empty()
	if cfg.SMTPHost == "" {
		log.Info("mail: delivering to files", "sink", "file", "dir", cfg.MailDir, "allowlist", allowlist)
		return mail.FileSender{Dir: cfg.MailDir}
	}
	log.Info("mail: delivering through smtp", "sink", "smtp", "host", cfg.SMTPHost, "port", cfg.SMTPPort, "allowlist", allowlist)
	return mail.SMTPSender{
		Host:        cfg.SMTPHost,
		Port:        cfg.SMTPPort,
		ImplicitTLS: cfg.SMTPPort == 465,
		Username:    cfg.SMTPUsername,
		Password:    cfg.SMTPPassword,
		From:        cfg.MailFrom,
	}
}
