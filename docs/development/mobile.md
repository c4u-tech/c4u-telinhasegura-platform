# Android and iOS

Running, building and debugging the app on the Android emulator and the
iOS simulator, against the local API. Prepare the machine first
([setup.md](setup.md)); `make doctor` should exit 0.

## 1. Quick start

```sh
make api                                                   # terminal 1: Postgres + API on :8080
cp app/config/local.example.json app/config/local.json     # once
make run-android                                           # terminal 2: emulator
make run-ios                                               # or: iOS simulator
```

The run targets boot a device when none is running, wait for it, and
start `flutter run` in debug. Hot reload (`r`), hot restart (`R`) and
quit (`q`) work in that terminal as usual.

## 2. Configuration

- **`app/config/local.json`** (git-ignored, copied from
  `local.example.json`) holds the sign-in defines: `GOOGLE_CLIENT_ID`,
  `GOOGLE_SERVER_CLIENT_ID`, `APPLE_SERVICES_ID`, `APPLE_REDIRECT_URI`.
  Empty values are fine: the app runs and email sign-in works. What
  each value means is in [app/README.md](../../app/README.md). Never
  commit real IDs to the example.
- **`API_BASE_URL` comes from the target, never from the file.** The
  Android emulator reaches the Mac at `10.0.2.2`, the iOS simulator and
  the web at `localhost`, so `make run-android` passes
  `http://10.0.2.2:8080` and `make run-ios` passes
  `http://localhost:8080`. Keeping it out of `local.json` avoids two
  sources for one define.
- The run targets stop before building when `local.json` is missing
  (naming the file to copy) or sets `API_BASE_URL`.

## 3. Release builds

```sh
make build-android ENV=prd   # app/build/app/outputs/flutter-apk/app-release.apk
                             # app/build/app/outputs/bundle/release/app-release.aab
make build-ios ENV=stg       # app/build/ios/iphoneos/Runner.app (unsigned)
```

`ENV` is `stg` or `prd` (default `prd`); anything else is refused. Each
build reads `app/config/<ENV>.json` through `--dart-define-from-file`, after
`tool/check_app_env.dart` has checked that every key is present and that
`API_BASE_URL` is an `https://` URL. The environment files are committed and
hold nothing secret; an empty OAuth ID turns that provider off. A mobile
release build also refuses to start against a non-HTTPS API. Signing is in
[`release-signing.md`](release-signing.md). Android release runs
(`flutter run --release`, `flutter build … --release`) now need the upload
key (`key.properties` or the four env vars); debug runs do not.

## 4. Debugging

- **Logs:** the `flutter run` terminal; `flutter logs` from another
  terminal; `adb logcat` for Android system logs; for iOS,
  `xcrun simctl spawn booted log stream --predicate 'process == "Runner"'`.
- **DevTools:** `flutter run` prints its URL; press `v` to open it.
- **Screenshots:**
  `adb exec-out screencap -p > shot.png` and
  `xcrun simctl io booted screenshot shot.png`.
- **Tapping from the command line:** Android has
  `adb shell input tap <x> <y>` and `adb shell input text '<text>'`
  (`%s` for a space); the iOS simulator has no equivalent built in, so
  iOS flows are walked by hand.
- **Fresh state:** `adb shell pm clear tech.coding4u.telinhasegura`;
  on iOS, delete the app from the simulator's home screen.

## 5. Emulator, simulator and web differ in

| | Android emulator | iOS simulator | Web |
| - | - | - | - |
| API host | `10.0.2.2` | `localhost` | `localhost` |
| Session | Bearer tokens in secure storage | Bearer tokens in Keychain | HttpOnly cookie + CSRF |
| Linked-device (child) mode | yes | yes | no |
| Session label | `Google sdk_gphone64_arm64` (maker + model) | `iPhone 16 Pro` (model name) | `Chrome no Mac` (browser + system) |

## 6. Development mail and email verification

The API writes every email as an `.eml` file under `backend/tmp/mail`
(`MAIL_DIR`); nothing is sent. The verification link points at the web
app (`APP_BASE_URL`, `http://localhost:5000`), which the mobile app
cannot open. On the emulator or simulator, confirm the token against the
API instead:

```sh
f=$(ls -t backend/tmp/mail/*.eml | head -1)
tok=$(grep -oE 'token=[A-Za-z0-9_%-]+' "$f" | head -1 | cut -d= -f2)
curl -s -X POST localhost:8080/v1/email-verifications/confirm \
  -H 'Content-Type: application/json' -d "{\"token\":\"$tok\"}"   # 204
```

Then sign in on the device. An account can also be created the same way
(`POST /v1/accounts` with `email`, `password` ≥ 15 characters and
`adult_declaration: true`).

## 7. Deep links without a camera

The kid-mode QR carries `telinhasegura://vincular?codigo=<code>`. To open
it on a device without scanning:

```sh
adb shell am start -W -a android.intent.action.VIEW \
  -d "telinhasegura://vincular?codigo=ABC123" tech.coding4u.telinhasegura
xcrun simctl openurl booted "telinhasegura://vincular?codigo=ABC123"
```

## 8. Google and Apple sign-in

Without provider IDs the buttons behave as unconfigured and email sign-in
covers every flow. To test them, fill `local.json`, set
`GOOGLE_REVERSED_CLIENT_ID` in `app/ios/Flutter/Debug.xcconfig` for iOS,
and give the API the same IDs (`GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS`,
`APP_ANDROID_PACKAGE`; see [backend/README.md](../../backend/README.md)).
Google on the Android emulator needs an image with Google Play services
("Google APIs" or "Google Play") and a signed-in Google account.

## 9. Network security

Plain HTTP to the local API is a debug-only exception:

- **Android:** `app/android/app/src/debug/res/xml/network_security_config.xml`
  allows cleartext to `10.0.2.2` and `localhost` only, wired from the
  debug manifest. The main and profile manifests carry no exception.
- **iOS:** none is needed: the simulator reaches `http://localhost`
  without an App Transport Security exception. A physical iPhone on the
  LAN would need one; that is out of scope.
- `app/test/platform/release_config_test.dart` (part of `make check`)
  fails if any Android manifest outside `src/debug`, `ios/Runner/Info.plist`
  or an `ios/Flutter/*.xcconfig` gains an exception. It reads the app's own
  files: an exception merged in from a plugin's manifest would pass it.

## 10. Troubleshooting

| Symptom | Cause and fix |
| ------- | ------------- |
| `make api`: `failed SASL auth: FATAL: password authentication failed for user "postgres"` | Another Postgres answers on the port `ts-pg` uses. `make api` reaches `ts-pg` on the port it publishes; if `docker port ts-pg` shows 5432 and another project's Postgres also holds 5432, recreate `ts-pg` on 55432 (this drops its data): `docker rm -f ts-pg && make api`. |
| `make api`: `Bind for 0.0.0.0:55432 failed: port is already allocated` | Another container or Postgres holds `ts-pg`'s host port. Stop it, or recreate `ts-pg` on a free port (drops its data): `docker rm -f ts-pg && TS_PG_PORT=<port> make api`. |
| `make api`: "Postgres in ts-pg is not ready after 60 s" | `docker logs ts-pg`; a container that keeps exiting is usually a port clash: `docker rm -f ts-pg && make api`. |
| `make api`: "Docker is not running" | Start Docker Desktop (or `colima start`). |
| `adb devices` shows `emulator-5554 offline` for minutes | The emulator fell back to software rendering (`lavapipe`/`swangle` in its log). `make run-android` boots with `-gpu host`; if you started it by hand, restart it with `emulator -avd <name> -gpu host`. |
| `make run-android`: "No Android emulator named …" | The default `AVD=Medium_Phone_API_37.0` is not on your machine. `make emulators` lists yours; run `make run-android AVD=<name>`. |
| "The emulator exited while booting" | Read the log path it prints. |
| `make run-android`: "local.json sets API_BASE_URL" | Remove `API_BASE_URL` from `app/config/local.json`; the target sets it. |
| "The emulator did not finish booting in 180 s" | Read the log path it prints; cold-boot with `emulator -avd <name> -gpu host -no-snapshot-load`. |
| The app shows "Não conseguimos falar com o servidor agora…" | The API is down (`make api`), or the device uses the wrong host: Android must use `10.0.2.2`, which `make run-android` sets. In a release build, cleartext is refused by design. |
| Android: `CLEARTEXT communication to … not permitted` | A host outside `10.0.2.2`/`localhost`, or a release/profile build. Use the debug run targets. |
| `make run-ios` prints "No simulator viewer found" and no window shows | The simulator runs headless; open the viewer from Xcode (Simulator.app up to Xcode 26, DeviceHub.app in Xcode 27, under `Xcode.app/Contents/Applications`). |
| "No iPhone simulator available" | `xcodebuild -downloadPlatform iOS`. |
| `xcode-select: error: tool 'xcodebuild' requires Xcode` | Step 1 of [setup.md](setup.md). |
| `flutter doctor`: "cmdline-tools component is missing" / "Android license status unknown" | Steps 4–5 of [setup.md](setup.md). |
| `flutter doctor`: "CocoaPods not installed" | Expected; see [setup.md](setup.md#expected-flutter-doctor-warnings). |
| iOS: `resource fork, Finder information, or similar detritus not allowed` / `Command CodeSign failed` | The clone is inside iCloud Drive. Move it out, or symlink `app/build` out of iCloud ([setup.md](setup.md#where-to-clone)). |
| iOS build stuck at "Xcode is fetching Swift Package Manager dependencies" | First build only; it downloads the plugins' packages. Later builds use the cache. |
| A session reads "Android" or "iPhone ou iPad" instead of the model | The device read failed or was slower than the sign-in's 1 s wait; the next sign-in names the model. |
| `sudo: a terminal is required to read the password` | The command ran without a terminal (from a tool or editor that does not attach one); run it in a real terminal. |
