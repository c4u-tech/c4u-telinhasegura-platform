package repoconfig

import (
	"reflect"
	"strings"
	"testing"
)

func TestDeployFollowsCIOKOnEnvironmentPushes(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	job := Dig(ci, "jobs", "deploy")
	if got := strs(t, Dig(job, "needs")); !reflect.DeepEqual(got, []string{"ci-ok"}) {
		t.Errorf("deploy needs %v, want [ci-ok]", got)
	}
	if got := Dig(job, "if"); got != "${{ !cancelled() && needs.ci-ok.result == 'success' && github.event_name == 'push' && (github.ref_name == 'stg' || github.ref_name == 'prd') }}" {
		t.Errorf("deploy if = %v", got)
	}
	if got := Dig(job, "uses"); got != "./.github/workflows/deploy.yml" {
		t.Errorf("deploy uses %v", got)
	}
	if Dig(job, "with", "environment") != "${{ github.ref_name }}" || Dig(job, "with", "ref") != "${{ github.sha }}" {
		t.Errorf("deploy with = %v", Dig(job, "with"))
	}
	// Staging never auto-deploys the backup app.
	if got := Dig(job, "with", "components"); got != "${{ github.ref_name == 'prd' && 'api web site backup' || 'api web site' }}" {
		t.Errorf("deploy with.components = %v", got)
	}
	if Dig(job, "secrets") != "inherit" {
		t.Errorf("deploy secrets = %v, want inherit", Dig(job, "secrets"))
	}
}

// Callable after CI and by hand.
func TestDeployWorkflowIsCallableAndManual(t *testing.T) {
	d := mustYAML(t, ".github/workflows/deploy.yml")
	for _, event := range []string{"workflow_call", "workflow_dispatch"} {
		for _, input := range []string{"environment", "ref", "components"} {
			if Dig(d, "on", event, "inputs", input) == nil {
				t.Errorf("on.%s lacks input %s", event, input)
			}
		}
	}
	if got := strs(t, Dig(d, "on", "workflow_dispatch", "inputs", "environment", "options")); !reflect.DeepEqual(got, []string{"stg", "prd"}) {
		t.Errorf("manual environments %v, want [stg prd]", got)
	}
}

func TestDeployNeverOverlapsNorCancels(t *testing.T) {
	d := mustYAML(t, ".github/workflows/deploy.yml")
	if got := Dig(d, "jobs", "deploy", "concurrency", "group"); got != "deploy-${{ inputs.environment }}" {
		t.Errorf("concurrency group %v", got)
	}
	if got := Dig(d, "jobs", "deploy", "concurrency", "cancel-in-progress"); got != false {
		t.Errorf("cancel-in-progress %v, want false", got)
	}
}

func TestDeployIsGatedPerEnvironment(t *testing.T) {
	d := mustYAML(t, ".github/workflows/deploy.yml")
	want := "${{ (inputs.environment == 'stg' && vars.DEPLOY_STG == 'true') || (inputs.environment == 'prd' && vars.DEPLOY_PRD == 'true') }}"
	if got := Dig(d, "jobs", "deploy", "env", "ENABLED"); got != want {
		t.Errorf("env.ENABLED = %v", got)
	}
	steps, _ := Dig(d, "jobs", "deploy", "steps").([]any)
	for i, s := range steps {
		cond, _ := Dig(s, "if").(string)
		if i == 0 {
			if !strings.Contains(cond, "env.ENABLED != 'true'") || !strings.Contains(Dig(s, "run").(string), "GITHUB_STEP_SUMMARY") {
				t.Errorf("the first step must write the notice when off; if %q", cond)
			}
			continue
		}
		if !strings.Contains(cond, "env.ENABLED == 'true'") {
			t.Errorf("step %d (%v) runs while the environment is off", i, Dig(s, "name"))
		}
	}
}

func TestDeployDeploysEachAppInOrderWithItsOwnToken(t *testing.T) {
	d := mustYAML(t, ".github/workflows/deploy.yml")
	steps, _ := Dig(d, "jobs", "deploy", "steps").([]any)
	var apps []string
	for _, s := range steps {
		uses, _ := Dig(s, "uses").(string)
		if !strings.HasPrefix(uses, "caprover/deploy-from-github@") {
			continue
		}
		app, _ := Dig(s, "with", "app").(string)
		apps = append(apps, app)
		c := strings.TrimSuffix(strings.TrimPrefix(app, "telinhasegura-"), "-${{ inputs.environment }}")
		C := strings.ToUpper(c)
		wantToken := "${{ inputs.environment == 'prd' && secrets.PRD_CAPROVER_" + C + "_TOKEN || secrets.STG_CAPROVER_" + C + "_TOKEN }}"
		if got := Dig(s, "with", "token"); got != wantToken {
			t.Errorf("%s token %v, want %s", app, got, wantToken)
		}
		if got := Dig(s, "with", "image"); got != "${{ steps.images.outputs."+c+" }}" {
			t.Errorf("%s image %v", app, got)
		}
		if got := Dig(s, "with", "server"); got != "${{ secrets.CAPROVER_URL }}" {
			t.Errorf("%s server %v", app, got)
		}
	}
	want := []string{"telinhasegura-api-${{ inputs.environment }}", "telinhasegura-web-${{ inputs.environment }}", "telinhasegura-site-${{ inputs.environment }}", "telinhasegura-backup-${{ inputs.environment }}"}
	if !reflect.DeepEqual(apps, want) {
		t.Errorf("deploy order %v, want %v", apps, want)
	}
}

// No script injection: inputs reach scripts only through env.
func TestDeployRunStepsNeverInterpolateInputs(t *testing.T) {
	d := mustYAML(t, ".github/workflows/deploy.yml")
	if got := Dig(d, "jobs", "deploy", "permissions"); !reflect.DeepEqual(got, map[string]any{"contents": "read", "packages": "read"}) {
		t.Errorf("deploy permissions %v, want contents and packages read", got)
	}
	steps, _ := Dig(d, "jobs", "deploy", "steps").([]any)
	for _, s := range steps {
		if run, ok := Dig(s, "run").(string); ok && strings.Contains(run, "${{") {
			t.Errorf("step %v interpolates an expression into its script: %q", Dig(s, "name"), run)
		}
	}
}

// A missing token must fail by name before any deploy: the per-app token
// expression falls back to the other environment's token when empty.
func TestDeployGuardsMissingSecretsBeforeCapRover(t *testing.T) {
	d := mustYAML(t, ".github/workflows/deploy.yml")
	steps, _ := Dig(d, "jobs", "deploy", "steps").([]any)
	guard, first := -1, -1
	for i, s := range steps {
		if uses, _ := Dig(s, "uses").(string); first < 0 && strings.HasPrefix(uses, "caprover/deploy-from-github@") {
			first = i
		}
		if run, _ := Dig(s, "run").(string); guard < 0 && strings.Contains(run, "CAPROVER_URL") {
			guard = i
			if cond, _ := Dig(s, "if").(string); !strings.Contains(cond, "env.ENABLED == 'true'") {
				t.Errorf("guard step runs while the environment is off")
			}
			env, _ := Dig(s, "env").(map[string]any)
			for _, name := range []string{"CAPROVER_URL", "PRD_CAPROVER_API_TOKEN", "STG_CAPROVER_API_TOKEN", "PRD_CAPROVER_WEB_TOKEN", "STG_CAPROVER_WEB_TOKEN", "PRD_CAPROVER_SITE_TOKEN", "STG_CAPROVER_SITE_TOKEN", "PRD_CAPROVER_BACKUP_TOKEN", "STG_CAPROVER_BACKUP_TOKEN"} {
				if got := env[name]; got != "${{ secrets."+name+" }}" {
					t.Errorf("guard env %s = %v", name, got)
				}
			}
		}
	}
	if guard < 0 || first < 0 || guard > first {
		t.Errorf("guard step at %d, first caprover step at %d; the guard must come first", guard, first)
	}
}
