package repoconfig

import (
	"reflect"
	"regexp"
	"strings"
	"testing"
)

const botToken = "${{ steps.app-token.outputs.token || github.token }}"

var sha40 = regexp.MustCompile(`^[0-9a-f]{40}$`)

// One component per package, tags carry it.
func TestReleasePleaseHasAnAppAndABackendComponent(t *testing.T) {
	cfg := mustJSON(t, "release-please-config.json")
	if cfg["include-component-in-tag"] != true {
		t.Error("include-component-in-tag must be true")
	}
	if cfg["separate-pull-requests"] != true {
		t.Error("separate-pull-requests must be true")
	}
	if s, _ := cfg["bootstrap-sha"].(string); !sha40.MatchString(s) {
		t.Errorf("bootstrap-sha = %q, want a full commit SHA", s)
	}
	pkgs, _ := cfg["packages"].(map[string]any)
	want := map[string][2]string{"app": {"dart", "app"}, "backend": {"go", "backend"}}
	if len(pkgs) != len(want) {
		t.Fatalf("packages = %v, want exactly app and backend", pkgs)
	}
	for path, w := range want {
		if got := Dig(pkgs, path, "release-type"); got != w[0] {
			t.Errorf("%s release-type = %v, want %s", path, got, w[0])
		}
		if got := Dig(pkgs, path, "component"); got != w[1] {
			t.Errorf("%s component = %v, want %s", path, got, w[1])
		}
	}
	// Every release PR bumps a version here, so only the shape is pinned.
	man := mustJSON(t, ".release-please-manifest.json")
	if len(man) != len(want) {
		t.Fatalf("manifest = %v, want exactly app and backend", man)
	}
	for path := range want {
		if v, _ := man[path].(string); !semver.MatchString(v) {
			t.Errorf("manifest %s = %v, want a version such as 0.1.0", path, man[path])
		}
	}
}

var semver = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)

func TestReleaseWorkflowRunsOnPushesToPrdOnly(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	on, _ := Dig(wf, "on").(map[string]any)
	if len(on) != 1 || on["push"] == nil {
		t.Fatalf("on = %v, want only push", on)
	}
	if got := strs(t, Dig(on, "push", "branches")); !reflect.DeepEqual(got, []string{"prd"}) {
		t.Errorf("push branches = %v, want [prd]", got)
	}
}

func TestReleaseJobsAskOnlyForContentsAndPullRequests(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	if top, ok := Dig(wf, "permissions").(map[string]any); !ok || len(top) != 0 {
		t.Errorf("top-level permissions = %v, want {}", Dig(wf, "permissions"))
	}
	jobs, _ := Dig(wf, "jobs").(map[string]any)
	want := map[string]any{"contents": "write", "pull-requests": "write"}
	for _, name := range []string{"release", "back-merge"} {
		if _, ok := jobs[name]; !ok {
			t.Errorf("job %s missing", name)
			continue
		}
		if got := Dig(jobs, name, "permissions"); !reflect.DeepEqual(got, want) {
			t.Errorf("job %s permissions = %v, want %v", name, got, want)
		}
	}
	if len(jobs) != 3 {
		t.Errorf("jobs = %d, want release, back-merge and store", len(jobs))
	}
}

func stepUsing(t *testing.T, job any, prefix string) map[string]any {
	t.Helper()
	steps, _ := Dig(job, "steps").([]any)
	for _, s := range steps {
		if uses, _ := Dig(s, "uses").(string); strings.HasPrefix(uses, prefix) {
			return s.(map[string]any)
		}
	}
	t.Fatalf("no step uses %s", prefix)
	return nil
}

func TestReleaseJobRunsReleasePleaseOnPrd(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	job := Dig(wf, "jobs", "release")
	step := stepUsing(t, job, "googleapis/release-please-action@")
	if step["id"] != "release" {
		t.Errorf("release-please step id = %v, want release", step["id"])
	}
	wantWith := map[string]any{
		"config-file":   "release-please-config.json",
		"manifest-file": ".release-please-manifest.json",
		"target-branch": "prd",
		"token":         botToken,
	}
	if got := Dig(step, "with"); !reflect.DeepEqual(got, wantWith) {
		t.Errorf("release-please with = %v, want %v", got, wantWith)
	}
	if got := Dig(job, "outputs", "releases_created"); got != "${{ steps.release.outputs.releases_created }}" {
		t.Errorf("release outputs.releases_created = %v", got)
	}
	if got := Dig(job, "outputs", "app_release_created"); got != "${{ steps.release.outputs['app--release_created'] }}" {
		t.Errorf("release outputs.app_release_created = %v", got)
	}
	if got := Dig(job, "outputs", "app_tag"); got != "${{ steps.release.outputs['app--tag_name'] }}" {
		t.Errorf("release outputs.app_tag = %v", got)
	}
}

// The back-merge runs in the same workflow, on every prd push.
func TestBackMergeRunsOnEveryPrdPush(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	job := Dig(wf, "jobs", "back-merge")
	if got := strs(t, Dig(job, "needs")); !reflect.DeepEqual(got, []string{"release"}) {
		t.Errorf("back-merge needs %v, want [release]", got)
	}
	if got := Dig(job, "if"); got != nil {
		t.Errorf("back-merge must run on every prd push, but has if = %v", got)
	}
	checkout := stepUsing(t, job, "actions/checkout@")
	if got := Dig(checkout, "with", "fetch-depth"); got != 0 {
		t.Errorf("checkout fetch-depth = %v, want 0", got)
	}
	steps, _ := Dig(job, "steps").([]any)
	var run map[string]any
	for _, s := range steps {
		if r, _ := Dig(s, "run").(string); strings.Contains(r, "sh scripts/back-merge.sh") {
			run = s.(map[string]any)
		}
	}
	if run == nil {
		t.Fatal("no step runs sh scripts/back-merge.sh")
	}
	if got := Dig(run, "env", "GH_TOKEN"); got != botToken {
		t.Errorf("back-merge GH_TOKEN = %v, want %s", got, botToken)
	}
}

// release-please commits as the token's identity, so the
// token must come from a GitHub App (<app>[bot], exempt from the dco check),
// never from a personal access token.
func TestReleaseJobsMintTheTokenFromAGitHubApp(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	for _, name := range []string{"release", "back-merge"} {
		job := Dig(wf, "jobs", name)
		steps, _ := Dig(job, "steps").([]any)
		if len(steps) == 0 {
			t.Fatalf("job %s has no steps", name)
		}
		if first, _ := Dig(steps[0], "uses").(string); !strings.HasPrefix(first, "actions/create-github-app-token@") {
			t.Errorf("job %s: the app token step must come first, got %q", name, first)
		}
		step := stepUsing(t, job, "actions/create-github-app-token@")
		uses, _ := step["uses"].(string)
		if !sha40.MatchString(strings.TrimPrefix(uses, "actions/create-github-app-token@")) {
			t.Errorf("job %s: app token action %q is not pinned by a 40-char SHA", name, uses)
		}
		if step["id"] != "app-token" {
			t.Errorf("job %s: id = %v, want app-token", name, step["id"])
		}
		if step["if"] != "vars.RELEASE_APP_CLIENT_ID != ''" {
			t.Errorf("job %s: if = %v", name, step["if"])
		}
		want := map[string]any{
			"client-id":   "${{ vars.RELEASE_APP_CLIENT_ID }}",
			"private-key": "${{ secrets.RELEASE_APP_PRIVATE_KEY }}",
		}
		if got := Dig(step, "with"); !reflect.DeepEqual(got, want) {
			t.Errorf("job %s: with = %v, want %v", name, got, want)
		}
	}
}

// A new app version goes to the stores with the tag release-please just
// made; calling the workflow does not depend on which token made the tag.
func TestReleaseCallsStoreForANewAppVersion(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	job := Dig(wf, "jobs", "store")
	if got := strs(t, Dig(job, "needs")); !reflect.DeepEqual(got, []string{"release"}) {
		t.Errorf("store needs %v, want [release]", got)
	}
	if got := Dig(job, "if"); got != "${{ needs.release.outputs.app_release_created == 'true' }}" {
		t.Errorf("store if = %v", got)
	}
	if got := Dig(job, "uses"); got != "./.github/workflows/store.yml" {
		t.Errorf("store uses %v", got)
	}
	if got := Dig(job, "with", "tag"); got != "${{ needs.release.outputs.app_tag }}" {
		t.Errorf("store with.tag = %v", got)
	}
	// The store secrets live in environments, and a called workflow's jobs
	// receive environment secrets only when the caller inherits secrets.
	if Dig(job, "secrets") != "inherit" {
		t.Errorf("store secrets = %v, want inherit", Dig(job, "secrets"))
	}
	if got := Dig(job, "permissions"); !reflect.DeepEqual(got, map[string]any{"contents": "read", "id-token": "write"}) {
		t.Errorf("store permissions = %v", got)
	}
}

// Only the release and back-merge jobs queue behind each other: the store
// job may wait days for approval and must not hold back later prd pushes.
func TestReleaseConcurrencyCoversOnlyTheReleaseAndBackMergeJobs(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/release.yml")
	if got, ok := wf["concurrency"]; ok {
		t.Errorf("workflow-level concurrency = %v, want none", got)
	}
	want := map[string]any{"group": "release", "cancel-in-progress": false}
	for _, name := range []string{"release", "back-merge"} {
		if got := Dig(wf, "jobs", name, "concurrency"); !reflect.DeepEqual(got, want) {
			t.Errorf("job %s concurrency = %v, want %v", name, got, want)
		}
	}
	if got := Dig(wf, "jobs", "store", "concurrency"); got != nil {
		t.Errorf("store job concurrency = %v, want none", got)
	}
}
