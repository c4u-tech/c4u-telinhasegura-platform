# telinha_segura

The Telinha Segura app: one Flutter package for Android, iOS and the web.

- **Run and build it:** [docs/development/](../docs/development/README.md)
  — machine setup, `make run-android` / `make run-ios`, release builds,
  troubleshooting.
- **Gates:** `make check` from the repository root.
- **Local defines:** copy `config/local.example.json` to
  `config/local.json` (git-ignored); the run targets read it.

## Google and Apple sign-in

Provider settings come only from `--dart-define` (never source
constants):

| Define | Value |
| ------ | ----- |
| `GOOGLE_CLIENT_ID` | iOS: the iOS client ID; web: the web client ID; Android: empty |
| `GOOGLE_SERVER_CLIENT_ID` | the web client ID (Android and iOS tokens use it as `aud`) |
| `APPLE_SERVICES_ID` | the Services ID of Apple's web flow |
| `APPLE_REDIRECT_URI` | Android: `<API>/v1/oauth/apple/callback`; web: the app origin registered with Apple |

On iOS, also set `GOOGLE_REVERSED_CLIENT_ID` in `ios/Flutter/*.xcconfig`.
The backend must accept the same IDs (`GOOGLE_CLIENT_IDS`,
`APPLE_CLIENT_IDS`; see `backend/README.md`).
