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
	want := []string{"android_internal", "android_promote", "android_rollout", "build_number", "ios_submit", "ios_testflight", "metadata"}
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

// Apple texts sit under metadata/ios so deliver never reads the Android
// folder as a language.
func TestMetadataLaneReadsBothFolders(t *testing.T) {
	full := read(t, "app/fastlane/Fastfile")
	start := strings.Index(full, "lane :metadata do")
	if start < 0 {
		t.Fatal("Fastfile has no metadata lane")
	}
	src := full[start:]
	if end := strings.Index(src, "\nend\n"); end >= 0 {
		src = src[:end]
	}
	for _, want := range []string{`"fastlane/metadata/ios"`, `"fastlane/metadata/android"`, "skip_binary_upload: true", "submit_for_review: false", "skip_upload_aab: true", "run_precheck_before_submit: false"} {
		if !strings.Contains(src, want) {
			t.Errorf("Fastfile metadata lane lacks %s", want)
		}
	}
}

// Images go out only when asked: the same switch frees both stores' image
// uploads, and the App Store set is replaced rather than appended to.
func TestMetadataLaneSendsImagesOnlyOnRequest(t *testing.T) {
	full := read(t, "app/fastlane/Fastfile")
	start := strings.Index(full, "lane :metadata do")
	if start < 0 {
		t.Fatal("Fastfile has no metadata lane")
	}
	src := full[start:]
	if end := strings.Index(src, "\nend\n"); end >= 0 {
		src = src[:end]
	}
	for _, want := range []string{
		`options[:images]`,
		"skip_upload_images: !images",
		"skip_upload_screenshots: !images",
		"skip_screenshots: !images",
		`screenshots_path: File.join(APP_DIR, "fastlane/screenshots/ios")`,
		"overwrite_screenshots: true",
	} {
		if !strings.Contains(src, want) {
			t.Errorf("Fastfile metadata lane lacks %s", want)
		}
	}
}

var deliverCall = regexp.MustCompile(`(?s)upload_to_app_store\((.*?)\n\s*\)`)

// fastlane/metadata holds both platforms, and deliver refuses to start when
// its default metadata folder has an "ios" or "android" folder in it, even
// with skip_metadata. Every deliver call must point at the iOS folders.
func TestEveryDeliverCallPointsAtTheIOSFolders(t *testing.T) {
	calls := deliverCall.FindAllStringSubmatch(read(t, "app/fastlane/Fastfile"), -1)
	if len(calls) == 0 {
		t.Fatal("Fastfile has no upload_to_app_store call")
	}
	for i, c := range calls {
		for _, want := range []string{`metadata_path: File.join(APP_DIR, "fastlane/metadata/ios")`, `screenshots_path: File.join(APP_DIR, "fastlane/screenshots/ios")`} {
			if !strings.Contains(c[1], want) {
				t.Errorf("upload_to_app_store call %d lacks %s", i+1, want)
			}
		}
	}
}
