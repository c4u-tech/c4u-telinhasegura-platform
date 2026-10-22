# Release signing

Runbook for the maintainer who signs the store builds. Nothing here is
committed: keystores, `key.properties` and passwords stay out of the
repository (`app/android/.gitignore` already ignores them).

## Android

A release build refuses to run without the upload key. It never falls back to
the debug key.
Android release runs (`flutter run --release`, `flutter build … --release`)
now need the upload key (`key.properties` or the four env vars); debug runs
do not.

1. Generate the upload key:

   ```bash
   keytool -genkeypair -v -keystore ~/telinhasegura-upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload
   ```

2. Write `app/android/key.properties` (git-ignored):

   ```properties
   storeFile=/Users/you/telinhasegura-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

   In CI the same four values come from `ANDROID_KEYSTORE_PATH`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.
   A relative `storeFile` resolves against `app/android/`.

3. Back up the `.jks` and both passwords in the password manager, never in
   the repository.
4. Create the app in Play Console with package `tech.coding4u.telinhasegura`
   and enrol in Play App Signing (Google-generated app key).
5. Build and upload the first bundle: `make build-android ENV=prd`.

Lost upload key: Play Console, "Request upload key reset".

## iOS

1. Set the Team ID in `app/ios/Flutter/Team.xcconfig`.
2. Open `ios/Runner.xcworkspace` once so automatic signing creates the
   profiles.
3. The App ID needs the Sign in with Apple capability.
4. Create the Sign in with Apple key (Keys, +, "Sign in with Apple", primary
   App ID `tech.coding4u.telinhasegura`) and set `APPLE_TEAM_ID`,
   `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` on the API before
   `APPLE_CLIENT_IDS`.

## Store releases

An app release (the `app-vX.Y.Z` tag release-please makes on `prd`) triggers
the `store` workflow. It builds one version and uploads it to both Play internal
testing and TestFlight with the same build number, then waits for approval in
the `store-production` environment before promoting that same build to
production.

The `rollout` workflow moves the Play rollout percentages and runs manually
from `prd`.

The store lanes live in `app/fastlane` and require Ruby 3.3 with `bundle
install` in `app/`.

The workflows read these variables:
- `PLAY_WIF_PROVIDER`: Workload identity provider for Play.
- `PLAY_SERVICE_ACCOUNT`: Service account email for Play.
- `ASC_KEY_ID`: App Store Connect key ID.
- `ASC_ISSUER_ID`: App Store Connect issuer ID.
- `MATCH_GIT_URL`: Private repository for iOS certificates and profiles.
- `PLAY_RELEASE_STATUS`: Play app release status.

And these secrets:
- `ASC_KEY_P8`: App Store Connect private key.
- `MATCH_PASSWORD`: Password for the private match repository.
- `MATCH_GIT_PRIVATE_KEY`: Private key to read the match repository.
- `ANDROID_UPLOAD_KEYSTORE_B64`: Upload keystore base64-encoded.
- `ANDROID_KEYSTORE_PASSWORD`: Upload keystore password.
- `ANDROID_KEY_ALIAS`: Upload key alias.
- `ANDROID_KEY_PASSWORD`: Upload key password.

The `match` tool keeps the iOS distribution certificate and profiles in a
private repository. CI reads it read-only.

From a workstation, run `make release-android` or `make release-ios` with
`BUILD_NUMBER` set to the build number (obtained from the lanes):

```bash
cd app && bundle exec fastlane build_number
make release-android BUILD_NUMBER=123
make release-ios BUILD_NUMBER=123
```
