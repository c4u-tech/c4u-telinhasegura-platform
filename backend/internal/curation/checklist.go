package curation

import "slices"

// ChecklistVersion names the list of questions curators answer. A review
// sent against another version is refused, so every stored answer reads
// against the exact questions that were asked.
const ChecklistVersion = "2026-10-20"

// Answer is a curator's answer to one question. For the questions asked
// in the positive (Positive) "ok" means yes and "appears" means no; for
// the others "ok" means the thing does not appear.
type Answer string

const (
	AnswerOK      Answer = "ok"
	AnswerAppears Answer = "appears"
	AnswerDoubt   Answer = "doubt"
)

// Rule is what an "appears" answer does to a review.
type Rule string

const (
	RuleRefuses       Rule = "refuses"        // the video cannot be approved
	RuleDoubt         Rule = "doubt"          // the video goes to a moderator
	RuleBand          Rule = "band"           // the youngest band is not allowed
	RuleInvalidReason Rule = "invalid_reason" // a reason the criteria never accept
	RuleConflict      Rule = "conflict"       // the curator may not review this video
)

type ChecklistItem struct {
	ID       string
	Text     string
	Rule     Rule
	Positive bool // asked in the positive: "ok" is yes, "appears" is no
}

type ChecklistGroup struct {
	ID    string
	Title string
	Items []ChecklistItem
}

var checklist = []ChecklistGroup{
	{ID: "antes", Title: "Antes de assistir", Items: []ChecklistItem{
		{ID: "c01", Text: "Está marcado como 'feito para crianças' no YouTube e pode ser incorporado?", Rule: RuleRefuses, Positive: true},
		{ID: "c02", Text: "É ao vivo, estreia ou '1 hora de…', ou passa do tempo máximo?", Rule: RuleRefuses},
		{ID: "c03", Text: "Tem o aviso 'Inclui promoção paga' ou fala em publi, parceria, patrocínio ou recebido?", Rule: RuleRefuses},
		{ID: "c25", Text: "Você tem vínculo com este canal ou com quem o publica (é seu, de parente, de empresa ou marca com que você tem relação)?", Rule: RuleConflict},
	}},
	{ID: "violencia", Title: "Violência e medo", Items: []ChecklistItem{
		{ID: "c04", Text: "Alguém bate, chuta, atira ou ataca de propósito, mesmo de mentirinha?", Rule: RuleRefuses},
		{ID: "c05", Text: "Aparece arma em destaque, sangue, ferimento, morte, doença grave ou luto?", Rule: RuleRefuses},
		{ID: "c06", Text: "Tem clima de medo ou suspense, susto, monstro ameaçador, grito de pavor?", Rule: RuleRefuses},
		{ID: "c07", Text: "Algum personagem fica triste como tema da história?", Rule: RuleDoubt},
	}},
	{ID: "linguagem", Title: "Linguagem e respeito", Items: []ChecklistItem{
		{ID: "c08", Text: "Alguém chama outro de bobo, feio, burro…, xinga ou faz gesto feio?", Rule: RuleRefuses},
		{ID: "c09", Text: "Alguém é zoado, humilhado, enganado ou tratado como inferior por quem é?", Rule: RuleRefuses},
		{ID: "c21", Text: "Você recusaria só porque mostra família, religião, cor ou deficiência diferente da sua?", Rule: RuleInvalidReason},
	}},
	{ID: "consumo", Title: "Consumo e publicidade", Items: []ChecklistItem{
		{ID: "c14", Text: "O vídeo existe para mostrar produtos (abrir, testar, colecionar)?", Rule: RuleRefuses},
		{ID: "c15", Text: "Pede para comprar, pedir aos pais, comentar para ganhar ou diz preço e loja?", Rule: RuleRefuses},
		{ID: "c16", Text: "Mostra ostentação, caixa surpresa paga, aposta ou roleta?", Rule: RuleRefuses},
		{ID: "c17", Text: "Pede para se inscrever, ativar o sininho, ver o próximo ou não sair?", Rule: RuleRefuses},
	}},
	{ID: "saude", Title: "Crianças, saúde e segurança", Items: []ChecklistItem{
		{ID: "c10", Text: "Aparece bebida alcoólica, cigarro, vape ou remédio usado como brincadeira?", Rule: RuleRefuses},
		{ID: "c11", Text: "Tem beijo romântico, namoro, roupa ou dança sensual, ou nudez?", Rule: RuleRefuses},
		{ID: "c12", Text: "Alguém faz algo perigoso que uma criança poderia imitar, sem adulto e sem aviso?", Rule: RuleRefuses},
		{ID: "c13", Text: "É um 'desafio' de aguentar, ficar sem ar, comer algo estranho ou se arriscar?", Rule: RuleRefuses},
		{ID: "c18", Text: "Mostra criança real chorando, castigada, envergonhada, adultizada, ou a rotina dela como show?", Rule: RuleRefuses},
		{ID: "c19", Text: "Ensina remédio, dieta ou 'cura', ou diz algo de saúde ou segurança que você não tem certeza que é verdade?", Rule: RuleRefuses},
		{ID: "c20", Text: "Pisca muito rápido ou tem luz estroboscópica?", Rule: RuleRefuses},
	}},
	{ID: "faixa", Title: "Faixa", Items: []ChecklistItem{
		{ID: "c22", Text: "Ritmo calmo, uma coisa por vez, frases curtas, sem gritaria ou cortes rápidos?", Rule: RuleBand, Positive: true},
		{ID: "c23", Text: "Tem começo, meio e fim claros?", Rule: RuleRefuses, Positive: true},
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
