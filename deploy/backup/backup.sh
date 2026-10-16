#!/bin/sh
# The database backup.
#   backup run        validate, then the daily schedule (supercronic)
#   backup run-once   pg_dump -Fc | age -r | rclone to incoming/, copied to
#                     daily/ once the dump and the encryption exited 0,
#                     copied to weekly/ on Sundays, then the heartbeat
#   backup restore <name|latest> <target-database-url>
#                     daily/<name> decrypted with $AGE_IDENTITY_FILE into
#                     pg_restore
# The bucket is the rclone remote "store", an S3 API configured from the
# BACKUP_* variables: Google Cloud Storage by default (an HMAC key),
# BACKUP_S3_ENDPOINT and BACKUP_S3_PROVIDER for another S3 server (the
# smoke test points them at a local one). Nothing here needs a delete, so a
# key that may only create and read objects is enough, and nothing here
# prints a credential.
set -eu

fail() {
  echo "backup: $1" >&2
  exit 1
}

require() {
  for name in "$@"; do
    eval "value=\${$name:-}"
    [ -n "$value" ] || fail "$name is required"
  done
}

remote() {
  require BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY BACKUP_BUCKET
  export RCLONE_CONFIG_STORE_TYPE=s3
  export RCLONE_CONFIG_STORE_PROVIDER="${BACKUP_S3_PROVIDER:-GCS}"
  export RCLONE_CONFIG_STORE_ENDPOINT="${BACKUP_S3_ENDPOINT:-https://storage.googleapis.com}"
  export RCLONE_CONFIG_STORE_REGION=auto
  export RCLONE_CONFIG_STORE_ACCESS_KEY_ID="$BACKUP_S3_ACCESS_KEY_ID"
  export RCLONE_CONFIG_STORE_SECRET_ACCESS_KEY="$BACKUP_S3_SECRET_ACCESS_KEY"
  export RCLONE_CONFIG_STORE_NO_CHECK_BUCKET=true
  bucket="store:$BACKUP_BUCKET"
}

heartbeat() {
  curl -fsS -m 10 --retry 3 -o /dev/null "$BACKUP_HEARTBEAT_URL$1" ||
    echo "backup: the heartbeat ping failed" >&2
}

# upload <name>: stream the encrypted dump to incoming/, then copy it to
# daily/ only if pg_dump and age both exited 0 (a dump that dies mid-stream
# still ends the pipe cleanly). The staged copy is then dropped where the key
# may delete; elsewhere the bucket's lifecycle clears it.
upload() {
  st="$(mktemp -d "${TMPDIR:-/tmp}/backup.XXXXXX")" || return 1
  { rc=0; pg_dump -Fc --no-password --dbname="$DATABASE_URL" || rc=$?; echo "$rc" >"$st/dump"; } |
    { rc=0; age -r "$AGE_RECIPIENT" || rc=$?; echo "$rc" >"$st/age"; } |
    rclone rcat "$bucket/incoming/$1" &&
    [ "$(cat "$st/dump")" = 0 ] && [ "$(cat "$st/age")" = 0 ] &&
    rclone copyto "$bucket/incoming/$1" "$bucket/daily/$1"
  code=$?
  [ "$code" != 0 ] || rclone deletefile "$bucket/incoming/$1" >/dev/null 2>&1 || true
  rm -rf "$st"
  return "$code"
}

# aborted: a TERM or INT (a container stop) mid-backup leaves nothing behind
# and still pings the failure.
aborted() {
  trap - TERM INT
  rm -rf "${st:-}"
  rclone deletefile "$bucket/incoming/$name" >/dev/null 2>&1 || true
  heartbeat /fail
  fail "the backup was interrupted; nothing was kept under daily/$name"
}

run_once() {
  require DATABASE_URL AGE_RECIPIENT BACKUP_HEARTBEAT_URL
  remote
  name="$(date -u +%Y-%m-%dT%H%MZ).dump.age"
  echo "backup: dumping to daily/$name"
  trap aborted TERM INT
  if ! upload "$name"; then
    rclone deletefile "$bucket/incoming/$name" >/dev/null 2>&1 || true
    heartbeat /fail
    fail "the backup failed; nothing was kept under daily/$name"
  fi
  trap - TERM INT
  if [ "$(TZ=America/Sao_Paulo date +%u)" = 7 ] &&
    ! rclone copyto "$bucket/daily/$name" "$bucket/weekly/$name"; then
    heartbeat /fail
    fail "daily/$name was written, but its weekly copy failed"
  fi
  heartbeat ""
  echo "backup: ok, daily/$name"
}

restore() {
  [ "$#" -eq 2 ] || fail "usage: backup restore <name|latest> <target-database-url>"
  require AGE_IDENTITY_FILE
  remote
  name="$1"
  if [ "$name" = latest ]; then
    list="$(rclone lsf "$bucket/daily/")" || fail "could not list daily/"
    name="$(printf '%s\n' "$list" | sort | tail -n 1)"
    [ -n "$name" ] || fail "no dump under daily/"
  fi
  echo "backup: restoring daily/$name"
  st="$(mktemp -d "${TMPDIR:-/tmp}/backup.XXXXXX")" || fail "could not make a temporary directory"
  if { rc=0; rclone cat "$bucket/daily/$name" || rc=$?; echo "$rc" >"$st/cat"; } |
    { rc=0; age -d -i "$AGE_IDENTITY_FILE" || rc=$?; echo "$rc" >"$st/age"; } |
    pg_restore --no-owner --no-privileges --exit-on-error --dbname="$2" &&
    [ "$(cat "$st/cat")" = 0 ] && [ "$(cat "$st/age")" = 0 ]; then
    rm -rf "$st"
    echo "backup: restored daily/$name"
  else
    rm -rf "$st"
    fail "the restore of daily/$name failed"
  fi
}

case "${1:-}" in
  run)
    require DATABASE_URL AGE_RECIPIENT BACKUP_HEARTBEAT_URL
    remote
    exec supercronic /etc/backup/crontab ;;
  run-once) run_once ;;
  restore)
    shift
    restore "$@" ;;
  *) fail "usage: backup run | run-once | restore <name|latest> <target-database-url>" ;;
esac
