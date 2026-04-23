# Gym Workout Tracker

Android Gym Workout Tracker built with Kotlin, Jetpack Compose, MVVM, Room, Coroutines/Flow, and Navigation Compose.

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

## Install Update Without Reinstall

```powershell
adb install -r app-debug.apk
```

Data is preserved only if:

- The app keeps the same `applicationId`.
- The APK is signed with the same signing key as the installed app.
- The new APK has a higher `versionCode` than the installed one.
