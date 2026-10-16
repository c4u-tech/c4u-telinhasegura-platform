package mail

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"mime"
	"mime/quotedprintable"
	"net"
	netmail "net/mail"
	"net/smtp"
	"net/textproto"
	"strconv"
	"strings"
	"time"
)

// SMTPSender delivers through any SMTP provider (Mailgun in production), so
// the provider is a setting. TLS is mandatory and verified:
// implicit on port 465, STARTTLS otherwise; a server that offers neither
// never sees the credential.
type SMTPSender struct {
	Host        string
	Port        int
	ImplicitTLS bool // port 465
	Username    string
	Password    string
	From        string           // MAIL_FROM, a mailbox: "Telinha Segura <nao-responda@mail.example>"
	RootCAs     *x509.CertPool   // nil: the system roots; set only by tests
	Now         func() time.Time // nil: time.Now
}

func (s SMTPSender) Send(ctx context.Context, m Message) error {
	if strings.ContainsAny(m.To, "\r\n") || strings.ContainsAny(m.Subject, "\r\n") {
		return Permanent(ErrHeaderBreak)
	}
	from, err := netmail.ParseAddress(s.From)
	if err != nil {
		return Permanent(fmt.Errorf("mail: MAIL_FROM: %w", err))
	}
	domain := from.Address[strings.LastIndex(from.Address, "@")+1:]
	tlsCfg := &tls.Config{ServerName: s.Host, RootCAs: s.RootCAs, MinVersion: tls.VersionTLS12}
	addr := net.JoinHostPort(s.Host, strconv.Itoa(s.Port))

	var conn net.Conn
	if s.ImplicitTLS {
		conn, err = (&tls.Dialer{Config: tlsCfg}).DialContext(ctx, "tcp", addr)
	} else {
		conn, err = (&net.Dialer{}).DialContext(ctx, "tcp", addr)
	}
	if err != nil {
		return classify(err)
	}
	defer conn.Close()
	// The context bounds the whole conversation, not only the dial.
	if dl, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(dl)
	}
	stop := context.AfterFunc(ctx, func() { _ = conn.SetDeadline(time.Now()) })
	defer stop()

	c, err := smtp.NewClient(conn, s.Host)
	if err != nil {
		return classify(err)
	}
	defer c.Close()
	if err := c.Hello(domain); err != nil {
		return classify(err)
	}
	if !s.ImplicitTLS {
		if ok, _ := c.Extension("STARTTLS"); !ok {
			return Permanent(ErrNoSTARTTLS)
		}
		if err := c.StartTLS(tlsCfg); err != nil {
			return classify(err)
		}
	}
	if err := c.Auth(smtp.PlainAuth("", s.Username, s.Password, s.Host)); err != nil {
		return classify(err)
	}
	if err := c.Mail(from.Address); err != nil {
		return classify(err)
	}
	if err := c.Rcpt(m.To); err != nil {
		return classify(err)
	}
	w, err := c.Data()
	if err != nil {
		return classify(err)
	}
	if _, err := w.Write(s.compose(from, domain, m)); err != nil {
		return classify(err)
	}
	if err := w.Close(); err != nil {
		return classify(err)
	}
	_ = c.Quit() // the message is accepted; a failed goodbye must not resend it
	return nil
}

// compose builds the RFC 5322 message: Q-encoded subject, quoted-printable
// UTF-8 body, CRLF line endings.
func (s SMTPSender) compose(from *netmail.Address, domain string, m Message) []byte {
	now := time.Now
	if s.Now != nil {
		now = s.Now
	}
	var b bytes.Buffer
	fmt.Fprintf(&b, "From: %s\r\n", from.String())
	fmt.Fprintf(&b, "To: %s\r\n", m.To)
	fmt.Fprintf(&b, "Subject: %s\r\n", mime.QEncoding.Encode("utf-8", m.Subject))
	fmt.Fprintf(&b, "Date: %s\r\n", now().Format(time.RFC1123Z))
	fmt.Fprintf(&b, "Message-ID: <%s@%s>\r\n", strings.ToLower(rand.Text()), domain)
	// Links carry one-time tokens: Mailgun must not rewrite them for click
	// or open tracking, whatever the sending domain's settings. Other
	// providers ignore these headers.
	b.WriteString("X-Mailgun-Track: no\r\nX-Mailgun-Track-Clicks: no\r\nX-Mailgun-Track-Opens: no\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	b.WriteString("Content-Transfer-Encoding: quoted-printable\r\n\r\n")
	qp := quotedprintable.NewWriter(&b) // writes every line break as CRLF
	_, _ = qp.Write([]byte(m.Body))
	_ = qp.Close()
	b.WriteString("\r\n")
	return b.Bytes()
}

// classify marks the errors a retry cannot fix as permanent: a 5xx
// reply and a certificate that does not verify. Everything
// else (4xx, timeouts, network) stays transient.
func classify(err error) error {
	var reply *textproto.Error
	var cert *tls.CertificateVerificationError
	switch {
	case errors.As(err, &reply) && reply.Code >= 500:
		return Permanent(err)
	case errors.As(err, &cert):
		return Permanent(err)
	}
	return err
}
