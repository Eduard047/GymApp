# GymApp for Garmin watches

Connect IQ watch app targeting the 108 API-compatible Garmin watches and wearable devices listed in `manifest.xml`. Products whose installed device package cannot satisfy the app's Connect IQ 3.2 minimum are intentionally excluded. The UI is drawn from a 260x260 baseline and scales positions/sizes from the active `dc.getWidth()` / `dc.getHeight()` values, so higher-resolution round screens such as Venu 3 do not render the layout as a tiny fixed-size block.

## Build pipeline

Install the pinned build dependencies with `pnpm install --frozen-lockfile` before using either build helper. Both helpers use the same source preparation, native resource packing and PRG optimizer. The source pass disables type propagation and single-use copy propagation; the pinned patch preserves SDK array construction. The PRG pass retains argument-count checks and uses partial redundancy elimination without forbidden transformations. Native device limits remain enforced by the SDK. Release exports require the pinned Store signer and package readback before replacing an existing output.

After device-specific source selection, oversized full profiles move stateless
value checks into a separate module to satisfy the 254-static-member ceiling on
older products. Compact profiles retain their existing class layout. Text
extraction uses explicit substring bounds for older Connect IQ runtimes.

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
- Finished workouts remain queued locally until Garmin Connect can deliver them to a compatible phone client.
- FIT finalization, queue append, queue recovery and final cleanup run in separate callbacks on Save. The saving screen consumes repeated input, and a failed stage returns to explicit retry. The durable owner/device/request marker remains authoritative across restarts.
- After the final cleanup the watch shows `SENDING...` while the phone is connected and stays open until the phone acknowledges the queue, 30 s pass without progress, or any button is pressed. The queue is kept on every early exit. The next set offset of a multi-part transfer is stored, so a restart resumes from it; a phone that no longer holds the staged transfer makes the watch restart from the first set.
- A failed save names its cause where it is known: a full queue shows the sync prompt and a storage budget overrun shows the storage status; other failures keep the generic save error.

## Lite mode (96 KiB watches)

- Applies to the 96 KiB tier: Instinct 2, 2S, 2X, Crossover and Descent G1. These watches record free workouts only; their heap cannot hold a plan, so plan mode, manual set entry and plan sync are not part of their build.
- Pairing still works. A `sync` message is applied for its binding fields (account, device, pairing generation, revision, language) with the same validation, replay, revision and ownership checks as every other profile. `planNames`, `planWeights`, `planReps` and `exercises` are replaced by empty values before validation and are never copied or stored.
- The watch answers with a lean `sync_ack`: the usual correlation and binding fields, `applied` (true when applied or an exact replay, false when refused) and an additive `lite: 1` key. It carries no plan counts. Queued workouts are sent after the acknowledgement, as on other profiles.
- `request_sync` identifies the tier by a `-lite` suffix on `watchVersion`; no new key is added because released phone parsers reject unknown `request_sync` keys.
- Phones that recognize the suffix should send a binding-only sync (empty plan arrays, no `exercises`). Released phones keep sending their full plan; the watch drops it and still acknowledges, so pairing completes either way.
- A plan stored by an older build is deleted once at startup (marker `lite96PurgedV1`), only while no active, prepared or queued workout depends on the exercise catalog.
- A finished free workout is queued (up to 3 on this tier) and sent as `create_workout` with `workoutMode: "free"`, no sets and the recorded duration and heart-rate summary. Android and iOS store it as an activity-only workout.
- Contract: `shared/garmin-lite-mode-v1.json`. Other profiles are unchanged; the lite code is selected with the `compactWorkoutMode96` / `richWorkoutMode` annotations.

## Memory tiers (128 KiB watches)

- The 128 KiB products take one of three incoming-sync tiers, chosen at build time (annotations `mem128` / `mem128Wide`):

  | Tier | Devices | Plan (sets / chars) | Catalog (entries / chars) |
  | --- | --- | --- | --- |
  | tight | Enduro, Fenix 6, Fenix 6S, Forerunner 245, Venu Sq | 0 / 0 | 5 / 100 |
  | wide | Instinct E 40 mm, Instinct E 45 mm, Instinct 3 Solar 45 mm | 20 / 500 | 40 / 700 |
  | fr55 | Forerunner 55 | 8 / 160 | 12 / 240 |

- Plan characters are the summed `String.length()` of `planNames`. Measured in the simulator: the tight group has under 1 KB of heap free at Ready once paired, so it accepts no plan and even a small sync may not fit; the fr55 limits leave about 3 KB free during a sync, while saving a planned workout remains the tightest step.
- A plan over the limit is refused before any copy: plan and catalog are dropped, pairing is still applied, and the watch sends `sync_ack` with `applied: false` and an additive `reason: "plan_too_large"`. A catalog over the limit is trimmed to its leading entries and the sync continues.
- `request_sync` marks the tier with a `-c128` suffix on `watchVersion` (`-fr55` on Forerunner 55); no new key is added.
- Android and iOS stop retrying when the acknowledgement matches exactly (correlation fields, `applied: false`, reason `plan_too_large`), keep the plan undelivered and show "This plan is too large for this watch. Shorten it and sync again."
- Once at startup (marker `mem128SizedV1`) a stored plan, catalog, deferred sync and legacy quarantine copies are deleted, except while a workout is active or prepared. Queued workouts are never deleted.
- Contract: `shared/garmin-memory-tiers-v1.json`.

## Workout data

- Garmin FIT activity is recorded as a strength-training workout through Connect IQ activity recording.
- GymApp calculates its own strength-focused kcal estimate and also shows Garmin's reported kcal for comparison.
- The phone app receives workout duration, Gym kcal, Garmin kcal, average/max HR, HR zones, and per-set duration, rest-before, start/peak/end HR, recovery drop, and detector confidence.
- Exercise name, weight, and reps still require the selected values on the watch; heart rate cannot reliably infer exercise/kg/reps by itself.
- On constrained-memory watches, per-set detector diagnostics are omitted from both the live set graph and outgoing payload, matching the compact restart checkpoint. Automatic set prompts, manual values, set intervals, workout heart-rate totals, and FIT recording remain available. The last set keeps its separate undo statistics only for the undo window.
- Completed sets are committed once to the atomic active-workout snapshot. Low-memory profiles avoid periodic full-history serialization, so long mixed-order workouts do not repeatedly duplicate the complete set graph on the constrained Connect IQ heap.
- FREE activities refresh a bounded checkpoint every 15 seconds and at lifecycle boundaries; bound compact workouts update only the empty-set header. Unpaired activities keep their separate watch-local journal. Resume restores elapsed time and metrics only after an explicit action. Pairing waits until that local activity is resolved; the journal never becomes a phone queue payload. A prepared/saved FIT phase prevents an uncertain save result from silently starting a duplicate activity after restart.
- Compact active snapshot v6 commits a bounded header after immutable, epoch-bound set rows. Undo and replacement keep the previous committed prefix readable until the new header is durable. Legacy v2/v3/v4 snapshots remain readable, and numeric values retain their original precision.
- Completed journal workouts pin their row bank. The queue writes bounded entries into an inactive slot before committing its small index; interrupted writes leave the previous index readable. Account/device/generation checks apply to the whole queue and every outgoing frame.
- Large compact workouts, and every workout with sets on 128 KiB watches, use `workout_part` frames with one set each. Android and iOS persist the ordered transfer before partial acknowledgement and acknowledge the complete workout only after durable import. Update the phone client before distributing a watch build that uses these frames; older clients ignore them and the watch retains the queue.

## Auto set detection

The watch estimates set/rest transitions from a bounded 25 Hz accelerometer movement score and heart-rate movement. The displayed HR remains Garmin's native current activity value (with direct sensor fallback); a three-sample median filter is used only for set/rest detection. Missing sensor data expires instead of leaving a stale number on screen, and a high but flat recovery heart rate cannot by itself start another set. Devices that cannot open the accelerometer stream automatically retain heart-rate-only detection.

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
are compiled with debug metadata stripped. The shared `fr55` target uses this
profile because the full 128 KiB build did not retain enough runtime headroom.
The current journal build still exceeds the limits of the five 96 KiB products:
compilation and Store export remain blocked for those products until the
program fits their native ceiling. The manifest retains their compatibility
entries; lowering the SDK limit checks is not a supported build path. The compact build preserves account/device
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

Enduro, Fenix 6, Fenix 6S, Forerunner 245, Venu Sq, Instinct E (40 mm and
45 mm), and Instinct 3 Solar 45 mm also have a real 128 KiB watch-app ceiling
(Forerunner 55 shares it on its own profile; see Memory tiers). Their enhanced compact state profile retains indexed atomic
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

Compact watches read committed sets through bounded journal references and preserve exact numeric values when building phone frames. UTF-8 bounds use byte arrays to avoid allocating a numeric slot for every text byte; wire limits and account-binding validation remain unchanged.

During recording, incoming phone messages remain enabled while periodic plan requests and automatic backlog uploads are deferred. The Ready screen retains manual plan synchronization, and queued workouts retry when recording is closed.
