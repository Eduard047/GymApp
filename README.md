# Gym Workout Tracker

Android Gym Workout Tracker built with Kotlin, Jetpack Compose, MVVM, Room, Coroutines/Flow, and Navigation Compose.

## Download APK

<p align="center">
  <a href="https://github.com/Eduard047/GymApp/releases/tag/debug-v1774304282">
    <img alt="Latest Build" src="https://img.shields.io/github/v/tag/Eduard047/GymApp?style=for-the-badge&label=Latest%20Build">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases/latest">
    <img alt="Releases" src="https://img.shields.io/badge/Open-Releases-181717?style=for-the-badge&logo=github&logoColor=white">
  </a>
  <a href="https://github.com/Eduard047/GymApp/releases/download/debug-v1774304282/app-debug.apk">
    <img alt="Download APK" src="https://img.shields.io/badge/Download-APK-34A853?style=for-the-badge&logo=android&logoColor=white">
  </a>
</p>

<p align="center">
  Android debug build for testing. If direct download fails, open Releases and download the APK asset manually.
</p>

## Releases

- Latest releases page: https://github.com/Eduard047/GymApp/releases/latest
- Current debug APK: https://github.com/Eduard047/GymApp/releases/download/debug-v1774304282/app-debug.apk

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
