# GymApp for Garmin Fenix 8 Solar 47 mm

Connect IQ watch app targeting the `fenix8solar47mm` 260x260 MIP device.

## Current controls

- `UP` / `DOWN`: select a row.
- `START/ENTER`: next exercise, increase value, add set, or finish workout.
- `BACK`: previous exercise or decrease the selected numeric value.
- Adding a set starts a 90-second rest timer with vibration at completion.
- Finished workouts are queued locally until Garmin Connect can deliver them to the Android app.

## Build prerequisites

1. Install Garmin Connect IQ SDK Manager and a current device SDK.
2. Generate a developer key through the Connect IQ tooling.
3. Set `GARMIN_DEVELOPER_KEY` to that key file.

Development build:

```powershell
.\scripts\build-garmin.ps1
```

Store export:

```powershell
.\scripts\build-garmin.ps1 -Release
```

Android communication uses Garmin's official `ciq-companion-app-sdk` and requires Garmin Connect to be installed, running, and paired with the watch.

The Garmin app id is `A72A5B9F4E3D4E5A8B72C1D9F6123E40`; it must remain identical in `manifest.xml` and the Android bridge.
