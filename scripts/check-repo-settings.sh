#!/bin/sh
# Checks, read-only, that GitHub enforces the branch model this repository
# relies on. Feature branches merge into dev by squash; dev, stg and prd live
# on and are promoted by merge commit. So the repository allows exactly those
# two merge methods, and each environment branch carries the ruleset
# committed in .github/rulesets/<branch>.json: no deletion, no force push, a
# pull request limited to that file's merge methods, and the aggregate ci-ok
# check required.
#
# It never changes the repository: for each gap it prints the command that
# closes it.
#
# usage: scripts/check-repo-settings.sh [owner/repo]
# Exit 0: all enforced; 1: a gap; 2: the repository could not be read.
set -u

GH="${GH:-gh}"
check="ci-ok"
root="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "check-repo-settings: jq is required" >&2; exit 2; }
command -v "$GH" >/dev/null 2>&1 || { echo "check-repo-settings: gh is required" >&2; exit 2; }
repo="${1:-$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
[ -n "$repo" ] || { echo "check-repo-settings: no GitHub repository; pass owner/repo" >&2; exit 2; }
gaps=0
gap() { echo "GAP   $1"; gaps=$((gaps + 1)); }
ok() { echo "ok    $1"; }

# 1. Merge methods: squash for feature branches, merge commits for
#    promotions, never rebase.
if ! settings="$("$GH" api "repos/$repo" 2>&1)"; then
  echo "check-repo-settings: cannot read $repo: $settings" >&2; exit 2
fi
if printf '%s' "$settings" | jq -e '.allow_squash_merge == true and .allow_merge_commit == true
    and .allow_rebase_merge == false' >/dev/null 2>&1; then
  ok "squash and merge commits are allowed, rebase is not"
else
  gap "merge methods differ from squash plus merge commit. To close it:"
  echo "      $GH repo edit $repo --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false"
fi

# 2. Each environment branch: the effective rules hold everything its
#    committed ruleset promises.
for branch in dev stg prd; do
  file=".github/rulesets/$branch.json"
  want="$(jq -c '[.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods[]] | sort' "$root/$file")"
  if rules="$("$GH" api "repos/$repo/rules/branches/$branch" 2>/dev/null)" &&
    printf '%s' "$rules" | jq -e --arg c "$check" --argjson want "$want" '
      any(.[]; .type == "deletion") and
      any(.[]; .type == "non_fast_forward") and
      any(.[]; .type == "pull_request" and ((.parameters.allowed_merge_methods // []) | sort) == $want) and
      any(.[]; .type == "required_status_checks" and
        any(.parameters.required_status_checks[]; .context == $c))' >/dev/null 2>&1; then
    ok "$branch is protected as $file says"
  else
    gap "$branch is not protected as $file says. To close it, create the ruleset"
    echo "      (or update the existing one with -X PUT repos/$repo/rulesets/<id>):"
    echo "      $GH api -X POST repos/$repo/rulesets --input $file"
  fi
done

echo
if [ "$gaps" -eq 0 ]; then echo "check-repo-settings: $repo enforces the branch model"; else echo "check-repo-settings: $gaps gap(s)"; fi
[ "$gaps" -eq 0 ]
