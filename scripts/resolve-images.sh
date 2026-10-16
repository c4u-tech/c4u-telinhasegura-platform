#!/bin/sh
# Resolves a commit SHA or an input-digest tag (in-<40 hex>) to each
# component's image pinned by manifest digest, as GitHub step outputs:
# <component>=<repo>@sha256:..., and api_revision=<the API image's
# revision label>. Prints nothing, and fails, when any requested image is
# missing, so no deploy step starts.
# usage: scripts/resolve-images.sh <ref> <component>...
set -eu
fail() {
  echo "resolve-images: $1" >&2
  exit 1
}
[ "$#" -ge 2 ] || fail "usage: scripts/resolve-images.sh <ref> <component>..."
ref="$1"
shift
case "$ref" in *"
"*) fail "ref must be a single line" ;; esac
printf '%s' "$ref" | grep -Eq '^(in-)?[0-9a-f]{40}$' || fail "ref must be a 40-hex commit SHA or in-<40 hex> (got '$ref')"
for c in "$@"; do
  case "$c" in api | web | site | backup) ;; *) fail "unknown component '$c'" ;; esac
done

registry="${REGISTRY:-ghcr.io/c4u-tech}"
out=""
for c in "$@"; do
  repo="$registry/telinhasegura-$c"
  docker pull -q "$repo:$ref" >/dev/null || fail "$repo:$ref does not exist"
  pinned="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$repo:$ref" | grep "^$repo@sha256:" | head -n 1)"
  [ -n "$pinned" ] || fail "$repo:$ref has no digest in $registry"
  out="$out$c=$pinned
"
  if [ "$c" = api ]; then
    revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$repo:$ref")"
    out="${out}api_revision=$revision
"
  fi
done
printf '%s' "$out"
