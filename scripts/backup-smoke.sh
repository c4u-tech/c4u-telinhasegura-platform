#!/bin/sh
# Smoke test of the backup image,
# run by CI's images job and by hand: a migrated source database with one
# account is backed up to a local S3 server (rclone serve s3), a failing
# run pings /fail and keeps nothing, and the restore drill brings the
# account back.
# usage: DATABASE_URL=... scripts/backup-smoke.sh <backup-image> <api-image>
# DATABASE_URL is an admin URL reaching Postgres from inside a container
# (host.docker.internal), ending in a database name.
set -eu
image="${1:?usage: scripts/backup-smoke.sh <backup-image> <api-image>}"
api_image="${2:?usage: scripts/backup-smoke.sh <backup-image> <api-image>}"
: "${DATABASE_URL:?DATABASE_URL is required}"

# rclone/rclone:1.75.2
s3_image=rclone/rclone@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5
# nginxinc/nginx-unprivileged:stable-alpine (nginx 1.30.5), the heartbeat receiver
hb_image=nginxinc/nginx-unprivileged@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3

tag="$$"
net="ts-smoke-$tag"
s3="ts-s3-$tag"
hb="ts-hb-$tag"
src_db="backup_smoke_$tag"
base="${DATABASE_URL%%\?*}"
query="${DATABASE_URL#"$base"}"
src="${base%/*}/$src_db$query"
work="$(mktemp -d "${TMPDIR:-/tmp}/backup-smoke.XXXXXX")" # TMPDIR must be shared with the Docker VM
api=""

tool() {
  entry="$1"
  shift
  docker run --rm --network "$net" --add-host=host.docker.internal:host-gateway --entrypoint "$entry" "$image" "$@"
}

cleanup() {
  [ -z "$api" ] || docker rm -f "$api" >/dev/null 2>&1 || true
  tool psql "$DATABASE_URL" -c "DROP DATABASE IF EXISTS $src_db WITH (FORCE)" >/dev/null 2>&1 || true
  docker rm -f "$s3" "$hb" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

fail() {
  echo "backup-smoke: $1" >&2
  exit 1
}

user="$(docker image inspect -f '{{.Config.User}}' "$image")"
case "$user" in
  "" | root | 0 | root:* | 0:*) fail "the image runs as root (user '$user')" ;;
esac

# The run path: the tools the image promises and a crontab supercronic accepts.
docker run --rm --entrypoint sh "$image" -c \
  'for t in psql pg_dump pg_restore age age-keygen rclone curl supercronic; do command -v "$t" >/dev/null || { echo "missing $t"; exit 1; }; done' ||
  fail "the image lacks a tool"
docker run --rm --entrypoint supercronic "$image" -test /etc/backup/crontab >/dev/null ||
  fail "supercronic rejects /etc/backup/crontab"

docker network create "$net" >/dev/null
docker run -d --name "$s3" --network "$net" "$s3_image" \
  serve s3 --addr 0.0.0.0:8080 --auth-key smoke,smokesecret /data >/dev/null
docker exec "$s3" mkdir -p /data/backups
docker run -d --name "$hb" --network "$net" "$hb_image" >/dev/null

# The age key pair: the identity stays in $work, the recipient goes to the run.
(umask 077 && tool age-keygen >"$work/identity" 2>/dev/null)
recipient="$(grep -o 'age1[0-9a-z]*' "$work/identity" | head -n 1)"
[ -n "$recipient" ] || fail "age-keygen gave no recipient"

# A migrated source database holding one account.
tool psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE $src_db"
api="$(docker run -d --add-host=host.docker.internal:host-gateway \
  -e DATABASE_URL="$src" -e APP_BASE_URL=https://smoke.test -e STAFF_MFA_REQUIRED=false "$api_image")"
i=0
until docker exec "$api" /api healthcheck 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { docker logs "$api" >&2; fail "the API never migrated the source database"; }
  sleep 1
done
docker rm -f "$api" >/dev/null
api=""
tool psql "$src" -v ON_ERROR_STOP=1 -q -c \
  "INSERT INTO accounts (email, adult_declared_at, created_at) VALUES ('smoke@example.test', now(), now())"

backup() {
  docker run --rm --network "$net" --add-host=host.docker.internal:host-gateway \
    -e AGE_RECIPIENT="$recipient" -e BACKUP_S3_ACCESS_KEY_ID=smoke -e BACKUP_S3_SECRET_ACCESS_KEY=smokesecret \
    -e BACKUP_BUCKET=backups -e BACKUP_S3_ENDPOINT="http://$s3:8080" -e BACKUP_S3_PROVIDER=Rclone \
    -e BACKUP_HEARTBEAT_URL="http://$hb:8080/hb" "$@" "$image" run-once
}
count() { docker exec "$s3" sh -c "ls /data/backups/$1 2>/dev/null | wc -l" | tr -d ' '; }

# One encrypted daily object, the heartbeat pinged.
backup -e DATABASE_URL="$src" || fail "run-once failed"
[ "$(count daily)" = 1 ] || fail "daily/ holds $(count daily) objects, want 1"
[ "$(count incoming)" = 0 ] || fail "incoming/ was not emptied"
docker logs "$hb" 2>&1 | grep -q '"GET /hb HTTP' || fail "the heartbeat was not pinged"

# A failing run keeps nothing and pings /fail.
if backup -e DATABASE_URL="${base%/*}/no_such_db$query"; then fail "a run against a missing database exited 0"; fi
[ "$(count daily)" = 1 ] || fail "a failed run changed daily/"
[ "$(count incoming)" = 0 ] || fail "a failed run left an incoming/ object"
docker logs "$hb" 2>&1 | grep -q '"GET /hb/fail HTTP' || fail "the failure was not pinged"

# The drill brings the account back.
out="$(ADMIN_DATABASE_URL="$DATABASE_URL" AGE_IDENTITY_FILE="$work/identity" \
  BACKUP_S3_ACCESS_KEY_ID=smoke BACKUP_S3_SECRET_ACCESS_KEY=smokesecret BACKUP_BUCKET=backups \
  BACKUP_S3_ENDPOINT="http://$s3:8080" BACKUP_S3_PROVIDER=Rclone DRILL_NETWORK="$net" \
  sh "$(dirname "$0")/restore-drill.sh" "$image" "$api_image" latest)" || fail "the restore drill failed"
case "$out" in
  *"restore-drill: ok, 1 accounts"*) ;;
  *) fail "the drill reported: $out" ;;
esac
echo "backup-smoke: ok"
