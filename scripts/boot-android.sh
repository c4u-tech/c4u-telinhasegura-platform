#!/bin/sh
# Boots $1 (an AVD name) unless an emulator is already listed, then waits
# until the emulator reports the boot complete, whether this script
# started it or not. The host GPU is forced: on Apple Silicon "auto" can
# fall back to software rendering, and the boot then never completes.
# `adb -e` targets the emulator, so a phone plugged in at the same time
# does not break the wait.
set -eu
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
LOG="${TMPDIR:-/tmp}/telinhasegura-emulator.log"
pid=""
# A starved host freezes the emulator, on any GPU mode or image, until
# Android's watchdog kills system_server and the app with it. Two signs: the swap nearly full, or a load average
# over twice the cores (iCloud and Spotlight re-scanning ~/Documents, a
# make check). Warn, don't stop: the developer decides whether to wait.
swap="${SWAPUSAGE:-$(sysctl -n vm.swapusage 2>/dev/null || true)}"
used_pct=$(echo "$swap" | awk '{ t = $3 + 0; u = $6 + 0; if (t > 0) printf "%d", u * 100 / t }')
if [ -n "$used_pct" ] && [ "$used_pct" -ge 80 ]; then
  echo "Warning: the Mac's swap is ${used_pct}% full; the emulator may freeze. Free memory or restart the Mac first." >&2
fi
load="${LOADAVG:-$(sysctl -n vm.loadavg 2>/dev/null || true)}"
cores="${NCPU:-$(sysctl -n hw.ncpu 2>/dev/null || echo 0)}"
busy=$(echo "$load" | awk -v c="$cores" '{ l = $2 + 0; if (c > 0 && l > 2 * c) printf "%d", l }')
if [ -n "$busy" ]; then
  echo "Warning: the Mac's load average is ${busy} on ${cores} cores; the emulator may freeze. Wait for it to settle first." >&2
fi
if ! "$ADB" devices | grep -q '^emulator-'; then
  if ! "$EMULATOR" -list-avds | grep -qx "$1"; then
    echo "No Android emulator named $1. Pass AVD=<name>; make emulators lists them." >&2
    exit 1
  fi
  echo "Booting the Android emulator $1 (log: $LOG)..."
  nohup "$EMULATOR" -avd "$1" -gpu host >"$LOG" 2>&1 &
  pid=$!
fi
waited=0
until [ "$("$ADB" -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "The emulator exited while booting; see $LOG" >&2
    exit 1
  fi
  if [ "$waited" -ge 180 ]; then
    echo "The emulator did not finish booting in 180 s; see $LOG" >&2
    exit 1
  fi
  sleep 3
  waited=$((waited + 3))
done
