package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// tree writes files (path relative to dir → content), creating parents.
func tree(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for rel, body := range files {
		p := filepath.Join(dir, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// digestRepo is a repository with a build context svc/ whose
// .dockerignore mirrors the API's, and a file outside the context.
func digestRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	git(t, dir, "init")
	tree(t, dir, map[string]string{
		"svc/.dockerignore": "# not inputs\ntmp/\n**/*_test.go\n**/*.md\n.DS_Store\n",
		"svc/Dockerfile":    "FROM scratch\n",
		"svc/main.go":       "package main\n",
		"svc/main_test.go":  "package main\n",
		"svc/CHANGELOG.md":  "0.1.0\n",
		"svc/docs/notes.md": "notes\n",
		"svc/tmp/cache":     "x\n",
		"svc/pkg/lib.go":    "package pkg\n",
		"other/outside.txt": "outside\n",
	})
	git(t, dir, "add", "-A")
	return dir
}

func imageDigest(t *testing.T, dir, ctx string) (string, string, error) {
	t.Helper()
	cmd := exec.Command("sh", filepath.Join(Root(), "scripts", "image-digest.sh"), ctx)
	cmd.Dir = dir
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	return strings.TrimSpace(string(out)), stderr.String(), err
}

func mustDigest(t *testing.T, dir, ctx string) string {
	t.Helper()
	d, stderr, err := imageDigest(t, dir, ctx)
	if err != nil {
		t.Fatalf("image-digest %s: %v\n%s", ctx, err, stderr)
	}
	return d
}

var hex40 = regexp.MustCompile(`^[0-9a-f]{40}$`)

func TestImageDigestIsEqualForEqualInputs(t *testing.T) {
	a := mustDigest(t, digestRepo(t), "svc")
	b := mustDigest(t, digestRepo(t), "svc/")
	if !hex40.MatchString(a) {
		t.Fatalf("digest %q is not 40 hex characters", a)
	}
	if a != b {
		t.Errorf("equal inputs gave %s and %s", a, b)
	}
}

func TestImageDigestIgnoresWhatDockerignoreExcludes(t *testing.T) {
	for _, rel := range []string{"svc/CHANGELOG.md", "svc/docs/notes.md", "svc/main_test.go", "svc/tmp/cache", "svc/tmp/new", "other/outside.txt"} {
		t.Run(rel, func(t *testing.T) {
			dir := digestRepo(t)
			before := mustDigest(t, dir, "svc")
			tree(t, dir, map[string]string{rel: "changed\n"})
			git(t, dir, "add", "-A")
			if after := mustDigest(t, dir, "svc"); after != before {
				t.Errorf("changing %s changed the digest", rel)
			}
		})
	}
}

func TestImageDigestChangesWithAnyBuildInput(t *testing.T) {
	for _, rel := range []string{"svc/main.go", "svc/Dockerfile", "svc/pkg/lib.go", "svc/pkg/new.go", "svc/.dockerignore"} {
		t.Run(rel, func(t *testing.T) {
			dir := digestRepo(t)
			before := mustDigest(t, dir, "svc")
			tree(t, dir, map[string]string{rel: "changed\n"})
			git(t, dir, "add", "-A")
			if after := mustDigest(t, dir, "svc"); after == before {
				t.Errorf("changing %s left the digest at %s", rel, before)
			}
		})
	}
}

// The web image copies an untracked build output; only tracked sources
// name it.
func TestImageDigestIgnoresUntrackedFiles(t *testing.T) {
	dir := digestRepo(t)
	before := mustDigest(t, dir, "svc")
	tree(t, dir, map[string]string{"svc/build/web/main.dart.js": "built\n"})
	if after := mustDigest(t, dir, "svc"); after != before {
		t.Error("an untracked file changed the digest")
	}
}

func TestImageDigestWorksFromASubdirectory(t *testing.T) {
	dir := digestRepo(t)
	want := mustDigest(t, dir, "svc")
	if got := mustDigest(t, filepath.Join(dir, "other"), "svc"); got != want {
		t.Errorf("from other/: %s, want %s", got, want)
	}
}

func TestImageDigestRejectsANegatedPattern(t *testing.T) {
	dir := digestRepo(t)
	tree(t, dir, map[string]string{"svc/.dockerignore": "*\n!main.go\n"})
	_, stderr, err := imageDigest(t, dir, "svc")
	if err == nil || !strings.Contains(stderr, "negated") {
		t.Errorf("err %v, stderr %q; want a failure naming negated patterns", err, stderr)
	}
}

func TestImageDigestFailsWithoutTheContext(t *testing.T) {
	_, stderr, err := imageDigest(t, digestRepo(t), "nope")
	if err == nil || !strings.Contains(stderr, "nope") {
		t.Errorf("err %v, stderr %q; want a failure naming the context", err, stderr)
	}
}

func TestImageDigestFailsWithNoTrackedFiles(t *testing.T) {
	dir := t.TempDir()
	git(t, dir, "init")
	tree(t, dir, map[string]string{
		"svc/.dockerignore": "**\n",
		"svc/main.go":       "package main\n",
	})
	git(t, dir, "add", "-A")
	_, stderr, err := imageDigest(t, dir, "svc")
	if err == nil || !strings.Contains(stderr, "no tracked files") {
		t.Errorf("err %v, stderr %q; want a failure naming no tracked files", err, stderr)
	}
}

// git ls-files errors are caught and reported, not swallowed. A context
// directory name that is itself a pathspec magic (e.g. :(bogus)x) causes
// git to reject the pathspec and exit non-zero. The script must catch
// this and report it instead of proceeding with empty output.
func TestImageDigestCatchesGitLSFilesErrors(t *testing.T) {
	dir := digestRepo(t)
	// Create a subdirectory with a pathspec-like name that git rejects.
	// When passed as the context, git ls-files sees it as an invalid
	// pathspec magic and fails with "Unimplemented pathspec magic 'bogus'".
	tree(t, dir, map[string]string{":(bogus)x/tracked.txt": "content\n"})
	git(t, dir, "add", "-A")

	stdout, stderr, err := imageDigest(t, dir, ":(bogus)x")
	if err == nil {
		t.Fatalf("err <nil>, stderr %q; want non-zero exit on invalid pathspec", stderr)
	}
	if stdout != "" {
		t.Errorf("stdout %q; want empty (no digest on git failure)", stdout)
	}
	if !strings.Contains(stderr, "ls-files failed") {
		t.Errorf("stderr %q; want message naming ls-files failure", stderr)
	}
}
