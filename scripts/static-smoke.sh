#!/bin/sh
# Smoke test of the web app and site images, run by CI's images job and by
# hand.
# usage: scripts/static-smoke.sh <image> web|site
set -eu
image="${1:?usage: scripts/static-smoke.sh <image> web|site}"
kind="${2:?usage: scripts/static-smoke.sh <image> web|site}"
port="${SMOKE_PORT:-18081}"
c=""
trap '[ -z "$c" ] || docker rm -f "$c" >/dev/null 2>&1 || true' EXIT

fail() {
  echo "static-smoke: $1" >&2
  [ -z "$c" ] || docker logs "$c" >&2 || true
  exit 1
}

user="$(docker image inspect -f '{{.Config.User}}' "$image")"
case "$user" in
  "" | root | 0 | root:* | 0:*) fail "the image runs as root (user '$user')" ;;
esac

start() {
  c="$(docker run -d -p "127.0.0.1:$port:8080" "$@" "$image")"
  i=0
  until curl -fsS -o /dev/null "http://127.0.0.1:$port/"; do
    i=$((i + 1))
    [ "$i" -lt 30 ] || fail "the image never answered on /"
    sleep 1
  done
}

# The container exits non-zero and never serves.
refuses() {
  r="$(docker run -d "$@" "$image")"
  i=0
  while [ "$(docker inspect -f '{{.State.Running}}' "$r")" = true ]; do
    i=$((i + 1))
    [ "$i" -lt 20 ] || { docker rm -f "$r" >/dev/null; fail "the container kept running with $*"; }
    sleep 1
  done
  code="$(docker inspect -f '{{.State.ExitCode}}' "$r")"
  docker rm -f "$r" >/dev/null
  [ "$code" != 0 ] || fail "the container exited 0 with $*"
}

headers() { curl -sS -D - -o /dev/null "http://127.0.0.1:$port$1" | tr -d '\r'; }
status() { curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$1"; }

has_header() {
  headers "$1" | grep -qi "^$2" || fail "$1 lacks the header '$2'"
}

common_headers() {
  for path in "$@"; do
    has_header "$path" 'cache-control: no-cache'
    has_header "$path" 'etag: '
    has_header "$path" 'strict-transport-security: max-age=31536000'
    has_header "$path" 'x-content-type-options: nosniff'
    has_header "$path" 'referrer-policy: strict-origin-when-cross-origin'
    has_header "$path" "content-security-policy: default-src 'self'"
  done
}

case "$kind" in
  web)
    refuses -e API_BASE_URL=
    refuses -e API_BASE_URL=ftp://api.test
    refuses -e API_BASE_URL=https://api.test/v1
    refuses -e API_BASE_URL=https://api.test -e 'GOOGLE_CLIENT_ID=a"b'
    start -e API_BASE_URL=https://api.test -e GOOGLE_CLIENT_ID=g1
    body="$(curl -fsS "http://127.0.0.1:$port/config.json")" || fail "/config.json did not answer"
    case "$body" in
      *'"apiBaseUrl":"https://api.test"'*'"googleClientId":"g1"'*'"appleServicesId":""'*) ;;
      *) fail "/config.json answered $body" ;;
    esac
    has_header /config.json 'content-type: application/json'
    [ "$(status /verificar-email)" = 200 ] || fail "/verificar-email did not fall back to the app"
    curl -fsS "http://127.0.0.1:$port/verificar-email" | grep -q flutter_bootstrap.js ||
      fail "/verificar-email did not serve index.html"
    common_headers / /config.json /verificar-email
    has_header / "content-security-policy: .*connect-src 'self' https://api.test "
    ;;
  site)
    start
    # Every page answers; its files carry their types.
    for page in / /privacidade /termos /suporte /excluir-conta /participe /curadoria; do
      [ "$(status "$page")" = 200 ] || fail "$page did not answer 200"
    done
    has_header /fonts/bricolage-grotesque.woff2 'content-type: font/woff2'
    [ "$(status /apoie)" = 301 ] || fail "/apoie did not redirect"
    has_header /apoie 'location: .*/participe'
    has_header /site.css 'content-type: text/css'
    [ "$(status /nao-existe)" = 404 ] || fail "an unknown path did not answer 404"
    curl -sS "http://127.0.0.1:$port/nao-existe" | grep -q 'Página não encontrada' ||
      fail "the 404 page is not 404.html"
    common_headers /
    has_header / "content-security-policy: default-src 'self'; frame-ancestors 'none'"
    ;;
  *) fail "unknown kind $kind (web or site)" ;;
esac
echo "static-smoke: ok ($kind)"
