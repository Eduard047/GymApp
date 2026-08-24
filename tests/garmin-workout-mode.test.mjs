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

const beginMode = ({ state, unfinished, plan, catalog }, usePlan) => {
  if (typeof usePlan !== "boolean" || state !== Mode.IDLE || unfinished) return state;
  if (usePlan && !validPlan(plan, catalog)) return state;
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
  assert.match(mode, /usePlan && !hasValidPlan\(\)/);
  assert.match(mode, /state = usePlan \? MODE_PLANNED : MODE_FREE/);
  assert.match(mode, /activeWorkoutModeV1/);
  assert.match(mode, /markerSize == 2 \|\| markerSize == 5/,
    "96 KiB mode recovery must accept the released 3.1.x marker");
  assert.match(mode, /GymStore\.hasUnfinishedWorkout\(\)/,
    "the compact marker is usable only beside an accepted owner-bound workout");

  const startSensors = section(session, "static function startSensors()", "static function stopSensors()");
  assert.match(startSensors, /if \(!GymWorkoutMode\.canResume\(\)\)/);
  assert.match(startSensors, /GymWorkoutMode\.allowsDetailedTracking\(\)[\s\S]*startMotionListener\(\)/);
  assert.match(startSensors, /else \{[\s\S]*stopMotionListener\(\)[\s\S]*motionAvailable = false/);
  assert.equal((session.match(/function onSensorData\(data\) \{\s*if \(!GymWorkoutMode\.allowsDetailedTracking\(\)\)/g) || []).length, 2);
  const heartRate = section(session, "static function applyHeartRate(value)", "static function filteredHeartRate(value)");
  assert.match(heartRate, /if \(detailedTracking\)[\s\S]*trackRecoveryHeartRate\(value\)[\s\S]*updateEffortState/);
  assert.match(heartRate, /else \{[\s\S]*autoLogPrompt = false[\s\S]*activeSetSeen = false[\s\S]*effortState = "FREE"/);
  const tick = section(session, "static function tick()", "static function startSensors()");
  assert.match(tick,
    /expireStaleHeartRate\(\)[\s\S]*if \(!detailedTracking\)[\s\S]*if \(!paused\)[\s\S]*effortState = "FREE"/,
    "FREE stale-HR expiry must preserve the paused lifecycle without arming detailed tracking");

  for (const guardedMutation of ["nextExercise", "addSet", "canUndoLastSet", "undoLastSet", "restSeconds"]) {
    const start = `static function ${guardedMutation}(`;
    const bodyStart = store.indexOf(start);
    assert.notEqual(bodyStart, -1, `missing ${guardedMutation}`);
    const body = store.slice(bodyStart, bodyStart + 420);
    assert.match(body, /GymWorkoutMode\.allowsDetailedTracking\(\)/, `${guardedMutation} must reject FREE`);
  }

  const freeDashboard = section(view, "function drawFreeDashboard(dc, w, h)", "(:fullLegacyState)\n    function isCompactDashboard");
  assert.match(freeDashboard, /GymSession\.elapsedText\(\)/);
  assert.match(freeDashboard, /GymSession\.zone/);
  assert.match(freeDashboard, /GymStore\.totalGymCalories\(\)/);
  assert.doesNotMatch(freeDashboard, /currentExercise|weight|reps|sets|rest|autoLog|motion/i);
  const compactDashboard = section(view,
    "(:compactLegacyState)\n    function drawTinyDashboard",
    "(:fullLegacyState)\n    function drawCompactHeartIcon");
  assert.match(compactDashboard,
    /if \(GymWorkoutMode\.isFree\(\)\)[\s\S]*totalGymCalories\(\)[\s\S]*\} else \{[\s\S]*currentExerciseLabel\(\)/,
    "96 KiB FREE must branch away from exercise and set rows");
  const compactReadyStatus = section(view,
    "(:compactLegacyState)\n    function readyStatusText()",
    "function readyPrimaryText()");
  assert.match(compactReadyStatus,
    /\|FIT FAIL\|FIT CHECK\|SAVE FAIL\|START FAIL\|REC FAIL\|FIT RETRY\|/,
    "compact recovery must localize exactly the released data-retention statuses");
  assert.doesNotMatch(compactReadyStatus, /current\.find\("FAIL"\)/,
    "unrelated internal failures must not be mislabeled as retained workout data");
  assert.match(view, /GymWorkoutMode\.isFree\(\)[\s\S]*openPauseMenu\(\)/);
  assert.match(view, /function navigateContent\(delta\) \{\s*if \(GymWorkoutMode\.isFree\(\)/);
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
    "static function isValidWorkoutMessage(message)", "static function isValidOptionalAccountBinding(value)");
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

  assert.match(message, /"workoutMode" => workoutMode/);
  assert.match(message, /"sets" => setCopies/);
  assert.match(message, /if \(!freeMode\) \{\s*message\.put\("setMetrics", setMetrics\)/);
  assert.match(message, /if \(!freeMode \|\| combinedSamples > 0\)/);
  assert.match(message, /runtimeWorkoutStartedAtSeconds/);
  assert.match(validator, /message\.size\(\) > 21/);
  assert.match(validator, /modeValue\.toString\(\)\.equals\("free"\)/);
  assert.match(validator, /setsValue\.size\(\) != 0/);
  assert.match(validator, /isBoundedNumber\(durationValue, 1\.0, 604800\.0\)/);
  assert.match(validator, /setMetricsValue == null/);
  assert.match(validator, /Missing workoutMode is the released detailed payload/);
  assert.doesNotMatch(recover, /plan = \[\]/,
    "finishing one activity must not erase the downloaded plan");
});
