package repoconfig

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

const iosMeta = "app/fastlane/metadata/ios"
const androidMeta = "app/fastlane/metadata/android"

func metaText(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(Root(), rel))
	if err != nil {
		t.Fatalf("%s: %v", rel, err)
	}
	return strings.TrimRight(string(b), "\n")
}

// rawText reads a file as the store receives it. Google Play takes the
// file whole, so a trailing newline would become part of the title.
func rawText(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(Root(), rel))
	if err != nil {
		t.Fatalf("%s: %v", rel, err)
	}
	return string(b)
}

// fold lowercases and strips accents, so "Vídeos" and "videos" compare equal.
func fold(s string) string {
	t := transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC)
	out, _, _ := transform.String(t, strings.ToLower(s))
	return out
}

type limit struct {
	rel string
	max int
}

func TestStoreTextsFitTheirFields(t *testing.T) {
	var limits []limit
	for _, loc := range []string{"pt-BR", "en-GB"} {
		d := iosMeta + "/" + loc + "/"
		limits = append(limits,
			limit{d + "name.txt", 30}, limit{d + "subtitle.txt", 30},
			limit{d + "keywords.txt", 100}, limit{d + "promotional_text.txt", 170},
			limit{d + "description.txt", 4000})
	}
	a := androidMeta + "/pt-BR/"
	limits = append(limits, limit{a + "title.txt", 30}, limit{a + "short_description.txt", 80}, limit{a + "full_description.txt", 4000})
	for _, l := range limits {
		s := metaText(t, l.rel)
		if strings.HasPrefix(l.rel, androidMeta) {
			s = rawText(t, l.rel)
		}
		if strings.TrimSpace(s) == "" {
			t.Errorf("%s is empty", l.rel)
		}
		if n := utf8.RuneCountInString(s); n > l.max {
			t.Errorf("%s has %d characters, the field allows %d", l.rel, n, l.max)
		}
	}
}

func TestPlayTextsEndWithoutANewline(t *testing.T) {
	for _, f := range []string{"title.txt", "short_description.txt", "full_description.txt"} {
		rel := androidMeta + "/pt-BR/" + f
		if s := rawText(t, rel); strings.HasSuffix(s, "\n") || strings.HasSuffix(s, "\r") {
			t.Errorf("%s ends with a newline, which Google Play would keep", rel)
		}
	}
}

// The exact texts the operator approved for the fields that rank.
func TestStoreTitlesAreTheApprovedOnes(t *testing.T) {
	want := map[string]string{
		iosMeta + "/pt-BR/name.txt":                  "Telinha Segura: vídeos curados",
		iosMeta + "/pt-BR/subtitle.txt":              "Controle parental com PIN",
		iosMeta + "/en-GB/name.txt":                  "Telinha Segura: Family Videos",
		iosMeta + "/en-GB/subtitle.txt":              "Screen time limits & PIN lock",
		androidMeta + "/pt-BR/title.txt":             "Telinha Segura: vídeo infantil",
		androidMeta + "/pt-BR/short_description.txt": "Vídeos infantis revisados por pais e cuidadores, com PIN e limite de tempo.",
		iosMeta + "/primary_category.txt":            "ENTERTAINMENT",
		iosMeta + "/secondary_category.txt":          "LIFESTYLE",
	}
	for rel, w := range want {
		if got := metaText(t, rel); got != w {
			t.Errorf("%s = %q, want %q", rel, got, w)
		}
	}
}

func TestAppStoreKeywordsAreClean(t *testing.T) {
	for _, loc := range []string{"pt-BR", "en-GB"} {
		d := iosMeta + "/" + loc + "/"
		kw := metaText(t, d+"keywords.txt")
		if strings.Contains(kw, ", ") || strings.Contains(kw, " ,") {
			t.Errorf("%s keywords: no spaces around commas", loc)
		}
		taken := map[string]bool{}
		for _, w := range strings.Fields(fold(metaText(t, d+"name.txt") + " " + metaText(t, d+"subtitle.txt"))) {
			taken[strings.Trim(w, ":&,.")] = true
		}
		seen := map[string]bool{}
		for _, term := range strings.Split(kw, ",") {
			f := fold(term)
			if f == "" || seen[f] {
				t.Errorf("%s keywords: empty or repeated term %q", loc, term)
			}
			seen[f] = true
			for _, w := range strings.Fields(f) {
				if taken[w] {
					t.Errorf("%s keywords: %q repeats a word of the name or subtitle", loc, term)
				}
			}
			if strings.Contains(f, "youtube") {
				t.Errorf("%s keywords: no trademarks (%q)", loc, term)
			}
		}
	}
}

var (
	bareNoAds = regexp.MustCompile(`(?i)sem an[uú]ncios(\s+nossos)?`)
	freeWord  = regexp.MustCompile(`(?i)\b(gr[aá]tis|gratuit[oa]s?|de gra[cç]a|free)\b`)
	kidsWord  = regexp.MustCompile(`(?i)\b(para crian[cç]as|infantil|infantis)\b`)
	// The English kids wording the App Store bars in visible fields; the
	// hidden keyword field may still carry "kids" and "children".
	kidsWordEN = regexp.MustCompile(`(?i)\b(for kids|for children|kids'|children's)`)
	proofWords = regexp.MustCompile(`(?i)(milh[oõ]es|milhares|mil fam[ií]lias|mais de mil|mais de \d|thousands of|millions of|★|estrelas|avalia[cç][aã]o \d|downloads)`)
)

func TestStoreTextsKeepTheCopyRules(t *testing.T) {
	descriptions := map[string]bool{
		iosMeta + "/pt-BR/description.txt": true, iosMeta + "/en-GB/description.txt": true,
		androidMeta + "/pt-BR/full_description.txt": true,
	}
	appleVisible := []string{"name.txt", "subtitle.txt", "promotional_text.txt", "description.txt"}
	var all []string
	for _, loc := range []string{"pt-BR", "en-GB"} {
		for _, f := range []string{"name.txt", "subtitle.txt", "keywords.txt", "promotional_text.txt", "description.txt"} {
			all = append(all, iosMeta+"/"+loc+"/"+f)
		}
	}
	all = append(all, androidMeta+"/pt-BR/title.txt", androidMeta+"/pt-BR/short_description.txt", androidMeta+"/pt-BR/full_description.txt")
	for _, rel := range all {
		s := metaText(t, rel)
		if strings.Contains(s, "!") {
			t.Errorf("%s: no exclamation marks", rel)
		}
		for _, m := range bareNoAds.FindAllStringSubmatch(s, -1) {
			if m[1] == "" {
				t.Errorf("%s: %q must read \"sem anúncios nossos\"", rel, m[0])
			}
		}
		if proofWords.MatchString(s) {
			t.Errorf("%s: no user numbers, ratings or testimonials (%q)", rel, proofWords.FindString(s))
		}
		if !descriptions[rel] {
			if strings.Contains(strings.ToLower(s), "youtube") {
				t.Errorf("%s: YouTube only in the long descriptions", rel)
			}
			if freeWord.MatchString(s) {
				t.Errorf("%s: price only in the long descriptions", rel)
			}
		}
	}
	for _, loc := range []string{"pt-BR", "en-GB"} {
		for _, f := range appleVisible {
			rel := iosMeta + "/" + loc + "/" + f
			s := metaText(t, rel)
			for _, re := range []*regexp.Regexp{kidsWord, kidsWordEN} {
				if re.MatchString(s) {
					t.Errorf("%s: the App Store bars %q outside the Kids category", rel, re.FindString(s))
				}
			}
		}
	}
}

func TestStoreURLsPointAtTheSite(t *testing.T) {
	want := map[string]string{
		"support_url.txt":   "https://telinhasegura.coding4u.tech/suporte",
		"marketing_url.txt": "https://telinhasegura.coding4u.tech/",
		"privacy_url.txt":   "https://telinhasegura.coding4u.tech/privacidade",
	}
	for _, loc := range []string{"pt-BR", "en-GB"} {
		for f, w := range want {
			if got := metaText(t, iosMeta+"/"+loc+"/"+f); got != w {
				t.Errorf("%s/%s = %q, want %q", loc, f, got, w)
			}
		}
	}
}
