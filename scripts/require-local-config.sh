#!/bin/sh
# Stops a run target before building when the local defines are missing
# or when they carry API_BASE_URL, which each run target sets itself (one
# source per define).
set -eu
if [ ! -f app/config/local.json ]; then
  echo "Missing app/config/local.json." >&2
  echo "Copy it first: cp app/config/local.example.json app/config/local.json" >&2
  exit 1
fi
if grep -q '"API_BASE_URL"' app/config/local.json; then
  echo "app/config/local.json sets API_BASE_URL; remove it: each run target sets it (10.0.2.2 on Android, localhost on iOS)." >&2
  exit 1
fi
