import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contract = JSON.parse(await readFile(
  "shared/activity-only-sync-v1.json",
  "utf8"
));

function exact(value) {
  return JSON.stringify(value);
}

function materialize(names) {
  return names.map(name => {
    assert.ok(Object.hasOwn(contract.items, name), `Unknown fixture item: ${name}`);
    return structuredClone(contract.items[name]);
  });
}

function mapByIdentity(items) {
  const result = new Map();
  for (const item of items) {
    const key = item[contract.identityField];
    assert.equal(Number.isSafeInteger(key), true);
    assert.equal(result.has(key), false, `Duplicate identity: ${key}`);
    result.set(key, item);
  }
  return result;
}

function referenceThreeWayMerge(baseItems, localItems, remoteItems) {
  const base = mapByIdentity(baseItems);
  const local = mapByIdentity(localItems);
  const remote = mapByIdentity(remoteItems);
  const keys = [...new Set([...base.keys(), ...local.keys(), ...remote.keys()])]
    .sort((left, right) => left - right);
  const result = [];

  for (const key of keys) {
    const baseItem = base.get(key);
    const localItem = local.get(key);
    const remoteItem = remote.get(key);
    const baseExists = baseItem !== undefined;
    const localExists = localItem !== undefined;
    const remoteExists = remoteItem !== undefined;

    if (!baseExists) {
      if (!localExists) result.push(remoteItem);
      else if (!remoteExists) result.push(localItem);
      else if (exact(localItem) === exact(remoteItem)) result.push(localItem);
      else throw new Error("Activity-only concurrent addition conflict.");
      continue;
    }

    if (!localExists && !remoteExists) continue;
    if (!localExists) {
      if (exact(remoteItem) === exact(baseItem)) continue;
      throw new Error("Activity-only delete-versus-edit conflict.");
    }
    if (!remoteExists) {
      if (exact(localItem) === exact(baseItem)) continue;
      throw new Error("Activity-only edit-versus-delete conflict.");
    }
    if (exact(localItem) === exact(remoteItem)) result.push(localItem);
    else if (exact(localItem) === exact(baseItem)) result.push(remoteItem);
    else if (exact(remoteItem) === exact(baseItem)) result.push(localItem);
    else throw new Error("Activity-only divergent edit conflict.");
  }

  assert.ok(result.length <= contract.maximumItems);
  return result;
}

test("activity-only merge contract is exact, bounded and owner-safe", () => {
  assert.equal(contract.schemaVersion, 1);
  assert.equal(contract.identityField, "workoutStartedAt");
  assert.equal(contract.maximumItems, 5000);
  assert.deepEqual(contract.wireContract.optionalFields, [
    "garminCalories",
    "averageHeartRate",
    "maximumHeartRate",
    "endingHeartRateZone",
    "note"
  ]);
  assert.equal(contract.wireContract.absentOptionalFieldsAreDistinctFromZero, true);
  assert.equal(contract.stateContract.baselineIsOwnerBound, true);
  assert.equal(contract.stateContract.baselineRetainsExactItems, true);
  assert.equal(contract.stateContract.pendingRequestReplaysBeforeRemoteMaterialization, true);
  assert.equal(contract.stateContract.deleteVersusEditFailsClosed, true);
  assert.notDeepEqual(contract.items.cExact, contract.items.cZero);
  assert.equal(Object.hasOwn(contract.items.cExact, "garminCalories"), false);
  assert.equal(contract.items.cZero.garminCalories, 0);
});

test("every golden three-way scenario matches the shared result", () => {
  const names = new Set();
  for (const scenario of contract.mergeScenarios) {
    assert.equal(names.has(scenario.name), false, `Duplicate scenario: ${scenario.name}`);
    names.add(scenario.name);
    const run = () => referenceThreeWayMerge(
      materialize(scenario.base),
      materialize(scenario.local),
      materialize(scenario.remote)
    );
    if (scenario.conflict) {
      assert.throws(run, /conflict/i, scenario.name);
    } else {
      assert.deepEqual(run(), materialize(scenario.result), scenario.name);
    }
  }
  assert.ok(names.size >= 15);
});
