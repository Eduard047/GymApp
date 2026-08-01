# GymApp for Garmin watches

Connect IQ watch app targeting the 108 API-compatible Garmin watches and wearable devices listed in `manifest.xml`. Products whose installed device package cannot satisfy the app's Connect IQ 3.2 minimum are intentionally excluded. The UI is drawn from a 260x260 baseline and scales positions/sizes from the active `dc.getWidth()` / `dc.getHeight()` values, so higher-resolution round screens such as Venu 3 do not render the layout as a tiny fixed-size block.

## Current controls

- Main dashboard uses a watch-first workout hierarchy: current heart rate and zone, elapsed time, Gym kcal, current planned set, exercise, weight/reps, and the live effort/rest status. Garmin kcal remains available in the workout summary.
- The app estimates effort from wrist movement plus heart-rate trend, with an automatic heart-rate-only fallback.
- When the watch detects a likely completed set, the dashboard shows `LOG SET?`; tap/select logs the set with the currently selected exercise, weight, and reps.
- After a set is saved, the last set can be undone for 5 seconds while the confirmation is visible. Tap the undo area, press `BACK`/`LAP`, swipe right, or use the left action on the save row. Undo also rolls back the set calorie correction and rest timer.
- Tap an empty dashboard area, or press right/select, to open the set entry screen.
- On touch watches, the exercise, weight, reps, save, and settings rows use full-width tap regions. Tap the left or right half of an adjustable row to decrease or increase it.
- On one- and two-button watches, next/previous moves between rows and select/start activates the highlighted row, so every action remains reachable without touch.
- On multi-button watches, up/down moves focus, left/right decreases/increases the selected value, and select/start performs the primary action.
- Set entry lets you pick exercise, adjust weight by the configured step, adjust reps, and save a set.
- On touch watches, swipe up/down to move focus, left to move to the next content screen, and right to go back.
- Debug screen shows the authoritative activity HR (`ACT`), direct sensor HR (`SNS`), movement score (`MOV`), confidence, effort state, kcal/min, and sync status.
- Settings screen lets you change auto-log on/off, auto-detect sensitivity, weight step, default rest time, and default reps.
- `SELECT` / `START`: perform the highlighted action.
- `BACK` or `MENU` from dashboard: pause the workout and open the pause menu.
- Pause menu has `RESUME`, `SAVE`, and `DISCARD`.
- `SAVE` opens a summary screen first; confirming there always saves the Garmin FIT activity, including workouts without manually logged sets or an Android phone connection. When the watch is securely paired with GymApp and sets were logged, the detailed GymApp summary is also queued for the phone.
- `DISCARD` opens an explicit warning screen. `KEEP WORKOUT` is selected by default, `BACK` cancels, and only `YES, DISCARD` exits without saving the Garmin activity or sending the GymApp workout.
- Finished workouts are queued locally until Garmin Connect can deliver them to the Android app.

## Workout data

- Garmin FIT activity is recorded as a strength-training workout through Connect IQ activity recording.
- GymApp calculates its own strength-focused kcal estimate and also shows Garmin's reported kcal for comparison.
- The phone app receives workout duration, Gym kcal, Garmin kcal, average/max HR, HR zones, and per-set duration, rest-before, start/peak/end HR, recovery drop, and detector confidence.
- Exercise name, weight, and reps still require the selected values on the watch; heart rate cannot reliably infer exercise/kg/reps by itself.

## Auto set detection

The watch estimates set/rest transitions from a bounded 10 Hz accelerometer movement score and heart-rate movement. The displayed HR remains Garmin's native current activity value (with direct sensor fallback); a three-sample median filter is used only for set/rest detection. Missing sensor data expires instead of leaving a stale number on screen, and a high but flat recovery heart rate cannot by itself start another set. Devices that cannot open the accelerometer stream automatically retain heart-rate-only detection.

Detection is expressed as low, medium, or high confidence. High-confidence evidence can start a detected set, while medium confidence is shown as `SET?` instead of being treated as completed. Raw accelerometer samples are held only for the callback, are bounded before processing, and are never persisted or synchronized.

The rest countdown is guidance rather than a paused tracking mode. FIT recording, heart-rate sampling, calorie tracking, and automatic detection continue during rest. When a new set is detected, the countdown ends immediately and the dashboard switches to `SET ACTIVE`.

- `LOW`: fewer false positives, waits longer before suggesting a logged set.
- `NORMAL`: default balance.
- `HIGH`: reacts sooner and can detect lighter/shorter sets, but may suggest more false positives.

When `LOG SET?` appears, tap/select saves the current exercise, weight, and reps as a set. If the suggestion is wrong, ignore it or turn `AUTO LOG` off in settings.

## Build prerequisites

1. Install Garmin Connect IQ SDK Manager and a current device SDK.
2. In SDK Manager, install every target device package you want to compile locally, for every target device listed in `manifest.xml`.
3. Generate a developer key through the Connect IQ tooling.
4. Set `GARMIN_DEVELOPER_KEY` to that key file.

Device development build:

```powershell
.\scripts\build-garmin.ps1 -DeveloperKey "C:\path\to\developer_key.der" -Device fenix8solar47mm
```

macOS development build:

```bash
./scripts/build-garmin.sh --developer-key /secure/developer_key.der --device fenix8solar47mm
```

Store export:

```powershell
.\scripts\build-garmin.ps1 -Release
```

```bash
./scripts/build-garmin.sh --release
```

The store export is written as `garmin/build/gymapp-garmin-connect-iq.iq`. It contains a device-specific binary for every compatible product declared in `manifest.xml`; it is not tied to the default development device name. A `.prg` development build remains device-specific and keeps that device in its filename.

Keep the RSA developer key outside the repository and back it up securely. Garmin requires the same key for every future update to an existing Connect IQ Store app.

Android communication uses Garmin's official `ciq-companion-app-sdk` and requires Garmin Connect to be installed, running, and paired with the watch.

The Garmin app id is `A72A5B9F4E3D4E5A8B72C1D9F6123E40`; it must remain identical in `manifest.xml` and the Android bridge.
