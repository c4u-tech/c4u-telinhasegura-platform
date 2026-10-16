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
var pagePaths = []string{"/", "/privacidade", "/termos", "/suporte", "/excluir-conta", "/apoie"}

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
	allowed := []string{AppURL, RepoURL, "mailto:" + SupportEmail, "mailto:" + PrivacyEmail}
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
		"art. 14", "art. 18", "encarregad", PrivacyEmail, "youtube-nocookie.com",
	} {
		if !strings.Contains(p.Text, want) {
			t.Errorf("/privacidade does not mention %q", want)
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

func TestDonationPageTellsTheTruth(t *testing.T) {
	p := mustPages(t)["/apoie"]
	for _, want := range []string{
		"voluntári", "não é uma compra", "não dá direito", "Coding For You Tecnologia Ltda",
		"sem fins lucrativos", "dedu", "41.894.811/0001-60",
	} {
		if !strings.Contains(p.Text, want) {
			t.Errorf("/apoie does not say %q", want)
		}
	}
	if !contains(p.Loads, "/"+strings.TrimPrefix(PixQRPath, "site/public/")) {
		t.Error("/apoie does not show the Pix QR")
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
