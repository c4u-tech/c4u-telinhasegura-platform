package repoconfig

import (
	"reflect"
	"strings"
	"testing"
)

func TestStoreMetadataIsManualFromPrdWithApproval(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/store-metadata.yml")
	on, _ := Dig(wf, "on").(map[string]any)
	if len(on) != 1 || on["workflow_dispatch"] == nil {
		t.Fatalf("on = %v, want only workflow_dispatch", on)
	}
	if top, ok := Dig(wf, "permissions").(map[string]any); !ok || len(top) != 0 {
		t.Errorf("top-level permissions = %v, want {}", Dig(wf, "permissions"))
	}
	// Google Play allows one edit at a time, so the texts queue behind a
	// store release, and neither cancels the other.
	release := mustYAML(t, ".github/workflows/store.yml")
	if got, want := Dig(wf, "concurrency", "group"), Dig(release, "concurrency", "group"); got == nil || got != want {
		t.Errorf("concurrency group = %v, want the store release's %v", got, want)
	}
	if Dig(wf, "concurrency", "cancel-in-progress") != false {
		t.Error("a store texts run must never be cancelled by another")
	}
	jobs, _ := Dig(wf, "jobs").(map[string]any)
	if len(jobs) != 1 {
		t.Fatalf("jobs = %d, want 1", len(jobs))
	}
	for name, job := range jobs {
		if Dig(job, "environment") != "store-production" {
			t.Errorf("%s environment = %v", name, Dig(job, "environment"))
		}
		if got := Dig(job, "permissions"); !reflect.DeepEqual(got, map[string]any{"contents": "read", "id-token": "write"}) {
			t.Errorf("%s permissions = %v", name, got)
		}
		steps, _ := Dig(job, "steps").([]any)
		first, _ := Dig(steps[0], "run").(string)
		if !strings.Contains(first, "refs/heads/prd") || Dig(steps[0], "env", "REF") != "${{ github.ref }}" {
			t.Error("the first step must refuse a run off prd")
		}
		ran := false
		for _, s := range steps {
			r, _ := Dig(s, "run").(string)
			if strings.Contains(r, "${{") {
				t.Errorf("step %v interpolates into its script", Dig(s, "name"))
			}
			if strings.Contains(r, "bundle exec fastlane metadata") {
				ran = true
				for k, v := range map[string]string{"ASC_KEY_ID": "${{ vars.ASC_KEY_ID }}", "ASC_ISSUER_ID": "${{ vars.ASC_ISSUER_ID }}", "ASC_KEY_P8": "${{ secrets.ASC_KEY_P8 }}"} {
					if Dig(s, "env", k) != v {
						t.Errorf("metadata step env %s = %v, want %s", k, Dig(s, "env", k), v)
					}
				}
			}
		}
		if !ran {
			t.Error("no step runs the metadata lane")
		}
		auth := stepUsing(t, job, "google-github-actions/auth@")
		if Dig(auth, "with", "workload_identity_provider") != "${{ vars.PLAY_WIF_PROVIDER }}" || Dig(auth, "with", "service_account") != "${{ vars.PLAY_SERVICE_ACCOUNT }}" {
			t.Errorf("auth with = %v", Dig(auth, "with"))
		}
	}
}
