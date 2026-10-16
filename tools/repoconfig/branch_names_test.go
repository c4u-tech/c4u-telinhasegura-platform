package repoconfig

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// A file names the old integration branch when it quotes it as a code
// span, lists it as a workflow branch, or refers to it on the remote.
var oldBranch = regexp.MustCompile("`main`|\\[main\\]|origin/main|branches/main")

// This package spells the pattern out, so it is not scanned.
var unscannedPaths = []string{
	"tools/repoconfig/",
}

func scanned(path string) bool {
	for _, p := range unscannedPaths {
		if strings.HasPrefix(path, p) {
			return false
		}
	}
	switch filepath.Ext(path) {
	case ".md", ".yml", ".yaml", ".json", ".sh":
		return true
	}
	return filepath.Base(path) == "Makefile"
}

func TestScannedCoversConfigAndDocsButNotThisPackage(t *testing.T) {
	cases := map[string]bool{
		"CONTRIBUTING.md":              true,
		"Makefile":                     true,
		"scripts/back-merge.sh":        true,
		".github/workflows/ci.yml":     true,
		".github/rulesets/dev.json":    true,
		"docs/development/setup.md":    true,
		"tools/repoconfig/testdata.md": false,
		"app/lib/main.dart":            false,
	}
	for path, want := range cases {
		if got := scanned(path); got != want {
			t.Errorf("scanned(%q) = %v, want %v", path, got, want)
		}
	}
}

func TestNoFileNamesMainAsTheIntegrationBranch(t *testing.T) {
	out, err := exec.Command("git", "-C", Root(), "ls-files", "-co", "--exclude-standard").Output()
	if err != nil {
		t.Fatalf("git ls-files: %v", err)
	}
	for _, path := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if !scanned(path) {
			continue
		}
		f, err := os.Open(filepath.Join(Root(), path))
		if err != nil {
			continue // listed but deleted in the working tree
		}
		sc := bufio.NewScanner(f)
		for n := 1; sc.Scan(); n++ {
			if oldBranch.MatchString(sc.Text()) {
				t.Errorf("%s:%d names main as the integration branch: %s", path, n, strings.TrimSpace(sc.Text()))
			}
		}
		f.Close()
	}
}
