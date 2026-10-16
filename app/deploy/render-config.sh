#!/bin/sh
# Renders the web app's runtime configuration: <out-dir>/config.json, read by the app before it starts,
# and <out-dir>/headers.conf, the nginx security headers whose CSP names the
# API origin. Exits non-zero, so the container never serves, when
# API_BASE_URL is not a usable origin or a value would break the JSON.
# usage: render-config.sh <out-dir>
set -eu
out="${1:?usage: render-config.sh <out-dir>}"
fail() {
  echo "render-config: $1" >&2
  exit 1
}

api="${API_BASE_URL:-}"
api="${api%/}"
case "$api" in
  https://* | http://localhost | http://localhost:*) ;;
  *) fail "API_BASE_URL must be an https:// origin or http://localhost (got '$api')" ;;
esac
host="${api#*://}"
case "$host" in
  "" | *[!A-Za-z0-9.:-]*) fail "API_BASE_URL must be an origin: scheme, host and port only (got '$api')" ;;
esac

for name in GOOGLE_CLIENT_ID GOOGLE_SERVER_CLIENT_ID APPLE_SERVICES_ID APPLE_REDIRECT_URI; do
  eval "value=\${$name:-}"
  case "$value" in
    *'"'* | *'\'*) fail "$name contains a quote or a backslash" ;;
  esac
  [ "$(printf '%s' "$value" | tr -d '[:cntrl:]')" = "$value" ] ||
    fail "$name contains a control character"
done

mkdir -p "$out"
cat >"$out/config.json" <<EOF
{"apiBaseUrl":"$api","googleClientId":"${GOOGLE_CLIENT_ID:-}","googleServerClientId":"${GOOGLE_SERVER_CLIENT_ID:-}","appleServicesId":"${APPLE_SERVICES_ID:-}","appleRedirectUri":"${APPLE_REDIRECT_URI:-}"}
EOF

# Origins: Google Identity Services (developers.google.com/identity/gsi/web/
# guides/get-google-api-clientid#content_security_policy), Sign in with
# Apple JS, the YouTube embed, Flutter's fallback fonts. CanvasKit
# is served by the image (--no-web-resources-cdn).
csp="default-src 'self'"
# 'unsafe-inline' is for the YouTube player: youtube_player_iframe_web loads
# it as a srcdoc iframe that inherits this CSP, with a per-video inline script
# no fixed hash can cover. A self-hosted player page loaded by src would
# remove it.
csp="$csp; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://accounts.google.com/gsi/client https://appleid.cdn-apple.com https://www.youtube.com https://s.ytimg.com"
csp="$csp; style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style"
csp="$csp; img-src 'self' data: blob: $api https://i.ytimg.com"
csp="$csp; font-src 'self' https://fonts.gstatic.com"
csp="$csp; connect-src 'self' $api https://accounts.google.com/gsi/ https://fonts.gstatic.com https://appleid.apple.com"
csp="$csp; frame-src https://accounts.google.com/gsi/ https://appleid.apple.com https://www.youtube-nocookie.com https://www.youtube.com"
csp="$csp; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self' https://appleid.apple.com; frame-ancestors 'none'"

cat >"$out/headers.conf" <<EOF
add_header Cache-Control "no-cache" always;
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "$csp" always;
EOF
echo "render-config: configured for $api"
