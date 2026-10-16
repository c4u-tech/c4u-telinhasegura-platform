package mail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/textproto"
)

// ErrNoSTARTTLS is a server that would take the credential in clear: the
// sender refuses it, permanently.
var ErrNoSTARTTLS = errors.New("mail: the SMTP server does not offer STARTTLS")

type permanentError struct{ err error }

func (p permanentError) Error() string { return p.err.Error() }
func (p permanentError) Unwrap() error { return p.err }

// Permanent marks err as one a retry cannot fix: an SMTP 5xx reply, a
// server without STARTTLS, a certificate that does not verify. The
// Worker then stops trying.
func Permanent(err error) error {
	if err == nil {
		return nil
	}
	return permanentError{err}
}

func IsPermanent(err error) bool {
	var p permanentError
	return errors.As(err, &p)
}

// Class names err for a log line without its text: an SMTP reply often
// echoes the recipient. The text goes only to last_error.
func Class(err error) string {
	var reply *textproto.Error
	var cert *tls.CertificateVerificationError
	var netErr net.Error
	switch {
	case err == nil:
		return ""
	case errors.As(err, &reply):
		return fmt.Sprintf("smtp %d", reply.Code)
	case errors.Is(err, ErrNoSTARTTLS), errors.As(err, &cert):
		return "tls"
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr) && netErr.Timeout():
		return "timeout"
	case errors.As(err, &netErr):
		return "network"
	default:
		return "other"
	}
}
