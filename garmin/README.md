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
- Exercise choice is free-order: saving a set keeps the selected exercise and loads only that exercise's next optional plan target. Moving to another exercise is always an explicit athlete action, and the picker retains bounded catalog exercises outside the current plan.
- On touch watches, swipe up/down to move focus, left to move to the next content screen, and right to go back.
- Debug screen shows the authoritative activity HR (`ACT`), direct sensor HR (`SNS`), movement score (`MOV`), confidence, effort state, kcal/min, and sync status where the device memory ceiling permits it.
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
- Completed sets are committed once to the atomic active-workout snapshot. Low-memory profiles avoid periodic full-history serialization, so long mixed-order workouts do not repeatedly duplicate the complete set graph on the constrained Connect IQ heap.
- Active snapshot v4 stores bounded exercise-catalog indices instead of repeating every exercise name. Legacy v2/v3 snapshots remain readable, while every catalog accepted by the phone's projected 60-set budget can no longer cross that budget around set 16.

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
pwsh -File .\scripts\build-garmin.ps1 -DeveloperKey "C:\path\to\developer_key.der" -Device fenix8solar47mm
```

The PowerShell build script requires PowerShell 7 or newer; Windows PowerShell
5.1 is not supported.

macOS development build:

```bash
./scripts/build-garmin.sh --developer-key /secure/developer_key.der --device fenix8solar47mm
```

Development compilation remains the default for compatibility. `-CompileOnly`
or `--compile-only` can be supplied when an explicit non-release mode is useful
in automation.

Development PRGs for Descent G1, Forerunner 55 / ForeAthlete 55, Instinct
2/2S/2X, and Instinct Crossover use the stable compact hardware-key build and
are compiled with debug metadata stripped. The five 96 KiB products require it;
the shared `fr55` target uses it because the full 128 KiB build did not retain
enough real loader/runtime headroom. The compact build preserves account/device
binding, completed sets, the FIT-before-queue commit, offline ordering, and the
same tutorial. It checkpoints the live timeline in the atomic workout snapshot,
but a process termination cannot reattach Garmin's native ActivityRecording
session; the next explicit Resume starts a new FIT session, and a paused rest
countdown may resume from the last compact checkpoint rather than the exact
instant of termination. On `fr55` and larger profiles, a phase-zero restart
opens an explicit FIT-history decision before any GymApp sync. The five 96 KiB
profiles keep the smaller Summary: a second explicit Save & Exit safely queues
the preserved sets with the same request ID, without claiming that the unknown
FIT activity was saved and without calling Garmin's recording API again. Use a
larger-memory target when source-level simulator debugging is required.

Enduro, Fenix 6, Fenix 6S, Forerunner 245, and Venu Sq also have a real 128 KiB
watch-app ceiling. Their enhanced compact state profile retains indexed atomic
workouts, FIT, phone sync, queueing, the tutorial, rich recovery, and the same
hardware-key workout actions while omitting the full legacy quarantine and
direct-cloud parser that do not fit the compiler limit. Cloud plans still reach
these products through the paired GymApp phone flow.

Store export:

```powershell
pwsh -File .\scripts\build-garmin.ps1 -Release
```

```bash
./scripts/build-garmin.sh --release
```

The store export is written as `garmin/build/gymapp-garmin-connect-iq.iq`. It contains a device-specific binary for every compatible product declared in `manifest.xml`; it is not tied to the default development device name. A `.prg` development build remains device-specific and keeps that device in its filename.

Store export fails closed unless the DER private key is RSA-4096 and its
SubjectPublicKeyInfo SHA-256 fingerprint is the pinned GymApp Store identity
`926b106c47125ddc97aef9801ffd4812f54562140122bb30f792493ed92adb47`.
`GARMIN_RELEASE_PUBLIC_KEY_SHA256`, `-ExpectedPublicKeySha256`,
`--expected-public-key-sha256`, or the ignored local file
`garmin-keys/release_public_key.sha256` may confirm that expected identity, but
cannot override it. The scripts build in isolated raw/sanitized staging
directories while keeping the compiler output basename canonical, so every
device entry remains `.../gymapp-garmin-connect-iq.prg` instead of inheriting a
temporary PID or dot-prefixed name. They replace the prior artifact only after
SDK export and readback succeed.

Readback fully opens the SDK-produced 7z package and requires its manifest,
512-byte RSA-4096 `manifest.sig2`, developer public key, and compiled PRG files.
Before the prior output is replaced, the release scripts rewrite only the
exact current source-root prefix and local user-root prefixes inside
`debug.xml` entries to equal-byte-length neutral relative prefixes. Other
private temporary roots, source-root lookalikes, and traversal segments remain
rejected. They then reopen the rewritten package, reject Unix user/private-temp
roots and Windows absolute/user-root paths anywhere in the archive, and compare SHA-256
for every non-debug entry with the SDK output. Readback also rejects any
compiled program whose internal basename is not
`gymapp-garmin-connect-iq.prg`. A failed rewrite, hash check, or readback leaves
the previous validated IQ untouched and does not print the
rejected local path. Release compiler and gate subprocess output is suppressed
and the success message uses the repository-relative artifact path, so local
usernames and workspace roots do not enter release logs.
Connect IQ SDK 9.2 does not expose a standalone cryptographic signature
verification command, so signer continuity is enforced before `monkeyc`; Store
acceptance remains the final external signature check.

Keep the RSA-4096 developer key outside the repository and back it up securely.
Garmin requires the same key for every future update to an existing Connect IQ
Store app.

Android communication uses Garmin's official `ciq-companion-app-sdk` and requires Garmin Connect to be installed, running, and paired with the watch.

The Garmin app id is `A72A5B9F4E3D4E5A8B72C1D9F6123E40`; it must remain identical in `manifest.xml` and the Android bridge.
