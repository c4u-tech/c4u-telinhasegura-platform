package curation_test

import (
	"fmt"
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
)

func TestChecklistIsTheCurrentList(t *testing.T) {
	if curation.ChecklistVersion != "2026-10-20" {
		t.Fatalf("version %q", curation.ChecklistVersion)
	}
	groups := curation.Checklist()
	var titles, ids, order []string
	items := map[string]curation.ChecklistItem{}
	for _, g := range groups {
		titles, ids = append(titles, g.Title), append(ids, g.ID)
		for _, it := range g.Items {
			if _, dup := items[it.ID]; dup {
				t.Errorf("%s twice", it.ID)
			}
			items[it.ID] = it
			order = append(order, it.ID)
		}
	}
	if want := []string{"Antes de assistir", "Violência e medo", "Linguagem e respeito", "Consumo e publicidade",
		"Crianças, saúde e segurança", "Faixa"}; !slices.Equal(titles, want) {
		t.Fatalf("groups %v", titles)
	}
	if want := []string{"antes", "violencia", "linguagem", "consumo", "saude", "faixa"}; !slices.Equal(ids, want) {
		t.Fatalf("group ids %v", ids)
	}
	if want := []string{"c01", "c02", "c03", "c25", "c04", "c05", "c06", "c07", "c08", "c09", "c21", "c14", "c15", "c16",
		"c17", "c10", "c11", "c12", "c13", "c18", "c19", "c20", "c22", "c23", "c24"}; !slices.Equal(order, want) {
		t.Fatalf("order %v", order)
	}
	special := map[string]curation.Rule{"c07": curation.RuleDoubt, "c24": curation.RuleDoubt,
		"c21": curation.RuleInvalidReason, "c22": curation.RuleBand, "c25": curation.RuleConflict}
	for i := 1; i <= 25; i++ {
		id := fmt.Sprintf("c%02d", i)
		it, ok := items[id]
		if !ok || it.Text == "" {
			t.Errorf("%s missing", id)
			continue
		}
		want, ok := special[id]
		if !ok {
			want = curation.RuleRefuses
		}
		if it.Rule != want {
			t.Errorf("%s rule %q, want %q", id, it.Rule, want)
		}
		if positive := id == "c01" || id == "c22" || id == "c23"; it.Positive != positive {
			t.Errorf("%s positive %v", id, it.Positive)
		}
	}
	for id, text := range map[string]string{
		"c01": "Está marcado como 'feito para crianças' no YouTube e pode ser incorporado?",
		"c18": "Mostra criança real chorando, castigada, envergonhada, adultizada, ou a rotina dela como show?",
		"c25": "Você tem vínculo com este canal ou com quem o publica (é seu, de parente, de empresa ou marca com que você tem relação)?",
	} {
		if items[id].Text != text {
			t.Errorf("%s text %q", id, items[id].Text)
		}
	}
	groups[0].Items[0].Text = "mudou"
	if curation.Checklist()[0].Items[0].Text == "mudou" {
		t.Fatal("Checklist hands out the list itself")
	}
}
