import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contract = JSON.parse(await readFile("shared/workout-sync-merge-v1.json", "utf8"));

function sortedKeys(value) {
  if (Array.isArray(value)) return value.map(sortedKeys);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortedKeys(value[key])]));
  }
  return value;
}

function exact(value) {
  return JSON.stringify(sortedKeys(value));
}

function sessionIdentity(session) {
  const key = session.date ?? session.startedAt;
  assert.equal(Number.isSafeInteger(key), true, "A workout needs an integer start time.");
  return key;
}

function exerciseIdentity(exercise) {
  const name = exercise.name.trim().replace(/\s+/gu, " ").toLowerCase();
  return `${name}|${exercise.catalogKey ?? ""}`;
}

function materialize(side, kind) {
  const names = side?.[kind] ?? [];
  const fixtures = kind === "sessions" ? contract.sessions : contract.exercises;
  return names.map(name => {
    assert.ok(Object.hasOwn(fixtures, name), `Unknown ${kind} fixture: ${name}`);
    return structuredClone(fixtures[name]);
  });
}

function byIdentity(items, identity) {
  const result = new Map();
  for (const item of items) {
    const key = identity(item);
    if (result.has(key)) throw new Error(`Duplicate identity: ${key}`);
    result.set(key, item);
  }
  return result;
}

/// Three-way merge of one collection. `resolveConflict(key, local, remote)`
/// decides divergent changes; `undefined` means "absent".
function threeWay(baseItems, localItems, remoteItems, identity, resolveConflict) {
  const base = byIdentity(baseItems, identity);
  const local = byIdentity(localItems, identity);
  const remote = byIdentity(remoteItems, identity);
  const keys = [...new Set([...base.keys(), ...local.keys(), ...remote.keys()])];
  const result = new Map();
  for (const key of keys) {
    const baseItem = base.get(key);
    const localItem = local.get(key);
    const remoteItem = remote.get(key);
    const same = (left, right) => (left === undefined && right === undefined) ||
      (left !== undefined && right !== undefined && exact(left) === exact(right));
    let chosen;
    if (same(localItem, remoteItem)) chosen = localItem;
    else if (same(localItem, baseItem)) chosen = remoteItem;
    else if (same(remoteItem, baseItem)) chosen = localItem;
    else chosen = resolveConflict(key, localItem, remoteItem);
    if (chosen !== undefined) result.set(key, chosen);
  }
  return result;
}

function referenceMerge(scenario) {
  const remoteRowUpdatedAt = contract.times.remoteRowUpdatedAt;
  const localChangedAt = new Map(Object.entries(scenario.localChangedAt ?? {}).map(([fixture, time]) => {
    assert.ok(Object.hasOwn(contract.sessions, fixture), `Unknown change-time fixture: ${fixture}`);
    assert.ok(Object.hasOwn(contract.times, time), `Unknown time: ${time}`);
    return [sessionIdentity(contract.sessions[fixture]), contract.times[time]];
  }));
  const sessions = threeWay(
    materialize(scenario.base, "sessions"),
    materialize(scenario.local, "sessions"),
    materialize(scenario.remote, "sessions"),
    sessionIdentity,
    (key, local, remote) => {
      const localTime = localChangedAt.get(key);
      return localTime !== undefined && localTime > remoteRowUpdatedAt ? local : remote;
    }
  );
  const exercises = threeWay(
    materialize(scenario.base, "exercises"),
    materialize(scenario.local, "exercises"),
    materialize(scenario.remote, "exercises"),
    exerciseIdentity,
    () => assert.fail("Custom exercises only appear or disappear; they cannot diverge.")
  );
  // A workout that survives the merge keeps every custom exercise it uses.
  const known = [...materialize(scenario.local, "exercises"), ...materialize(scenario.remote, "exercises")];
  for (const session of sessions.values()) {
    for (const block of session.exercises ?? []) {
      if (block.catalogKey) continue;
      const key = exerciseIdentity(block);
      if (exercises.has(key)) continue;
      const entry = known.find(exercise => exerciseIdentity(exercise) === key) ?? { name: block.name };
      exercises.set(key, entry);
    }
  }
  return {
    sessions: [...sessions.values()].sort((left, right) => sessionIdentity(left) - sessionIdentity(right)),
    exercises: [...exercises.values()].sort((left, right) => exerciseIdentity(left).localeCompare(exerciseIdentity(right)))
  };
}

test("workout merge contract fixtures are well formed", () => {
  assert.equal(contract.schemaVersion, 1);
  assert.equal(contract.identity.session, "date");
  assert.equal(contract.newerWins.tie, "remote");
  assert.equal(contract.newerWins.missingLocalChangeTime, "remote");
  assert.equal(contract.stateContract.compatibilityRowUnchanged, true);
  for (const [name, session] of Object.entries(contract.sessions)) {
    assert.deepEqual(Object.keys(session).filter(key => !["date", "note", "exercises"].includes(key)), [], name);
    sessionIdentity(session);
    for (const block of session.exercises) {
      assert.equal(typeof block.name, "string", name);
      assert.ok(block.sets.length > 0, name);
      for (const set of block.sets) {
        assert.equal(Number.isFinite(set.weight) && set.weight >= 0, true, name);
        assert.equal(Number.isSafeInteger(set.reps) && set.reps > 0, true, name);
      }
    }
  }
  assert.ok(contract.times.localNewer > contract.times.remoteRowUpdatedAt);
  assert.ok(contract.times.localOlder < contract.times.remoteRowUpdatedAt);
});

test("every merge scenario matches the reference three-way merge", () => {
  assert.ok(contract.mergeScenarios.length >= 20);
  for (const scenario of contract.mergeScenarios) {
    const merged = referenceMerge(scenario);
    assert.deepEqual(
      merged.sessions.map(exact),
      materialize(scenario.result, "sessions").map(exact),
      scenario.name
    );
    assert.deepEqual(
      merged.exercises.map(exact),
      materialize(scenario.result, "exercises")
        .sort((left, right) => exerciseIdentity(left).localeCompare(exerciseIdentity(right)))
        .map(exact),
      scenario.name
    );
  }
});

test("duplicate start times on one side fail closed", () => {
  for (const scenario of contract.failClosedScenarios) {
    assert.throws(() => referenceMerge(scenario), /Duplicate identity/, scenario.name);
  }
});

test("the headline case keeps edits of different workouts from both devices", () => {
  const scenario = contract.mergeScenarios.find(item => item.name.startsWith("edits of different workouts"));
  const merged = referenceMerge(scenario);
  assert.deepEqual(merged.sessions.map(exact), [contract.sessions.aLocalEdit, contract.sessions.bRemoteEdit].map(exact));
});
