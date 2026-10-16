# Development

How to get from a fresh clone to the app running on the Android emulator,
the iOS simulator and the web, against a local API.

| Page | Read it when |
| ---- | ------------ |
| [setup.md](setup.md) | preparing a Mac for the first time, or after a Flutter, Xcode or Android Studio upgrade |
| [mobile.md](mobile.md) | running, building or debugging the app on Android and iOS |
| [../../backend/README.md](../../backend/README.md) | running the API on its own, its environment variables |
| [../../app/README.md](../../app/README.md) | configuring Google and Apple sign-in (`--dart-define`) |
| [release-signing.md](release-signing.md) | signing the Android and iOS store builds |
| [open-repository.md](open-repository.md) | applying the GitHub repository settings: security, rulesets, the release App |

Read them in that order the first time: `setup.md` ends with `make doctor`
green, and `mobile.md` starts from there.

## The `make` targets

The gates (`make check`, `make fast`) are described in
[CONTRIBUTING.md](../../CONTRIBUTING.md#the-gate). The targets below are
development conveniences and never part of a gate.

| Target | Does |
| ------ | ---- |
| `make doctor` | `flutter doctor -v`, then this project's minimums, each with its fix |
| `make emulators` | lists the Android emulators and iOS simulators |
| `make api` | Postgres (Docker container `ts-pg`) and the Go API on `http://localhost:8080` |
| `make run-android` | boots the emulator if none runs, then `flutter run` in debug against `http://10.0.2.2:8080` |
| `make run-ios` | boots an iPhone simulator if none runs, waits until it is ready, then `flutter run` in debug on that simulator against `http://localhost:8080` |
| `make build-android` | release APK and app bundle, no store signing |
| `make build-ios` | release `Runner.app`, unsigned |

Variables: `AVD=` (default `Medium_Phone_API_37.0`), `ANDROID_DEVICE=`
(default `emulator`), `IOS_DEVICE=` (default: the simulator `make run-ios` boots, by UDID), `TS_PG_PORT=`
(the host port for a new `ts-pg`, default `55432`).

The scripts behind them live in [`scripts/`](../../scripts/). iOS plugins
resolve through Swift Package Manager only (no `Podfile`), and plain HTTP
to the local API is allowed in Android debug builds only.
