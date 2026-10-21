package curation

import (
	"slices"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

// ChecklistVersion names the list of questions curators answer. A review
// sent against another version is refused, so every stored answer reads
// against the exact questions that were asked.
const ChecklistVersion = "2026-10-21"

// Answer is a curator's answer to one question. Every question asks
// whether something is in the video, so "ok" (no) is always the answer
// that keeps it, "appears" is yes and "doubt" is "I don't know". Answers
// stored under the former list keep their meaning: there, too, "appears"
// on the pace and on the story meant a fast pace and a missing story.
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
	RuleBand     Rule = "band"     // the youngest band is not allowed
	RuleConflict Rule = "conflict" // the curator may not review this video
)

type ChecklistItem struct {
	ID   string
	Text string
	Rule Rule
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
		{ID: "c07", Text: "Algum personagem fica triste como tema da história?", Rule: RuleDoubt},
	}},
	{ID: "linguagem", Title: "Linguagem e respeito", Items: []ChecklistItem{
		{ID: "c08", Text: "Alguém xinga, chama outro de bobo, feio ou burro, ou faz gesto feio?", Rule: RuleRefuses},
		{ID: "c09", Text: "Alguém é zoado, humilhado, enganado ou tratado como inferior por quem é?", Rule: RuleRefuses},
	}},
	{ID: "consumo", Title: "Consumo e publicidade", Items: []ChecklistItem{
		{ID: "c14", Text: "O vídeo existe para mostrar produtos (abrir, testar, colecionar)?", Rule: RuleRefuses},
		{ID: "c15", Text: "Pede para comprar, pedir aos pais, comentar para ganhar, ou diz preço e loja?", Rule: RuleRefuses},
		{ID: "c16", Text: "Mostra ostentação, caixa surpresa paga, aposta ou roleta?", Rule: RuleRefuses},
		{ID: "c17", Text: "Pede para se inscrever, ativar o sininho, ver o próximo ou não sair?", Rule: RuleRefuses},
	}},
	{ID: "saude", Title: "Saúde e segurança", Items: []ChecklistItem{
		{ID: "c10", Text: "Aparece bebida alcoólica, cigarro, vape, ou remédio usado como brincadeira?", Rule: RuleRefuses},
		{ID: "c11", Text: "Tem beijo romântico, namoro, roupa ou dança sensual, ou nudez?", Rule: RuleRefuses},
		{ID: "c12", Text: "Alguém faz algo perigoso que uma criança poderia imitar, sem adulto e sem aviso?", Rule: RuleRefuses},
		{ID: "c13", Text: "É um desafio de aguentar, ficar sem ar, comer algo estranho ou se arriscar?", Rule: RuleRefuses},
		{ID: "c18", Text: "Mostra criança real chorando, castigada, envergonhada, adultizada, ou a rotina dela como show?", Rule: RuleRefuses},
		{ID: "c19", Text: "Ensina remédio, dieta ou 'cura', ou diz algo de saúde ou segurança de que você não tem certeza?", Rule: RuleRefuses},
		{ID: "c20", Text: "Pisca muito rápido ou tem luz estroboscópica?", Rule: RuleRefuses},
	}},
	{ID: "ritmo", Title: "Ritmo e canal", Items: []ChecklistItem{
		{ID: "c22", Text: "Tem ritmo agitado, gritaria ou cortes rápidos?", Rule: RuleBand},
		{ID: "c23", Text: "Falta começo, meio ou fim na história?", Rule: RuleRefuses},
		{ID: "c02", Text: "É uma compilação longa ('1 hora de…') ou uma estreia?", Rule: RuleRefuses},
		{ID: "c24", Text: "O canal tem outros vídeos que você recusaria?", Rule: RuleDoubt},
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

// judge reads a complete answer set against the current list. A missing,
// unknown or malformed answer is ErrValidation, and so is "I don't know"
// on the tie to the channel: the curator knows whether they have one. A
// tie comes first, since such a curator must not judge the video at all;
// then an answer that refuses the video; then the pace that rules out the
// youngest band. It reports whether the review is a doubt: an explicit
// "doubt", or a yes on a question that asks for a moderator.
func judge(answers map[string]Answer, band family.AgeBand) (bool, error) {
	if len(answers) != len(checklistOrder) {
		return false, ErrValidation
	}
	var conflict, refuses, fast, doubt bool
	for id, a := range answers {
		item, ok := checklistItem[id]
		if !ok || a != AnswerOK && a != AnswerAppears && a != AnswerDoubt {
			return false, ErrValidation
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
		case RuleBand:
			fast = true
		case RuleDoubt:
			doubt = true
		}
	}
	switch {
	case conflict:
		return false, ErrConflictOfInterest
	case refuses:
		return false, ErrChecklistRefuses
	case fast && band == family.AgeUpTo4:
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
