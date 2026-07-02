# GymApp Agent Notes

- When the task is about updating Google Play, closed testing, Play Console, or a Play Store release, build the signed release Android App Bundle with `.\scripts\build-play-release-aab.ps1` and use `gymapp-play-release.aab`. Do not treat `app-debug.apk` as the Play artifact; debug APKs are only for local emulator/device checks.
