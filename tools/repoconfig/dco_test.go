package repoconfig

import (
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// The DCO runs on PRs only, reads only, sees full
// history, and checks what is new to all three environment branches.
func TestDCOJobChecksNewCommitsOnPullRequests(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	job := Dig(ci, "jobs", "dco")
	if job == nil {
		t.Fatal("ci.yml has no dco job")
	}
	if got := Dig(job, "if"); got != "github.event_name == 'pull_request'" {
		t.Errorf("dco if = %v, want pull requests only", got)
	}
	if got := Dig(job, "permissions"); !reflect.DeepEqual(got, map[string]any{"contents": "read"}) {
		t.Errorf("dco permissions = %v, want only contents: read", got)
	}
	co := stepUsing(t, job, "actions/checkout@")
	if got := Dig(co, "with", "fetch-depth"); got != 0 {
		t.Errorf("checkout fetch-depth = %v, want 0 (full history and branches)", got)
	}
	stepUsing(t, job, "actions/setup-go@")
	var run string
	steps, _ := Dig(job, "steps").([]any)
	for _, s := range steps {
		if wd, ok := Dig(s, "working-directory").(string); ok {
			run += wd
		}
		if r, ok := Dig(s, "run").(string); ok {
			run += r
		}
	}
	for _, want := range []string{"tools/dco", "go run .", "--head ${{ github.event.pull_request.head.sha }}", "origin/dev", "origin/stg", "origin/prd"} {
		if !strings.Contains(run, want) {
			t.Errorf("dco run step %q lacks %q", run, want)
		}
	}
}

// pull_request_target runs with write access on fork code; no workflow may
// use it, in any of the forms `on` takes (string, list or map).
func TestNoWorkflowUsesPullRequestTarget(t *testing.T) {
	files, err := filepath.Glob(filepath.Join(Root(), ".github", "workflows", "*.yml"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no workflows found: %v", err)
	}
	for _, f := range files {
		rel := ".github/workflows/" + filepath.Base(f)
		var events []string
		switch on := Dig(mustYAML(t, rel), "on").(type) {
		case string:
			events = []string{on}
		case []any:
			for _, e := range on {
				s, _ := e.(string)
				events = append(events, s)
			}
		case map[string]any:
			for e := range on {
				events = append(events, e)
			}
		default:
			t.Errorf("%s: unexpected on: %v", rel, on)
		}
		for _, e := range events {
			if e == "pull_request_target" {
				t.Errorf("%s uses pull_request_target", rel)
			}
		}
	}
}
