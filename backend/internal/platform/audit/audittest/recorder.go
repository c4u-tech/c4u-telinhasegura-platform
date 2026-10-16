// Package audittest records audit events for assertions.
package audittest

import (
	"context"
	"sync"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

type Entry struct {
	AccountID string
	Event     audit.Event
}

type Recorder struct {
	mu      sync.Mutex
	Entries []Entry
	Actions []audit.Action
}

func (r *Recorder) Record(_ context.Context, accountID string, e audit.Event) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.Entries = append(r.Entries, Entry{accountID, e})
}

// RecordAction keeps the action, and its actor and event as an Entry, so
// Has and the event counts see it too.
func (r *Recorder) RecordAction(_ context.Context, a audit.Action) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.Entries = append(r.Entries, Entry{a.Actor, a.Event})
	r.Actions = append(r.Actions, a)
}

func (r *Recorder) Has(accountID string, e audit.Event) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, x := range r.Entries {
		if x.AccountID == accountID && x.Event == e {
			return true
		}
	}
	return false
}

// LastAction is the latest action of event e.
func (r *Recorder) LastAction(e audit.Event) (audit.Action, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := len(r.Actions) - 1; i >= 0; i-- {
		if r.Actions[i].Event == e {
			return r.Actions[i], true
		}
	}
	return audit.Action{}, false
}
