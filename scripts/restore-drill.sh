#!/bin/sh
# The restore drill: restores the
# newest (or a named) dump into a throwaway database, boots the API on it so
# its migrations run, counts the accounts, and drops the database, also
# when a step fails. Runs on the maintainer's machine (or in the backup
# smoke) with Docker; the age private key never leaves it.
# usage: ADMIN_DATABASE_URL=... AGE_IDENTITY_FILE=... \
#   BACKUP_S3_ACCESS_KEY_ID=... BACKUP_S3_SECRET_ACCESS_KEY=... BACKUP_BUCKET=... \
#   scripts/restore-drill.sh <backup-image> <api-image> [name|latest]
# ADMIN_DATABASE_URL may create databases and must reach Postgres from
# inside a container (host.docker.internal is mapped to the host); it ends
# in a database name, e.g. .../postgres?sslmode=disable.
set -eu
backup_image="${1:?usage: scripts/restore-drill.sh <backup-image> <api-image> [name|latest]}"
api_image="${2:?usage: scripts/restore-drill.sh <backup-image> <api-image> [name|latest]}"
name="${3:-latest}"
: "${ADMIN_DATABASE_URL:?ADMIN_DATABASE_URL is required}"
: "${AGE_IDENTITY_FILE:?AGE_IDENTITY_FILE is required}"

case "$AGE_IDENTITY_FILE" in
  /*) ;;
  *) AGE_IDENTITY_FILE="$(pwd)/$AGE_IDENTITY_FILE" ;;
esac
[ -f "$AGE_IDENTITY_FILE" ] && [ -r "$AGE_IDENTITY_FILE" ] ||
  { echo "restore-drill: AGE_IDENTITY_FILE is not a readable file" >&2; exit 1; }

db="restore_drill_$(date +%s)_$$"
base="${ADMIN_DATABASE_URL%%\?*}"
query="${ADMIN_DATABASE_URL#"$base"}"
target="${base%/*}/$db$query"
net=""
[ -z "${DRILL_NETWORK:-}" ] || net="--network=$DRILL_NETWORK"
api=""

tool() {
  entry="$1"
  shift
  # shellcheck disable=SC2086 # $net is one flag or nothing
  docker run --rm $net --add-host=host.docker.internal:host-gateway --entrypoint "$entry" "$backup_image" "$@"
}

cleanup() {
  [ -z "$api" ] || docker rm -f "$api" >/dev/null 2>&1 || true
  tool psql "$ADMIN_DATABASE_URL" -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

fail() {
  echo "restore-drill: $1" >&2
  exit 1
}

tool psql "$ADMIN_DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE $db" ||
  fail "could not create $db"

# shellcheck disable=SC2086
docker run --rm $net --add-host=host.docker.internal:host-gateway \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -e BACKUP_S3_ACCESS_KEY_ID -e BACKUP_S3_SECRET_ACCESS_KEY -e BACKUP_BUCKET \
  -e BACKUP_S3_ENDPOINT -e BACKUP_S3_PROVIDER \
  -e AGE_IDENTITY_FILE=/run/age/identity -v "$AGE_IDENTITY_FILE:/run/age/identity:ro" \
  "$backup_image" restore "$name" "$target" || fail "the restore failed"

api="$(docker run -d --add-host=host.docker.internal:host-gateway \
  -e DATABASE_URL="$target" -e APP_BASE_URL=https://drill.test -e STAFF_MFA_REQUIRED=false \
  "$api_image")"
i=0
until docker exec "$api" /api healthcheck 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { docker logs "$api" >&2; fail "the API never became healthy on the restored database"; }
  sleep 1
done

count="$(tool psql "$target" -tA -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM accounts")" ||
  fail "the smoke query failed"
case "$count" in
  "" | *[!0-9]* | 0) fail "the restored database holds no accounts" ;;
esac
echo "restore-drill: ok, $count accounts"
