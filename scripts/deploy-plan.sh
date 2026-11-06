#!/bin/sh
# Works out which components an environment does not run yet, and records
# what it runs once a deploy is verified. Each environment's running image
# carries the tag deployed-<env>; it moves only through `record`.
#
# usage: scripts/deploy-plan.sh <stg|prd> <ref> <component>...
#   prints, space-separated and in the order given, the components whose
#   <ref> image differs from deployed-<env> by manifest digest, or that
#   have no deployed-<env> tag yet. Fails, printing nothing, when a <ref>
#   image is missing.
# usage: scripts/deploy-plan.sh record <stg|prd> <repo>@sha256:<digest>
#   tags that image as <repo>:deployed-<env>.
# REGISTRY defaults to ghcr.io/c4u-tech. Digests are read from the
# registry without pulling.
set -eu
fail() {
  echo "deploy-plan: $1" >&2
  exit 1
}
usage="usage: scripts/deploy-plan.sh <stg|prd> <ref> <component>... | record <stg|prd> <repo>@sha256:<digest>"
env_ok() {
  case "$1" in stg | prd) ;; *) fail "unknown environment '$1'" ;; esac
}
registry="${REGISTRY:-ghcr.io/c4u-tech}"

if [ "${1:-}" = record ]; then
  [ "$#" -eq 3 ] || fail "$usage"
  env_ok "$2"
  pinned="$3"
  case "$pinned" in *"
"*) fail "image must be a single line" ;; esac
  printf '%s' "$pinned" | grep -Eq "^$registry/telinhasegura-(api|web|site|backup)@sha256:[0-9a-f]+\$" ||
    fail "image must be $registry/telinhasegura-<component>@sha256:<digest> (got '$pinned')"
  repo="${pinned%@*}"
  docker buildx imagetools create --tag "$repo:deployed-$2" "$pinned"
  exit 0
fi

[ "$#" -ge 3 ] || fail "$usage"
target="$1"
ref="$2"
shift 2
env_ok "$target"
case "$ref" in *"
"*) fail "ref must be a single line" ;; esac
printf '%s' "$ref" | grep -Eq '^(in-)?[0-9a-f]{40}$' || fail "ref must be a 40-hex commit SHA or in-<40 hex> (got '$ref')"
for c in "$@"; do
  case "$c" in api | web | site | backup) ;; *) fail "unknown component '$c'" ;; esac
done

digest() {
  docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$1"
}
plan=""
for c in "$@"; do
  repo="$registry/telinhasegura-$c"
  want="$(digest "$repo:$ref")" && [ -n "$want" ] || fail "$repo:$ref does not exist"
  # No deployed tag yet (or one that cannot be read) means deploy.
  have="$(digest "$repo:deployed-$target" 2>/dev/null || true)"
  [ "$want" = "$have" ] || plan="${plan:+$plan }$c"
done
echo "$plan"
