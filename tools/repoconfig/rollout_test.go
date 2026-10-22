package repoconfig

import (
	"reflect"
	"strings"
	"testing"
)

func TestRolloutIsManualWithThreeSteps(t *testing.T) {
	wf := mustYAML(t, ".github/workflows/rollout.yml")
	on, _ := Dig(wf, "on").(map[string]any)
	if len(on) != 1 || on["workflow_dispatch"] == nil {
		t.Fatalf("on = %v, want only workflow_dispatch", on)
	}
	if got := strs(t, Dig(on, "workflow_dispatch", "inputs", "step", "options")); !reflect.DeepEqual(got, []string{"50", "100", "halt"}) {
		t.Errorf("step options %v, want [50 100 halt]", got)
	}
	if top, ok := Dig(wf, "permissions").(map[string]any); !ok || len(top) != 0 {
		t.Errorf("top-level permissions = %v, want {}", Dig(wf, "permissions"))
	}
	if got := Dig(wf, "concurrency", "group"); got != "store-rollout" {
		t.Errorf("concurrency group = %v, want store-rollout", got)
	}
	if got := Dig(wf, "concurrency", "cancel-in-progress"); got != false {
		t.Errorf("cancel-in-progress = %v, want false", got)
	}
	jobs, _ := Dig(wf, "jobs").(map[string]any)
	if len(jobs) != 1 {
		t.Fatalf("jobs = %d, want 1", len(jobs))
	}
	for name, job := range jobs {
		if Dig(job, "environment") != "store-production" {
			t.Errorf("job %s environment = %v, want store-production", name, Dig(job, "environment"))
		}
		if got := Dig(job, "permissions"); !reflect.DeepEqual(got, map[string]any{"contents": "read", "id-token": "write"}) {
			t.Errorf("job %s permissions = %v", name, got)
		}
		steps, _ := Dig(job, "steps").([]any)
		first, _ := Dig(steps[0], "run").(string)
		if !strings.Contains(first, "refs/heads/prd") || Dig(steps[0], "env", "REF") != "${{ github.ref }}" {
			t.Errorf("the first step must refuse a run off prd")
		}
		var lane map[string]any
		for _, s := range steps {
			if r, _ := Dig(s, "run").(string); strings.Contains(r, "${{") {
				t.Errorf("step %v interpolates into its script", Dig(s, "name"))
			} else if strings.Contains(r, `bundle exec fastlane android_rollout "step:$STEP"`) {
				lane = s.(map[string]any)
			}
		}
		if lane == nil || Dig(lane, "env", "STEP") != "${{ inputs.step }}" {
			t.Errorf("no step runs android_rollout with STEP from inputs.step")
		}
		auth := stepUsing(t, job, "google-github-actions/auth@")
		if Dig(auth, "with", "workload_identity_provider") != "${{ vars.PLAY_WIF_PROVIDER }}" {
			t.Errorf("auth with = %v", Dig(auth, "with"))
		}
	}
}
