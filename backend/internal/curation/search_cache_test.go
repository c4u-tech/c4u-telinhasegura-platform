package curation

import (
	"reflect"
	"sync"
	"testing"
	"time"
)

func TestSearchCacheExpiresAfterTTL(t *testing.T) {
	t0 := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	now := t0
	c := newSearchCache(24*time.Hour, 10, func() time.Time { return now })
	c.put("q", []Metadata{{ID: "v1"}})

	now = t0.Add(24*time.Hour - time.Minute)
	if _, ok := c.get("q"); !ok {
		t.Fatal("entry should be live just before the TTL")
	}
	if !c.has("v1") {
		t.Fatal("has should be true just before the TTL")
	}

	now = t0.Add(24 * time.Hour)
	if _, ok := c.get("q"); ok {
		t.Fatal("entry should be gone at the TTL")
	}
	if c.has("v1") {
		t.Fatal("has should be false at the TTL")
	}
}

func TestSearchCacheEvictsTheOldest(t *testing.T) {
	now := time.Now()
	c := newSearchCache(time.Hour, 2, func() time.Time { return now })
	c.put("a", []Metadata{{ID: "only-a"}})
	c.put("b", []Metadata{{ID: "vb"}})
	c.put("c", []Metadata{{ID: "vc"}})

	if _, ok := c.get("a"); ok {
		t.Fatal("a should have been evicted")
	}
	if _, ok := c.get("b"); !ok {
		t.Fatal("b should be present")
	}
	if _, ok := c.get("c"); !ok {
		t.Fatal("c should be present")
	}
	if c.has("only-a") {
		t.Fatal("an ID only in an evicted entry must not be found")
	}
}

func TestSearchCacheReputMovesToNewest(t *testing.T) {
	now := time.Now()
	c := newSearchCache(time.Hour, 2, func() time.Time { return now })
	c.put("a", []Metadata{{ID: "va"}})
	c.put("b", []Metadata{{ID: "vb"}})
	c.put("a", []Metadata{{ID: "va2"}})
	c.put("c", []Metadata{{ID: "vc"}})

	if _, ok := c.get("b"); ok {
		t.Fatal("b is the oldest and should be evicted")
	}
	if got, ok := c.get("a"); !ok || got[0].ID != "va2" {
		t.Fatalf("a should hold the replacement, got %v %v", got, ok)
	}
	if c.has("va") {
		t.Fatal("the replaced hits must not be found")
	}
}

func TestSearchCacheKeepsOrder(t *testing.T) {
	now := time.Now()
	c := newSearchCache(time.Hour, 2, func() time.Time { return now })
	want := []Metadata{{ID: "3"}, {ID: "1"}, {ID: "2"}}
	c.put("q", want)
	got, ok := c.get("q")
	if !ok || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v %v, want %v", got, ok, want)
	}
}

func TestSearchCacheConcurrentUse(t *testing.T) {
	c := newSearchCache(time.Hour, 5, time.Now)
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			k := string(rune('a' + i%8))
			c.put(k, []Metadata{{ID: k}})
			c.get(k)
			c.has(k)
		}(i)
	}
	wg.Wait()
}
