#!/bin/sh
# Publishes one component's image,
# in three steps CI runs around the smoke test:
#   reuse  prints "reused" after tagging an existing image whose build
#          inputs are this commit's (its in-<digest> tag) with the
#          revision, or "absent"
#   build  (runs <context>/deploy/prebuild.sh first when it exists) builds
#          telinhasegura-<component>:smoke with the revision label
#   push   pushes the built image as in-<digest> and <revision>
# usage: scripts/publish-image.sh reuse|build|push <component> <revision>
#   component: api | web | site | backup; revision: a 40-hex commit SHA
# REGISTRY defaults to ghcr.io/c4u-tech. Only VERSION is a build argument:
# build arguments land in the image's provenance.
set -eu
usage() {
  echo "usage: scripts/publish-image.sh reuse|build|push <component> <revision>" >&2
  exit 1
}
[ "$#" -eq 3 ] || usage
step="$1"
component="$2"
revision="$3"
printf '%s' "$revision" | grep -Eq '^[0-9a-f]{40}$' || usage
case "$component" in
  api) ctx=backend ;;
  web) ctx=app ;;
  site) ctx=site ;;
  backup) ctx=deploy/backup ;;
  *) usage ;;
esac
cd "$(dirname "$0")/.."
repo="${REGISTRY:-ghcr.io/c4u-tech}/telinhasegura-$component"
in="$repo:in-$(sh scripts/image-digest.sh "$ctx")"
local="telinhasegura-$component:smoke"

case "$step" in
  reuse)
    if docker buildx imagetools inspect "$in" >/dev/null 2>&1; then
      docker buildx imagetools create --tag "$repo:$revision" "$in" >&2
      echo reused
    else
      echo absent
    fi ;;
  build)
    [ ! -f "$ctx/deploy/prebuild.sh" ] || sh "$ctx/deploy/prebuild.sh"
    docker build --build-arg "VERSION=$revision" \
      --label "org.opencontainers.image.revision=$revision" \
      --label "org.opencontainers.image.source=https://github.com/c4u-tech/c4u-telinhasegura-platform" \
      -t "$local" "$ctx" ;;
  push)
    docker tag "$local" "$in"
    docker tag "$local" "$repo:$revision"
    docker push "$in"
    docker push "$repo:$revision" ;;
  *) usage ;;
esac
