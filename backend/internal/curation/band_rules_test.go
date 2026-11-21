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

// Each former list keeps the words it asked its band questions with, as
// a moderator would read an answer to one the current list no longer
// asks.
func TestEachFormerListKeepsItsOwnWording(t *testing.T) {
	want := map[string]string{
		"2026-10-20": "Ritmo calmo, uma coisa por vez, frases curtas, sem gritaria ou cortes rápidos?",
		"2026-10-21": "Tem ritmo agitado, gritaria ou cortes rápidos?",
		"2026-11-11": "Tem ritmo agitado, gritaria ou cortes rápidos?",
	}
	for version, text := range want {
		qs := formerBandQuestions[version]
		if len(qs) != 1 || qs[0].ID != "c22" || qs[0].Text != text || qs[0].MinBand != family.Age5To8 {
			t.Errorf("%s: %+v, want c22 %q from 5 to 8", version, qs, text)
		}
	}
}
