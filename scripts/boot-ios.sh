#!/bin/sh
# Boots the first available iPhone simulator unless one is booted, waits
# until it is ready, shows it, and prints its UDID on stdout (all other
# messages go to stderr) so make run-ios targets exactly that simulator,
# never a physical iPhone that matches by name. The viewer moved between
# Xcode versions (Simulator.app up to Xcode 26, DeviceHub.app in Xcode
# 27), so the script opens whichever the selected Xcode has; the
# simulator runs without a window otherwise.
set -eu
udid="$(xcrun simctl list devices booted | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
if [ -z "$udid" ]; then
  udid="$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
  if [ -z "$udid" ]; then
    echo "No iPhone simulator available: xcodebuild -downloadPlatform iOS" >&2
    exit 1
  fi
  echo "Booting the iOS simulator $udid..." >&2
  xcrun simctl boot "$udid"
fi
xcrun simctl bootstatus "$udid" -b >/dev/null
xcode="$(xcode-select -p)/.."
viewer=""
for app in "$xcode/Developer/Applications/Simulator.app" "$xcode/Applications/DeviceHub.app"; do
  if [ -d "$app" ]; then viewer="$app"; break; fi
done
if [ -n "$viewer" ]; then
  open "$viewer"
else
  echo "No simulator viewer found; the simulator runs without a window." >&2
fi
echo "$udid"
