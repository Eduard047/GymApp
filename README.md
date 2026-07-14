# Gym Workout Tracker

Cross-platform Gym Workout Tracker with native Android and iOS applications,
plus Garmin, Wear OS, and browser companions.

## Public URLs

- Marketing site and PWA: https://gymapptracker.com/
- Support: https://gymapptracker.com/support.html
- Privacy policy: https://gymapptracker.com/privacy-policy.html

GitHub Releases remain the distribution source for downloadable Android, iOS
Simulator, and Garmin test artifacts.

## Current Feature Set

### Phone app

- Workout logging with multiple exercises, multiple sets, notes, and fast set shortcuts.
- Copy a previous workout day into a new draft, then adjust weights, reps, or remove/add sets during the workout.
- Repeat the latest workout as a quick template.
- Post-workout summary with XP gained, level progress, loaded muscle groups, top muscle of the day, and new PRs.
- Activity heatmap, rank/achievement progression, missions, and recent workout history.

### Native iOS app

- SwiftUI application in `ios/GymApp-iOS` with the same Supabase account and workout data.
- Password recovery, cloud sync, canonical XP/rank rules, muscle maps, activity heatmap, missions, and leaderboards.
- App Store privacy manifest, localized metadata, support/privacy pages, release validation, and archive scripts.
- Current public binary is a universal iOS Simulator build; a signed App Store IPA still requires Apple Distribution signing.

### Muscle Map

- Muscle load map with `All time`, `Month`, and `Week` filters.
- Tap a muscle group to see which exercises loaded it.
- Unmapped/new exercise list for exercises the app cannot confidently classify.
- Manual exercise-to-muscle mapping stored in the local Room database.
- Automatic recommendations based on training history:
  - stale muscle groups,
  - posterior-chain imbalance,
  - next suggested workout type such as push, pull, or legs with the actual muscles explained in the card.

### Backup, Import, And Diagnostics

Open `Exercises` and use `Backup and diagnostics`.

- `Export JSON` creates an importable backup of exercises and workouts.
- `Import JSON` restores workouts from an exported GymApp JSON backup.
- `Export redacted diagnostics` creates an aggregate-only support report without workout rows,
  exercise names, notes, account identifiers, or other backup content.
- `Share PDF report` creates a readable diagnostics report for sharing/debugging.

Important: diagnostics and PDF reports are for support only and cannot restore data. Only the
separate `Export JSON` backup is the source of truth for import/restore; review it before sharing
because it contains private workout data.

### Wear OS app

- Record workout sets from the watch.
- Numeric keypad editor for weight and reps, avoiding the system keyboard input bug.
- Haptic feedback on save/delete/quick controls.
- Quick presets for current-set weight and reps.
- Large current-set mode.
- Explicit sync status: idle, waiting phone, sent, failed.

### Garmin Fenix 8 Solar app

- Native Connect IQ app for the Fenix 8 Solar 47 mm 260x260 MIP display.
- Record exercises, weight, reps, and sets with the five hardware buttons.
- 90-second rest timer with vibration.
- Offline workout queue and two-way sync through Garmin Connect and the Android app.
- Source and build instructions: `garmin/README.md`.

## Download APK

<p align="center">
  <a href="https://github.com/Eduard047/GymApp/releases/latest">
    <img alt="Latest Build" src="https://img.shields.io/github/v/release/Eduard047/GymApp?include_prereleases&style=for-the-badge&label=Latest%20Build">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases">
    <img alt="Releases" src="https://img.shields.io/badge/Open-Releases-181717?style=for-the-badge&logo=github&logoColor=white">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases/download/debug-2026.07.12.1819/gymapp-phone-debug.apk">
    <img alt="Download Phone APK" src="https://img.shields.io/badge/Download-Phone%20APK-34A853?style=for-the-badge&logo=android&logoColor=white">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases/download/debug-2026.07.12.1819/GymApp-iOS-1.0.0-build1-Simulator-universal.app.zip">
    <img alt="Download iOS Simulator Build" src="https://img.shields.io/badge/Download-iOS%20Simulator-000000?style=for-the-badge&logo=apple&logoColor=white">
  </a>
</p>

<p align="center">
  Android debug builds for testing. If direct download fails, open Releases and download APK assets manually.
</p>

## Releases

- Releases page: https://github.com/Eduard047/GymApp/releases
- Latest release: https://github.com/Eduard047/GymApp/releases/latest
- Current store release tag: https://github.com/Eduard047/GymApp/releases/tag/release-2026.07.05.1238
- Current Play AAB: https://github.com/Eduard047/GymApp/releases/download/release-2026.07.05.1238/gymapp-play-release.aab
- Current cross-platform prerelease: https://github.com/Eduard047/GymApp/releases/tag/debug-2026.07.12.1819
- Current phone debug APK: https://github.com/Eduard047/GymApp/releases/download/debug-2026.07.12.1819/gymapp-phone-debug.apk
- Current iOS Simulator build: https://github.com/Eduard047/GymApp/releases/download/debug-2026.07.12.1819/GymApp-iOS-1.0.0-build1-Simulator-universal.app.zip
- Current Garmin IQ package: https://github.com/Eduard047/GymApp/releases/download/debug-2026.07.12.1819/gymapp-fenix8solar47mm.iq

When publishing a new phone build, upload the debug APK asset to the current release:

```text
app/build/outputs/apk/debug/app-debug.apk
```

For the native iOS source, open:

```sh
open ios/GymApp-iOS/GymApp.xcodeproj
```

The Garmin IQ attached to the cross-platform prerelease is byte-identical to
the verified `release-2026.07.05.1238` asset because Garmin source did not
change in this update.

## Build Update APK (preserve app data)

Use the helper script to build a debug APK with auto-generated version fields:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-update-apk.ps1
```

The script will:

1. Ensure `JAVA_HOME` is set (from environment, `java` in PATH, or common fallback locations).
2. Generate timestamp-based `versionCode`.
3. Generate datetime-based `versionName`.
4. Build with:

```powershell
./gradlew.bat :app:assembleDebug -PappVersionCode=<generated> -PappVersionName=<generated>
```

5. Copy output APK to project root as `app-debug.apk`.

For the normal module output used by GitHub Releases:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
.\gradlew.bat :app:assembleDebug :wear:assembleDebug
```

## Install Update Without Reinstall

```powershell
adb install -r app-debug.apk
```

Data is preserved only if:

- The app keeps the same `applicationId`.
- The APK is signed with the same signing key as the installed app.
- The new APK has a higher `versionCode` than the installed one.

For local debug builds from the module output:

```powershell
adb install -r -d .\app\build\outputs\apk\debug\app-debug.apk
```

For wireless debugging:

```powershell
adb pair <phone-ip>:<pairing-port> <pairing-code>
adb connect <phone-ip>:<connect-port>
adb -s <phone-ip>:<connect-port> install -r -d .\app\build\outputs\apk\debug\app-debug.apk
```

## iPhone PWA

The Android app cannot be installed on iPhone as an APK, so this repo also includes a standalone PWA in `pwa/`.

The PWA is a browser port of the phone app experience: workouts, workout detail, post-workout summary, exercises, exercise history, progress, missions, ranks, solo XP, activity heatmap, muscle map, smart workout generation, templates, local timers, JSON backup/import, and diagnostics export.

Run it locally:

```powershell
python -m http.server 4173 --directory .\pwa
```

Open:

```text
http://127.0.0.1:4173
```

To install on iPhone, host the `pwa/` folder over HTTPS, open the URL in Safari, then use `Share` -> `Add to Home Screen`.

The PWA stores workouts locally in the browser, syncs through Supabase when cloud login is enabled, and supports JSON export/import from the Exercises backup tools.

### Public-site and Auth cutover

The `pwa/CNAME` file prepares GitHub Pages for `gymapptracker.com`. Before
publishing it or changing Supabase Auth, verify that the apex domain serves the
first-party GymApp pages directly over HTTPS and does not redirect to a registrar
parking page. Do not send authentication callbacks to the custom domain until
that check passes.

After the DNS/Pages cutover, configure Supabase Auth with:

- Site URL: `https://gymapptracker.com/`
- Android redirect: `https://gymapptracker.com/confirmed.html?platform=android`
- Web redirect: `https://gymapptracker.com/confirmed.html?platform=web`
- iOS PKCE redirect allow-list pattern:
  `https://gymapptracker.com/confirmed.html?platform=ios&state=*`

Keep `https://eduard047.github.io/GymApp/confirmed.html` in the redirect allow
list and keep the legacy GitHub Pages callback functional while released Android
builds or already-sent confirmation emails can still use it. The legacy callback
forwards the existing Android implicit-flow fragment. The iOS route is separate:
it requires `platform=ios`, one 32-character base64url `state`, and forwards only
the PKCE `code` or bounded `error` fields after a user taps the bridge button.
It never accepts an implicit token fragment.

### Garmin cloud sync POC

The iPhone/PWA Garmin path uses Supabase as a queue and Garmin Connect Mobile as the watch network bridge:

1. Apply every ordered SQL file in `supabase/migrations/` through the normal
   Supabase migration workflow. The root `supabase-schema.sql` is a retired,
   fail-closed stub and must not be used.
2. Deploy the Edge Function:

```powershell
supabase functions deploy garmin-sync --project-ref owrcbsrectdgaotndtxy
```

3. In the PWA Add Workout screen, tap `Sync Watch`. The first run creates a Garmin device token and copies it.
4. Paste that token into the GymApp `Cloud Token` setting in Garmin Connect IQ Mobile.
5. On the watch, open settings and select `CLOUD / SYNC` to download the latest pending plan.

Run the no-device Garmin cloud sync checks:

```powershell
npm run test:garmin-cloud
```

### Supabase migration safety

Production is migration-managed. The exact privacy-hardening versions recorded in
production history are:

- `20260711084556_create_leaderboard_public.sql`
- `20260711084559_harden_gymapp_production_access.sql`
- `20260711090358_fix_user_state_revision_trigger.sql`

All three must remain ordered after the existing Garmin migrations. The first
adds the sanitized authenticated leaderboard and moderation tables; the second
removes cross-user direct `profiles` reads and anonymous table grants; the third
fixes the server-owned cloud-state revision trigger. Do not restore a
`Leaderboard is public` policy on `profiles`, the old `public.leaderboard`
view, or direct anonymous Garmin table access.
