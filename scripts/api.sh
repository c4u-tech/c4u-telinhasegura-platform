#!/bin/sh
# make api: Postgres in Docker (container ts-pg) and the Go API on :8080
# (HTTP_ADDR), as backend/README.md describes. Mail lands in
# backend/tmp/mail. The database is reached on the host port ts-pg
# publishes, not an assumed 5432 (another Postgres may hold it); a new ts-pg is
# created on TS_PG_PORT (default 55432).
set -eu
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is not running: start Docker Desktop, then run make api again." >&2
  exit 1
fi
if docker container inspect ts-pg >/dev/null 2>&1; then
  if ! err="$(docker start ts-pg 2>&1 >/dev/null)"; then
    echo "$err" >&2
    case "$err" in
      *"port is already allocated"*)
        echo "Another container or Postgres holds ts-pg's host port. Stop it, or recreate ts-pg on a free port (this drops its data): docker rm -f ts-pg && TS_PG_PORT=<port> make api" >&2 ;;
    esac
    exit 1
  fi
else
  docker run -d --name ts-pg -e POSTGRES_PASSWORD=postgres \
    -p "${TS_PG_PORT:-55432}:5432" postgres:17 >/dev/null
fi
# Over TCP: during its first start the image runs a temporary server on
# the socket only, then restarts; the API's single ping must not land
# in that window.
waited=0
until docker exec ts-pg pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; do
  if [ "$waited" -ge 60 ]; then
    echo "Postgres in ts-pg is not ready after 60 s; see: docker logs ts-pg" >&2
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done
port="$(docker port ts-pg 5432/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | head -n1)"
if [ -z "$port" ]; then
  echo "ts-pg publishes no host port for 5432. Recreate it (this drops its data): docker rm -f ts-pg && make api" >&2
  exit 1
fi
echo "Postgres (ts-pg) on localhost:$port; API on http://localhost:8080"
cd backend
# The staff MFA switch is on by default and needs a key: a local one, made once and kept in the git-ignored tmp/, so
# enrolled factors survive restarts.
mkdir -p tmp
if [ ! -s tmp/staff-mfa.key ]; then
  (umask 077 && openssl rand -base64 32 >tmp/staff-mfa.key)
fi
STAFF_MFA_KEY="${STAFF_MFA_KEY:-$(cat tmp/staff-mfa.key)}" \
  DATABASE_URL="postgres://postgres:postgres@localhost:$port/postgres?sslmode=disable" \
  APP_BASE_URL=http://localhost:5000 ALLOWED_ORIGINS=http://localhost:5000 \
  exec go run ./cmd/api
