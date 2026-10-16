package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeGH answers the four gh calls scripts/back-merge.sh makes. Every call
// is appended to $GH_LOG. FAKE_OPEN_PR names a base whose PR is already
// open; FAKE_MERGEABLE_<base> sets what `pr view` answers (default
// MERGEABLE).
const fakeGH = `#!/bin/sh
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list")
    base=$4
    [ "$FAKE_OPEN_PR" = "$base" ] && echo "https://example.test/pr/open-$base"
    exit 0 ;;
  "pr create")
    echo "https://example.test/pr/$4"
    exit 0 ;;
  "pr view")
    base=${3##*/}; base=${base#open-}
    eval "state=\${FAKE_MERGEABLE_$base:-MERGEABLE}"
    echo "$state"
    exit 0 ;;
esac
echo "fake gh: unexpected call: $*" >&2
exit 2
`

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=dev"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

// repoWithRelease builds an origin where dev, stg and prd start equal and
// prd then gains one release commit. With devHasIt, dev is fast-forwarded
// to prd as well. It returns a fetched clone.
func repoWithRelease(t *testing.T, devHasIt bool) string {
	t.Helper()
	root := t.TempDir()
	origin := filepath.Join(root, "origin.git")
	work := filepath.Join(root, "work")
	git(t, root, "init", "--bare", origin)
	git(t, root, "clone", origin, work)
	git(t, work, "commit", "--allow-empty", "-m", "chore: start")
	git(t, work, "push", "origin", "HEAD:dev", "HEAD:stg", "HEAD:prd")
	if err := os.WriteFile(filepath.Join(work, "CHANGELOG.md"), []byte("0.2.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git(t, work, "add", "CHANGELOG.md")
	git(t, work, "commit", "-m", "chore(release): release app 0.2.0")
	git(t, work, "push", "origin", "HEAD:prd")
	if devHasIt {
		git(t, work, "push", "origin", "HEAD:dev")
	}
	git(t, work, "fetch", "origin")
	return work
}

func runBackMerge(t *testing.T, work string, env ...string) (string, string, error) {
	t.Helper()
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "gh"), []byte(fakeGH), 0o755); err != nil {
		t.Fatal(err)
	}
	log := filepath.Join(bin, "gh.log")
	cmd := exec.Command("sh", filepath.Join(Root(), "scripts", "back-merge.sh"))
	cmd.Dir = work
	cmd.Env = append(os.Environ(), append([]string{
		"PATH=" + bin + string(os.PathListSeparator) + os.Getenv("PATH"),
		"GH_LOG=" + log,
		"BACK_MERGE_POLL_SECONDS=0",
	}, env...)...)
	var stdout, stderr strings.Builder
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	calls, _ := os.ReadFile(log)
	return stdout.String() + stderr.String(), string(calls), err
}

func TestBackMergeOpensAPRIntoStgAndDev(t *testing.T) {
	out, calls, err := runBackMerge(t, repoWithRelease(t, false))
	if err != nil {
		t.Fatalf("exit: %v\n%s", err, out)
	}
	for _, base := range []string{"stg", "dev"} {
		if !strings.Contains(calls, "pr create --base "+base+" --head prd") {
			t.Errorf("no PR created into %s; calls:\n%s", base, calls)
		}
	}
	if !strings.Contains(calls, "--title chore(release): back-merge prd into stg") {
		t.Errorf("PR title is not the Conventional Commit; calls:\n%s", calls)
	}
}

func TestBackMergeFailsNamingTheConflictingBranch(t *testing.T) {
	out, calls, err := runBackMerge(t, repoWithRelease(t, false), "FAKE_MERGEABLE_stg=CONFLICTING")
	if err == nil {
		t.Fatalf("want a non-zero exit on a conflict\n%s", out)
	}
	if !strings.Contains(out, "prd conflicts with stg") {
		t.Errorf("output does not name stg:\n%s", out)
	}
	if !strings.Contains(calls, "pr create --base dev") {
		t.Errorf("dev was not processed after stg conflicted:\n%s", calls)
	}
}

func TestBackMergeSkipsATargetWithTheSameTree(t *testing.T) {
	work := repoWithRelease(t, false)
	git(t, work, "checkout", "-q", "-b", "stgside", "origin/stg")
	if err := os.WriteFile(filepath.Join(work, "CHANGELOG.md"), []byte("0.2.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git(t, work, "add", "CHANGELOG.md")
	git(t, work, "commit", "-m", "chore: same tree, other commit")
	git(t, work, "push", "origin", "HEAD:stg")
	git(t, work, "fetch", "origin")
	out, calls, err := runBackMerge(t, work)
	if err != nil {
		t.Fatalf("exit: %v\n%s", err, out)
	}
	if strings.Contains(calls, "--base stg") {
		t.Errorf("stg has prd's tree, but gh was asked about it:\n%s", calls)
	}
	if !strings.Contains(out, "stg already contains prd") {
		t.Errorf("no skip line for stg:\n%s", out)
	}
	if !strings.Contains(calls, "pr create --base dev") {
		t.Errorf("dev was not processed:\n%s", calls)
	}
}

func TestBackMergeSkipsATargetThatAlreadyHasTheRelease(t *testing.T) {
	out, calls, err := runBackMerge(t, repoWithRelease(t, true))
	if err != nil {
		t.Fatalf("exit: %v\n%s", err, out)
	}
	if strings.Contains(calls, "--base dev") {
		t.Errorf("dev already has prd, but gh was asked about it:\n%s", calls)
	}
	if !strings.Contains(out, "dev already contains prd") {
		t.Errorf("no skip line for dev:\n%s", out)
	}
}

func TestBackMergeReusesAnOpenPR(t *testing.T) {
	out, calls, err := runBackMerge(t, repoWithRelease(t, false), "FAKE_OPEN_PR=stg")
	if err != nil {
		t.Fatalf("exit: %v\n%s", err, out)
	}
	if strings.Contains(calls, "pr create --base stg") {
		t.Errorf("a PR into stg was already open, but another was created:\n%s", calls)
	}
	if !strings.Contains(out, "open-stg") {
		t.Errorf("the open PR is not reported:\n%s", out)
	}
}

func TestBackMergeDoesNotCallUnknownAConflict(t *testing.T) {
	out, calls, err := runBackMerge(t, repoWithRelease(t, false), "FAKE_MERGEABLE_stg=UNKNOWN")
	if err != nil {
		t.Fatalf("UNKNOWN must not fail the job: %v\n%s", err, out)
	}
	if n := strings.Count(calls, "pr view https://example.test/pr/stg"); n < 2 {
		t.Errorf("UNKNOWN was not retried (%d views)", n)
	}
	if !strings.Contains(out, "(UNKNOWN)") {
		t.Errorf("the unresolved state is not reported:\n%s", out)
	}
}
