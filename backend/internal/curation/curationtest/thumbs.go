package curationtest

import (
	"context"
	"fmt"
	"slices"
	"sync"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

// Thumbs answers the images added to it; an unknown ID fails as a 404
// from the image host would.
type Thumbs struct {
	Err    error  // when set, every call fails with it
	OnCall func() // runs inside each call, before it answers

	mu     sync.Mutex
	images map[string][]byte
	calls  []string
}

func (t *Thumbs) Add(youtubeID string, b []byte) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.images == nil {
		t.images = map[string][]byte{}
	}
	t.images[youtubeID] = b
}

func (t *Thumbs) Thumbnail(_ context.Context, youtubeID string) ([]byte, error) {
	t.mu.Lock()
	t.calls = append(t.calls, youtubeID)
	b, ok := t.images[youtubeID]
	t.mu.Unlock()
	if t.OnCall != nil {
		t.OnCall()
	}
	if t.Err != nil {
		return nil, t.Err
	}
	if !ok {
		return nil, fmt.Errorf("%w: status 404", curation.ErrThumbnailUnavailable)
	}
	return slices.Clone(b), nil
}

// Calls lists the IDs asked for, in order.
func (t *Thumbs) Calls() []string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return slices.Clone(t.calls)
}
