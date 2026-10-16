#!/bin/sh
# After every push to prd, open a PR from prd into stg and into dev, to be
# merged by a person with a merge commit, never a squash. A target that already contains prd, or whose tree
# equals prd's, is skipped; a PR already
# open is reused. Fails, naming the branch, when GitHub reports a
# conflict. Needs gh authenticated through GH_TOKEN, run in a checkout
# whose origin branches are fetched.
set -eu

src="${BACK_MERGE_SOURCE:-prd}"
poll="${BACK_MERGE_POLL_SECONDS:-5}"
status=0

for target in stg dev; do
  if [ -z "$(git rev-list "origin/$target..origin/$src")" ] ||
    git diff --quiet "origin/$target" "origin/$src"; then
    echo "back-merge: $target already contains $src"
    continue
  fi
  url="$(gh pr list --base "$target" --head "$src" --state open --json url --jq '.[0].url // empty')"
  if [ -z "$url" ]; then
    url="$(gh pr create --base "$target" --head "$src" \
      --title "chore(release): back-merge $src into $target" \
      --body "Brings the release on \`$src\` back into \`$target\`. Merge with a merge commit, never a squash.")"
  fi
  # GitHub computes mergeability asynchronously: UNKNOWN is not a conflict.
  state=UNKNOWN
  tries=0
  while [ "$tries" -lt 6 ]; do
    state="$(gh pr view "$url" --json mergeable --jq .mergeable)"
    [ "$state" != UNKNOWN ] && break
    tries=$((tries + 1))
    sleep "$poll"
  done
  if [ "$state" = CONFLICTING ]; then
    echo "back-merge: $src conflicts with $target: $url" >&2
    status=1
  else
    echo "back-merge: $url ($state)"
  fi
done

exit "$status"
