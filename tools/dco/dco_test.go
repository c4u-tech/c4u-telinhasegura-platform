package main

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// repo makes a throwaway repository on branch dev with one unsigned commit,
// standing for the history from before the DCO. Global and system git
// config are ignored so a developer's signing setup cannot leak in.
func repo(t *testing.T) string {
	t.Helper()
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	dir := t.TempDir()
	git(t, dir, "init", "-q", "-b", "dev")
	commit(t, dir, "Dev One", "dev@example.com", "chore: before the dco")
	return dir
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

// commit makes an empty commit by the given author with the given message.
func commit(t *testing.T, dir, name, email, msg string) string {
	t.Helper()
	git(t, dir, "-c", "user.name="+name, "-c", "user.email="+email,
		"commit", "-q", "--allow-empty", "-m", msg)
	return git(t, dir, "rev-parse", "HEAD")
}

func unsigned(t *testing.T, dir string, exclude ...string) []Commit {
	t.Helper()
	got, err := Unsigned(dir, "HEAD", exclude)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func TestUnsignedFlagsACommitWithoutSignOff(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	sha := commit(t, dir, "Ana", "ana@example.com", "feat: no sign-off")
	got := unsigned(t, dir, "dev")
	if len(got) != 1 || got[0].SHA != sha || got[0].Subject != "feat: no sign-off" {
		t.Fatalf("got %+v, want the one unsigned feature commit", got)
	}
}

func TestUnsignedAcceptsTheAuthorsSignOff(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	commit(t, dir, "Ana", "ana@example.com", "feat: signed\n\nSigned-off-by: Ana <ana@example.com>")
	if got := unsigned(t, dir, "dev"); len(got) != 0 {
		t.Fatalf("got %+v, want none", got)
	}
}

func TestUnsignedIgnoresEmailCase(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	commit(t, dir, "Ana", "Ana@Example.com", "feat: signed\n\nSigned-off-by: Ana <ana@example.com>")
	if got := unsigned(t, dir, "dev"); len(got) != 0 {
		t.Fatalf("got %+v, want none", got)
	}
}

func TestUnsignedRejectsASignOffByAnotherEmail(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	commit(t, dir, "Ana", "ana@example.com", "feat: wrong signer\n\nSigned-off-by: Bia <bia@example.com>")
	if got := unsigned(t, dir, "dev"); len(got) != 1 {
		t.Fatalf("got %+v, want the commit signed by someone else", got)
	}
}

func TestUnsignedNeedsTheTrailerAtLineStart(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	commit(t, dir, "Ana", "ana@example.com", "feat: quoted\n\nI did not add Signed-off-by: Ana <ana@example.com> here\n   Signed-off-by: Ana <ana@example.com>")
	if got := unsigned(t, dir, "dev"); len(got) != 1 {
		t.Fatalf("got %+v, want the commit whose sign-off is not a trailer line", got)
	}
}

func TestUnsignedSkipsCommitsOnAnExcludedBranch(t *testing.T) {
	dir := repo(t)
	// A promotion: stg is behind dev, and the PR head is dev itself.
	git(t, dir, "branch", "stg")
	commit(t, dir, "Dev One", "dev@example.com", "chore: also before the dco")
	if got := unsigned(t, dir, "dev", "stg"); len(got) != 0 {
		t.Fatalf("got %+v, want none: every commit is already on dev", got)
	}
}

func TestUnsignedExemptsMergeCommitsAndBots(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "side")
	commit(t, dir, "Ana", "ana@example.com", "feat: side\n\nSigned-off-by: Ana <ana@example.com>")
	git(t, dir, "switch", "-q", "-c", "feature", "dev")
	commit(t, dir, "github-actions[bot]", "41898282+github-actions[bot]@users.noreply.github.com", "chore(release): release app 0.2.0")
	git(t, dir, "-c", "user.name=Ana", "-c", "user.email=ana@example.com", "merge", "-q", "--no-ff", "--no-edit", "side")
	if got := unsigned(t, dir, "dev"); len(got) != 0 {
		t.Fatalf("got %+v, want none: a merge and a bot commit", got)
	}
}

// The release App's identity is <app>[bot] with a numeric noreply email.
func TestUnsignedExemptsTheReleaseApp(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	commit(t, dir, "telinha-release[bot]", "123+telinha-release[bot]@users.noreply.github.com", "chore(release): release backend 0.2.0")
	if got := unsigned(t, dir, "dev"); len(got) != 0 {
		t.Fatalf("got %+v, want none: a GitHub App commit", got)
	}
}

// A name ending in [bot] alone proves nothing: anyone can set user.name.
func TestUnsignedDoesNotExemptAHumanNamedLikeABot(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	commit(t, dir, "x[bot]", "ana@example.com", "feat: sneaky")
	if got := unsigned(t, dir, "dev"); len(got) != 1 {
		t.Fatalf("got %+v, want the one commit named like a bot", got)
	}
}

func TestRunNamesEachUnsignedCommitAndFails(t *testing.T) {
	dir := repo(t)
	git(t, dir, "switch", "-q", "-c", "feature")
	sha := commit(t, dir, "Ana", "ana@example.com", "feat: no sign-off")
	var out strings.Builder
	if code := run(dir, []string{"--head", "HEAD", "dev"}, &out); code != 1 {
		t.Fatalf("exit %d, want 1; output:\n%s", code, out.String())
	}
	if !strings.Contains(out.String(), sha[:12]) || !strings.Contains(out.String(), "ana@example.com") {
		t.Errorf("output %q must name the commit and the author email", out.String())
	}
}

func TestRunPassesWhenEverythingIsSigned(t *testing.T) {
	dir := repo(t)
	var out strings.Builder
	if code := run(dir, []string{"--head", "HEAD", "dev"}, &out); code != 0 {
		t.Fatalf("exit %d, want 0; output:\n%s", code, out.String())
	}
}

func TestRunRejectsAnUnknownRef(t *testing.T) {
	dir := repo(t)
	var out strings.Builder
	if code := run(dir, []string{"--head", "HEAD", "origin/nope"}, &out); code != 2 {
		t.Fatalf("exit %d, want 2 for a ref that does not exist", code)
	}
}
