package repoconfig

import (
	"reflect"
	"strings"
	"testing"
)

func storeWF(t *testing.T) map[string]any { return mustYAML(t, ".github/workflows/store.yml") }

func TestStoreRunsOnlyWhenCalledOrDispatchedWithATag(t *testing.T) {
	on, _ := Dig(storeWF(t), "on").(map[string]any)
	if len(on) != 2 || on["workflow_call"] == nil || on["workflow_dispatch"] == nil {
		t.Fatalf("on = %v, want only workflow_call and workflow_dispatch", on)
	}
	for _, ev := range []string{"workflow_call", "workflow_dispatch"} {
		if Dig(on, ev, "inputs", "tag", "required") != true {
			t.Errorf("%s lacks a required tag input", ev)
		}
	}
}

func TestStoreJobsUseTheirEnvironments(t *testing.T) {
	jobs, _ := Dig(storeWF(t), "jobs").(map[string]any)
	want := map[string]string{"version": "store-beta", "android": "store-beta", "ios": "store-beta", "production": "store-production"}
	if len(jobs) != len(want) {
		t.Errorf("jobs = %d, want %d", len(jobs), len(want))
	}
	for name, env := range want {
		if got := Dig(jobs, name, "environment"); got != env {
			t.Errorf("job %s environment = %v, want %s", name, got, env)
		}
	}
	if got := strs(t, Dig(jobs, "production", "needs")); !reflect.DeepEqual(got, []string{"version", "android", "ios"}) {
		t.Errorf("production needs %v, want [version android ios]", got)
	}
	for _, name := range []string{"android", "ios"} {
		if got := strs(t, Dig(jobs, name, "needs")); !reflect.DeepEqual(got, []string{"version"}) {
			t.Errorf("%s needs %v, want [version]", name, got)
		}
	}
}

func TestStorePermissionsAreMinimal(t *testing.T) {
	wf := storeWF(t)
	if top, ok := Dig(wf, "permissions").(map[string]any); !ok || len(top) != 0 {
		t.Errorf("top-level permissions = %v, want {}", Dig(wf, "permissions"))
	}
	want := map[string]any{"contents": "read", "id-token": "write"}
	jobs, _ := Dig(wf, "jobs").(map[string]any)
	for name := range jobs {
		if got := Dig(jobs, name, "permissions"); !reflect.DeepEqual(got, want) {
			t.Errorf("job %s permissions = %v, want %v", name, got, want)
		}
	}
	if Dig(wf, "concurrency", "cancel-in-progress") != false {
		t.Error("a store run must never be cancelled by another")
	}
}

// The guard runs first and refuses a non-app tag or a run off prd.
func TestStoreGuardsTheTagAndTheBranchFirst(t *testing.T) {
	steps, _ := Dig(storeWF(t), "jobs", "version", "steps").([]any)
	if len(steps) == 0 {
		t.Fatal("version has no steps")
	}
	g := steps[0]
	run, _ := Dig(g, "run").(string)
	for _, want := range []string{`"$TAG"`, "app-v", "refs/heads/prd", "exit 1"} {
		if !strings.Contains(run, want) {
			t.Errorf("guard script lacks %q:\n%s", want, run)
		}
	}
	if Dig(g, "env", "TAG") != "${{ inputs.tag }}" || Dig(g, "env", "REF") != "${{ github.ref }}" {
		t.Errorf("guard env = %v", Dig(g, "env"))
	}
}

func TestStoreNeverInterpolatesIntoScripts(t *testing.T) {
	jobs, _ := Dig(storeWF(t), "jobs").(map[string]any)
	for name, job := range jobs {
		steps, _ := Dig(job, "steps").([]any)
		for _, s := range steps {
			if run, ok := Dig(s, "run").(string); ok && strings.Contains(run, "${{") {
				t.Errorf("job %s step %v interpolates into its script", name, Dig(s, "name"))
			}
		}
	}
}

// Every job builds or acts on the tagged commit, not the tip of prd.
func TestStoreChecksOutTheTag(t *testing.T) {
	jobs, _ := Dig(storeWF(t), "jobs").(map[string]any)
	for name, job := range jobs {
		co := stepUsing(t, job, "actions/checkout@")
		if Dig(co, "with", "ref") != "${{ inputs.tag }}" {
			t.Errorf("job %s checks out %v, want the tag", name, Dig(co, "with", "ref"))
		}
	}
}

// Credentials and resource names come only from vars and secrets.
func TestStoreTakesCredentialsFromVarsAndSecrets(t *testing.T) {
	jobs, _ := Dig(storeWF(t), "jobs").(map[string]any)
	for _, name := range []string{"version", "android", "production"} {
		auth := stepUsing(t, jobs[name], "google-github-actions/auth@")
		if Dig(auth, "with", "workload_identity_provider") != "${{ vars.PLAY_WIF_PROVIDER }}" || Dig(auth, "with", "service_account") != "${{ vars.PLAY_SERVICE_ACCOUNT }}" {
			t.Errorf("job %s auth with = %v", name, Dig(auth, "with"))
		}
	}
	want := map[string]string{
		"ASC_KEY_ID": "${{ vars.ASC_KEY_ID }}", "ASC_ISSUER_ID": "${{ vars.ASC_ISSUER_ID }}", "ASC_KEY_P8": "${{ secrets.ASC_KEY_P8 }}",
	}
	for _, name := range []string{"version", "ios", "production"} {
		env := laneEnv(t, jobs[name])
		for k, v := range want {
			if env[k] != v {
				t.Errorf("job %s env %s = %v, want %s", name, k, env[k], v)
			}
		}
	}
	ios := laneEnv(t, jobs["ios"])
	for k, v := range map[string]string{"MATCH_GIT_URL": "${{ vars.MATCH_GIT_URL }}", "MATCH_PASSWORD": "${{ secrets.MATCH_PASSWORD }}", "MATCH_GIT_PRIVATE_KEY": "${{ secrets.MATCH_GIT_PRIVATE_KEY }}"} {
		if ios[k] != v {
			t.Errorf("ios env %s = %v, want %s", k, ios[k], v)
		}
	}
	if laneEnv(t, jobs["android"])["PLAY_RELEASE_STATUS"] != "${{ vars.PLAY_RELEASE_STATUS }}" {
		t.Error("android lane must take PLAY_RELEASE_STATUS from vars")
	}
}

// laneEnv returns the env of the step that runs a fastlane lane.
func laneEnv(t *testing.T, job any) map[string]any {
	t.Helper()
	steps, _ := Dig(job, "steps").([]any)
	for _, s := range steps {
		if run, _ := Dig(s, "run").(string); strings.Contains(run, "bundle exec fastlane ") {
			env, _ := Dig(s, "env").(map[string]any)
			return env
		}
	}
	t.Fatal("no step runs a fastlane lane")
	return nil
}

func TestStoreRunsTheLanesWithTheBuildNumber(t *testing.T) {
	jobs, _ := Dig(storeWF(t), "jobs").(map[string]any)
	if got := Dig(jobs, "version", "outputs", "build_number"); got != "${{ steps.number.outputs.number }}" {
		t.Errorf("version outputs.build_number = %v", got)
	}
	want := map[string][]string{
		"version":    {"bundle exec fastlane build_number"},
		"android":    {`bundle exec fastlane android_internal "build_number:$BUILD_NUMBER"`},
		"ios":        {`bundle exec fastlane ios_testflight "build_number:$BUILD_NUMBER"`},
		"production": {`bundle exec fastlane android_promote "build_number:$BUILD_NUMBER"`, `bundle exec fastlane ios_submit "build_number:$BUILD_NUMBER"`},
	}
	for name, lanes := range want {
		steps, _ := Dig(jobs, name, "steps").([]any)
		var all string
		for _, s := range steps {
			r, _ := Dig(s, "run").(string)
			all += r + "\n"
			if strings.Contains(r, "$BUILD_NUMBER") && Dig(s, "env", "BUILD_NUMBER") != "${{ needs.version.outputs.build_number }}" {
				t.Errorf("job %s: BUILD_NUMBER must come from needs.version", name)
			}
		}
		for _, l := range lanes {
			if !strings.Contains(all, l) {
				t.Errorf("job %s does not run %q", name, l)
			}
		}
	}
}

// The decoded upload key never outlives the job.
func TestStoreDeletesTheUploadKey(t *testing.T) {
	steps, _ := Dig(storeWF(t), "jobs", "android", "steps").([]any)
	var wrote, removed bool
	for _, s := range steps {
		run, _ := Dig(s, "run").(string)
		if strings.Contains(run, "base64") && strings.Contains(run, "ANDROID_UPLOAD_KEYSTORE_B64") {
			wrote = true
			if Dig(s, "env", "ANDROID_UPLOAD_KEYSTORE_B64") != "${{ secrets.ANDROID_UPLOAD_KEYSTORE_B64 }}" {
				t.Error("keystore must come from secrets.ANDROID_UPLOAD_KEYSTORE_B64")
			}
		}
		if strings.Contains(run, "rm -f") && strings.Contains(run, "upload.jks") {
			removed = Dig(s, "if") == "always()"
		}
	}
	if !wrote || !removed {
		t.Errorf("android must write the keystore from the secret and remove it with if: always() (wrote %v, removed %v)", wrote, removed)
	}
}
