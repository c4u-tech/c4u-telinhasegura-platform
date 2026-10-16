#!/bin/sh
# Verifies a deploy: the API's /livez
# reports the deployed revision, the web app's /config.json names its
# environment's API, the site answers. CapRover deploys detached, so each
# check retries (VERIFY_TRIES x VERIFY_PAUSE s, 3 minutes by default).
# usage: scripts/deploy-verify.sh <stg|prd> <api-revision> <component>...
set -eu
fail() {
  echo "deploy-verify: $1" >&2
  exit 1
}
[ "$#" -ge 3 ] || fail "usage: scripts/deploy-verify.sh <stg|prd> <api-revision> <component>..."
case "$1" in
  prd) prefix="" ;;
  stg) prefix="stg." ;;
  *) fail "unknown environment '$1'" ;;
esac
revision="$2"
shift 2
domain=telinhasegura.coding4u.tech
api="https://${prefix}api.$domain"
web="https://${prefix}app.$domain"
site="https://$prefix$domain"
tries="${VERIFY_TRIES:-36}"
pause="${VERIFY_PAUSE:-5}"

check() {
  name="$1"
  url="$2"
  want="$3"
  i=0
  while :; do
    body="$(curl -fsS -m 10 "$url" 2>/dev/null || true)"
    case "$body" in
      *"$want"*)
        echo "deploy-verify: $name ok ($url)"
        return 0 ;;
    esac
    i=$((i + 1))
    [ "$i" -lt "$tries" ] || fail "$name at $url never answered '$want' (last: ${body:-no answer})"
    sleep "$pause"
  done
}

for c in "$@"; do
  case "$c" in
    api) check api "$api/livez" "\"version\":\"$revision\"" ;;
    web) check web "$web/config.json" "\"apiBaseUrl\":\"$api\"" ;;
    site) check site "$site/" "<html" ;;
    backup) echo "deploy-verify: backup has no endpoint; its heartbeat watches it" ;;
    *) fail "unknown component '$c'" ;;
  esac
done
