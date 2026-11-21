package curation

import (
	"reflect"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// A band question a former list asked and the current one no longer does
// still raises the band, so the moderator still sees it, worded as that
// list worded it; one still asked is worded as the current list words it.
func TestABandAnswerToAQuestionNoLongerAskedIsStillListed(t *testing.T) {
	former := formerBandQuestions
	t.Cleanup(func() { formerBandQuestions = former })
	formerBandQuestions = map[string][]bandQuestion{
		"2026-01-01": {
			{ID: "c22", Text: "Ritmo como era perguntado?", MinBand: family.Age5To8},
			{ID: "c90", Text: "Uma pergunta que saiu da lista?", MinBand: family.Age9To12},
		},
	}
	reviews := []storedAnswers{
		{role: MaePai, version: "2026-01-01", answers: map[string]Answer{"c22": AnswerAppears, "c90": AnswerDoubt}},
		{role: Pedagogo, version: ChecklistVersion, answers: map[string]Answer{"c34": AnswerAppears}},
	}
	want := []BandAnswer{
		{Text: checklistItem["c22"].Text, Answer: AnswerAppears, DisplayRole: MaePai},
		{Text: checklistItem["c34"].Text, Answer: AnswerAppears, DisplayRole: Pedagogo},
		{Text: "Uma pergunta que saiu da lista?", Answer: AnswerDoubt, DisplayRole: MaePai},
	}
	if got := bandAnswers(reviews); !reflect.DeepEqual(got, want) {
		t.Fatalf("band answers %+v, want %+v", got, want)
	}
}
