#!/bin/sh
# Builds the web app for the web image:
# no environment value, only RUNTIME_CONFIG, which makes the app read
# /config.json; CanvasKit served from the image, not a CDN.
set -eu
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn --dart-define=RUNTIME_CONFIG=true
