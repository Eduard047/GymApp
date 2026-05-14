# Gym Workout Tracker

Android Gym Workout Tracker built with Kotlin, Jetpack Compose, MVVM, Room, Coroutines/Flow, and Navigation Compose.

## Current Feature Set

### Phone app

- Workout logging with multiple exercises, multiple sets, notes, and fast set shortcuts.
- Copy a previous workout day into a new draft, then adjust weights, reps, or remove/add sets during the workout.
- Repeat the latest workout as a quick template.
- Post-workout summary with XP gained, level progress, loaded muscle groups, top muscle of the day, and new PRs.
- Activity heatmap, rank/achievement progression, missions, and recent workout history.

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
- `Send diagnostics / DB snapshot` creates the same full JSON snapshot with extra summary metadata.
- `Share PDF report` creates a readable diagnostics report for sharing/debugging.

Important: PDF is for reading and sharing only. JSON is the source of truth for import/restore.

### Wear OS app

- Record workout sets from the watch.
- Numeric keypad editor for weight and reps, avoiding the system keyboard input bug.
- Haptic feedback on save/delete/quick controls.
- Quick presets for current-set weight and reps.
- Large current-set mode.
- Explicit sync status: idle, waiting phone, sent, failed.

## Download APK

<p align="center">
  <a href="https://github.com/Eduard047/GymApp/releases/tag/debug-v20260423">
    <img alt="Latest Build" src="https://img.shields.io/github/v/release/Eduard047/GymApp?include_prereleases&style=for-the-badge&label=Latest%20Build">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases">
    <img alt="Releases" src="https://img.shields.io/badge/Open-Releases-181717?style=for-the-badge&logo=github&logoColor=white">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases/download/debug-v20260423/GymApp-phone-debug.apk">
    <img alt="Download Phone APK" src="https://img.shields.io/badge/Download-Phone%20APK-34A853?style=for-the-badge&logo=android&logoColor=white">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases/download/debug-v20260423/GymApp-watch-debug.apk">
    <img alt="Download Watch APK" src="https://img.shields.io/badge/Download-Watch%20APK-3D7DFF?style=for-the-badge&logo=wearos&logoColor=white">
  </a>
</p>

<p align="center">
  Android debug builds for testing. If direct download fails, open Releases and download APK assets manually.
</p>

## Releases

- Releases page: https://github.com/Eduard047/GymApp/releases
- Current release tag: https://github.com/Eduard047/GymApp/releases/tag/debug-v20260423
- Current phone debug APK: https://github.com/Eduard047/GymApp/releases/download/debug-v20260423/GymApp-phone-debug.apk
- Current watch debug APK: https://github.com/Eduard047/GymApp/releases/download/debug-v20260423/GymApp-watch-debug.apk

When publishing a new phone build, replace `GymApp-phone-debug.apk` in the current release with:

```text
app/build/outputs/apk/debug/app-debug.apk
```

When publishing a new watch build, replace `GymApp-watch-debug.apk` with:

```text
wear/build/outputs/apk/debug/wear-debug.apk
```

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
