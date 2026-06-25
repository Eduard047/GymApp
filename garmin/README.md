# GymApp for Garmin Fenix 8 Solar 47 mm

Connect IQ watch app targeting the `fenix8solar47mm` 260x260 MIP device.

## Current controls

- Main dashboard shows workout time, current heart rate, heart-rate zone bar, Gym kcal, and Garmin kcal.
- The app automatically estimates effort state from heart-rate trend: warmup, set active, rest, or ready.
- When the watch detects a likely completed set, the dashboard shows `LOG SET?`; tap/select logs the set with the currently selected exercise, weight, and reps.
- Tap/right/select from the dashboard opens the set entry screen.
- Set entry screen lets you pick exercise, adjust weight by 2.5 kg, adjust reps, and save a set.
- `START`: pause/resume the workout.
- `BACK` from dashboard: open pause menu.
- Pause menu has `RESUME`, `SAVE`, and `DISCARD`.
- `SAVE` opens a summary screen first; confirming there saves the Garmin FIT activity and sends the GymApp summary to the Android phone app.
- `DISCARD` exits without saving the Garmin activity or sending the GymApp workout.
- Finished workouts are queued locally until Garmin Connect can deliver them to the Android app.

## Workout data

- Garmin FIT activity is recorded as a strength-training workout through Connect IQ activity recording.
- GymApp calculates its own strength-focused kcal estimate and also shows Garmin's reported kcal for comparison.
- The phone app receives workout duration, Gym kcal, Garmin kcal, average/max HR, HR zones, set count, and debug state.
- Exercise name, weight, and reps still require the selected values on the watch; heart rate cannot reliably infer exercise/kg/reps by itself.

## Build prerequisites

1. Install Garmin Connect IQ SDK Manager and a current device SDK.
2. Generate a developer key through the Connect IQ tooling.
3. Set `GARMIN_DEVELOPER_KEY` to that key file.

Development build:

```powershell
.\scripts\build-garmin.ps1 -DeveloperKey "C:\path\to\developer_key.der"
```

Store export:

```powershell
.\scripts\build-garmin.ps1 -DeveloperKey "C:\path\to\developer_key.der" -Release
```

Android communication uses Garmin's official `ciq-companion-app-sdk` and requires Garmin Connect to be installed, running, and paired with the watch.

The Garmin app id is `A72A5B9F4E3D4E5A8B72C1D9F6123E40`; it must remain identical in `manifest.xml` and the Android bridge.
