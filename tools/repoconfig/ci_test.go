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

// The affected set, the title lint, the DCO, the image job and the fastlane
// check all feed the one required check.
func TestCIOKAggregatesEveryJob(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if got := strs(t, Dig(ci, "jobs", "ci-ok", "needs")); !reflect.DeepEqual(got, []string{"affected", "check", "pr-title", "dco", "images", "fastlane"}) {
		t.Errorf("ci-ok needs %v, want [affected check pr-title dco images fastlane]", got)
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
	if got := strs(t, Dig(ci, "jobs", "images", "needs")); !reflect.DeepEqual(got, []string{"affected", "check"}) {
		t.Errorf("images needs %v, want [affected check]", got)
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
	ci := mustYAML(t, ".github/workflows/ci.yml")
	if got := Dig(ci, "jobs", "deploy", "permissions"); !reflect.DeepEqual(got, map[string]any{"contents": "read", "packages": "write"}) {
		t.Errorf("ci.yml deploy permissions %v, want contents read and packages write", got)
	}
	files, _ := filepath.Glob(filepath.Join(Root(), ".github", "workflows", "*.yml"))
	for _, f := range files {
		rel, _ := filepath.Rel(Root(), f)
		wf := mustYAML(t, rel)
		if Dig(wf, "permissions", "packages") == "write" {
			t.Errorf("%s grants packages: write to every job", rel)
		}
		jobs, _ := Dig(wf, "jobs").(map[string]any)
		for name, job := range jobs {
			// The images job publishes; the deploy job, and ci.yml's job
			// that calls it, move the tag naming what an environment runs.
			writer := (rel == ".github/workflows/ci.yml" && (name == "images" || name == "deploy")) ||
				(rel == ".github/workflows/deploy.yml" && name == "deploy")
			if Dig(job, "permissions", "packages") == "write" && !writer {
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

// runSteps returns a job's steps that carry a run script.
func runSteps(t *testing.T, job any) []map[string]any {
	t.Helper()
	steps, _ := Dig(job, "steps").([]any)
	var out []map[string]any
	for _, s := range steps {
		if _, ok := Dig(s, "run").(string); ok {
			out = append(out, s.(map[string]any))
		}
	}
	return out
}

// A pull request is checked for what it changes since it left its base;
// every other event checks everything. The commit SHAs reach the script
// through the environment, never spliced into the script text.
func TestAffectedJobFeedsTheOthers(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	job := Dig(ci, "jobs", "affected")
	if job == nil {
		t.Fatal("ci.yml has no affected job")
	}
	checkout := stepUsing(t, job, "actions/checkout@")
	if got := Dig(checkout, "with", "fetch-depth"); got != 0 {
		t.Errorf("affected checkout fetch-depth = %v, want 0 (the merge base needs history)", got)
	}
	runs := runSteps(t, job)
	if len(runs) != 1 {
		t.Fatalf("affected has %d run steps, want 1", len(runs))
	}
	step := runs[0]
	run := step["run"].(string)
	for _, want := range []string{`pull_request`, `scripts/affected.sh --all`, `scripts/affected.sh "$BASE" "$HEAD"`, `"$GITHUB_OUTPUT"`} {
		if !strings.Contains(run, want) {
			t.Errorf("affected run lacks %s:\n%s", want, run)
		}
	}
	if strings.Contains(run, "${{") {
		t.Errorf("affected run interpolates an expression; pass it through env:\n%s", run)
	}
	if got := Dig(step, "env", "BASE"); got != "${{ github.event.pull_request.base.sha }}" {
		t.Errorf("affected env.BASE = %v", got)
	}
	if got := Dig(step, "env", "HEAD"); got != "${{ github.event.pull_request.head.sha }}" {
		t.Errorf("affected env.HEAD = %v", got)
	}
	id, _ := step["id"].(string)
	if id == "" {
		t.Fatal("affected run step has no id")
	}
	outputs, _ := Dig(job, "outputs").(map[string]any)
	keys := make([]string, 0, len(outputs))
	for _, k := range []string{"go", "dart", "ruby", "images", "full"} {
		if want := "${{ steps." + id + ".outputs." + k + " }}"; outputs[k] != want {
			t.Errorf("affected outputs.%s = %v, want %s", k, outputs[k], want)
		}
	}
	for k := range outputs {
		keys = append(keys, k)
	}
	if len(keys) != 5 {
		t.Errorf("affected outputs %v, want exactly go dart ruby images full", keys)
	}
	for _, name := range []string{"check", "images", "fastlane", "ci-ok"} {
		needs := strs(t, Dig(ci, "jobs", name, "needs"))
		found := false
		for _, n := range needs {
			found = found || n == "affected"
		}
		if !found {
			t.Errorf("%s needs %v, want it to include affected", name, needs)
		}
	}
}

// A push to an environment branch runs the whole gate; a pull request runs
// the same targets over the modules it touches.
func TestPushesRunTheWholeGate(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	var step map[string]any
	for _, s := range runSteps(t, Dig(ci, "jobs", "check")) {
		if strings.Contains(s["run"].(string), "make") {
			step = s
		}
	}
	if step == nil {
		t.Fatal("check has no make step")
	}
	run := step["run"].(string)
	for _, want := range []string{"pull_request", "make check", "go-fmt go-vet go-test go-build", "dart-fmt dart-analyze dart-test", "ruby-test", `GO_MODULES="$GO"`, `DART_PACKAGES="$DART"`} {
		if !strings.Contains(run, want) {
			t.Errorf("check run lacks %s:\n%s", want, run)
		}
	}
	if strings.Contains(run, "${{") {
		t.Errorf("check run interpolates an expression; pass it through env:\n%s", run)
	}
	for k, want := range map[string]string{
		"GO":   "${{ needs.affected.outputs.go }}",
		"DART": "${{ needs.affected.outputs.dart }}",
		"RUBY": "${{ needs.affected.outputs.ruby }}",
	} {
		if got := Dig(step, "env", k); got != want {
			t.Errorf("check env.%s = %v, want %s", k, got, want)
		}
	}
}

// Flutter is only installed when there is Dart to check.
func TestFlutterSetupOnlyWhenADartPackageIsAffected(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	step := stepUsing(t, Dig(ci, "jobs", "check"), "subosito/flutter-action@")
	if got := Dig(step, "if"); got != "needs.affected.outputs.dart != ''" {
		t.Errorf("check flutter setup if = %v, want needs.affected.outputs.dart != ''", got)
	}
}

// A component whose image the change does not touch skips every step.
func TestImagesRunOnlyForAffectedComponents(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	job := Dig(ci, "jobs", "images")
	if got := Dig(job, "env", "RUN"); got != "${{ contains(needs.affected.outputs.images, matrix.component) }}" {
		t.Errorf("images env.RUN = %v", got)
	}
	steps, _ := Dig(job, "steps").([]any)
	if len(steps) < 2 {
		t.Fatalf("images has %d steps", len(steps))
	}
	if uses, _ := Dig(steps[0], "uses").(string); !strings.HasPrefix(uses, "actions/checkout@") {
		t.Fatalf("images first step %q, want checkout", uses)
	}
	for i, s := range steps[1:] {
		cond, _ := Dig(s, "if").(string)
		if !strings.Contains(cond, "env.RUN == 'true'") {
			t.Errorf("images step %d (%v) runs without env.RUN == 'true' (if: %q)", i+1, Dig(s, "name"), cond)
		}
	}
}

// The store lanes are checked when their Ruby changes, and always on the
// app release pull request, whose release notes they verify.
func TestFastlaneRunsWhenRubyIsAffectedOrOnTheAppReleasePR(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	want := "${{ needs.affected.outputs.ruby == 'true' || startsWith(github.head_ref, 'release-please--branches--prd--components--app') }}"
	if got := Dig(ci, "jobs", "fastlane", "if"); got != want {
		t.Errorf("fastlane if = %v, want %s", got, want)
	}
}
