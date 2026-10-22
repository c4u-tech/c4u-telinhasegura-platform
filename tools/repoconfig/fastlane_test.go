package repoconfig

import (
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
)

var laneDef = regexp.MustCompile(`(?m)^\s*lane\s+:([a-z_]+)`)

// The workflows call these lanes by name.
func TestFastfileDefinesTheStoreLanes(t *testing.T) {
	src := read(t, "app/fastlane/Fastfile")
	var got []string
	for _, m := range laneDef.FindAllStringSubmatch(src, -1) {
		got = append(got, m[1])
	}
	sort.Strings(got)
	want := []string{"android_internal", "android_promote", "android_rollout", "build_number", "ios_submit", "ios_testflight"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("lanes = %v, want %v", got, want)
	}
}

// fastlane must carry the fix that lets supply use workload identity
// credentials, and both runners' platforms must be locked.
func TestGemfilePinsFastlane(t *testing.T) {
	if g := read(t, "app/Gemfile"); !strings.Contains(g, `gem "fastlane", "2.241.1"`) {
		t.Errorf("app/Gemfile must pin fastlane 2.241.1")
	}
	lock := read(t, "app/Gemfile.lock")
	for _, p := range []string{"x86_64-linux", "arm64-darwin"} {
		if !strings.Contains(lock, p) {
			t.Errorf("Gemfile.lock lacks platform %s", p)
		}
	}
	if v := strings.TrimSpace(read(t, "app/.ruby-version")); v != "3.3" {
		t.Errorf("app/.ruby-version = %q, want 3.3", v)
	}
}

// Store credentials only ever come from the environment.
func TestFastlaneFilesCarryNoCredentialValues(t *testing.T) {
	for _, f := range []string{"app/fastlane/Fastfile", "app/fastlane/Appfile", "app/fastlane/Matchfile"} {
		src := read(t, f)
		for _, bad := range []string{"iam.gserviceaccount.com", "workloadIdentityPools", "git@github.com:", "https://github.com/", "-----BEGIN"} {
			if strings.Contains(src, bad) {
				t.Errorf("%s contains %q; credentials and resource names come from the environment", f, bad)
			}
		}
	}
}

func TestCIRunsFastlaneLanes(t *testing.T) {
	ci := mustYAML(t, ".github/workflows/ci.yml")
	job := Dig(ci, "jobs", "fastlane")
	setup := stepUsing(t, job, "ruby/setup-ruby@")
	if Dig(setup, "with", "working-directory") != "app" || Dig(setup, "with", "bundler-cache") != true {
		t.Errorf("setup-ruby with = %v, want working-directory app and bundler-cache", Dig(setup, "with"))
	}
	steps, _ := Dig(job, "steps").([]any)
	found := false
	for _, s := range steps {
		if Dig(s, "run") == "bundle exec fastlane lanes" && Dig(s, "working-directory") == "app" {
			found = true
		}
	}
	if !found {
		t.Error("ci fastlane job must run `bundle exec fastlane lanes` in app")
	}
}
