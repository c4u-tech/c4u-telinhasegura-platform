package sitecheck

import (
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// The pages the site serves, by URL path.
var pagePaths = []string{"/", "/privacidade", "/termos", "/suporte", "/excluir-conta", "/participe", "/curadoria"}

func mustPages(t *testing.T) map[string]*Page {
	t.Helper()
	pages := map[string]*Page{}
	for _, p := range append(append([]string{}, pagePaths...), "/404") {
		page, err := LoadPage(p)
		if err != nil {
			t.Fatalf("%s: %v", p, err)
		}
		pages[p] = page
	}
	return pages
}

func TestEveryPageHasItsHeadAndOneHeading(t *testing.T) {
	titles := map[string]string{}
	for path, p := range mustPages(t) {
		if p.Lang != "pt-BR" {
			t.Errorf("%s: lang = %q", path, p.Lang)
		}
		if !strings.Contains(p.Meta["viewport"], "width=device-width") {
			t.Errorf("%s: no viewport", path)
		}
		if strings.TrimSpace(p.Meta["description"]) == "" {
			t.Errorf("%s: no meta description", path)
		}
		if p.Title == "" {
			t.Errorf("%s: no title", path)
		} else if other, dup := titles[p.Title]; dup {
			t.Errorf("%s and %s share the title %q", path, other, p.Title)
		}
		titles[p.Title] = path
		if p.H1 != 1 {
			t.Errorf("%s: %d h1 elements, want 1", path, p.H1)
		}
	}
}

// The footer links every other page, the repository and
// the endorsement.
func TestEveryFooterLinksTheWholeSite(t *testing.T) {
	for path, p := range mustPages(t) {
		for _, want := range pagePaths {
			if want == path || want == "/" {
				continue
			}
			if !contains(p.FooterHrefs, want) {
				t.Errorf("%s: footer lacks %s", path, want)
			}
		}
		if !contains(p.FooterHrefs, RepoURL) {
			t.Errorf("%s: footer lacks the repository", path)
		}
		if !strings.Contains(p.FooterText, "Feito pela Coding4u") {
			t.Errorf("%s: footer lacks the endorsement", path)
		}
	}
}

// Everything the page loads is its own.
func TestPagesLoadOnlyTheirOwnFiles(t *testing.T) {
	for path, p := range mustPages(t) {
		if p.InlineScripts > 0 || p.StyleElements > 0 || p.StyleAttrs > 0 {
			t.Errorf("%s: %d inline scripts, %d style elements, %d style attributes", path, p.InlineScripts, p.StyleElements, p.StyleAttrs)
		}
		for _, src := range p.Loads {
			if u, err := url.Parse(src); err != nil || u.Scheme != "" || u.Host != "" || strings.HasPrefix(src, "//") {
				t.Errorf("%s loads %q from outside the site", path, src)
				continue
			}
			if !fileExists(src) {
				t.Errorf("%s loads %q, which is not in site/public", path, src)
			}
		}
	}
	css := mustRead(t, "site/public/site.css")
	for _, m := range regexp.MustCompile(`url\(([^)]*)\)`).FindAllStringSubmatch(css, -1) {
		ref := strings.Trim(m[1], `"' `)
		if strings.Contains(ref, ":") || !fileExists(ref) {
			t.Errorf("site.css references %q", ref)
		}
	}
	if strings.Contains(css, "@import") {
		t.Error("site.css imports another stylesheet")
	}
}

func TestLinksResolveAndLeaveOnlyForKnownPlaces(t *testing.T) {
	pages := mustPages(t)
	allowed := []string{AppURL, RepoURL, "mailto:" + SupportEmail, "mailto:" + PrivacyEmail, "mailto:" + CurationEmail,
		"mailto:" + ReportEmail, GooglePrivacyURL, YouTubeTermsURL, RepoURL + "/blob/"}
	for path, p := range pages {
		for _, href := range p.Hrefs {
			u, err := url.Parse(href)
			if err != nil {
				t.Errorf("%s: bad href %q", path, href)
				continue
			}
			if u.Scheme != "" || u.Host != "" {
				ok := false
				for _, a := range allowed {
					if href == a || strings.HasPrefix(href, a+"/") || strings.HasPrefix(href, a+"?") {
						ok = true
					}
				}
				if !ok {
					t.Errorf("%s links outside the allowed places: %q", path, href)
				}
				continue
			}
			target := path
			if u.Path != "" {
				target = u.Path
			}
			tp, isPage := pages[target]
			if !isPage && !fileExists(target) {
				t.Errorf("%s links %q, which resolves to nothing", path, href)
				continue
			}
			if u.Fragment != "" && (!isPage || !contains(tp.IDs, u.Fragment)) {
				t.Errorf("%s links %q, but no element has that id", path, href)
			}
		}
	}
}

func TestLandingOpensTheWebAppAndNamesTheStoresAsComing(t *testing.T) {
	p := mustPages(t)["/"]
	n := 0
	for i, href := range p.Hrefs {
		if href == AppURL && p.HrefTexts[i] == "Usar no navegador" {
			n++
		}
	}
	if n < 2 {
		t.Errorf("the landing carries %d \"Usar no navegador\" links to the web app, want 2", n)
	}
	for _, store := range []string{"Google Play", "App Store"} {
		if !strings.Contains(p.Text, store) {
			t.Errorf("the landing does not name %s", store)
		}
	}
	if !strings.Contains(p.Text, "em breve") {
		t.Error("the landing does not say the stores are coming")
	}
	for _, href := range p.Hrefs {
		if strings.Contains(href, "play.google.com") || strings.Contains(href, "apps.apple.com") {
			t.Errorf("the landing links a store: %s", href)
		}
	}
}

func TestNoPageStatesNumbersItCannotProve(t *testing.T) {
	claim := regexp.MustCompile(`(?i)\b\d[\d.]*\s*(mil\s+)?(revisor|curador|vídeo|famíli|usuári|pais\b|download|estrela)|depoimento|avaliaç(ão|ões) n[ao]s? loja`)
	for path, p := range mustPages(t) {
		if m := claim.FindString(p.Text); m != "" {
			t.Errorf("%s states %q", path, m)
		}
	}
}

func TestLegalPagesAreDatedAndPendingReview(t *testing.T) {
	date := regexp.MustCompile(`Versão de \d{1,2} de [a-zç]+ de 20\d\d`)
	for _, path := range []string{"/privacidade", "/termos"} {
		p := mustPages(t)[path]
		if !date.MatchString(p.Text) {
			t.Errorf("%s does not show its version date", path)
		}
		if !strings.Contains(p.Text, "revisão jurídica") {
			t.Errorf("%s does not say it is pending legal review", path)
		}
	}
}

func TestPrivacyPolicyCoversTheLawsList(t *testing.T) {
	p := mustPages(t)["/privacidade"]
	for _, want := range []string{
		"e-⁠mail", "apelido", "faixa de idade", "PIN", "aparelho", "consentimento",
		"30 dias", "90 dias", "29 dias", "Mailgun", "Estados Unidos", "Google Cloud",
		"art. 14", "art. 18", "Nosso canal para assuntos de dados pessoais", PrivacyEmail, "youtube-nocookie.com",
	} {
		if !strings.Contains(p.Text, want) {
			t.Errorf("/privacidade does not mention %q", want)
		}
	}
}

// LGPD art. 33: the policy names who hosts the server and the database,
// and in which country, not only where the backups live.
func TestPrivacyPolicyNamesTheHostAndItsCountry(t *testing.T) {
	p := mustPages(t)["/privacidade"]
	want := "Hospeda o servidor onde o Telinha Segura roda, com o banco de dados"
	if !strings.Contains(p.Text, want) {
		t.Errorf("/privacidade does not name the host of the server and the database")
	}
	if strings.Contains(p.Text, "provedor de hospedagem contratado") {
		t.Errorf("/privacidade still hides the hosting provider")
	}
}

// What the law, YouTube's API policies and the stores ask the public pages
// to say, and what they say must match how the service works.
func TestLegalPagesCarryTheRequiredNotices(t *testing.T) {
	pages := mustPages(t)
	says := map[string][]string{
		"/privacidade": {"Serviços de API do YouTube", "anúncios do próprio YouTube", "37 dias",
			"15 dias", "não é obrigado a autorizar", "em nosso nome",
			"Registro de acesso", "6 meses", "Marco Civil da Internet, art. 15", "ordem judicial",
			"5 anos depois da exclusão do perfil", "Mantido por 5 anos",
			"apagado 90 dias depois de vencer ou ser encerrada", "(2 a 4, 5 a 8, ou 9 a 12 anos)",
			"registro de acesso dos aparelhos vinculados",
			"a porta quando disponível", "6 meses, inclusive depois da exclusão da conta, por obrigação legal",
			"ligado à conta excluída e em sigilo", "o registro de acesso da sua conta"},
		"/termos": {"pelo menos duas pessoas", "15 dias", "30 dias de antecedência",
			"Termos de Serviço do YouTube", "abuso", "classificação indicativa Livre", Address,
			"escolhe e supervisiona quem faz a curadoria"},
		"/suporte":       {ReportEmail, "mesmo sem conta", "anônim", "Disque 100", "190"},
		"/excluir-conta": {"37 dias", "15 dias"},
		"/":              {"pelo menos duas pessoas"},
	}
	for path, wants := range says {
		for _, want := range wants {
			if !strings.Contains(pages[path].Text, want) {
				t.Errorf("%s does not say %q", path, want)
			}
		}
	}
	links := map[string][]string{
		"/privacidade": {GooglePrivacyURL},
		"/termos":      {YouTubeTermsURL, "/curadoria"},
		"/suporte":     {"mailto:" + ReportEmail},
	}
	for path, hrefs := range links {
		for _, h := range hrefs {
			if !contains(pages[path].Hrefs, h) {
				t.Errorf("%s does not link %s", path, h)
			}
		}
	}
	// A report hides a video from the reporting family at once; it leaves
	// everyone's screen only when several families report it.
	stale := regexp.MustCompile(`volta para (a comunidade )?revis|em até 29 dias|O modo criança não tem anúncios|encarregad|[Aa]té 4 anos|\(até 4,|IP não fica gravado`)
	for path, p := range pages {
		if m := stale.FindString(p.Text); m != "" {
			t.Errorf("%s still says %q, which no longer matches the service", path, m)
		}
	}
}

func TestHelpPagesGiveTheirSteps(t *testing.T) {
	pages := mustPages(t)
	del := pages["/excluir-conta"]
	for _, want := range []string{"Sua conta", "Excluir conta", "Excluir minha conta", "na hora", SupportEmail} {
		if !strings.Contains(del.Text, want) {
			t.Errorf("/excluir-conta does not mention %q", want)
		}
	}
	sup := pages["/suporte"]
	for _, want := range []string{SupportEmail, "Denunciar este vídeo"} {
		if !strings.Contains(sup.Text, want) {
			t.Errorf("/suporte does not mention %q", want)
		}
	}
}

// The service asks nobody for money: people take part by curating, telling
// other families, reporting and contributing to the open code.
func TestJoinPageInvitesCurators(t *testing.T) {
	p := mustPages(t)["/participe"]
	for _, want := range []string{
		"curador", CurationEmail, "voluntári", "não é remunerad", "código aberto",
	} {
		if !strings.Contains(p.Text, want) {
			t.Errorf("/participe does not say %q", want)
		}
	}
	if !contains(p.Hrefs, "mailto:"+CurationEmail) {
		t.Error("/participe does not link the curation mailbox")
	}
	if !contains(p.Hrefs, RepoURL) {
		t.Error("/participe does not link the code")
	}
}

func TestNoPageAsksForMoney(t *testing.T) {
	money := regexp.MustCompile(`(?i)\bpix\b|doa(ç|c)(ão|ões)|\bdoar\b|contribui(ç|c)(ão|ões) (voluntária|financeira)|apoie o projeto`)
	for path, p := range mustPages(t) {
		if m := money.FindString(p.Text); m != "" {
			t.Errorf("%s asks for money: %q", path, m)
		}
		for _, h := range p.Hrefs {
			if h == "/apoie" {
				t.Errorf("%s still links /apoie", path)
			}
		}
	}
}

// Markup never leaks into what a reader sees or hears (a tag pasted inside
// an attribute ends the attribute early and spills the rest as text).
func TestNoMarkupLeaksIntoText(t *testing.T) {
	leak := regexp.MustCompile(`<|>|\w="`)
	for path, p := range mustPages(t) {
		if m := leak.FindString(p.Text); m != "" {
			t.Errorf("%s shows markup as text: %q", path, m)
		}
	}
}

// Curly quotes belong to copy, never to markup: an attribute opened by one
// is unquoted, and its value stops at the first space.
func TestAttributesUseStraightQuotes(t *testing.T) {
	files, _ := filepath.Glob(filepath.Join(Root(), "site", "public", "*.html"))
	for _, f := range files {
		b, _ := os.ReadFile(f)
		if m := regexp.MustCompile(`=[“”‘’]`).Find(b); m != nil {
			t.Errorf("%s opens an attribute with %q", filepath.Base(f), m)
		}
	}
}

func TestCopyKeepsTheBrandsTypography(t *testing.T) {
	bare := regexp.MustCompile(`(?i)e-mail`)
	for path, p := range mustPages(t) {
		if m := bare.FindString(p.Text); m != "" {
			t.Errorf("%s sets %q without a word joiner", path, m)
		}
		if strings.Contains(p.Text, "!") {
			t.Errorf("%s carries an exclamation mark", path)
		}
	}
}

func contains(xs []string, x string) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}

func fileExists(urlPath string) bool {
	u, err := url.Parse(urlPath)
	if err != nil {
		return false
	}
	st, err := os.Stat(filepath.Join(Root(), "site", "public", filepath.FromSlash(strings.TrimPrefix(u.Path, "/"))))
	return err == nil && !st.IsDir()
}

func mustRead(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(Root(), rel))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// The company's full address, as consumer law asks of a business online.
const Address = "Alameda Salvador, 1057, Salvador Shopping Business, Torre América, salas 911 e 912, Caminho das Árvores, Salvador, BA, CEP 41820-790"

func TestEveryFooterGivesTheFullAddress(t *testing.T) {
	for path, p := range mustPages(t) {
		if !strings.Contains(p.FooterText, Address) {
			t.Errorf("%s: footer lacks the full address", path)
		}
	}
}

// The criteria the curation follows are public, so families can check them.
func TestCurationPagePublishesTheCriteria(t *testing.T) {
	pages := mustPages(t)
	p := pages["/curadoria"]
	for _, want := range []string{
		"Classificação Indicativa", "Livre", "2 a 4", "5 a 8", "9 a 12 anos",
		"pelo menos duas pessoas", "Quem sugere um vídeo não pode aprová-lo",
		"A Coding4u, que faz o Telinha Segura, escolhe quem faz parte da curadoria",
		"Não recusamos", "menos de 2 anos", "Denunciar este vídeo",
	} {
		if !strings.Contains(p.Text, want) {
			t.Errorf("/curadoria does not say %q", want)
		}
	}
	if !contains(pages["/participe"].Hrefs, "/curadoria") {
		t.Error("/participe does not link /curadoria")
	}
}
