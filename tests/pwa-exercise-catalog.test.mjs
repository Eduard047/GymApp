import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");
const stateContractSource = await readFile("pwa/state-contract.js", "utf8");
const russianTextSource = await readFile("pwa/russian-text.js", "utf8");

function loadPwaContext({ userAgent = "" } = {}) {
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
    navigator: { userAgent },
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
  vm.runInContext(russianTextSource, context);
  vm.runInContext(appSource, context);
  return context;
}

function jsonFrom(context, expression) {
  return JSON.parse(vm.runInContext(`JSON.stringify(${expression})`, context));
}

test("Garmin store link opens our public listing and isolates the new tab", () => {
  const context = loadPwaContext();
  const html = vm.runInContext("accountPanel()", context);

  assert.equal(
    html.includes(
      'href="https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f"'
    ),
    true
  );
  assert.equal(html.includes('target="_blank" rel="noopener noreferrer"'), true);
  assert.equal(html.includes(".iq"), false);
});

test("Android web link opens Connect IQ and falls back to its Google Play listing", () => {
  const context = loadPwaContext({ userAgent: "Mozilla/5.0 (Linux; Android 16) Chrome/140" });
  const html = vm.runInContext("accountPanel()", context);

  assert.equal(
    html.includes(
      'href="intent://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f#Intent;'
    ),
    true
  );
  assert.equal(html.includes("package=com.garmin.connectiq;"), true);
  assert.equal(
    html.includes(
      "S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.garmin.connectiq;"
    ),
    true
  );
});

test("built-in exercise catalog persists stable keys and localizes only display names", () => {
  const context = loadPwaContext();
  const defaults = jsonFrom(context, "defaultAppState().exercises");

  assert.equal(defaults.length, 52);
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
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 2);
  assert.equal(vm.runInContext("state.exercises.length", context), 53);

  vm.runInContext(`state.exercises = state.exercises.filter(
    exercise => exercise.catalogKey !== "bench_press"
  )`, context);
  assert.equal(vm.runInContext("ensureBuiltInExerciseCatalog(state)", context), false);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "bench_press")',
    context
  ), false);

  const exported = jsonFrom(context, "JSON.parse(exportPayload(false))");
  assert.equal(exported.catalogSeedVersion, 2);
});

test("catalog version 2 adds only hip abduction to existing accounts", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = defaultAppState();
    state.catalogSeedVersion = 1;
    state.exercises = state.exercises.filter(exercise =>
      exercise.catalogKey !== "hip_abduction" && exercise.catalogKey !== "bench_press"
    );`, context);

  assert.equal(vm.runInContext("ensureBuiltInExerciseCatalog(state)", context), true);
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 2);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "hip_abduction")',
    context
  ), true);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "bench_press")',
    context
  ), false);
});

test("canonical aliases derive their stable key while custom labels remain custom", () => {
  const context = loadPwaContext();
  const normalized = jsonFrom(context, `normalizeExerciseCatalog([
    { id: 7, name: "Жим штанги лежачи" },
    { id: 8, name: "Bench Press" },
    { id: 9, name: "Моя вправа" },
    { id: 10, name: "Bench Press", catalogKey: "bench_press" }
  ])`);

  assert.deepEqual(normalized, [
    { id: 7, name: "Жим штанги лежачи", catalogKey: "bench_press" },
    { id: 8, name: "Bench Press", catalogKey: "bench_press" },
    { id: 9, name: "Моя вправа" },
    { id: 10, name: "Bench Press", catalogKey: "bench_press" }
  ]);
  assert.equal(
    vm.runInContext('exerciseMatchKey({ name: "Bench Press" })', context),
    vm.runInContext('exerciseMatchKey({ name: "Жим штанги лежачи" })', context)
  );
  assert.equal(vm.runInContext('exerciseDisplayName({ name: "Жим штанги лежачи" }, "en")', context), "Bench Press");
  assert.equal(vm.runInContext('exerciseMatchesSearch({ name: "Bench Press", catalogKey: "bench_press" }, "штанги", "uk")', context), true);
  assert.equal(vm.runInContext('exerciseCatalogKey("Barbell Squat")', context), "squat");
  assert.equal(vm.runInContext('exerciseCatalogKey("Присід зі штангою")', context), "squat");
  assert.equal(vm.runInContext('exerciseCatalogKey("Приседания со штангой")', context), "squat");
  assert.equal(vm.runInContext('exerciseCatalogKey("Жим сидячи над головою")', context), "shoulder_press");
  assert.equal(vm.runInContext('exerciseCatalogKey("Разведение ног в тренажере")', context), "hip_abduction");
});

test("hip abduction aliases map to glutes without shoulder pollution", () => {
  const context = loadPwaContext();
  for (const name of ["Hip Abduction", "Розведення ніг", "Разведение ног в тренажере"]) {
    const muscleIds = jsonFrom(
      context,
      `contributionFor({ name: ${JSON.stringify(name)} }).map(item => item.muscleId)`
    );
    assert.equal(muscleIds.includes("glutes"), true, `${name} should map to glutes`);
    assert.equal(muscleIds.includes("shoulders"), false, `${name} should not map to shoulders`);
  }
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
    { id: 2, name: "My custom bench label" },
    { id: 3, name: "Планка", catalogKey: "plank" }
  ]);
  assert.equal(
    vm.runInContext('exerciseDisplayName({ name: "Bench Press", catalogKey: "squat" }, "en")', context),
    "Bench Press"
  );
  assert.equal(
    vm.runInContext('resolvedExerciseCatalogKey({ catalogKey: "bench_press" })', context),
    "bench_press"
  );
  assert.equal(
    vm.runInContext('resolvedExerciseCatalogKey({ name: "My custom bench", catalogKey: "bench_press" })', context),
    null
  );
});

test("an explicit empty remote catalog remains empty and is not replaced by defaults", () => {
  const context = loadPwaContext();

  assert.equal(vm.runInContext("normalizeImportedState({ exercises: [], sessions: [] }, defaultAppState()).exercises.length", context), 0);
  assert.equal(vm.runInContext("normalizeImportedState({ sessions: [] }, defaultAppState()).exercises.length", context), 52);
});

test("exercise library sorts by unique workout frequency in both directions", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    state = {
      ...defaultAppState(),
      exercises: [
        { id: 1, name: "Bench Press", catalogKey: "bench_press" },
        { id: 2, name: "Squat", catalogKey: "squat" },
        { id: 3, name: "Plank", catalogKey: "plank" }
      ],
      sessions: [
        { id: 10, startedAt: 10, sets: [
          { id: 11, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 50, reps: 8 },
          { id: 12, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 55, reps: 6 },
          { id: 13, exerciseName: "Squat", catalogKey: "squat", weight: 80, reps: 5 }
        ] },
        { id: 20, startedAt: 20, sets: [
          { id: 21, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 60, reps: 5 }
        ] }
      ]
    };
    exerciseSortMode = "most";
  `, context);

  assert.equal(vm.runInContext("exerciseWorkoutCount(state.exercises[0])", context), 2);
  assert.equal(vm.runInContext("exerciseWorkoutCount(state.exercises[1])", context), 1);
  assert.deepEqual(jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.id)"), [1, 2, 3]);

  vm.runInContext('exerciseSortMode = "least"', context);
  assert.deepEqual(jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.id)"), [3, 2, 1]);
});

test("legacy session aliases preserve raw labels and derive the same stable identity", () => {
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
  assert.equal(session.sets[0].catalogKey, "bench_press");
  assert.equal(session.sets[1].catalogKey, "bench_press");
});

test("nested session blocks ignore an attacker key for a nonblank custom name", () => {
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
    { id: 2, exerciseName: "My bench label", weight: 50, reps: 8, orderIndex: 0 },
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
      sets: [
        { id: 11, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 50, reps: 8, orderIndex: 0 },
        { id: 12, exerciseName: "Жим штанги лежачи", weight: 55, reps: 6, orderIndex: 0 }
      ]
    }
  ]);

  const roundTripped = jsonFrom(context, "normalizeSessions(JSON.parse(exportPayload(false)).sessions)[0]");
  assert.equal(roundTripped.sets.length, 2);
  assert.deepEqual(roundTripped.sets.map(set => set.exerciseName), ["Bench Press", "Жим штанги лежачи"]);
  assert.equal(roundTripped.sets[0].catalogKey, "bench_press");
  assert.equal(roundTripped.sets[1].catalogKey, "bench_press");
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

test("detail, summary, and progress UI do not reclassify a custom label from an attacker key", () => {
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
    assert.match(markup, /My bench label/);
    assert.doesNotMatch(markup, /Жим штанги лежачи/);
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
  assert.equal(vm.runInContext('exerciseMatchKey(state.exercises[0])', context), "catalog:squat");
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

test("favorites are account-local, filterable, and excluded from cloud schema-v2", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    render = () => {};
    activeAccount = { id: "local-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name: "Alpha", localIdVersion: 2 };
    state = {
      ...defaultAppState(),
      exercises: [
        { id: 1, name: "Bench Press", catalogKey: "bench_press", favorite: true },
        { id: 2, name: "Squat", catalogKey: "squat" },
        { id: 3, name: "Plank", catalogKey: "plank", favorite: true }
      ]
    };
    exerciseFavoritesOnly = true;
  `, context);

  assert.deepEqual(jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.id)"), [1, 3]);
  vm.runInContext("toggleExerciseFavorite(1)", context);
  assert.deepEqual(jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.id)"), [3]);
  assert.equal(vm.runInContext(`JSON.parse(localStorage.getItem(
    "gym-pwa-account:local-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  )).exercises[0].favorite === undefined`, context), true);

  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      name: "Cloud",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase"
    };
    state.exercises[2].favorite = true;
  `, context);
  const remote = jsonFrom(context, 'remoteStatePayload("11111111-1111-4111-8111-111111111111")');
  assert.equal(remote.exercises.some(exercise => "favorite" in exercise || "isFavorite" in exercise), false);
  assert.equal(jsonFrom(context, "JSON.parse(exportPayload(false)).exercises")[2].favorite, true);
});

test("older manual backups preserve existing favorites while explicit false can clear them", () => {
  const context = loadPwaContext();
  const preserved = jsonFrom(context, `(() => {
    const previous = { exercises: [{ id: 1, name: "Bench Press", catalogKey: "bench_press", favorite: true }] };
    const next = { exercises: [{ id: 9, name: "Bench Press", catalogKey: "bench_press" }] };
    preserveExerciseFavorites(next, previous);
    return next.exercises[0];
  })()`);
  assert.equal(preserved.favorite, true);

  const cleared = jsonFrom(context, `(() => {
    const previous = { exercises: [{ id: 1, name: "Bench Press", catalogKey: "bench_press", favorite: true }] };
    const next = { exercises: [{ id: 9, name: "Bench Press", catalogKey: "bench_press", favorite: false }] };
    preserveExerciseFavorites(next, previous);
    return next.exercises[0];
  })()`);
  assert.equal(cleared.favorite, false);

  const cloudProtected = jsonFrom(context, `(() => {
    const previous = { exercises: [{ id: 1, name: "Bench Press", catalogKey: "bench_press", favorite: true }] };
    const next = { exercises: [{ id: 9, name: "Bench Press", catalogKey: "bench_press", favorite: false }] };
    preserveExerciseFavorites(next, previous, { preferPrevious: true });
    return next.exercises[0];
  })()`);
  assert.equal(cloudProtected.favorite, true);
});

test("Profile owns account tools and keeps the leaderboard below them", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = { id: "local-v2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", name: "Profile Owner", localIdVersion: 2 };
    state = defaultAppState();
  `, context);
  const profile = vm.runInContext("leaderboardScreen()", context);
  const exercises = vm.runInContext("exercisesScreen()", context);

  assert.match(profile, /Profile Owner/);
  assert.match(profile, /support\.html/);
  assert.match(profile, /privacy-policy\.html/);
  assert.ok(profile.indexOf("Profile Owner") < profile.indexOf("leaderboard-list"));
  assert.doesNotMatch(exercises, /Profile Owner|support\.html|privacy-policy\.html|export-json/);
  assert.equal(vm.runInContext('titleForRoute({ name: "leaderboard" })', context), "Profile");
});

test("Missions renders the full stable achievement gallery and Workouts has no duplicate", () => {
  const context = loadPwaContext();
  const missions = vm.runInContext("missionsScreen()", context);
  const workoutsOverview = vm.runInContext("overviewCards([])", context);
  const ids = [...missions.matchAll(/data-achievement-id="([^"]+)"/g)].map(match => match[1]);

  assert.deepEqual(ids, [
    "first_workout",
    "workout_5",
    "workout_10",
    "workout_25",
    "workout_50",
    "workout_100",
    "streak_7",
    "streak_14",
    "streak_30",
    "volume_10k",
    "volume_50k",
    "comeback"
  ]);
  assert.equal(new Set(ids).size, ids.length);
  assert.doesNotMatch(workoutsOverview, /data-achievement-id=/);
});

test("leaderboard cache and in-flight work are invalidated by account generation", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    let leaderboardAbortObserved = false;
    leaderboardRequestId = 7;
    leaderboardRequestController = { abort() { leaderboardAbortObserved = true; } };
    leaderboardState = { status: "loaded", source: "old", rows: [{ display_name: "Old" }], error: "" };
    resetLeaderboardContext();
  `, context);
  assert.equal(vm.runInContext("leaderboardAbortObserved", context), true);
  assert.equal(vm.runInContext("leaderboardRequestId", context), 8);
  assert.deepEqual(jsonFrom(context, "leaderboardState"), {
    status: "idle",
    source: null,
    rows: [],
    error: ""
  });

  vm.runInContext(`
    activeAccount = { id: "local-v2-cccccccccccccccccccccccccccccccc", name: "One", localIdVersion: 2 };
    accountEpoch = 4;
  `, context);
  const first = vm.runInContext("leaderboardSourceKey()", context);
  vm.runInContext(`
    activeAccount = { id: "local-v2-dddddddddddddddddddddddddddddddd", name: "Two", localIdVersion: 2 };
    accountEpoch += 1;
  `, context);
  const second = vm.runInContext("leaderboardSourceKey()", context);
  assert.notEqual(first, second);
});
