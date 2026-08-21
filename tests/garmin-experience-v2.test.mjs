import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(path, "utf8");

const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `Missing start anchor: ${start}`);
  assert.notEqual(endIndex, -1, `Missing end anchor: ${end}`);
  return source.slice(startIndex, endIndex);
};

test("Garmin finish is a prepared to FIT-saved to queued transaction", async () => {
  const [store, view] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/WorkoutView.mc")
  ]);
  const saveAndExit = section(view, "function saveAndExit()", "function onUpdate(");
  const prepared = section(
    store,
    "static function restorePreparedWorkout(value)",
    "static function restoreLastWorkoutSync(value)"
  );

  const prepareAt = saveAndExit.indexOf("GymStore.prepareWorkoutCommit()");
  const fitAt = saveAndExit.indexOf("GymSession.stopAndSave()");
  const markAt = saveAndExit.indexOf("GymStore.markPreparedWorkoutFitSaved()");
  const queueAt = saveAndExit.indexOf("finishWorkout()");
  assert.ok(prepareAt >= 0 && prepareAt < fitAt && fitAt < markAt && markAt < queueAt);
  assert.match(prepared, /Storage\.setValue\("preparedWorkoutV1", marker\)/);
  assert.match(prepared, /activeWorkoutSnapshotMatchesBindings\(value\)/);
  assert.match(prepared, /nextRequestId\("workout"\)/);
  assert.match(prepared, /preparedWorkout\[5\] = 1[\s\S]*Storage\.setValue\("preparedWorkoutV1", preparedWorkout\)/);
  assert.match(prepared, /preparedWorkout\[5\] = 0[\s\S]*status = "FIT CHECK"/);
  assert.match(prepared, /return workoutMessage\(preparedWorkout\[4\]\.toString\(\)\)/);
  assert.match(store, /status = "SYNC FULL"/);
  assert.ok(
    saveAndExit.indexOf("finishWorkout()") < saveAndExit.indexOf("GymStore.clearActiveWorkout()"),
    "active sets may clear only after the durable queue accepts the FIT-saved request"
  );
});

test("Garmin exposes recovery, queue count, last sync, and bounded oldest-first retry", async () => {
  const [store, view, app] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/WorkoutView.mc"),
    read("garmin/source/GymApp.mc")
  ]);
  const retry = section(view, "function maybeRetryPending()", "function hasWorkoutToResume()");
  assert.match(view, /GymStore\.pending\.size\(\)/);
  assert.match(view, /GymStore\.lastWorkoutSyncText\(\)/);
  assert.match(view, /"DATA KEPT · RETRY"/);
  assert.match(retry, /pendingRetryDelayMs\.toLong\(\)/);
  assert.match(view, /if \(next > 300000\)[\s\S]*next = 300000/);
  assert.match(view, /GymComm\.send\(GymStore\.pending\[0\], method\(:onPendingSent\)\)/);
  assert.match(store, /lastWorkoutSyncAtSeconds = Time\.now\(\)\.value\(\)[\s\S]*if \(save\(\)\)/);
  assert.match(app, /removePendingByRequestId\(ackRequestId\)[\s\S]*sendNextPendingWorkout\(\)/);
});

test("Garmin tutorial is once per account, defers recovery, and remains replayable", async () => {
  const [store, view] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/WorkoutView.mc")
  ]);
  assert.match(store, /tutorialHistoryV1/);
  assert.match(store, /maxTutorialAccounts = 4/);
  assert.match(store, /shouldStartTutorial\(\)[\s\S]*!hasUnfinishedWorkout\(\)[\s\S]*!hasPreparedWorkout\(\)/);
  assert.match(store, /next\.add\(accountBinding\.toString\(\)\)[\s\S]*while \(next\.size\(\) > maxTutorialAccounts\)/);
  assert.match(view, /page == 7 && GymStore\.shouldStartTutorial\(\)[\s\S]*startTutorial\(\)/);
  assert.match(view, /settingsCount = 7/);
  assert.match(view, /"TUTORIAL", "НАВЧАННЯ", "ОБУЧЕНИЕ"/);
  assert.match(view, /settingsSelected == 6[\s\S]*view\.page = 7[\s\S]*view\.startTutorial\(\)/);
  assert.match(view, /tutorialStep < 2[\s\S]*GymStore\.markTutorialHandled\(\)/);
  assert.match(view, /tutorialBackOrSkip\(\)/);
  assert.match(view, /Gfx\.COLOR_BLUE/);
});

test("96 KiB watches keep cloud-plan outcome through phone sync without duplicate HTTP parser", async () => {
  const [comm, view, jungle] = await Promise.all([
    read("garmin/source/GymComm.mc"),
    read("garmin/source/WorkoutView.mc"),
    read("garmin/monkey.jungle")
  ]);
  assert.match(jungle, /instinct2\.excludeAnnotations = fullLegacyState;compactRichRecovery;fr55UpgradeBridge/);
  assert.match(comm, /\(:fullLegacyState\)\s+static function requestCloudPlan/);
  assert.match(comm, /\(:compactLegacyState\)\s+static function hasCloudDeviceToken\(\)[\s\S]*return false/);
  assert.match(comm, /\(:compactLegacyState\)\s+static function reconcileCloudDeviceToken/);
  assert.match(view, /\(:compactLegacyState\)\s+function requestCloudSyncNow\(\)[\s\S]*requestSyncNow\(\)/);
});

test("Forerunner 55 compact summary keeps the action below workout metrics", async () => {
  const view = await read("garmin/source/WorkoutView.mc");
  const compactStart = view.indexOf("(:compactRichRecovery)\n    function drawSummary");
  const compactEnd = view.indexOf("(:fullLegacyState)\n    function drawSummaryValue", compactStart);
  assert.notEqual(compactStart, -1);
  assert.notEqual(compactEnd, -1);
  const compactSummary = view.slice(compactStart, compactEnd);

  assert.match(compactSummary, /sy\(h, 62\)[\s\S]*sy\(h, 112\)[\s\S]*sy\(h, 146\)[\s\S]*sy\(h, 190\)/);
  assert.doesNotMatch(compactSummary, /drawMenuRow\(/);
});

test("Forerunner 55 upgrade bridges full-v3 into indexed v4 and merges its runtime journal", async () => {
  const store = await read("garmin/source/GymStore.mc");
  const runtimeBridge = section(
    store,
    "static function fullRuntimeForCompactMigration(active)",
    "static function compactActiveSnapshotFromFullV3(value)"
  );
  const converter = section(
    store,
    "static function compactActiveSnapshotFromFullV3(value)",
    "(:noFr55UpgradeBridge)\n    static function compactActiveSnapshotFromFullV3(value)"
  );
  const compactLoad = section(
    store,
    "(:compactLegacyState)\n    static function load()",
    "(:compactLegacyState)\n    static function save()"
  );
  const migration = section(
    store,
    "(:fr55UpgradeBridge)\n    static function restoreMigratedActiveWorkout(savedActive)",
    "(:noFr55UpgradeBridge)\n    static function compactActiveSnapshotFromFullV3(value)"
  );

  assert.match(converter, /value\.size\(\) != 11/);
  assert.match(store, /\(:fr55UpgradeBridge\)[\s\S]*static function compactActiveSnapshotFromFullV3/);
  assert.match(store, /\(:noFr55UpgradeBridge\)[\s\S]*static function compactActiveSnapshotFromFullV3\(value\)[\s\S]*return null/);
  assert.match(converter, /activeWorkoutSnapshotMatchesBindings\(value\)/);
  assert.ok(
    converter.indexOf("activeWorkoutSnapshotMatchesBindings(value)") <
      converter.indexOf("isValidExerciseList(names, maxWorkoutSets)"),
    "wrong-account snapshots must fail before set conversion"
  );
  assert.match(converter, /isValidSetMetricsList\(metrics, names\)/);
  assert.match(converter, /weights\.size\(\) != names\.size\(\)/);
  assert.match(converter, /isValidWeight\(weights\[i\]\)/);
  assert.match(converter, /isValidReps\(setReps\[i\]\)/);
  assert.match(converter, /checkpoint == null[\s\S]*intervals != null/);
  assert.match(converter, /isValidTimelineCheckpoint\(checkpoint\)/);
  assert.match(converter, /isValidSetIntervalsList\(intervals, names\)/);
  assert.match(converter, /areSetIntervalsConsistent\([\s\S]*checkpoint\[0\][\s\S]*checkpoint\[1\][\s\S]*checkpoint\[2\]/);
  assert.match(runtimeBridge, /Storage\.getValue\("activeRuntimeV1"\)/);
  assert.match(runtimeBridge, /runtime\[4\] != active\[5\]\.size\(\)/);
  assert.match(runtimeBridge, /active\[1\][\s\S]*runtime\[1\][\s\S]*active\[2\][\s\S]*runtime\[2\]/);
  assert.match(runtimeBridge, /sameOptionalText\(active\[3\], runtime\[3\]\)/);
  assert.match(runtimeBridge, /active\[5\]\.size\(\) > 0[\s\S]*active\[4\] != runtime\[6\]/);
  assert.match(converter, /var runtime = fullRuntimeForCompactMigration\(value\)/);
  assert.match(converter, /startedAt = runtime\[6\][\s\S]*checkpoint = runtime\[7\]/);
  assert.ok(
    converter.indexOf("fullRuntimeForCompactMigration(value)") <
      converter.indexOf("var indices = []"),
    "the current runtime must be merged before the indexed transaction is built"
  );
  assert.match(converter, /var catalogIndex = exerciseIndexForName\(names\[j\]\)/);
  assert.match(converter, /indices\.add\(catalogIndex\)/);
  assert.match(converter, /safeIntervals\.add\(copySetInterval\(intervals\[j\]\)\)/);
  assert.match(converter, /safeCheckpoint = checkpoint == null \? null : copySetInterval\(checkpoint\)/);
  assert.match(converter, /var candidate = \[[\s\S]*4,[\s\S]*indices,[\s\S]*safeWeights,[\s\S]*safeReps,[\s\S]*safeIntervals,[\s\S]*safeCheckpoint/);
  assert.match(converter, /isValidActiveWorkoutSnapshot\(candidate\)[\s\S]*isWithinStorageBudgetForActiveSnapshot\(candidate\)/);

  const restoreAt = migration.indexOf("restoreActiveWorkoutSnapshot(migratedActive)");
  const rewriteAt = migration.indexOf('Storage.setValue("activeWorkoutV1", migratedActive)');
  const cleanupAt = migration.indexOf('Storage.deleteValue("activeRuntimeV1")');
  assert.ok(restoreAt >= 0 && restoreAt < rewriteAt && rewriteAt < cleanupAt);
  assert.match(migration, /catch \(e\) \{[\s\S]*status = "SAVE FAIL"/);
  assert.match(compactLoad, /ownerMatches && restoreMigratedActiveWorkout\(savedActive\)/);

  const OWNER = "a".repeat(64);
  const DEVICE = "fr55-device";
  const GENERATION = "b".repeat(64);
  const ORIGIN = 1_800_000_000;
  const CATALOG = ["Bench Press", "Squat", "Deadlift"];
  const checkpoint = [120, 4.0, 3, 13_000, 100, 160, 138, 3];
  const intervalA = [0, 35, 1.5, 1, 0, 5, 15, 10, 5, 0];
  const intervalB = [60, 95, 1.7, 1, 0, 5, 15, 10, 5, 0];
  const full = [
    3,
    OWNER,
    DEVICE,
    GENERATION,
    ORIGIN,
    ["Bench Press", "Squat"],
    [60, 80],
    [10, 8],
    [[35, null, 110, 150, 135, 15, 90], [35, 25, 115, 160, 138, null, 88]],
    [intervalA, intervalB],
    checkpoint
  ];

  const runtimeForActive = (active, runtime) => {
    if (runtime == null) return null;
    if (!Array.isArray(runtime) || runtime.length !== 11 || runtime[0] !== 1 ||
        runtime[1] !== active[1] || runtime[2] !== active[2] || runtime[3] !== active[3] ||
        runtime[4] !== active[5].length || !Number.isInteger(runtime[5]) ||
        !Number.isInteger(runtime[6]) || runtime[6] > runtime[5] ||
        runtime[5] - runtime[6] > 604_800 || !Array.isArray(runtime[7]) ||
        runtime[7].length !== 8 || typeof runtime[8] !== "boolean" ||
        !Number.isInteger(runtime[9]) || runtime[9] < 0 || runtime[9] > 2) return null;
    if (active[5].length > 0 && active[4] !== runtime[6]) return null;
    return runtime;
  };

  const migrateModel = (
    value,
    { binding = [OWNER, DEVICE, GENERATION], catalog = CATALOG, runtime = null } = {}
  ) => {
    if (!Array.isArray(value) || value.length !== 11 || value[0] !== 3 ||
        value[1] !== binding[0] || value[2] !== binding[1] || value[3] !== binding[2]) return null;
    const [names, weights, reps, metrics, intervals, timeline] =
      [value[5], value[6], value[7], value[8], value[9], value[10]];
    if (!Array.isArray(names) || names.length > 60 ||
        !Array.isArray(weights) || !Array.isArray(reps) || !Array.isArray(metrics) ||
        weights.length !== names.length || reps.length !== names.length ||
        metrics.length !== names.length ||
        names.some((name) => typeof name !== "string" || name.length < 1 || name.length > 96) ||
        weights.some((weight) => !Number.isFinite(weight) || weight < 0 || weight > 1000) ||
        reps.some((count) => !Number.isInteger(count) || count < 1 || count > 999) ||
        metrics.some((item) => !Array.isArray(item) || item.length !== 7)) return null;
    let started = value[4];
    let safeIntervals = intervals;
    let safeTimeline = timeline;
    if ((names.length === 0 && started !== null) ||
        (names.length > 0 && started !== null &&
          (!Number.isInteger(started) || started < 946684800 || started > 2147483647)) ||
        (names.length > 0 && started === null && timeline !== null)) return null;
    if (timeline === null) {
      if (intervals !== null) return null;
    } else {
      if (!Array.isArray(timeline) || timeline.length !== 8 ||
          !Array.isArray(intervals) || intervals.length !== names.length) return null;
      let previousEnd = 0;
      let gymTotal = 0;
      for (const item of intervals) {
        if (!Array.isArray(item) || item.length !== 10 || item[0] < previousEnd ||
            item[1] < item[0] || item[1] > timeline[0]) return null;
        previousEnd = item[1];
        gymTotal += item[2];
      }
      if (gymTotal > timeline[1] + 0.1) return null;
    }
    const currentRuntime = runtimeForActive(value, runtime);
    if (currentRuntime != null) {
      started = currentRuntime[6];
      safeTimeline = currentRuntime[7];
      if (names.length === 0) safeIntervals = [];
    }
    const indices = names.map((name) => catalog.indexOf(name));
    if (indices.some((index) => index < 0)) return null;
    return [
      4,
      value[1],
      value[2],
      value[3],
      started,
      indices,
      [...weights],
      [...reps],
      safeTimeline === null ? null : safeIntervals.map((item) => [...item]),
      safeTimeline === null ? null : [...safeTimeline]
    ];
  };

  const migrated = migrateModel(full);
  assert.deepEqual(migrated.slice(0, 5), [4, OWNER, DEVICE, GENERATION, ORIGIN]);
  assert.deepEqual(migrated[5], [0, 1]);
  assert.deepEqual(migrated[6], [60, 80]);
  assert.deepEqual(migrated[7], [10, 8]);
  assert.deepEqual(migrated[8], [intervalA, intervalB]);
  assert.deepEqual(migrated[9], checkpoint);
  assert.notEqual(migrated[8][0], intervalA);
  assert.notEqual(migrated[9], checkpoint);
  assert.equal(migrated.length, 10, "compact v4 deliberately drops the full-only metrics column");

  const withoutTimeline = structuredClone(full);
  withoutTimeline[9] = null;
  withoutTimeline[10] = null;
  assert.equal(migrateModel(withoutTimeline)[8], null);

  const tombstone = [3, OWNER, DEVICE, GENERATION, null, [], [], [], [], null, null];
  assert.deepEqual(migrateModel(tombstone),
    [4, OWNER, DEVICE, GENERATION, null, [], [], [], null, null]);
  const runtimeCheckpoint = [12, 1.5, null, 1300, 10, 145, 140, 2];
  const activeRuntimeV1 = [
    1, OWNER, DEVICE, GENERATION, 0, ORIGIN + 120, ORIGIN,
    runtimeCheckpoint, false, 0, 0
  ];
  const preSetRuntime = migrateModel(tombstone, { runtime: activeRuntimeV1 });
  assert.equal(preSetRuntime[4], ORIGIN);
  assert.deepEqual(preSetRuntime[8], []);
  assert.deepEqual(preSetRuntime[9], runtimeCheckpoint);
  assert.notEqual(preSetRuntime[9], runtimeCheckpoint);
  const isUnfinished = (candidate) => candidate[5].length > 0 || candidate[4] !== null ||
    (candidate[9] != null &&
      (candidate[9][0] > 0 || candidate[9][1] > 0 || candidate[9][2] !== null ||
        candidate[9][4] > 0 || candidate[9][5] > 0 || candidate[9][6] !== null));
  assert.equal(isUnfinished(migrateModel(tombstone)), false);
  assert.equal(isUnfinished(preSetRuntime), true);

  const foreignRuntime = structuredClone(activeRuntimeV1);
  foreignRuntime[1] = "c".repeat(64);
  assert.equal(migrateModel(tombstone, { runtime: foreignRuntime })[4], null,
    "a foreign runtime is ignored instead of authorizing a started workout");

  assert.equal(migrateModel(full, { binding: ["c".repeat(64), DEVICE, GENERATION] }), null);
  assert.equal(migrateModel(full, { binding: [OWNER, "wrong-device", GENERATION] }), null);
  assert.equal(migrateModel(full, { binding: [OWNER, DEVICE, "d".repeat(64)] }), null);
  assert.equal(migrateModel(full, { catalog: ["Bench Press"] }), null,
    "every v3 name must resolve against the durable catalog before it becomes an index");
  const malformedMetrics = structuredClone(full);
  malformedMetrics[8][0] = [1, 2];
  assert.equal(migrateModel(malformedMetrics), null);
  const invalidWeight = structuredClone(full);
  invalidWeight[6][0] = Number.NaN;
  assert.equal(migrateModel(invalidWeight), null);
  const unequal = structuredClone(full);
  unequal[7].pop();
  assert.equal(migrateModel(unequal), null);
  const overlapping = structuredClone(full);
  overlapping[9][1][0] = 30;
  assert.equal(migrateModel(overlapping), null);
  const noIntervals = structuredClone(full);
  noIntervals[9] = null;
  assert.equal(migrateModel(noIntervals), null);
  const intervalsWithoutTimeline = structuredClone(full);
  intervalsWithoutTimeline[10] = null;
  assert.equal(migrateModel(intervalsWithoutTimeline), null);
});

test("Forerunner 55 checkpoints explicit lifecycle boundaries without periodic history copies", async () => {
  const [store, view] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/WorkoutView.mc")
  ]);
  const compactValidation = section(
    store,
    "(:enhancedCompactCheckpoint)\n    static function isValidActiveWorkoutSnapshot(snapshot)",
    "// The five 96 KiB products"
  );
  const compact96Validation = section(
    store,
    "(:compactCheckpoint96)\n    static function isValidActiveWorkoutSnapshot(snapshot)",
    "// These products used the full v3 parallel-array snapshot"
  );
  const compactRestore = section(
    store,
    "(:enhancedCompactCheckpoint)\n    static function restoreActiveWorkoutSnapshot(snapshot)",
    "(:compactCheckpoint96)\n    static function restoreActiveWorkoutSnapshot(snapshot)"
  );
  const compactCheckpoint = section(
    store,
    "(:enhancedCompactCheckpoint)\n    static function checkpointLiveWorkout(force)",
    "(:compactCheckpoint96)\n    static function checkpointLiveWorkout(force)"
  );
  const compactSave = section(
    store,
    "(:compactLegacyState)\n    static function save()",
    "(:fullLegacyState)\n    static function resetRuntimeCheckpointState()"
  );

  assert.match(compactValidation, /snapshotSets\.size\(\) == 0 && startedAtSeconds != null[\s\S]*snapshot\[0\] != 3[\s\S]*checkpoint == null[\s\S]*isValidWorkoutStartedAtSeconds/);
  assert.match(compact96Validation, /snapshotSets\.size\(\) == 0 && startedAtSeconds != null[\s\S]*snapshot\[0\] != 3[\s\S]*checkpoint == null[\s\S]*isValidWorkoutStartedAtSeconds/);
  assert.match(compactCheckpoint, /if \(!force\) \{\s*return true;/);
  assert.doesNotMatch(compactCheckpoint, /elapsedSeconds - lastCompactCheckpointElapsed < 15/);
  assert.match(compactCheckpoint, /origin = GymSession\.startedAt/);
  assert.match(compactCheckpoint, /persistActiveWorkoutSnapshot\(sets, origin, checkpoint\)[\s\S]*activeWorkoutStartedAtSeconds = origin[\s\S]*runtimeWorkoutStartedAtSeconds = origin/);
  assert.doesNotMatch(compactSave, /persistActiveWorkoutSnapshot\(/);
  assert.match(compactRestore, /lastInterval = sets\[sets\.size\(\) - 1\]\.get\("setInterval"\)/);
  assert.match(compactRestore, /elapsedSinceSet = checkpoint\[0\] - lastInterval\[1\]/);
  assert.match(compactRestore, /remainingRest = restSecondsDefault - elapsedSinceSet/);
  assert.match(view, /startOrResumeWorkout\(usePlan\)[\s\S]*checkpointLiveWorkout\(true\)/);
  assert.match(view, /A restored workout is already durable[\s\S]*!resuming && !GymStore\.checkpointLiveWorkout\(true\)/);
  assert.match(view, /openPauseMenu\(\)[\s\S]*checkpointLiveWorkout\(true\)/);
  assert.match(view, /function onHide\(\)[\s\S]*checkpointLiveWorkout\(true\)[\s\S]*stopSensors\(\)/);

  const ORIGIN = 1_800_000_000;
  const tombstone = [3, "a".repeat(64), "fr55", null, null, [],
    [0, 0, null, 0, 0, 0, null, 0]];
  const justStarted = structuredClone(tombstone);
  justStarted[4] = ORIGIN;
  const validEmpty = (snapshot) => snapshot[5].length === 0 &&
    (snapshot[4] === null ||
      (snapshot[0] === 3 && snapshot[6] !== null &&
        Number.isInteger(snapshot[4]) && snapshot[4] >= 946684800));
  assert.equal(validEmpty(tombstone), true);
  assert.equal(validEmpty(justStarted), true);
  assert.equal(tombstone[4] !== null, false);
  assert.equal(justStarted[4] !== null, true);

  const remainingRest = ({ checkpointElapsed, intervalEnd, restDefault }) => {
    const remaining = restDefault - (checkpointElapsed - intervalEnd);
    return remaining > 0 && remaining <= 3600 ? remaining : 0;
  };
  assert.equal(remainingRest({ checkpointElapsed: 75, intervalEnd: 35, restDefault: 90 }), 50);
  assert.equal(remainingRest({ checkpointElapsed: 140, intervalEnd: 35, restDefault: 90 }), 0);
});

test("96 KiB phase-zero retry is sets-only, idempotent, and cannot race an ACK", async () => {
  const [store, session, view, app] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/GymSession.mc"),
    read("garmin/source/WorkoutView.mc"),
    read("garmin/source/GymApp.mc")
  ]);
  const compactOutcome = section(
    session,
    "(:compactRecovery96)\n    static function fitOutcomeUnknownAfterRestart()",
    "static function discard()"
  );
  const compactMessage = section(
    store,
    "(:compactRecovery96)\n    static function preparedWorkoutSetsOnlyMessage()",
    "static function restoreLastWorkoutSync(value)"
  );
  const compactFinish = section(
    view,
    "(:compactRecovery96)\n    function finishWorkout()",
    "(:richRecovery)\n    function finishFitRecovery(activityFound)"
  );
  const compactSave = section(
    view,
    "(:compactRecovery96)\n    function saveAndExit()",
    "(:fullLegacyState)\n    function onUpdate(dc)"
  );
  const queue = section(
    store,
    "static function queueWorkout(message)",
    "static function beginAccountTransition()"
  );

  assert.match(compactOutcome, /session == null && !recording && !fitSaved/);
  assert.doesNotMatch(compactOutcome, /createSession|stopAndSave|\.save\(|\.discard\(/);
  assert.match(compactMessage, /hasPreparedWorkout\(\)[\s\S]*preparedWorkout\[5\] != 0[\s\S]*fitOutcomeUnknownAfterRestart\(\)/);
  assert.match(compactMessage, /workoutMessage\(preparedWorkout\[4\]\.toString\(\)\)/);
  assert.match(compactSave, /fitUnknown = needsPhoneSync[\s\S]*!fitUnknown && !fitAlreadySaved && !GymSession\.stopAndSave\(\)/);
  assert.match(compactSave, /needsPhoneSync && !fitUnknown[\s\S]*markPreparedWorkoutFitSaved\(\)/);
  assert.match(compactFinish, /preparedWorkoutFitSaved\(\) \?[\s\S]*preparedWorkoutMessage\(\) :[\s\S]*preparedWorkoutSetsOnlyMessage\(\)/);

  const duplicateAt = queue.indexOf("alreadyQueued = true");
  const capacityAt = queue.indexOf("canQueueWorkout(message)");
  const recoverAt = queue.indexOf("recoverQueuedWorkout()");
  assert.ok(duplicateAt >= 0 && duplicateAt < capacityAt && capacityAt < recoverAt,
    "same-id recovery must bypass a full queue before finalizing the transaction");
  assert.match(queue, /Storage\.setValue\("queuedActiveRequestId", requestId\)[\s\S]*Storage\.setValue\("pending", nextPending\)/);
  assert.match(queue, /persistEmptyActiveWorkoutSnapshot\(\)[\s\S]*sets = \[\][\s\S]*if \(!save\(\)\)[\s\S]*clearPreparedWorkout\(marker\)/);
  assert.match(store, /removePendingByRequestId\(requestId\)[\s\S]*!recoverQueuedWorkout\(\)/);
  assert.match(view, /function flushPending\(\)[\s\S]*!GymStore\.recoverQueuedWorkout\(\)[\s\S]*GymComm\.send/);
  assert.match(app, /function sendNextPendingWorkout\(\)[\s\S]*!GymStore\.recoverQueuedWorkout\(\)[\s\S]*GymComm\.send/);

  const simulate = ({ markerWritten, pendingWritten, tombstoneWritten, cleaned }) => ({
    sendable: markerWritten && pendingWritten && tombstoneWritten && cleaned,
    preservesSets: !tombstoneWritten,
    canRetrySameId: pendingWritten && !cleaned
  });
  assert.deepEqual(simulate({ markerWritten: true, pendingWritten: false,
    tombstoneWritten: false, cleaned: false }), {
    sendable: false, preservesSets: true, canRetrySameId: false
  });
  assert.deepEqual(simulate({ markerWritten: true, pendingWritten: true,
    tombstoneWritten: false, cleaned: false }), {
    sendable: false, preservesSets: true, canRetrySameId: true
  });
  assert.deepEqual(simulate({ markerWritten: true, pendingWritten: true,
    tombstoneWritten: true, cleaned: true }), {
    sendable: true, preservesSets: false, canRetrySameId: false
  });
});
