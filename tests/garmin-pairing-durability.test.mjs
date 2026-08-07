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

// save() writes the authoritative active snapshot first, pending later, and the
// standalone pairing generation after both. Each cut models power loss before
// the next write; the already durable phone stage is intentionally retained.
const storeAtWriteCut = (previousGeneration, cut) => {
  const stored = initialStore(previousGeneration);
  const writes = [
    () => { stored.active.pairingGeneration = NEXT_GENERATION; },
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
  const generationAllowed = (value) => value === stored.pairingGeneration ||
    (needsRecovery && value === target);
  const scopeAllowed = (value) => value.accountBinding === stored.accountBinding &&
    value.deviceBinding === stored.deviceBinding &&
    generationAllowed(value.pairingGeneration);
  if (!scopeAllowed(stored.active) || !stored.pending.every(scopeAllowed)) {
    return { ok: false, stored };
  }

  if (needsRecovery) {
    stored.pairingGeneration = target;
    stored.active.pairingGeneration = target;
    stored.pending.forEach((item) => { item.pairingGeneration = target; });
    if (!recoverySaveSucceeds) {
      stored.pairingGeneration = originalGeneration;
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

test("Garmin load journals same-owner pairing adoption and repair before restoring active state", () => {
  const load = functionSlice("load", "save");
  const recovery = functionSlice("stagedPairingRecoveryTarget", "loadSyncStage");
  const rotate = functionSlice("rotatePairingGenerationForPending", "queueWorkout");
  const applySync = functionSlice("applySyncFromSource", "applyValidatedSync");

  assert.ok(load.indexOf('loadSyncStage("phone")') <
    load.indexOf("stagedPairingRecoveryTarget()"));
  assert.ok(load.indexOf("stagedPairingRecoveryTarget()") <
    load.indexOf("isValidActiveWorkoutSnapshot(savedActiveWorkout)"));
  assert.match(load, /validActiveSnapshot[\s\S]*!snapshotMatches && recoveredPairing[\s\S]*pairingGeneration = previousPairingGeneration[\s\S]*activeWorkoutSnapshotMatchesBindings\(savedActiveWorkout\)[\s\S]*pairingGeneration = pairingRecoveryTarget/);
  assert.match(load, /pruneAccountScopedState\(\);[\s\S]*recoverQueuedWorkout\(\);[\s\S]*if \(recoveredPairing && !save\(\)\)[\s\S]*pairingGeneration = previousPairingGeneration[\s\S]*pending\[i\]\.put\("pairingGeneration", previousPairingGeneration\)[\s\S]*status = "SAVE FAIL"/);
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
  assert.doesNotMatch(storeSource, /adoptPairingGenerationForPending/);
});

test("every pairing write cut preserves active and pending workouts", () => {
  const cases = [
    { name: "adoption", previous: null, repair: false },
    { name: "repair", previous: OLD_GENERATION, repair: true }
  ];

  for (const scenario of cases) {
    for (let cut = 0; cut <= 3; cut += 1) {
      const beforeLoad = storeAtWriteCut(scenario.previous, cut);
      const result = loadWithDurableStage(beforeLoad, stagedTransition(scenario.repair));
      assert.equal(result.ok, true, `${scenario.name} cut ${cut} must load`);
      assert.equal(result.stageRetained, true, `${scenario.name} cut ${cut} keeps replay journal`);
      assert.equal(result.stored.pairingGeneration, NEXT_GENERATION);
      assert.equal(result.stored.active.pairingGeneration, NEXT_GENERATION);
      assert.equal(result.stored.active.workoutId, "active-workout");
      assert.deepEqual(result.stored.active.sets,
        [{ exerciseName: "Squat", weight: 100, reps: 5 }]);
      assert.deepEqual(result.stored.pending.map((item) => item.requestId),
        ["pending-1", "pending-2"]);
      assert.ok(result.stored.pending.every((item) =>
        item.pairingGeneration === NEXT_GENERATION));
      assert.equal(result.recovered, cut < 3,
        `${scenario.name} cut ${cut} recovery classification`);
    }
  }
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
    assert.ok(result.stored.pending.every((item) =>
      item.pairingGeneration === scenario.previous));
    assert.notEqual(result.stored.pairingGeneration, NEXT_GENERATION,
      "an uncommitted generation must not authorize outbound pending messages");
  }
});
