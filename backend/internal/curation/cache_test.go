package curation_test

import (
	"errors"
	"sync"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

func TestChildThumbnailIsCachedAfterOneSuccess(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	f.thumbs.Add(nthID(1), []byte("jpeg-1"))

	for range 2 {
		b, err := f.svc.ChildThumbnail(ctx, lia, v)
		if err != nil || string(b) != "jpeg-1" {
			t.Fatalf("%q %v", b, err)
		}
	}
	if calls := f.thumbs.Calls(); len(calls) != 1 {
		t.Fatalf("image host called %d times", len(calls))
	}
}

func TestAFailedThumbnailIsTriedAgain(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)

	if _, err := f.svc.ChildThumbnail(ctx, lia, v); !errors.Is(err, curation.ErrThumbnailUnavailable) {
		t.Fatalf("first: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM video_thumbnails`); n != 0 {
		t.Fatalf("a failure was stored: %d rows", n)
	}
	f.thumbs.Add(nthID(1), []byte("jpeg-1"))
	if b, err := f.svc.ChildThumbnail(ctx, lia, v); err != nil || string(b) != "jpeg-1" {
		t.Fatalf("second: %q %v", b, err)
	}
	if calls := f.thumbs.Calls(); len(calls) != 2 {
		t.Fatalf("image host called %d times", len(calls))
	}
}

func TestChildThumbnailNeedsAnEligibleVideo(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	strict := f.published(nthID(1), "bichos", family.Age9To12)
	f.thumbs.Add(nthID(1), []byte("jpeg-1"))

	for name, id := range map[string]string{"stricter band": strict, "malformed": "abc"} {
		if _, err := f.svc.ChildThumbnail(ctx, lia, id); !errors.Is(err, curation.ErrVideoNotAllowed) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if calls := f.thumbs.Calls(); len(calls) != 0 {
		t.Fatalf("image host called for a refused video: %v", calls)
	}
}

func TestFamilyThumbnailServesApprovedAndHeldOnly(t *testing.T) {
	f := newFixture(t)
	approved := f.published(nthID(1), "bichos", family.Age9To12)
	held := f.published(nthID(2), "bichos", family.AgeUpTo4)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'reports' WHERE id = $1::uuid`, held)
	pending := f.video(nthID(3))
	for i := 1; i <= 3; i++ {
		f.thumbs.Add(nthID(i), []byte("jpeg"))
	}

	for name, id := range map[string]string{"approved": approved, "held": held} {
		if b, err := f.svc.FamilyThumbnail(ctx, id); err != nil || string(b) != "jpeg" {
			t.Errorf("%s: %q %v", name, b, err)
		}
	}
	for name, id := range map[string]string{"pending": pending, "malformed": "abc",
		"unknown": "00000000-0000-0000-0000-000000000000"} {
		if _, err := f.svc.FamilyThumbnail(ctx, id); !errors.Is(err, curation.ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestConcurrentFirstThumbnailRequestsStoreOnce(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	f.thumbs.Add(nthID(1), []byte("jpeg-1"))
	var arrived sync.WaitGroup
	arrived.Add(2)
	f.thumbs.OnCall = func() { arrived.Done(); arrived.Wait() } // both requests miss the cache before either stores

	errs := make(chan error, 2)
	for range 2 {
		go func() {
			_, err := f.svc.ChildThumbnail(ctx, lia, v)
			errs <- err
		}()
	}
	for range 2 {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
	}
	if n := f.count(`SELECT count(*) FROM video_thumbnails`); n != 1 {
		t.Fatalf("%d rows", n)
	}
}
