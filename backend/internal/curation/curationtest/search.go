package curationtest

import (
	"context"
	"slices"
	"sync"
)

// Search answers from the queries added to it; a query never added gets no
// results and no error.
type Search struct {
	Err error // when set, every call fails with it

	mu    sync.Mutex
	byQ   map[string][]string
	calls []string
}

// Add sets the IDs answered for exactly q.
func (s *Search) Add(q string, ids ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.byQ == nil {
		s.byQ = map[string][]string{}
	}
	s.byQ[q] = slices.Clone(ids)
}

func (s *Search) Search(_ context.Context, q string) ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls = append(s.calls, q)
	if s.Err != nil {
		return nil, s.Err
	}
	return slices.Clone(s.byQ[q]), nil
}

// Calls lists the queries received, in order.
func (s *Search) Calls() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.calls)
}
