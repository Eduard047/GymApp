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
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
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
  assert.match(session, /var zoneEntrySignal = zoneEnough && \(delta >= 1 \|\| hrTrend >= 1\.0\)/);
  assert.match(session, /static function hasValidHeartRateZones\(\)/);
  assert.match(view, /"ACT", GymSession\.activityHr/);
  assert.match(view, /"SNS", GymSession\.sensorHr/);
  assert.match(view, /"MOV", GymSession\.motionAvailable/);
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
    /rest > 0 && GymSession\.effortState\.equals\("SET ACTIVE"\)[\s\S]*GymStore\.cancelRest\(\)/
  );
  assert.ok(
    tick.indexOf("restWasActive = false") < tick.indexOf('GymStore.status = "REST DONE"'),
    "canceling rest for a new set must not vibrate as if the timer completed"
  );
  const dashboard = section(view, "function drawDashboard(", "function showPauseFlash()");
  assert.match(dashboard, /var setActive = GymSession\.effortState\.equals\("SET ACTIVE"\)/);
  assert.ok(
    dashboard.indexOf("setActive ?") < dashboard.indexOf("rest > 0 ?"),
    "active-set status must take visual priority over the countdown"
  );
  assert.match(store, /static function cancelRest\(\) \{\s*restEndsAt = 0;/);
  assert.match(store, /static function cancelRest\(\)[\s\S]*clearTransientSetActions\(\)/);
  assert.match(tick, /GymStore\.cancelRest\(\)[\s\S]*dismissSetSavedFlash\(\)/);
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
  assert.match(clear, /lastMotionTimerMs = 0/);
  assert.match(clear, /lastCredibleMotionSeconds = 0/);
  assert.match(clear, /clearSetCandidate\(\)/);
  assert.match(clear, /effortState = "REST"/);
  assert.doesNotMatch(clear, /clearTransientSetActions|lastSetUndoUntil/);

  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.ok(
    addSet.indexOf("lastSetUndoUntil =") < addSet.indexOf("GymSession.clearAutoPrompt()") &&
      addSet.indexOf("GymSession.clearAutoPrompt()") < addSet.indexOf("restEndsAt ="),
    "commit must retain undo, clear old motion, and only then start rest"
  );

  const freshness = section(
    session,
    "static function isMotionFresh()",
    "static function readHeartRateFromSensor("
  );
  assert.match(freshness, /lastMotionTimerMs <= 0[\s\S]*return false/);

  const tick = section(view, "function tick()", "function requestSyncNow()");
  assert.match(tick, /rest > 0 && GymSession\.effortState\.equals\("SET ACTIVE"\)/);
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
  assert.match(dashboard, /GymSession\.gymCalories\.format\("%\.0f"\)/);
  assert.match(dashboard, /dashboardSetProgressText\(\)/);
  assert.match(dashboard, /GymStore\.currentExerciseLabel\(\)/);
  assert.match(dashboard, /setSummaryText\(\)/);
  assert.match(dashboard, /countdownText\(rest\)/);
  assert.match(view, /function drawHeartIcon\(/);
  assert.match(view, /function drawDashboardStatusPill\(/);
  assert.match(view, /function isCompactDashboard\(w, h\)/);
  assert.match(view, /function drawCompactDashboard\(/);
  assert.match(view, /function isTinyDashboard\(w, h\)/);
  assert.match(view, /isTinyDashboard\(w, h\) \? h - 10 : h - 14/);
  assert.doesNotMatch(dashboard, /"142"|"00:17:34"|"Bench Press"|"128"/);
});

test("Garmin can undo only the most recent set inside a bounded window", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  assert.match(store, /undoWindowMs = 5000/);
  assert.match(store, /static function canUndoLastSet\(\)/);
  const undo = section(store, "static function undoLastSet()", "static function cancelRest()");
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
  assert.match(undo, /restEndsAt = 0/);
  assert.match(session, /static function restoreSetAfterUndo\(statistics, restorePrompt\)/);
  assert.match(undo, /GymSession\.restoreSetAfterUndo\(restoreStatistics, restorePrompt\)/);
  assert.match(view, /function isUndoOverlayActive\(\)/);
  assert.match(view, /GymStore\.tr\("TAP \/ BACK: UNDO"/);
  assert.match(view, /savedSetFlashUntil = System\.getTimer\(\) \+ GymStore\.undoWindowMs/);
  assert.match(view, /function onBack\(\)[\s\S]*if \(view\.isUndoOverlayActive\(\)\)[\s\S]*undoLastSet\(\)/);
  assert.match(view, /if \(x < \(view\.screenWidth \/ 2\)\)[\s\S]*undoLastSet\(\)[\s\S]*recordSet\(\)/);
});

test("Garmin manual and automatic undo restore the same captured set statistics", async () => {
  const [session, store] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  const undo = section(store, "static function undoLastSet()", "static function cancelRest()");
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
  const undo = section(store, "static function undoLastSet()", "static function cancelRest()");
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
  assert.match(session, /if \(setConfidence >= 70\)[\s\S]*activeSignalCount \+= 1/);
  assert.match(view, /SET MAYBE/);
  assert.match(view, /confidenceLabel\(\)/);
});

test("Garmin backdates a confirmed set to bounded first evidence and drops false candidates", async () => {
  const session = await readFile("garmin/source/GymSession.mc", "utf8");
  const effort = section(session, "static function updateEffortState(value)", "static function updateSetConfidence");
  assert.match(effort, /setConfidence >= 40[\s\S]*beginSetCandidate\(value\)/);
  assert.match(effort, /setConfidence >= 70[\s\S]*activeSignalCount \+= 1/);
  assert.match(effort, /candidateStartSeconds <= elapsedSeconds[\s\S]*elapsedSeconds - candidateStartSeconds <= 8/);
  assert.match(effort, /activeStartSeconds = hasCandidate \? candidateStartSeconds : elapsedSeconds/);
  assert.match(effort, /else \{\s*clearSetCandidate\(\);\s*\}/);

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

  const message = section(store, "static function workoutMessage()", "static function applyPhoneSync(");
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
  const message = section(store, "static function workoutMessage()", "static function applyPhoneSync(");
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
  const undo = section(store, "static function undoLastSet()", "static function cancelRest()");
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
  assert.ok(
    load.indexOf('Storage.getValue("activeWorkoutV1")') <
      load.indexOf("restoreActiveWorkoutSnapshot(savedActiveWorkout)"),
    "the authoritative empty tombstone must be considered on every load"
  );
});

test("Garmin low-memory products keep an atomic compact ownerless recovery boundary", async () => {
  const [store, jungle] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/monkey.jungle", "utf8")
  ]);

  assert.match(jungle, /^base\.excludeAnnotations = compactLegacyState$/m);
  const compactProducts = [
    "descentg1",
    "instinct2",
    "instinct2s",
    "instinct2x",
    "instinctcrossover"
  ];
  for (const product of compactProducts) {
    assert.match(
      jungle,
      new RegExp(`^${product}\\.excludeAnnotations = fullLegacyState$`, "m")
    );
  }
  assert.equal(
    (jungle.match(/\.excludeAnnotations = fullLegacyState/g) || []).length,
    compactProducts.length
  );

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
  assert.match(onShow, /!GymSession\.recording[\s\S]*GymStore\.sets\.size\(\) > 0[\s\S]*GymStore\.markWorkoutResumed\(\)[\s\S]*GymSession\.start\(\)/);
  const markResumed = section(store, "static function markWorkoutResumed()", "static function clearActiveWorkout()");
  assert.match(markResumed, /sets\.size\(\) > 0 && !activeWorkoutTimelineValid/);

  const snapshotValidation = section(
    store,
    "static function isValidActiveWorkoutSnapshot(",
    "static function restoreActiveWorkoutSnapshot("
  );
  assert.match(snapshotValidation, /snapshot\.size\(\) != 7/);
  assert.match(snapshotValidation, /snapshot\[0\] != 2/);
  assert.match(snapshotValidation, /isValidAccountBinding\(snapshot\[1\]\)/);
  assert.match(snapshotValidation, /isBoundedText\(snapshot\[2\], maxBindingLength\)/);
  assert.match(snapshotValidation, /isValidOptionalAccountBinding\(snapshot\[3\]\)/);
  assert.match(snapshotValidation, /isValidSetList\(snapshot\[5\], maxWorkoutSets, true\)/);
  assert.match(snapshotValidation, /startedAtSeconds == null && checkpoint != null/);
  assert.match(snapshotValidation, /startedAtSeconds != null &&[\s\S]*!isValidWorkoutStartedAtSeconds\(startedAtSeconds\)/);
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
  assert.match(persist, /var snapshot = \[[\s\S]*2,/);
  assert.match(persist, /Storage\.setValue\("activeWorkoutV1", snapshot\)/);
  assert.doesNotMatch(persist, /Storage\.setValue\("sets"/);
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /legacyOriginUnavailable = previousSets\.size\(\) > 0[\s\S]*previousWorkoutStartedAt == null[\s\S]*resumedWorkoutIntervalsInvalid/);
  assert.ok(
    addSet.indexOf("persistActiveWorkoutSnapshot(nextSets") < addSet.indexOf("sets = nextSets"),
    "add must publish the new set only after its atomic snapshot commits"
  );
  const undo = section(store, "static function undoLastSet()", "static function cancelRest()");
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
  const message = section(store, "static function workoutMessage()", "static function applyPhoneSync(");
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
  assert.match(save, /Storage\.setValue\("sets", \[\]\)/);
  assert.match(save, /Storage\.setValue\("activeWorkoutStartedAtSeconds", null\)/);
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
