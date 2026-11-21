package curation

import (
	"maps"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// Reviews stored under a list keep its band questions after a new list
// replaces it, and a moderator's decision on an unknown list is refused.
// So when the current list changes, the band questions it had must be
// copied into formerBandQuestions first. This test pins them, so it starts
// failing on the day the list changes without that copy.
func TestTheBandQuestionsOfAStoredListOutliveIt(t *testing.T) {
	want := map[string]family.AgeBand{
		"c22": family.Age5To8, "c32": family.Age5To8, "c33": family.Age5To8, "c34": family.Age5To8,
		"c35": family.Age9To12, "c36": family.Age9To12,
	}
	if got := bandRules("2026-11-20"); !maps.Equal(got, want) {
		t.Fatalf("band questions of 2026-11-20: %v, want %v", got, want)
	}
}
