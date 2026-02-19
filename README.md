# Gym Workout Tracker

Android Gym Workout Tracker built with Kotlin, Jetpack Compose, MVVM, Room, Coroutines/Flow, and Navigation Compose.

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
