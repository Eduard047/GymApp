import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");
const stateContractSource = await readFile("pwa/state-contract.js", "utf8");

function loadPwaContext() {
  const values = new Map();
  const context = {
    console,
    Date,
    Map,
    Set,
    TextEncoder,
    URLSearchParams,
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {},
      GymProgressionRules: {
        sessionXP: () => 100,
        MAX_SUPPORTED_XP: 2147483647,
        requirementForLevel: () => 100,
        cumulativeXPForLevel: () => 0,
        levelProgress: value => ({ level: 1, currentLevelXp: Number(value || 0), xpForNextLevel: 100, progressFraction: 0 })
      }
    },
    document: {
      documentElement: { lang: "en" },
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: {},
    localStorage: {
      getItem: key => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, String(value)),
      removeItem: key => values.delete(key)
    },
    requestAnimationFrame: callback => callback(),
    clearTimeout,
    setTimeout,
    clearInterval,
    setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests"))
  };
  context.window.document = context.document;
  context.window.navigator = context.navigator;
  context.window.localStorage = context.localStorage;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(appSource, context);
  return context;
}

function jsonFrom(context, expression) {
  return JSON.parse(vm.runInContext(`JSON.stringify(${expression})`, context));
}

test("built-in exercise catalog persists stable keys and localizes only display names", () => {
  const context = loadPwaContext();
  const defaults = jsonFrom(context, "defaultAppState().exercises");

  assert.equal(defaults.length, 51);
  assert.deepEqual(defaults[0], { id: 1, name: "Bench Press", catalogKey: "bench_press" });
  assert.equal(vm.runInContext('exerciseDisplayName(defaultAppState().exercises[0], "uk")', context), "Жим штанги лежачи");
  assert.equal(vm.runInContext('exerciseDisplayName({ name: "My custom press" }, "uk")', context), "My custom press");
});

test("catalog seeding runs once and preserves later user deletions", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = normalizeImportedState({
    language: "en",
    exercises: [{ id: 900, name: "My custom exercise" }],
    sessions: [],
    mappings: {},
    profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
  }, defaultAppState())`, context);

  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 0);
  assert.equal(vm.runInContext("ensureBuiltInExerciseCatalog(state)", context), true);
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 1);
  assert.equal(vm.runInContext("state.exercises.length", context), 52);

  vm.runInContext(`state.exercises = state.exercises.filter(
    exercise => exercise.catalogKey !== "bench_press"
  )`, context);
  assert.equal(vm.runInContext("ensureBuiltInExerciseCatalog(state)", context), false);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "bench_press")',
    context
  ), false);

  const exported = jsonFrom(context, "JSON.parse(exportPayload(false))");
  assert.equal(exported.catalogSeedVersion, 1);
});

test("legacy aliases localize without collapsing or rewriting separate catalog rows", () => {
  const context = loadPwaContext();
  const normalized = jsonFrom(context, `normalizeExerciseCatalog([
    { id: 7, name: "Жим штанги лежачи" },
    { id: 8, name: "Bench Press" },
    { id: 9, name: "Моя вправа" },
    { id: 10, name: "Bench Press", catalogKey: "bench_press" }
  ])`);

  assert.deepEqual(normalized, [
    { id: 7, name: "Жим штанги лежачи" },
    { id: 8, name: "Bench Press" },
    { id: 9, name: "Моя вправа" },
    { id: 10, name: "Bench Press", catalogKey: "bench_press" }
  ]);
  assert.notEqual(
    vm.runInContext('exerciseMatchKey({ name: "Bench Press" })', context),
    vm.runInContext('exerciseMatchKey({ name: "Жим штанги лежачи" })', context)
  );
  assert.equal(vm.runInContext('exerciseDisplayName({ name: "Жим штанги лежачи" }, "en")', context), "Bench Press");
  assert.equal(vm.runInContext('exerciseMatchesSearch({ name: "Bench Press", catalogKey: "bench_press" }, "штанги", "uk")', context), true);
  assert.equal(vm.runInContext('exerciseCatalogKey("Barbell Squat")', context), "squat");
  assert.equal(vm.runInContext('exerciseCatalogKey("Присід зі штангою")', context), "squat");
  assert.equal(vm.runInContext('exerciseCatalogKey("Жим сидячи над головою")', context), "shoulder_press");
});

test("recognized raw name wins over a conflicting imported catalog key", () => {
  const context = loadPwaContext();
  const normalized = jsonFrom(context, `normalizeExerciseCatalog([
    { id: 1, name: "Bench Press", catalogKey: "squat" },
    { id: 2, name: "My custom bench label", catalogKey: "bench_press" },
    { id: 3, name: "Планка", catalogKey: "not_a_real_key" }
  ])`);

  assert.deepEqual(normalized, [
    { id: 1, name: "Bench Press", catalogKey: "bench_press" },
    { id: 2, name: "My custom bench label", catalogKey: "bench_press" },
    { id: 3, name: "Планка" }
  ]);
  assert.equal(
    vm.runInContext('exerciseDisplayName({ name: "Bench Press", catalogKey: "squat" }, "en")', context),
    "Bench Press"
  );
});

test("an explicit empty remote catalog remains empty and is not replaced by defaults", () => {
  const context = loadPwaContext();

  assert.equal(vm.runInContext("normalizeImportedState({ exercises: [], sessions: [] }, defaultAppState()).exercises.length", context), 0);
  assert.equal(vm.runInContext("normalizeImportedState({ sessions: [] }, defaultAppState()).exercises.length", context), 51);
});

test("legacy session aliases preserve separate raw history", () => {
  const context = loadPwaContext();
  const session = jsonFrom(context, `normalizeSessions([{
    id: 1,
    startedAt: 1,
    exerciseNames: ["Bench Press", "Жим штанги лежачи"],
    sets: [
      { id: 2, exerciseName: "Bench Press", weight: 50, reps: 8 },
      { id: 3, exerciseName: "Жим штанги лежачи", weight: 55, reps: 6 }
    ]
  }])[0]`);

  assert.deepEqual(session.exerciseNames, ["Bench Press", "Жим штанги лежачи"]);
  assert.deepEqual(session.sets.map(set => set.exerciseName), ["Bench Press", "Жим штанги лежачи"]);
  assert.equal("catalogKey" in session.sets[0], false);
  assert.equal("catalogKey" in session.sets[1], false);
});

test("nested session blocks propagate an allowlisted catalog key without rewriting history", () => {
  const context = loadPwaContext();
  const session = jsonFrom(context, `normalizeSessions([{
    id: 1,
    startedAt: 1,
    exercises: [{
      name: "My bench label",
      catalogKey: "bench_press",
      sets: [{ id: 2, weight: 50, reps: 8 }]
    }, {
      name: "Bench Press",
      catalogKey: "squat",
      sets: [{ id: 3, weight: 60, reps: 5 }]
    }]
  }])[0]`);

  assert.deepEqual(session.sets, [
    { id: 2, exerciseName: "My bench label", catalogKey: "bench_press", weight: 50, reps: 8, orderIndex: 0 },
    { id: 3, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 60, reps: 5, orderIndex: 1 }
  ]);
});

test("schema-v2 export keeps nested catalog keys and round-trips sets once", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = {
    ...defaultAppState(),
    exercises: [
      { id: 1, name: "Bench Press", catalogKey: "bench_press" },
      { id: 2, name: "Жим штанги лежачи" }
    ],
    sessions: [{
      id: 10,
      startedAt: 20,
      note: "",
      exerciseNames: ["Bench Press", "Жим штанги лежачи"],
      sets: [
        { id: 11, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 50, reps: 8, orderIndex: 0 },
        { id: 12, exerciseName: "Жим штанги лежачи", weight: 55, reps: 6, orderIndex: 0 }
      ]
    }]
  }`, context);

  const exported = jsonFrom(context, "JSON.parse(exportPayload(false))");
  assert.deepEqual(exported.sessions[0].exercises, [
    {
      name: "Bench Press",
      catalogKey: "bench_press",
      sets: [{ id: 11, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 50, reps: 8, orderIndex: 0 }]
    },
    {
      name: "Жим штанги лежачи",
      sets: [{ id: 12, exerciseName: "Жим штанги лежачи", weight: 55, reps: 6, orderIndex: 0 }]
    }
  ]);

  const roundTripped = jsonFrom(context, "normalizeSessions(JSON.parse(exportPayload(false)).sessions)[0]");
  assert.equal(roundTripped.sets.length, 2);
  assert.deepEqual(roundTripped.sets.map(set => set.exerciseName), ["Bench Press", "Жим штанги лежачи"]);
  assert.equal(roundTripped.sets[0].catalogKey, "bench_press");
  assert.equal("catalogKey" in roundTripped.sets[1], false);
});

test("PWA diagnostics are aggregate-only and cannot expose backup content", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = { id: "private-local", name: "Private Owner", email: "owner@example.test" };
    state = {
      ...defaultAppState(),
      exercises: [{ id: 1, name: "Secret Exercise" }],
      sessions: [{
        id: 10,
        startedAt: 20,
        note: "Private medical note",
        exerciseNames: ["Secret Exercise"],
        sets: [{ id: 11, exerciseName: "Secret Exercise", weight: 50, reps: 8, orderIndex: 0 }]
      }]
    };
  `, context);

  const diagnostics = jsonFrom(context, "JSON.parse(exportPayload(true))");
  assert.equal(diagnostics.diagnostics, true);
  assert.deepEqual(diagnostics.summary, { exerciseCount: 1, sessionCount: 1, setCount: 1 });
  for (const privateField of ["owner", "exercises", "sessions", "mappings", "profile"]) {
    assert.equal(privateField in diagnostics, false, privateField);
  }
  const serialized = JSON.stringify(diagnostics);
  assert.doesNotMatch(serialized, /Private Owner|owner@example|Secret Exercise|medical note/);
});

test("local mutation commits enforce numeric bounds and preserve epoch-zero timestamps", () => {
  const context = loadPwaContext();
  assert.equal(
    vm.runInContext("normalizeSessions([{ id: 1, startedAt: 0, note: '', sets: [] }])[0].startedAt", context),
    0
  );
  assert.throws(() => vm.runInContext(`
    state = defaultAppState();
    state.sessions = [{
      id: 1,
      startedAt: 20,
      note: "",
      sets: [{ id: 2, exerciseName: "Bench Press", weight: Infinity, reps: 8, orderIndex: 0 }]
    }];
    saveState({ queueRemote: false });
  `, context), /finite number/);
});

test("malformed backup entries reject the whole temporary import state", () => {
  const context = loadPwaContext();
  assert.throws(() => vm.runInContext(`normalizeImportedState({
      exercises: [null, 42, { id: 3, name: "Планка", catalogKey: "invalid" }],
      sessions: []
    }, defaultAppState())`, context), /must be a string|must be an object/);
});

test("detail, summary, and progress UI use a set catalog key for localized display and history", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = {
    ...defaultAppState(),
    language: "uk",
    progressExerciseId: 1,
    exercises: [{ id: 1, name: "My bench label", catalogKey: "bench_press" }],
    sessions: [{
      id: 10,
      startedAt: Date.now(),
      note: "",
      exerciseNames: ["My bench label"],
      sets: [{ id: 11, exerciseName: "My bench label", catalogKey: "bench_press", weight: 50, reps: 8, orderIndex: 0 }]
    }]
  }`, context);

  for (const markup of [
    vm.runInContext("detailScreen(10)", context),
    vm.runInContext("summaryScreen(10)", context),
    vm.runInContext("progressScreen()", context)
  ]) {
    assert.match(markup, /Жим штанги лежачи/);
  }
  assert.equal(
    vm.runInContext("allSets().filter(set => exercisesMatch(set, state.exercises[0])).length", context),
    1
  );
});

test("saving an untouched localized rename keeps a legacy raw alias and identity", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    state = {
      ...defaultAppState(),
      language: "en",
      exercises: [{ id: 1, name: "Barbell Squat" }],
      sessions: []
    };
    document.querySelector = selector => selector === "#rename-name"
      ? { value: "Squat" }
      : { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
    applyRename(1);
  `, context);

  assert.deepEqual(jsonFrom(context, "state.exercises"), [{ id: 1, name: "Barbell Squat" }]);
  assert.equal(vm.runInContext('exerciseMatchKey(state.exercises[0])', context), "custom:barbell squat");
});

test("logging a legacy alias reuses its exact catalog row instead of creating a duplicate", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = {
    ...defaultAppState(),
    exercises: [{ id: 7, name: "Barbell Squat" }],
    sessions: []
  }`, context);

  assert.equal(vm.runInContext('ensureExercise("Barbell Squat").id', context), 7);
  assert.deepEqual(jsonFrom(context, "state.exercises"), [{ id: 7, name: "Barbell Squat" }]);
});

test("adding another language alias reuses the existing built-in row", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = {
    ...defaultAppState(),
    exercises: [{ id: 7, name: "Присідання зі штангою" }],
    sessions: []
  }`, context);

  assert.equal(vm.runInContext('ensureExercise("Squat").id', context), 7);
  assert.equal(vm.runInContext("state.exercises.length", context), 1);
});
