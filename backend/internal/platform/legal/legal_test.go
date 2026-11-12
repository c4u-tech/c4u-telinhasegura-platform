package legal_test

import (
	"slices"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/legal"
)

var graceEnd = time.Date(2026, 11, 26, 3, 0, 0, 0, time.UTC)

func TestCurrentAlwaysCounts(t *testing.T) {
	v := legal.Version{Current: "new", Previous: "old", GraceUntil: graceEnd}
	for _, at := range []time.Time{graceEnd.Add(-time.Hour), graceEnd, graceEnd.Add(time.Hour)} {
		if !v.Accepts("new", at) {
			t.Fatalf("current refused at %s", at)
		}
	}
}

func TestPreviousCountsOnlyBeforeTheGraceEnds(t *testing.T) {
	v := legal.Version{Current: "new", Previous: "old", GraceUntil: graceEnd}
	if !v.Accepts("old", graceEnd.Add(-time.Nanosecond)) {
		t.Fatal("previous refused before the grace ends")
	}
	if v.Accepts("old", graceEnd) {
		t.Fatal("previous accepted when the grace ends")
	}
	if v.Accepts("other", graceEnd.Add(-time.Hour)) || v.Accepts("", graceEnd.Add(-time.Hour)) {
		t.Fatal("an unknown version accepted")
	}
}

func TestNoGraceAcceptsOnlyTheCurrent(t *testing.T) {
	v := legal.Version{Current: "new", Previous: "old"}
	if v.Accepts("old", time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)) {
		t.Fatal("previous accepted without a grace")
	}
	if got := v.Accepted(time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)); !slices.Equal(got, []string{"new"}) {
		t.Fatalf("accepted %v", got)
	}
}

func TestAcceptedListsTheVersionsInForce(t *testing.T) {
	v := legal.Version{Current: "new", Previous: "old", GraceUntil: graceEnd}
	if got := v.Accepted(graceEnd.Add(-time.Hour)); !slices.Equal(got, []string{"new", "old"}) {
		t.Fatalf("before: %v", got)
	}
	if got := v.Accepted(graceEnd); !slices.Equal(got, []string{"new"}) {
		t.Fatalf("after: %v", got)
	}
}
