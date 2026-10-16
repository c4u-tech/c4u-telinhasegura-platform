package mail_test

import (
	"bufio"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"errors"
	"io"
	"math/big"
	"mime"
	"mime/quotedprintable"
	"net"
	netmail "net/mail"
	"net/textproto"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

// selfSigned is a certificate for 127.0.0.1 and the pool that trusts it.
func selfSigned(t *testing.T) (tls.Certificate, *x509.CertPool) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "fake smtp"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, IsCA: true, BasicConstraintsValid: true,
		KeyUsage:    x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	leaf, _ := x509.ParseCertificate(der)
	pool := x509.NewCertPool()
	pool.AddCert(leaf)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key, Leaf: leaf}, pool
}

// fakeSMTP is a one-connection-at-a-time SMTP server for the sender's tests.
type fakeSMTP struct {
	cert      tls.Certificate
	implicit  bool   // TLS from the first byte (port 465 behavior)
	starttls  bool   // offers STARTTLS on a plain connection
	rcptReply string // the reply to RCPT TO; default "250 2.1.5 OK"
	silent    bool   // never greets (timeout test)
	hangUp    bool   // closes right after the greeting

	mu                         sync.Mutex
	authTLS                    bool
	user, pass, from, to, data string
}

func (f *fakeSMTP) start(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go f.serve(c)
		}
	}()
	return ln.Addr().(*net.TCPAddr).Port
}

func (f *fakeSMTP) serve(c net.Conn) {
	defer c.Close()
	cfg := &tls.Config{Certificates: []tls.Certificate{f.cert}}
	onTLS := f.implicit
	if f.implicit {
		c = tls.Server(c, cfg)
	}
	if f.silent {
		_, _ = io.Copy(io.Discard, c)
		return
	}
	tp := textproto.NewConn(c)
	_ = tp.PrintfLine("220 fake ESMTP")
	if f.hangUp {
		return
	}
	for {
		line, err := tp.ReadLine()
		if err != nil {
			return
		}
		verb, arg, _ := strings.Cut(line, " ")
		switch strings.ToUpper(verb) {
		case "EHLO", "HELO":
			_ = tp.PrintfLine("250-fake")
			if f.starttls && !onTLS {
				_ = tp.PrintfLine("250-STARTTLS")
			}
			_ = tp.PrintfLine("250 AUTH PLAIN")
		case "STARTTLS":
			_ = tp.PrintfLine("220 2.0.0 go ahead")
			tc := tls.Server(c, cfg)
			if tc.Handshake() != nil {
				return
			}
			c, onTLS = tc, true
			tp = textproto.NewConn(c)
		case "AUTH":
			_, b64, _ := strings.Cut(arg, " ")
			raw, _ := base64.StdEncoding.DecodeString(b64)
			parts := strings.Split(string(raw), "\x00")
			f.mu.Lock()
			f.authTLS = onTLS
			if len(parts) == 3 {
				f.user, f.pass = parts[1], parts[2]
			}
			f.mu.Unlock()
			_ = tp.PrintfLine("235 2.7.0 ok")
		case "MAIL":
			f.mu.Lock()
			f.from = arg
			f.mu.Unlock()
			_ = tp.PrintfLine("250 2.1.0 ok")
		case "RCPT":
			f.mu.Lock()
			f.to = arg
			f.mu.Unlock()
			reply := f.rcptReply
			if reply == "" {
				reply = "250 2.1.5 ok"
			}
			_ = tp.PrintfLine("%s", reply)
		case "DATA":
			_ = tp.PrintfLine("354 go ahead")
			d, _ := tp.ReadDotBytes()
			f.mu.Lock()
			f.data = string(d)
			f.mu.Unlock()
			_ = tp.PrintfLine("250 2.0.0 queued")
		case "QUIT":
			_ = tp.PrintfLine("221 bye")
			return
		default:
			_ = tp.PrintfLine("502 5.5.1 no")
		}
	}
}

func newSender(port int, roots *x509.CertPool) mail.SMTPSender {
	return mail.SMTPSender{Host: "127.0.0.1", Port: port, Username: "postmaster@mail.example.com", Password: "s3cret",
		From: "Telinha Segura <nao-responda@mail.example.com>", RootCAs: roots,
		Now: func() time.Time { return base }}
}

var accented = mail.Message{
	To:      "ana@example.com",
	Subject: "Confirme seu e-mail — ação necessária",
	Body:    "Olá!\n\nAbra o link: https://app.test/verificar-email?token=" + strings.Repeat("x", 200) + "\n\nObrigado.",
}

func TestSMTPSenderDeliversOverSTARTTLS(t *testing.T) {
	cert, roots := selfSigned(t)
	srv := &fakeSMTP{cert: cert, starttls: true}
	if err := newSender(srv.start(t), roots).Send(context.Background(), accented); err != nil {
		t.Fatal(err)
	}
	srv.mu.Lock()
	defer srv.mu.Unlock()
	if !srv.authTLS || srv.user != "postmaster@mail.example.com" || srv.pass != "s3cret" {
		t.Fatalf("auth: tls %v user %q", srv.authTLS, srv.user)
	}
	if srv.from != "FROM:<nao-responda@mail.example.com>" || srv.to != "TO:<ana@example.com>" {
		t.Fatalf("envelope %q %q", srv.from, srv.to)
	}
	checkMessage(t, srv.data)
}

func checkMessage(t *testing.T, data string) {
	t.Helper()
	m, err := netmail.ReadMessage(bufio.NewReader(strings.NewReader(data)))
	if err != nil {
		t.Fatal(err)
	}
	h := m.Header
	subject, err := new(mime.WordDecoder).DecodeHeader(h.Get("Subject"))
	if err != nil || subject != accented.Subject {
		t.Errorf("subject %q (%v)", subject, err)
	}
	from, err := netmail.ParseAddress(h.Get("From"))
	if err != nil || from.Address != "nao-responda@mail.example.com" || from.Name != "Telinha Segura" {
		t.Errorf("from %q", h.Get("From"))
	}
	if date, err := h.Date(); err != nil || !date.Equal(base) {
		t.Errorf("date %q", h.Get("Date"))
	}
	if id := h.Get("Message-ID"); !strings.HasPrefix(id, "<") || !strings.HasSuffix(id, "@mail.example.com>") {
		t.Errorf("message-id %q", id)
	}
	if h.Get("To") != "ana@example.com" || h.Get("MIME-Version") != "1.0" ||
		h.Get("Content-Type") != "text/plain; charset=utf-8" || h.Get("Content-Transfer-Encoding") != "quoted-printable" {
		t.Errorf("headers %v", h)
	}
	// Links carry one-time tokens: a provider's click or open tracking
	// must never rewrite them, whatever the sending domain's settings.
	for _, k := range []string{"X-Mailgun-Track", "X-Mailgun-Track-Clicks", "X-Mailgun-Track-Opens"} {
		if h.Get(k) != "no" {
			t.Errorf("%s %q", k, h.Get(k))
		}
	}
	body, err := io.ReadAll(quotedprintable.NewReader(m.Body))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimRight(strings.ReplaceAll(string(body), "\r\n", "\n"), "\n"); got != accented.Body {
		t.Errorf("body %q", got)
	}
}

func TestSMTPSenderDeliversOverImplicitTLS(t *testing.T) {
	cert, roots := selfSigned(t)
	srv := &fakeSMTP{cert: cert, implicit: true}
	s := newSender(srv.start(t), roots)
	s.ImplicitTLS = true
	if err := s.Send(context.Background(), accented); err != nil {
		t.Fatal(err)
	}
	srv.mu.Lock()
	defer srv.mu.Unlock()
	if !srv.authTLS || srv.pass != "s3cret" {
		t.Fatal("not authenticated over TLS")
	}
	checkMessage(t, srv.data)
}

func TestSMTPSenderRefusesAServerWithoutSTARTTLS(t *testing.T) {
	cert, roots := selfSigned(t)
	srv := &fakeSMTP{cert: cert}
	err := newSender(srv.start(t), roots).Send(context.Background(), accented)
	if !mail.IsPermanent(err) || !errors.Is(err, mail.ErrNoSTARTTLS) {
		t.Fatalf("err %v, want permanent ErrNoSTARTTLS", err)
	}
	srv.mu.Lock()
	defer srv.mu.Unlock()
	if srv.pass != "" {
		t.Fatal("the credential went out in clear")
	}
}

func TestSMTPSenderRefusesAnUnverifiedCertificate(t *testing.T) {
	cert, _ := selfSigned(t)
	srv := &fakeSMTP{cert: cert, starttls: true}
	err := newSender(srv.start(t), x509.NewCertPool()).Send(context.Background(), accented)
	if !mail.IsPermanent(err) || mail.Class(err) != "tls" {
		t.Fatalf("err %v (class %q), want a permanent tls error", err, mail.Class(err))
	}
	srv.mu.Lock()
	defer srv.mu.Unlock()
	if srv.pass != "" {
		t.Fatal("the credential reached an unverified server")
	}
}

func TestSMTPSenderClassifiesReplies(t *testing.T) {
	cert, roots := selfSigned(t)
	for name, tc := range map[string]struct {
		srv       *fakeSMTP
		permanent bool
		class     string
	}{
		"5xx":    {&fakeSMTP{cert: cert, starttls: true, rcptReply: "550 5.1.1 <ana@example.com>: user unknown"}, true, "smtp 550"},
		"4xx":    {&fakeSMTP{cert: cert, starttls: true, rcptReply: "451 4.7.1 try later"}, false, "smtp 451"},
		"hangup": {&fakeSMTP{cert: cert, starttls: true, hangUp: true}, false, ""},
		"silent": {&fakeSMTP{cert: cert, starttls: true, silent: true}, false, "timeout"},
	} {
		t.Run(name, func(t *testing.T) {
			sendCtx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
			defer cancel()
			err := newSender(tc.srv.start(t), roots).Send(sendCtx, accented)
			if err == nil || mail.IsPermanent(err) != tc.permanent {
				t.Fatalf("err %v, permanent %v", err, mail.IsPermanent(err))
			}
			if tc.class != "" && mail.Class(err) != tc.class {
				t.Fatalf("class %q, want %q", mail.Class(err), tc.class)
			}
		})
	}
}

func TestSMTPSenderRefusesHeaderBreaks(t *testing.T) {
	err := mail.SMTPSender{Host: "127.0.0.1", Port: 1}.Send(context.Background(), mail.Message{To: "a@b.c\r\nBcc: x@y.z", Subject: "s"})
	if !errors.Is(err, mail.ErrHeaderBreak) || !mail.IsPermanent(err) {
		t.Fatalf("err %v", err)
	}
}
