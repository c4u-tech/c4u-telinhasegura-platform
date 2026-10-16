#!/bin/sh
# make doctor: Flutter's own report, then this project's minimums.
set -u
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
fail=0
check() {
  if eval "$2" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  FAIL $1 — $3"
    fail=1
  fi
}

flutter doctor -v
echo
echo "Project minimums:"
check "Flutter 3.47.x stable" "flutter --version | grep -q 'Flutter 3\.47\..*channel stable'" "install Flutter 3.47 stable"
check "Xcode selected" "xcode-select -p | grep -q 'Xcode.app'" "sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
check "Xcode first launch done" "xcodebuild -checkFirstLaunchStatus" "sudo xcodebuild -runFirstLaunch"
check "iOS simulator runtime" "xcrun simctl list runtimes | grep -q '^iOS'" "xcodebuild -downloadPlatform iOS"
check "Android cmdline-tools" "test -x '$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager'" "Android Studio > SDK Manager > SDK Tools > Android SDK Command-line Tools"
check "Android licences" "test -f '$ANDROID_HOME/licenses/android-sdk-license'" "flutter doctor --android-licenses"
check "An Android emulator (AVD)" "test -n \"\$('$ANDROID_HOME/emulator/emulator' -list-avds)\"" "Android Studio > Device Manager > Create device"
check "Docker running (for make api)" "docker info" "start Docker Desktop"
exit $fail
