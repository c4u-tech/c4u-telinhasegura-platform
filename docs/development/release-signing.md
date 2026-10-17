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
