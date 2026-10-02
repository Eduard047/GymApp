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

const Mode = Object.freeze({ IDLE: 0, FREE: 1, PLANNED: 2 });

const validPlan = (plan, catalog) =>
  Array.isArray(plan) && plan.length > 0 && plan.length <= 60 &&
  plan.every((item) => item && typeof item.exerciseName === "string" &&
    catalog.includes(item.exerciseName));

const startablePlan = (plan, catalog) => validPlan(plan, catalog) && plan.length <= 30;

const beginMode = ({ state, unfinished, plan, catalog, pendingCount = 0, queueReadable = true }, usePlan) => {
  if (typeof usePlan !== "boolean" || state !== Mode.IDLE || unfinished) return state;
  if (!queueReadable || pendingCount > 0) return state;
  if (usePlan && !startablePlan(plan, catalog)) return state;
  return usePlan ? Mode.PLANNED : Mode.FREE;
};

const restoreMode = ({ marker, prepared, owner, device, generation, unfinished, plan, catalog }) => {
  const bindingMatches = (value) => value?.[1] === owner && value?.[2] === device &&
    (value?.[3] ?? null) === (generation ?? null);
  const preparedMode = Array.isArray(prepared) && bindingMatches(prepared) &&
    ((prepared.length === 6 && prepared[0] === 1) ||
      (prepared.length === 7 && prepared[0] === 2 &&
        typeof prepared[6] === "boolean"))
    ? (prepared.length === 7 && prepared[6] ? "free" : "planned") : null;
  const markerValid = Array.isArray(marker) && marker.length === 5 && marker[0] === 1 &&
    bindingMatches(marker) && typeof marker[4] === "boolean" && unfinished &&
    (!marker[4] || validPlan(plan, catalog)) &&
    (preparedMode == null || preparedMode === (marker[4] ? "planned" : "free"));
  if (markerValid) return marker[4] ? Mode.PLANNED : Mode.FREE;
  if (preparedMode === "free") return Mode.FREE;
  if (preparedMode === "planned" && validPlan(plan, catalog)) return Mode.PLANNED;
  return Mode.IDLE;
};

const validWireWorkout = (message) => {
  if (!message || message.type !== "create_workout" || message.bindingVersion !== 2 ||
      !Number.isFinite(message.startedAtSeconds) || !Array.isArray(message.sets)) return false;
  if (message.workoutMode != null && !["free", "planned"].includes(message.workoutMode)) {
    return false;
  }
  if (message.workoutMode === "free") {
    return message.sets.length === 0 && Number.isFinite(message.durationSeconds) &&
      message.durationSeconds >= 1 && message.durationSeconds <= 604_800 &&
      Number.isFinite(message.gymCalories) && message.gymCalories >= 0 &&
      message.gymCalories <= 10_000_000 && message.setMetrics == null &&
      message.setIntervals == null && message.plannedSetCount == null &&
      message.plannedTargetSetCount == null && message.completedPlannedSetCount == null;
  }
  return message.sets.length > 0;
};

test("Garmin workout modes follow a one-way IDLE to FREE or PLANNED state machine", () => {
  const catalog = ["Squat", "Row"];
  const plan = [{ exerciseName: "Squat" }];
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false, plan, catalog }, false), Mode.FREE);
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false, plan, catalog }, true), Mode.PLANNED);
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false, plan: [], catalog }, true), Mode.IDLE);
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false,
    plan: [{ exerciseName: "Unknown" }], catalog }, true), Mode.IDLE);
  const thirtySetPlan = Array.from({ length: 30 }, () => ({ exerciseName: "Squat" }));
  const thirtyOneSetPlan = Array.from({ length: 31 }, () => ({ exerciseName: "Squat" }));
  assert.equal(startablePlan(thirtySetPlan, catalog), true);
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false,
    plan: thirtySetPlan, catalog }, true), Mode.PLANNED);
  assert.equal(validPlan(thirtyOneSetPlan, catalog), true,
    "the historical storage/resume validator still accepts up to 60 targets");
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false,
    plan: thirtyOneSetPlan, catalog }, true), Mode.IDLE,
  "a new planned workout stops at today's 30-target cap");
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false, pendingCount: 1,
    plan: thirtySetPlan, catalog }, true), Mode.IDLE,
  "a durable pending workout reserves the queue slot until it drains");
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: false, queueReadable: false,
    plan, catalog }, false), Mode.IDLE,
  "an unreadable pending journal fails closed for new workouts");
  assert.equal(beginMode({ state: Mode.FREE, unfinished: false, plan, catalog }, true), Mode.FREE,
    "an activity cannot switch from FREE to PLANNED");
  assert.equal(beginMode({ state: Mode.PLANNED, unfinished: false, plan, catalog }, false), Mode.PLANNED,
    "an activity cannot switch from PLANNED to FREE");
  assert.equal(beginMode({ state: Mode.IDLE, unfinished: true, plan, catalog }, false), Mode.IDLE,
    "unfinished data must be resumed or discarded, never relabelled");
});

test("mode recovery requires exact ownership and preserves the prepared mode", () => {
  const base = {
    owner: "acct", device: "watch", generation: "g1", unfinished: true,
    plan: [{ exerciseName: "Squat" }], catalog: ["Squat"]
  };
  const freeMarker = [1, "acct", "watch", "g1", false];
  const plannedMarker = [1, "acct", "watch", "g1", true];
  const freePrepared = [2, "acct", "watch", "g1", "req", 0, true];
  assert.equal(restoreMode({ ...base, marker: freeMarker, prepared: freePrepared }), Mode.FREE);
  assert.equal(restoreMode({ ...base, marker: plannedMarker, prepared: null }), Mode.PLANNED);
  const legacySixtyPlan = Array.from({ length: 60 }, () => ({ exerciseName: "Squat" }));
  assert.equal(restoreMode({ ...base, marker: plannedMarker, prepared: null,
    plan: legacySixtyPlan }), Mode.PLANNED,
  "an existing owner-bound plan remains resumable at the legacy storage cap");
  assert.equal(restoreMode({ ...base, marker: null, prepared: freePrepared }), Mode.FREE,
    "phase recovery is an independent mode journal");
  assert.equal(restoreMode({ ...base, marker: plannedMarker, prepared: freePrepared }), Mode.FREE,
    "the later owner-bound phase marker preserves the transaction mode");
  assert.equal(restoreMode({ ...base, marker: freeMarker, prepared: null, owner: "other" }), Mode.IDLE);
  assert.equal(restoreMode({ ...base, marker: freeMarker, prepared: null, device: "other" }), Mode.IDLE);
  assert.equal(restoreMode({ ...base, marker: freeMarker, prepared: null, generation: "g2" }), Mode.IDLE);
  assert.equal(restoreMode({ ...base, marker: freeMarker, prepared: null, unfinished: false }), Mode.IDLE);
});

test("FREE wire payload accepts duration-only metrics and rejects fake or detailed payloads", () => {
  const base = {
    type: "create_workout",
    bindingVersion: 2,
    requestId: "req",
    accountBinding: "acct",
    deviceBinding: "watch",
    startedAtSeconds: 1_700_000_000
  };
  assert.equal(validWireWorkout({ ...base, workoutMode: "free", sets: [],
    durationSeconds: 1, gymCalories: 0 }), true,
  "FREE is valid without HR or Garmin calories when elapsed time is positive");
  assert.equal(validWireWorkout({ ...base, workoutMode: "free", sets: [],
    durationSeconds: 60, gymCalories: 4.2, avgHeartRate: 0 }), true);
  assert.equal(validWireWorkout({ ...base, workoutMode: "free", sets: [],
    durationSeconds: 0, gymCalories: 0 }), false);
  assert.equal(validWireWorkout({ ...base, workoutMode: "free", sets: [],
    gymCalories: 0 }), false);
  assert.equal(validWireWorkout({ ...base, workoutMode: "free", sets: [{}],
    durationSeconds: 60, gymCalories: 1 }), false);
  assert.equal(validWireWorkout({ ...base, workoutMode: "free", sets: [],
    durationSeconds: 60, gymCalories: 1, setMetrics: [] }), false);
  assert.equal(validWireWorkout({ ...base, workoutMode: "planned", sets: [] }), false);
  assert.equal(validWireWorkout({ ...base, workoutMode: "planned", sets: [{}] }), true);
  assert.equal(validWireWorkout({ ...base, sets: [{}] }), true,
    "queued legacy detailed messages remain valid without workoutMode");
  assert.equal(validWireWorkout({ ...base, workoutMode: "other", sets: [{}] }), false);
});

test("Monkey C implementation gates sensors, detector, detailed mutations, and FREE UI", async () => {
  const [mode, session, store, view] = await Promise.all([
    readFile("garmin/source/GymWorkoutMode.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);
  assert.match(mode, /MODE_IDLE = 0[\s\S]*MODE_FREE = 1[\s\S]*MODE_PLANNED = 2/);
  assert.match(mode, /!isIdle\(\) \|\|\s*GymStore\.hasUnfinishedWorkout\(\)/);
  const validPlan = section(mode, "static function hasValidPlan()", "static function hasStartablePlan()");
  const startablePlan = section(mode, "static function hasStartablePlan()", "static function canResume()");
  const resumePlan = section(mode, "static function canResume()", "(:richWorkoutMode)\n    static function begin(usePlan)");
  const richSetGate = section(mode,
    "(:richWorkoutMode, :inline)\n    static function allowsDetailedTracking()",
    "(:compactWorkoutMode96, :inline)\n    static function allowsDetailedTracking()");
  const manualSetGate = section(mode,
    "(:compactWorkoutMode96, :inline)\n    static function allowsDetailedTracking()",
    "static function hasValidPlan()");
  assert.match(validPlan, /GymStore\.isValidLiveSetList\(currentPlan, GymStore\.maxPlanSets, true\)/);
  assert.match(startablePlan, /GymStore\.plan\.size\(\) <= GymStore\.maxNewWorkoutSets && hasValidPlan\(\)/);
  assert.match(resumePlan, /state == MODE_PLANNED && hasValidPlan\(\)/);
  assert.match(richSetGate, /return state == MODE_PLANNED;/,
    "128 KiB rich profiles retain the detector-backed set gate");
  assert.match(manualSetGate, /return false;/,
    "96 KiB lite profiles have no plan, so athlete-entered sets are never allowed");
  const begin = section(mode, "(:richWorkoutMode)\n    static function begin(usePlan)", "(:compactWorkoutMode96)\n    static function begin(usePlan)");
  const compactBegin = section(mode, "(:compactWorkoutMode96)\n    static function begin(usePlan)", "(:richWorkoutMode)\n    static function restore()");
  for (const implementation of [begin, compactBegin]) {
    assert.match(implementation, /!GymPendingJournal\.readable \|\| GymStore\.pendingCount\(\) > 0/,
      "new workouts must reserve a durable pending queue slot");
  }
  assert.match(begin, /usePlan && !hasStartablePlan\(\)/);
  assert.match(compactBegin, /usePlan \|\| state != MODE_IDLE/,
    "96 KiB lite mode rejects plan starts; every workout begins FREE");
  assert.match(compactBegin, /state = MODE_FREE;/);
  assert.match(mode, /state = usePlan \? MODE_PLANNED : MODE_FREE/);
  assert.match(mode, /activeWorkoutModeV1/);
  assert.match(mode, /marker instanceof Lang\.Array && marker\.size\(\) > 0/,
    "96 KiB mode recovery accepts any released marker size and resumes it as FREE");
  assert.match(mode, /GymStore\.hasUnfinishedWorkout\(\)/,
    "the compact marker is usable only beside an accepted owner-bound workout");

  const richStartSensors = section(session,
    "(:richWorkoutMode)\n    static function startSensors()",
    "(:compactWorkoutMode96)\n    static function startSensors()");
  const manualStartSensors = section(session,
    "(:compactWorkoutMode96)\n    static function startSensors()",
    "static function stopSensors()");
  assert.match(richStartSensors, /if \(!GymWorkoutMode\.canResume\(\)\)/);
  assert.match(richStartSensors, /GymWorkoutMode\.allowsDetailedTracking\(\)[\s\S]*startMotionListener\(\)/);
  assert.match(richStartSensors, /else \{[\s\S]*stopMotionListener\(\)[\s\S]*motionAvailable = false/);
  assert.match(manualStartSensors, /Sensor\.setEnabledSensors\(\[Sensor\.SENSOR_HEARTRATE\]\)/);
  assert.doesNotMatch(manualStartSensors,
    /autoPromptEnabled|startMotionListener|\bregisterSensorDataListener|SENSOR_ACCEL|SENSOR_GYRO|accelerometer|gyroscope/i,
    "96 KiB startup remains HR-only even when the legacy setting is enabled");
  assert.equal((session.match(/function onSensorData\(data\) \{\s*if \(!GymWorkoutMode\.allowsDetailedTracking\(\)\)/g) || []).length, 2);
  const heartRate = section(session, "static function applyHeartRate(value)", "static function filteredHeartRate(value)");
  assert.match(session, /static const EFFORT_FREE = 6;/);
  assert.match(heartRate, /if \(detailedTracking\)[\s\S]*trackRecoveryHeartRate\(value\)[\s\S]*updateEffortState/);
  assert.match(heartRate, /else \{[\s\S]*autoLogPrompt = false[\s\S]*activeSetSeen = false[\s\S]*effortState = EFFORT_FREE/);
  const tick = section(session, "static function tick(", "static function startSensors()");
  assert.match(tick,
    /expireStaleHeartRate\(\)[\s\S]*if \(!detailedTracking\)[\s\S]*if \(!paused\)[\s\S]*effortState = EFFORT_FREE/,
    "FREE stale-HR expiry must preserve the paused lifecycle without arming detailed tracking");
  const effortLabel = section(view, "function effortLabel(state)", "function confidenceLabel()");
  assert.match(effortLabel, /return "FREE";/,
    "the internal EFFORT_FREE state still renders with the FREE label");

  for (const guardedMutation of ["nextExercise", "addSet", "canUndoLastSet", "undoLastSet", "restSeconds"]) {
    const start = `static function ${guardedMutation}(`;
    const bodyStart = store.indexOf(start);
    assert.notEqual(bodyStart, -1, `missing ${guardedMutation}`);
    const body = store.slice(bodyStart, bodyStart + 420);
    assert.match(body, /GymWorkoutMode\.allowsDetailedTracking\(\)/,
      `${guardedMutation} must use the profile-specific mode gate`);
  }

  const freeDashboard = section(view, "function drawFreeDashboard(dc, w, h)", "(:fullLegacyState)\n    function isCompactDashboard");
  const overview = section(view, "function drawDashboardOverview(dc, w, h, hrText)",
    "(:fullLegacyState)\n    function drawFreeDashboard(dc, w, h)");
  assert.match(freeDashboard, /drawDashboardOverview\(dc, w, h/);
  assert.match(overview, /GymSession\.elapsedText\(\)/);
  assert.match(overview, /drawHeartRateZones\(dc, w, h/);
  assert.match(overview, /GymStore\.totalGymCalories\(\)/);
  assert.doesNotMatch(freeDashboard + overview, /currentExercise|weight|reps|sets|rest|autoLog|motion/i);
  assert.doesNotMatch(view, /compactWorkoutMode96\)\s*function (drawManualDashboard|drawEntry)/,
    "96 KiB lite mode has no manual set dashboard or entry screen");
  const freeSession = section(view,
    "(:compactWorkoutMode96)\n    function drawFreeSessionDashboard",
    "(:fullLegacyState)\n    function drawCompactHeartIcon");
  assert.match(view,
    /\} else if \(page == 0\) \{\s*drawFreeSessionDashboard\(dc, w, h, false\);\s*\} else if \(page == 2\)/,
    "96 KiB lite mode always draws the FREE dashboard");
  assert.match(freeSession,
    /"HR " \+ heart[\s\S]*GymSession\.elapsedText\(\)[\s\S]*"KCAL " \+ GymStore\.totalGymCalories\(\)\.format\("%\.1f"\)/,
    "FREE displays aggregate heart rate, elapsed time, and calories");
  assert.match(freeSession,
    /if \(!saveAction\) \{\s*drawMinimalLine\(dc, w, h \* 0\.84,[\s\S]*"SELECT: PAUSE"/,
    "FREE offers pause from its workout dashboard");
  assert.doesNotMatch(freeSession, /GymStore\.sets|currentExercise|weight|reps|SET ENTRY/i,
    "FREE does not display manual set controls or details");
  const compactReadyStatus = section(view,
    "(:compactLegacyState)\n    function readyStatusText()",
    "function readyActionCount()");
  assert.match(compactReadyStatus,
    /current == GymStatus\.FIT_FAIL \|\| current == GymStatus\.FIT_CHECK \|\| current == GymStatus\.SAVE_FAIL \|\| current == GymStatus\.START_FAIL \|\| current == GymStatus\.REC_FAIL \|\| current == GymStatus\.FIT_RETRY/,
    "compact recovery must localize exactly the released data-retention statuses");
  assert.doesNotMatch(compactReadyStatus, /current\.find\("FAIL"\)/,
    "unrelated internal failures must not be mislabeled as retained workout data");
  assert.match(view, /\} else if \(view\.page == 0\) \{\s*openPauseMenu\(\);\s*\}/,
    "SELECT on the FREE dashboard opens the pause menu");
  assert.match(view, /function navigateContent\(delta\) \{\}/,
    "96 KiB lite mode has no page navigation");
  assert.match(view, /function hasPendingSetPrompt\(\) \{\s*if \(!GymWorkoutMode\.allowsDetailedTracking\(\)\)/);
});

test("prepared FREE commit and queue are mode-bound, positive-duration, and plan-preserving", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const preparedValidator = section(store,
    "static function isValidPreparedWorkout(value)", "static function hasPreparedWorkout()");
  const prepare = section(store,
    "static function prepareWorkoutCommit()", "static function markPreparedWorkoutFitSaved()");
  const message = section(store,
    "static function workoutMessage(requestId)", "static function applyPhoneSync(");
  const validator = section(store,
    "static function isValidWorkoutMetadata(message, actualSetCount)", "static function isValidOptionalAccountBinding(value)");
  const recover = section(store,
    "static function recoverQueuedWorkout()", "static function beginAccountTransition()");

  assert.match(preparedValidator, /markerSize != 6 && markerSize != 7/);
  assert.match(preparedValidator, /markerSize == 6[\s\S]*return true/);
  assert.match(preparedValidator, /value\[6\] instanceof Lang\.Boolean/);
  assert.match(prepare, /var freeMode = GymWorkoutMode\.isFree\(\)/);
  assert.match(prepare,
    /if \(freeMode\) \{\s*if \(sets\.size\(\) != 0 \|\| !GymSession\.recording\)/);
  assert.match(prepare, /checkpointLiveWorkout\(true\)/);
  assert.match(prepare, /freeCheckpoint\[0\] <= 0/);
  assert.match(prepare, /var marker = \[\s*2,[\s\S]*freeMode\s*\]/);

  assert.match(message, /"workoutMode" => freeMode \? "free" : "planned"/);
  assert.match(message, /message\["sets"\] = setCopies/);
  assert.match(message, /if \(keepsSetDiagnostics && !freeMode && setMetrics != null\) \{\s*message\["setMetrics"\] = setMetrics/);
  assert.match(message, /if \(!freeMode \|\| samples > 0\)/);
  assert.match(message, /runtimeWorkoutStartedAtSeconds/);
  assert.match(validator, /message\.size\(\) > 21/);
  assert.match(validator, /modeValue\.toString\(\)\.equals\("free"\)/);
  assert.match(validator, /actualSetCount == 0[\s\S]*isValidSetList\(setsValue, maxWorkoutSets, freeMode\)/);
  assert.match(validator, /isBoundedNumber\(durationValue, 1\.0, 604800\.0\)/);
  assert.match(validator, /message\.get\("setMetrics"\) == null/);
  assert.match(validator, /if \(modeValue != null && modeValue\.toString\(\)\.equals\("free"\)\)[\s\S]*return actualSetCount > 0/);
  assert.doesNotMatch(recover, /plan = \[\]/,
    "finishing one activity must not erase the downloaded plan");
});
