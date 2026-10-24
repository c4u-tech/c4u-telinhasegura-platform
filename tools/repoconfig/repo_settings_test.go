package repoconfig

import (
	"strings"
	"testing"
)

// fakeGitHub answers the reads check-repo-settings.sh makes: the repository
// settings from $FAKE_REPO, and a branch's effective rules from
// $FAKE_RULES_<branch> (empty: no rules). Any other call is logged and fails,
// so a write would show up in the log and in the exit status.
const fakeGitHub = `#!/bin/sh
echo "gh $*" >> "$FAKE_LOG"
[ "$1" = api ] && [ "$#" -eq 2 ] || { echo "fake gh: unexpected call" >&2; exit 1; }
case "$2" in
  repos/acme/app) echo "$FAKE_REPO" ;;
  repos/acme/app/rules/branches/*)
    eval "rules=\${FAKE_RULES_${2##*/}:-}"
    if [ -n "$rules" ]; then echo "$rules"; else echo '[]'; fi ;;
  *) echo "fake gh: unexpected $2" >&2; exit 1 ;;
esac
`

const goodRepo = `{"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":false,"delete_branch_on_merge":false}`

func branchRules(methods ...string) string {
	return `[{"type":"deletion","parameters":null},{"type":"non_fast_forward","parameters":null},` +
		`{"type":"pull_request","parameters":{"allowed_merge_methods":["` + strings.Join(methods, `","`) + `"]}},` +
		`{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci-ok"}]}}]`
}

func settingsEnv(repo string, rules map[string]string) map[string]string {
	env := map[string]string{"FAKE_REPO": repo}
	for b, r := range rules {
		env["FAKE_RULES_"+b] = r
	}
	return env
}

func enforced() map[string]string {
	return map[string]string{
		"dev": branchRules("merge", "squash"),
		"stg": branchRules("merge"),
		"prd": branchRules("merge"),
	}
}

func checkSettings(t *testing.T, env map[string]string) (string, string, error) {
	t.Helper()
	out, log, err := runScript(t, "check-repo-settings.sh", map[string]string{"gh": fakeGitHub}, env, "acme/app")
	for _, line := range strings.Split(log, "\n") {
		if strings.HasPrefix(line, "gh ") && !strings.HasPrefix(line, "gh api repos/acme/app") {
			t.Errorf("check-repo-settings made a call other than a read: %q", line)
		}
	}
	return out, log, err
}

func TestCheckRepoSettingsPassesAnEnforcedRepository(t *testing.T) {
	out, log, err := checkSettings(t, settingsEnv(goodRepo, enforced()))
	if err != nil {
		t.Fatalf("enforced repository reported a gap: %v\n%s%s", err, out, log)
	}
	for _, b := range []string{"dev", "stg", "prd"} {
		if !strings.Contains(out, "ok    "+b+" ") {
			t.Errorf("no ok line for %s:\n%s", b, out)
		}
	}
}

func TestCheckRepoSettingsReportsMergeMethodDrift(t *testing.T) {
	repo := `{"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true,"delete_branch_on_merge":false}`
	out, _, err := checkSettings(t, settingsEnv(repo, enforced()))
	if err == nil {
		t.Fatalf("rebase allowed, but no gap:\n%s", out)
	}
	if !strings.Contains(out, "gh repo edit acme/app --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false") {
		t.Errorf("no command to close the merge-method gap:\n%s", out)
	}
}

func TestCheckRepoSettingsReportsAMissingRuleset(t *testing.T) {
	rules := enforced()
	delete(rules, "stg")
	out, _, err := checkSettings(t, settingsEnv(goodRepo, rules))
	if err == nil {
		t.Fatalf("stg unprotected, but no gap:\n%s", out)
	}
	if !strings.Contains(out, "GAP   stg") || !strings.Contains(out, "gh api -X POST repos/acme/app/rulesets --input .github/rulesets/stg.json") {
		t.Errorf("no gap and command for stg:\n%s", out)
	}
	if strings.Contains(out, "GAP   dev") || strings.Contains(out, "GAP   prd") {
		t.Errorf("gap reported on an enforced branch:\n%s", out)
	}
}

func TestCheckRepoSettingsReportsAWeakerRuleset(t *testing.T) {
	cases := map[string]string{
		"squash allowed on prd": branchRules("merge", "squash"),
		"ci-ok not required":    strings.Replace(branchRules("merge"), "ci-ok", "build", 1),
		"force push allowed":    strings.Replace(branchRules("merge"), `{"type":"non_fast_forward","parameters":null},`, "", 1),
	}
	for name, prd := range cases {
		t.Run(name, func(t *testing.T) {
			rules := enforced()
			rules["prd"] = prd
			out, _, err := checkSettings(t, settingsEnv(goodRepo, rules))
			if err == nil || !strings.Contains(out, "GAP   prd") {
				t.Errorf("%s: no gap on prd (err %v):\n%s", name, err, out)
			}
		})
	}
}
