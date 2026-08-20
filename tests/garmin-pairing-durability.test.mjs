import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const storeSource = await readFile("garmin/source/GymStore.mc", "utf8");

const functionSlice = (name, nextName) => {
  const start = storeSource.indexOf(`static function ${name}(`);
  const end = storeSource.indexOf(`static function ${nextName}(`, start + 1);
  assert.ok(start >= 0 && end > start, `missing ${name} source`);
  return storeSource.slice(start, end);
};

const copy = (value) => JSON.parse(JSON.stringify(value));
const OWNER = "a".repeat(64);
const OTHER_OWNER = "b".repeat(64);
const OLD_GENERATION = "c".repeat(64);
const NEXT_GENERATION = "d".repeat(64);
const DEVICE = "garmin-device-1";

const initialStore = (generation) => ({
  accountBinding: OWNER,
  stateOwnerBinding: OWNER,
  deviceBinding: DEVICE,
  pairingGeneration: generation,
  active: {
    accountBinding: OWNER,
    deviceBinding: DEVICE,
    pairingGeneration: generation,
    workoutId: "active-workout",
    sets: [{ exerciseName: "Squat", weight: 100, reps: 5 }]
  },
  prepared: {
    accountBinding: OWNER,
    deviceBinding: DEVICE,
    pairingGeneration: generation,
    requestId: "prepared-1"
  },
  pending: [
    {
      accountBinding: OWNER,
      deviceBinding: DEVICE,
      pairingGeneration: generation,
      requestId: "pending-1"
    },
    {
      accountBinding: OWNER,
      deviceBinding: DEVICE,
      pairingGeneration: generation,
      requestId: "pending-2"
    }
  ],
  fence: { revision: 40, requestId: "sync-40", accountBinding: OWNER }
});

const stagedTransition = (repairPairing) => ({
  revision: 41,
  requestId: "sync-41",
  accountBinding: OWNER,
  deviceBinding: DEVICE,
  pairingGeneration: NEXT_GENERATION,
  repairPairing,
  resetWorkout: false
});

// The target-bound active transaction is already durable. save() then writes the
// prepared marker and pending queue before publishing the standalone generation.
// Each cut models power loss before the next write; the phone stage is retained.
const storeAtWriteCut = (previousGeneration, cut) => {
  const stored = initialStore(previousGeneration);
  stored.active.pairingGeneration = NEXT_GENERATION;
  const writes = [
    () => { stored.prepared.pairingGeneration = NEXT_GENERATION; },
    () => {
      stored.pending = stored.pending.map((item) => ({
        ...item,
        pairingGeneration: NEXT_GENERATION
      }));
    },
    () => { stored.pairingGeneration = NEXT_GENERATION; }
  ];
  for (let index = 0; index < cut; index += 1) writes[index]();
  return stored;
};

const loadWithDurableStage = (input, stage, { recoverySaveSucceeds = true } = {}) => {
  const stored = copy(input);
  const originalGeneration = stored.pairingGeneration;
  const sameOwner = stored.accountBinding === stored.stateOwnerBinding &&
    stage.accountBinding === stored.accountBinding;
  const sameDevice = stage.deviceBinding === stored.deviceBinding;
  const currentFenceAllowsStage = stage.revision > stored.fence.revision ||
    (stage.revision === stored.fence.revision &&
      stage.requestId === stored.fence.requestId &&
      stage.accountBinding === stored.fence.accountBinding);
  if (!sameOwner || !sameDevice || !currentFenceAllowsStage ||
      stage.resetWorkout === true || typeof stage.pairingGeneration !== "string") {
    return { ok: false, stored };
  }

  const target = stage.pairingGeneration;
  const needsRecovery = originalGeneration !== target;
  if (needsRecovery) {
    const validTransition = originalGeneration == null ?
      stage.repairPairing !== true : stage.repairPairing === true;
    if (!validTransition) return { ok: false, stored };
  }
  const scopeMatches = (value) => value.accountBinding === stored.accountBinding &&
    value.deviceBinding === stored.deviceBinding;
  if ((stored.active != null && !scopeMatches(stored.active)) ||
      (stored.prepared != null && !scopeMatches(stored.prepared)) ||
      !stored.pending.every(scopeMatches)) {
    return { ok: false, stored };
  }

  if (needsRecovery) {
    const activeTargetsRecovery = stored.active != null &&
      stored.active.pairingGeneration === target;
    const preparedTargetsRecovery = stored.prepared != null &&
      stored.prepared.pairingGeneration === target;
    if ((stored.active != null && !activeTargetsRecovery) ||
        (stored.active == null && stored.prepared != null && !preparedTargetsRecovery)) {
      return {
        ok: false,
        deferred: true,
        stageRetained: true,
        stored
      };
    }
    const pendingTransitionIsValid = stored.pending.every((item) =>
      item.pairingGeneration === originalGeneration || item.pairingGeneration === target);
    const preparedTransitionIsValid = stored.prepared == null ||
      stored.prepared.pairingGeneration === originalGeneration || preparedTargetsRecovery;
    if (!pendingTransitionIsValid || !preparedTransitionIsValid) {
      return { ok: false, stored };
    }
    stored.pairingGeneration = target;
    if (stored.prepared != null) stored.prepared.pairingGeneration = target;
    stored.pending.forEach((item) => { item.pairingGeneration = target; });
    if (!recoverySaveSucceeds) {
      stored.pairingGeneration = originalGeneration;
      if (stored.prepared != null) stored.prepared.pairingGeneration = originalGeneration;
      stored.pending.forEach((item) => { item.pairingGeneration = originalGeneration; });
      return {
        ok: false,
        recoverySaveFailed: true,
        stageRetained: true,
        stored
      };
    }
  }
  return { ok: true, recovered: needsRecovery, stageRetained: true, stored };
};

test("Garmin load defers old-bound pairing stages and completes target-bound partial commits", () => {
  const load = functionSlice("load", "save");
  const recovery = functionSlice("stagedPairingRecoveryTarget", "loadSyncStage");
  const rotate = functionSlice("rotatePairingGenerationForPending", "queueWorkout");
  const applySync = functionSlice("applySyncFromSource", "applyValidatedSync");
  const compactApplyStart = storeSource.indexOf(
    "(:compactLegacyState)\n    static function applySyncFromSource("
  );
  const compactApplyEnd = storeSource.indexOf(
    "static function applyValidatedSync(",
    compactApplyStart
  );
  const compactApplySync = storeSource.slice(compactApplyStart, compactApplyEnd);

  assert.ok(load.indexOf('loadSyncStage("phone")') <
    load.indexOf("stagedPairingRecoveryTarget()"));
  assert.ok(load.indexOf("stagedPairingRecoveryTarget()") <
    load.indexOf("isValidActiveWorkoutSnapshot(savedActiveWorkout)"));
  assert.match(load, /savedRuntimeForPairingRecovery = Storage\.getValue\("activeRuntimeV1"\)/);
  assert.match(load, /savedActiveHasSets = storedActiveSnapshotHasSets\(savedActiveWorkout\)/);
  assert.match(load, /activeAlreadyTargetsRecovery[\s\S]*activeWorkoutSnapshotMatchesBindings\(savedActiveWorkout\)/);
  assert.match(load, /savedActiveHasSets \|\| savedRuntimeForPairingRecovery != null[\s\S]*!activeAlreadyTargetsRecovery[\s\S]*pairingRecoveryDeferred = true/);
  assert.match(load, /!savedActiveHasSets && savedRuntimeForPairingRecovery == null[\s\S]*savedPreparedWorkout != null && !preparedAlreadyTargetsRecovery/);
  assert.match(load, /if \(pairingRecoveryDeferred\)[\s\S]*pairingRecoveryTarget = null/);
  assert.match(load, /validActiveSnapshot[\s\S]*!snapshotMatches && recoveredPairing[\s\S]*pairingGeneration = previousPairingGeneration[\s\S]*activeWorkoutSnapshotMatchesBindings\(savedActiveWorkout\)[\s\S]*pairingGeneration = pairingRecoveryTarget/);
  assert.match(load, /recoveredPairing && savedPreparedWorkout != null[\s\S]*preparedMatchesPrevious[\s\S]*savedPreparedWorkout\[3\] = pairingRecoveryTarget/);
  assert.match(load, /pairingRecoveryDeferred && preparedAlreadyTargetsRecovery[\s\S]*preparedWorkout = savedPreparedWorkout/);
  assert.match(load, /pruneAccountScopedState\(\);[\s\S]*recoverQueuedWorkout\(\);[\s\S]*if \(recoveredPairing\)[\s\S]*pairingRecoveryCommitLast = true[\s\S]*recoverySaved = save\(\)[\s\S]*pairingRecoveryCommitLast = false[\s\S]*if \(!recoverySaved\)[\s\S]*pairingGeneration = previousPairingGeneration[\s\S]*pending\[i\]\.put\("pairingGeneration", previousPairingGeneration\)[\s\S]*status = "SAVE FAIL"/);
  assert.doesNotMatch(load, /clearSyncStage/);

  assert.match(recovery, /hasAccountBinding\(\)/);
  assert.match(recovery, /syncRevisionStatus\(message, "phone"\) < 0/);
  assert.match(recovery, /accountBinding[\s\S]*message\.get\("accountBinding"\)/);
  assert.match(recovery, /deviceBinding[\s\S]*message\.get\("deviceBinding"\)/);
  assert.match(recovery, /message\.get\("resetWorkout"\) == true/);
  assert.match(recovery, /isValidAccountBinding\(message\.get\("pairingGeneration"\)\)/);
  assert.match(recovery, /return repair \? nextGeneration : null[\s\S]*return repair \? null : nextGeneration/);

  assert.match(rotate, /isValidOptionalAccountBinding\(previousGeneration\)/);
  assert.match(rotate, /matchesPrevious[\s\S]*matchesNext/);
  assert.match(rotate, /accountBinding[\s\S]*deviceBinding/);
  assert.ok(rotate.indexOf("matchesNext") < rotate.indexOf("for (var j = 0"));
  assert.match(rotate, /pending\[j\]\.put\("pairingGeneration", nextGeneration\.toString\(\)\)/);

  assert.match(applySync, /var revisionStatus = syncRevisionStatus\(safeMessage, bindingSource\)[\s\S]*var repairReplay = repairPairing/);
  assert.match(applySync, /revisionStatus == 0 \|\| isExactStagedSync\(safeMessage, bindingSource\)/);
  assert.match(applySync, /pairingGeneration\.toString\(\)\.equals\(nextPairingGeneration\.toString\(\)\)[\s\S]*!repairReplay/);
  assert.match(applySync, /\(shouldUpgradePending \|\| repairPairing\)[\s\S]*rotatePairingGenerationForPending/);
  assert.ok(
    applySync.indexOf("pairingGenerationChanges") < applySync.indexOf("stageSync(safeMessage"),
    "a live old-bound workout must reject the new generation before journaling it"
  );
  assert.doesNotMatch(storeSource, /adoptPairingGenerationForPending/);
  assert.match(compactApplySync, /revisionStatus == 0[\s\S]*isExactStagedSync\(safeMessage, bindingSource\)[\s\S]*!syncBindingsMatch\(safeMessage\)[\s\S]*revisionStatus = 1[\s\S]*status = "SYNC DUP"[\s\S]*clearSyncStageIfMatches\(safeMessage, bindingSource\)[\s\S]*return true/);

  const fullSaveStart = storeSource.indexOf("(:fullLegacyState)\n    static function save()");
  const fullSaveEnd = storeSource.indexOf("(:compactLegacyState)\n    static function load()", fullSaveStart);
  const compactSaveStart = storeSource.indexOf("(:compactLegacyState)\n    static function save()");
  const compactSaveEnd = storeSource.indexOf("static function ensureDurableExerciseCatalog()", compactSaveStart);
  for (const save of [
    storeSource.slice(fullSaveStart, fullSaveEnd),
    storeSource.slice(compactSaveStart, compactSaveEnd)
  ]) {
    const pendingAt = save.indexOf('Storage.setValue("pending", pending)');
    const preparedSetAt = save.indexOf('Storage.setValue("preparedWorkoutV1", preparedWorkout)');
    const preparedDeleteAt = save.indexOf('Storage.deleteValue("preparedWorkoutV1")');
    const ownerSetAt = save.indexOf('Storage.setValue("stateOwnerBinding", accountBinding)');
    const ownerDeleteAt = save.indexOf('Storage.deleteValue("stateOwnerBinding")');
    const ordinaryGenerationAt = save.indexOf('Storage.setValue("pairingGeneration", pairingGeneration)');
    const recoveryGenerationAt = save.indexOf(
      'Storage.setValue("pairingGeneration", pairingGeneration)',
      ordinaryGenerationAt + 1
    );
    const ordinaryGuardAt = save.indexOf("if (!pairingRecoveryCommitLast)");
    const recoveryGuardAt = save.indexOf("if (pairingRecoveryCommitLast)");
    assert.ok(pendingAt >= 0 && preparedSetAt >= 0 && preparedDeleteAt >= 0 &&
      ownerSetAt >= 0 && ownerDeleteAt >= 0 && ordinaryGenerationAt >= 0 &&
      recoveryGenerationAt > ordinaryGenerationAt && ordinaryGuardAt >= 0 &&
      recoveryGuardAt >= 0);
    assert.ok(pendingAt < ordinaryGenerationAt && preparedSetAt < ordinaryGenerationAt &&
      preparedDeleteAt < ordinaryGenerationAt,
    "prepared and pending transactions must be durable before either commit point");
    assert.ok(ordinaryGenerationAt < ownerSetAt && ordinaryGenerationAt < ownerDeleteAt,
      "ordinary account transitions publish generation before the owner commit point");
    assert.ok(ownerSetAt < recoveryGenerationAt && ownerDeleteAt < recoveryGenerationAt,
      "same-owner pairing recovery publishes generation after the unchanged owner marker");
    assert.ok(ordinaryGuardAt < ordinaryGenerationAt,
      "ordinary generation write must be guarded by non-recovery mode");
    assert.ok(recoveryGuardAt < recoveryGenerationAt,
      "recovery generation write must be guarded by recovery mode");
    assert.doesNotMatch(save.slice(recoveryGenerationAt + 1),
      /Storage\.(?:setValue|deleteValue)\(/,
      "pairing recovery generation must be the final throwable Storage commit");
  }
});

test("old-bound stages wait while every target-bound pairing write cut completes", () => {
  const cases = [
    { name: "adoption", previous: null, repair: false },
    { name: "repair", previous: OLD_GENERATION, repair: true }
  ];

  for (const scenario of cases) {
    const oldBound = initialStore(scenario.previous);
    const deferred = loadWithDurableStage(oldBound, stagedTransition(scenario.repair));
    assert.equal(deferred.ok, false);
    assert.equal(deferred.deferred, true);
    assert.equal(deferred.stageRetained, true);
    assert.deepEqual(deferred.stored, oldBound,
      `${scenario.name} must not rotate an old-bound active workout`);

    const preparedOnlyOld = initialStore(scenario.previous);
    preparedOnlyOld.active = null;
    const preparedDeferred = loadWithDurableStage(
      preparedOnlyOld,
      stagedTransition(scenario.repair)
    );
    assert.equal(preparedDeferred.deferred, true,
      `${scenario.name} must also wait for an old-bound prepared FIT transaction`);

    const preparedOnlyTarget = initialStore(scenario.previous);
    preparedOnlyTarget.active = null;
    preparedOnlyTarget.prepared.pairingGeneration = NEXT_GENERATION;
    const preparedRecovered = loadWithDurableStage(
      preparedOnlyTarget,
      stagedTransition(scenario.repair)
    );
    assert.equal(preparedRecovered.ok, true);
    assert.equal(preparedRecovered.stored.pairingGeneration, NEXT_GENERATION);
    assert.equal(preparedRecovered.stored.prepared.pairingGeneration, NEXT_GENERATION);

    for (let cut = 0; cut <= 3; cut += 1) {
      const beforeLoad = storeAtWriteCut(scenario.previous, cut);
      const result = loadWithDurableStage(beforeLoad, stagedTransition(scenario.repair));
      assert.equal(result.ok, true, `${scenario.name} cut ${cut} must load`);
      assert.equal(result.stageRetained, true, `${scenario.name} cut ${cut} keeps replay journal`);
      assert.equal(result.stored.pairingGeneration, NEXT_GENERATION);
      assert.equal(result.stored.active.pairingGeneration, NEXT_GENERATION);
      assert.equal(result.stored.prepared.pairingGeneration, NEXT_GENERATION);
      assert.equal(result.stored.active.workoutId, "active-workout");
      assert.deepEqual(result.stored.active.sets,
        [{ exerciseName: "Squat", weight: 100, reps: 5 }]);
      assert.deepEqual(result.stored.pending.map((item) => item.requestId),
        ["pending-1", "pending-2"]);
      assert.ok(result.stored.pending.every((item) =>
        item.pairingGeneration === NEXT_GENERATION));
      assert.equal(result.recovered, cut < 3,
        `${scenario.name} cut ${cut} recovery classification`);
      if (cut === 3) {
        assert.equal(result.recovered, false,
          `${scenario.name} power loss immediately after generation commit is complete`);
      }
    }
  }
});

test("account reset keeps the owner marker as the final commit boundary", () => {
  const resetAtCut = (cut) => {
    const stored = initialStore(OLD_GENERATION);
    // All reset payload values, including the new account key, are written before
    // either commit point. The old owner must keep that half-write unusable.
    stored.accountBinding = OTHER_OWNER;
    stored.active = null;
    stored.prepared = null;
    stored.pending = [];
    if (cut >= 1) stored.pairingGeneration = NEXT_GENERATION;
    if (cut >= 2) stored.stateOwnerBinding = OTHER_OWNER;
    return stored;
  };

  for (let cut = 0; cut <= 2; cut += 1) {
    const stored = resetAtCut(cut);
    const scoped = stored.accountBinding === stored.stateOwnerBinding;
    assert.equal(scoped, cut === 2,
      `reset cut ${cut} must be unavailable until the owner marker commits`);
    if (scoped) {
      assert.equal(stored.pairingGeneration, NEXT_GENERATION);
    } else {
      assert.equal(stored.active, null,
        "a half-written account reset cannot expose a workout to a retry");
    }
  }
});

test("compact exact reset replay preserves a post-commit workout", () => {
  const exactReplay = ({ bindingsMatch, workout }) => {
    if (!bindingsMatch) {
      return { action: "reapply", workout: null };
    }
    return { action: "duplicate", workout };
  };

  const newWorkout = {
    id: "after-reset",
    sets: [{ exerciseName: "Deadlift", weight: 120, reps: 3 }]
  };
  const committed = exactReplay({ bindingsMatch: true, workout: newWorkout });
  assert.equal(committed.action, "duplicate");
  assert.deepEqual(committed.workout, newWorkout,
    "a stale exact reset stage cannot erase work created after its commit");

  const incomplete = exactReplay({ bindingsMatch: false, workout: null });
  assert.equal(incomplete.action, "reapply");
  assert.equal(incomplete.workout, null,
    "an incomplete owner transition remains safe to complete exactly once");
});

test("pairing recovery rejects stale, destructive, cross-owner, and cross-device stages", () => {
  const base = initialStore(OLD_GENERATION);
  const validStage = stagedTransition(true);
  const rejectedStages = [
    { ...validStage, revision: 39 },
    { ...validStage, resetWorkout: true },
    { ...validStage, accountBinding: OTHER_OWNER },
    { ...validStage, deviceBinding: "another-device" },
    { ...validStage, repairPairing: false }
  ];

  for (const stage of rejectedStages) {
    const before = copy(base);
    const result = loadWithDurableStage(before, stage);
    assert.equal(result.ok, false);
    assert.deepEqual(result.stored, before, "a rejected stage must not mutate valid state");
  }

  const adoption = initialStore(null);
  const invalidRepairAdoption = loadWithDurableStage(adoption, stagedTransition(true));
  assert.equal(invalidRepairAdoption.ok, false);
  assert.deepEqual(invalidRepairAdoption.stored, adoption);

  const foreignPending = initialStore(OLD_GENERATION);
  foreignPending.active.pairingGeneration = NEXT_GENERATION;
  foreignPending.pending[0].accountBinding = OTHER_OWNER;
  const rejectedPending = loadWithDurableStage(foreignPending, validStage);
  assert.equal(rejectedPending.ok, false);
  assert.equal(rejectedPending.stored.pending[0].accountBinding, OTHER_OWNER);
});

test("failed recovery persistence keeps the stage and withholds the new generation", () => {
  for (const scenario of [
    { previous: null, repair: false },
    { previous: OLD_GENERATION, repair: true }
  ]) {
    const partiallyWritten = storeAtWriteCut(scenario.previous, 1);
    const result = loadWithDurableStage(
      partiallyWritten,
      stagedTransition(scenario.repair),
      { recoverySaveSucceeds: false }
    );

    assert.equal(result.ok, false);
    assert.equal(result.recoverySaveFailed, true);
    assert.equal(result.stageRetained, true);
    assert.equal(result.stored.pairingGeneration, scenario.previous);
    assert.equal(result.stored.prepared.pairingGeneration, scenario.previous);
    assert.ok(result.stored.pending.every((item) =>
      item.pairingGeneration === scenario.previous));
    assert.equal(result.stored.active.pairingGeneration, NEXT_GENERATION,
      "the already durable target-bound active transaction remains the recovery anchor");
    assert.notEqual(result.stored.pairingGeneration, NEXT_GENERATION,
      "an uncommitted generation must not authorize outbound pending messages");
  }
});
