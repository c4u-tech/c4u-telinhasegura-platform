// Package curationtest fakes the YouTube video source for tests.
package curationtest

import (
	"context"
	"slices"
	"sync"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// Fake answers from the videos added to it; an unknown ID is
// ErrVideoNotFound.
type Fake struct {
	Err    error  // when set, every call fails with it
	OnCall func() // runs inside each call, before it answers
	// Unreadable IDs are left out of answers, which then carry a BatchItemsError.
	Unreadable map[string]bool

	mu      sync.Mutex
	videos  map[string]curation.Metadata
	calls   []string
	batches [][]string
}

func (f *Fake) Add(m curation.Metadata) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.videos == nil {
		f.videos = map[string]curation.Metadata{}
	}
	f.videos[m.ID] = m
}

func (f *Fake) Video(_ context.Context, id string) (curation.Metadata, error) {
	f.mu.Lock()
	f.calls = append(f.calls, id)
	m, ok := f.videos[id]
	unreadable := f.Unreadable[id]
	f.mu.Unlock()
	if f.OnCall != nil {
		f.OnCall()
	}
	if f.Err != nil {
		return curation.Metadata{}, f.Err
	}
	if unreadable {
		return curation.Metadata{}, &curation.BatchItemsError{IDs: []string{id}}
	}
	if !ok {
		return curation.Metadata{}, curation.ErrVideoNotFound
	}
	return m, nil
}

// Videos answers the known IDs of a batch; each ID also counts in Calls.
func (f *Fake) Videos(_ context.Context, ids []string) (map[string]curation.Metadata, error) {
	f.mu.Lock()
	f.batches = append(f.batches, slices.Clone(ids))
	f.calls = append(f.calls, ids...)
	out := map[string]curation.Metadata{}
	var bad []string
	for _, id := range ids {
		if f.Unreadable[id] {
			bad = append(bad, id)
			continue
		}
		if m, ok := f.videos[id]; ok {
			out[id] = m
		}
	}
	f.mu.Unlock()
	if f.OnCall != nil {
		f.OnCall()
	}
	if f.Err != nil {
		return nil, f.Err
	}
	if len(bad) > 0 {
		return out, &curation.BatchItemsError{IDs: bad}
	}
	return out, nil
}

// Batches lists each Videos call's IDs, in order.
func (f *Fake) Batches() [][]string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.batches)
}

// Calls lists the IDs asked for, in order.
func (f *Fake) Calls() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.calls)
}

// Kids is a video every refusal rule passes: made for kids, embeddable,
// not live, five minutes long.
func Kids(id, title string) curation.Metadata {
	return curation.Metadata{ID: id, Title: title, ChannelID: "UC" + id, ChannelTitle: "Canal " + title,
		Duration: 5 * time.Minute, MadeForKids: true, Embeddable: true, Live: "none"}
}
