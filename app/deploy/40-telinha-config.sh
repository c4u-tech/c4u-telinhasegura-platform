#!/bin/sh
# Renders /config.json and the headers before nginx starts.
set -eu
/usr/local/bin/render-config.sh /tmp/telinha
