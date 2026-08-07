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

test("muscle mapping identifiers use the shared Unicode character and byte limits", () => {
  const valid = validBackup();
  valid.mappings = { "custom carry": ["💪".repeat(32)] };
  assert.equal(
    contract.validateAndNormalize(valid).state.mappings["custom carry"][0],
    "💪".repeat(32)
  );

  for (const muscle of ["a".repeat(65), "💪".repeat(33)]) {
    const invalid = validBackup();
    invalid.mappings = { "custom carry": [muscle] };
    assert.throws(() => contract.validateAndNormalize(invalid), /supported length/);
  }
});

test("exercise machine load profiles are normalized and bounded", () => {
  const valid = validBackup();
  valid.exercises[0].loadProfile = {
    direction: "higherIsHarder",
    allowedWeightsKg: [0, 2.5, 5, 12.5, 69, 73]
  };
  assert.deepEqual(contract.validateAndNormalize(valid).state.exercises[0].loadProfile, {
    direction: "higherIsHarder",
    allowedWeightsKg: [0, 2.5, 5, 12.5, 69, 73]
  });

  const assisted = validBackup();
  assisted.exercises[0].loadProfile = {
    direction: "lowerIsHarder",
    allowedWeightsKg: [20, 25, 30, 35, 40, 45, 50]
  };
  assert.equal(contract.validateAndNormalize(assisted).state.exercises[0].loadProfile.direction, "lowerIsHarder");

  for (const loadProfile of [
    { direction: "unknown", allowedWeightsKg: [5] },
    { direction: "higherIsHarder", allowedWeightsKg: [] },
    { direction: "higherIsHarder", allowedWeightsKg: [5, 5] },
    { direction: "higherIsHarder", allowedWeightsKg: [10, 5] },
    { direction: "higherIsHarder", allowedWeightsKg: [-1, 5] },
    { direction: "higherIsHarder", allowedWeightsKg: [5, Infinity] },
    { direction: "higherIsHarder", allowedWeightsKg: Array.from({ length: contract.LIMITS.loadProfileWeights + 1 }, (_, index) => index) }
  ]) {
    const invalid = validBackup();
    invalid.exercises[0].loadProfile = loadProfile;
    assert.throws(() => contract.validateAndNormalize(invalid));
  }
});

test("portable exercise identity uses NFC, Unicode whitespace, apostrophe, and yo normalization", () => {
  const key = contract.portableExerciseNameKey;
  assert.equal(key("  МОЁ\u00a0УПРАЖНЕНИЕ\u2019  "), "мое упражнение'");
  assert.equal(key("Row\u001cMachine"), "row machine");
  assert.equal(key("Cafe\u0301\tRow"), key("Café Row"));
  assert.notEqual(key("Café Row"), key("Cafe Row"), "unrelated accents must remain distinct");

  const duplicateNames = validBackup();
  duplicateNames.exercises = [{ name: "Моё упражнение" }];
  duplicateNames.sessions[0].exercises = [
    { name: "Мое\u2003упражнение", sets: [{ weight: -0, reps: 8 }] },
    { name: "МОЁ УПРАЖНЕНИЕ", sets: [{ weight: 5, reps: 8 }] }
  ];
  const normalized = contract.validateAndNormalize(duplicateNames).state;
  assert.equal(normalized.sessions[0].exerciseNames.length, 1);
  assert.equal(Object.is(normalized.sessions[0].sets[0].weight, -0), false);
});

test("exercise names and mapping keys reject C0/C1 controls on normal import", () => {
  const mutations = [
    backup => { backup.exercises[0].name = "Bench\u0000Press"; },
    backup => { backup.sessions[0].exerciseNames = ["Bench\u001fPress"]; },
    backup => { backup.sessions[0].exercises[0].name = "Bench\u007fPress"; },
    backup => {
      backup.sessions[0].sets = [{ exerciseName: "Bench\u0085Press", weight: 20, reps: 8 }];
    },
    backup => { backup.mappings = { "Bench\u009fPress": ["chest"] }; }
  ];

  for (const mutate of mutations) {
    const backup = validBackup();
    mutate(backup);
    assert.throws(
      () => contract.validateAndNormalize(JSON.stringify(backup)),
      error => error.code === "unsupported_exercise_name"
    );
  }
});

test("local-only migration preserves legacy control names and removes stale catalog identity", () => {
  const backup = validBackup();
  backup.exercises = [{ id: 1, name: "Catalog\u0000Name", catalogKey: "bench_press" }];
  backup.sessions = [{
    id: 10,
    date: 1760000000000,
    note: "Legacy names",
    exerciseNames: ["Explicit\u001fName"],
    exercises: [{
      name: "Nested\u0085Name",
      catalogKey: "bench_press",
      sets: [{ id: 11, catalogKey: "bench_press", weight: 20, reps: 8 }]
    }]
  }];
  backup.mappings = { "Map\u007fName": ["chest"] };

  const result = contract.validateAndNormalize(JSON.stringify(backup), {
    migrateLegacyExerciseNameControls: true
  });
  assert.equal(result.migratedLegacyExerciseNameControls, true);
  assert.equal(result.state.exercises[0].name, contract.migrateLegacyExerciseNameControls("Catalog\u0000Name"));
  assert.equal(Object.hasOwn(result.state.exercises[0], "catalogKey"), false);
  assert.deepEqual(result.state.sessions[0].exerciseNames, [
    contract.migrateLegacyExerciseNameControls("Explicit\u001fName"),
    contract.migrateLegacyExerciseNameControls("Nested\u0085Name")
  ]);
  assert.equal(
    result.state.sessions[0].sets[0].exerciseName,
    contract.migrateLegacyExerciseNameControls("Nested\u0085Name")
  );
  assert.equal(Object.hasOwn(result.state.sessions[0].sets[0], "catalogKey"), false);
  assert.deepEqual(
    result.state.mappings[contract.migrateLegacyExerciseNameControls("Map\u007fName")],
    ["chest"]
  );
  assert.equal(
    contract.containsUnsupportedExerciseNameControls(JSON.stringify(result.state)),
    false
  );
  assert.notEqual(
    contract.migrateLegacyExerciseNameControls("A\u0000"),
    contract.migrateLegacyExerciseNameControls("A\u0001")
  );
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
  const astralBoundaryName = "😀".repeat(contract.LIMITS.exerciseName);
  portable.exercises = [{ name: astralBoundaryName }];
  portable.sessions[0].exercises[0].name = astralBoundaryName;
  delete portable.sessions[0].exercises[0].catalogKey;
  portable.mappings = { [astralBoundaryName]: ["chest"] };
  assert.doesNotThrow(() => contract.validateAndNormalize(portable));
  assert.equal(astralBoundaryName.length, contract.LIMITS.exerciseName * 2);
  assert.equal(contract.utf8ByteLength(astralBoundaryName), contract.LIMITS.exerciseNameBytes);
  assert.equal(contract.unicodeCodePointLengthAtMost(astralBoundaryName, contract.LIMITS.exerciseName), true);

  const oversizedName = validBackup();
  oversizedName.sessions[0].exercises[0].name = "😀".repeat(contract.LIMITS.exerciseName + 1);
  assert.throws(() => contract.validateAndNormalize(oversizedName));
  assert.equal(
    contract.unicodeCodePointLengthAtMost(
      "😀".repeat(contract.LIMITS.exerciseName + 1),
      contract.LIMITS.exerciseName
    ),
    false
  );

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
  assert.match(source, /session\.note \? [^\r\n]*escapeHtml\(session\.note\)/);
  assert.doesNotMatch(source, /document\.write\(/);
  assert.match(source, /window\.location\.replace\("\.\/confirmed\.html\?platform=web"\)/);
  assert.doesNotMatch(source, /window\.location\.hash\}`/);
  assert.match(index, /name="referrer" content="no-referrer"/);
  assert.match(index, /Content-Security-Policy/);
  assert.match(index, /script-src 'self'/);
});
