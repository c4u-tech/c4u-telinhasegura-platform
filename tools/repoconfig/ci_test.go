package repoconfig

import (
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

func mustYAML(t *testing.T, rel string) map[string]any {
	t.Helper()
	m, err := LoadYAML(rel)
	if err != nil {
		t.Fatalf("load %s: %v", rel, err)
	}
	return m
}

func mustJSON(t *testing.T, rel string) map[string]any {
	t.Helper()
	m, err := LoadJSON(rel)
	if err != nil {
		t.Fatalf("load %s: %v", rel, err)
	}
	return m
}

// strs reads a YAML/JSON list of strings; a lone string is a list of one.
func strs(t *testing.T, v any) []string {
	t.Helper()
	switch x := v.(type) {
	case string:
		return []string{x}
	case []any:
		out := make([]string, 0, len(x))
		for _, e := range x {
			s, ok := e.(string)
			if !ok {
				t.Fatalf("list element %v is not a string", e)
			}
			out = append(out, s)
		}
		return out
	}
	t.Fatalf("%v is not a string list", v)
	return nil
}

func TestCIRunsOnEveryEnvironmentBranch(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	want := []string{"dev", "stg", "prd"}
	for _, event := range []string{"push", "pull_request"} {
		got := strs(t, Dig(ci, "on", event, "branches"))
		if !reflect.DeepEqual(got, want) {
			t.Errorf("on.%s.branches = %v, want %v", event, got, want)
		}
	}
}

// The title lint, the DCO, the image job and the fastlane check all feed the one required
// check.
func TestCIOKAggregatesEveryJob(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if got := strs(t, Dig(ci, "jobs", "ci-ok", "needs")); !reflect.DeepEqual(got, []string{"check", "pr-title", "dco", "images", "fastlane"}) {
		t.Errorf("ci-ok needs %v, want [check pr-title dco images fastlane]", got)
	}
	if got := Dig(ci, "jobs", "ci-ok", "if"); got != "always()" {
		t.Errorf("ci-ok if = %v, want always()", got)
	}
	steps, _ := Dig(ci, "jobs", "pr-title", "steps").([]any)
	if len(steps) == 0 {
		t.Fatal("pr-title has no steps")
	}
	uses, _ := Dig(steps[0], "uses").(string)
	if !strings.HasPrefix(uses, "amannn/action-semantic-pull-request@") {
		t.Errorf("pr-title uses %q, want the semantic PR title action", uses)
	}
}

var pinned = regexp.MustCompile(`^[^@\s]+@[0-9a-f]{40}$`)

// actionPinned reports whether a `uses:` value is acceptable: local
// actions and Docker images are not fetched from a tag, everything else
// must be pinned by commit SHA.
func actionPinned(uses string) bool {
	if strings.HasPrefix(uses, "./") || strings.HasPrefix(uses, "docker://") {
		return true
	}
	return pinned.MatchString(uses)
}

func TestActionPinnedCases(t *testing.T) {
	cases := map[string]bool{
		"actions/checkout@11d5960a326750d5838078e36cf38b85af677262": true,
		"actions/checkout@v4":           false,
		"actions/checkout@main":         false,
		"./.github/actions/setup":       true,
		"docker://alpine:3.20":          true,
		"actions/checkout@11d5960a3267": false,
	}
	for uses, want := range cases {
		if got := actionPinned(uses); got != want {
			t.Errorf("actionPinned(%q) = %v, want %v", uses, got, want)
		}
	}
}

// Every workflow, present and future.
func TestEveryActionIsPinnedBySHA(t *testing.T) {
	files, err := filepath.Glob(filepath.Join(Root(), ".github", "workflows", "*.yml"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no workflows found: %v", err)
	}
	for _, f := range files {
		rel, _ := filepath.Rel(Root(), f)
		wf := mustYAML(t, rel)
		jobs, _ := Dig(wf, "jobs").(map[string]any)
		for name, job := range jobs {
			steps, _ := Dig(job, "steps").([]any)
			for _, s := range steps {
				uses, ok := Dig(s, "uses").(string)
				if ok && !actionPinned(uses) {
					t.Errorf("%s job %s: %q is not pinned by commit SHA", rel, name, uses)
				}
			}
		}
	}
	if _, err := os.Stat(filepath.Join(Root(), ".github", "workflows", "ci.yml")); err != nil {
		t.Fatal(err)
	}
}

func TestImagesJobBuildsEveryComponent(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if _, ok := Dig(ci, "jobs", "image").(map[string]any); ok {
		t.Error("the old image job is still there; images replaces it")
	}
	got := strs(t, Dig(ci, "jobs", "images", "strategy", "matrix", "component"))
	if !reflect.DeepEqual(got, []string{"api", "web", "site", "backup"}) {
		t.Errorf("images matrix %v, want [api web site backup]", got)
	}
	if ff, _ := Dig(ci, "jobs", "images", "strategy", "fail-fast").(bool); ff {
		t.Error("images fail-fast is on; one component's failure must not hide another's")
	}
	if got := Dig(ci, "jobs", "images", "if"); got != "github.event_name == 'pull_request' || github.ref_name == 'stg' || github.ref_name == 'prd'" {
		t.Errorf("images if = %v", got)
	}
}

// No image of a red commit reaches GHCR, so images wait for check.
func TestImagesWaitForTheCheck(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if got := strs(t, Dig(ci, "jobs", "images", "needs")); !reflect.DeepEqual(got, []string{"check"}) {
		t.Errorf("images needs %v, want [check]", got)
	}
}

// Pushes only from stg and prd, after a reuse check.
func TestImagesPushOnlyFromEnvironmentBranches(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if got := Dig(ci, "jobs", "images", "env", "PUSH"); got != "${{ github.event_name == 'push' && (github.ref_name == 'stg' || github.ref_name == 'prd') }}" {
		t.Errorf("images env.PUSH = %v", got)
	}
	steps, _ := Dig(ci, "jobs", "images", "steps").([]any)
	var pushes, logins int
	for _, s := range steps {
		run, _ := Dig(s, "run").(string)
		uses, _ := Dig(s, "uses").(string)
		cond, _ := Dig(s, "if").(string)
		if strings.Contains(run, "publish-image.sh push") || strings.HasPrefix(uses, "docker/login-action@") {
			if !strings.Contains(cond, "env.PUSH == 'true'") {
				t.Errorf("step %v runs without env.PUSH == 'true' (if: %q)", Dig(s, "name"), cond)
			}
			if strings.Contains(run, "push") {
				pushes++
			} else {
				logins++
			}
		}
	}
	if pushes != 1 || logins != 1 {
		t.Errorf("%d push steps and %d logins, want one each", pushes, logins)
	}
}

// Only the job that pushes may write packages.
func TestOnlyTheImagesJobWritesPackages(t *testing.T) {
	files, _ := filepath.Glob(filepath.Join(Root(), ".github", "workflows", "*.yml"))
	for _, f := range files {
		rel, _ := filepath.Rel(Root(), f)
		wf := mustYAML(t, rel)
		if Dig(wf, "permissions", "packages") == "write" {
			t.Errorf("%s grants packages: write to every job", rel)
		}
		jobs, _ := Dig(wf, "jobs").(map[string]any)
		for name, job := range jobs {
			if Dig(job, "permissions", "packages") == "write" && (rel != ".github/workflows/ci.yml" || name != "images") {
				t.Errorf("%s job %s may write packages", rel, name)
			}
		}
	}
}

// A newer push never cancels a running deploy.
func TestCINeverCancelsAPush(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if got := Dig(ci, "concurrency", "cancel-in-progress"); got != "${{ github.event_name == 'pull_request' }}" {
		t.Errorf("ci concurrency cancel-in-progress = %v, want only for pull requests", got)
	}
}
