#!/bin/sh
# Runs one component image's smoke test, as
# CI's images job does after publish-image.sh build.
# usage: scripts/smoke.sh <component> <image> <revision>
# DATABASE_URL (api, backup) must reach Postgres from inside a container.
set -eu
component="${1:?usage: scripts/smoke.sh <component> <image> <revision>}"
image="${2:?usage: scripts/smoke.sh <component> <image> <revision>}"
revision="${3:?usage: scripts/smoke.sh <component> <image> <revision>}"
cd "$(dirname "$0")/.."
case "$component" in
  api) exec sh scripts/image-smoke.sh "$image" "$revision" ;;
  web) exec sh scripts/static-smoke.sh "$image" web ;;
  site) exec sh scripts/static-smoke.sh "$image" site ;;
  backup)
    docker build --build-arg "VERSION=$revision" -t telinhasegura-api:smoke backend
    exec sh scripts/backup-smoke.sh "$image" telinhasegura-api:smoke ;;
  *) echo "smoke: unknown component $component" >&2; exit 1 ;;
esac
