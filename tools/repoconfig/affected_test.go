package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// affectedRepo is a repository shaped like this one: the Go modules, the
// app package with its fastlane tooling, the four image contexts, docs and
// the shared files, committed on dev. It is left on a branch pr off dev.
func affectedRepo(t *testing.T) string {
	t.Helper()
	dockerignore, err := os.ReadFile(filepath.Join(Root(), "app", ".dockerignore"))
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	git(t, dir, "init")
	tree(t, dir, map[string]string{
		"backend/go.mod":                     "module backend\n",
		"backend/main.go":                    "package main\n",
		"backend/internal/identity/terms.go": "package identity\n",
		"backend/Dockerfile":                 "FROM scratch\n",
		"tools/sitecheck/go.mod":             "module sitecheck\n",
		"tools/repoconfig/go.mod":            "module repoconfig\n",
		"tools/dco/go.mod":                   "module dco\n",
		"app/pubspec.yaml":                   "name: app\n",
		"app/lib/a.dart":                     "void main() {}\n",
		"app/fastlane/Fastfile":              "lane :x do\nend\n",
		"app/.dockerignore":                  string(dockerignore),
		"app/Dockerfile":                     "FROM scratch\n",
		"site/public/index.html":             "<p>hi</p>\n",
		"site/Dockerfile":                    "FROM scratch\n",
		"deploy/backup/Dockerfile":           "FROM scratch\n",
		"docs/x.md":                          "# x\n",
		"Makefile":                           "check:\n",
		"scripts/s.sh":                       "#!/bin/sh\n",
		".github/workflows/ci.yml":           "name: ci\n",
		".github/CODEOWNERS":                 "* @someone\n",
	})
	git(t, dir, "add", "-A")
	git(t, dir, "commit", "-m", "start")
	git(t, dir, "checkout", "-b", "pr")
	return dir
}

// change writes each file and commits the change on the current branch.
func change(t *testing.T, dir string, rels ...string) {
	t.Helper()
	for _, rel := range rels {
		tree(t, dir, map[string]string{rel: "changed " + rel + "\n"})
	}
	git(t, dir, "add", "-A")
	git(t, dir, "commit", "-m", "change")
}

func runAffected(t *testing.T, dir string, args ...string) (map[string]string, string, error) {
	t.Helper()
	cmd := exec.Command("sh", append([]string{filepath.Join(Root(), "scripts", "affected.sh")}, args...)...)
	cmd.Dir = dir
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	got := map[string]string{}
	for _, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		if k, v, ok := strings.Cut(line, "="); ok {
			got[k] = v
		}
	}
	return got, stderr.String(), err
}

func mustAffected(t *testing.T, dir string, args ...string) map[string]string {
	t.Helper()
	got, stderr, err := runAffected(t, dir, args...)
	if err != nil {
		t.Fatalf("affected.sh %v: %v\n%s", args, err, stderr)
	}
	return got
}

func affectedBetweenDevAndHead(t *testing.T, dir string) map[string]string {
	t.Helper()
	return mustAffected(t, dir, "dev", "HEAD")
}

func wantAffected(t *testing.T, got map[string]string, goMods, dart, ruby, images, full string) {
	t.Helper()
	want := map[string]string{"go": goMods, "dart": dart, "ruby": ruby, "images": images, "full": full}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("affected\n got %v\nwant %v", got, want)
	}
}

const everyGoModule = "backend/ tools/dco/ tools/repoconfig/ tools/sitecheck/"

func TestAffectedSiteOnly(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "site/public/index.html")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "tools/repoconfig/ tools/sitecheck/", "", "false", "site", "false")
}

// The site's legal pages show the terms version the backend defines.
func TestAffectedTermsVersionAlsoChecksTheSite(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "backend/internal/identity/terms.go")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "backend/ tools/repoconfig/ tools/sitecheck/", "", "false", "api backup", "false")
}

// The backup image's smoke test runs against the API image.
func TestAffectedBackendAlsoSmokesBackup(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "backend/main.go")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "backend/ tools/repoconfig/", "", "false", "api backup", "false")
}

func TestAffectedAppCode(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "app/lib/a.dart")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "tools/repoconfig/", "app/", "false", "web", "false")
}

func TestAffectedFastlaneIsRubyOnly(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "app/fastlane/Fastfile")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "tools/repoconfig/", "", "true", "", "false")
}

func TestAffectedDocsOnly(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "docs/x.md", ".github/CODEOWNERS")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "tools/repoconfig/", "", "false", "", "false")
}

func TestAffectedSharedPathsMeanEverything(t *testing.T) {
	for _, rel := range []string{"Makefile", "scripts/s.sh", ".github/workflows/ci.yml", "unknown/file"} {
		t.Run(rel, func(t *testing.T) {
			dir := affectedRepo(t)
			change(t, dir, rel)
			wantAffected(t, affectedBetweenDevAndHead(t, dir), everyGoModule, "app/", "true", "api web site backup", "true")
		})
	}
}

// A commit that reached dev after the branch was cut is not the pull
// request's change, so it must not widen what the pull request runs.
func TestAffectedCountsOnlyThePRsOwnChanges(t *testing.T) {
	dir := affectedRepo(t)
	change(t, dir, "site/public/index.html")
	git(t, dir, "checkout", "dev")
	change(t, dir, "backend/main.go")
	git(t, dir, "checkout", "pr")
	wantAffected(t, affectedBetweenDevAndHead(t, dir), "tools/repoconfig/ tools/sitecheck/", "", "false", "site", "false")
}

func TestAffectedDeletedModuleMeansEverything(t *testing.T) {
	dir := affectedRepo(t)
	git(t, dir, "rm", "-r", "-q", "tools/dco")
	git(t, dir, "commit", "-m", "drop dco")
	if got := affectedBetweenDevAndHead(t, dir); got["full"] != "true" {
		t.Errorf("full = %q, want true (got %v)", got["full"], got)
	}
}

func TestAffectedAllFlag(t *testing.T) {
	dir := affectedRepo(t)
	wantAffected(t, mustAffected(t, dir, "--all"), everyGoModule, "app/", "true", "api web site backup", "true")
}

func TestAffectedRefusesBadArgs(t *testing.T) {
	dir := affectedRepo(t)
	for _, args := range [][]string{{}, {"dev"}} {
		_, stderr, err := runAffected(t, dir, args...)
		if err == nil || !strings.Contains(stderr, "usage") {
			t.Errorf("args %v: err %v, stderr %q; want a non-zero exit with a usage line", args, err, stderr)
		}
	}
}
