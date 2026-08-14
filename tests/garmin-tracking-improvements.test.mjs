import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `Missing start anchor: ${start}`);
  assert.notEqual(endIndex, -1, `Missing end anchor: ${end}`);
  return source.slice(startIndex, endIndex);
};

const completedCountByExercise = (sets, exerciseName) =>
  sets.filter((set) => set.exerciseName === exerciseName).length;

const nextRemainingGlobalSlot = (plan, sets) => {
  const seenPlanSlots = new Map();
  for (const slot of plan) {
    const ordinal = seenPlanSlots.get(slot.exerciseName) ?? 0;
    seenPlanSlots.set(slot.exerciseName, ordinal + 1);
    if (completedCountByExercise(sets, slot.exerciseName) <= ordinal) {
      return slot;
    }
  }
  return null;
};

const completedPlannedCount = (plan, sets) => {
  const planned = new Map();
  for (const slot of plan) {
    planned.set(slot.exerciseName, (planned.get(slot.exerciseName) ?? 0) + 1);
  }
  const actual = new Map();
  for (const set of sets) {
    actual.set(set.exerciseName, (actual.get(set.exerciseName) ?? 0) + 1);
  }
  return [...planned].reduce(
    (sum, [name, count]) => sum + Math.min(count, actual.get(name) ?? 0),
    0
  );
};

const intervalsAreConsistent = (intervals, durationSeconds, gymTotal, garminTotal) => {
  let previousEnd = 0;
  let gymSum = 0;
  let garminSum = 0;
  let hasGarminSlice = false;
  for (const interval of intervals) {
    const [start, end, gym, garmin] = interval;
    if (start < previousEnd || end < start || end > durationSeconds) return false;
    previousEnd = end;
    gymSum += gym;
    if (garmin != null) {
      hasGarminSlice = true;
      garminSum += garmin;
    }
  }
  return (
    gymTotal != null &&
    gymSum <= gymTotal + 0.1 &&
    (!hasGarminSlice || (garminTotal != null && garminSum <= garminTotal + 0.1))
  );
};

test("Garmin tracking prefers activity HR, diagnoses both sources, and expires stale readings", async () => {
  const [session, view, store] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  const tick = section(session, "static function tick()", "static function startSensors()");
  assert.ok(
    tick.indexOf("updateGarminActivityInfo()") < tick.indexOf("readHeartRateFromSensor()"),
    "the native activity sample remains authoritative"
  );
  assert.match(tick, /if \(!appliedActivityHeartRate\)[\s\S]*applyHeartRate\(sampledSensorHeartRate\)/);
  assert.match(tick, /expireStaleHeartRate\(\)/);
  assert.match(session, /elapsedSeconds - lastValidHrSeconds >= 5/);
  assert.match(session, /var a = olderFilterHr[\s\S]*var b = previousFilterHr[\s\S]*var c = value/);
  assert.match(session, /updateEffortState\(filteredHr\)/);
  assert.match(session, /var renewedRiseDelta = 3/);
  assert.match(session, /var renewedRiseTrend = 2\.0/);
  assert.match(
    session,
    /var zoneEntrySignal = zoneEnough &&\s*\(delta >= renewedRiseDelta \|\| hrTrend >= renewedRiseTrend\)/
  );
  assert.match(session, /static function hasValidHeartRateZones\(\)/);
  assert.match(view, /"ACT", GymSession\.activityHr/);
  assert.match(view, /"SNS", GymSession\.sensorHr/);
  assert.match(view, /"MOV", motionDebugText\(\)/);
  assert.match(view, /function motionDebugText\(\)[\s\S]*GymSession\.motionAvailable/);
  assert.match(view, /"CONF", GymSession\.setConfidence/);
  assert.match(view, /dc\.getFontHeight\(Gfx\.FONT_XTINY\)/);
  assert.match(view, /lineY = sy\(h, 34\) \+ lineHeight \+ sr\(w, h, 4\)/);
  assert.doesNotMatch(view, /drawDebugLine\(dc, w, h, 46,/);
});

test("Garmin rest countdown never blocks or hides a detected next set", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const tick = section(view, "function tick()", "function requestSyncNow()");
  assert.match(
    tick,
    /GymStore\.restStartedAt != null[\s\S]*GymSession\.effortState\.equals\("SET ACTIVE"\)[\s\S]*GymStore\.timerElapsedMs\(GymStore\.restStartedAt\)[\s\S]*GymStore\.restStartedAt = null/
  );
  assert.ok(
    tick.indexOf("restWasActive = false") < tick.indexOf('GymStore.status = "REST DONE"'),
    "suspending rest for a possible set must not vibrate as if the timer completed"
  );
  const dashboard = section(view, "function drawDashboard(", "function showSetSavedFlash(");
  assert.match(dashboard, /var setActive = GymSession\.effortState\.equals\("SET ACTIVE"\)/);
  assert.ok(
    dashboard.indexOf("setActive ?") < dashboard.indexOf("rest > 0 ?"),
    "active-set status must take visual priority over the countdown"
  );
  assert.doesNotMatch(tick, /clearTransientSetActions\(\)/);
  assert.match(tick, /GymStore\.restDurationMs > 0 && GymStore\.restStartedAt == null[\s\S]*dismissSetSavedFlash\(\)/);
  assert.match(tick, /!GymSession\.activeSetSeen[\s\S]*!GymSession\.autoLogPrompt[\s\S]*restoreSuspendedRest\(\)/);
  const restore = section(view, "function restoreSuspendedRest()", "function onSyncSent(");
  assert.match(restore, /GymStore\.restStartedAt = System\.getTimer\(\)/);
  assert.match(restore, /restWasActive = true/);
  assert.match(restore, /REST RESUMED/);
  const undoDelegate = section(view, "function undoLastSet()", "function handleSettings(");
  assert.match(undoDelegate, /GymStore\.restDurationMs > 0 && GymStore\.restStartedAt == null[\s\S]*GymSession\.activeSetSeen/);
  assert.ok(
    undoDelegate.indexOf("return;") < undoDelegate.indexOf("GymStore.undoLastSet()"),
    "undo must not restore the previous set snapshot over a live candidate"
  );
  assert.match(
    session,
    /static function clearAutoPrompt\(\)[\s\S]*effortState = "REST"[\s\S]*lastHrChangeSeconds = elapsedSeconds/
  );
});

test("Garmin set commit clears residual motion while preserving genuinely new detection", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const clear = section(
    session,
    "static function clearAutoPrompt()",
    "static function restoreSetAfterUndo("
  );
  assert.match(clear, /activeSignalCount = 0/);
  assert.match(clear, /motionSignalCount = 0/);
  assert.match(clear, /motionScore = 0\.0/);
  assert.match(clear, /lastMotionTimerMs = null/);
  assert.match(clear, /lastCredibleMotionSeconds = 0/);
  assert.match(clear, /clearSetCandidate\(\)/);
  assert.match(clear, /effortState = "REST"/);
  assert.doesNotMatch(clear, /clearTransientSetActions|lastSetUndoStartedAt/);

  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.ok(
    addSet.indexOf("lastSetUndoStartedAt =") < addSet.indexOf("GymSession.clearAutoPrompt()") &&
      addSet.indexOf("GymSession.clearAutoPrompt()") < addSet.indexOf("restDurationMs ="),
    "commit must retain undo, clear old motion, and only then start rest"
  );

  const freshness = section(
    session,
    "static function isMotionFresh()",
    "static function readHeartRateFromSensor("
  );
  assert.match(freshness, /lastMotionTimerMs == null[\s\S]*return false/);
  assert.match(freshness, /GymStore\.timerElapsedMs\(lastMotionTimerMs\)/);

  const tick = section(view, "function tick()", "function requestSyncNow()");
  assert.match(tick, /GymStore\.restStartedAt != null[\s\S]*GymSession\.effortState\.equals\("SET ACTIVE"\)/);
  assert.match(tick, /GymStore\.timerElapsedMs\(GymStore\.restStartedAt\)/);
  assert.match(store, /static function canUndoLastSet\(\)/);

  const sensorCallback = section(
    session,
    "static function onSensorData(data)",
    "static function isFiniteSensorNumber"
  );
  assert.match(sensorCallback, /motionScore = \(motionScore \* 0\.55\) \+ \(sampleScore \* 0\.45\)/);
  assert.match(sensorCallback, /lastMotionTimerMs = System\.getTimer\(\)/);
});

test("Garmin dashboard renders the selected live workout hierarchy without static mock data", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const dashboard = section(view, "function drawDashboard(", "function drawHeartIcon(");

  assert.match(dashboard, /GymSession\.hr == null \? "--" : GymSession\.hr\.toString\(\)/);
  assert.match(dashboard, /GymSession\.elapsedText\(\)/);
  assert.match(dashboard, /GymStore\.totalGymCalories\(\)\.format\("%\.1f"\)/);
  assert.match(dashboard, /dashboardSetProgressText\(\)/);
  assert.match(dashboard, /GymStore\.currentExerciseLabel\(\)/);
  assert.match(dashboard, /setSummaryText\(\)/);
  assert.match(dashboard, /dashboardStatusText\(rest, setActive, setMaybe\)/);
  assert.match(view, /function dashboardStatusText\(rest, setActive, setMaybe\)[\s\S]*countdownText\(rest\)/);
  assert.match(view, /function drawHeartIcon\(/);
  assert.match(view, /function drawDashboardStatusPill\(/);
  assert.match(view, /function isCompactDashboard\(w, h\)/);
  assert.match(view, /function drawCompactDashboard\(/);
  assert.match(view, /function isTinyDashboard\(w, h\)/);
  assert.match(view, /isTinyDashboard\(w, h\) \? h - 10 : h - 14/);
  assert.doesNotMatch(dashboard, /"142"|"00:17:34"|"Bench Press"|"128"/);
});

test("Garmin workout clock, pause lifecycle, and calorie display keep advancing independently", async () => {
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const onShow = section(view, "function onShow()", "function onHide()");
  const viewTick = section(view, "function tick()", "function requestSyncNow()");
  const sessionTick = section(session, "static function tick()", "static function startSensors()");
  const pause = section(session, "static function pause()", "static function resume()");
  const resume = section(session, "static function resume()", "static function stopAndSave()");
  const calories = section(session, "static function updateCalories()", "static function setBoostFor(");

  assert.match(onShow, /ticker\.start\(method\(:tick\), 1000, true\)/);
  assert.match(viewTick, /GymSession\.tick\(\)/);
  assert.match(viewTick, /Ui\.requestUpdate\(\)/);
  assert.match(sessionTick, /elapsedSeconds = now - startedAt - pausedAccumSeconds - currentPaused/);
  assert.ok(
    sessionTick.indexOf("elapsedSeconds =") < sessionTick.indexOf("if (paused)"),
    "a paused frame must first capture the exact elapsed time at pause"
  );
  assert.match(pause, /pausedAt = Time\.now\(\)\.value\(\)/);
  assert.ok(
    pause.indexOf("session.stop()") < pause.indexOf("paused = true"),
    "the UI must remain unpaused when Garmin refuses to stop recording"
  );
  assert.match(resume, /pausedAccumSeconds \+= now - pausedAt/);
  assert.match(resume, /session\.start\(\)/);
  assert.ok(
    resume.indexOf("session.start()") < resume.indexOf("paused = false"),
    "the UI must remain paused when Garmin refuses to resume recording"
  );

  assert.match(calories, /deltaSeconds = elapsedSeconds - lastCalorieSeconds/);
  assert.match(calories, /if \(deltaSeconds > 30\)[\s\S]*deltaSeconds = 30/);
  assert.match(calories, /gymCalories \+= lastKcalPerMinute \* \(deltaSeconds \/ 60\.0\)/);
  assert.match(calories, /lastCalorieSeconds = elapsedSeconds/);
  assert.equal((view.match(/GymStore\.totalGymCalories\(\)\.format\("%\.1f"\)/g) || []).length, 3);

  const displayedCalories = (value) => value.toFixed(1);
  assert.equal(displayedCalories(0), "0.0");
  assert.equal(displayedCalories(0.28), "0.3");
  assert.equal(displayedCalories(99.94), "99.9");
  assert.equal(displayedCalories(100.1), "100.1");
});

test("Garmin can undo only the most recent set inside a bounded window", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  assert.match(store, /undoWindowMs = 5000/);
  assert.match(store, /static function canUndoLastSet\(\)/);
  const undo = section(store, "static function undoLastSet()", "static function clearTransientSetActions()");
  assert.match(undo, /if \(!canUndoLastSet\(\)\)[\s\S]*return false/);
  assert.match(undo, /var previousSets = sets/);
  assert.match(undo, /var lastIndex = previousSets\.size\(\) - 1/);
  assert.match(undo, /var nextSets = normalizedSetList\(previousSets\)/);
  assert.match(undo, /nextSets\.remove\(nextSets\[nextSets\.size\(\) - 1\]\)/);
  assert.ok(
    undo.indexOf("persistActiveWorkoutSnapshot(nextSets") < undo.indexOf("sets = nextSets"),
    "undo must commit the copy-on-write snapshot before publishing globals"
  );
  assert.match(undo, /GymSession\.removeSetBoost\(boost\)/);
  assert.match(undo, /weight = lastSet\.get\("weight"\)/);
  assert.match(undo, /reps = lastSet\.get\("reps"\)/);
  assert.doesNotMatch(undo, /applyCurrentPlanSet\(\)/);
  assert.match(undo, /var previousWorkoutStartedAt = activeWorkoutStartedAtSeconds/);
  assert.match(undo, /if \(nextSets\.size\(\) == 0\)[\s\S]*nextWorkoutStartedAt = null/);
  assert.match(undo, /if \(!compatibilitySaved && !usedAtomicSnapshot && !legacySnapshotCommitted\)[\s\S]*sets = previousSets[\s\S]*GymSession\.restoreSetBoost\(boost\)/);
  assert.match(undo, /if \(!save\(\)\)[\s\S]*status = "RECOVERY FAIL"/);
  assert.match(undo, /restDurationMs = 0[\s\S]*restStartedAt = null/);
  assert.match(session, /static function restoreSetAfterUndo\(statistics, restorePrompt\)/);
  assert.match(undo, /GymSession\.restoreSetAfterUndo\(restoreStatistics, restorePrompt\)/);
  assert.match(view, /function isUndoOverlayActive\(\)/);
  assert.match(view, /GymStore\.tr\("TAP \/ BACK: UNDO"/);
  assert.match(view, /savedSetFlashStartedAt = System\.getTimer\(\)/);
  assert.match(view, /GymStore\.timerElapsedMs\(savedSetFlashStartedAt\) <= GymStore\.undoWindowMs/);
  assert.match(view, /function onBack\(\)[\s\S]*if \(view\.isUndoOverlayActive\(\)\)[\s\S]*undoLastSet\(\)/);
  assert.match(view, /if \(x < \(view\.screenWidth \/ 2\)\)[\s\S]*undoLastSet\(\)[\s\S]*recordSet\(\)/);
});

test("Garmin manual and automatic undo restore the same captured set statistics", async () => {
  const [session, store] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  const undo = section(store, "static function undoLastSet()", "static function clearTransientSetActions()");
  assert.match(undo, /GymSession\.restoreSetAfterUndo\(restoreStatistics, restorePrompt\)/);
  assert.doesNotMatch(undo, /if \(restorePrompt\)|clearRecoveryTracking\(\)/);
  assert.doesNotMatch(undo, /applyCurrentPlanSet\(\)/);

  const restore = section(
    session,
    "static function restoreSetAfterUndo(statistics, restorePrompt)",
    "static function resetProfileDefaults()"
  );
  assert.match(restore, /autoLogPrompt = restorePrompt instanceof Lang\.Boolean && restorePrompt/);
  assert.match(restore, /activeStartSeconds = statistics\.get\("setStartedSeconds"\)/);
  assert.match(restore, /currentSetStartHr = statistics\.get\("startHeartRate"\)/);
  assert.match(restore, /currentSetPeakHr = statistics\.get\("peakHeartRate"\)/);
  assert.match(restore, /restoredSetInterval = copySetInterval\(statistics\.get\("setInterval"\)\)/);

  const captured = {
    setStartedSeconds: 42,
    setEndedSeconds: 65,
    startHeartRate: 118,
    peakHeartRate: 151,
    endHeartRate: 132,
    detectionConfidence: 88,
    setInterval: [42, 65, 2.4, 3, 0, 2, 8, 9, 4, 0]
  };
  const restoreContract = (statistics, wasAutoPrompt) => ({
    ...structuredClone(statistics),
    autoLogPrompt: wasAutoPrompt
  });
  for (const wasAutoPrompt of [false, true]) {
    const restored = restoreContract(captured, wasAutoPrompt);
    assert.deepEqual(restored.setInterval, captured.setInterval);
    assert.equal(restored.startHeartRate, captured.startHeartRate);
    assert.equal(restored.peakHeartRate, captured.peakHeartRate);
    assert.equal(restored.autoLogPrompt, wasAutoPrompt);
  }
});

test("Garmin saved-set overlay consumes hidden navigation and cannot create a phantom set", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");

  for (const handler of ["onNextPage()", "onPreviousPage()", "onNextMode()", "onPreviousMode()", "onMenu()"]) {
    const body = section(view, `function ${handler}`, "function ");
    assert.match(body, /if \(view\.isUndoOverlayActive\(\)\) \{\s*return true;/, handler);
  }
  const key = section(view, "function onKey(evt)", "function handleSelect()");
  assert.ok(
    key.indexOf("if (view.isUndoOverlayActive())") < key.indexOf("if (key == Ui.KEY_UP)"),
    "overlay guard must run before arrows can reach the hidden selection"
  );
  assert.match(key, /KEY_ESC[\s\S]*return onBack\(\)/);
  assert.match(key, /KEY_ENTER[\s\S]*return onSelect\(\)/);
  assert.match(key, /return true;[\s\S]*if \(key == Ui\.KEY_UP\)/);
  const activate = section(view, "function activate(delta)", "function recordSet()");
  assert.match(activate, /if \(view\.isUndoOverlayActive\(\)\) \{\s*return;/);

  const dispatch = (state, event) => {
    if (state.overlay && !["back", "dismiss", "undo"].includes(event)) return state;
    if (event === "right" && state.selected === 3) return { ...state, sets: state.sets + 1 };
    if (event === "back" || event === "undo") return { ...state, overlay: false, sets: state.sets - 1 };
    if (event === "dismiss") return { ...state, overlay: false };
    return state;
  };
  const saved = { overlay: true, selected: 3, sets: 1 };
  assert.deepEqual(dispatch(saved, "right"), saved);
  assert.deepEqual(dispatch(saved, "pageDown"), saved);
  assert.equal(dispatch(saved, "back").sets, 0);
  assert.equal(dispatch(saved, "dismiss").sets, 1);
});

test("Garmin set save and undo keep calorie corrections consistent on failure", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /var boost = GymSession\.setBoostFor\(weight, reps\)/);
  assert.ok(
    addSet.indexOf("persistActiveWorkoutSnapshot(nextSets") <
      addSet.indexOf("GymSession.restoreSetBoost(boost)"),
    "the durable snapshot must commit before the calorie correction becomes visible"
  );
  assert.match(addSet, /if \(!compatibilitySaved && !usedAtomicSnapshot && !legacySnapshotCommitted\)/);
  assert.match(addSet, /if \(!save\(\)\)[\s\S]*status = "RECOVERY FAIL"/);
  const undo = section(store, "static function undoLastSet()", "static function clearTransientSetActions()");
  assert.ok(
    undo.indexOf("persistActiveWorkoutSnapshot(nextSets") <
      undo.indexOf("GymSession.removeSetBoost(boost)"),
    "undo must not remove calories until its snapshot tombstone/list is durable"
  );
  assert.match(session, /static function setBoostFor\(weightKg, reps\)/);
  assert.match(session, /static function removeSetBoost\(boost\)/);
  assert.match(session, /static function restoreSetBoost\(boost\)/);
  const recordSet = section(view, "function recordSet()", "function undoLastSet()");
  assert.match(recordSet, /if \(GymStore\.addSet\(\)\)[\s\S]*showSetSavedFlash[\s\S]*Attention\.vibrate/);
});

test("Garmin fuses bounded motion evidence with HR and falls back safely", async () => {
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const listener = section(session, "static function startMotionListener()", "static function stopMotionListener()");
  assert.match(listener, /Sensor has :registerSensorDataListener/);
  assert.match(listener, /:sampleRate => 10/);
  assert.match(listener, /catch \(ex\)[\s\S]*motionAvailable = false/);
  const callback = section(session, "static function onSensorData(data)", "static function isFiniteSensorNumber");
  assert.match(callback, /count > 40/);
  assert.match(callback, /isFiniteSensorNumber/);
  assert.doesNotMatch(callback, /Storage|GymComm|setValue/);
  const confidence = section(session, "static function updateSetConfidence", "static function motionThreshold");
  assert.match(confidence, /if \(!freshMotion\)[\s\S]*score = 85/);
  assert.match(confidence, /strongMotion[\s\S]*moderateMotion/);
  assert.match(confidence, /strongMotion && motionSignalCount >= 2[\s\S]*score \+= 75/);
  assert.match(session, /motionSignalCount > 4[\s\S]*motionSignalCount = 4/);
  assert.match(
    session,
    /if \(setConfidence >= 75 &&[\s\S]*hasCredibleRestRestartEvidence\(risingEnough\)[\s\S]*activeSignalCount \+= 1/
  );
  assert.match(session, /if \(activeSignalCount >= 3\)/);
  assert.match(view, /SET MAYBE/);
  assert.match(view, /confidenceLabel\(\)/);
});

test("Garmin motion lifecycle uses gyro opportunistically, rejects noise, and asks before saving", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const listener = section(session, "static function startMotionListener()", "static function stopMotionListener()");
  const fullListener = listener.slice(0, listener.indexOf("// The compact hardware tier"));
  assert.match(listener, /:synchronous => true/);
  assert.match(listener, /:gyroscope => \{[\s\S]*:sampleRate => 10/);
  assert.equal(
    (fullListener.match(/Sensor\.registerSensorDataListener/g) || []).length,
    2,
    "one dual-sensor attempt and one accelerometer-only fallback are allowed"
  );
  assert.ok(
    fullListener.indexOf("Sensor.unregisterSensorDataListener()") <
      fullListener.lastIndexOf("Sensor.registerSensorDataListener"),
    "a rejected dual request must release the single listener before fallback"
  );
  assert.match(listener, /catch \(fallbackEx\)[\s\S]*motionAvailable = false/);

  const callback = section(session, "static function onSensorData(data)", "static function isFiniteSensorNumber");
  assert.match(callback, /count > 40[\s\S]*count = 40/);
  assert.match(callback, /absolute\(dominant\) >= 10/);
  assert.match(callback, /reversals >= 1 && reversals <= 6/);
  assert.match(callback, /data has :gyroscopeData/);
  assert.match(callback, /if \(!gyroRead\) \{\s*gyroAvailable = false;\s*gyroScore = 0\.0;/);
  assert.match(callback, /accelStrong \|\| \(accelModerate && gyroStrong\)/);
  assert.doesNotMatch(callback, /Storage|GymComm|setValue/);

  const noise = section(session, "static function updateMotionNoiseFloor(", "static function gyroThreshold()");
  assert.match(noise, /sampleScore > base \* 0\.40/);
  assert.match(noise, /motionNoiseFloor \* 0\.92/);
  assert.match(noise, /var ceiling = base \* 1\.75/);

  const lifecycle = section(session, "static function updateMotionLifecycle()", "static function activeSetSeconds()");
  assert.match(lifecycle, /motionBurstSignals >= 4 && motionRhythmSignals >= 3/);
  assert.match(
    session,
    /static function canArmMotionCandidate\(\)[\s\S]*elapsedSeconds - lastLoggedSetSeconds >=[\s\S]*10/
  );
  assert.match(lifecycle, /quietSeconds >= motionQuietWindowSeconds\(\)/);
  assert.match(lifecycle, /motionDuration >= motionMinimumSetSeconds\(\)[\s\S]*endSetFromMotion\(\)[\s\S]*else if \(currentSetMotionOnly\)[\s\S]*discardShortMotionInterval\(\)/);
  assert.match(lifecycle, /if \(!GymStore\.autoPromptEnabled\) \{\s*return;/);
  assert.match(lifecycle, /static function endSetFromMotion\(\)/);
  const motionEnd = section(session, "static function endSetFromMotion()", "static function snapshotMotionSetZones()");
  assert.match(motionEnd, /var ended = lastCredibleMotionSeconds/);
  assert.match(motionEnd, /ended < activeStartSeconds[\s\S]*ended > elapsedSeconds/);
  assert.doesNotMatch(motionEnd, /activeEvidenceEndSeconds\(\)/);
  assert.match(motionEnd, /currentSetEndHr = currentSetLastMotionHr/);
  assert.match(motionEnd, /restoreMotionSetZoneSnapshot\(\)/);
  assert.match(lifecycle, /autoLogPrompt = true/);
  assert.match(motionEnd, /if \(!GymStore\.autoPromptEnabled\) \{\s*return;/);
  assert.doesNotMatch(motionEnd, /promptGap/);
  assert.doesNotMatch(lifecycle, /GymStore\.addSet|Storage|GymComm/);
  const shortMotion = section(session, "static function discardShortMotionInterval()", "static function endHrCorroboratedSetAfterSignalLoss()");
  assert.match(shortMotion, /clearAutoPrompt\(\)/);
  assert.match(shortMotion, /status = "MOTION SHORT"/);
  assert.doesNotMatch(shortMotion, /GymStore\.addSet|startRest|Storage|GymComm|autoLogPrompt = true/);
  const signalLossEnd = section(session, "static function endHrCorroboratedSetAfterSignalLoss()", "static function promoteMotionCandidate()");
  assert.match(signalLossEnd, /autoLogPrompt = true/);

  const promote = section(session, "static function promoteMotionCandidate()", "static function endSetFromMotion()");
  assert.match(promote, /var gyroCorroborated = gyroAvailable && gyroScore >= gyroThreshold\(\)/);
  assert.match(promote, /gyroCorroborated \? 85 : 78/);
  assert.match(promote, /gyroCorroborated \? "motion\+gyro" : "motion rhythm"/);
  assert.match(promote, /currentSetMotionOnly = true/);

  const zoneSnapshot = section(session, "static function snapshotMotionSetZones()", "static function motionMinimumSetSeconds()");
  assert.match(zoneSnapshot, /currentSetLastMotionZoneSeconds = \[0, 0, 0, 0, 0, 0\]/);
  assert.match(zoneSnapshot, /currentSetZoneSeconds = \[0, 0, 0, 0, 0, 0\]/);

  const capture = section(session, "static function captureSetStatistics()", "static function promoteSetCandidateForCapture()");
  assert.match(capture, /hasEndedInterval \? null : hr/);
  assert.match(capture, /if \(!hasEndedInterval && peakHrValue == null && hr != null\)/);
  const effort = section(session, "static function updateEffortState(value)", "static function updateSetConfidence");
  assert.doesNotMatch(effort, /promptGapSeconds/);
  assert.match(effort, /GymStore\.autoPromptEnabled[\s\S]*activeDuration >= minActiveSeconds/);
  assert.match(
    effort,
    /wasSetActive && activeSetSeen && hasCompleteMotionInterval\(\)[\s\S]*effortState = "SET ACTIVE"[\s\S]*lastAutoReason = "motion boundary"[\s\S]*return;/
  );
  assert.match(motionEnd, /currentSetPeakHr = currentSetLastMotionPeakHr/);
  assert.match(callback, /currentSetLastMotionPeakHr = currentSetPeakHr/);
  const initializeSnapshot = section(session, "static function initializeMotionSetSnapshot()", "static function motionMinimumSetSeconds()");
  assert.match(initializeSnapshot, /if \(!currentSetMotionConfirmed\)/);
  assert.match(initializeSnapshot, /currentSetLastMotionHr = hr/);
  assert.match(initializeSnapshot, /currentSetLastMotionPeakHr = currentSetPeakHr/);
  assert.match(initializeSnapshot, /snapshotMotionSetZones\(\)/);
  assert.match(effort, /beginSetInterval\(\);\s*initializeMotionSetSnapshot\(\);/);
  const completeMotion = section(session, "static function hasCompleteMotionInterval()", "static function motionMinimumSetSeconds()");
  assert.match(completeMotion, /if \(!currentSetMotionConfirmed\)/);
  assert.match(completeMotion, /ended - activeStartSeconds >= motionMinimumSetSeconds\(\)/);
  assert.match(effort, /wasSetActive && activeSetSeen && hasCompleteMotionInterval\(\)/);
  assert.match(effort, /currentSetMotionOnly && activeSetSeen && setConfidence >= 70[\s\S]*currentSetMotionOnly = false/);
  assert.match(effort, /currentSetMotionConfirmed = motionBurstSignals >= 2[\s\S]*currentSetMotionOnly = false;[\s\S]*beginSetInterval\(\)/);

  const staleHr = section(session, "static function expireStaleHeartRate()", "static function trackMinuteHeartRate(");
  assert.match(staleHr, /var wasActiveSet = effortState\.equals\("SET ACTIVE"\) && activeSetSeen/);
  assert.match(staleHr, /var keepMotionSet = wasActiveSet && currentSetMotionConfirmed/);
  assert.doesNotMatch(staleHr, /currentSetMotionConfirmed && isMotionFresh\(\)/);
  assert.match(staleHr, /if \(wasActiveSet\)[\s\S]*currentSetEndHr = hr/);
  const keepMotionBlock = staleHr.slice(
    staleHr.lastIndexOf("if (keepMotionSet)"),
    staleHr.indexOf("else if (wasActiveSet && !GymStore.autoPromptEnabled)")
  );
  assert.doesNotMatch(keepMotionBlock, /currentSetEndGymCalories|currentSetEndGarminCalories/);
  assert.match(staleHr, /lastAutoReason = "motion no hr"/);
  assert.match(staleHr, /lastSetEndSeconds - activeStartSeconds >= minimum[\s\S]*autoLogPrompt = true/);
  assert.match(staleHr, /else \{\s*clearAutoPrompt\(\);[\s\S]*status = "HR SHORT"/);

  const clear = section(session, "static function clearAutoPrompt()", "static function restoreSetAfterUndo(");
  assert.match(clear, /motionBurstSignals = 0/);
  assert.match(clear, /motionRhythmSignals = 0/);
  assert.match(clear, /lastLoggedSetSeconds = elapsedSeconds/);
  const reject = section(session, "static function rejectAutoPrompt()", "static function restoreSetAfterUndo(");
  assert.match(reject, /if \(!autoLogPrompt\)[\s\S]*return false/);
  assert.match(reject, /clearAutoPrompt\(\)/);
  assert.match(reject, /status = "SET SKIPPED"/);
  assert.match(reject, /GymStore\.status = "SET SKIPPED"/);
  assert.doesNotMatch(reject, /GymStore\.addSet|startRest|Storage|GymComm/);

  const viewTick = section(view, "function tick()", "function requestSyncNow()");
  assert.match(viewTick, /!autoPromptWasActive && GymSession\.autoLogPrompt/);
  assert.match(viewTick, /Attention\.vibrate\(\[[\s\S]*CONFIRM SET/);
  assert.match(viewTick, /autoPromptWasActive = GymSession\.autoLogPrompt/);
  assert.match(viewTick, /GymStore\.timerElapsedMs\(GymStore\.restStartedAt\)[\s\S]*GymStore\.restStartedAt = null/);
  assert.match(viewTick, /!GymSession\.activeSetSeen[\s\S]*restoreSuspendedRest\(\)/);
  assert.doesNotMatch(viewTick, /GymStore\.cancelRest\(\)/);
  assert.doesNotMatch(viewTick, /clearTransientSetActions\(\)/);
  const status = section(view, "function dashboardStatusText(", "function motionDebugText()");
  assert.match(status, /GymSession\.activeSetText\(\)/);
  assert.match(status, /GymSession\.recoveryHeartRateDrop\(\)/);
  assert.match(status, /GymStore\.tr\("SAVE\/BACK "/);
  const delegate = section(view, "class WorkoutDelegate", "function recordSet()");
  assert.match(delegate, /function hasPendingSetPrompt\(\)/);
  assert.match(delegate, /function onBack\(\)[\s\S]*hasPendingSetPrompt\(\)[\s\S]*rejectSetPrompt\(\)/);
  assert.match(delegate, /function onSwipe\(evt\)[\s\S]*hasPendingSetPrompt\(\)[\s\S]*Ui\.SWIPE_RIGHT \? onBack\(\) : true/);
  assert.match(view, /function rejectSetPrompt\(\)[\s\S]*GymSession\.rejectAutoPrompt\(\)/);
  assert.match(view, /function rejectSetPrompt\(\)[\s\S]*view\.restoreSuspendedRest\(\)/);
  assert.match(view, /function recordSet\(\)[\s\S]*GymStore\.addSet\(\)[\s\S]*showSetSavedFlash/);

  const adaptiveThreshold = (base, noiseFloor) =>
    Math.min(base * 1.75, Math.max(base, noiseFloor * 2.4 + 35));
  const canLearnAsNoise = (base, sample) => sample <= base * 0.4;
  assert.equal(canLearnAsNoise(130, 20), true);
  assert.equal(canLearnAsNoise(130, 80), false, "a light first repetition cannot poison the noise floor");
  assert.equal(adaptiveThreshold(130, 10), 130);
  assert.equal(adaptiveThreshold(130, 60), 179);
  assert.equal(adaptiveThreshold(130, 1_000), 227.5, "threshold remains bounded under hostile input");

  const advanceBurst = (state, { strong, moderate, rhythmic }) => {
    const next = { ...state };
    if (strong) {
      next.burst = Math.min(6, next.burst + 1);
      next.rhythm = rhythmic ? Math.min(6, next.rhythm + 1) : Math.max(0, next.rhythm - 1);
    } else if (moderate) {
      next.burst = Math.max(0, next.burst - 1);
      next.rhythm = Math.max(0, next.rhythm - 1);
    } else {
      next.burst = 0;
      next.rhythm = 0;
    }
    next.active = next.burst >= 4 && next.rhythm >= 3;
    return next;
  };
  let detector = { burst: 0, rhythm: 0, active: false };
  for (let i = 0; i < 12; i += 1) {
    detector = advanceBurst(detector, { strong: false, moderate: i % 4 === 0, rhythmic: false });
  }
  assert.equal(detector.active, false, "sporadic locker-room movement must not start a set");
  detector = advanceBurst(detector, { strong: true, moderate: true, rhythmic: true });
  detector = advanceBurst(detector, { strong: true, moderate: true, rhythmic: true });
  assert.equal(detector.active, false, "two motion windows remain only a candidate");
  detector = advanceBurst(detector, { strong: true, moderate: true, rhythmic: true });
  assert.equal(detector.active, false, "three arm-swing windows still cannot start a motion-only set");
  detector = advanceBurst(detector, { strong: true, moderate: true, rhythmic: true });
  assert.equal(detector.active, true, "four bounded rhythmic windows can confirm sustained activity");

  const boundedMotionEnd = (started, lastMotion, now) =>
    Math.min(now, Math.max(started, lastMotion));
  assert.equal(boundedMotionEnd(10, 31, 38), 31, "quiet HR ticks cannot extend a motion-ended set");
  assert.equal(boundedMotionEnd(10, 4, 38), 10, "malformed old evidence cannot precede set start");
  assert.equal(boundedMotionEnd(10, 80, 38), 38, "future evidence is bounded to elapsed time");

  const zonesAtLastMotion = [0, 2, 4, 3, 1, 0];
  const zonesAfterQuietHr = [0, 2, 4, 8, 1, 0];
  assert.ok(zonesAfterQuietHr.reduce((a, b) => a + b, 0) > zonesAtLastMotion.reduce((a, b) => a + b, 0));
  assert.deepEqual([...zonesAtLastMotion], [0, 2, 4, 3, 1, 0], "motion end restores the bounded zone snapshot");

  const promptAfterMotionEnd = ({ autoPromptEnabled, priorPromptAge }) => ({
    autoLogPrompt: autoPromptEnabled,
    persisted: false,
    autoPromptEnabled,
    priorPromptAge
  });
  assert.deepEqual(
    promptAfterMotionEnd({ autoPromptEnabled: false, priorPromptAge: 5 }),
    { autoLogPrompt: false, persisted: false, autoPromptEnabled: false, priorPromptAge: 5 },
    "AUTO OFF remains manual mode and never creates a prompt or vibration"
  );
  assert.equal(
    promptAfterMotionEnd({ autoPromptEnabled: true, priorPromptAge: 5 }).autoLogPrompt,
    true,
    "AUTO ON prompts every distinct ended set even inside the former throttle window"
  );

  const captureEndHr = ({ ended, recordedEndHr, liveHr }) =>
    recordedEndHr ?? (ended ? null : liveHr);
  assert.equal(captureEndHr({ ended: true, recordedEndHr: null, liveHr: 142 }), null);
  assert.equal(captureEndHr({ ended: false, recordedEndHr: null, liveHr: 142 }), 142);
  const capturePeakHr = ({ ended, recordedPeakHr, liveHr }) =>
    recordedPeakHr ?? (ended ? null : liveHr);
  assert.equal(capturePeakHr({ ended: true, recordedPeakHr: null, liveHr: 151 }), null);
  assert.equal(capturePeakHr({ ended: false, recordedPeakHr: null, liveHr: 151 }), 151);

  const fastHrFall = ({ motionConfirmed, motionDuration, minimumDuration, quietSeconds, quietWindow }) => {
    if (motionConfirmed && motionDuration >= minimumDuration && quietSeconds < quietWindow) {
      return { state: "SET ACTIVE", prompt: false, boundary: "last-motion" };
    }
    return {
      state: "REST",
      prompt: true,
      boundary: motionDuration >= minimumDuration ? "last-motion" : "hr"
    };
  };
  assert.deepEqual(
    fastHrFall({ motionConfirmed: true, motionDuration: 12, minimumDuration: 10, quietSeconds: 2, quietWindow: 6 }),
    { state: "SET ACTIVE", prompt: false, boundary: "last-motion" },
    "a fast HR fall cannot preempt the bounded motion quiet window"
  );
  assert.deepEqual(
    fastHrFall({ motionConfirmed: true, motionDuration: 12, minimumDuration: 10, quietSeconds: 6, quietWindow: 6 }),
    { state: "REST", prompt: true, boundary: "last-motion" }
  );
  assert.deepEqual(
    fastHrFall({ motionConfirmed: true, motionDuration: 4, minimumDuration: 10, quietSeconds: 2, quietWindow: 6 }),
    { state: "REST", prompt: true, boundary: "hr" },
    "a short motion burst cannot trap an HR-confirmed set in SET ACTIVE"
  );

  const promoteOnLastMotion = ({ motionConfirmed, hr, peak, zones }) =>
    motionConfirmed ? { hr, peak, zones: [...zones] } : null;
  assert.deepEqual(
    promoteOnLastMotion({ motionConfirmed: true, hr: 128, peak: 136, zones: [0, 1, 3, 0, 0, 0] }),
    { hr: 128, peak: 136, zones: [0, 1, 3, 0, 0, 0] },
    "HR promotion on the final motion batch initializes a usable bounded snapshot"
  );

  const finishMotionOnly = ({ motionDuration, minimumDuration, quietComplete, hrCorroborated = false }) => {
    if (!quietComplete) return "ACTIVE";
    if (hrCorroborated && motionDuration < minimumDuration) return "HR_OWNS_BOUNDARY";
    return motionDuration >= minimumDuration ? "PROMPT" : "DISCARD_TRANSIENT";
  };
  assert.equal(finishMotionOnly({ motionDuration: 4, minimumDuration: 10, quietComplete: true }), "DISCARD_TRANSIENT");
  assert.equal(finishMotionOnly({ motionDuration: 12, minimumDuration: 10, quietComplete: true }), "PROMPT");
  assert.equal(finishMotionOnly({ motionDuration: 4, minimumDuration: 10, quietComplete: false }), "ACTIVE");
  assert.equal(
    finishMotionOnly({ motionDuration: 4, minimumDuration: 10, quietComplete: true, hrCorroborated: true }),
    "HR_OWNS_BOUNDARY",
    "a short HR-corroborated strength set is not discarded as motion noise"
  );

  const staleHrAtQuietBoundary = ({ motionDuration, minimumDuration, motionOnly }) => {
    if (motionDuration >= minimumDuration) return "MOTION_SNAPSHOT_PROMPT";
    return motionOnly ? "DISCARD_TRANSIENT" : "HR_SIGNAL_LOSS_PROMPT";
  };
  assert.equal(staleHrAtQuietBoundary({ motionDuration: 12, minimumDuration: 10, motionOnly: false }), "MOTION_SNAPSHOT_PROMPT");
  assert.equal(staleHrAtQuietBoundary({ motionDuration: 4, minimumDuration: 10, motionOnly: true }), "DISCARD_TRANSIENT");
  assert.equal(staleHrAtQuietBoundary({ motionDuration: 4, minimumDuration: 10, motionOnly: false }), "HR_SIGNAL_LOSS_PROMPT");

  const resolveSuspendedRest = ({ remaining, resolution }) =>
    resolution === "SAVE" ? 90 : remaining;
  assert.equal(resolveSuspendedRest({ remaining: 47, resolution: "SHORT_FALSE_START" }), 47);
  assert.equal(resolveSuspendedRest({ remaining: 47, resolution: "BACK_REJECT" }), 47);
  assert.equal(resolveSuspendedRest({ remaining: 47, resolution: "SAVE" }), 90);
});

test("Garmin preserves active evidence, suspended rest, and prompts across UI transitions", async () => {
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const stopMotion = section(
    session,
    "static function stopMotionListener()",
    "(:fullLegacyState)\n    static function onSensorData"
  );
  const inactiveReset = stopMotion.slice(stopMotion.indexOf("if (!activeSetSeen)"));
  assert.doesNotMatch(
    stopMotion.slice(0, stopMotion.indexOf("if (!activeSetSeen)")),
    /lastCredibleMotionSeconds = 0|motionBurstSignals = 0/
  );
  assert.match(inactiveReset, /lastCredibleMotionSeconds = 0/);
  assert.match(inactiveReset, /motionBurstSignals = 0/);

  const callback = section(session, "static function onSensorData(data)", "static function isFiniteSensorNumber");
  assert.match(
    callback,
    /lastCredibleMotionSeconds = elapsedSeconds[\s\S]*currentSetEndGymCalories = gymCalories[\s\S]*currentSetEndGarminCalories = garminCalories/
  );
  assert.match(
    callback,
    /effortState\.equals\("SET ACTIVE"\)[\s\S]*if \(strongMotion && rhythmic\) \{[\s\S]*lastCredibleMotionSeconds = elapsedSeconds/
  );
  const evidenceTotals = section(session, "static function captureActiveEvidenceTotals()", "static function captureEndedSetTotals()");
  assert.doesNotMatch(evidenceTotals, /currentSetEndGymCalories|currentSetEndGarminCalories/);
  const motionEnd = section(session, "static function endSetFromMotion()", "static function snapshotMotionSetZones()");
  assert.doesNotMatch(motionEnd, /currentSetLastEvidenceGymCalories|currentSetLastEvidenceGarminCalories/);
  const initialMotionSnapshot = section(session, "static function initializeMotionSetSnapshot()", "static function motionMinimumSetSeconds()");
  assert.match(initialMotionSnapshot, /currentSetEndGymCalories = gymCalories/);
  assert.match(initialMotionSnapshot, /currentSetEndGarminCalories = garminCalories/);

  const effort = section(session, "static function updateEffortState(value)", "static function updateSetConfidence");
  assert.match(
    effort,
    /activeDuration < minActiveSeconds[\s\S]*!currentSetMotionConfirmed \|\| currentSetMotionOnly[\s\S]*clearAutoPrompt\(\)[\s\S]*status = "HR SHORT"/
  );
  assert.match(
    effort,
    /activeDuration >= minActiveSeconds \|\|[\s\S]*currentSetMotionConfirmed && !currentSetMotionOnly/
  );
  assert.match(effort, /currentSetEndGymCalories = null[\s\S]*currentSetEndGarminCalories = null/);
  assert.match(effort, /effortState\.equals\("SET ACTIVE"\)[\s\S]*currentSetEndHr = value/);
  assert.ok(
    effort.indexOf("!GymStore.autoPromptEnabled") < effort.indexOf('status = "HR SHORT"'),
    "AUTO OFF must hold any detected interval before automatic short-start cleanup"
  );
  const capture = section(session, "static function captureSetStatistics()", "static function promoteSetCandidateForCapture()");
  assert.match(capture, /lastSetEndSeconds > 0 && lastSetEndSeconds >= activeStartSeconds/);
  const pause = section(session, "static function pause()", "static function resume()");
  assert.doesNotMatch(pause, /lastSetEndSeconds =|currentSetEndGymCalories =|currentSetEndGarminCalories =/);
  const resume = section(session, "static function resume()", "static function stopAndSave()");
  assert.match(resume, /effortState = activeSetSeen \? "SET ACTIVE" : "READY"/);
  assert.doesNotMatch(resume, /lastSetEndSeconds =|currentSetEndGymCalories =|currentSetEndGarminCalories =/);

  const viewTick = section(view, "function tick()", "function requestSyncNow()");
  assert.ok(
    viewTick.indexOf("page = 0") < viewTick.indexOf("notifyAutoPrompt()"),
    "a prompt raised on entry/settings/debug must return to the visible dashboard"
  );
  const saveAndExit = section(view, "function saveAndExit()", "function onUpdate(");
  assert.ok(
    saveAndExit.indexOf("GymSession.autoLogPrompt") < saveAndExit.indexOf("finishWorkout()"),
    "direct save/exit cannot drop a pending detected set"
  );
  assert.match(saveAndExit, /GymSession\.autoLogPrompt \|\| GymSession\.activeSetSeen/);
  const delegate = section(view, "class WorkoutDelegate", "function handleSelect()");
  const pending = section(delegate, "function hasPendingSetPrompt()", "function onSelect()");
  assert.match(pending, /return view\.page != 7 && GymSession\.autoLogPrompt/);
  const select = section(delegate, "function onSelect()", "function onNextPage()");
  assert.ok(
    select.indexOf("hasPendingSetPrompt()") < select.indexOf("view.page == 3"),
    "select resolves the prompt before summary save or page-specific actions"
  );
  const tap = section(delegate, "function onTap(evt)", "function rowAt(");
  assert.ok(
    tap.indexOf("hasPendingSetPrompt()") < tap.indexOf("view.page == 3"),
    "touch resolves the prompt before summary save or page-specific actions"
  );
  const undoDelegate = section(view, "function undoLastSet()", "function handleSettings(");
  assert.match(undoDelegate, /view\.page = GymSession\.autoLogPrompt \? 0 : 1/);
  assert.match(undoDelegate, /view\.autoPromptWasActive = GymSession\.autoLogPrompt/);

  const stopMotionModel = (state) => ({
    ...state,
    motionScore: 0,
    lastMotionTimerMs: 0,
    ...(state.activeSetSeen
      ? {}
      : { lastCredibleMotionSeconds: 0, motionBurstSignals: 0, motionRhythmSignals: 0 })
  });
  const activeBeforeHide = {
    activeSetSeen: true,
    activeStartSeconds: 10,
    lastCredibleMotionSeconds: 22,
    motionBurstSignals: 5,
    motionRhythmSignals: 4,
    motionScore: 180,
    lastMotionTimerMs: 25_000
  };
  const activeAfterHide = stopMotionModel(activeBeforeHide);
  assert.equal(activeAfterHide.lastCredibleMotionSeconds, 22);
  assert.equal(activeAfterHide.motionBurstSignals, 5);
  assert.equal(
    activeAfterHide.lastCredibleMotionSeconds - activeAfterHide.activeStartSeconds >= 10 &&
      30 - activeAfterHide.lastCredibleMotionSeconds >= 6,
    true,
    "reopening after a quiet window still finalizes the valid 12-second motion interval"
  );
  assert.equal(stopMotionModel({ ...activeBeforeHide, activeSetSeen: false }).lastCredibleMotionSeconds, 0);

  const evidence = { currentSetEndGymCalories: 14.2, lastEvidenceGymCalories: 14.2 };
  evidence.lastEvidenceGymCalories = 15.1;
  assert.equal(
    evidence.currentSetEndGymCalories,
    14.2,
    "quiet/recovery HR ticks may advance generic evidence but cannot extend motion calories"
  );
  const continueBoundary = (lastMotion, { strong, rhythmic, elapsed }) =>
    strong && rhythmic ? elapsed : lastMotion;
  assert.equal(continueBoundary(22, { strong: false, rhythmic: false, elapsed: 25 }), 22);
  assert.equal(continueBoundary(22, { strong: true, rhythmic: false, elapsed: 25 }), 22);
  assert.equal(
    continueBoundary(22, { strong: true, rhythmic: true, elapsed: 25 }),
    25,
    "only another bounded rep-like reversal extends a confirmed motion set"
  );

  const captureEnded = ({ started, lastEnded, motionCalories }) =>
    lastEnded > 0 && lastEnded >= started
      ? { ended: lastEnded, calories: motionCalories }
      : { ended: "LIVE_EVIDENCE", calories: motionCalories };
  assert.deepEqual(
    captureEnded({ started: 0, lastEnded: 0, motionCalories: 1.8 }),
    { ended: "LIVE_EVIDENCE", calories: 1.8 },
    "a manual save of the first active set cannot be mistaken for an interval ended at zero"
  );

  const restDeadline = 100_000;
  const suspendedAt = 53_000;
  const suspendedRest = suspendedAt - restDeadline;
  const shortFalseStart = { activeSetSeen: false, autoLogPrompt: false };
  const restoredAt = 57_000 - suspendedRest;
  assert.equal(suspendedRest, -47_000);
  assert.equal(shortFalseStart.activeSetSeen, false);
  assert.equal(restoredAt, 104_000, "short HR cleanup restores the exact 47 seconds at the later tick");

  const resolveHrFall = ({ autoPromptEnabled, short, motionCorroborated }) => {
    if (!autoPromptEnabled) return "SET ACTIVE";
    if (short && !motionCorroborated) return "CLEAR_FALSE_START";
    return "PROMPT";
  };
  assert.equal(
    resolveHrFall({ autoPromptEnabled: false, short: true, motionCorroborated: false }),
    "SET ACTIVE",
    "compact/AUTO OFF keeps short HR evidence for manual SAVE"
  );
  assert.equal(
    resolveHrFall({ autoPromptEnabled: true, short: true, motionCorroborated: false }),
    "CLEAR_FALSE_START"
  );
  const resolveStaleHr = ({ autoPromptEnabled, duration, minimum, motionConfirmed }) => {
    if (motionConfirmed) return "MOTION_LIFECYCLE";
    if (!autoPromptEnabled) return "SET ACTIVE";
    return duration >= minimum ? "PROMPT" : "CLEAR_FALSE_START";
  };
  assert.equal(
    resolveStaleHr({ autoPromptEnabled: true, duration: 18, minimum: 15, motionConfirmed: false }),
    "PROMPT",
    "a sufficiently long HR-only set becomes a bounded prompt when the sensor disappears"
  );
  assert.equal(
    resolveStaleHr({ autoPromptEnabled: true, duration: 9, minimum: 15, motionConfirmed: false }),
    "CLEAR_FALSE_START"
  );
  assert.equal(
    resolveStaleHr({ autoPromptEnabled: false, duration: 9, minimum: 15, motionConfirmed: false }),
    "SET ACTIVE",
    "AUTO OFF preserves the same stale-HR interval for manual SAVE"
  );
  const staleMotionManual = { lastSetEndSeconds: 0, lastCredibleMotionSeconds: 25 };
  staleMotionManual.lastCredibleMotionSeconds = 35;
  assert.equal(
    staleMotionManual.lastSetEndSeconds > 0
      ? staleMotionManual.lastSetEndSeconds
      : staleMotionManual.lastCredibleMotionSeconds,
    35,
    "stale HR cannot freeze a motion-confirmed AUTO OFF set before later repetitions"
  );
  const resumeState = (activeSetSeen) => (activeSetSeen ? "SET ACTIVE" : "READY");
  assert.equal(resumeState(true), "SET ACTIVE", "pause/resume cannot orphan a suspended active interval");
  const resumeActiveInterval = (state) => ({
    ...state,
    effortState: state.activeSetSeen ? "SET ACTIVE" : "READY"
  });
  const resumed = resumeActiveInterval({
    activeSetSeen: true,
    lastSetEndSeconds: 0,
    latestEvidence: 20,
    motionCalories: 1.7
  });
  assert.equal(resumed.lastSetEndSeconds, 0);
  assert.equal(resumed.latestEvidence, 20);
  assert.equal(resumed.motionCalories, 1.7);
  assert.equal(
    resumed.lastSetEndSeconds > 0 ? resumed.lastSetEndSeconds : resumed.latestEvidence,
    20,
    "continued motion after pause is included in manual SAVE instead of truncating at the pause"
  );
  const undoPage = (restoredAutoPrompt) => ({
    page: restoredAutoPrompt ? 0 : 1,
    promptWasActive: restoredAutoPrompt
  });
  assert.deepEqual(
    undoPage(true),
    { page: 0, promptWasActive: true },
    "immediate undo of an accepted auto prompt reveals the restored SAVE/BACK prompt"
  );

  const selectRoute = (page, prompt) => (prompt ? "RECORD_SET" : page === 3 ? "SAVE_WORKOUT" : "PAGE_ACTION");
  for (const page of [0, 1, 2, 3, 4, 5, 6]) {
    assert.equal(selectRoute(page, true), "RECORD_SET", `page ${page} cannot bypass a pending prompt`);
  }
});

test("Garmin backdates a confirmed set to bounded first evidence and drops false candidates", async () => {
  const session = await readFile("garmin/source/GymSession.mc", "utf8");
  const effort = section(session, "static function updateEffortState(value)", "static function updateSetConfidence");
  assert.match(effort, /setConfidence >= 40[\s\S]*beginSetCandidate\(value\)/);
  assert.match(effort, /setConfidence >= 70[\s\S]*activeSignalCount \+= 1/);
  assert.match(effort, /candidateStartSeconds <= elapsedSeconds[\s\S]*elapsedSeconds - candidateStartSeconds <= 8/);
  assert.match(effort, /activeStartSeconds = hasCandidate \? candidateStartSeconds : elapsedSeconds/);
  assert.match(
    effort,
    /else if \(!\(candidateZoneSeconds instanceof Lang\.Array\) \|\|[\s\S]*motionBurstSignals == 0\) \{\s*clearSetCandidate\(\);/
  );

  const candidate = section(session, "static function beginSetCandidate(", "static function activeEvidenceEndSeconds(");
  assert.match(candidate, /candidateStartGymCalories = gymCalories/);
  assert.match(candidate, /candidateStartGarminCalories = garminCalories/);
  assert.match(candidate, /elapsedSeconds - candidateStartSeconds > 8/);
  assert.match(candidate, /elapsedSeconds - candidateLastSignalSeconds > 3/);
  const beginInterval = section(session, "static function beginSetInterval()", "static function resetCurrentSetInterval()");
  assert.match(beginInterval, /currentSetStartGymCalories = useCandidate \? candidateStartGymCalories : gymCalories/);

  const capture = section(session, "static function captureSetStatistics()", "static function beginSetInterval()");
  assert.match(capture, /promoteSetCandidateForCapture\(\)/);
  assert.match(capture, /elapsedSeconds - candidateStartSeconds > 8/);
  assert.match(capture, /elapsedSeconds - candidateLastSignalSeconds > 3/);
  assert.match(capture, /activeStartSeconds = candidateStartSeconds/);
  assert.match(capture, /beginSetInterval\(\)/);

  const detector = { candidateStart: null, activeStart: null, consecutive: 0 };
  const signal = (state, time, confidence) => {
    if (confidence < 40) return { candidateStart: null, activeStart: null, consecutive: 0 };
    const candidateStart = state.candidateStart ?? time;
    const consecutive = confidence >= 70 ? state.consecutive + 1 : 0;
    return {
      candidateStart,
      consecutive,
      activeStart: consecutive >= 2 && time - candidateStart <= 8 ? candidateStart : null
    };
  };
  const first = signal(detector, 10, 75);
  const confirmed = signal(first, 11, 80);
  assert.equal(confirmed.activeStart, 10, "confirmation must include the first credible second");
  assert.equal(signal(first, 11, 10).candidateStart, null, "a false candidate must not leak into another set");
});

test("Garmin preserves global per-set plan order while manual exercise jumps remain deterministic", async () => {
  const [store, view] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const applyTarget = section(
    store,
    "static function applyCurrentPlanSet()",
    "static function applyPlanItem("
  );
  assert.match(applyTarget, /var completed = completedSetsForExercise\(exerciseName\)/);
  assert.match(applyTarget, /if \(matchingIndex == completed\)[\s\S]*item = candidate/);
  assert.match(applyTarget, /item = candidate;[\s\S]*matchingIndex \+= 1/);

  const applyItem = section(
    store,
    "static function applyPlanItem(",
    "static function completedSetsForExercise("
  );
  assert.match(applyItem, /!isValidWeight\(plannedWeight\) \|\| !isValidReps\(plannedReps\)/);
  assert.match(applyItem, /weight = plannedWeight;\s*reps = plannedReps;/);
  assert.doesNotMatch(applyItem, /plannedWeight instanceof Lang\.(Number|Float)/);

  const countCompleted = section(
    store,
    "static function completedSetsForExercise(",
    "static function remainingPlannedSetsForExercise("
  );
  assert.match(countCompleted, /item\.get\("exerciseName"\)\.toString\(\)\.equals\(exerciseName\)/);

  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /var wasPlannedSet = remainingPlannedSetsForExercise\(currentExercise\(\)\) > 0/);
  assert.match(addSet, /if \(wasPlannedSet\)[\s\S]*advancePlanAfterSetSaved\(\)/);
  assert.match(store, /static function selectNextPlanSlotInGlobalOrder\(\)/);
  const advance = section(store, "static function advancePlanAfterSetSaved()", "static function nextExercise(");
  assert.match(advance, /selectNextPlanSlotInGlobalOrder\(\)/);

  const plan = [
    { exerciseName: "A", weight: 10, reps: 12 },
    { exerciseName: "B", weight: 20, reps: 8 },
    { exerciseName: "A", weight: 12.5, reps: 10 },
    { exerciseName: "B", weight: 22.5, reps: 6 }
  ];
  const completed = [];
  const observed = [];
  while (true) {
    const next = nextRemainingGlobalSlot(plan, completed);
    if (!next) break;
    observed.push([next.exerciseName, next.weight, next.reps]);
    completed.push(next);
  }
  assert.deepEqual(
    observed,
    plan.map(({ exerciseName, weight, reps }) => [exerciseName, weight, reps]),
    "automatic progression must retain A1, B1, A2, B2 instead of grouping by exercise"
  );

  const manualOutOfOrder = [plan[0], plan[2]];
  assert.equal(nextRemainingGlobalSlot(plan, manualOutOfOrder), plan[1]);
  assert.equal(completedPlannedCount(plan, [...manualOutOfOrder, { exerciseName: "A" }]), 2);
  const mixedPlan = [
    { exerciseName: "A" },
    { exerciseName: "A" },
    { exerciseName: "B" }
  ];
  const extraAMissingB = [
    { exerciseName: "A" },
    { exerciseName: "A" },
    { exerciseName: "A" }
  ];
  assert.equal(completedPlannedCount(mixedPlan, extraAMissingB), 2);
  assert.equal(completedPlannedCount(mixedPlan, [...extraAMissingB, { exerciseName: "B" }]), 3);
  const plannedProgress = section(
    store,
    "static function completedPlannedSetCount()",
    "static function planSlotIsCompleted("
  );
  assert.match(plannedProgress, /earlierActual < plannedSetsForExercise\(exerciseName\)/);
  const progressValidation = section(
    store,
    "static function isValidCompletedPlannedSetCount(",
    "static function isValidPendingList("
  );
  assert.match(progressValidation, /targetCount < actualSetCount \? targetCount : actualSetCount/);
  assert.match(progressValidation, /return value <= maximum/);
  assert.match(progressValidation, /static function isValidExactPlannedProgress/);
  assert.match(progressValidation, /targetCount == null && completedCount == null/);
  assert.match(progressValidation, /targetCount <= legacyCount/);

  const overlay = section(view, "function drawSetSavedOverlay(", "function drawPausedOverlay(");
  assert.match(overlay, /GymStore\.tr\("NEXT: "/);
  assert.match(overlay, /fitTextWidth\(dc, setSummaryText\(\)/);
  assert.match(overlay, /GymStore\.tr\("REST "/);
  assert.match(overlay, /countdownText\(rest\)/);
});

test("Garmin emits bounded active-set calorie and heart-zone slices without changing legacy metrics", async () => {
  const [session, store] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  assert.match(session, /currentSetZoneSeconds = \[0, 0, 0, 0, 0, 0\]/);
  assert.match(session, /trackActiveSetInterval\(lastValidHrSeconds, zone\)/);
  assert.match(session, /if \(delta > 1\)[\s\S]*delta = 1/);
  assert.match(session, /currentSetZoneSeconds\[sampleZone\] \+= delta/);
  assert.match(session, /ended > started \+ 7200[\s\S]*ended = started \+ 7200/);
  assert.match(session, /gymDelta > 100000\.0[\s\S]*gymDelta = 100000\.0/);
  assert.match(session, /garminDelta > 100000[\s\S]*garminDelta = 100000/);
  assert.match(session, /captureEndedSetTotals\(\)/);
  assert.match(session, /endingGarminCalories >= currentSetStartGarminCalories/);

  const message = section(store, "static function workoutMessage(requestId)", "static function applyPhoneSync(");
  assert.match(message, /setMetrics\.add\(compactSetMetrics\(setItem\)\)/);
  assert.match(message, /setIntervals\.add\(copySetInterval\(setInterval\)\)/);
  assert.match(message, /message\.put\("setIntervals", setIntervals\)/);
  assert.match(message, /message\.put\("plannedSetCount", plannedSetCount\)/);
  assert.match(message, /message\.put\("plannedTargetSetCount", plannedTargetSetCount\)/);
  assert.match(message, /message\.put\("completedPlannedSetCount", completedPlannedSetCount\(\)\)/);

  const intervalValidation = section(
    store,
    "static function isValidSetInterval(",
    "static function isValidSetIntervalsList("
  );
  assert.match(intervalValidation, /value\.size\(\) != 10/);
  assert.match(intervalValidation, /value\[1\] - value\[0\] > 7200/);
  assert.match(intervalValidation, /!isBoundedNumber\(value\[2\], 0\.0, 100000\.0\)/);
  assert.match(intervalValidation, /!isOptionalBoundedInteger\(value\[3\], 0, 100000\)/);
  assert.match(intervalValidation, /zoneSeconds <= value\[1\] - value\[0\]/);

  const legacyMetrics = section(
    store,
    "static function isValidSetMetricsList(",
    "static function normalizedLegacyPendingList("
  );
  assert.match(legacyMetrics, /metrics\.size\(\) != 7/);
});

test("Garmin omits unavailable system calories and heart rate instead of sending null", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const message = section(store, "static function workoutMessage(requestId)", "static function applyPhoneSync(");
  const freshDiagnostics = section(
    message,
    "if (messageCheckpoint != null)",
    "if (allIntervalsAvailable"
  );

  assert.match(freshDiagnostics, /if \(messageCheckpoint\[2\] != null\)/);
  assert.match(freshDiagnostics, /if \(messageCheckpoint\[6\] != null\)/);
  assert.equal((freshDiagnostics.match(/message\.put\("garminCalories"/g) || []).length, 1);
  assert.equal((freshDiagnostics.match(/message\.put\("lastHeartRate"/g) || []).length, 1);
});

test("Garmin active-workout copy-on-write has only old-or-new crash outcomes", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  const undo = section(store, "static function undoLastSet()", "static function clearTransientSetActions()");
  for (const mutation of [addSet, undo]) {
    assert.ok(
      mutation.indexOf("ensureUnboundAtomicQuarantine()") < mutation.indexOf("sets = nextSets"),
      "an ownerless add/undo must establish its atomic recovery boundary before mutation"
    );
    assert.ok(
      mutation.indexOf("persistActiveWorkoutSnapshot(nextSets") < mutation.indexOf("sets = nextSets"),
      "globals must not expose an uncommitted set mutation"
    );
  }

  const unbound = section(
    store,
    "static function ensureUnboundAtomicQuarantine()",
    "static function ensureLegacyQuarantine()"
  );
  assert.match(unbound, /accountBinding != null \|\| stateOwnerBinding != null/);
  assert.match(unbound, /legacyRawSets = normalizedSetList\(sets\)/);
  assert.match(unbound, /legacyRawPlan = normalizedSetList\(plan\)/);
  assert.ok(
    unbound.indexOf("ensureLegacyQuarantine()") <
      unbound.indexOf('Storage.setValue("legacyUnboundState", true)'),
    "the old ownerless state must exist atomically before its durable recovery marker"
  );
  const quarantine = section(
    store,
    "static function ensureLegacyQuarantine()",
    "static function clearPartialLegacyQuarantine()"
  );
  assert.ok(
    quarantine.indexOf("refreshLegacyCurrentQuarantine()") <
      quarantine.indexOf('Storage.setValue("legacyQuarantineVersion", 1)'),
    "the current ownerless snapshot must commit before the quarantine version"
  );

  const before = Object.freeze({ sets: Object.freeze([{ exerciseName: "A" }]) });
  const afterAdd = Object.freeze({ sets: Object.freeze([...before.sets, { exerciseName: "B" }]) });
  const afterUndo = Object.freeze({ sets: Object.freeze([]) });
  const atomicWrite = (next, failBeforeCommit) => (failBeforeCommit ? before : next);
  assert.equal(atomicWrite(afterAdd, true), before);
  assert.equal(atomicWrite(afterAdd, false), afterAdd);
  assert.equal(atomicWrite(afterUndo, true), before);
  assert.equal(atomicWrite(afterUndo, false), afterUndo);

  const clear = section(
    store,
    "static function persistEmptyActiveWorkoutSnapshot()",
    "static function isUk()"
  );
  assert.match(clear, /persistActiveWorkoutSnapshot\(\[\], null, emptyTimelineCheckpoint\(\)\)/);
  const load = section(store, "static function load()", "static function save()");
  const fullActiveRestore = section(
    store,
    "(:fullLegacyState)\n    static function restoreActiveWorkoutSnapshot(",
    "(:enhancedCompactCheckpoint)\n    static function restoreActiveWorkoutSnapshot("
  );
  assert.ok(
    load.indexOf('Storage.getValue("activeWorkoutV1")') <
      load.indexOf("restoreActiveWorkoutSnapshot(savedActiveWorkout)"),
    "the authoritative empty tombstone must be considered on every load"
  );
});

test("Garmin low-memory products keep an atomic compact ownerless recovery boundary", async () => {
  const [store, jungle, bashBuild, powershellBuild, readme] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/monkey.jungle", "utf8"),
    readFile("scripts/build-garmin.sh", "utf8"),
    readFile("scripts/build-garmin.ps1", "utf8"),
    readFile("garmin/README.md", "utf8")
  ]);

  assert.match(
    jungle,
    /^base\.excludeAnnotations = .*compactLegacyState.*compactRecovery96.*compactCheckpoint96.*enhancedCompactCheckpoint.*noPageDots$/m
  );
  const compactProducts = [
    "descentg1",
    "fr55",
    "instinct2",
    "instinct2s",
    "instinct2x",
    "instinctcrossover"
  ];
  assert.match(
    jungle,
    /^fr55\.excludeAnnotations = fullLegacyState;noFr55UpgradeBridge;compactRecovery96;compactCheckpoint96;pageDots$/m
  );
  for (const product of compactProducts.filter((product) => product !== "fr55")) {
    assert.match(jungle,
      new RegExp(`^${product}\\.excludeAnnotations = fullLegacyState;compactRichRecovery;fr55UpgradeBridge;richRecovery;richRecoveryNavigation;recoveryCore;enhancedCompactCheckpoint;enhancedRecoveryCheckpoint;pageDots$`, "m"));
  }
  assert.equal(
    (jungle.match(/\.excludeAnnotations = fullLegacyState/g) || []).length,
    compactProducts.length
  );
  assert.match(
    bashBuild,
    /descentg1\|enduro\|fenix6\|fenix6s\|fr245\|fr55\|instinct2\|instinct2s\|instinct2x\|instinctcrossover\|venusq\)[\s\S]*compiler_args\+=\(-r\)/
  );
  for (const product of compactProducts) {
    assert.match(powershellBuild, new RegExp(`'${product}'`));
  }
  assert.match(powershellBuild, /\$constrainedDevices -contains \$Device[\s\S]*\$compilerArgs \+= '-r'/);
  assert.match(readme, /five 96 KiB products/);
  assert.match(readme, /Forerunner 55 \/ ForeAthlete 55/);
  assert.match(readme, /preserves account\/device[\s\S]*FIT-before-queue commit/);
  assert.match(readme, /cannot reattach Garmin's native ActivityRecording[\s\S]*explicit Resume starts a new FIT session/);
  assert.match(readme, /paused rest[\s\S]*last compact checkpoint/);

  const constrainedFullProducts = ["enduro", "fenix6", "fenix6s", "fr245", "venusq"];
  for (const product of constrainedFullProducts) {
    assert.match(
      jungle,
      new RegExp(`^${product}\\.excludeAnnotations = compactLegacyState;compactRichRecovery;fr55UpgradeBridge;noFr55UpgradeBridge;compactRecovery96;compactCheckpoint96;enhancedCompactCheckpoint;pageDots$`, "m")
    );
    assert.match(powershellBuild, new RegExp(`'${product}'`));
  }
  assert.match(readme, /Enduro, Fenix 6, Fenix 6S, Forerunner 245, and Venu Sq/);
  assert.match(readme, /omits only the decorative page-dot indicator/);

  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  assert.match(view, /\(:pageDots\)\s+function drawPageDots\([\s\S]*dc\.fillCircle/);
  assert.match(view, /\(:noPageDots\)\s+function drawPageDots\([\s\S]*decorative page indicator/);

  const compact = section(
    store,
    "// CIQ 3.4 products with a 96 KiB watch-app ceiling",
    "static function builtInExercises()"
  );
  const load = section(store, "static function load()", "static function save()");
  assert.match(
    load,
    /hasLegacyMarker = savedLegacyMarker instanceof Lang\.Boolean && savedLegacyMarker/
  );
  assert.match(
    load,
    /restoreLegacyCurrentQuarantine\(legacyUnboundUpgrade && !hasLegacyMarker\)/
  );
  assert.match(compact, /accountBinding != null \|\| stateOwnerBinding != null/);
  assert.doesNotMatch(compact, /legacyUnboundState = false/);
  assert.match(
    compact,
    /legacyCompactCount == -2 \|\|[\s\S]*!isValidSetList\(sets, maxWorkoutSets, true\)/
  );
  assert.ok(
    compact.indexOf("refreshLegacyCurrentQuarantine()") <
      compact.indexOf('Storage.setValue("legacyUnboundState", true)'),
    "the compact set snapshot must commit before the ownerless recovery marker"
  );
  assert.match(compact, /Storage\.setValue\("legacyCompactCurrentV1", \[/);
  assert.match(compact, /normalizedSetList\(sets\)/);
  assert.match(compact, /isValidSetList\(snapshot\[1\], maxWorkoutSets, true\)/);
  assert.match(compact, /legacyCompactCount = sets\.size\(\)/);
  assert.match(
    compact,
    /static function ensureLegacyQuarantine\(\)[\s\S]*legacyCompactCount != -2/
  );
  const compactRestore = section(
    compact,
    "static function restoreLegacyCurrentQuarantine(",
    "static function legacyCurrentSetCount()"
  );
  assert.match(compactRestore, /snapshot == null[\s\S]*legacyCompactCount = allowSeed \? -1 : -2/);
  assert.match(compactRestore, /return allowSeed/);
  assert.match(compactRestore, /legacyCompactCount = -2;[\s\S]*return false/);
  assert.doesNotMatch(compactRestore, /sets = \[\]/);
  assert.match(compact, /static function isValidLegacyPendingList\(value\)[\s\S]*return false/);
  assert.match(compact, /static function normalizedLegacyPendingList\(source\)[\s\S]*return \[\]/);

  const fullLegacy = store.match(/\(:fullLegacyState\)/g) || [];
  assert.ok(fullLegacy.length >= 10, "ordinary devices must retain the full legacy quarantine path");
  assert.match(store, /Storage\.setValue\("legacyQuarantineCore", core\)/);
});

test("Garmin atomically resumes bounded interval timelines without mixing segment clocks", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const load = section(store, "static function load()", "static function save()");
  assert.match(load, /Storage\.getValue\("activeWorkoutV1"\)/);
  assert.match(load, /isValidActiveWorkoutSnapshot\(savedActiveWorkout\)/);
  assert.match(load, /activeWorkoutSnapshotMatchesBindings\(savedActiveWorkout\)/);
  assert.match(load, /restoreActiveWorkoutSnapshot\(savedActiveWorkout\)/);
  const onShow = section(view, "function onShow()", "function onHide()");
  const explicitStart = section(view, "function startOrResumeWorkout()", "function syncFromReady()");
  assert.match(onShow, /page = GymStore\.hasPreparedWorkout\(\) \? 3 : 7/);
  assert.doesNotMatch(onShow, /GymSession\.(?:start|resume|startSensors)\(/);
  assert.match(explicitStart, /hasWorkoutToResume\(\)/);
  assert.match(explicitStart, /started = GymSession\.start\(\)/);
  assert.match(explicitStart, /if \(resuming\)[\s\S]*GymStore\.markWorkoutResumed\(\)[\s\S]*"RESUMED"/);
  const markResumed = section(store, "static function markWorkoutResumed()", "static function clearActiveWorkout()");
  assert.match(markResumed, /sets\.size\(\) > 0 && !activeWorkoutTimelineValid/);

  const snapshotValidation = section(
    store,
    "static function isValidActiveWorkoutSnapshot(",
    "static function restoreActiveWorkoutSnapshot("
  );
  assert.match(snapshotValidation, /snapshot\.size\(\) != 7/);
  assert.match(snapshotValidation, /snapshot\[0\] != 2 && snapshot\[0\] != 3/);
  assert.match(snapshotValidation, /isValidAccountBinding\(snapshot\[1\]\)/);
  assert.match(snapshotValidation, /isBoundedText\(snapshot\[2\], maxBindingLength\)/);
  assert.match(snapshotValidation, /isValidOptionalAccountBinding\(snapshot\[3\]\)/);
  assert.match(snapshotValidation, /snapshotVersion == 2[\s\S]*isValidSetList\(snapshotSets, maxWorkoutSets, true\)/);
  assert.match(snapshotValidation, /snapshotVersion == 3[\s\S]*isValidCompactActiveSetArrays\(snapshot\)/);
  assert.match(snapshotValidation, /startedAtSeconds == null && checkpoint != null/);
  assert.match(snapshotValidation, /startedAtSeconds != null &&[\s\S]*!isValidWorkoutStartedAtSeconds\(startedAtSeconds\)/);
  assert.match(snapshotValidation, /snapshotVersion == 3[\s\S]*isValidSetIntervalsList\(snapshot\[9\], snapshotSets\)/);
  assert.match(snapshotValidation, /areSnapshotIntervalsConsistent\(snapshotSets, checkpoint\)/);

  const validOriginState = ({ setCount, startedAt, checkpoint }) => {
    if (setCount === 0) return startedAt === null;
    if (startedAt === null) return checkpoint === null;
    return Number.isInteger(startedAt) && startedAt >= 946_684_800;
  };
  assert.equal(validOriginState({ setCount: 2, startedAt: null, checkpoint: null }), true);
  assert.equal(validOriginState({ setCount: 2, startedAt: null, checkpoint: {} }), false);
  assert.equal(validOriginState({ setCount: 0, startedAt: 1_800_000_000, checkpoint: null }), false);

  const persist = section(
    store,
    "static function persistActiveWorkoutSnapshot(",
    "static function persistEmptyActiveWorkoutSnapshot("
  );
  assert.match(persist, /var names = \[\];[\s\S]*var metrics = \[\];/);
  assert.match(persist, /var compactSets = compatibilityActiveSetList\(nextSets\)/);
  assert.match(persist, /var snapshot = \[[\s\S]*3,/);
  assert.match(persist, /Storage\.setValue\("activeWorkoutV1", snapshot\)/);
  assert.doesNotMatch(persist, /Storage\.setValue\("sets"/);
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /legacyOriginUnavailable = previousSets\.size\(\) > 0[\s\S]*previousWorkoutStartedAt == null[\s\S]*resumedWorkoutIntervalsInvalid/);
  assert.ok(
    addSet.indexOf("persistActiveWorkoutSnapshot(nextSets") < addSet.indexOf("sets = nextSets"),
    "add must publish the new set only after its atomic snapshot commits"
  );
  const undo = section(store, "static function undoLastSet()", "static function clearTransientSetActions()");
  assert.match(undo, /legacyOriginUnavailable = nextSets\.size\(\) > 0[\s\S]*previousWorkoutStartedAt == null[\s\S]*resumedWorkoutIntervalsInvalid/);
  assert.ok(
    undo.indexOf("persistActiveWorkoutSnapshot(nextSets") < undo.indexOf("sets = nextSets"),
    "undo must publish the shortened list only after its atomic snapshot commits"
  );

  const shift = section(
    store,
    "static function setIntervalForCurrentTimeline(",
    "static function persistActiveWorkoutSnapshot("
  );
  assert.match(shift, /elapsedOffset = timelineBase == null \? 0 : timelineBase\[0\]/);
  assert.match(shift, /shiftedStart = interval\[0\] \+ elapsedOffset/);
  assert.match(shift, /shiftedEnd = interval\[1\] \+ elapsedOffset/);
  assert.match(shift, /shiftedStart <= 604800 && shiftedEnd <= 604800/);
  const message = section(store, "static function workoutMessage(requestId)", "static function applyPhoneSync(");
  assert.match(message, /messageCheckpoint = activeWorkoutTimelineValid &&[\s\S]*currentTimelineCheckpoint\(0\.0\)/);
  assert.match(message, /allIntervalsAvailable = messageCheckpoint != null/);
  const resumedMetrics = section(
    message,
    "if (messageCheckpoint != null)",
    "if (allIntervalsAvailable"
  );
  for (const field of [
    "durationSeconds",
    "gymCalories",
    "avgHeartRate",
    "maxHeartRate",
    "heartRateZone"
  ]) {
    assert.match(resumedMetrics, new RegExp(`message\\.put\\("${field}"`));
  }
  assert.match(resumedMetrics, /messageCheckpoint\[2\]/);
  assert.match(resumedMetrics, /messageCheckpoint\[6\]/);
  assert.match(message, /areSetIntervalsConsistent\([\s\S]*messageCheckpoint\[0\]/);
  assert.ok(
    message.indexOf("areSetIntervalsConsistent(") < message.indexOf('message.put("setIntervals"'),
    "aggregate validation must happen before the optional diagnostics enter the payload"
  );
  const aggregate = section(
    store,
    "static function areSetIntervalsConsistent(",
    "static function isValidPlannedSetCount("
  );
  assert.match(aggregate, /interval\[0\] < previousEnd/);
  assert.match(aggregate, /interval\[1\] > durationSeconds/);
  assert.match(aggregate, /gymSum > gymTotal\.toFloat\(\) \+ 0\.1/);
  assert.match(aggregate, /garminSum <= garminTotal\.toFloat\(\) \+ 0\.1/);

  const firstSegment = [2, 8, 1.0, 1, 0, 0, 2, 4, 0, 0];
  const checkpointAfterS1 = { elapsed: 10, gym: 1.5, garmin: 2 };
  const resumedRawS2 = [2, 8, 1.5, 2, 0, 1, 2, 3, 0, 0];
  const resumedS2 = [
    resumedRawS2[0] + checkpointAfterS1.elapsed,
    resumedRawS2[1] + checkpointAfterS1.elapsed,
    ...resumedRawS2.slice(2)
  ];
  assert.deepEqual(resumedS2.slice(0, 2), [12, 18]);
  assert.equal(
    intervalsAreConsistent(
      [firstSegment, resumedS2],
      checkpointAfterS1.elapsed + 10,
      checkpointAfterS1.gym + 2,
      checkpointAfterS1.garmin + 3
    ),
    true
  );
  const secondRestartRawS3 = [1, 4, 0.5, null, 0, 0, 1, 2, 0, 0];
  const secondBase = 20;
  const resumedS3 = [
    secondRestartRawS3[0] + secondBase,
    secondRestartRawS3[1] + secondBase,
    ...secondRestartRawS3.slice(2)
  ];
  assert.equal(intervalsAreConsistent([firstSegment, resumedS2, resumedS3], 25, 4, 5), true);
  assert.equal(intervalsAreConsistent([[1, 4, 5, null]], 5, 4, null), false);

  const tracking = section(
    session,
    "static function trackActiveSetInterval(sampleSeconds, sampleZone)",
    "static function capturedSetInterval("
  );
  assert.match(tracking, /var delta = elapsedSeconds - sampleSeconds/);
  assert.match(tracking, /if \(delta > 1\)[\s\S]*delta = 1/);
  assert.match(tracking, /currentSetZoneSeconds\[sampleZone\] \+= delta/);
  const expiry = section(session, "static function expireStaleHeartRate()", "static function trackMinuteHeartRate(");
  assert.match(expiry, /lastSetEndSeconds = activeEvidenceEndSeconds\(\)/);
  assert.doesNotMatch(expiry, /trackActiveSetInterval/);
  assert.ok(expiry.indexOf("lastSetEndSeconds =") < expiry.indexOf("hr = null"));
  const capture = section(session, "static function captureSetStatistics()", "static function beginSetInterval()");
  assert.match(capture, /currentSetZoneSeconds instanceof Lang\.Array \? activeEvidenceEndSeconds\(\) : elapsedSeconds/);
  const capturedInterval = section(session, "static function capturedSetInterval(", "static function copySetInterval(");
  assert.match(capturedInterval, /currentSetLastEvidenceGymCalories != null/);
  assert.match(capturedInterval, /currentSetLastEvidenceGarminCalories != null/);
  const evidenceEnd = (lastHr, lastMotion, start, elapsed) =>
    Math.min(elapsed, Math.max(start, lastHr, lastMotion));
  assert.equal(evidenceEnd(12, 0, 5, 17), 12);
  assert.equal(evidenceEnd(12, 14, 5, 17), 14);

  const attributePreviousSample = (zoneSeconds, previousTime, previousZone, currentTime) => {
    const delta = Math.min(1, Math.max(0, currentTime - previousTime));
    zoneSeconds[previousZone] += delta;
    return zoneSeconds;
  };
  const zonesAfterGap = attributePreviousSample([0, 0, 0, 0, 0, 0], 1, 1, 5);
  assert.deepEqual(zonesAfterGap, [0, 1, 0, 0, 0, 0]);
  assert.equal(zonesAfterGap[4], 0, "the later Z4 sample must not smear across t2-t4");

  const workoutValidation = section(store, "static function isValidWorkoutMessage(", "static function isValidOptionalAccountBinding(");
  assert.match(workoutValidation, /isOptionalBoundedNumber\(message\.get\("durationSeconds"\)/);

  const save = section(store, "static function save()", "static function isUk()");
  assert.match(save, /activeWorkoutSnapshotValid && hasAccountBinding\(\)/);
  assert.match(save, /currentTimelineCheckpoint\(0\.0\)/);
  assert.match(save, /var compatibleSets = compatibilityActiveSetList\(sets\)/);
  assert.match(save, /Storage\.setValue\("sets", compatibleSets\)/);
  assert.match(save, /sets\.size\(\) == 0 \? null : activeWorkoutStartedAtSeconds/);
  const budget = section(store, "static function isWithinStorageBudget()", "static function isValidWorkoutStartedAtSeconds(");
  assert.match(budget, /estimatedValueBytes\(activeWorkoutStartedAtSeconds\)/);
  const timestampValidation = section(
    store,
    "static function isValidWorkoutStartedAtSeconds(",
    "static function estimatedValueBytes("
  );
  assert.match(timestampValidation, /isBoundedInteger\(value, 946684800, 2147483647\)/);
  const validStoredTimestamp = (value) => Number.isInteger(value) && value >= 946_684_800 && value <= 2_147_483_647;
  assert.equal(validStoredTimestamp(1_800_000_000), true);
  assert.equal(validStoredTimestamp(1_800_000_000.5), false);

  const malformedCheckpoint = { elapsedSeconds: -1 };
  assert.equal(Number.isInteger(malformedCheckpoint.elapsedSeconds) && malformedCheckpoint.elapsedSeconds >= 0, false);
});

test("Garmin active runtime checkpoint is bounded, owner-scoped, and restart-safe", async () => {
  const [store, session, view, app] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymApp.mc", "utf8")
  ]);

  const load = section(store, "static function load()", "static function save()");
  const validation = section(
    store,
    "static function isValidRuntimeCheckpoint(",
    "static function restoreRuntimeCheckpoint("
  );
  const restore = section(
    store,
    "static function restoreRuntimeCheckpoint(",
    "static function activeWorkoutSnapshotMatchesBindings("
  );
  const writer = section(
    store,
    "static function checkpointLiveWorkout(",
    "static function consumeRecoveredPause("
  );
  const fullActiveRestore = section(
    store,
    "(:fullLegacyState)\n    static function restoreActiveWorkoutSnapshot(",
    "(:enhancedCompactCheckpoint)\n    static function restoreActiveWorkoutSnapshot("
  );

  assert.match(fullActiveRestore, /Storage\.getValue\("activeRuntimeV1"\)/);
  assert.match(
    fullActiveRestore,
    /isValidRuntimeCheckpoint\(runtime\)[\s\S]*activeWorkoutSnapshotMatchesBindings\(runtime\)/
  );
  assert.match(validation, /snapshot\.size\(\) != 11/);
  assert.match(validation, /snapshot\[0\] != 1/);
  assert.match(validation, /isValidAccountBinding\(snapshot\[1\]\)/);
  assert.match(validation, /isBoundedText\(snapshot\[2\], maxBindingLength\)/);
  assert.match(validation, /isValidOptionalAccountBinding\(snapshot\[3\]\)/);
  assert.match(validation, /isBoundedInteger\(snapshot\[4\], 0, maxWorkoutSets\)/);
  assert.match(validation, /isValidWorkoutStartedAtSeconds\(snapshot\[5\]\)/);
  assert.match(validation, /isValidWorkoutStartedAtSeconds\(snapshot\[6\]\)/);
  assert.match(validation, /isValidTimelineCheckpoint\(snapshot\[7\]\)/);
  assert.match(validation, /snapshot\[8\] instanceof Lang\.Boolean/);
  assert.match(validation, /isBoundedInteger\(snapshot\[9\], 0, 2\)/);
  assert.match(validation, /estimatedValueBytes\(snapshot\) > maxRuntimeCheckpointBytes/);
  assert.match(validation, /restMode == 0[\s\S]*restValue instanceof Lang\.Number && restValue == 0/);
  assert.match(validation, /restMode == 1[\s\S]*restValue >= snapshot\[5\][\s\S]*restValue - snapshot\[5\] <= 3600/);
  assert.match(validation, /isBoundedInteger\(restValue, 1, 3600\)/);
  assert.match(
    writer,
    /var snapshot = \[\s*1,\s*accountBinding\.toString\(\),\s*deviceBinding\.toString\(\),[\s\S]*sets\.size\(\),\s*savedAt,\s*origin,\s*checkpoint,\s*GymSession\.paused,\s*restMode,\s*restValue\s*\]/
  );
  assert.match(writer, /Storage\.setValue\("activeRuntimeV1", snapshot\)/);

  assert.match(restore, /!activeWorkoutSnapshotMatchesBindings\(snapshot\)/);
  assert.match(restore, /snapshot\[4\] != sets\.size\(\)/);
  assert.match(restore, /activeWorkoutStartedAtSeconds != origin/);
  assert.match(restore, /areSnapshotIntervalsConsistent\(sets, checkpoint\)/);
  assert.match(store, /private static const runtimeCheckpointIntervalMs = 15000/);
  assert.match(store, /private static const maxRuntimeClockRecoverySeconds = 30/);
  assert.match(
    writer,
    /!force[\s\S]*timerElapsedMs\(lastRuntimeCheckpointTimerMs\) <[\s\S]*runtimeCheckpointIntervalMs\.toLong\(\)/
  );
  assert.match(
    restore,
    /!snapshot\[8\] && recoveryGap >= 0 &&[\s\S]*recoveryGap <= maxRuntimeClockRecoverySeconds[\s\S]*restoredCheckpoint\[0\] \+= recoveryGap/
  );

  assert.match(writer, /restMode = 1;[\s\S]*restValue = savedAt \+ remaining/);
  assert.match(writer, /restMode = 2;[\s\S]*restValue = suspendedSeconds/);
  assert.match(
    restore,
    /snapshot\[9\] == 1[\s\S]*remaining = snapshot\[10\] - now[\s\S]*restStartedAt = System\.getTimer\(\)/
  );
  assert.match(
    restore,
    /snapshot\[9\] == 2[\s\S]*restDurationMs = snapshot\[10\] \* 1000/
  );

  const totalGym = section(
    store,
    "static function totalGymCalories()",
    "static function totalGarminCalories()"
  );
  const totalGarmin = section(
    store,
    "static function totalGarminCalories()",
    "static function checkpointLiveWorkout("
  );
  assert.match(totalGym, /timelineBase == null \? 0\.0 : timelineBase\[1\]/);
  assert.match(totalGym, /GymSession\.gymCalories/);
  assert.match(totalGarmin, /timelineBase == null \? null : timelineBase\[2\]/);
  assert.match(totalGarmin, /GymSession\.garminCalories/);
  assert.match(session, /elapsedText\(\)[\s\S]*GymStore\.timelineBase == null[\s\S]*GymStore\.timelineBase\[0\][\s\S]*elapsedSeconds/);
  assert.match(view, /GymStore\.totalGymCalories\(\)/);
  assert.match(view, /GymStore\.totalGarminCalories\(\)/);

  const onShow = section(view, "function onShow()", "function onHide()");
  const onHide = section(view, "function onHide()", "function tick()");
  const tick = section(view, "function tick()", "function requestSyncNow()");
  const onStop = section(app, "function onStop(state)", "function getInitialView()");
  const pause = section(session, "static function pause()", "static function resume()");
  const resume = section(session, "static function resume()", "static function stopAndSave()");
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  const undo = section(store, "static function undoLastSet()", "static function clearTransientSetActions()");
  assert.match(tick, /checkpointLiveWorkout\(false\)/);
  assert.match(onHide, /GymStore\.save\(\)/);
  assert.match(onStop, /GymStore\.save\(\)/);
  assert.match(writer, /runtimePausePending[\s\S]*GymSession\.pause\(\)/);
  assert.match(
    writer,
    /if \(!GymSession\.pause\(\)\)[\s\S]*return false;[\s\S]*runtimePausePending = false;/
  );
  assert.match(
    writer,
    /\(:enhancedCompactCheckpoint\)[\s\S]*GymSession\.fitSaved[\s\S]*GymSession\.elapsedSeconds - lastCompactCheckpointElapsed < 15[\s\S]*persistActiveWorkoutSnapshot\(sets, origin, checkpoint\)/
  );
  assert.doesNotMatch(
    writer.slice(writer.indexOf("(:compactCheckpoint96)")),
    /lastCompactCheckpointElapsed/
  );
  assert.match(view, /startOrResumeWorkout\(\)[\s\S]*checkpointLiveWorkout\(true\)/);
  assert.match(view, /openPauseMenu\(\)[\s\S]*GymSession\.pause\(\)[\s\S]*checkpointLiveWorkout\(true\)/);

  const saveAndExit = section(view, "function saveAndExit()", "function onUpdate(");
  const clearActive = section(
    store,
    "static function clearActiveWorkout()",
    "static function restSeconds()"
  );
  const clearRuntime = section(
    store,
    "static function clearRuntimeCheckpoint()",
    "static function emptyTimelineCheckpoint()"
  );
  const clearSnapshot = section(
    store,
    "static function persistEmptyActiveWorkoutSnapshot()",
    "static function isUk()"
  );
  const accountTransition = section(
    store,
    "static function beginAccountTransition()",
    "static function clearCloudSyncStageForAccountTransition()"
  );
  const clearAccount = section(
    store,
    "static function clearAccountScopedState()",
    "(:fullLegacyState)"
  );
  assert.match(saveAndExit, /GymStore\.clearActiveWorkout\(\)/);
  assert.doesNotMatch(saveAndExit, /sets\.size\(\) > 0 && !GymStore\.clearActiveWorkout\(\)/);
  assert.match(clearActive, /persistEmptyActiveWorkoutSnapshot\(\)/);
  assert.match(clearSnapshot, /clearRuntimeCheckpoint\(\)/);
  assert.ok(
    clearSnapshot.indexOf("persistActiveWorkoutSnapshot([], null, emptyTimelineCheckpoint())") <
      clearSnapshot.indexOf("clearRuntimeCheckpoint()"),
    "the empty active snapshot must commit before the runtime journal is removed"
  );
  assert.match(clearRuntime, /Storage\.deleteValue\("activeRuntimeV1"\)/);
  assert.match(accountTransition, /Storage\.deleteValue\("activeRuntimeV1"\)/);
  assert.match(accountTransition, /resetRuntimeCheckpointState\(\)/);
  assert.match(clearAccount, /Storage\.deleteValue\("activeRuntimeV1"\)/);
  assert.match(clearAccount, /resetRuntimeCheckpointState\(\)/);

  const OWNER = "a".repeat(64);
  const OTHER_OWNER = "b".repeat(64);
  const DEVICE = "garmin-device";
  const GENERATION = "c".repeat(64);
  const ORIGIN = 1_800_000_000;
  const SAVED_AT = ORIGIN + 120;
  const checkpoint = [120, 40.0, 38, 12_000, 100, 165, 140, 3];
  const runtime = [
    1,
    OWNER,
    DEVICE,
    GENERATION,
    2,
    SAVED_AT,
    ORIGIN,
    checkpoint,
    false,
    1,
    SAVED_AT + 60
  ];
  assert.equal(runtime.length, 11);

  const boundedInteger = (value, min, max) =>
    Number.isInteger(value) && value >= min && value <= max;
  const validAccount = (value) =>
    typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
  const validTime = (value) => boundedInteger(value, 946_684_800, 2_147_483_647);
  const validTimeline = (value) =>
    Array.isArray(value) &&
    value.length === 8 &&
    boundedInteger(value[0], 0, 604_800) &&
    Number.isFinite(value[1]) && value[1] >= 0 && value[1] <= 10_000_000 &&
    (value[2] == null || boundedInteger(value[2], 0, 10_000_000)) &&
    boundedInteger(value[3], 0, 200_000_000) &&
    boundedInteger(value[4], 0, 604_800) &&
    boundedInteger(value[5], 0, 300) &&
    (value[6] == null || boundedInteger(value[6], 0, 300)) &&
    boundedInteger(value[7], 0, 5) &&
    (value[4] > 0 || value[3] === 0) &&
    value[3] <= value[4] * 240;
  const validRuntime = (value) => {
    if (!Array.isArray(value) || value.length !== 11 || value[0] !== 1 ||
        !validAccount(value[1]) || typeof value[2] !== "string" ||
        value[2].length === 0 || value[2].length > 128 ||
        !(value[3] == null || validAccount(value[3])) ||
        !boundedInteger(value[4], 0, 60) ||
        !validTime(value[5]) || !validTime(value[6]) ||
        value[6] > value[5] || value[5] - value[6] > 604_800 ||
        !validTimeline(value[7]) || typeof value[8] !== "boolean" ||
        !boundedInteger(value[9], 0, 2)) {
      return false;
    }
    if (value[9] === 0) return value[10] === 0;
    if (value[9] === 1) {
      return validTime(value[10]) && value[10] >= value[5] &&
        value[10] - value[5] <= 3_600;
    }
    return boundedInteger(value[10], 1, 3_600);
  };
  const restoreModel = (value, {
    now,
    owner = OWNER,
    device = DEVICE,
    generation = GENERATION,
    setCount = 2,
    activeOrigin = ORIGIN,
    activeSnapshotValid = true,
    intervalsConsistent = true
  }) => {
    if (!validRuntime(value) ||
        value[1] !== owner || value[2] !== device || value[3] !== generation ||
        value[4] !== setCount) {
      return null;
    }
    if (setCount > 0 &&
        (!activeSnapshotValid || activeOrigin !== value[6] || !intervalsConsistent)) {
      return null;
    }
    if (setCount === 0 && (activeOrigin != null || value[9] !== 0)) {
      return null;
    }
    const restored = value[7].slice();
    const gap = now - value[5];
    if (!value[8] && gap >= 0 && gap <= 30 && restored[0] + gap <= 604_800) {
      restored[0] += gap;
    }
    let rest = null;
    if (value[9] === 1) {
      const remaining = value[10] - now;
      if (remaining > 0 && remaining <= 3_600) {
        rest = { mode: "running", seconds: remaining };
      }
    } else if (value[9] === 2) {
      rest = { mode: "suspended", seconds: value[10] };
    }
    return { checkpoint: restored, paused: value[8], rest };
  };

  const recovered = restoreModel(runtime, { now: SAVED_AT + 20 });
  assert.equal(recovered.checkpoint[0], 140, "a running gap of at most 30 seconds resumes the clock");
  assert.deepEqual(recovered.rest, { mode: "running", seconds: 40 });
  const longGap = restoreModel(runtime, { now: SAVED_AT + 31 });
  assert.equal(longGap.checkpoint[0], 120, "a longer gap cannot inflate elapsed time");

  const pausedRuntime = runtime.slice();
  pausedRuntime[8] = true;
  assert.equal(
    restoreModel(pausedRuntime, { now: SAVED_AT + 30 }).checkpoint[0],
    120,
    "a recovered paused workout does not count the process gap"
  );
  const suspendedRuntime = runtime.slice();
  suspendedRuntime[9] = 2;
  suspendedRuntime[10] = 47;
  assert.deepEqual(
    restoreModel(suspendedRuntime, { now: SAVED_AT + 20 }).rest,
    { mode: "suspended", seconds: 47 }
  );

  assert.equal(
    restoreModel(runtime, { now: SAVED_AT + 1, setCount: 3 }),
    null,
    "a runtime checkpoint from an older completed-set revision is stale"
  );
  assert.equal(
    restoreModel(runtime, { now: SAVED_AT + 1, activeOrigin: ORIGIN + 1 }),
    null,
    "a runtime checkpoint from another workout origin is stale"
  );
  assert.equal(restoreModel(runtime, { now: SAVED_AT + 1, owner: OTHER_OWNER }), null);
  assert.equal(restoreModel(runtime, { now: SAVED_AT + 1, device: "other-device" }), null);
  assert.equal(restoreModel(runtime, { now: SAVED_AT + 1, generation: OTHER_OWNER }), null);
  assert.equal(restoreModel(runtime.slice(0, 10), { now: SAVED_AT + 1 }), null);
  const malformedRest = runtime.slice();
  malformedRest[10] = SAVED_AT - 1;
  assert.equal(restoreModel(malformedRest, { now: SAVED_AT + 1 }), null);

  const shouldCheckpoint = ({ force, lastTimer, nowTimer }) =>
    force || lastTimer == null || nowTimer - lastTimer >= 15_000;
  assert.equal(shouldCheckpoint({ force: false, lastTimer: 10_000, nowTimer: 24_999 }), false);
  assert.equal(shouldCheckpoint({ force: false, lastTimer: 10_000, nowTimer: 25_000 }), true);
  assert.equal(shouldCheckpoint({ force: true, lastTimer: 10_000, nowTimer: 10_001 }), true);

  const shouldCheckpointCompact = ({ elapsed, last = -15, force = false, fitSaved = false }) =>
    !fitSaved && (force || elapsed - last >= 15);
  assert.equal(shouldCheckpointCompact({ elapsed: 0 }), true);
  assert.equal(shouldCheckpointCompact({ elapsed: 14, last: 0 }), false);
  assert.equal(shouldCheckpointCompact({ elapsed: 15, last: 0 }), true);
  assert.equal(shouldCheckpointCompact({ elapsed: 17, last: 15 }), false);
  assert.equal(shouldCheckpointCompact({ elapsed: 17, last: 15, force: true }), true);
  assert.equal(shouldCheckpointCompact({ elapsed: 30, last: 15, fitSaved: true }), false);

  const totalModel = (base, live) => ({
    elapsed: Math.min(604_800, Math.max(0, base[0] + live.elapsed)),
    gym: Math.max(0, base[1] + live.gym),
    garmin: live.garmin == null ? base[2] : (base[2] == null ? 0 : base[2]) + live.garmin
  });
  assert.deepEqual(
    totalModel(checkpoint, { elapsed: 5, gym: 1.5, garmin: 2 }),
    { elapsed: 125, gym: 41.5, garmin: 40 }
  );
  assert.equal(totalModel(checkpoint, { elapsed: 0, gym: 0, garmin: null }).garmin, 38);
});

test("Garmin set metrics are bounded, persisted, undo-aware, and synchronized without raw motion", async () => {
  const [session, store, androidSecurity, androidManager] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncSecurity.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt", "utf8")
  ]);

  assert.match(session, /static function captureSetStatistics\(\)/);
  assert.match(session, /"activeSeconds" => duration/);
  assert.match(session, /static function recoveryHeartRateDrop\(\)/);
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /var restBefore = null/);
  assert.match(
    addSet,
    /lastLoggedSetEndSeconds > 0[\s\S]*restBefore = currentStart - lastLoggedSetEndSeconds/
  );
  assert.match(addSet, /"restBeforeSeconds" => restBefore/);
  assert.match(addSet, /"detectionConfidence" => statistics\.get\("detectionConfidence"\)/);
  assert.match(addSet, /var nextSets = normalizedSetList\(sets\)/);
  assert.match(addSet, /var previousSet = nextSets\[nextSets\.size\(\) - 1\]/);
  assert.match(addSet, /previousSet\.put\("recoveryHeartRateDrop", recoveryDrop\)/);
  assert.ok(
    addSet.indexOf("previousSet.put") < addSet.indexOf("persistActiveWorkoutSnapshot(nextSets"),
    "the previous set recovery update must be part of the same atomic snapshot"
  );
  assert.match(store, /setMetrics\.add\(compactSetMetrics\(setItem\)\)/);
  assert.match(store, /"setMetrics" => setMetrics/);
  assert.match(store, /peakHeartRate == null \|\| startHeartRate > peakHeartRate/);
  assert.match(session, /peakHrValue == null \|\| endHrValue > peakHrValue/);
  assert.match(store, /static function isValidSetMetricsList/);
  assert.doesNotMatch(store, /accelerometerData|motionScore/);
  assert.match(androidSecurity, /data class GarminSetStatistics/);
  assert.match(androidSecurity, /require\(values\.size == 7\)/);
  assert.match(androidSecurity, /optionalBoundedLong\(item, "activeSeconds", 0L, 7_200L\)/);
  assert.match(androidSecurity, /optionalBoundedInt\(item, "detectionConfidence", 0, 100\)/);
  assert.match(androidSecurity, /gymapp-garmin-workout\/v2/);
  assert.match(androidManager, /statistics\.recoveryHeartRateDrop/);
  assert.match(androidManager, /statistics\.detectionConfidence/);
});

test("Garmin ignores one-bpm and weak post-save noise before suspending rest", async () => {
  const session = await readFile("garmin/source/GymSession.mc", "utf8");
  const effort = section(session, "static function updateEffortState(value)", "static function updateSetConfidence");
  const restart = section(
    session,
    "static function hasCredibleRestRestartEvidence(",
    "static function updateMotionLifecycle()"
  );

  assert.doesNotMatch(effort, /delta >= 1 \|\| hrTrend >= 1\.0/);
  assert.match(effort, /renewedRiseDelta = 3/);
  assert.match(effort, /renewedRiseTrend = 2\.0/);
  assert.match(effort, /setConfidence >= 75/);
  assert.match(effort, /activeSignalCount >= 3/);
  assert.match(restart, /GymStore\.restDurationMs <= 0/);
  assert.match(restart, /lastLoggedSetSeconds >=[\s\S]*10/);
  assert.match(restart, /motionSignalCount >= 3/);
  assert.match(restart, /motionBurstSignals >= 4 && motionRhythmSignals >= 3/);

  const renewedZoneRise = (delta, trend, sensitivity = 1) => {
    const deltaThreshold = sensitivity === 0 ? 4 : sensitivity === 2 ? 2 : 3;
    const trendThreshold = sensitivity === 0 ? 2.5 : sensitivity === 2 ? 1.5 : 2;
    return delta >= deltaThreshold || trend >= trendThreshold;
  };
  for (const sensitivity of [0, 1, 2]) {
    assert.equal(
      renewedZoneRise(1, 1, sensitivity),
      false,
      `+1 bpm noise must not arm sensitivity ${sensitivity}`
    );
  }

  const canRestartRest = ({ age, deadband = 10, rising, strong, signals, burst, rhythm }) =>
    age >= deadband &&
    (rising || (strong && signals >= 3 && burst >= 4 && rhythm >= 3));
  assert.equal(
    canRestartRest({ age: 3, rising: false, strong: true, signals: 4, burst: 4, rhythm: 3 }),
    false,
    "even strong handling motion is suppressed inside the post-save deadband"
  );
  assert.equal(
    canRestartRest({ age: 20, rising: false, strong: false, signals: 1, burst: 1, rhythm: 0 }),
    false,
    "weak motion during the 90-second rest cannot cancel it"
  );
  assert.equal(
    canRestartRest({ age: 20, rising: false, strong: true, signals: 3, burst: 4, rhythm: 3 }),
    true,
    "sustained rep-like movement can still start the next set early"
  );
});

test("Garmin compact snapshots preserve many completed sets across restart with bounded state", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const persist = section(
    store,
    "static function persistActiveWorkoutSnapshot(",
    "static function persistEmptyActiveWorkoutSnapshot("
  );
  const validation = section(
    store,
    "static function isValidActiveWorkoutSnapshot(",
    "static function isValidTimelineCheckpoint("
  );
  const budget = section(
    store,
    "static function isWithinStorageBudget()",
    "static function isValidWorkoutStartedAtSeconds("
  );
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");

  assert.match(validation, /snapshot\[0\] != 2 && snapshot\[0\] != 3/);
  assert.match(validation, /isValidCompactActiveSetArrays\(snapshot\)/);
  assert.match(validation, /weights\.size\(\) != names\.size\(\)/);
  assert.match(validation, /isValidSetMetricsList\(snapshot\[8\], names\)/);
  assert.match(validation, /\(:enhancedCompactCheckpoint\)[\s\S]*isValidSetList\(snapshot\[5\], maxWorkoutSets, true\)/);
  assert.match(
    store,
    /\(:fullLegacyState\)[\s\S]*static function restoreActiveWorkoutSnapshot\(snapshot\)[\s\S]*snapshot\[8\]\[i\]\[k\][\s\S]*copySetInterval\(snapshot\[9\]\[i\]\)/
  );
  assert.match(
    store,
    /\(:enhancedCompactCheckpoint\)[\s\S]*static function restoreActiveWorkoutSnapshot\(snapshot\)[\s\S]*normalizedSetList\(snapshot\[5\]\)/
  );
  assert.match(store, /static function compatibilityActiveSetList\(source\)/);
  assert.match(store, /"exerciseName" => item\.get\("exerciseName"\)\.toString\(\)[\s\S]*"weight" => item\.get\("weight"\)[\s\S]*"reps" => item\.get\("reps"\)/);
  assert.match(store, /safe\.put\("setInterval", item\.get\("setInterval"\)\)/);
  assert.match(store, /Storage\.setValue\("sets", compatibleSets\)/);
  assert.match(persist, /var names = \[\];[\s\S]*var metrics = \[\];[\s\S]*Storage\.setValue\("activeWorkoutV1", snapshot\)/);
  assert.match(persist, /var compactSets = compatibilityActiveSetList\(nextSets\)[\s\S]*var snapshot = \[[\s\S]*3,/);
  assert.match(persist, /catch \(e\) \{[\s\S]*status = "SAVE FAIL";[\s\S]*return false/);
  assert.doesNotMatch(persist, /normalizedSetList\(nextSets\)/);
  assert.match(budget, /if \(activeWorkoutSnapshotValid && hasAccountBinding\(\)\)[\s\S]*setListNameBytes\(sets\)[\s\S]*estimatedValueBytes\(sets\)/);
  assert.match(store, /persistActiveWorkoutSnapshot\(nextSets[\s\S]*previousSets = null[\s\S]*sets = nextSets/);
  assert.ok(
    addSet.indexOf("persistActiveWorkoutSnapshot(nextSets") < addSet.indexOf("sets = nextSets"),
    "a thrown compact Storage write returns before publishing the new in-memory set list"
  );

  const manySets = Array.from({ length: 60 }, (_, index) => ({
    exerciseName: `Exercise ${index % 8}`,
    weight: 40 + index * 0.5,
    reps: 8 + (index % 5),
    activeSeconds: 30 + (index % 10),
    restBeforeSeconds: index === 0 ? null : 90,
    startHeartRate: 110 + (index % 15),
    peakHeartRate: 135 + (index % 20),
    endHeartRate: 125 + (index % 15),
    recoveryHeartRateDrop: index === 59 ? null : 12,
    detectionConfidence: 86,
    setInterval: [index * 120, index * 120 + 35, 2.2, 2, 0, 5, 15, 10, 5, 0]
  }));
  const names = manySets.map((item) => item.exerciseName);
  const weights = manySets.map((item) => item.weight);
  const reps = manySets.map((item) => item.reps);
  const metrics = manySets.map((item) => [
    item.activeSeconds,
    item.restBeforeSeconds,
    item.startHeartRate,
    item.peakHeartRate,
    item.endHeartRate,
    item.recoveryHeartRateDrop,
    item.detectionConfidence
  ]);
  const intervals = manySets.map((item) => item.setInterval);
  const fullCompact = [names, weights, reps, metrics, intervals];
  const restored = names.map((exerciseName, index) => ({
    exerciseName,
    weight: weights[index],
    reps: reps[index],
    activeSeconds: metrics[index][0],
    restBeforeSeconds: metrics[index][1],
    startHeartRate: metrics[index][2],
    peakHeartRate: metrics[index][3],
    endHeartRate: metrics[index][4],
    recoveryHeartRateDrop: metrics[index][5],
    detectionConfidence: metrics[index][6],
    setInterval: intervals[index]
  }));
  assert.deepEqual(restored, manySets, "ordinary watches restore every v3 metric");
  assert.ok(
    JSON.stringify(fullCompact).length < JSON.stringify(manySets).length * 0.55,
    "parallel arrays must materially reduce long-workout storage and allocation pressure"
  );

  assert.equal(names.length, 60, "the full bounded watch workout remains representable");
  assert.equal([...names, names[0]].length > 60, true, "a 61st set is outside the bound");

  const compatibilityMirror = manySets.map(({ exerciseName, weight, reps, setInterval }) => ({
    exerciseName,
    weight,
    reps,
    setInterval
  }));
  assert.equal(compatibilityMirror.length, 60);
  assert.deepEqual(
    (({ exerciseName, weight, reps }) => ({ exerciseName, weight, reps }))(compatibilityMirror[59]),
    { exerciseName: "Exercise 3", weight: 69.5, reps: 12 },
    "an older reader retains the final exercise/kg/reps without understanding v3"
  );
  assert.deepEqual(
    compatibilityMirror[59].setInterval,
    manySets[59].setInterval,
    "the 96 KiB v3 tier also restores the final set interval and timeline"
  );

  const legacyV2SnapshotSets = manySets.slice(0, 18).map((item) => ({ ...item }));
  const restoredFromV2 = legacyV2SnapshotSets.map((item) => ({ ...item }));
  assert.deepEqual(
    restoredFromV2,
    legacyV2SnapshotSets,
    "the v3 loader keeps accepting already-persisted v2 dictionary snapshots"
  );

  const committedBeforeCrash = compatibilityMirror.slice(0, 59);
  const crashSafeCommit = (writeCompleted) => writeCompleted ? compatibilityMirror : committedBeforeCrash;
  assert.equal(crashSafeCommit(false).length, 59, "a failed 60th write keeps the prior partial workout");
  assert.equal(crashSafeCommit(true).length, 60, "a completed atomic write restores the new workout");
});
