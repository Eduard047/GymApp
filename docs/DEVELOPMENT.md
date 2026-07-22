# Development guide

This guide keeps build and validation commands out of the project landing page.
Production credentials, signing files, real user data, and local backups must
never be stored in this repository.

## Toolchains

| Surface | Primary tools |
| --- | --- |
| Android | Android Studio, JDK 21, Android SDK, Gradle wrapper |
| iOS | Xcode 26 with an iOS Simulator runtime |
| PWA and contracts | Node.js 24; Python 3 or another static file server |
| Garmin | Connect IQ SDK Manager and a developer key outside the repository |
| Supabase | Supabase CLI and Deno for Edge Function checks |

## Validation

Cross-platform contract tests:

```sh
node --test tests/*.test.mjs
```

Android phone tests and debug build:

```sh
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

iOS commands and release prerequisites are documented in
[`ios/GymApp-iOS/README.md`](../ios/GymApp-iOS/README.md).

Garmin device builds and the multi-device Store export are documented in
[`garmin/README.md`](../garmin/README.md).

## Local PWA

Serve the static application from the repository root:

```sh
python3 -m http.server 4173 --directory pwa
```

Open <http://127.0.0.1:4173>. Browser storage, imported backups, profile fields,
exercise names, query parameters, and cloud responses must always be treated as
untrusted input.

## Android release artifacts

Production Android artifacts must use the existing release identity and the
checked-in version from `gradle.properties`.

Build the direct-install APK with PowerShell:

```powershell
./scripts/build-phone-release-apk.ps1
```

Build the Google Play AAB with PowerShell:

```powershell
./scripts/build-play-release-aab.ps1
```

The expected outputs are `gymapp-phone-release.apk` and
`gymapp-play-release.aab`. They are ignored local artifacts and must be verified
before upload. A debug APK is never a Play or production artifact.

## Release verification

Before publication:

1. Run the relevant native and contract tests.
2. Verify package IDs, versions, signing identities, exported components, and
   archive contents.
3. Generate and verify SHA-256 checksums.
4. Scan the outgoing Git range and release files for credentials and private
   data.
5. Keep database migrations and Edge Function deployment as separately reviewed
   privileged operations.

See [`docs/OPERATIONS.md`](OPERATIONS.md) for deployment boundaries and
[`.github/SECURITY.md`](../.github/SECURITY.md) for the release security gate.
