package sitecheck

import (
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// The pages are hand-written, so header and footer are copied into each.
// The copies must stay the same: only the mark of the page a reader is on
// may differ.
func TestHeaderAndFooterAreTheSameOnEveryPage(t *testing.T) {
	blocks := map[string]*regexp.Regexp{
		"header": regexp.MustCompile(`(?s)<header class="site-header">.*?</header>`),
		"footer": regexp.MustCompile(`(?s)<footer class="site-footer">.*?</footer>`),
	}
	mark := regexp.MustCompile(` aria-current="page"`)
	for name, re := range blocks {
		var want, wantFrom string
		for _, path := range append(append([]string{}, pagePaths...), "/404") {
			raw := mustReadPage(t, path)
			found := re.FindAllString(raw, -1)
			if len(found) != 1 {
				t.Errorf("%s: %d site %s blocks, want 1", path, len(found), name)
				continue
			}
			got := mark.ReplaceAllString(found[0], "")
			if want == "" {
				want, wantFrom = got, path
				continue
			}
			if got != want {
				t.Errorf("%s: the %s differs from the one on %s", path, name, wantFrom)
			}
		}
	}
}

// Each page marks where the reader is, once in the header's places or the
// footer's, and never marks another page.
func TestEveryPageMarksOnlyItself(t *testing.T) {
	current := regexp.MustCompile(`<a [^>]*href="([^"]*)"[^>]*aria-current="page"|<a [^>]*aria-current="page"[^>]*href="([^"]*)"`)
	for _, path := range append(append([]string{}, pagePaths...), "/404") {
		for _, m := range current.FindAllStringSubmatch(mustReadPage(t, path), -1) {
			href := m[1] + m[2]
			if href != path {
				t.Errorf("%s marks %s as the current page", path, href)
			}
		}
	}
}

// The header names the site and four places; on a phone the footer carries
// them, so the header's list may hide there.
func TestHeaderNamesTheFourPlaces(t *testing.T) {
	raw := regexp.MustCompile(`(?s)<header class="site-header">.*?</header>`).FindString(mustReadPage(t, "/"))
	links := regexp.MustCompile(`<a [^>]*href="([^"]*)"[^>]*>([^<]*)<`).FindAllStringSubmatch(raw, -1)
	want := [][2]string{{"/curadoria", "Como escolhemos"}, {"/participe", "Participe"}, {"/suporte", "Suporte"}, {AppURL, "Usar no navegador"}}
	var got [][2]string
	for _, l := range links {
		if l[1] == "/" {
			continue // the wordmark
		}
		got = append(got, [2]string{l[1], strings.TrimSpace(l[2])})
	}
	if len(got) != len(want) {
		t.Fatalf("header links %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("header link %d = %v, want %v", i, got[i], want[i])
		}
	}
	if !strings.Contains(raw, `<a class="wordmark" href="/"`) {
		t.Error("the header's wordmark does not lead home")
	}
}

// The footer's columns and every link it has always had, and the code's
// licence named beside the repository.
func TestFooterGroupsItsLinks(t *testing.T) {
	p := mustPages(t)["/404"]
	for _, want := range []string{"O app", "Seus dados", "Código aberto", "Vídeos para crianças escolhidos por gente.", "Licença AGPL", "Código no GitHub"} {
		if !strings.Contains(p.FooterText, want) {
			t.Errorf("the footer lacks %q", want)
		}
	}
	if !contains(p.FooterHrefs, AppURL) {
		t.Error("the footer does not lead to the web app")
	}
}

// Every picture reserves its place before it loads and says what it shows,
// or says it shows nothing (alt="").
func TestImagesCarryTheirSizeAndAlternative(t *testing.T) {
	for path, p := range mustPages(t) {
		for _, img := range p.Images {
			if !img.HasAlt {
				t.Errorf("%s: %s has no alt", path, img.Src)
			}
			if _, err := strconv.Atoi(img.Width); err != nil {
				t.Errorf("%s: %s has no width", path, img.Src)
			}
			if _, err := strconv.Atoi(img.Height); err != nil {
				t.Errorf("%s: %s has no height", path, img.Src)
			}
		}
	}
}

// The mascot the site used before is gone from the pictures and their
// descriptions: the drawing over the header, the old sun in the stylesheet
// and the link preview's card, and the name anywhere else. The terms of use
// still name the old character once, as a trademark; that is legal text,
// changed only with the terms, so that one sentence is the only exception.
func TestTheOldMascotIsGone(t *testing.T) {
	old := regexp.MustCompile(`(?i)class="head"|#f2b23a|espiadinha`)
	const trademark = "a Espiadinha (o personagem da marca)"
	files, _ := filepath.Glob(filepath.Join(Root(), "site", "public", "*.html"))
	files = append(files, filepath.Join(Root(), "site", "public", "site.css"), filepath.Join(Root(), "site", "og", "card.html"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		if filepath.Base(f) == "termos.html" {
			b = []byte(strings.Replace(string(b), trademark, "", 1))
		}
		if m := old.Find(b); m != nil {
			t.Errorf("%s still carries %q", filepath.Base(f), m)
		}
	}
	if !strings.Contains(mustRead(t, "site/public/site.css"), "--sun: #ffc42e;") {
		t.Error("site.css does not carry the brand's sun, #ffc42e")
	}
}

// The home page shows the review as four steps, the first with nobody on
// the wire yet, and leads to the curation page and the code.
func TestHomeShowsTheReviewAndTheCode(t *testing.T) {
	raw := mustReadPage(t, "/")
	list := regexp.MustCompile(`(?s)<ol class="wire-steps">(.*?)</ol>`).FindStringSubmatch(raw)
	if list == nil {
		t.Fatal("the home page has no list of the review's steps")
	}
	items := regexp.MustCompile(`(?s)<li>.*?</li>`).FindAllString(list[1], -1)
	if len(items) != 4 {
		t.Fatalf("the review has %d steps, want 4", len(items))
	}
	for i, item := range items {
		if n := strings.Count(item, `class="bird"`); n != i {
			t.Errorf("step %d shows %d birds", i+1, n)
		}
		if !strings.Contains(item, "<svg") {
			t.Errorf("step %d has no drawn wire", i+1)
		}
	}
	// The second approval is the moment the video enters the app; it reads
	// as the step's headline.
	if !strings.Contains(items[2], `<p class="moment">Só agora o vídeo entra no app.</p>`) {
		t.Error("the third step does not set its moment apart")
	}
	// On a phone the words about the resting screen come before its picture.
	night := regexp.MustCompile(`(?s)<section id="uma-telinha-com-fim".*?</section>`).FindString(raw)
	if h, i := strings.Index(night, "<h2"), strings.Index(night, "<img"); h < 0 || i < 0 || h > i {
		t.Error("the resting section does not put its heading before its picture")
	}
	p := mustPages(t)["/"]
	for _, s := range []string{
		"Pedimos o mínimo sobre a criança: um apelido, um avatar e a faixa de idade.",
		"Você entrega o celular no modo criança, ou vincula o tablet da criança à sua família.",
	} {
		if !strings.Contains(p.Text, s) {
			t.Errorf("the home page no longer says %q", s)
		}
	}
	for i, h := range p.Hrefs {
		if h == RepoURL && p.HrefTexts[i] == "Código no GitHub" {
			return
		}
	}
	t.Error("the home page does not link the code with the words \"Código no GitHub\"")
}

func TestNotFoundPageSaysNobodySawIt(t *testing.T) {
	p := mustPages(t)["/404"]
	if !strings.Contains(p.Text, "Ninguém viu esta página antes.") {
		t.Error("the 404 page does not say nobody saw it")
	}
	for _, h := range []string{"/", "/suporte"} {
		if !contains(p.Hrefs, h) {
			t.Errorf("the 404 page does not lead to %s", h)
		}
	}
}

// The text and the controls the site draws stay legible on the grounds
// they sit on (WCAG 2.2: 4.5:1 for text, 3:1 for focus rings and other
// non-text parts), in light and dark.
func TestColourPairsKeepTheirContrast(t *testing.T) {
	css := mustRead(t, "site/public/site.css")
	light := tokens(t, regexp.MustCompile(`(?s)^.*?:root \{(.*?)\n\}`).FindStringSubmatch(css))
	dark := tokens(t, regexp.MustCompile(`(?s)@media \(prefers-color-scheme: dark\) \{\s*:root \{(.*?)\n  \}`).FindStringSubmatch(css))
	for k, v := range light {
		if _, ok := dark[k]; !ok {
			dark[k] = v
		}
	}
	type pair struct {
		fg, bg string
		min    float64
	}
	pairs := []pair{
		{"text", "ground", 4.5}, {"muted", "ground", 4.5}, {"text", "paper", 4.5},
		{"muted", "paper", 4.5}, {"focus", "ground", 3}, {"focus", "paper", 3},
		{"cream", "ink", 4.5}, {"sun", "ink", 3}, {"dark", "sun", 4.5}, {"cream", "dark", 4.5},
		{"sky", "dark", 4.5}, {"muted-on-dark", "dark", 4.5}, {"cream", "night", 4.5}, {"sky", "night", 4.5},
		{"focus-on-field", "ink", 3}, {"focus-on-field", "dark", 3}, {"focus-on-field", "night", 3},
		// The skip link opens over the header's ink ground, so its ring
		// takes the on-field colour.
		{"skip-focus", "ink", 3},
	}
	if !regexp.MustCompile(`(?s)\.skip:focus-visible \{[^}]*outline-color: var\(--skip-focus\);`).MatchString(css) {
		t.Error("the skip link's focus ring does not use --skip-focus")
	}
	for scheme, vars := range map[string]map[string]string{"light": light, "dark": dark} {
		for _, p := range pairs {
			fg, bg := resolve(t, vars, p.fg), resolve(t, vars, p.bg)
			if r := contrast(fg, bg); r < p.min {
				t.Errorf("%s: %s on %s is %.2f:1, want %.1f:1", scheme, p.fg, p.bg, r, p.min)
			}
		}
	}
}

func tokens(t *testing.T, m []string) map[string]string {
	t.Helper()
	if m == nil {
		t.Fatal("site.css lacks a :root block")
	}
	out := map[string]string{}
	for _, d := range regexp.MustCompile(`--([a-z-]+):\s*([^;]+);`).FindAllStringSubmatch(m[1], -1) {
		out[d[1]] = strings.TrimSpace(d[2])
	}
	return out
}

func resolve(t *testing.T, vars map[string]string, name string) string {
	t.Helper()
	v, ok := vars[name]
	for i := 0; ok && strings.HasPrefix(v, "var(--") && i < 8; i++ {
		v, ok = vars[strings.TrimSuffix(strings.TrimPrefix(v, "var(--"), ")")]
	}
	if !ok || !regexp.MustCompile(`^#[0-9a-f]{6}$`).MatchString(v) {
		t.Fatalf("--%s is not a six-digit colour (%q)", name, v)
	}
	return v
}

func contrast(a, b string) float64 {
	la, lb := luminance(a), luminance(b)
	if la < lb {
		la, lb = lb, la
	}
	return (la + 0.05) / (lb + 0.05)
}

func luminance(hex string) float64 {
	ch := func(i int) float64 {
		v, _ := strconv.ParseUint(hex[i:i+2], 16, 8)
		c := float64(v) / 255
		if c <= 0.04045 {
			return c / 12.92
		}
		return math.Pow((c+0.055)/1.055, 2.4)
	}
	return 0.2126*ch(1) + 0.7152*ch(3) + 0.0722*ch(5)
}

func mustReadPage(t *testing.T, path string) string {
	t.Helper()
	name := strings.TrimPrefix(path, "/")
	if name == "" {
		name = "index"
	}
	return mustRead(t, filepath.Join("site", "public", name+".html"))
}
