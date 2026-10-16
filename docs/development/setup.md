# Preparing a Mac

Everything here is done once per machine, and again after upgrading
Flutter, Xcode or Android Studio. The goal is `make doctor` exiting 0.

## Validated on 2026-10-04

The versions below ran every step of [mobile.md](mobile.md). Newer
patch versions are expected to work; record a new row here when you
validate a different combination.

| Tool | Version |
| ---- | ------- |
| macOS | 26.6.2 (Apple Silicon, arm64) |
| Flutter / Dart | 3.47.6 stable / 3.13.5 (Swift Package Manager feature on) |
| Xcode | 27.0 (27A266a), iOS simulator runtimes 27.0 and 18.6, iPhone 16 Pro |
| Android Studio SDK | platform android-37.0, build-tools 36.0.0, emulator 37.2.12, cmdline-tools latest |
| Android emulator image | `Medium_Phone_API_37.0` (Google APIs Play Store, arm64-v8a) |
| JDK | the one bundled with Android Studio (OpenJDK 25.0.3) |
| Docker | 29.8.2 |
| Go | 1.27.1 |

## Where to clone

Clone the repository **outside iCloud Drive**: `~/Documents` and
`~/Desktop` are often synced, and iCloud marks files in `app/build` with
attributes that make iOS code signing fail.
`~/Developer` or `~/code` are safe. If the clone must stay where it is,
move the build output out of iCloud once:

```sh
mkdir -p ~/Library/Caches/telinhasegura
mv app/build ~/Library/Caches/telinhasegura/app-build   # if it exists
ln -s ~/Library/Caches/telinhasegura/app-build app/build
```

## Steps

Run `make doctor` first: it prints Flutter's report, then one line per
project minimum, each `ok` or `FAIL` with the command that fixes it.

> **Run the `sudo` steps in a real terminal** (Terminal.app, iTerm).
> A tool or editor that runs commands without a terminal leaves `sudo`
> unable to ask for the password, and it fails with
> "a terminal is required to read the password".

1. **Select the full Xcode.** The Command Line Tools alone cannot build
   for iOS.
   `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
   → turns "Xcode selected" `ok`.
2. **Finish Xcode's first launch** (installs its system components).
   `sudo xcodebuild -runFirstLaunch` → "Xcode first launch done".
3. **Download an iOS simulator runtime** (several GB).
   `xcodebuild -downloadPlatform iOS` → "iOS simulator runtime".
4. **Install the Android command-line tools.** Android Studio →
   Settings → Languages & Frameworks → Android SDK → SDK Tools → check
   "Android SDK Command-line Tools (latest)" → Apply.
   → "Android cmdline-tools".
5. **Accept the Android licences.** `flutter doctor --android-licenses`.
   With the new Android CLI (2026) it may answer "The --licenses option
   is no longer needed"; that is fine. → "Android licences".
6. **Create an emulator** if `make emulators` lists none: Android Studio
   → Device Manager → Create device (a phone image for the latest API,
   arm64). The `make` targets default to `Medium_Phone_API_37.0`;
   pass `AVD=<name>` for another one.
7. **Start Docker Desktop** (or Colima) for `make api`.

## Expected `flutter doctor` warnings

- **"CocoaPods not installed."** Expected: this project resolves iOS
  plugins with Swift Package Manager only.
  Do not install CocoaPods to silence it.

## Why Swift Package Manager and not CocoaPods

Flutter enables Swift Package Manager by default and every iOS plugin
this app uses ships a `Package.swift`. SPM needs no Ruby toolchain, and
its lockfiles (`app/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`
and the one under `Runner.xcodeproj`) are versioned, so everyone builds
the same plugin versions. A plugin without SPM support would reopen the
decision.
