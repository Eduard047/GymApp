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

test("Forerunner 55 upgrade preserves an owner-bound full-v3 active workout", async () => {
  const store = await read("garmin/source/GymStore.mc");
  const converter = section(
    store,
    "static function compactActiveSnapshotFromFullV3(value)",
    "// Version 3 stores set fields in parallel arrays"
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
  assert.match(converter, /safe\.put\("setInterval", copySetInterval\(intervals\[j\]\)\)/);
  assert.match(converter, /safeCheckpoint = checkpoint == null \? null : copySetInterval\(checkpoint\)/);
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

  const migrateModel = (value, binding = [OWNER, DEVICE, GENERATION]) => {
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
    const started = value[4];
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
    return [3, value[1], value[2], value[3], started, names.map((name, index) => ({
      exerciseName: name,
      weight: weights[index],
      reps: reps[index],
      ...(timeline === null ? {} : { setInterval: [...intervals[index]] })
    })), timeline === null ? null : [...timeline]];
  };

  const migrated = migrateModel(full);
  assert.deepEqual(migrated.slice(0, 5), full.slice(0, 5));
  assert.deepEqual(migrated[5].map(({ exerciseName, weight, reps }) =>
    [exerciseName, weight, reps]), [["Bench Press", 60, 10], ["Squat", 80, 8]]);
  assert.deepEqual(migrated[6], checkpoint);
  assert.notEqual(migrated[5][0].setInterval, intervalA);
  assert.notEqual(migrated[6], checkpoint);
  assert.equal("activeSeconds" in migrated[5][0], false);

  const withoutTimeline = structuredClone(full);
  withoutTimeline[9] = null;
  withoutTimeline[10] = null;
  assert.equal("setInterval" in migrateModel(withoutTimeline)[5][0], false);

  const tombstone = [3, OWNER, DEVICE, GENERATION, null, [], [], [], [], [],
    [0, 0, null, 0, 0, 0, null, 0]];
  assert.deepEqual(migrateModel(tombstone)[5], []);
  const preSetRuntime = structuredClone(tombstone);
  preSetRuntime[10] = [12, 1.5, null, 1300, 10, 145, 140, 2];
  assert.deepEqual(migrateModel(preSetRuntime)[6], preSetRuntime[10]);
  const isUnfinished = (candidate) => candidate[5].length > 0 || candidate[4] !== null ||
    candidate[6][0] > 0 || candidate[6][1] > 0 || candidate[6][2] !== null ||
    candidate[6][4] > 0 || candidate[6][5] > 0 || candidate[6][6] !== null;
  assert.equal(isUnfinished(migrateModel(tombstone)), false);
  assert.equal(isUnfinished(migrateModel(preSetRuntime)), true);

  assert.equal(migrateModel(full, ["c".repeat(64), DEVICE, GENERATION]), null);
  assert.equal(migrateModel(full, [OWNER, "wrong-device", GENERATION]), null);
  assert.equal(migrateModel(full, [OWNER, DEVICE, "d".repeat(64)]), null);
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

test("Forerunner 55 checkpoints the first second, pause, and bounded rest recovery", async () => {
  const [store, view] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/WorkoutView.mc")
  ]);
  const compactValidation = section(
    store,
    "(:enhancedCompactCheckpoint)\n    static function isValidActiveWorkoutSnapshot(snapshot)",
    "// Preserve the proven low-memory validation path"
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
  assert.match(compactCheckpoint, /!force && \(GymSession\.paused \|\|[\s\S]*GymSession\.elapsedSeconds - lastCompactCheckpointElapsed < 15\)/);
  assert.match(compactCheckpoint, /origin = GymSession\.startedAt/);
  assert.match(compactCheckpoint, /persistActiveWorkoutSnapshot\(sets, origin, checkpoint\)[\s\S]*activeWorkoutStartedAtSeconds = origin[\s\S]*runtimeWorkoutStartedAtSeconds = origin[\s\S]*lastCompactCheckpointElapsed = GymSession\.elapsedSeconds/);
  assert.match(compactSave, /runtimeWorkoutStartedAtSeconds == null[\s\S]*emptyTimelineCheckpoint\(\) : currentTimelineCheckpoint/);
  assert.match(compactSave, /persistActiveWorkoutSnapshot\([\s\S]*sets,[\s\S]*activeWorkoutStartedAtSeconds,[\s\S]*checkpoint/);
  assert.match(compactRestore, /lastInterval = sets\[sets\.size\(\) - 1\]\.get\("setInterval"\)/);
  assert.match(compactRestore, /elapsedSinceSet = checkpoint\[0\] - lastInterval\[1\]/);
  assert.match(compactRestore, /remainingRest = restSecondsDefault - elapsedSinceSet/);
  assert.match(view, /startOrResumeWorkout\(\)[\s\S]*checkpointLiveWorkout\(true\)/);
  assert.match(view, /openPauseMenu\(\)[\s\S]*checkpointLiveWorkout\(true\)/);

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
