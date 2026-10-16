// Package mail is the port through which the API sends email.
package mail

import (
	"context"
	"fmt"
	"os"
	"time"
)

// DefaultTTL is how long a message without a TTL of its own is worth
// sending.
const DefaultTTL = 72 * time.Hour

type Message struct {
	To      string
	Subject string
	Body    string
	TTL     time.Duration // how long the message is worth sending; zero means DefaultTTL
}

type Sender interface {
	Send(ctx context.Context, m Message) error
}

// FileSender writes each message as an .eml file under Dir. It is for
// local development only; a real provider is deferred.
type FileSender struct{ Dir string }

func (f FileSender) Send(_ context.Context, m Message) error {
	if err := os.MkdirAll(f.Dir, 0o700); err != nil {
		return err
	}
	file, err := os.CreateTemp(f.Dir, "*.eml")
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = fmt.Fprintf(file, "To: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n%s\r\n", m.To, m.Subject, m.Body)
	return err
}
