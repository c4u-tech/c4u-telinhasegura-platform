package repoconfig

import (
	"reflect"
	"testing"
)

func TestRulesetsProtectEveryEnvironmentBranch(t *testing.T) {
	methods := map[string][]string{
		"dev": {"squash", "merge"},
		"stg": {"merge"},
		"prd": {"merge"},
	}
	for branch, wantMethods := range methods {
		rs := mustJSON(t, ".github/rulesets/"+branch+".json")
		if rs["target"] != "branch" || rs["enforcement"] != "active" {
			t.Errorf("%s: target %v enforcement %v, want branch/active", branch, rs["target"], rs["enforcement"])
		}
		if got := strs(t, Dig(rs, "conditions", "ref_name", "include")); !reflect.DeepEqual(got, []string{"refs/heads/" + branch}) {
			t.Errorf("%s: include = %v", branch, got)
		}
		if b, _ := rs["bypass_actors"].([]any); len(b) != 0 {
			t.Errorf("%s: bypass_actors = %v, want none", branch, b)
		}
		rules := map[string]any{}
		list, _ := rs["rules"].([]any)
		for _, r := range list {
			typ, _ := Dig(r, "type").(string)
			rules[typ] = Dig(r, "parameters")
		}
		for _, typ := range []string{"deletion", "non_fast_forward", "pull_request", "required_status_checks"} {
			if _, ok := rules[typ]; !ok {
				t.Errorf("%s: rule %s missing", branch, typ)
			}
		}
		if _, ok := rules["required_linear_history"]; ok {
			t.Errorf("%s: linear history would refuse merge commits", branch)
		}
		if got := strs(t, Dig(rules["pull_request"], "allowed_merge_methods")); !reflect.DeepEqual(got, wantMethods) {
			t.Errorf("%s: allowed_merge_methods = %v, want %v", branch, got, wantMethods)
		}
		checks, _ := Dig(rules["required_status_checks"], "required_status_checks").([]any)
		if len(checks) != 1 || Dig(checks[0], "context") != "ci-ok" {
			t.Errorf("%s: required checks = %v, want only ci-ok", branch, checks)
		}
	}
}
