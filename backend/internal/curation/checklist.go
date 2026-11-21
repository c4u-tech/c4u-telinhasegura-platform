package curation

import (
	"slices"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// ChecklistVersion names the list of questions curators answer. A review
// sent against another version is refused, so every stored answer reads
// against the exact questions that were asked.
const ChecklistVersion = "2026-11-20"

// Answer is a curator's answer to one question. Every question asks
// whether something is in the video, so "ok" (no) is always the answer
// that keeps it, "appears" is yes and "doubt" is "I don't know". Answers
// stored under a former list keep their meaning: there, "appears" on the
// pace and on the story meant a fast pace and a missing story, and on a sad
// character it was a doubt, not a refusal.
type Answer string

const (
	AnswerOK      Answer = "ok"
	AnswerAppears Answer = "appears"
	AnswerDoubt   Answer = "doubt"
)

// Rule is what a yes ("appears") does to a review.
type Rule string

const (
	RuleRefuses  Rule = "refuses"  // the video cannot be approved
	RuleDoubt    Rule = "doubt"    // the video goes to a moderator
	RuleBand     Rule = "band"     // only the question's MinBand and older are allowed
	RuleConflict Rule = "conflict" // the curator may not review this video
	RuleNotes    Rule = "notes"    // recorded for the team, never changes the outcome
)

// ChecklistItem is one question. A LongOnly question is asked of a long
// video only: a long video's review must answer it, a short one's must not.
// MinBand is the youngest band a yes still allows; only a RuleBand question
// sets it.
type ChecklistItem struct {
	ID       string
	Text     string
	Rule     Rule
	LongOnly bool
	MinBand  family.AgeBand
}

type ChecklistGroup struct {
	ID    string
	Title string
	Items []ChecklistItem
}

var checklist = []ChecklistGroup{
	{ID: "antes", Title: "Antes de começar", Items: []ChecklistItem{
		{ID: "c25", Text: "Você tem vínculo com este canal ou com quem o publica?", Rule: RuleConflict},
		{ID: "c03", Text: "Aparece 'Inclui promoção paga' ou fala em publi, parceria, patrocínio ou recebido?", Rule: RuleRefuses},
	}},
	{ID: "violencia", Title: "Violência e medo", Items: []ChecklistItem{
		{ID: "c04", Text: "Alguém bate, chuta, atira ou ataca de propósito, mesmo de brincadeira?", Rule: RuleRefuses},
		{ID: "c05", Text: "Aparece arma em destaque, sangue, ferimento, morte, doença grave ou luto?", Rule: RuleRefuses},
		{ID: "c06", Text: "Tem clima de medo ou suspense, susto, monstro ameaçador ou grito de pavor?", Rule: RuleRefuses},
		{ID: "c07", Text: "A história trata da tristeza de algum personagem (uma despedida, uma perda, saudade)?", Rule: RuleRefuses},
		{ID: "c29", Text: "Alguém furta, picha, invade ou faz outra coisa contra a lei, mesmo sem violência?", Rule: RuleRefuses},
		{ID: "c30", Text: "Mostra vômito, fezes ou secreções para causar nojo, briga feia de palavras, acidente ou destruição com peso emocional, cirurgia ou ossada?", Rule: RuleRefuses},
		{ID: "c32", Text: "Aparece personagem de aparência estranha ou assustadora, ou que se transforma na tela, mesmo sendo bonzinho?", Rule: RuleBand, MinBand: family.Age5To8},
		{ID: "c33", Text: "Alguém leva tombo, trombada ou torta na cara para fazer rir, sem se machucar?", Rule: RuleBand, MinBand: family.Age5To8},
	}},
	{ID: "linguagem", Title: "Linguagem e respeito", Items: []ChecklistItem{
		{ID: "c08", Text: "Alguém xinga ou diminui outro (bobo, chato, feio, burro, medroso, mimado), na frente ou pelas costas, ou faz gesto feio?", Rule: RuleRefuses},
		{ID: "c09", Text: "Alguém é zoado, humilhado, enganado ou tratado como inferior por quem é?", Rule: RuleRefuses},
	}},
	{ID: "consumo", Title: "Consumo e publicidade", Items: []ChecklistItem{
		{ID: "c14", Text: "O vídeo existe para mostrar produtos (abrir, testar, colecionar)?", Rule: RuleRefuses},
		{ID: "c15", Text: "Pede para comprar, pedir aos pais, comentar para ganhar, ou diz preço e loja?", Rule: RuleRefuses},
		{ID: "c16", Text: "Mostra ostentação, caixa surpresa paga, aposta ou roleta?", Rule: RuleRefuses},
		{ID: "c17", Text: "Pede para se inscrever, ativar o sininho, ver o próximo ou não sair?", Rule: RuleRefuses},
	}},
	{ID: "saude", Title: "Saúde e segurança", Items: []ChecklistItem{
		{ID: "c10", Text: "Aparece ou se fala de bebida alcoólica, cigarro, vape ou outra droga, ou remédio usado como brincadeira?", Rule: RuleRefuses},
		{ID: "c11", Text: "Tem beijo romântico, namoro, roupa ou dança sensual, ou nudez?", Rule: RuleRefuses},
		{ID: "c12", Text: "Alguém faz algo perigoso que uma criança poderia imitar, sem adulto e sem aviso?", Rule: RuleRefuses},
		{ID: "c13", Text: "É um desafio de aguentar, ficar sem ar, comer algo estranho ou se arriscar?", Rule: RuleRefuses},
		{ID: "c18", Text: "Mostra criança real chorando, castigada, envergonhada, adultizada, ou a rotina dela como show?", Rule: RuleRefuses},
		{ID: "c19", Text: "Ensina remédio, dieta ou 'cura', ou diz algo de saúde ou segurança de que você não tem certeza?", Rule: RuleRefuses},
		{ID: "c20", Text: "Pisca muito rápido ou tem luz estroboscópica?", Rule: RuleRefuses},
		{ID: "c31", Text: "Explica partes íntimas, diferenças entre os corpos, de onde vêm os bebês ou como se proteger de abuso?", Rule: RuleRefuses},
	}},
	{ID: "ritmo", Title: "Ritmo e canal", Items: []ChecklistItem{
		{ID: "c22", Text: "Tem ritmo agitado, gritaria ou cortes rápidos?", Rule: RuleBand, MinBand: family.Age5To8},
		{ID: "c34", Text: "Para acompanhar o vídeo é preciso ler o que está escrito na tela?", Rule: RuleBand, MinBand: family.Age5To8},
		{ID: "c35", Text: "A história volta no tempo, troca de narrador ou depende de ironia para ser entendida?", Rule: RuleBand, MinBand: family.Age9To12},
		{ID: "c36", Text: "Algum personagem se comporta mal durante boa parte do vídeo e só no fim aprende?", Rule: RuleBand, MinBand: family.Age9To12},
		{ID: "c23", Text: "Falta começo, meio ou fim na história?", Rule: RuleRefuses},
		{ID: "c02", Text: "É uma compilação longa ('1 hora de…') ou uma estreia?", Rule: RuleRefuses},
		{ID: "c24", Text: "O canal tem outros vídeos que você recusaria?", Rule: RuleDoubt},
	}},
	{ID: "longo", Title: "Vídeo longo", Items: []ChecklistItem{
		{ID: "c26", Text: "É filme, episódio ou história publicada por um canal que não é o oficial da obra nem licenciado por quem tem os direitos?", Rule: RuleRefuses, LongOnly: true},
		{ID: "c27", Text: "A obra tem classificação indicativa oficial acima de Livre?", Rule: RuleRefuses, LongOnly: true},
		{ID: "c28", Text: "Aparecem anúncios no meio do vídeo?", Rule: RuleNotes, LongOnly: true},
	}},
}

// checklistItem finds a question by its ID; checklistOrder is the IDs in
// the order the list asks them.
var checklistItem, checklistOrder = func() (map[string]ChecklistItem, []string) {
	byID := map[string]ChecklistItem{}
	var order []string
	for _, g := range checklist {
		for _, it := range g.Items {
			byID[it.ID] = it
			order = append(order, it.ID)
		}
	}
	return byID, order
}()

// Checklist is the current list, groups and questions in the order they
// are asked. The caller gets its own copy.
func Checklist() []ChecklistGroup {
	out := make([]ChecklistGroup, len(checklist))
	for i, g := range checklist {
		out[i] = ChecklistGroup{ID: g.ID, Title: g.Title, Items: slices.Clone(g.Items)}
	}
	return out
}

// bandQuestion is one band question of a former list: its ID, its words
// as that list asked it, and the youngest band a yes still allowed.
type bandQuestion struct {
	ID      string
	Text    string
	MinBand family.AgeBand
}

// formerBandQuestions are the band questions of every former list, in the
// order it asked them, so a review keeps the meaning it was stored with,
// and a question the current list no longer asks can still be worded. A
// review written before any list bars no band; one stored under a list
// missing here stops a moderator's decision, so when the current list
// changes its band questions must be added here first, with their words.
var formerBandQuestions = map[string][]bandQuestion{
	"2026-10-20": {{ID: "c22", Text: "Tem ritmo agitado, gritaria ou cortes rápidos?", MinBand: family.Age5To8}},
	"2026-10-21": {{ID: "c22", Text: "Tem ritmo agitado, gritaria ou cortes rápidos?", MinBand: family.Age5To8}},
	"2026-11-11": {{ID: "c22", Text: "Tem ritmo agitado, gritaria ou cortes rápidos?", MinBand: family.Age5To8}},
}

// currentBandRules are the current list's band questions and their bands.
var currentBandRules = func() map[string]family.AgeBand {
	out := map[string]family.AgeBand{}
	for _, it := range checklistItem {
		if it.Rule == RuleBand {
			out[it.ID] = it.MinBand
		}
	}
	return out
}()

// bandRules are the band questions of the list version names, each with
// the youngest band a yes allows.
func bandRules(version string) map[string]family.AgeBand {
	if version == ChecklistVersion {
		return currentBandRules
	}
	qs, ok := formerBandQuestions[version]
	if !ok {
		return nil
	}
	out := make(map[string]family.AgeBand, len(qs))
	for _, q := range qs {
		out[q.ID] = q.MinBand
	}
	return out
}

// knownList reports whether a review stored under version can be read for
// its band: the current list, a former one, or none at all.
func knownList(version string) bool {
	_, former := formerBandQuestions[version]
	return version == "" || version == ChecklistVersion || former
}

// bandFrom is the youngest band a review's answers allow, read under the
// list the review was stored with: the oldest band among the band
// questions answered yes or "I don't know", and at least the band above
// the youngest for a video too long for it. A band is not released over a
// fact the reviewer could not affirm. Curators and moderators are held to
// this one rule.
func bandFrom(version string, answers map[string]Answer, overYoungest bool) family.AgeBand {
	band := family.AgeUpTo4
	if overYoungest {
		band = family.Age5To8
	}
	for id, min := range bandRules(version) {
		if a := answers[id]; (a == AnswerAppears || a == AnswerDoubt) && bandRank(min) > bandRank(band) {
			band = min
		}
	}
	return band
}

// judge reads a complete answer set against the current list. A missing,
// unknown or malformed answer is ErrValidation, and so is "I don't know"
// on the tie to the channel: the curator knows whether they have one. A
// tie comes first, since such a curator must not judge the video at all;
// then an answer that refuses the video; then a stated band younger than
// computed, the band the answers and the length allow (a band question's
// yes or "I don't know" allows from its own band up). A doubt that states no band is not
// judged on it. It reports whether the review is a doubt: an explicit
// "doubt", or a yes on a question that asks for a moderator. The questions
// asked of a long video only are checked when present; whether they must be
// is the video's length, which the caller knows.
func judge(answers map[string]Answer, stated, computed family.AgeBand) (bool, error) {
	for _, id := range checklistOrder {
		if _, ok := answers[id]; !ok && !checklistItem[id].LongOnly {
			return false, ErrValidation
		}
	}
	var conflict, refuses, doubt bool
	for id, a := range answers {
		item, ok := checklistItem[id]
		if !ok || a != AnswerOK && a != AnswerAppears && a != AnswerDoubt {
			return false, ErrValidation
		}
		if item.Rule == RuleNotes {
			continue
		}
		if a == AnswerDoubt {
			if item.Rule == RuleConflict {
				return false, ErrValidation
			}
			doubt = true
		}
		if a != AnswerAppears {
			continue
		}
		switch item.Rule {
		case RuleConflict:
			conflict = true
		case RuleRefuses:
			refuses = true
		case RuleDoubt:
			doubt = true
		}
	}
	switch {
	case conflict:
		return false, ErrConflictOfInterest
	case refuses:
		return false, ErrChecklistRefuses
	case stated != "" && bandRank(stated) < bandRank(computed):
		return false, ErrChecklistBand
	}
	return doubt, nil
}

// failedItems checks a rejection's questions: one or more, each one whose
// "appears" refuses, none twice. It returns them in the list's order.
func failedItems(ids []string) ([]ChecklistItem, error) {
	if len(ids) == 0 {
		return nil, ErrValidation
	}
	seen := map[string]bool{}
	for _, id := range ids {
		item, ok := checklistItem[id]
		if !ok || item.Rule != RuleRefuses || seen[id] {
			return nil, ErrValidation
		}
		seen[id] = true
	}
	var out []ChecklistItem
	for _, id := range checklistOrder {
		if seen[id] {
			out = append(out, checklistItem[id])
		}
	}
	return out, nil
}

// composeReason is a rejection's reason as the held screens and the
// history show it: each failed question on its own line, then the
// curator's note.
func composeReason(items []ChecklistItem, note string) string {
	lines := make([]string, 0, len(items)+1)
	for _, it := range items {
		lines = append(lines, it.Text)
	}
	if note != "" {
		lines = append(lines, note)
	}
	return strings.Join(lines, "\n")
}
