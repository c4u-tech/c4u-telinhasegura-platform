package curation_test

import (
	"slices"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// questions is the current list's wording, question by question.
var questions = map[string]string{
	"c25": "Você tem vínculo com este canal ou com quem o publica?",
	"c03": "Aparece 'Inclui promoção paga' ou fala em publi, parceria, patrocínio ou recebido?",
	"c04": "Alguém bate, chuta, atira ou ataca de propósito, mesmo de brincadeira?",
	"c05": "Aparece arma em destaque, sangue, ferimento, morte, doença grave ou luto?",
	"c06": "Tem clima de medo ou suspense, susto, monstro ameaçador ou grito de pavor?",
	"c07": "Algum personagem fica triste de um jeito que a história para para mostrar?",
	"c29": "Alguém furta, picha, invade ou faz outra coisa contra a lei, mesmo sem violência?",
	"c30": "Mostra vômito, fezes ou secreções para causar nojo, briga feia de palavras, acidente ou destruição com peso emocional, cirurgia ou ossada?",
	"c32": "Aparece personagem de aparência estranha ou assustadora, ou que se transforma na tela, mesmo sendo bonzinho?",
	"c33": "Alguém leva tombo, trombada ou torta na cara para fazer rir, sem se machucar?",
	"c08": "Alguém xinga ou diminui outro (bobo, chato, feio, burro, medroso, mimado), na frente ou pelas costas, ou faz gesto feio?",
	"c09": "Alguém é zoado, humilhado, enganado ou tratado como inferior por quem é?",
	"c14": "O vídeo existe para mostrar produtos (abrir, testar, colecionar)?",
	"c15": "Pede para comprar, pedir aos pais, comentar para ganhar, ou diz preço e loja?",
	"c16": "Mostra ostentação, caixa surpresa paga, aposta ou roleta?",
	"c17": "Pede para se inscrever, ativar o sininho, ver o próximo ou não sair?",
	"c10": "Aparece ou se fala de bebida alcoólica, cigarro, vape ou outra droga, ou remédio usado como brincadeira?",
	"c11": "Tem beijo romântico, namoro, roupa ou dança sensual, ou nudez?",
	"c12": "Alguém faz algo perigoso que uma criança poderia imitar, sem adulto e sem aviso?",
	"c13": "É um desafio de aguentar, ficar sem ar, comer algo estranho ou se arriscar?",
	"c18": "Mostra criança real chorando, castigada, envergonhada, adultizada, ou a rotina dela como show?",
	"c19": "Ensina remédio, dieta ou 'cura', ou diz algo de saúde ou segurança de que você não tem certeza?",
	"c20": "Pisca muito rápido ou tem luz estroboscópica?",
	"c31": "Explica partes íntimas, diferenças entre os corpos, de onde vêm os bebês ou como se proteger de abuso?",
	"c22": "Tem ritmo agitado, gritaria ou cortes rápidos?",
	"c34": "Para acompanhar o vídeo é preciso ler o que está escrito na tela?",
	"c35": "A história volta no tempo, troca de narrador ou depende de ironia para ser entendida?",
	"c36": "Algum personagem se comporta mal durante boa parte do vídeo e só no fim aprende?",
	"c23": "Falta começo, meio ou fim na história?",
	"c02": "É uma compilação longa ('1 hora de…') ou uma estreia?",
	"c24": "O canal tem outros vídeos que você recusaria?",
	"c26": "É filme, episódio ou história publicada por um canal que não é o oficial da obra nem licenciado por quem tem os direitos?",
	"c27": "A obra tem classificação indicativa oficial acima de Livre?",
	"c28": "Aparecem anúncios no meio do vídeo?",
}

func TestChecklistIsTheCurrentList(t *testing.T) {
	if curation.ChecklistVersion != "2026-11-20" {
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
	if want := []string{"Antes de começar", "Violência e medo", "Linguagem e respeito", "Consumo e publicidade",
		"Saúde e segurança", "Ritmo e canal", "Vídeo longo"}; !slices.Equal(titles, want) {
		t.Fatalf("groups %v", titles)
	}
	if want := []string{"antes", "violencia", "linguagem", "consumo", "saude", "ritmo", "longo"}; !slices.Equal(ids, want) {
		t.Fatalf("group ids %v", ids)
	}
	if want := []string{"c25", "c03", "c04", "c05", "c06", "c07", "c29", "c30", "c32", "c33", "c08", "c09",
		"c14", "c15", "c16", "c17", "c10", "c11", "c12", "c13", "c18", "c19", "c20", "c31",
		"c22", "c34", "c35", "c36", "c23", "c02", "c24", "c26", "c27", "c28"}; !slices.Equal(order, want) {
		t.Fatalf("order %v", order)
	}
	if len(items) != len(questions) {
		t.Fatalf("%d questions, want %d", len(items), len(questions))
	}
	special := map[string]curation.Rule{"c24": curation.RuleDoubt, "c25": curation.RuleConflict, "c28": curation.RuleNotes,
		"c22": curation.RuleBand, "c32": curation.RuleBand, "c33": curation.RuleBand, "c34": curation.RuleBand,
		"c35": curation.RuleBand, "c36": curation.RuleBand}
	// The youngest band a yes still allows, set on the band questions only.
	minBand := map[string]family.AgeBand{"c22": family.Age5To8, "c32": family.Age5To8, "c33": family.Age5To8,
		"c34": family.Age5To8, "c35": family.Age9To12, "c36": family.Age9To12}
	for id, text := range questions {
		it, ok := items[id]
		if !ok {
			t.Errorf("%s missing", id)
			continue
		}
		if it.Text != text {
			t.Errorf("%s text %q", id, it.Text)
		}
		want, ok := special[id]
		if !ok {
			want = curation.RuleRefuses
		}
		if it.Rule != want {
			t.Errorf("%s rule %q, want %q", id, it.Rule, want)
		}
		if it.MinBand != minBand[id] {
			t.Errorf("%s min band %q, want %q", id, it.MinBand, minBand[id])
		}
		// Only a long video is asked about its rights, its rating and its ads.
		if long := id == "c26" || id == "c27" || id == "c28"; it.LongOnly != long {
			t.Errorf("%s long only %v", id, it.LongOnly)
		}
	}
	for _, gone := range []string{"c01", "c21"} {
		if _, ok := items[gone]; ok {
			t.Errorf("%s is still asked", gone)
		}
	}
	groups[0].Items[0].Text = "mudou"
	if curation.Checklist()[0].Items[0].Text == "mudou" {
		t.Fatal("Checklist hands out the list itself")
	}
}
