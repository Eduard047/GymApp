import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const contract = require("../pwa/state-contract.js");

function validBackup() {
  return {
    schemaVersion: 2,
    owner: { accountId: "local-a", userId: null, email: null, remote: false },
    language: "uk",
    exercises: [{ id: 1, name: "Bench Press", catalogKey: "bench_press" }],
    sessions: [{
      id: 10,
      date: 1760000000000,
      note: "Push day",
      exercises: [{
        name: "Bench Press",
        catalogKey: "bench_press",
        sets: [{ id: 11, weight: 80.5, reps: 8 }]
      }]
    }],
    mappings: { "bench press": ["chest", "triceps"] },
    profile: { split: "Upper / Lower", days: 4, goal: "Strength", calories: "Maintenance" }
  };
}

test("the state boundary accepts and normalizes a legitimate schema-v2 backup", () => {
  const result = contract.validateAndNormalize(JSON.stringify(validBackup()), {
    fallback: { profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" } }
  });

  assert.equal(result.owner.accountId, "local-a");
  assert.equal(result.state.language, "uk");
  assert.deepEqual(result.state.profile, {
    split: "Upper / Lower",
    days: 4,
    goal: "Strength",
    calories: "Maintenance"
  });
  assert.equal(result.state.sessions.length, 1);
  assert.equal(Object.getPrototypeOf(result.state.mappings), null);
  assert.deepEqual(result.state.sessions[0].sets[0], {
    id: 11,
    exerciseName: "Bench Press",
    catalogKey: "bench_press",
    weight: 80.5,
    reps: 8,
    orderIndex: 0
  });
});

test("exercise favorites are bounded booleans with a backward-compatible alias", () => {
  const canonical = validBackup();
  canonical.exercises[0].favorite = true;
  assert.equal(contract.validateAndNormalize(canonical).state.exercises[0].favorite, true);

  const legacy = validBackup();
  legacy.exercises[0].isFavorite = true;
  assert.deepEqual(contract.validateAndNormalize(legacy).state.exercises[0], {
    id: 1,
    name: "Bench Press",
    catalogKey: "bench_press",
    favorite: true
  });

  for (const favorite of ["true", 1, null, {}, []]) {
    const invalid = validBackup();
    invalid.exercises[0].favorite = favorite;
    assert.throws(() => contract.validateAndNormalize(invalid), /favorite must be a boolean/);
  }

  const conflicting = validBackup();
  conflicting.exercises[0].favorite = true;
  conflicting.exercises[0].isFavorite = false;
  assert.throws(() => contract.validateAndNormalize(conflicting), /conflicting favorite values/);
});

test("profile enums never return an attacker-controlled fallback string", () => {
  const backup = validBackup();
  backup.profile = {
    split: "<img src=x onerror=alert(1)>",
    days: 999,
    goal: "javascript:alert(1)",
    calories: "\" onmouseover=alert(1)"
  };
  const result = contract.validateAndNormalize(backup, {
    fallback: { profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" } }
  });
  assert.deepEqual(result.state.profile, {
    split: "Push Pull Legs",
    days: 4,
    goal: "Balanced",
    calories: "Maintenance"
  });
});

test("oversized, deeply nested, and over-count backups fail before commit", () => {
  const oversized = `{"padding":"${"x".repeat(contract.LIMITS.rawBytes)}"}`;
  assert.throws(
    () => contract.validateAndNormalize(oversized),
    error => error.code === "state_too_large"
  );

  let deep = "value";
  for (let index = 0; index < contract.LIMITS.maxDepth + 2; index += 1) deep = { child: deep };
  assert.throws(
    () => contract.validateAndNormalize(deep),
    error => error.code === "state_too_deep"
  );

  const oversizedUnknownString = validBackup();
  oversizedUnknownString.unknown = "x".repeat(contract.LIMITS.jsonStringBytes + 1);
  assert.throws(
    () => contract.validateAndNormalize(oversizedUnknownString),
    error => error.code === "state_too_complex"
  );

  const tooManyExercises = validBackup();
  tooManyExercises.exercises = Array.from({ length: contract.LIMITS.exercises + 1 }, (_, index) => ({ name: `Exercise ${index}` }));
  assert.throws(
    () => contract.validateAndNormalize(tooManyExercises),
    error => error.code === "too_many_exercises"
  );

  const tooManySessions = validBackup();
  tooManySessions.sessions = Array.from({ length: contract.LIMITS.sessions + 1 }, () => ({}));
  assert.throws(
    () => contract.validateAndNormalize(tooManySessions),
    error => error.code === "too_many_sessions"
  );

  const tooManyDistinct = validBackup();
  tooManyDistinct.exercises = [
    { name: "Bench Press" },
    ...Array.from({ length: contract.LIMITS.exercises - 1 }, (_, index) => ({ name: `Catalog ${index}` }))
  ];
  tooManyDistinct.sessions[0].exercises[0].name = "One extra exercise";
  assert.throws(
    () => contract.validateAndNormalize(tooManyDistinct),
    error => error.code === "too_many_exercises"
  );
});

test("portable metadata and legacy Supabase owner markers are validated", () => {
  const legacyOwner = validBackup();
  legacyOwner.exportedAt = 1760000000000;
  legacyOwner.owner.remote = "supabase";
  assert.equal(contract.validateAndNormalize(legacyOwner).owner.remote, "supabase");

  for (const mutate of [
    backup => { backup.exportedAt = contract.LIMITS.timestampMax + 1; },
    backup => { backup.diagnostics = "yes"; },
    backup => { backup.language = "unknown"; },
    backup => { backup.owner.remote = "attacker-controlled"; },
    backup => { backup.exercises = { length: 1 }; },
    backup => { delete backup.exercises; backup.exerciseCatalog = { 0: "Bench Press" }; }
  ]) {
    const backup = validBackup();
    mutate(backup);
    assert.throws(() => contract.validateAndNormalize(backup));
  }
});

test("set type, finiteness, range, per-exercise, and total budgets are enforced", () => {
  for (const invalidSet of [
    { weight: Infinity, reps: 8 },
    { weight: -1, reps: 8 },
    { weight: 1000001, reps: 8 },
    { weight: 20, reps: 1.5 },
    { weight: 20, reps: 10001 }
  ]) {
    const backup = validBackup();
    backup.sessions[0].exercises[0].sets = [invalidSet];
    assert.throws(() => contract.validateAndNormalize(backup));
  }

  const perExercise = validBackup();
  perExercise.sessions[0].exercises[0].sets = Array.from(
    { length: contract.LIMITS.setsPerExercise + 1 },
    () => ({ weight: 20, reps: 8 })
  );
  assert.throws(
    () => contract.validateAndNormalize(perExercise),
    error => error.code === "too_many_sets"
  );

  const sets = Array.from({ length: 100 }, () => ({ weight: 1, reps: 1 }));
  const exercises = Array.from({ length: 100 }, (_, index) => ({ name: `Exercise ${index}`, sets }));
  const totalBudget = validBackup();
  totalBudget.exercises = [];
  totalBudget.sessions = Array.from({ length: 11 }, (_, index) => ({
    id: index + 1,
    startedAt: 1760000000000 + index,
    exercises
  }));
  assert.throws(
    () => contract.validateAndNormalize(totalBudget),
    error => error.code === "too_many_sets"
  );
});

test("portable timestamp and UTF-8 text boundaries match the native clients", () => {
  const portable = validBackup();
  portable.sessions[0].date = contract.LIMITS.timestampMin;
  portable.sessions[0].note = "Ж".repeat(contract.LIMITS.note);
  portable.sessions[0].exercises[0].name = "Ж".repeat(contract.LIMITS.exerciseName);
  assert.doesNotThrow(() => contract.validateAndNormalize(portable));

  const oversizedName = validBackup();
  oversizedName.sessions[0].exercises[0].name = "😀".repeat(contract.LIMITS.exerciseName + 1);
  assert.throws(() => contract.validateAndNormalize(oversizedName));

  const oversizedNote = validBackup();
  oversizedNote.sessions[0].note = "😀".repeat(contract.LIMITS.note + 1);
  assert.throws(() => contract.validateAndNormalize(oversizedNote));

  const unsupportedTimestamp = validBackup();
  unsupportedTimestamp.sessions[0].date = contract.LIMITS.timestampMax + 1;
  assert.throws(() => contract.validateAndNormalize(unsupportedTimestamp));
});

test("recommendation content is hydrated with textContent and profile labels fail safe", async () => {
  const [source, index] = await Promise.all([
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8")
  ]);
  assert.match(source, /field\.textContent = recommendation\[field\.dataset\.recommendationField\]/);
  assert.doesNotMatch(source, /\$\{rec\.(?:title|supporting|priority)\}/);
  assert.match(source, /\}\[value\] \|\| tx\("Unknown", "Невідомо"\)/);
  assert.match(source, /const nextState = imported\.state;/);
  assert.match(source, /preserveExerciseFavorites\(nextState, state\);/);
  assert.match(source, /if \(imported\.diagnostics\)/);
  assert.match(source, /activeAccount\.remote === "supabase" &&\s*cloudStateRecovery\?\.userId === activeAccount\.userId/);
  assert.match(source, /session\.note \? escapeHtml\(session\.note\)/);
  assert.doesNotMatch(source, /document\.write\(/);
  assert.match(source, /window\.location\.replace\("\.\/confirmed\.html\?platform=web"\)/);
  assert.doesNotMatch(source, /window\.location\.hash\}`/);
  assert.match(index, /name="referrer" content="no-referrer"/);
  assert.match(index, /Content-Security-Policy/);
  assert.match(index, /script-src 'self'/);
});
