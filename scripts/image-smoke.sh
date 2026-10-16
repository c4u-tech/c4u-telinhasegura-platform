#!/bin/sh
# The API image's smoke test,
# run by CI's image job and by hand. It checks the image is not root,
# starts it against Postgres, waits for the image's own healthcheck, checks
# /livez reports the expected version, and that SIGTERM drains cleanly.
# usage: DATABASE_URL=... scripts/image-smoke.sh <image> <version>
# DATABASE_URL must reach Postgres from inside the container:
# host.docker.internal is mapped to the host.
set -eu
image="${1:?usage: scripts/image-smoke.sh <image> <version>}"
version="${2:?usage: scripts/image-smoke.sh <image> <version>}"
: "${DATABASE_URL:?DATABASE_URL is required}"
port="${SMOKE_PORT:-18080}"

user="$(docker image inspect -f '{{.Config.User}}' "$image")"
case "$user" in
  "" | root | 0 | root:* | 0:*)
    echo "image-smoke: the image runs as root (user '$user')" >&2
    exit 1 ;;
esac

c="$(docker run -d --add-host=host.docker.internal:host-gateway \
  -e DATABASE_URL -e APP_BASE_URL=https://app.test -e STAFF_MFA_REQUIRED=false \
  -p "127.0.0.1:$port:8080" "$image")"
trap 'docker rm -f "$c" >/dev/null 2>&1 || true' EXIT

fail() {
  echo "image-smoke: $1" >&2
  docker logs "$c" >&2 || true
  exit 1
}

i=0
until docker exec "$c" /api healthcheck 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || fail "the healthcheck never passed"
  sleep 1
done

body="$(curl -fsS "http://127.0.0.1:$port/livez")" || fail "/livez did not answer"
case "$body" in
  *"\"version\":\"$version\""*) ;;
  *) fail "/livez answered $body, want version $version" ;;
esac

# PID 1 is the API, so SIGTERM reaches the drain and the
# process exits 0 well before docker stop's 10s kill.
docker stop "$c" >/dev/null
code="$(docker inspect -f '{{.State.ExitCode}}' "$c")"
[ "$code" = 0 ] || fail "the API exited $code on SIGTERM, want 0"
echo "image-smoke: ok ($body)"
