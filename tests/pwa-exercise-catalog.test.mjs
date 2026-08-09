import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");
const stateContractSource = await readFile("pwa/state-contract.js", "utf8");
const russianTextSource = await readFile("pwa/russian-text.js", "utf8");
const exerciseSearchVocabularySource = await readFile("pwa/exercise-search-vocabulary.js", "utf8");
const sharedWorkoutSource = await readFile("pwa/shared-workout.js", "utf8");

function loadPwaContext({ userAgent = "" } = {}) {
  const values = new Map();
  const sessionValues = new Map();
  const context = {
    console,
    Date,
    Map,
    Set,
    TextDecoder,
    TextEncoder,
    AbortController,
    URLSearchParams,
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {},
      GymProgressionRules: {
        sessionXP: () => 100,
        MAX_SUPPORTED_XP: 2147483647,
        requirementForLevel: () => 100,
        cumulativeXPForLevel: () => 0,
        levelProgress: value => ({ level: 1, currentLevelXp: Number(value || 0), xpForNextLevel: 100, progressFraction: 0 }),
        currentWeeklyStreak: () => 0,
        bestWeeklyStreakDuring: () => 0
      }
    },
    document: {
      documentElement: { lang: "en" },
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: { userAgent },
    history: { state: null, pushState() {}, replaceState() {}, back() {} },
    localStorage: {
      getItem: key => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, String(value)),
      removeItem: key => values.delete(key)
    },
    sessionStorage: {
      getItem: key => sessionValues.get(key) ?? null,
      setItem: (key, value) => sessionValues.set(key, String(value)),
      removeItem: key => sessionValues.delete(key)
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
  context.window.history = context.history;
  context.window.localStorage = context.localStorage;
  context.window.sessionStorage = context.sessionStorage;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(sharedWorkoutSource, context);
  context.window.GymSharedWorkout = context.GymSharedWorkout;
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(russianTextSource, context);
  vm.runInContext(exerciseSearchVocabularySource, context);
  vm.runInContext(appSource, context);
  return context;
}

function jsonFrom(context, expression) {
  return JSON.parse(vm.runInContext(`JSON.stringify(${expression})`, context));
}

function socialDashboardFixture() {
  return {
    version: 1,
    self: {
      profileId: "p_11111111111111111111111111111111",
      friendCode: "p_11111111111111111111111111111111",
      displayName: "Owner",
      xp: 1200,
      level: 5,
      workouts: 12,
      statsAvailable: true,
      progressUpdatedAt: "2026-08-09T12:00:00Z",
      privacy: {
        allowRequests: true,
        shareProgress: true,
        shareRecentWorkouts: true,
        shareRecords: true
      },
      settingsRevision: 2
    },
    friends: [{
      friendshipId: "f_22222222222222222222222222222222",
      profileId: "p_22222222222222222222222222222222",
      displayName: "Friend",
      xp: 900,
      level: 4,
      workouts: 10,
      progressShared: true,
      statsAvailable: true,
      progressUpdatedAt: "2026-08-09T11:00:00Z",
      friendshipRevision: 3,
      status: "accepted"
    }],
    incoming: [],
    outgoing: [],
    blocked: [],
    pendingWorkoutInviteCount: 1
  };
}

function sharedWorkoutFixture() {
  return {
    version: 1,
    exercises: [{
      catalogKey: "bench_press",
      name: "Bench Press",
      sets: [{ weight: 80, reps: 8 }]
    }]
  };
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

  assert.equal(defaults.length, 53);
  assert.deepEqual(defaults[0], { id: 1, name: "Bench Press", catalogKey: "bench_press" });
  assert.equal(vm.runInContext('exerciseDisplayName(defaultAppState().exercises[0], "uk")', context), "Жим штанги лежачи");
  assert.equal(vm.runInContext('exerciseDisplayName({ name: "My custom press" }, "uk")', context), "My custom press");
});

test("exercise add and rename use the native Unicode name boundary", () => {
  const context = loadPwaContext();
  const accepted = "😀".repeat(160);
  const rejected = "😀".repeat(161);

  assert.equal(
    vm.runInContext(`isSupportedExerciseName(${JSON.stringify(accepted)})`, context),
    true
  );
  assert.equal(
    vm.runInContext(`isSupportedExerciseName(${JSON.stringify(rejected)})`, context),
    false
  );
  assert.match(appSource, /id="new-exercise-name" maxlength="320"/);
  assert.match(appSource, /id="rename-name" maxlength="320"/);
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
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 3);
  assert.equal(vm.runInContext("state.exercises.length", context), 54);

  vm.runInContext(`state.exercises = state.exercises.filter(
    exercise => exercise.catalogKey !== "bench_press"
  )`, context);
  assert.equal(vm.runInContext("ensureBuiltInExerciseCatalog(state)", context), false);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "bench_press")',
    context
  ), false);

  const exported = jsonFrom(context, "JSON.parse(exportPayload(false))");
  assert.equal(exported.catalogSeedVersion, 3);
});

test("catalog upgrades add only exercises introduced after the stored seed", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = defaultAppState();
    state.catalogSeedVersion = 1;
    state.exercises = state.exercises.filter(exercise =>
      exercise.catalogKey !== "hip_abduction" && exercise.catalogKey !== "bench_press"
    );`, context);

  assert.equal(vm.runInContext("ensureBuiltInExerciseCatalog(state)", context), true);
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 3);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "hip_abduction")',
    context
  ), true);
  assert.equal(vm.runInContext(
    'state.exercises.some(exercise => exercise.catalogKey === "assisted_dip")',
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
  for (const alias of [
    "підтягування з брусьями",
    "підтягування з брусами",
    "підтягування с брусьями",
    "підтягування с брусами",
    "подтягивания с брусьями",
    "подтягивание с брусьями"
  ]) {
    assert.equal(vm.runInContext(`exerciseCatalogKey(${JSON.stringify(alias)})`, context), "assisted_dip");
  }
  assert.equal(vm.runInContext('exerciseCatalogKey("брусья в гравитроне")', context), null);
});

test("colloquial exercise search is multilingual, order independent, and identity safe", () => {
  const context = loadPwaContext();
  const examples = [
    ["lateral_raise", "махи в сторони с гантелями"],
    ["lateral_raise", "гантели стороны махи"],
    ["lateral_raise", "DB lat raises"],
    ["shoulder_press", "OHP"],
    ["romanian_deadlift", "RDL"],
    ["bulgarian_split_squat", "BSS"],
    ["bulgarian_split_squat", "RFESS"],
    ["chest_fly_machine", "pec-deck"],
    ["face_pull", "rope face pull"],
    ["plate_loaded_row", "тяга у хаммері"],
    ["hammer_curl", "молотки"],
    ["preacher_curl", "Scott curl"],
    ["plate_twist", "Russian twist"]
  ];
  for (const [catalogKey, query] of examples) {
    assert.equal(
      vm.runInContext(
        `exerciseMatchesSearch({ name: builtInExerciseByKey.get(${JSON.stringify(catalogKey)}).names.en, catalogKey: ${JSON.stringify(catalogKey)} }, ${JSON.stringify(query)}, "ru")`,
        context
      ),
      true,
      `${query} should find ${catalogKey}`
    );
  }

  for (const searchOnlyAlias of [
    "бабочка", "OHP", "RDL", "BSS", "RFESS", "Scott curl",
    "махи гантелями в стороны"
  ]) {
    assert.equal(
      vm.runInContext(`exerciseCatalogKey(${JSON.stringify(searchOnlyAlias)})`, context),
      null,
      `${searchOnlyAlias} must not become a persisted identity alias`
    );
  }
});

test("exercise search ranks exact phrases above partial variants", () => {
  const context = loadPwaContext();
  vm.runInContext(`state = defaultAppState(); exerciseSortMode = "name"; exerciseSearchQuery = "Bench Press";`, context);
  const benchKeys = jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.catalogKey)");
  assert.equal(benchKeys[0], "bench_press");
  assert.ok(benchKeys.includes("dumbbell_bench_press"));

  vm.runInContext(`state = defaultAppState(); exerciseSortMode = "name"; exerciseSearchQuery = "pec deck";`, context);
  const pecDeckKeys = jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.catalogKey)");
  assert.equal(pecDeckKeys[0], "chest_fly_machine");
  assert.ok(pecDeckKeys.includes("rear_delt_fly"));
  assert.ok(
    vm.runInContext(`exerciseSearchMatch(state.exercises.find(exercise => exercise.catalogKey === "chest_fly_machine"), "pec deck", "en").score`, context) >
    vm.runInContext(`exerciseSearchMatch(state.exercises.find(exercise => exercise.catalogKey === "rear_delt_fly"), "pec deck", "en").score`, context)
  );

  vm.runInContext(`exerciseSearchQuery = "reverse pec deck";`, context);
  const reverseKeys = jsonFrom(context, "filteredLibraryExercises().map(exercise => exercise.catalogKey)");
  assert.equal(reverseKeys[0], "rear_delt_fly");
  assert.equal(reverseKeys.includes("chest_fly_machine"), false);
});

test("exercise search tolerates only bounded useful typos and transliteration", () => {
  const context = loadPwaContext();
  for (const [catalogKey, query] of [
    ["assisted_pull_up", "граветрон"],
    ["chest_fly_machine", "pecdek"],
    ["romanian_deadlift", "ruminka"],
    ["lateral_raise", "mahi gantelyami"],
    ["lateral_raise", "mahi s gantelyami"],
    ["incline_dumbbell_press", "zhim na verh grudi"],
    ["lat_pulldown", "spina na bloke"]
  ]) {
    assert.equal(
      vm.runInContext(`exerciseMatchesSearch(defaultAppState().exercises.find(exercise => exercise.catalogKey === ${JSON.stringify(catalogKey)}), ${JSON.stringify(query)}, "ru")`, context),
      true,
      `${query} should find ${catalogKey}`
    );
  }
  assert.equal(vm.runInContext(`exerciseMatchesSearch(defaultAppState().exercises[0], "db", "en")`, context), false);
  assert.equal(vm.runInContext(`exerciseMatchesSearch(defaultAppState().exercises[0], "db db", "en")`, context), false);
  assert.equal(vm.runInContext(`exerciseMatchesSearch(defaultAppState().exercises[0], "zzzzzz", "en")`, context), false);
});

test("exercise search combines muscle and equipment vocabulary", () => {
  const context = loadPwaContext();
  const matchingKeys = query => jsonFrom(
    context,
    `defaultAppState().exercises.filter(exercise => exerciseMatchesSearch(exercise, ${JSON.stringify(query)}, "ru")).map(exercise => exercise.catalogKey)`
  );
  assert.deepEqual(matchingKeys("задняя дельта"), ["rear_delt_fly"]);
  const upperChestMatches = matchingKeys("верх груди");
  assert.ok(upperChestMatches.includes("incline_dumbbell_press"));
  assert.ok(upperChestMatches.includes("incline_bench_press"));
  assert.equal(upperChestMatches.includes("lat_pulldown"), false);
  assert.ok(matchingKeys("спина блок").includes("lat_pulldown"));
  assert.ok(matchingKeys("спина блок").includes("seated_cable_row"));
  assert.ok(matchingKeys("гантели трицепс").includes("overhead_dumbbell_triceps_extension"));
});

test("exercise search explains useful non-canonical matches in every UI language", () => {
  const context = loadPwaContext();
  for (const [language, expectedPrefix] of [
    ["en", "Found by:"],
    ["uk", "Знайдено за запитом:"],
    ["ru", "Найдено по:"]
  ]) {
    vm.runInContext(`state = defaultAppState(); state.language = ${JSON.stringify(language)}; exerciseSearchQuery = "махи в стороны";`, context);
    const markup = vm.runInContext(`exerciseSearchReasonMarkup(state.exercises.find(exercise => exercise.catalogKey === "lateral_raise"))`, context);
    assert.ok(markup.includes(expectedPrefix));
    assert.ok(markup.includes("махи в стороны"), markup);
  }
  vm.runInContext(`state.language = "en"; exerciseSearchQuery = "Lateral Raise";`, context);
  assert.equal(
    vm.runInContext(`exerciseSearchReasonMarkup(state.exercises.find(exercise => exercise.catalogKey === "lateral_raise"))`, context),
    ""
  );
});

test("ambiguous gym terms return honest choices without reviving a misleading legacy search alias", () => {
  const context = loadPwaContext();
  const matchingKeys = query => jsonFrom(
    context,
    `defaultAppState().exercises
      .filter(exercise => exerciseMatchesSearch(exercise, ${JSON.stringify(query)}, "ru"))
      .map(exercise => exercise.catalogKey)
      .sort()`
  );

  assert.deepEqual(matchingKeys("гравитрон"), ["assisted_dip", "assisted_pull_up"]);
  assert.deepEqual(matchingKeys("бабочка"), ["chest_fly_machine", "rear_delt_fly"]);
  assert.ok(matchingKeys("бицепс бедра").includes("lying_leg_curl"));
  assert.ok(matchingKeys("бицепс бедра").includes("seated_leg_curl"));
  assert.ok(matchingKeys("вертикальная тяга").includes("lat_pulldown"));
  assert.equal(matchingKeys("вертикальная тяга").includes("upright_row"), false);
});

test("exercise search rejects unbounded queries before scanning aliases", () => {
  const context = loadPwaContext();
  assert.equal(
    vm.runInContext(
      `exerciseMatchesSearch({ name: "Bench Press", catalogKey: "bench_press" }, ${JSON.stringify("x".repeat(257))}, "en")`,
      context
    ),
    false
  );
  assert.equal(
    vm.runInContext(
      `exerciseMatchesSearch({ name: "Bench Press", catalogKey: "bench_press" }, ${JSON.stringify(Array.from({ length: 17 }, (_, index) => `word${index}`).join(" "))}, "en")`,
      context
    ),
    false
  );
  assert.equal(
    vm.runInContext(
      `exerciseMatchesSearch({ name: ${JSON.stringify("y".repeat(129))} }, ${JSON.stringify("y".repeat(128))}, "en")`,
      context
    ),
    false
  );
});

test("assisted-dip upgrade preserves the legacy row and history without a duplicate", () => {
  const context = loadPwaContext();
  const upgraded = jsonFrom(context, `(() => {
    const next = normalizeImportedState({
      catalogSeedVersion: 2,
      exercises: [{ id: 700, name: "підтягування с брусьями", favorite: true }],
      sessions: [{ id: 10, startedAt: 1760000000000, sets: [
        { id: 11, exerciseName: "підтягування с брусьями", weight: 50, reps: 8, orderIndex: 0 }
      ] }],
      mappings: {},
      profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
    }, defaultAppState());
    ensureBuiltInExerciseCatalog(next);
    return next;
  })()`);

  const matches = upgraded.exercises.filter(exercise => exercise.catalogKey === "assisted_dip");
  assert.equal(matches.length, 1);
  assert.deepEqual(matches[0], { id: 700, name: "Assisted Dip", catalogKey: "assisted_dip", favorite: true });
  assert.equal(upgraded.sessions[0].sets[0].exerciseName, "підтягування с брусьями");
  assert.equal(upgraded.sessions[0].sets[0].weight, 50);
  assert.equal(upgraded.catalogSeedVersion, 3);
});

test("older cloud payloads keep a valid local machine profile only on cloud merge", () => {
  const context = loadPwaContext();
  const result = jsonFrom(context, `(() => {
    const local = { exercises: [{ id: 1, name: "Lat Pulldown", catalogKey: "lat_pulldown", loadProfile: {
      direction: "higherIsHarder", allowedWeightsKg: [45, 50, 55]
    } }] };
    const missing = { exercises: [{ id: 1, name: "Lat Pulldown", catalogKey: "lat_pulldown" }] };
    const explicit = { exercises: [{ id: 1, name: "Lat Pulldown", catalogKey: "lat_pulldown", loadProfile: {
      direction: "higherIsHarder", allowedWeightsKg: [40, 45, 50]
    } }] };
    const ordinaryReplacement = JSON.parse(JSON.stringify(missing));
    preserveExerciseFavorites(missing, local, { preserveMissingLoadProfiles: true });
    preserveExerciseFavorites(explicit, local, { preserveMissingLoadProfiles: true });
    preserveExerciseFavorites(ordinaryReplacement, local);
    return { missing, explicit, ordinaryReplacement };
  })()`);

  assert.deepEqual(result.missing.exercises[0].loadProfile.allowedWeightsKg, [45, 50, 55]);
  assert.deepEqual(result.explicit.exercises[0].loadProfile.allowedWeightsKg, [40, 45, 50]);
  assert.equal("loadProfile" in result.ordinaryReplacement.exercises[0], false);
});

test("machine-profile controls stay Russian without dynamic English keys", () => {
  const context = loadPwaContext();
  const markup = vm.runInContext(`(() => {
    state = defaultAppState();
    state.language = "ru";
    const exercise = state.exercises.find(item => item.catalogKey === "lat_pulldown");
    exercise.loadProfile = { direction: "higherIsHarder", allowedWeightsKg: [45, 50, 55] };
    modal = { type: "load-profile", exerciseId: exercise.id };
    return exerciseRow(exercise) + draftBlock({
      exerciseName: exercise.name,
      catalogKey: exercise.catalogKey,
      sets: [{ weight: 50, reps: 8 }]
    }, 0) + modalMarkup();
  })()`, context);

  assert.match(markup, /Веса тренажера/);
  assert.match(markup, /Настроенные веса тренажера/);
  assert.doesNotMatch(markup, /Machine weights|Configured machine weights/);
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
  assert.equal(vm.runInContext("normalizeImportedState({ sessions: [] }, defaultAppState()).exercises.length", context), 53);
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

test("exercise media thumbnails appear across library, progress, workout detail, and history", () => {
  const context = loadPwaContext();
  const markup = vm.runInContext(`(() => {
    state = defaultAppState();
    const exercise = state.exercises.find(item => item.catalogKey === "bench_press");
    state.progressExerciseId = exercise.id;
    state.sessions = [{
      id: 10,
      startedAt: Date.now(),
      note: "",
      exerciseNames: [exercise.name],
      sets: [{ id: 11, exerciseName: exercise.name, catalogKey: exercise.catalogKey, weight: 50, reps: 8, orderIndex: 0 }]
    }];
    return [
      exerciseRow(exercise),
      progressScreen(),
      detailScreen(10),
      exerciseHistoryMarkup(exercise)
    ].join("\\n");
  })()`, context);

  assert.equal((markup.match(/data-action="open-exercise-media"/g) || []).length, 4);
  assert.equal((markup.match(/data-exercise-id="1"/g) || []).length, 4);
  assert.equal((markup.match(/exercise-media\/bench_press_0\.jpg/g) || []).length, 4);
});

test("exercise media actions resolve only validated stored IDs and custom labels cannot borrow built-in media", () => {
  const context = loadPwaContext();
  const result = jsonFrom(context, `(() => {
    state = defaultAppState();
    workoutDraft = null;
    modal = null;
    const bench = state.exercises.find(item => item.catalogKey === "bench_press");
    const custom = { id: 999, name: "<img src=x onerror=alert(1)>", catalogKey: "bench_press" };
    state.exercises.push(custom);
    const customMarkup = exerciseMediaThumbnail(custom);
    handleAction("open-exercise-media", { dataset: { exerciseId: String(bench.id) } });
    const openedId = modal?.exercise?.id || null;
    modal = null;
    handleAction("open-exercise-media", { dataset: { exerciseId: "1e309" } });
    return { customMarkup, openedId, invalidOpened: modal !== null };
  })()`);

  assert.equal(result.openedId, 1);
  assert.equal(result.invalidOpened, false);
  assert.doesNotMatch(result.customMarkup, /<img /);
  assert.match(result.customMarkup, /data-exercise-id="999"/);
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

test("Profile owns account tools and keeps protected friends below them", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = { id: "local-v2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", name: "Profile Owner", localIdVersion: 2 };
    state = defaultAppState();
  `, context);
  const profile = vm.runInContext("friendsProfileScreen()", context);
  const exercises = vm.runInContext("exercisesScreen()", context);

  assert.match(profile, /Profile Owner/);
  assert.match(profile, /support\.html/);
  assert.match(profile, /privacy-policy\.html/);
  assert.ok(profile.indexOf("Profile Owner") < profile.indexOf("Cloud sign-in required"));
  assert.match(profile, /Friends/);
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

test("friend caches and in-flight work are invalidated by account generation", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    let socialAbortObserved = false;
    let socialDetailAbortObserved = false;
    socialRequestId = 7;
    socialRequestController = { abort() { socialAbortObserved = true; } };
    socialDetailRequestId = 11;
    socialDetailRequestController = { abort() { socialDetailAbortObserved = true; } };
    socialState = { status: "loaded", source: "old", dashboard: { version: 1 }, inbox: { version: 1 }, error: "" };
    socialDetailState = { status: "loaded", source: "old:friend", profileId: "p_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", value: { version: 1 }, error: "" };
    socialMutationInProgress = true;
    socialLastLoadedAt = 1234;
    socialWorkoutInviteRequests.set("old", { key: "old", requestId: "11111111-1111-4111-8111-111111111111" });
    resetSocialContext();
  `, context);
  assert.equal(vm.runInContext("socialAbortObserved", context), true);
  assert.equal(vm.runInContext("socialDetailAbortObserved", context), true);
  assert.equal(vm.runInContext("socialRequestId", context), 8);
  assert.equal(vm.runInContext("socialDetailRequestId", context), 12);
  assert.deepEqual(jsonFrom(context, "socialState"), {
    status: "idle",
    source: null,
    dashboard: null,
    inbox: null,
    error: ""
  });
  assert.deepEqual(jsonFrom(context, "socialDetailState"), {
    status: "idle",
    source: null,
    profileId: null,
    value: null,
    error: ""
  });
  assert.equal(vm.runInContext("socialMutationInProgress", context), false);
  assert.equal(vm.runInContext("socialLastLoadedAt", context), 0);
  assert.equal(vm.runInContext("socialWorkoutInviteRequests.size", context), 1);

  vm.runInContext(`
    activeAccount = { id: "local-v2-cccccccccccccccccccccccccccccccc", name: "One", localIdVersion: 2 };
    accountEpoch = 4;
  `, context);
  const first = vm.runInContext("socialSourceKey()", context);
  vm.runInContext(`
    activeAccount = { id: "local-v2-dddddddddddddddddddddddddddddddd", name: "Two", localIdVersion: 2 };
    accountEpoch += 1;
  `, context);
  const second = vm.runInContext("socialSourceKey()", context);
  assert.notEqual(first, second);

  const linkPlan = sharedWorkoutFixture();
  vm.runInContext(`
    pendingSharedWorkout = ${JSON.stringify(linkPlan)};
    pendingSharedWorkoutOrigin = { type: "link" };
    modal = {
      type: "confirm-social-workout-replace",
      workout: { version: 1, exercises: [{ name: "Private invite", sets: [{ weight: 1, reps: 1 }] }] },
      inviteId: "wi_33333333333333333333333333333333",
      expectedEpoch: accountEpoch,
      expectedUserId: "11111111-1111-4111-8111-111111111111"
    };
    resetRemoteSyncContext();
  `, context);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(vm.runInContext("pendingSharedWorkoutOrigin.type", context), "link");
  assert.deepEqual(jsonFrom(context, "pendingSharedWorkout"), linkPlan);
  assert.equal(vm.runInContext("socialWorkoutInviteRequests.size", context), 0);
});

test("account transitions clear account-bound drafts and private share surfaces", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner A"
    };
    workoutDraft = { startedAt: 1, note: "private A", blocks: [{ exerciseName: "Private invite", sets: [] }] };
    smartGeneratedPlan = { exercises: [{ name: "Private smart plan" }] };
    smartPlanStale = true;
    modal = { type: "workout-share", plan: { version: 1, exercises: [] } };
    resetRemoteSyncContext();
    activeAccount = {
      id: "remote-22222222-2222-4222-8222-222222222222",
      userId: "22222222-2222-4222-8222-222222222222",
      remote: "supabase",
      name: "Owner B"
    };
  `, context);
  assert.equal(vm.runInContext("workoutDraft", context), null);
  assert.equal(vm.runInContext("smartGeneratedPlan", context), null);
  assert.equal(vm.runInContext("smartPlanStale", context), false);
  assert.equal(vm.runInContext("modal", context), null);
});

test("friend dashboard parser is exact, bounded, and renders server text as text", () => {
  const context = loadPwaContext();
  const fixture = socialDashboardFixture();
  fixture.friends[0].displayName = '<img src=x onerror="alert(1)">';
  const parsed = jsonFrom(context, `parseSocialDashboard(${JSON.stringify(fixture)})`);
  assert.equal(parsed.friends[0].profileId, fixture.friends[0].profileId);

  vm.runInContext(`socialState.dashboard = parseSocialDashboard(${JSON.stringify(fixture)})`, context);
  const markup = vm.runInContext("friendRankingRow(socialRankingRows()[1], 1)", context);
  assert.match(markup, /&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt;/);
  assert.doesNotMatch(markup, /<img/);

  const nonBreakingEdges = structuredClone(fixture);
  nonBreakingEdges.self.displayName = "\u00a0Owner\u00a0";
  nonBreakingEdges.friends[0].displayName = "\u00a0Friend\u00a0";
  const nonBreakingParsed = jsonFrom(
    context,
    `parseSocialDashboard(${JSON.stringify(nonBreakingEdges)})`
  );
  assert.equal(nonBreakingParsed.self.displayName, "\u00a0Owner\u00a0");
  assert.equal(nonBreakingParsed.friends[0].displayName, "\u00a0Friend\u00a0");

  const asciiSpaceEdge = structuredClone(fixture);
  asciiSpaceEdge.self.displayName = " Owner";
  assert.throws(
    () => vm.runInContext(`parseSocialDashboard(${JSON.stringify(asciiSpaceEdge)})`, context),
    /text is invalid/
  );

  const extraIdentifier = structuredClone(fixture);
  extraIdentifier.self.userId = "11111111-1111-4111-8111-111111111111";
  assert.throws(
    () => vm.runInContext(`parseSocialDashboard(${JSON.stringify(extraIdentifier)})`, context),
    /shape/
  );

  const hiddenButLeaking = structuredClone(fixture);
  Object.assign(hiddenButLeaking.friends[0], {
    progressShared: false,
    statsAvailable: false
  });
  assert.throws(
    () => vm.runInContext(`parseSocialDashboard(${JSON.stringify(hiddenButLeaking)})`, context),
    /inconsistent/
  );

  const duplicateRelationship = structuredClone(fixture);
  duplicateRelationship.incoming.push({
    friendshipId: fixture.friends[0].friendshipId,
    profileId: "p_33333333333333333333333333333333",
    displayName: "Duplicate",
    requestedAt: "2026-08-09T10:00:00Z",
    friendshipRevision: 1,
    status: "pending"
  });
  assert.throws(
    () => vm.runInContext(`parseSocialDashboard(${JSON.stringify(duplicateRelationship)})`, context),
    /relationships are inconsistent/
  );

  const missingProgressTimestamp = structuredClone(fixture);
  missingProgressTimestamp.self.progressUpdatedAt = null;
  assert.throws(
    () => vm.runInContext(`parseSocialDashboard(${JSON.stringify(missingProgressTimestamp)})`, context),
    /progress is inconsistent/
  );

  const normalizedInvalidTimestamp = structuredClone(fixture);
  normalizedInvalidTimestamp.self.progressUpdatedAt = "2026-02-30T12:00:00Z";
  assert.throws(
    () => vm.runInContext(`parseSocialDashboard(${JSON.stringify(normalizedInvalidTimestamp)})`, context),
    /timestamp is invalid/
  );
});

test("friend details expose only bounded summaries and independent entered bests", () => {
  const context = loadPwaContext();
  const details = {
    version: 1,
    friend: {
      profileId: "p_22222222222222222222222222222222",
      displayName: "Friend",
      xp: 900,
      level: 4,
      workouts: 10,
      progressShared: true,
      statsAvailable: true,
      progressUpdatedAt: "2026-08-09T11:00:00Z"
    },
    recentWorkouts: [{
      workoutDay: "2026-08-08",
      exerciseCount: 1,
      setCount: 3,
      exercises: [{ catalogKey: "bench_press", name: "Bench Press" }]
    }, {
      workoutDay: "2026-08-08",
      exerciseCount: 1,
      setCount: 2,
      exercises: [{ catalogKey: "squat", name: "Squat" }]
    }],
    exerciseRecords: [{
      catalogKey: "bench_press",
      name: "Bench Press",
      bestWeightKg: 100,
      bestReps: 12,
      workoutCount: 5,
      lastWorkoutDay: "2026-08-08"
    }],
    sharing: { progress: true, recentWorkouts: true, records: true },
    activityUpdatedAt: "2026-08-09T11:00:00Z",
    integrity: "self_reported"
  };
  const parsed = jsonFrom(context, `parseSocialFriendDetails(${JSON.stringify(details)})`);
  assert.equal(parsed.recentWorkouts.length, 2, "two distinct same-day sessions stay visible");
  assert.equal(parsed.recentWorkouts[0].workoutDay, parsed.recentWorkouts[1].workoutDay);
  assert.equal(parsed.exerciseRecords[0].bestWeightKg, 100);
  assert.equal(parsed.exerciseRecords[0].bestReps, 12);

  const widthDistinct = structuredClone(details);
  widthDistinct.recentWorkouts[0].exerciseCount = 2;
  widthDistinct.recentWorkouts[0].exercises = [
    { catalogKey: null, name: "A" },
    { catalogKey: null, name: "Ａ" }
  ];
  widthDistinct.exerciseRecords = [
    {
      catalogKey: null,
      name: "A",
      bestWeightKg: 10,
      bestReps: 5,
      workoutCount: 1,
      lastWorkoutDay: "2026-08-08"
    },
    {
      catalogKey: null,
      name: "Ａ",
      bestWeightKg: 10,
      bestReps: 5,
      workoutCount: 1,
      lastWorkoutDay: "2026-08-08"
    }
  ];
  const widthDistinctParsed = jsonFrom(
    context,
    `parseSocialFriendDetails(${JSON.stringify(widthDistinct)})`
  );
  assert.deepEqual(
    widthDistinctParsed.exerciseRecords.map(record => record.name),
    ["A", "Ａ"],
    "NFC identity keeps fullwidth characters distinct"
  );

  const staleButFailClosed = structuredClone(details);
  Object.assign(staleButFailClosed.friend, {
    xp: null,
    level: null,
    workouts: null,
    statsAvailable: false,
    progressUpdatedAt: null
  });
  staleButFailClosed.activityUpdatedAt = null;
  staleButFailClosed.recentWorkouts = [];
  staleButFailClosed.exerciseRecords = [];
  assert.equal(
    jsonFrom(context, `parseSocialFriendDetails(${JSON.stringify(staleButFailClosed)}).friend`).statsAvailable,
    false
  );

  const privateLeak = structuredClone(details);
  privateLeak.sharing.recentWorkouts = false;
  assert.throws(
    () => vm.runInContext(`parseSocialFriendDetails(${JSON.stringify(privateLeak)})`, context),
    /Hidden friend activity/
  );

  const rawHistoryLeak = structuredClone(details);
  rawHistoryLeak.recentWorkouts[0].note = "private";
  assert.throws(
    () => vm.runInContext(`parseSocialFriendDetails(${JSON.stringify(rawHistoryLeak)})`, context),
    /shape/
  );

  const mismatchedExerciseCount = structuredClone(details);
  mismatchedExerciseCount.recentWorkouts[0].exerciseCount = 2;
  assert.throws(
    () => vm.runInContext(`parseSocialFriendDetails(${JSON.stringify(mismatchedExerciseCount)})`, context),
    /summary is inconsistent/
  );

  const duplicateExerciseIdentity = structuredClone(details);
  duplicateExerciseIdentity.recentWorkouts[0].exerciseCount = 2;
  duplicateExerciseIdentity.recentWorkouts[0].exercises.push({
    catalogKey: "bench_press",
    name: "Bench Press duplicate label"
  });
  assert.throws(
    () => vm.runInContext(`parseSocialFriendDetails(${JSON.stringify(duplicateExerciseIdentity)})`, context),
    /summary is inconsistent/
  );
});

test("dashboard refresh invalidates and refetches an open friend detail after privacy changes", async () => {
  const context = loadPwaContext();
  const dashboard = socialDashboardFixture();
  dashboard.pendingWorkoutInviteCount = 0;
  const refreshedDetail = {
    version: 1,
    friend: {
      profileId: "p_22222222222222222222222222222222",
      displayName: "Friend",
      xp: 900,
      level: 4,
      workouts: 10,
      progressShared: true,
      statsAvailable: true,
      progressUpdatedAt: "2026-08-09T11:00:00Z"
    },
    sharing: { progress: true, recentWorkouts: false, records: false },
    activityUpdatedAt: null,
    recentWorkouts: [],
    exerciseRecords: [],
    integrity: "self_reported"
  };
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 6;
    remoteAuthEnabled = () => true;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    socialState = { status: "loaded", source: socialSourceKey(), dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}), inbox: null, error: "" };
    socialDetailState = {
      status: "loaded",
      source: socialSourceKey() + ":p_22222222222222222222222222222222",
      profileId: "p_22222222222222222222222222222222",
      value: { recentWorkouts: [{ exercises: [{ name: "stale private row" }] }] },
      error: ""
    };
    modal = { type: "friend-detail", profileId: "p_22222222222222222222222222222222" };
    flushPendingRemoteSave = async () => {};
    socialRpc = async name => {
      if (name === "social_dashboard") return ${JSON.stringify(dashboard)};
      if (name === "social_workout_inbox") return { version: 1, pendingIncomingCount: 0, incoming: [], outgoing: [] };
      if (name === "social_friend_details") return ${JSON.stringify(refreshedDetail)};
      throw new Error("unexpected RPC");
    };
    render = () => {};
  `, context);
  await vm.runInContext("refreshSocialData(true)", context);
  const value = jsonFrom(context, "socialDetailState.value");
  assert.equal(value.sharing.recentWorkouts, false);
  assert.equal(value.sharing.records, false);
  assert.deepEqual(value.recentWorkouts, []);
  assert.doesNotMatch(JSON.stringify(value), /stale private row/);
});

test("workout invitation parser rejects private fields and enforces the canonical plan", () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  const inbox = {
    version: 1,
    pendingIncomingCount: 1,
    incoming: [{
      inviteId: "wi_33333333333333333333333333333333",
      profileId: "p_22222222222222222222222222222222",
      displayName: "Friend",
      status: "pending",
      inviteRevision: 1,
      createdAt: "2026-08-09T12:00:00Z",
      expiresAt: "2026-08-16T12:00:00Z",
      respondedAt: null,
      summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
      workout
    }],
    outgoing: []
  };
  const parsed = jsonFrom(context, `parseSocialWorkoutInbox(${JSON.stringify(inbox)})`);
  assert.deepEqual(parsed.incoming[0].workout, workout);

  const builtInAliasPair = structuredClone(inbox);
  builtInAliasPair.incoming[0].summary = {
    exerciseCount: 2,
    setCount: 2,
    exerciseNames: ["Bench Press", "Жим штанги лежачи"]
  };
  builtInAliasPair.incoming[0].workout = {
    version: 1,
    exercises: [{
      name: "Bench Press",
      sets: [{ weight: 80, reps: 8 }]
    }, {
      name: "Жим штанги лежачи",
      sets: [{ weight: 80, reps: 8 }]
    }]
  };
  const aliasPairParsed = jsonFrom(
    context,
    `parseSocialWorkoutInbox(${JSON.stringify(builtInAliasPair)})`
  );
  assert.equal(aliasPairParsed.incoming[0].workout.exercises.length, 2);

  const nonBreakingEdges = structuredClone(inbox);
  nonBreakingEdges.incoming[0].displayName = "\u00a0Friend\u00a0";
  nonBreakingEdges.incoming[0].summary.exerciseNames[0] = "\u00a0Bench Press\u00a0";
  nonBreakingEdges.incoming[0].workout.exercises[0].name = "\u00a0Bench Press\u00a0";
  const nonBreakingParsed = jsonFrom(
    context,
    `parseSocialWorkoutInbox(${JSON.stringify(nonBreakingEdges)})`
  );
  assert.equal(nonBreakingParsed.incoming[0].displayName, "\u00a0Friend\u00a0");
  assert.equal(nonBreakingParsed.incoming[0].workout.exercises[0].name, "\u00a0Bench Press\u00a0");

  const privatePayload = structuredClone(inbox);
  privatePayload.incoming[0].workout.accountId = "must-not-leak";
  assert.throws(
    () => vm.runInContext(`parseSocialWorkoutInbox(${JSON.stringify(privatePayload)})`, context),
    /shape/
  );

  const extraOutgoingPayload = structuredClone(inbox);
  extraOutgoingPayload.outgoing = [{ ...extraOutgoingPayload.incoming[0] }];
  assert.throws(
    () => vm.runInContext(`parseSocialWorkoutInbox(${JSON.stringify(extraOutgoingPayload)})`, context),
    /shape/
  );

  const misleadingSummary = structuredClone(inbox);
  misleadingSummary.incoming[0].summary.setCount = 2;
  assert.throws(
    () => vm.runInContext(`parseSocialWorkoutInbox(${JSON.stringify(misleadingSummary)})`, context),
    /metadata is inconsistent/
  );

  const acceptedInbox = structuredClone(inbox);
  acceptedInbox.pendingIncomingCount = 0;
  Object.assign(acceptedInbox.incoming[0], {
    status: "accepted",
    inviteRevision: 2,
    respondedAt: "2026-08-09T12:05:00Z"
  });
  vm.runInContext(`socialState.inbox = parseSocialWorkoutInbox(${JSON.stringify(acceptedInbox)})`, context);
  const acceptedMarkup = vm.runInContext("socialWorkoutInviteRows()", context);
  assert.match(acceptedMarkup, /data-action="open-accepted-workout-invite"/);
  assert.match(acceptedMarkup, /Open copy again/);
});

test("one unimportable social plan cannot poison the workout inbox", () => {
  const context = loadPwaContext();
  const aliasPlan = {
    version: 1,
    exercises: [{ name: "Bench Press", sets: [{ weight: 80, reps: 8 }] }, {
      name: "Жим штанги лежачи", sets: [{ weight: 80, reps: 8 }]
    }]
  };
  vm.runInContext(`
    pendingSharedWorkout = normalizeSocialWorkoutPlan(${JSON.stringify(aliasPlan)});
    pendingSharedWorkoutOrigin = {
      type: "social",
      inviteId: "wi_33333333333333333333333333333333",
      userId: "11111111-1111-4111-8111-111111111111"
    };
    workoutDraft = null;
    activeWorkout = null;
    window.GymSharedWorkoutFlow = {
      prepareImport() { throw new TypeError("duplicate built-in alias"); }
    };
    let aliasImportToast = "";
    render = () => {};
    showToast = message => { aliasImportToast = message; };
  `, context);
  const applied = vm.runInContext("applyPendingSharedWorkout(false)", context);
  assert.equal(applied, false);
  assert.equal(vm.runInContext("pendingSharedWorkout", context), null);
  assert.equal(vm.runInContext("pendingSharedWorkoutOrigin", context), null);
  assert.match(vm.runInContext("aliasImportToast", context), /cannot be imported safely/);
});

test("an unimportable pending invite stays declineable without an accept RPC", async () => {
  const context = loadPwaContext();
  const aliasPlan = {
    version: 1,
    exercises: [{ name: "Bench Press", sets: [{ weight: 80, reps: 8 }] }, {
      name: "Жим штанги лежачи", sets: [{ weight: 80, reps: 8 }]
    }]
  };
  vm.runInContext(`
    socialState.inbox = parseSocialWorkoutInbox({
      version: 1,
      pendingIncomingCount: 1,
      incoming: [{
        inviteId: "wi_33333333333333333333333333333333",
        profileId: "p_22222222222222222222222222222222",
        displayName: "Friend",
        status: "pending",
        inviteRevision: 1,
        createdAt: "2026-08-09T12:00:00Z",
        expiresAt: "2026-08-16T12:00:00Z",
        respondedAt: null,
        summary: {
          exerciseCount: 2,
          setCount: 2,
          exerciseNames: ["Bench Press", "Жим штанги лежачи"]
        },
        workout: ${JSON.stringify(aliasPlan)}
      }],
      outgoing: []
    });
    activeWorkout = null;
    let unsafeAcceptMutationCount = 0;
    let unsafeAcceptToast = "";
    executeSocialMutation = async () => {
      unsafeAcceptMutationCount += 1;
      return null;
    };
    showToast = message => { unsafeAcceptToast = message; };
  `, context);
  await vm.runInContext(`respondWorkoutInvite({ dataset: {
    inviteId: "wi_33333333333333333333333333333333", decision: "accept", revision: "1"
  } })`, context);
  assert.equal(vm.runInContext("unsafeAcceptMutationCount", context), 0);
  assert.equal(vm.runInContext("socialState.inbox.incoming[0].status", context), "pending");
  assert.match(vm.runInContext("unsafeAcceptToast", context), /cannot be imported safely/);
});

test("accepted friend plan can be recovered after reload without another server mutation", () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 8;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    socialState.inbox = parseSocialWorkoutInbox({
      version: 1,
      pendingIncomingCount: 0,
      incoming: [{
        inviteId: "wi_33333333333333333333333333333333",
        profileId: "p_22222222222222222222222222222222",
        displayName: "Friend",
        status: "accepted",
        inviteRevision: 2,
        createdAt: "2026-08-09T12:00:00Z",
        expiresAt: "2026-08-16T12:00:00Z",
        respondedAt: "2026-08-09T12:05:00Z",
        summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
        workout: ${JSON.stringify(workout)}
      }],
      outgoing: []
    });
    activeWorkout = null;
    workoutDraft = null;
    pendingSharedWorkout = null;
    pendingSharedWorkoutOrigin = null;
    let recoveryMutationCount = 0;
    executeSocialMutation = async () => { recoveryMutationCount += 1; return null; };
    window.GymSharedWorkoutFlow = {
      prepareImport(plan, options) {
        return { status: "ready", draft: { startedAt: options.now, note: "", blocks: [{ exerciseName: plan.exercises[0].name, sets: plan.exercises[0].sets }] } };
      }
    };
    render = () => {};
    showToast = () => {};
  `, context);
  const opened = vm.runInContext(`openAcceptedWorkoutInvite({ dataset: {
    inviteId: "wi_33333333333333333333333333333333"
  } })`, context);
  assert.equal(opened, true);
  assert.equal(vm.runInContext("recoveryMutationCount", context), 0);
  assert.equal(vm.runInContext("workoutDraft.blocks[0].exerciseName", context), "Bench Press");
  assert.equal(vm.runInContext("sessionStorage.getItem(SHARED_WORKOUT_PENDING_KEY)", context), null);
});

test("active workout leaves a friend invitation pending without consuming it", async () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  vm.runInContext(`
    socialState.inbox = parseSocialWorkoutInbox({
      version: 1,
      pendingIncomingCount: 1,
      incoming: [{
        inviteId: "wi_33333333333333333333333333333333",
        profileId: "p_22222222222222222222222222222222",
        displayName: "Friend",
        status: "pending",
        inviteRevision: 1,
        createdAt: "2026-08-09T12:00:00Z",
        expiresAt: "2026-08-16T12:00:00Z",
        respondedAt: null,
        summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
        workout: ${JSON.stringify(workout)}
      }],
      outgoing: []
    });
    activeWorkout = { id: 9 };
    let inviteMutationCount = 0;
    let inviteBlockedToast = "";
    executeSocialMutation = async () => { inviteMutationCount += 1; return null; };
    showToast = message => { inviteBlockedToast = message; };
  `, context);
  await vm.runInContext(`respondWorkoutInvite({ dataset: {
    inviteId: "wi_33333333333333333333333333333333", decision: "accept", revision: "1"
  } })`, context);
  assert.equal(vm.runInContext("inviteMutationCount", context), 0);
  assert.match(vm.runInContext("inviteBlockedToast", context), /Finish or discard/);
  assert.equal(vm.runInContext("socialState.inbox.incoming[0].status", context), "pending");
});

test("mismatched workout acknowledgement fails closed without opening a returned plan", async () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 3;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    socialState.inbox = parseSocialWorkoutInbox({
      version: 1,
      pendingIncomingCount: 1,
      incoming: [{
        inviteId: "wi_33333333333333333333333333333333",
        profileId: "p_22222222222222222222222222222222",
        displayName: "Friend",
        status: "pending",
        inviteRevision: 1,
        createdAt: "2026-08-09T12:00:00Z",
        expiresAt: "2026-08-16T12:00:00Z",
        respondedAt: null,
        summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
        workout: ${JSON.stringify(workout)}
      }],
      outgoing: []
    });
    activeWorkout = null;
    pendingSharedWorkout = null;
    pendingSharedWorkoutOrigin = null;
    let mismatchRefreshCount = 0;
    let mismatchToast = "";
    socialRpc = async () => ({
      version: 1,
      inviteId: "wi_44444444444444444444444444444444",
      status: "accepted",
      inviteRevision: 2,
      workout: ${JSON.stringify(workout)}
    });
    refreshSocialData = async () => { mismatchRefreshCount += 1; };
    render = () => {};
    showToast = message => { mismatchToast = message; };
  `, context);
  await vm.runInContext(`respondWorkoutInvite({ dataset: {
    inviteId: "wi_33333333333333333333333333333333", decision: "accept", revision: "1"
  } })`, context);
  assert.equal(vm.runInContext("mismatchRefreshCount", context), 0);
  assert.equal(vm.runInContext("pendingSharedWorkout", context), null);
  assert.match(vm.runInContext("mismatchToast", context), /could not be completed safely/);
  assert.match(appSource, /parsed\.friendshipId !== friendshipId/);
  assert.match(appSource, /parsed\.profileId !== profileId/);
});

test("accepted friend plan preserves an existing draft until replacement confirmation", async () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 5;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    socialState.inbox = parseSocialWorkoutInbox({
      version: 1,
      pendingIncomingCount: 1,
      incoming: [{
        inviteId: "wi_33333333333333333333333333333333",
        profileId: "p_22222222222222222222222222222222",
        displayName: "Friend",
        status: "pending",
        inviteRevision: 1,
        createdAt: "2026-08-09T12:00:00Z",
        expiresAt: "2026-08-16T12:00:00Z",
        respondedAt: null,
        summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
        workout: ${JSON.stringify(workout)}
      }],
      outgoing: []
    });
    activeWorkout = null;
    workoutDraft = { startedAt: 1, note: "keep me", blocks: [{ exerciseName: "Squat", sets: [{ weight: 50, reps: 5 }] }] };
    window.GymSharedWorkoutFlow = {
      prepareImport(plan, options) {
        return options.hasDraft && !options.allowDraftReplacement
          ? { status: "confirm-replace" }
          : { status: "ready", draft: { startedAt: options.now, note: "", blocks: [] } };
      }
    };
    executeSocialMutation = async () => ({
      version: 1,
      inviteId: "wi_33333333333333333333333333333333",
      status: "accepted",
      inviteRevision: 2,
      workout: ${JSON.stringify(workout)}
    });
    refreshSocialData = async () => {};
    render = () => {};
  `, context);
  await vm.runInContext(`respondWorkoutInvite({ dataset: {
    inviteId: "wi_33333333333333333333333333333333", decision: "accept", revision: "1"
  } })`, context);
  assert.equal(vm.runInContext("workoutDraft.note", context), "keep me");
  assert.equal(vm.runInContext("modal.type", context), "confirm-shared-workout-replace");
  assert.deepEqual(jsonFrom(context, "pendingSharedWorkout"), workout);
  assert.equal(vm.runInContext("pendingSharedWorkoutOrigin.type", context), "social");
  assert.equal(vm.runInContext("sessionStorage.getItem(SHARED_WORKOUT_PENDING_KEY)", context), null);

  vm.runInContext("resetRemoteSyncContext()", context);
  assert.equal(vm.runInContext("pendingSharedWorkout", context), null);
  assert.equal(vm.runInContext("pendingSharedWorkoutOrigin", context), null);
  assert.equal(vm.runInContext("modal", context), null);
});

test("workout share chooser keeps link fallback and targets confirmed friends only", () => {
  const context = loadPwaContext();
  const dashboard = socialDashboardFixture();
  vm.runInContext(`
    remoteAuthEnabled = () => true;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    socialState = {
      status: "loaded",
      source: "test",
      dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
      inbox: null,
      error: ""
    };
    modal = { type: "workout-share", plan: ${JSON.stringify(sharedWorkoutFixture())}, url: "https://gymapptracker.com/workout/#workout=x" };
  `, context);
  const markup = vm.runInContext("workoutShareSheetMarkup()", context);
  assert.match(markup, /data-action="share-workout-link"/);
  assert.match(markup, /data-action="send-workout-invite"/);
  assert.match(markup, /p_22222222222222222222222222222222/);
  assert.match(markup, /not synchronized live/);
  assert.doesNotMatch(markup, /accountId|userId|private note|must-not-leak/);
});

test("an outcome-unknown workout invitation retries the exact client request id", async () => {
  const context = loadPwaContext();
  const dashboard = socialDashboardFixture();
  const workout = sharedWorkoutFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 12;
    window.crypto = { getRandomValues(bytes) { for (let index = 0; index < bytes.length; index += 1) bytes[index] = index + 1; return bytes; } };
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    socialState.dashboard = parseSocialDashboard(${JSON.stringify(dashboard)});
    modal = { type: "workout-share", plan: ${JSON.stringify(workout)}, url: "https://gymapptracker.com/workout/#workout=x" };
    let socialInviteAttempts = [];
    socialRpc = async (name, body) => {
      socialInviteAttempts.push({ name, body });
      if (socialInviteAttempts.length === 1) throw new Error("outcome unknown");
      return { version: 1, result: "submitted_or_unavailable" };
    };
    refreshSocialData = async () => {};
    render = () => {};
    showToast = () => {};
  `, context);
  const expression = `sendWorkoutInvite({ dataset: {
    profileId: "p_22222222222222222222222222222222"
  } })`;
  await vm.runInContext(expression, context);
  assert.equal(vm.runInContext("modal.type", context), "workout-share");
  assert.equal(vm.runInContext("socialWorkoutInviteRequests.size", context), 1);
  await vm.runInContext(expression, context);
  const attempts = jsonFrom(context, "socialInviteAttempts");
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0].name, "social_send_workout_invite");
  assert.equal(attempts[0].body.p_client_request_id, attempts[1].body.p_client_request_id);
  assert.match(attempts[0].body.p_client_request_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(vm.runInContext("socialWorkoutInviteRequests.size", context), 0);
  assert.equal(vm.runInContext("modal", context), null);
});

test("unresolved workout invitation ids are never evicted at the bounded capacity", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 14;
    window.crypto = { getRandomValues(bytes) { for (let index = 0; index < bytes.length; index += 1) bytes[index] = index + 1; return bytes; } };
    for (let index = 0; index < MAX_PENDING_SOCIAL_WORKOUT_REQUESTS; index += 1) {
      socialWorkoutInviteRequests.set("unknown-" + index, {
        key: "unknown-" + index,
        source: socialSourceKey(),
        fingerprint: "fingerprint-" + index,
        requestId: "11111111-1111-4111-8111-111111111111"
      });
    }
  `, context);
  const before = jsonFrom(context, "[...socialWorkoutInviteRequests.keys()]");
  assert.throws(
    () => vm.runInContext(`prepareSocialWorkoutInviteRequest(
      "p_22222222222222222222222222222222",
      ${JSON.stringify(sharedWorkoutFixture())}
    )`, context),
    /outcomes are still unknown/
  );
  assert.deepEqual(jsonFrom(context, "[...socialWorkoutInviteRequests.keys()]"), before);
});

test("saving unchanged friend privacy accepts the server no-op revision", async () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 13;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    app.querySelector = selector => ({ checked: selector !== "#social-share-records" });
    socialRpc = async () => ({
      version: 1,
      privacy: {
        allowRequests: true,
        shareProgress: true,
        shareRecentWorkouts: true,
        shareRecords: false
      },
      settingsRevision: 7
    });
    let privacyRefreshCount = 0;
    let privacyToast = "";
    refreshSocialData = async () => { privacyRefreshCount += 1; };
    render = () => {};
    showToast = message => { privacyToast = message; };
  `, context);
  await vm.runInContext(`saveSocialPrivacy({ dataset: { revision: "7" } })`, context);
  assert.equal(vm.runInContext("privacyRefreshCount", context), 1);
  assert.match(vm.runInContext("privacyToast", context), /visibility updated/);
});

test("lost remove and block responses immediately hide cached friend data", async () => {
  for (const action of ["remove", "block"]) {
    const context = loadPwaContext();
    const dashboard = socialDashboardFixture();
    vm.runInContext(`
      activeAccount = {
        id: "remote-11111111-1111-4111-8111-111111111111",
        userId: "11111111-1111-4111-8111-111111111111",
        remote: "supabase",
        name: "Owner"
      };
      accountEpoch = 15;
      loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
      socialState = {
        status: "loaded",
        source: socialSourceKey(),
        dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
        inbox: { version: 1, pendingIncomingCount: 0, incoming: [], outgoing: [] },
        error: ""
      };
      socialDetailState = {
        status: "loaded",
        source: socialSourceKey() + ":p_22222222222222222222222222222222",
        profileId: "p_22222222222222222222222222222222",
        value: { version: 1, private: "must disappear" },
        error: ""
      };
      modal = { type: "friend-detail", profileId: "p_22222222222222222222222222222222" };
      window.confirm = () => true;
      socialRpc = async () => { throw new Error("response lost after commit"); };
      let privacyRefreshAfterLoss = 0;
      refreshSocialData = async () => { privacyRefreshAfterLoss += 1; };
      render = () => {};
      showToast = () => {};
    `, context);
    if (action === "remove") {
      await vm.runInContext(`removeFriend({ dataset: {
        friendshipId: "f_22222222222222222222222222222222", revision: "3"
      } })`, context);
    } else {
      await vm.runInContext(`changeFriendBlock("p_22222222222222222222222222222222", true)`, context);
    }
    assert.equal(vm.runInContext("modal", context), null, `${action} must close detail`);
    assert.equal(vm.runInContext("socialState.dashboard", context), null, `${action} must clear dashboard`);
    assert.equal(vm.runInContext("socialState.inbox", context), null, `${action} must clear inbox`);
    assert.equal(vm.runInContext("socialDetailState.value", context), null, `${action} must clear detail`);
    assert.equal(vm.runInContext("privacyRefreshAfterLoss", context), 0);
  }
});

test("remove and block preserve the social mutation mutex", async () => {
  const context = loadPwaContext();
  const dashboard = socialDashboardFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 16;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    socialState = {
      status: "loaded",
      source: socialSourceKey(),
      dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
      inbox: { version: 1, pendingIncomingCount: 0, incoming: [], outgoing: [] },
      error: ""
    };
    socialMutationInProgress = true;
    let concurrentMutationRpcCalls = 0;
    socialRpc = async () => { concurrentMutationRpcCalls += 1; return null; };
    window.confirm = () => true;
  `, context);

  await vm.runInContext(`removeFriend({ dataset: {
    friendshipId: "f_22222222222222222222222222222222", revision: "3"
  } })`, context);
  await vm.runInContext(`changeFriendBlock("p_22222222222222222222222222222222", true)`, context);
  assert.equal(vm.runInContext("socialMutationInProgress", context), true);
  assert.equal(vm.runInContext("concurrentMutationRpcCalls", context), 0);
  assert.notEqual(vm.runInContext("socialState.dashboard", context), null);

  vm.runInContext("failCloseSocialPrivateCache()", context);
  assert.equal(vm.runInContext("socialMutationInProgress", context), true);
  assert.equal(vm.runInContext("socialState.dashboard", context), null);
  assert.equal(vm.runInContext("socialState.inbox", context), null);
});
