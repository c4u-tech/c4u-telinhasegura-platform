package curation

import (
	"container/list"
	"slices"
	"sync"
	"time"
)

// searchCache keeps the YouTube part of recent searches in memory, keyed by
// the normalized query. The keys are what people typed, so they live only
// here: never written to a log or a store. Entries expire after ttl and the
// oldest is dropped once max are held.
type searchCache struct {
	ttl time.Duration
	max int
	now func() time.Time

	mu      sync.Mutex
	entries map[string]*list.Element // value: *searchEntry
	order   *list.List               // front is the oldest
}

type searchEntry struct {
	key     string
	hits    []Metadata
	expires time.Time
}

func newSearchCache(ttl time.Duration, max int, now func() time.Time) *searchCache {
	return &searchCache{
		ttl:     ttl,
		max:     max,
		now:     now,
		entries: map[string]*list.Element{},
		order:   list.New(),
	}
}

// get returns a copy of the hits stored under key, in the order they were
// put, unless the entry is missing or expired.
func (c *searchCache) get(key string) ([]Metadata, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	el, ok := c.entries[key]
	if !ok {
		return nil, false
	}
	e := el.Value.(*searchEntry)
	if !c.now().Before(e.expires) {
		c.remove(el)
		return nil, false
	}
	return slices.Clone(e.hits), true
}

// put stores hits under key as the newest entry, replacing any previous
// one, and drops the oldest entries beyond the limit.
func (c *searchCache) put(key string, hits []Metadata) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.entries[key]; ok {
		c.remove(el)
	}
	e := &searchEntry{key: key, hits: slices.Clone(hits), expires: c.now().Add(c.ttl)}
	c.entries[key] = c.order.PushBack(e)
	for c.order.Len() > c.max {
		c.remove(c.order.Front())
	}
}

// has reports whether a live entry holds the video.
func (c *searchCache) has(youtubeID string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now()
	for el := c.order.Front(); el != nil; {
		next := el.Next()
		e := el.Value.(*searchEntry)
		if !now.Before(e.expires) {
			c.remove(el)
		} else if slices.ContainsFunc(e.hits, func(m Metadata) bool { return m.ID == youtubeID }) {
			return true
		}
		el = next
	}
	return false
}

func (c *searchCache) remove(el *list.Element) {
	delete(c.entries, el.Value.(*searchEntry).key)
	c.order.Remove(el)
}
