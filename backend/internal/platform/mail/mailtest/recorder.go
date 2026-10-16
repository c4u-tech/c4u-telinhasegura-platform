// Package mailtest records sent messages for assertions.
package mailtest

import (
	"context"
	"sync"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

type Recorder struct {
	mu   sync.Mutex
	Sent []mail.Message
}

func (r *Recorder) Send(_ context.Context, m mail.Message) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.Sent = append(r.Sent, m)
	return nil
}

// To returns the messages sent to addr, oldest first.
func (r *Recorder) To(addr string) []mail.Message {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []mail.Message
	for _, m := range r.Sent {
		if m.To == addr {
			out = append(out, m)
		}
	}
	return out
}
