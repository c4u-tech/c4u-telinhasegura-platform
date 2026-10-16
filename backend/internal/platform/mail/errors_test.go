package mail_test

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/textproto"
	"os"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

func TestPermanentWrapsAndIsDetectedThroughWrapping(t *testing.T) {
	base := &textproto.Error{Code: 550, Msg: "5.1.1 <ana@example.com>: user unknown"}
	if !mail.IsPermanent(fmt.Errorf("send: %w", mail.Permanent(base))) {
		t.Fatal("a wrapped permanent error was not detected")
	}
	if mail.IsPermanent(base) || mail.IsPermanent(nil) || mail.Permanent(nil) != nil {
		t.Fatal("only Permanent marks an error permanent")
	}
	if !errors.Is(mail.Permanent(base), base) {
		t.Fatal("Permanent hides the cause")
	}
}

func TestClassNeverCarriesTheErrorText(t *testing.T) {
	for err, want := range map[error]string{
		nil: "",
		mail.Permanent(&textproto.Error{Code: 550, Msg: "<ana@example.com> unknown"}): "smtp 550",
		&textproto.Error{Code: 451, Msg: "try later"}:                                 "smtp 451",
		context.DeadlineExceeded:                                                      "timeout",
		os.ErrDeadlineExceeded:                                                        "timeout",
		mail.Permanent(mail.ErrNoSTARTTLS):                                            "tls",
		&tls.CertificateVerificationError{Err: errors.New("x509: unknown authority")}: "tls",
		&net.OpError{Op: "dial", Err: errors.New("connection refused")}:               "network",
		errors.New("ana@example.com broke"):                                           "other",
	} {
		got := mail.Class(err)
		if got != want || strings.Contains(got, "@") {
			t.Errorf("Class(%v) = %q, want %q", err, got, want)
		}
	}
}
