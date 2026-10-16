package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestCommunityHealthFilesExist(t *testing.T) {
	for _, rel := range []string{
		"README.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md", "SUPPORT.md",
		".github/CODEOWNERS", ".github/ISSUE_TEMPLATE/bug_report.yml",
		".github/ISSUE_TEMPLATE/proposal.yml", ".github/ISSUE_TEMPLATE/config.yml",
	} {
		if _, err := os.Stat(filepath.Join(Root(), rel)); err != nil {
			t.Errorf("missing %s", rel)
		}
	}
}

func TestIssueChooserHasNoBlankIssuesAndPointsToPrivateReports(t *testing.T) {
	cfg := mustYAML(t, ".github/ISSUE_TEMPLATE/config.yml")
	if cfg["blank_issues_enabled"] != false {
		t.Errorf("blank_issues_enabled = %v, want false", cfg["blank_issues_enabled"])
	}
	links, _ := cfg["contact_links"].([]any)
	found := false
	for _, l := range links {
		if u, _ := Dig(l, "url").(string); strings.HasSuffix(u, "/security/advisories/new") {
			found = true
		}
	}
	if !found {
		t.Error("contact_links lacks the private vulnerability report (security/advisories/new)")
	}
}

func TestCodeownersCoversTheWholeTree(t *testing.T) {
	if !regexp.MustCompile(`(?m)^\*\s+@patricksferraz\s*$`).MatchString(read(t, ".github/CODEOWNERS")) {
		t.Error(".github/CODEOWNERS must assign * to @patricksferraz")
	}
}

var mdLink = regexp.MustCompile(`\]\(([^)\s]+)(?:\s+"[^"]*")?\)`)

// linkTarget returns the repository path a Markdown link points to, or
// false for links that are not files of this repository.
func linkTarget(link string) (string, bool) {
	if strings.HasPrefix(link, "#") || strings.Contains(link, "://") || strings.HasPrefix(link, "mailto:") {
		return "", false
	}
	if i := strings.IndexByte(link, '#'); i >= 0 {
		link = link[:i]
	}
	return strings.TrimPrefix(link, "./"), link != ""
}

func TestLinkTargetCases(t *testing.T) {
	cases := map[string]struct {
		path string
		ok   bool
	}{
		"CONTRIBUTING.md":   {"CONTRIBUTING.md", true},
		"./CONTRIBUTING.md": {"CONTRIBUTING.md", true},
		"docs/development/README.md#the-make-targets": {"docs/development/README.md", true},
		"#quick-start":              {"", false},
		"https://example.test/x.md": {"", false},
		"mailto:a@example.test":     {"", false},
	}
	for in, want := range cases {
		path, ok := linkTarget(in)
		if path != want.path || ok != want.ok {
			t.Errorf("linkTarget(%q) = %q, %v; want %q, %v", in, path, ok, want.path, want.ok)
		}
	}
}

// publicDocs are the files a visitor reads first: root Markdown and .github,
// as git publishes them (ignored files are not part of the repository).
func publicDocs(t *testing.T) []string {
	t.Helper()
	out, err := exec.Command("git", "-C", Root(), "ls-files", "-co", "--exclude-standard", "--", "*.md", ".github").Output()
	if err != nil {
		t.Fatalf("git ls-files: %v", err)
	}
	var files []string
	for _, rel := range strings.Fields(string(out)) {
		root := !strings.Contains(rel, "/") && strings.HasSuffix(rel, ".md")
		github := strings.HasPrefix(rel, ".github/") && (strings.HasSuffix(rel, ".md") || strings.HasSuffix(rel, ".yml") || filepath.Base(rel) == "CODEOWNERS")
		if !root && !github {
			continue
		}
		if _, err := os.Stat(filepath.Join(Root(), rel)); err == nil {
			files = append(files, filepath.Join(Root(), rel))
		}
	}
	return files
}

func TestRelativeLinksResolve(t *testing.T) {
	for _, f := range publicDocs(t) {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		rel, _ := filepath.Rel(Root(), f)
		for _, m := range mdLink.FindAllStringSubmatch(string(b), -1) {
			target, ok := linkTarget(m[1])
			if !ok {
				continue
			}
			if _, err := os.Stat(filepath.Join(filepath.Dir(f), target)); err != nil {
				t.Errorf("%s links to %s, which does not exist", rel, m[1])
			}
		}
	}
}

// A link to the site names a page it serves (site/public/<page>.html).
func TestSiteLinksNameBuiltPages(t *testing.T) {
	site := regexp.MustCompile(`https://telinhasegura\.coding4u\.tech/([a-z-]+)`)
	for _, f := range publicDocs(t) {
		b, _ := os.ReadFile(f)
		for _, m := range site.FindAllStringSubmatch(string(b), -1) {
			if _, err := os.Stat(filepath.Join(Root(), "site", "public", m[1]+".html")); err != nil {
				rel, _ := filepath.Rel(Root(), f)
				t.Errorf("%s links to %s, which the site does not serve", rel, m[0])
			}
		}
	}
}

// Donations go only to the site's page.
func TestFundingPointsOnlyToTheDonationPage(t *testing.T) {
	cfg := mustYAML(t, ".github/FUNDING.yml")
	if len(cfg) != 1 {
		t.Errorf("FUNDING.yml has %d platforms, want only custom", len(cfg))
	}
	custom := cfg["custom"]
	if list, ok := custom.([]any); ok && len(list) == 1 {
		custom = list[0]
	}
	if custom != "https://telinhasegura.coding4u.tech/apoie" {
		t.Errorf("FUNDING.yml custom = %v, want the site's /apoie", custom)
	}
}

func TestReadmeAndSupportPointToTheSite(t *testing.T) {
	readme := read(t, "README.md")
	if !regexp.MustCompile(`(?m)^## Apoie o projeto$`).MatchString(readme) ||
		!strings.Contains(readme, "https://telinhasegura.coding4u.tech/apoie") {
		t.Error(`README.md lacks an "Apoie o projeto" section linking /apoie`)
	}
	support := read(t, "SUPPORT.md")
	for _, want := range []string{"suporte@telinhasegura.coding4u.tech", "https://telinhasegura.coding4u.tech/suporte"} {
		if !strings.Contains(support, want) {
			t.Errorf("SUPPORT.md does not give %s", want)
		}
	}
}

// Families reach the site's support from the chooser.
func TestIssueChooserOffersFamiliesTheSupportPage(t *testing.T) {
	cfg := mustYAML(t, ".github/ISSUE_TEMPLATE/config.yml")
	links, _ := cfg["contact_links"].([]any)
	found := false
	for _, l := range links {
		if u, _ := Dig(l, "url").(string); u == "https://telinhasegura.coding4u.tech/suporte" {
			found = true
		}
	}
	if !found {
		t.Error("contact_links lacks the families' support page")
	}
}

func TestReadmeStatesTheSPDXExpression(t *testing.T) {
	if !strings.Contains(read(t, "README.md"), spdx) {
		t.Error("README.md does not state the SPDX expression")
	}
}

func TestReadmeLinksTheCommunityFiles(t *testing.T) {
	readme := read(t, "README.md")
	for _, f := range []string{"CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md", "CODE_OF_CONDUCT.md", "TRADEMARKS.md", "COPYRIGHT.md"} {
		if !strings.Contains(readme, "]("+f+")") {
			t.Errorf("README.md does not link %s", f)
		}
	}
}

// The README states the business model: free, no ads, no purchases.
func TestReadmeStatesTheBusinessModel(t *testing.T) {
	readme := read(t, "README.md")
	if !strings.Contains(readme, "Business model:") {
		t.Error("README.md lacks a \"Business model:\" line")
	}
	for _, want := range []string{"no ads", "no in-app purchases"} {
		if !strings.Contains(readme, want) {
			t.Errorf("README.md does not state %q", want)
		}
	}
}
