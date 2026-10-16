package curation_test

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation/curationtest"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

func TestUnavailableHoldsWhatYouTubeNoLongerPasses(t *testing.T) {
	kids := curationtest.Kids(nthID(1), "Baby Shark")
	notForKids, notEmbeddable, live, tooLong := kids, kids, kids, kids
	notForKids.MadeForKids = false
	notEmbeddable.Embeddable = false
	live.Live = "live"
	tooLong.Duration = 21 * time.Minute
	for name, m := range map[string]*curation.Metadata{
		"gone": nil, "not for kids": &notForKids, "not embeddable": &notEmbeddable, "live": &live, "too long": &tooLong,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFixture(t)
			fam, _ := f.family("ana@example.com")
			lia := f.minor(fam, family.Age5To8)
			v := f.published(nthID(1), "bichos", family.AgeUpTo4)
			if m != nil {
				f.source.Add(*m)
			}
			if err := f.svc.ReportUnavailable(ctx, lia, v); err != nil {
				t.Fatal(err)
			}
			if state, reason := f.state(v); state != "held" || reason != curation.HeldByUnavailable {
				t.Fatalf("%s %s", state, reason)
			}
			if !f.audit.Has("", audit.VideoHeld) {
				t.Fatal("video_held not recorded without an actor")
			}
		})
	}
}

func TestUnavailableKeepsAVideoThatStillPasses(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	f.source.Add(curationtest.Kids(nthID(1), "Baby Shark"))

	if err := f.svc.ReportUnavailable(ctx, lia, v); err != nil {
		t.Fatal(err)
	}
	if state, _ := f.state(v); state != "approved" {
		t.Fatalf("state %s", state)
	}
	if calls := f.source.Calls(); len(calls) != 1 || calls[0] != nthID(1) {
		t.Fatalf("calls %v", calls)
	}
}

func TestUnavailableCallsYouTubeOncePerVideoPerHour(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia, teo := f.minor(fam, family.Age5To8), f.minor(fam, family.Age5To8)
	v := f.published(nthID(1), "bichos", family.AgeUpTo4)
	f.source.Add(curationtest.Kids(nthID(1), "Baby Shark"))

	for _, c := range []curation.Child{lia, teo} {
		if err := f.svc.ReportUnavailable(ctx, c, v); err != nil {
			t.Fatal(err)
		}
	}
	if n := len(f.source.Calls()); n != 1 {
		t.Fatalf("%d calls within the hour", n)
	}
	f.now = f.now.Add(time.Hour)
	if err := f.svc.ReportUnavailable(ctx, lia, v); err != nil {
		t.Fatal(err)
	}
	if n := len(f.source.Calls()); n != 2 {
		t.Fatalf("%d calls after the hour", n)
	}
}

func TestUnavailableAcceptsTenChecksPerChildPerHour(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	for i := range 11 {
		v := f.published(nthID(i), "bichos", family.AgeUpTo4)
		f.source.Add(curationtest.Kids(nthID(i), fmt.Sprint("Vídeo ", i)))
		if err := f.svc.ReportUnavailable(ctx, lia, v); err != nil {
			t.Fatal(err)
		}
	}
	if n := len(f.source.Calls()); n != 10 {
		t.Fatalf("%d calls, want 10", n)
	}
}

func TestUnavailableWithoutAKeyOrWithYouTubeDown(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	v1 := f.published(nthID(1), "bichos", family.AgeUpTo4)
	v2 := f.published(nthID(2), "bichos", family.AgeUpTo4)

	f.source.Err = fmt.Errorf("%w: status 403", curation.ErrSourceUnavailable)
	if err := f.svc.ReportUnavailable(ctx, lia, v1); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(f.logs.String(), "video source failed") {
		t.Fatalf("the failure was not logged: %s", f.logs)
	}
	f.rebuild(func(d *curation.Deps) { d.Source = nil })
	if err := f.svc.ReportUnavailable(ctx, lia, v2); err != nil {
		t.Fatal(err)
	}
	for _, v := range []string{v1, v2} {
		if state, _ := f.state(v); state != "approved" {
			t.Fatalf("held without a verdict: %s", state)
		}
	}
}

func TestUnavailableNeedsAnEligibleVideo(t *testing.T) {
	f := newFixture(t)
	fam, _ := f.family("ana@example.com")
	lia := f.minor(fam, family.Age5To8)
	strict := f.published(nthID(1), "bichos", family.Age9To12)
	for name, id := range map[string]string{"stricter band": strict, "malformed": "abc"} {
		if err := f.svc.ReportUnavailable(ctx, lia, id); !errors.Is(err, curation.ErrVideoNotAllowed) {
			t.Errorf("%s: %v", name, err)
		}
	}
	if calls := f.source.Calls(); len(calls) != 0 {
		t.Fatalf("YouTube called for a refused video: %v", calls)
	}
}
