import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");
const stateContractSource = await readFile("pwa/state-contract.js", "utf8");
const russianTextSource = await readFile("pwa/russian-text.js", "utf8");
const exerciseSearchVocabularySource = await readFile("pwa/exercise-search-vocabulary.js", "utf8");
const sharedWorkoutSource = await readFile("pwa/shared-workout.js", "utf8");
const liveWorkoutSource = await readFile("pwa/live-workout.js", "utf8");
const liveWorkoutStateSource = await readFile("pwa/live-workout-state.js", "utf8");

function fakeIndexedDb(initialBinding = null) {
  const values = new Map(initialBinding ? [["current", initialBinding]] : []);
  let storeCreated = initialBinding !== null;
  const requestFor = (transaction, operation) => {
    const request = { result: undefined, error: null, onsuccess: null, onerror: null };
    transaction.pending += 1;
    queueMicrotask(() => {
      try {
        request.result = operation();
        request.onsuccess?.();
      } catch (error) {
        request.error = error;
        request.onerror?.();
        transaction.error = error;
        transaction.onerror?.();
        transaction.onabort?.();
      } finally {
        transaction.pending -= 1;
        if (transaction.pending === 0 && !transaction.error) {
          queueMicrotask(() => transaction.pending === 0 && transaction.oncomplete?.());
        }
      }
    });
    return request;
  };
  const database = {
    objectStoreNames: { contains: name => storeCreated && name === "current-bindings" },
    createObjectStore(name) {
      if (name !== "current-bindings" || storeCreated) throw new Error("invalid store");
      storeCreated = true;
    },
    transaction(name) {
      if (name !== "current-bindings" || !storeCreated) throw new Error("missing store");
      const transaction = {
        pending: 0,
        error: null,
        onabort: null,
        onerror: null,
        oncomplete: null,
        objectStore() {
          return {
            get: key => requestFor(transaction, () => values.get(key)),
            put: (value, key) => requestFor(transaction, () => values.set(key, value)),
            delete: key => requestFor(transaction, () => values.delete(key))
          };
        }
      };
      return transaction;
    },
    close() {}
  };
  return {
    open() {
      const request = {
        result: database,
        error: null,
        onupgradeneeded: null,
        onsuccess: null,
        onerror: null,
        onblocked: null
      };
      queueMicrotask(() => {
        if (!storeCreated) request.onupgradeneeded?.();
        request.onsuccess?.();
      });
      return request;
    },
    values
  };
}

function loadPwaContext({ userAgent = "", push = null, fetchImpl = null } = {}) {
  const values = new Map();
  const sessionValues = new Map();
  const indexedDB = fakeIndexedDb(push?.binding ?? null);
  const context = {
    console,
    Date,
    Map,
    Set,
    TextDecoder,
    TextEncoder,
    AbortController,
    AbortSignal,
    Headers,
    Response,
    URL,
    crypto,
    atob,
    btoa,
    URLSearchParams,
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {},
      indexedDB,
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
      removeItem: key => values.delete(key),
      entries: () => [...values.entries()]
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
    fetch: fetchImpl || (() => Promise.reject(new Error("network disabled in tests")))
  };
  if (push) {
    if (typeof push.registration.getNotifications !== "function") {
      push.registration.getNotifications = async () => [];
    }
    context.window.PushManager = function PushManager() {};
    context.window.Notification = push.notification;
    context.window.GYM_SUPABASE = {
      url: "https://project.supabase.co",
      anonKey: "sb_publishable_test_key",
      webPushVapidPublicKey: push.vapidPublicKey
    };
    context.navigator.serviceWorker = {
      ready: Promise.resolve(push.registration),
      getRegistration: async () => push.registration,
      register: async () => push.registration,
      addEventListener() {}
    };
  }
  context.window.document = context.document;
  context.window.navigator = context.navigator;
  context.window.history = context.history;
  context.window.localStorage = context.localStorage;
  context.window.sessionStorage = context.sessionStorage;
  context.window.crypto = context.crypto;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(sharedWorkoutSource, context);
  context.window.GymSharedWorkout = context.GymSharedWorkout;
  vm.runInContext(liveWorkoutSource, context);
  context.window.GymLiveWorkout = context.GymLiveWorkout;
  vm.runInContext(liveWorkoutStateSource, context);
  context.window.GymLiveWorkoutState = context.GymLiveWorkoutState;
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(russianTextSource, context);
  vm.runInContext(exerciseSearchVocabularySource, context);
  vm.runInContext(appSource, context);
  context.pushBindingValues = indexedDB.values;
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

function emptySocialWorkoutInboxPage() {
  return {
    version: 2,
    pendingIncomingCount: 0,
    incoming: [],
    outgoing: [],
    nextCursor: null
  };
}

function socialWorkoutInviteMetadataFixture({
  inviteId = `wi_${"3".repeat(32)}`,
  status = "pending",
  inviteRevision = status === "pending" ? 1 : 2,
  createdAt = "2026-08-09T12:00:00Z"
} = {}) {
  return {
    inviteId,
    profileId: `p_${"2".repeat(32)}`,
    displayName: "Friend",
    status,
    inviteRevision,
    createdAt,
    expiresAt: "2026-08-16T12:00:00Z",
    respondedAt: status === "pending" ? null : "2026-08-09T12:05:00Z",
    summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] }
  };
}

function activeLiveInboxFixture(roomId = `lr_${"a".repeat(32)}`) {
  return {
    version: 1,
    invitations: [],
    rooms: [{
      roomId,
      status: "active",
      roomRevision: 3,
      role: "participant",
      memberState: "joined",
      membershipRevision: 2,
      createdAt: "2026-08-10T08:00:00Z",
      startedAt: "2026-08-10T08:05:00Z",
      activeExpiresAt: "2026-08-11T08:05:00Z",
      summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
      peer: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" }
    }]
  };
}

function activeLiveSnapshotFixture(roomId = `lr_${"a".repeat(32)}`) {
  return {
    version: 1,
    room: {
      roomId,
      status: "active",
      roomRevision: 3,
      closeReason: null,
      createdAt: "2026-08-10T08:00:00Z",
      inviteExpiresAt: "2026-08-17T08:00:00Z",
      startedAt: "2026-08-10T08:05:00Z",
      activeExpiresAt: "2026-08-11T08:05:00Z",
      endedAt: null,
      summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] }
    },
    plan: {
      version: 1,
      exercises: [{
        exerciseId: "e_01",
        catalogKey: "bench_press",
        name: "Bench Press",
        sets: [{ setId: "s_01_01", weight: 80, reps: 8 }]
      }]
    },
    participants: [{
      isSelf: false,
      profile: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" },
      role: "owner",
      state: "joined",
      membershipRevision: 2,
      joinedAt: "2026-08-10T08:01:00Z",
      finishedAt: null,
      departedAt: null,
      progress: {
        version: 1,
        revision: 1,
        completedSets: [],
        undoableSetId: null,
        finishedAt: null
      }
    }, {
      isSelf: true,
      profile: { profileId: "p_11111111111111111111111111111111", displayName: "Me" },
      role: "participant",
      state: "joined",
      membershipRevision: 2,
      joinedAt: "2026-08-10T08:01:00Z",
      finishedAt: null,
      departedAt: null,
      progress: {
        version: 1,
        revision: 1,
        completedSets: [],
        undoableSetId: null,
        finishedAt: null
      }
    }]
  };
}

function testAccessToken(userId, sessionId) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode({
    sub: userId,
    session_id: sessionId,
    exp: 4102444800
  })}.test-signature`;
}

test("activity heatmap cells stay out of the tab order and expose useful labels", () => {
  const context = loadPwaContext();
  const html = vm.runInContext(`(() => {
    state = defaultAppState();
    const startedAt = Date.now();
    state.sessions = [{
      id: 1,
      startedAt,
      note: "",
      sets: [{
        id: 2,
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        weight: 50,
        reps: 8,
        orderIndex: 0
      }]
    }];
    return activityHeatmapCard();
  })()`, context);
  const cells = html.match(/<button[^>]*class="heat-cell[^"]*"[^>]*>/g) || [];
  const outsideCells = cells.filter(cell => /class="heat-cell outside"/.test(cell));
  const dayCells = cells.filter(cell => !/class="heat-cell outside"/.test(cell));

  assert.ok(cells.length >= 28 && cells.length <= 42);
  assert.ok(cells.every(cell => /tabindex="-1"/.test(cell)));
  assert.ok(outsideCells.length > 0);
  assert.ok(outsideCells.every(cell => /aria-hidden="true"/.test(cell)));
  assert.ok(dayCells.every(cell => /aria-disabled="true"/.test(cell)));
  assert.ok(dayCells.every(cell => /aria-label="[^"]+: \d+ load"/.test(cell)));
});

test("saved workout cards activate from Enter and Space", () => {
  const context = loadPwaContext();
  const html = vm.runInContext(`workoutItem({
    id: 10,
    startedAt: Date.now(),
    note: "",
    sets: [{
      id: 11,
      exerciseName: "Bench Press",
      catalogKey: "bench_press",
      weight: 50,
      reps: 8,
      orderIndex: 0
    }]
  })`, context);
  assert.match(html, /<article class="workout-item clickable" role="button" tabindex="0" data-action="open-detail"/);
  assert.match(appSource, /addEventListener\("keydown", activateDataActionFromKeyboard\)/);

  const activation = jsonFrom(context, `(() => {
    let clicks = 0;
    let prevented = 0;
    const currentTarget = { click() { clicks += 1; } };
    const event = key => ({
      key,
      currentTarget,
      preventDefault() { prevented += 1; }
    });
    return {
      enter: activateDataActionFromKeyboard(event("Enter")),
      space: activateDataActionFromKeyboard(event(" ")),
      escape: activateDataActionFromKeyboard(event("Escape")),
      clicks,
      prevented
    };
  })()`);
  assert.deepEqual(activation, {
    enter: true,
    space: true,
    escape: false,
    clicks: 2,
    prevented: 2
  });
});

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
    progressHubSection = "exercises";
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

test("Profile defaults to protected friends and keeps account tools in their own segment", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = { id: "local-v2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", name: "Profile Owner", localIdVersion: 2 };
    state = defaultAppState();
  `, context);
  const trainingProfile = vm.runInContext("friendsProfileScreen()", context);
  const settingsProfile = vm.runInContext('profileHubSection = "settings"; friendsProfileScreen()', context);
  const exercises = vm.runInContext("exercisesScreen()", context);

  assert.match(trainingProfile, /Profile Owner/);
  assert.match(trainingProfile, /Friends &amp; live|Friends & live/);
  assert.match(trainingProfile, /Cloud sign-in required/);
  assert.match(trainingProfile, /id="profile-settings-panel"[^>]*hidden/);
  assert.match(settingsProfile, /Profile Owner/);
  assert.match(settingsProfile, /support\.html/);
  assert.match(settingsProfile, /privacy-policy\.html/);
  assert.match(settingsProfile, /id="profile-training-panel"[^>]*hidden/);
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
    let socialInboxPageAbortObserved = false;
    let socialDetailAbortObserved = false;
    socialRequestId = 7;
    socialRequestController = { abort() { socialAbortObserved = true; } };
    socialWorkoutInboxPageRequestId = 13;
    socialWorkoutInboxPageRequestController = { abort() { socialInboxPageAbortObserved = true; } };
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
  assert.equal(vm.runInContext("socialInboxPageAbortObserved", context), true);
  assert.equal(vm.runInContext("socialDetailAbortObserved", context), true);
  assert.equal(vm.runInContext("socialRequestId", context), 8);
  assert.equal(vm.runInContext("socialWorkoutInboxPageRequestId", context), 14);
  assert.equal(vm.runInContext("socialDetailRequestId", context), 12);
  assert.deepEqual(jsonFrom(context, "socialState"), {
    status: "idle",
    source: null,
    dashboard: null,
    inbox: null,
    friendCode: null,
    inboxPageCount: 0,
    inboxLoadingMore: false,
    inboxLoadMoreError: "",
    workoutDetailPrivacy: null,
    workoutDetailPrivacySupported: false,
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

test("short friend codes stay separate from profile identity and normalize human input", () => {
  const context = loadPwaContext();
  assert.equal(
    vm.runInContext('parseSocialMyFriendCode({ version: 1, friendCode: "g_a1b2c3d4e5f6" })', context),
    "g_a1b2c3d4e5f6"
  );
  assert.equal(
    vm.runInContext('formatSocialFriendCode("g_a1b2c3d4e5f6")', context),
    "GYM-A1B2-C3D4-E5F6"
  );
  assert.equal(
    vm.runInContext('normalizeSocialFriendCodeInput("  GYM-A1B2-C3D4-E5F6  ")', context),
    "g_a1b2c3d4e5f6"
  );
  assert.equal(
    vm.runInContext('normalizeSocialFriendCodeInput("g_a1b2c3d4e5f6")', context),
    "g_a1b2c3d4e5f6"
  );
  assert.equal(
    vm.runInContext('normalizeSocialFriendCodeInput("p_11111111111111111111111111111111")', context),
    "p_11111111111111111111111111111111"
  );
  assert.equal(
    vm.runInContext('normalizeSocialFriendCodeInput(" ".repeat(65) + "GYM-A1B2-C3D4-E5F6")', context),
    null
  );
  assert.equal(
    vm.runInContext('normalizeSocialFriendCodeInput("€".repeat(43))', context),
    null
  );
  assert.equal(vm.runInContext('normalizeSocialFriendCodeInput("GYM-AAAA-BBBB")', context), null);
  assert.throws(
    () => vm.runInContext('parseSocialMyFriendCode({ version: 1, friendCode: "p_11111111111111111111111111111111" })', context),
    /friend code is invalid/
  );
  assert.throws(
    () => vm.runInContext('parseSocialMyFriendCode({ version: 1, friendCode: "g_a1b2c3d4e5f6", profileId: "p_11111111111111111111111111111111" })', context),
    /shape/
  );
  assert.throws(
    () => vm.runInContext('parseSocialMyFriendCode({ version: 1, friendCode: "g_A1B2C3D4E5F6" })', context),
    /friend code is invalid/
  );
  const normalizer = appSource.slice(
    appSource.indexOf("function normalizeSocialFriendCodeInput"),
    appSource.indexOf("function formatSocialFriendCode")
  );
  assert.ok(normalizer.indexOf("MAX_SOCIAL_FRIEND_CODE_INPUT_CHARACTERS") < normalizer.indexOf("value.trim()"));
  assert.ok(normalizer.indexOf("MAX_SOCIAL_FRIEND_CODE_INPUT_BYTES") < normalizer.indexOf("value.trim()"));
});

test("bounded PostgREST errors expose only a validated structured code", async () => {
  const requestError = async body => {
    const context = loadPwaContext({
      fetchImpl: async () => new Response(body, {
        status: 404,
        headers: { "Content-Type": "application/json" }
      })
    });
    vm.runInContext(`window.GYM_SUPABASE = {
      url: "https://project.supabase.co",
      anonKey: "sb_publishable_test_key"
    }`, context);
    try {
      await vm.runInContext(
        'supabaseRequest("/rest/v1/rpc/social_my_friend_code", { method: "POST", anonymous: true, body: "{}" })',
        context
      );
      assert.fail("request must reject");
    } catch (error) {
      return error;
    }
  };

  for (const code of ["PGRST202", "42883"]) {
    const error = await requestError(JSON.stringify({
      code,
      details: null,
      hint: null,
      message: "Function unavailable"
    }));
    assert.equal(error.status, 404);
    assert.equal(error.postgrestCode, code);
  }
  for (const body of [
    JSON.stringify({ message: "missing code" }),
    JSON.stringify({ code: "PGRST202", message: "extra field", extra: true }),
    JSON.stringify({ code: "not-a-code", message: "invalid code" }),
    "{malformed"
  ]) {
    const error = await requestError(body);
    assert.equal(error.status, 404);
    assert.equal(error.postgrestCode, undefined);
  }
  assert.equal(
    vm.runInContext(`parseBoundedPostgrestError(JSON.stringify({
      code: "PGRST202",
      message: "x".repeat(MAX_REMOTE_ERROR_RESPONSE_BYTES)
    }))`, loadPwaContext()),
    null
  );
});

test("human friend codes submit the compact locator and copy only the formatted public code", async () => {
  const context = loadPwaContext();
  const dashboard = socialDashboardFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 18;
    loadRemoteSession = () => ({ user: { id: activeAccount.userId } });
    socialState = {
      status: "loaded",
      source: socialSourceKey(),
      dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
      inbox: null,
      friendCode: "g_a1b2c3d4e5f6",
      error: ""
    };
    app.querySelector = selector => selector === "#social-friend-code"
      ? { value: "GYM-0A0B-1C1D-2E2F" }
      : null;
    let submittedFriendCode = null;
    socialRpc = async (name, body) => {
      submittedFriendCode = { name, body };
      return { version: 1, result: "submitted_or_unavailable" };
    };
    refreshSocialData = async () => {};
    render = () => {};
    showToast = () => {};
    let copiedFriendCode = null;
    navigator.clipboard = { writeText: async value => { copiedFriendCode = value; } };
  `, context);
  await vm.runInContext("sendFriendRequest()", context);
  assert.deepEqual(jsonFrom(context, "submittedFriendCode"), {
    name: "social_send_friend_request",
    body: { p_friend_code: "g_0a0b1c1d2e2f" }
  });
  assert.equal(await vm.runInContext("copyCurrentFriendCode()", context), true);
  assert.equal(vm.runInContext("copiedFriendCode", context), "GYM-A1B2-C3D4-E5F6");
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
      if (name === "social_my_friend_code") return { version: 1, friendCode: "g_a1b2c3d4e5f6" };
      if (name === "social_workout_detail_privacy") return {
        version: 1, shareWorkoutDetails: false, settingsRevision: 1
      };
      if (name === "social_workout_inbox_page") return ${JSON.stringify(emptySocialWorkoutInboxPage())};
      if (name === "social_friend_details") return ${JSON.stringify(refreshedDetail)};
      throw new Error("unexpected RPC");
    };
    render = () => {};
  `, context);
  await vm.runInContext("refreshSocialData(true)", context);
  const value = jsonFrom(context, "socialDetailState.value");
  assert.equal(vm.runInContext("socialState.friendCode", context), "g_a1b2c3d4e5f6");
  assert.equal(value.sharing.recentWorkouts, false);
  assert.equal(value.sharing.records, false);
  assert.deepEqual(value.recentWorkouts, []);
  assert.doesNotMatch(JSON.stringify(value), /stale private row/);
});

test("friend-code refresh falls back only for validated missing-function errors and drops late account results", async () => {
  const dashboard = socialDashboardFixture();
  dashboard.pendingWorkoutInviteCount = 0;
  const inbox = { version: 1, pendingIncomingCount: 0, incoming: [], outgoing: [] };

  for (const missingCode of ["PGRST202", "42883"]) {
    const fallbackContext = loadPwaContext();
    vm.runInContext(`
      activeAccount = {
        id: "remote-11111111-1111-4111-8111-111111111111",
        userId: "11111111-1111-4111-8111-111111111111",
        remote: "supabase",
        name: "Owner"
      };
      accountEpoch = 20;
      remoteAuthEnabled = () => true;
      loadRemoteSession = () => ({ user: { id: activeAccount.userId } });
      render = () => {};
      socialRpc = async name => {
        if (name === "social_dashboard") return ${JSON.stringify(dashboard)};
        if (name === "social_workout_inbox_page") return ${JSON.stringify(emptySocialWorkoutInboxPage())};
        if (name === "social_workout_detail_privacy") return {
          version: 1, shareWorkoutDetails: false, settingsRevision: 1
        };
        if (name === "social_my_friend_code") {
          const error = new Error("missing function");
          error.status = 404;
          error.postgrestCode = ${JSON.stringify(missingCode)};
          throw error;
        }
        throw new Error("unexpected RPC");
      };
    `, fallbackContext);
    await vm.runInContext("refreshSocialData(true)", fallbackContext);
    assert.equal(vm.runInContext("socialState.status", fallbackContext), "loaded");
    assert.equal(
      vm.runInContext("socialState.friendCode", fallbackContext),
      dashboard.self.friendCode
    );
  }

  const rejectedFallbacks = [
    { label: "code-less 404", status: 404 },
    { label: "other 404", status: 404, code: "PGRST205" },
    { label: "invalid JWT", status: 401, code: "PGRST301" },
    { label: "service unavailable", status: 503, code: "PGRST000" },
    { label: "network failure" },
    { label: "malformed 2xx", value: { version: 1, friendCode: "g_A1B2C3D4E5F6" } }
  ];
  for (const scenario of rejectedFallbacks) {
    const failedContext = loadPwaContext();
    vm.runInContext(`
      const friendCodeFailureScenario = ${JSON.stringify(scenario)};
      activeAccount = {
        id: "remote-11111111-1111-4111-8111-111111111111",
        userId: "11111111-1111-4111-8111-111111111111",
        remote: "supabase",
        name: "Owner"
      };
      accountEpoch = 20;
      remoteAuthEnabled = () => true;
      loadRemoteSession = () => ({ user: { id: activeAccount.userId } });
      render = () => {};
      socialRpc = async name => {
        if (name === "social_dashboard") return ${JSON.stringify(dashboard)};
        if (name === "social_workout_inbox_page") return ${JSON.stringify(emptySocialWorkoutInboxPage())};
        if (name === "social_my_friend_code") {
          if (Object.hasOwn(friendCodeFailureScenario, "value")) {
            return friendCodeFailureScenario.value;
          }
          const error = new Error(friendCodeFailureScenario.label);
          if (Object.hasOwn(friendCodeFailureScenario, "status")) error.status = friendCodeFailureScenario.status;
          if (friendCodeFailureScenario.code) error.postgrestCode = friendCodeFailureScenario.code;
          throw error;
        }
        throw new Error("unexpected RPC");
      };
    `, failedContext);
    await vm.runInContext("refreshSocialData(true)", failedContext);
    assert.equal(
      vm.runInContext("socialState.status", failedContext),
      "error",
      scenario.label
    );
    assert.equal(vm.runInContext("socialState.dashboard", failedContext), null, scenario.label);
    assert.equal(vm.runInContext("socialState.friendCode", failedContext), null, scenario.label);
  }

  const staleContext = loadPwaContext();
  vm.runInContext(`
    let socialCodeResolve;
    let sessionUserId = "11111111-1111-4111-8111-111111111111";
    const delayedSocialCode = new Promise(resolve => { socialCodeResolve = resolve; });
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: sessionUserId,
      remote: "supabase",
      name: "Owner A"
    };
    accountEpoch = 21;
    remoteAuthEnabled = () => true;
    loadRemoteSession = () => ({ user: { id: sessionUserId } });
    render = () => {};
    socialRpc = async name => {
      if (name === "social_dashboard") return ${JSON.stringify(dashboard)};
      if (name === "social_workout_inbox_page") return ${JSON.stringify(emptySocialWorkoutInboxPage())};
      if (name === "social_my_friend_code") return delayedSocialCode;
      throw new Error("unexpected RPC");
    };
  `, staleContext);
  const staleRefresh = vm.runInContext("refreshSocialData(true)", staleContext);
  await new Promise(resolve => setTimeout(resolve, 0));
  vm.runInContext(`
    accountEpoch += 1;
    sessionUserId = "22222222-2222-4222-8222-222222222222";
    activeAccount = {
      id: "remote-22222222-2222-4222-8222-222222222222",
      userId: sessionUserId,
      remote: "supabase",
      name: "Owner B"
    };
    socialCodeResolve({ version: 1, friendCode: "g_a1b2c3d4e5f6" });
  `, staleContext);
  await staleRefresh;
  assert.equal(vm.runInContext("socialState.friendCode", staleContext), null);
  assert.equal(vm.runInContext("socialState.dashboard", staleContext), null);
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

test("metadata workout inbox pages exclude exact plans and validate the pending cursor tuple", () => {
  const context = loadPwaContext();
  const incoming = Array.from({ length: 10 }, (_, index) => socialWorkoutInviteMetadataFixture({
    inviteId: `wi_${index.toString(16).padStart(32, "0")}`,
    createdAt: new Date(Date.UTC(2026, 7, 9, 12, 0, 10 - index)).toISOString()
  }));
  const last = incoming.at(-1);
  const page = {
    version: 2,
    pendingIncomingCount: 20,
    incoming,
    outgoing: [],
    nextCursor: { createdAt: last.createdAt, inviteId: last.inviteId, pending: true }
  };
  const parsed = jsonFrom(context, `parseSocialWorkoutInboxPage(${JSON.stringify(page)})`);
  assert.equal(parsed.version, 2);
  assert.equal(parsed.incoming.length, 10);
  assert.equal(Object.hasOwn(parsed.incoming[0], "workout"), false);
  assert.deepEqual(parsed.nextCursor, page.nextCursor);

  const leaked = structuredClone(page);
  leaked.incoming[0].workout = sharedWorkoutFixture();
  assert.throws(
    () => vm.runInContext(`parseSocialWorkoutInboxPage(${JSON.stringify(leaked)})`, context),
    /shape/
  );
  const incompleteCursor = structuredClone(page);
  delete incompleteCursor.nextCursor.pending;
  assert.throws(
    () => vm.runInContext(`parseSocialWorkoutInboxPage(${JSON.stringify(incompleteCursor)})`, context),
    /shape/
  );
  const wrongPendingCursor = structuredClone(page);
  wrongPendingCursor.nextCursor.pending = false;
  assert.throws(
    () => vm.runInContext(`parseSocialWorkoutInboxPage(${JSON.stringify(wrongPendingCursor)})`, context),
    /cursor is inconsistent/
  );
});

test("metadata inbox uses the four-argument stable cursor and legacy fallback only for a missing RPC", async () => {
  const context = loadPwaContext();
  const firstIncoming = Array.from({ length: 10 }, (_, index) => socialWorkoutInviteMetadataFixture({
    inviteId: `wi_${(index + 1).toString(16).padStart(32, "0")}`,
    createdAt: new Date(Date.UTC(2026, 7, 9, 12, 0, 20 - index)).toISOString()
  }));
  const last = firstIncoming.at(-1);
  const firstPage = {
    version: 2,
    pendingIncomingCount: 20,
    incoming: firstIncoming,
    outgoing: [],
    nextCursor: { createdAt: last.createdAt, inviteId: last.inviteId, pending: true }
  };
  vm.runInContext(`
    const boundedInboxCalls = [];
    socialRpc = async (name, body) => {
      boundedInboxCalls.push({ name, body });
      if (name !== "social_workout_inbox_page") throw new Error("unexpected legacy fallback");
      return ${JSON.stringify(firstPage)};
    };
  `, context);
  const parsed = await vm.runInContext("loadSocialWorkoutInbox({ user: { id: 'test' } }, undefined)", context);
  assert.equal(parsed.version, 2);
  assert.equal(parsed.incoming.length, 10);
  assert.deepEqual(JSON.parse(JSON.stringify(parsed.nextCursor)), firstPage.nextCursor);
  assert.deepEqual(jsonFrom(context, "boundedInboxCalls.map(call => call.body)"), [{
    p_cursor_created_at: null,
    p_cursor_invite_id: null,
    p_cursor_pending: null,
    p_limit: 10
  }]);

  for (const postgrestCode of ["PGRST202", "42883"]) {
    const fallbackContext = loadPwaContext();
    vm.runInContext(`
      const legacyFallbackCalls = [];
      socialRpc = async name => {
        legacyFallbackCalls.push(name);
        if (name === "social_workout_inbox_page") {
          const error = new Error("missing page RPC");
          error.status = 404;
          error.postgrestCode = ${JSON.stringify(postgrestCode)};
          throw error;
        }
        if (name === "social_workout_inbox") {
          return { version: 1, pendingIncomingCount: 0, incoming: [], outgoing: [] };
        }
        throw new Error("unexpected RPC");
      };
    `, fallbackContext);
    const fallback = await vm.runInContext(
      "loadSocialWorkoutInbox({ user: { id: 'test' } }, undefined)",
      fallbackContext
    );
    assert.equal(fallback.version, 1);
    assert.deepEqual(jsonFrom(fallbackContext, "legacyFallbackCalls"), [
      "social_workout_inbox_page",
      "social_workout_inbox"
    ]);
  }

  const deniedFallbackContext = loadPwaContext();
  vm.runInContext(`
    const deniedFallbackCalls = [];
    socialRpc = async name => {
      deniedFallbackCalls.push(name);
      const error = new Error("ordinary not found");
      error.status = 404;
      error.postgrestCode = "PGRST205";
      throw error;
    };
  `, deniedFallbackContext);
  await assert.rejects(vm.runInContext(
    "loadSocialWorkoutInbox({ user: { id: 'test' } }, undefined)",
    deniedFallbackContext
  ));
  assert.deepEqual(jsonFrom(deniedFallbackContext, "deniedFallbackCalls"), [
    "social_workout_inbox_page"
  ]);
});

test("workout inbox loads one explicit second page, keeps the outgoing snapshot exact, and stops at 20", async () => {
  const context = loadPwaContext();
  const incomingPage = (start, end) => Array.from({ length: end - start + 1 }, (_, offset) => {
    const value = start + offset;
    return socialWorkoutInviteMetadataFixture({
      inviteId: `wi_${value.toString(16).padStart(32, "0")}`,
      createdAt: new Date(Date.UTC(2026, 7, 9, 12, 0, 21 - value)).toISOString()
    });
  });
  const firstIncoming = incomingPage(1, 10);
  const secondIncoming = incomingPage(11, 20);
  const outgoing = [socialWorkoutInviteMetadataFixture({
    inviteId: `wi_${"f".repeat(32)}`,
    createdAt: "2026-08-09T12:00:30.000Z"
  })];
  const firstPage = {
    version: 2,
    pendingIncomingCount: 20,
    incoming: firstIncoming,
    outgoing,
    nextCursor: {
      createdAt: firstIncoming.at(-1).createdAt,
      inviteId: firstIncoming.at(-1).inviteId,
      pending: true
    }
  };
  const secondPage = {
    version: 2,
    pendingIncomingCount: 20,
    incoming: secondIncoming,
    outgoing,
    nextCursor: null
  };
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 17;
    loadRemoteSession = () => ({
      access_token: "bounded-session-token",
      user: { id: activeAccount.userId }
    });
    socialState = {
      ...socialState,
      status: "loaded",
      source: "test-source",
      inbox: parseSocialWorkoutInboxPage(${JSON.stringify(firstPage)}),
      inboxPageCount: 1,
      inboxLoadingMore: false,
      inboxLoadMoreError: ""
    };
    const explicitLoadMoreMarkup = socialWorkoutInviteRows();
    const loadMoreCalls = [];
    socialRpc = async (name, body) => {
      loadMoreCalls.push({ name, body });
      return ${JSON.stringify(secondPage)};
    };
    render = () => {};
  `, context);

  assert.match(vm.runInContext("explicitLoadMoreMarkup", context), /data-action="load-more-workout-invites"/);
  assert.match(vm.runInContext("explicitLoadMoreMarkup", context), />Load more</);
  assert.equal(await vm.runInContext("loadMoreSocialWorkoutInbox()", context), true);
  assert.equal(vm.runInContext("socialState.inbox.incoming.length", context), 20);
  assert.equal(vm.runInContext("socialState.inbox.outgoing.length", context), 1);
  assert.equal(vm.runInContext("socialState.inboxPageCount", context), 2);
  assert.equal(vm.runInContext("socialState.inbox.nextCursor", context), null);
  assert.equal(vm.runInContext("socialWorkoutInboxCanLoadMore()", context), false);
  assert.deepEqual(jsonFrom(context, "loadMoreCalls"), [{
    name: "social_workout_inbox_page",
    body: {
      p_cursor_created_at: firstPage.nextCursor.createdAt,
      p_cursor_invite_id: firstPage.nextCursor.inviteId,
      p_cursor_pending: true,
      p_limit: 10
    }
  }]);

  const changedOutgoingPage = structuredClone(secondPage);
  changedOutgoingPage.outgoing[0].inviteRevision = 2;
  assert.throws(() => vm.runInContext(
    `mergeSocialWorkoutInboxPage(
      parseSocialWorkoutInboxPage(${JSON.stringify(firstPage)}),
      parseSocialWorkoutInboxPage(${JSON.stringify(changedOutgoingPage)})
    )`,
    context
  ), /snapshot changed/);

  vm.runInContext(`
    socialState = {
      ...socialState,
      status: "loaded",
      source: "test-source",
      inbox: parseSocialWorkoutInboxPage(${JSON.stringify(firstPage)}),
      inboxPageCount: 1,
      inboxLoadingMore: false,
      inboxLoadMoreError: ""
    };
    let snapshotRestartCount = 0;
    socialRpc = async () => (${JSON.stringify(changedOutgoingPage)});
    refreshSocialData = async force => {
      if (!force) throw new Error("snapshot restart must be authoritative");
      snapshotRestartCount += 1;
      socialState = {
        ...socialState,
        status: "loaded",
        inbox: parseSocialWorkoutInboxPage(${JSON.stringify(firstPage)}),
        inboxPageCount: 1,
        inboxLoadingMore: false,
        inboxLoadMoreError: ""
      };
      return true;
    };
  `, context);
  assert.equal(await vm.runInContext("loadMoreSocialWorkoutInbox()", context), true);
  assert.equal(vm.runInContext("snapshotRestartCount", context), 1);
  assert.equal(vm.runInContext("socialState.inbox.incoming.length", context), 10);
  assert.equal(vm.runInContext("socialState.inboxPageCount", context), 1);

  vm.runInContext(`
    socialState = {
      ...socialState,
      inbox: parseSocialWorkoutInboxPage(${JSON.stringify(firstPage)}),
      inboxPageCount: 1,
      inboxLoadingMore: false,
      inboxLoadMoreError: ""
    };
    loadRemoteSession = () => ({
      access_token: "session-before-refresh",
      user: { id: activeAccount.userId }
    });
    let releaseStaleInboxPage;
    socialRpc = () => new Promise(resolve => { releaseStaleInboxPage = resolve; });
  `, context);
  const staleLoad = vm.runInContext("loadMoreSocialWorkoutInbox()", context);
  vm.runInContext(`
    loadRemoteSession = () => ({
      access_token: "session-after-refresh",
      user: { id: activeAccount.userId }
    });
    releaseStaleInboxPage(${JSON.stringify(secondPage)});
  `, context);
  assert.equal(await staleLoad, false);
  assert.equal(vm.runInContext("socialState.inbox.incoming.length", context), 10);
  assert.equal(vm.runInContext("socialState.inboxLoadingMore", context), false);
});

test("metadata invite acceptance fetches the exact revision once per winning action and never duplicates mutation", async () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  const invite = socialWorkoutInviteMetadataFixture();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 40;
    loadRemoteSession = () => ({
      access_token: ${JSON.stringify(testAccessToken(
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222"
      ))},
      user: { id: activeAccount.userId }
    });
    socialState.inbox = parseSocialWorkoutInboxPage({
      version: 2,
      pendingIncomingCount: 1,
      incoming: [${JSON.stringify(invite)}],
      outgoing: [],
      nextCursor: null
    });
    activeWorkout = null;
    workoutDraft = null;
    let exactPlanReads = 0;
    let acceptMutations = 0;
    let acceptedRefreshes = 0;
    socialRpc = async (name, body) => {
      if (name === "social_workout_invite_plan") {
        exactPlanReads += 1;
        return {
          version: 1,
          inviteId: body.p_invite_id,
          inviteRevision: body.p_expected_revision,
          workout: ${JSON.stringify(workout)}
        };
      }
      if (name === "social_respond_workout_invite") {
        acceptMutations += 1;
        return {
          version: 1,
          inviteId: body.p_invite_id,
          status: "accepted",
          inviteRevision: 2,
          workout: ${JSON.stringify(workout)}
        };
      }
      throw new Error("unexpected RPC");
    };
    refreshSocialData = async () => { acceptedRefreshes += 1; };
    window.GymSharedWorkoutFlow = {
      prepareImport(plan, options) {
        return {
          status: "ready",
          draft: {
            startedAt: options.now,
            note: "",
            blocks: [{ exerciseName: plan.exercises[0].name, sets: plan.exercises[0].sets }]
          }
        };
      }
    };
    render = () => {};
    showToast = () => {};
  `, context);
  const results = await vm.runInContext(`Promise.all([
    respondWorkoutInvite({ dataset: {
      inviteId: "${invite.inviteId}", decision: "accept", revision: "1"
    } }),
    respondWorkoutInvite({ dataset: {
      inviteId: "${invite.inviteId}", decision: "accept", revision: "1"
    } })
  ])`, context);
  assert.equal(results.filter(Boolean).length, 1);
  assert.equal(vm.runInContext("exactPlanReads", context), 2);
  assert.equal(vm.runInContext("acceptMutations", context), 1);
  assert.equal(vm.runInContext("acceptedRefreshes", context), 1);
  assert.equal(vm.runInContext("workoutDraft.blocks[0].exerciseName", context), "Bench Press");
});

test("metadata accepted invite recovery reauthorizes the exact plan without another mutation", async () => {
  const context = loadPwaContext();
  const workout = sharedWorkoutFixture();
  const invite = socialWorkoutInviteMetadataFixture({ status: "accepted", inviteRevision: 2 });
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 41;
    loadRemoteSession = () => ({ access_token: "session-a", user: { id: activeAccount.userId } });
    socialState.inbox = parseSocialWorkoutInboxPage({
      version: 2,
      pendingIncomingCount: 0,
      incoming: [${JSON.stringify(invite)}],
      outgoing: [],
      nextCursor: null
    });
    activeWorkout = null;
    workoutDraft = null;
    let recoveryPlanReads = 0;
    let recoveryMutations = 0;
    socialRpc = async (name, body) => {
      if (name === "social_workout_invite_plan") {
        recoveryPlanReads += 1;
        return {
          version: 1,
          inviteId: body.p_invite_id,
          inviteRevision: body.p_expected_revision,
          workout: ${JSON.stringify(workout)}
        };
      }
      recoveryMutations += 1;
      throw new Error("recovery must not mutate");
    };
    window.GymSharedWorkoutFlow = {
      prepareImport(plan, options) {
        return {
          status: "ready",
          draft: {
            startedAt: options.now,
            note: "",
            blocks: [{ exerciseName: plan.exercises[0].name, sets: plan.exercises[0].sets }]
          }
        };
      }
    };
    render = () => {};
    showToast = () => {};
  `, context);
  assert.equal(await vm.runInContext(`openAcceptedWorkoutInvite({ dataset: {
    inviteId: "${invite.inviteId}"
  } })`, context), true);
  assert.equal(vm.runInContext("recoveryPlanReads", context), 1);
  assert.equal(vm.runInContext("recoveryMutations", context), 0);
  assert.equal(vm.runInContext("workoutDraft.blocks[0].exerciseName", context), "Bench Press");
});

test("exact invite plan reads are account and session fenced with one neutral privacy fallback", async () => {
  const context = loadPwaContext();
  const invite = socialWorkoutInviteMetadataFixture();
  vm.runInContext(`
    let detailResolve;
    const delayedDetail = new Promise(resolve => { detailResolve = resolve; });
    let sessionUserId = "11111111-1111-4111-8111-111111111111";
    let sessionAccessToken = "session-a";
    activeAccount = {
      id: "remote-" + sessionUserId,
      userId: sessionUserId,
      remote: "supabase",
      name: "Owner A"
    };
    accountEpoch = 50;
    loadRemoteSession = () => ({ access_token: sessionAccessToken, user: { id: sessionUserId } });
    socialState.inbox = parseSocialWorkoutInboxPage({
      version: 2,
      pendingIncomingCount: 1,
      incoming: [${JSON.stringify(invite)}],
      outgoing: [],
      nextCursor: null
    });
    activeWorkout = null;
    let staleAcceptMutations = 0;
    socialRpc = async name => {
      if (name === "social_workout_invite_plan") return delayedDetail;
      if (name === "social_respond_workout_invite") {
        staleAcceptMutations += 1;
        throw new Error("stale mutation must not run");
      }
      throw new Error("unexpected RPC");
    };
    render = () => {};
    showToast = () => {};
  `, context);
  const staleAction = vm.runInContext(`respondWorkoutInvite({ dataset: {
    inviteId: "${invite.inviteId}", decision: "accept", revision: "1"
  } })`, context);
  await new Promise(resolve => setTimeout(resolve, 0));
  vm.runInContext(`
    sessionAccessToken = "session-b";
    detailResolve({
      version: 1,
      inviteId: "${invite.inviteId}",
      inviteRevision: 1,
      workout: ${JSON.stringify(sharedWorkoutFixture())}
    });
  `, context);
  assert.equal(await staleAction, false);
  assert.equal(vm.runInContext("staleAcceptMutations", context), 0);

  const privacyContext = loadPwaContext();
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 51;
    loadRemoteSession = () => ({ user: { id: activeAccount.userId } });
    socialState.inbox = parseSocialWorkoutInboxPage({
      version: 2,
      pendingIncomingCount: 1,
      incoming: [${JSON.stringify(invite)}],
      outgoing: [],
      nextCursor: null
    });
    activeWorkout = null;
    let privacyMutations = 0;
    let privacyRefreshes = 0;
    let privacyToast = "";
    socialRpc = async name => {
      if (name === "social_workout_invite_plan") {
        const error = new Error("private resource changed");
        error.status = 404;
        error.postgrestCode = "P0002";
        throw error;
      }
      if (name === "social_respond_workout_invite") privacyMutations += 1;
      throw new Error("unexpected RPC");
    };
    refreshSocialData = async () => { privacyRefreshes += 1; };
    render = () => {};
    showToast = message => { privacyToast = message; };
  `, privacyContext);
  assert.equal(await vm.runInContext(`respondWorkoutInvite({ dataset: {
    inviteId: "${invite.inviteId}", decision: "accept", revision: "1"
  } })`, privacyContext), false);
  assert.equal(vm.runInContext("privacyMutations", privacyContext), 0);
  assert.equal(vm.runInContext("privacyRefreshes", privacyContext), 1);
  assert.equal(
    vm.runInContext("privacyToast", privacyContext),
    "Friends changed. Current account data was refreshed."
  );
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
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 7;
    loadRemoteSession = () => ({ user: { id: activeAccount.userId } });
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

test("accepted friend plan can be recovered after reload without another server mutation", async () => {
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
    loadRemoteSession = () => ({
      access_token: ${JSON.stringify(testAccessToken(
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222"
      ))},
      user: { id: "11111111-1111-4111-8111-111111111111" }
    });
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
  const opened = await vm.runInContext(`openAcceptedWorkoutInvite({ dataset: {
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
    showToast = () => {};
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
  assert.match(markup, /data-action="send-live-workout-invite"/);
  assert.match(markup, /p_22222222222222222222222222222222/);
  assert.match(markup, /Live starts for both people as soon as the friend joins and keeps set progress synchronized/);
  assert.doesNotMatch(markup, /accountId|userId|private note|must-not-leak/);
});

test("live gateway uses the versioned Edge envelope and binds the response parser", async () => {
  const context = loadPwaContext();
  const result = await vm.runInContext(`
    capturedLiveGateway = null;
    supabaseRequest = async (path, options) => {
      capturedLiveGateway = { path, options };
      return {
        version: 1,
        result: {
          version: 1,
          result: "submitted",
          roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          status: "waiting",
          roomRevision: 1
        }
      };
    };
    liveGateway("live_send_invite", {
      profileId: "p_22222222222222222222222222222222",
      clientRequestId: "33333333-3333-4333-8333-333333333333",
      workout: ${JSON.stringify(sharedWorkoutFixture())}
    }, window.GymLiveWorkout.sendResult)
  `, context);
  assert.equal(result.roomId, "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
  const captured = jsonFrom(context, "capturedLiveGateway");
  assert.equal(captured.path, "/functions/v1/social-live-gateway");
  assert.deepEqual(JSON.parse(captured.options.body), {
    version: 1,
    action: "live_send_invite",
    payload: {
      profileId: "p_22222222222222222222222222222222",
      clientRequestId: "33333333-3333-4333-8333-333333333333",
      workout: sharedWorkoutFixture()
    }
  });
});

test("unknown live invitation outcomes reuse ids and never evict at capacity", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    liveSourceKey = () => "cloud:test";
    newUuidV4 = (() => {
      let value = 0;
      return () => "00000000-0000-4000-8000-" + String(++value).padStart(12, "0");
    })();
  `, context);
  const first = jsonFrom(context, `prepareLiveRequest(liveWorkoutInviteRequests, {
    profileId: "p_22222222222222222222222222222222",
    workout: ${JSON.stringify(sharedWorkoutFixture())}
  })`);
  const retry = jsonFrom(context, `prepareLiveRequest(liveWorkoutInviteRequests, {
    profileId: "p_22222222222222222222222222222222",
    workout: ${JSON.stringify(sharedWorkoutFixture())}
  })`);
  assert.equal(retry.requestId, first.requestId);
  vm.runInContext(`
    for (let index = 1; index < MAX_PENDING_LIVE_REQUESTS; index += 1) {
      prepareLiveRequest(liveWorkoutInviteRequests, { profileId: "p_" + String(index).padStart(32, "0") });
    }
  `, context);
  assert.equal(vm.runInContext("liveWorkoutInviteRequests.size", context), 25);
  assert.throws(() => vm.runInContext(
    `prepareLiveRequest(liveWorkoutInviteRequests, { profileId: "p_99999999999999999999999999999999" })`,
    context
  ));
  assert.equal(jsonFrom(context, `liveWorkoutInviteRequests.get(${JSON.stringify(first.key)})`).requestId, first.requestId);
});

test("live invitation UI escapes friend data and exposes Start together or decline only", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    liveWorkoutState = {
      status: "loaded",
      source: "test",
      error: "",
      snapshot: null,
      inbox: window.GymLiveWorkout.inbox({
        version: 1,
        invitations: [{
          roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          status: "waiting",
          roomRevision: 1,
          createdAt: "2026-08-10T08:00:00Z",
          inviteExpiresAt: "2026-08-10T08:30:00Z",
          summary: { exerciseCount: 1, setCount: 2, exerciseNames: ["Bench Press"] },
          owner: { profileId: "p_22222222222222222222222222222222", displayName: "<Friend>" }
        }],
        rooms: []
      })
    };
  `, context);
  const markup = vm.runInContext("liveWorkoutInboxMarkup()", context);
  assert.match(markup, /&lt;Friend&gt;/);
  assert.match(markup, /data-action="respond-live-invite" data-decision="accept"/);
  assert.match(markup, />Start together<\/button>/);
  assert.match(markup, /data-decision="decline"/);
  assert.doesNotMatch(markup, /data-action="start-live-room"/);
  assert.doesNotMatch(markup, /<Friend>|userId|sessionId|completedSets/);
});

test("live room renders escaped per-exercise self and peer set lanes", () => {
  const context = loadPwaContext();
  const snapshot = activeLiveSnapshotFixture();
  snapshot.room.summary.setCount = 2;
  snapshot.room.summary.exerciseNames = ["<Bench & Row>"];
  snapshot.plan.exercises[0].name = "<Bench & Row>";
  snapshot.plan.exercises[0].sets.push({ setId: "s_01_02", weight: 70, reps: 10 });
  snapshot.participants[0].profile.displayName = "<Friend>";
  snapshot.participants[0].progress.completedSets = [{
    setId: "s_01_01",
    weight: 80,
    reps: 8,
    completedAt: "2026-08-10T08:10:00Z"
  }];
  snapshot.participants[0].progress.undoableSetId = "s_01_01";
  snapshot.participants[1].progress.completedSets = [{
    setId: "s_01_02",
    weight: 70,
    reps: 10,
    completedAt: "2026-08-10T08:11:00Z"
  }];
  snapshot.participants[1].progress.undoableSetId = "s_01_02";
  vm.runInContext(`
    state.language = "uk";
    matrixSnapshot = window.GymLiveWorkout.snapshot(${JSON.stringify(snapshot)});
  `, context);

  const markup = vm.runInContext("liveWorkoutExerciseMatrixMarkup(matrixSnapshot)", context);
  assert.match(markup, /&lt;Bench &amp; Row&gt;/);
  assert.match(markup, /data-live-lane="self"[^]*?<strong role="rowheader">Ти<\/strong>/);
  assert.match(markup, /data-live-lane="peer"[^]*?<strong role="rowheader">&lt;Friend&gt;<\/strong>/);
  assert.match(markup, /data-live-lane="self"[^]*?data-live-set-state="pending"[^]*?data-live-set-state="completed"/);
  assert.match(markup, /data-live-lane="peer"[^]*?data-live-set-state="completed"[^]*?data-live-set-state="pending"/);
  assert.match(markup, /aria-label="Підхід 2: Записано"/);
  assert.doesNotMatch(markup, /<Bench & Row>|<Friend>|userId|sessionId/);

  vm.runInContext(`state.language = "ru"`, context);
  const russianMarkup = vm.runInContext(
    "liveWorkoutExerciseMatrixMarkup(matrixSnapshot)",
    context
  );
  assert.match(russianMarkup, /Прогресс друзей/);
  assert.match(russianMarkup, /<strong role="rowheader">Вы<\/strong>/);
  assert.match(russianMarkup, /aria-label="Подход 2: Записано"/);
  assert.doesNotMatch(russianMarkup, /Friends progress|Recorded|Planned|Set progress/);

  snapshot.plan.exercises[0].name = "Straight Arm Pulldown";
  snapshot.plan.exercises[0].catalogKey = "straight_arm_pulldown";
  snapshot.room.summary.exerciseNames = ["Straight Arm Pulldown"];
  vm.runInContext(`
    state.language = "ru";
    matrixSnapshot = window.GymLiveWorkout.snapshot(${JSON.stringify(snapshot)});
  `, context);
  const craneMarkup = vm.runInContext(
    "liveWorkoutExerciseMatrixMarkup(matrixSnapshot)",
    context
  );
  assert.match(craneMarkup, /Журавель — тяга прямыми руками/);
  assert.doesNotMatch(craneMarkup, /Straight Arm Pulldown/);
});

test("PWA push targets preserve an exact live room and clean consumed URL state", () => {
  const context = loadPwaContext();
  const roomId = `lr_${"b".repeat(32)}`;
  const friendshipId = `f_${"c".repeat(32)}`;
  const bindingId = "55555555-5555-4555-8555-555555555555";
  assert.deepEqual(jsonFrom(context,
    `parseAppPushData({ version: 1, target: "live", bindingId: "${bindingId}", roomId: "${roomId}" })`
  ), { version: 1, target: "live", bindingId, roomId });
  assert.deepEqual(jsonFrom(context,
    `parseAppPushData({ version: 1, target: "live" })`
  ), { version: 1, target: "live" });
  assert.deepEqual(jsonFrom(context,
    `parseAppPushData({ version: 1, target: "social" })`
  ), { version: 1, target: "social" });
  assert.deepEqual(jsonFrom(context,
    `parseAppPushData({ version: 1, target: "social", socialType: "friend_request_received", objectId: "${friendshipId}", objectRevision: 4 })`
  ), {
    version: 1,
    target: "social",
    socialType: "friend_request_received",
    objectId: friendshipId,
    objectRevision: 4
  });
  assert.throws(() => vm.runInContext(
    `parseAppPushData({ version: 1, target: "social", roomId: "${roomId}" })`,
    context
  ), /cannot select a live room/);
  assert.throws(() => vm.runInContext(
    `parseAppPushData({ version: 1, target: "live", roomId: "lr_not-valid" })`,
    context
  ), /room is invalid/);
  assert.throws(() => vm.runInContext(
    `parseAppPushData({ version: 1, target: "live", roomId: "${roomId}", url: "https:\/\/evil.example" })`,
    context
  ), /shape is invalid/);

  vm.runInContext(`
    window.location.href = "https://gymapptracker.com/GymApp/?notification=live&binding=${bindingId}&room=${roomId}&keep=1#section";
    capturedPushCleanUrl = null;
    history.replaceState = (_state, _title, url) => { capturedPushCleanUrl = url; };
  `, context);
  assert.deepEqual(jsonFrom(context, "captureAppPushTargetFromLocation()"), {
    version: 1,
    target: "live",
    bindingId,
    roomId
  });
  assert.equal(vm.runInContext("capturedPushCleanUrl", context), "/GymApp/?keep=1#section");

  vm.runInContext(`
    window.location.href = "https://gymapptracker.com/GymApp/?notification=live&room=lr_not-valid&keep=1";
    capturedPushCleanUrl = null;
  `, context);
  assert.equal(vm.runInContext("captureAppPushTargetFromLocation()", context), null);
  assert.equal(vm.runInContext("capturedPushCleanUrl", context), "/GymApp/?keep=1");

  vm.runInContext(`
    window.location.href = "https://gymapptracker.com/GymApp/?notification=social&social_type=friend_request_received&object=${friendshipId}&revision=4&keep=1";
    capturedPushCleanUrl = null;
  `, context);
  assert.deepEqual(jsonFrom(context, "captureAppPushTargetFromLocation()"), {
    version: 1,
    target: "social",
    socialType: "friend_request_received",
    objectId: friendshipId,
    objectRevision: 4
  });
  assert.equal(vm.runInContext("capturedPushCleanUrl", context), "/GymApp/?keep=1");
});

test("a service-worker push binding cannot navigate a different account after an async switch", async () => {
  const context = loadPwaContext();
  const userA = "11111111-1111-4111-8111-111111111111";
  const userB = "22222222-2222-4222-8222-222222222222";
  const bindingId = "55555555-5555-4555-8555-555555555555";
  context.pushBindingValues.set("current", {
    version: 1,
    ownerId: userA,
    bindingId
  });
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userA}", userId: "${userA}", remote: "supabase", name: "Owner A"
    };
    accountEpoch = 40;
    nav = [{ name: "workouts" }];
    loadRemoteSession = () => ({ user: { id: activeAccount.userId } });
    render = () => {};
    replaceNavigationHistory = () => {};
    pushBindingRefreshes = 0;
    refreshSocialData = async () => { pushBindingRefreshes += 1; };
  `, context);
  const opening = vm.runInContext(`openBoundAppPushTarget(parseAppPushData({
    version: 1,
    target: "social",
    bindingId: "${bindingId}"
  }))`, context);
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userB}", userId: "${userB}", remote: "supabase", name: "Owner B"
    };
    accountEpoch = 41;
  `, context);

  assert.equal(await opening, false);
  assert.deepEqual(jsonFrom(context, "nav"), [{ name: "workouts" }]);
  assert.equal(vm.runInContext("pushBindingRefreshes", context), 0);
});

test("social push targets resolve only after an account-fenced authoritative refresh", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const dashboard = socialDashboardFixture();
  dashboard.pendingWorkoutInviteCount = 0;
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    accountEpoch = 31;
    loadRemoteSession = () => ({ user: { id: "${userId}" } });
    render = () => {};
    neutralPushToasts = 0;
    showToast = () => { neutralPushToasts += 1; };
    authoritativePushRefreshes = 0;
    refreshSocialData = async () => {
      authoritativePushRefreshes += 1;
      socialState = {
        status: "loaded",
        source: "test",
        dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
        inbox: parseSocialWorkoutInbox({ version: 1, pendingIncomingCount: 0, incoming: [], outgoing: [] }),
        friendCode: null,
        workoutDetailPrivacy: null,
        workoutDetailPrivacySupported: false,
        error: ""
      };
    };
  `, context);
  const accepted = {
    version: 1,
    target: "social",
    socialType: "friend_request_accepted",
    objectId: "f_22222222222222222222222222222222",
    objectRevision: 3
  };
  assert.equal(await vm.runInContext(
    `openSocialPushTarget(${JSON.stringify(accepted)})`,
    context
  ), true);
  assert.equal(vm.runInContext("authoritativePushRefreshes", context), 1);
  assert.equal(vm.runInContext("neutralPushToasts", context), 0);

  assert.equal(await vm.runInContext(
    `openSocialPushTarget(${JSON.stringify({ ...accepted, objectId: `f_${"e".repeat(32)}` })})`,
    context
  ), false);
  assert.equal(vm.runInContext("authoritativePushRefreshes", context), 2);
  assert.equal(vm.runInContext("neutralPushToasts", context), 1);
});

test("an exact workout push may authorize the bounded second inbox page without an existence oracle", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const dashboard = socialDashboardFixture();
  dashboard.pendingWorkoutInviteCount = 20;
  const makeRows = (start, end) => Array.from({ length: end - start + 1 }, (_, offset) => {
    const value = start + offset;
    return socialWorkoutInviteMetadataFixture({
      inviteId: `wi_${value.toString(16).padStart(32, "0")}`,
      createdAt: new Date(Date.UTC(2026, 7, 9, 12, 0, 21 - value)).toISOString()
    });
  });
  const firstIncoming = makeRows(1, 10);
  const secondIncoming = makeRows(11, 20);
  const firstPage = {
    version: 2,
    pendingIncomingCount: 20,
    incoming: firstIncoming,
    outgoing: [],
    nextCursor: {
      createdAt: firstIncoming.at(-1).createdAt,
      inviteId: firstIncoming.at(-1).inviteId,
      pending: true
    }
  };
  const secondPage = {
    version: 2,
    pendingIncomingCount: 20,
    incoming: secondIncoming,
    outgoing: [],
    nextCursor: null
  };
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    accountEpoch = 32;
    loadRemoteSession = () => ({
      access_token: "push-page-session",
      user: { id: "${userId}" }
    });
    render = () => {};
    pushPageToasts = 0;
    showToast = () => { pushPageToasts += 1; };
    pushPageReads = 0;
    refreshSocialData = async () => {
      socialState = {
        status: "loaded",
        source: "push-page-source",
        dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
        inbox: parseSocialWorkoutInboxPage(${JSON.stringify(firstPage)}),
        friendCode: null,
        inboxPageCount: 1,
        inboxLoadingMore: false,
        inboxLoadMoreError: "",
        workoutDetailPrivacy: null,
        workoutDetailPrivacySupported: false,
        error: ""
      };
    };
    socialRpc = async (name, body) => {
      pushPageReads += 1;
      if (name !== "social_workout_inbox_page" || body.p_limit !== 10) {
        throw new Error("unexpected push page read");
      }
      return ${JSON.stringify(secondPage)};
    };
  `, context);
  const target = {
    version: 1,
    target: "social",
    socialType: "workout_invite_received",
    objectId: secondIncoming[4].inviteId,
    objectRevision: 1
  };
  assert.equal(await vm.runInContext(
    `openSocialPushTarget(${JSON.stringify(target)})`,
    context
  ), true);
  assert.equal(vm.runInContext("pushPageReads", context), 1);
  assert.equal(vm.runInContext("socialState.inbox.incoming.length", context), 20);
  assert.equal(vm.runInContext("pushPageToasts", context), 0);
});

test("a precise live push opens only a server-visible room and fences a late account result", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const roomId = `lr_${"b".repeat(32)}`;
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-test", user: { id: "${userId}" }
    });
    render = () => {};
    replaceNavigationHistory = () => {};
    precisePushRoomId = null;
    refreshLiveWorkoutData = async (_force, requestedRoomId) => {
      precisePushRoomId = requestedRoomId;
      liveWorkoutState = {
        status: "loaded", source: "test", error: "", snapshot: null,
        inbox: window.GymLiveWorkout.inbox(${JSON.stringify(activeLiveInboxFixture(roomId))})
      };
      return true;
    };
  `, context);
  assert.equal(vm.runInContext(
    `openAppPushTarget({ version: 1, target: "live", roomId: "${roomId}" })`,
    context
  ), true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(vm.runInContext("precisePushRoomId", context), roomId);
  assert.deepEqual(jsonFrom(context, "modal"), { type: "live-workout-room", roomId });

  vm.runInContext(`
    modal = null;
    refreshLiveWorkoutData = async () => {
      liveWorkoutState = {
        status: "loaded", source: "test", error: "", snapshot: null,
        inbox: window.GymLiveWorkout.inbox(
          ${JSON.stringify(activeLiveInboxFixture(`lr_${"d".repeat(32)}`))}
        )
      };
      return true;
    };
  `, context);
  assert.equal(await vm.runInContext(`openLiveWorkoutPushRoom("${roomId}")`, context), false);
  assert.equal(vm.runInContext("modal", context), null);

  vm.runInContext(`
    refreshLiveWorkoutData = async () => {
      accountEpoch += 1;
      return true;
    };
  `, context);
  assert.equal(await vm.runInContext(`openLiveWorkoutPushRoom("${roomId}")`, context), false);
  assert.equal(vm.runInContext("modal", context), null);
});

test("an accepted room discovered as active auto-attaches and opens its frozen workout", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const roomId = `lr_${"c".repeat(32)}`;
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-test", user: { id: "${userId}" }
    });
    state = defaultAppState();
    let autoAttachUid = 8_000_000_000_000_000;
    uid = () => ++autoAttachUid;
    activeWorkout = null;
    activeWorkoutStorageRaw = null;
    workoutDraft = null;
    liveWorkoutBinding = null;
    liveWorkoutState = { status: "idle", source: null, inbox: null, snapshot: null, error: "" };
    liveWorkoutAutoAttachAttempts.clear();
    autoAttachGatewayCalls = [];
    const autoAttachInboxRaw = ${JSON.stringify(activeLiveInboxFixture(roomId))};
    const autoAttachSnapshotRaw = ${JSON.stringify(activeLiveSnapshotFixture(roomId))};
    const autoAttachCreatedAt = Date.now() - 120_000;
    const autoAttachStartedAt = autoAttachCreatedAt + 60_000;
    const autoAttachExpiresAt = autoAttachStartedAt + 86_400_000;
    autoAttachInboxRaw.rooms[0].createdAt = new Date(autoAttachCreatedAt).toISOString();
    autoAttachInboxRaw.rooms[0].startedAt = new Date(autoAttachStartedAt).toISOString();
    autoAttachInboxRaw.rooms[0].activeExpiresAt = new Date(autoAttachExpiresAt).toISOString();
    autoAttachSnapshotRaw.room.createdAt = new Date(autoAttachCreatedAt).toISOString();
    autoAttachSnapshotRaw.room.inviteExpiresAt = new Date(
      autoAttachCreatedAt + 7 * 86_400_000
    ).toISOString();
    autoAttachSnapshotRaw.room.startedAt = new Date(autoAttachStartedAt).toISOString();
    autoAttachSnapshotRaw.room.activeExpiresAt = new Date(autoAttachExpiresAt).toISOString();
    const autoAttachInbox = window.GymLiveWorkout.inbox(autoAttachInboxRaw);
    const autoAttachSnapshot = window.GymLiveWorkout.snapshot(autoAttachSnapshotRaw);
    localStorage.setItem(liveWorkoutReservationKey("${userId}"), JSON.stringify({
      version: 1, userId: "${userId}", sessionId: "${sessionId}", role: "participant",
      operationId: "55555555-5555-4555-8555-555555555555",
      roomId: "${roomId}", phase: "active", createdAt: autoAttachCreatedAt,
      expiresAt: autoAttachExpiresAt
    }));
    liveGateway = async (action, payload) => {
      autoAttachGatewayCalls.push({ action, payload });
      if (action === "live_inbox") return autoAttachInbox;
      if (action === "live_snapshot" && payload.roomId === "${roomId}") return autoAttachSnapshot;
      throw new Error("unexpected live gateway call");
    };
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    ensureLiveWorkoutRealtime = async () => false;
    syncWebPushIfEnabled = () => {};
    scheduleLiveWorkoutPoll = () => {};
    recoverFinishedLiveWorkoutIntent = () => false;
    drainLiveWorkoutOperations = async () => true;
    render = () => {};
    showToast = message => { autoAttachToast = message; };
  `, context);

  assert.equal(await vm.runInContext("refreshLiveWorkoutData(true, null)", context), true);
  const calls = jsonFrom(context, "autoAttachGatewayCalls");
  assert.deepEqual(calls.map(call => call.action), ["live_inbox", "live_snapshot"]);
  assert.deepEqual(calls[1].payload, { roomId });
  assert.deepEqual(jsonFrom(context, `({
    bindingRoomId: liveWorkoutBinding?.roomId || null,
    activeWorkoutStarted: activeWorkout !== null,
    toast: typeof autoAttachToast === "string" ? autoAttachToast : ""
  })`), {
    bindingRoomId: roomId,
    activeWorkoutStarted: true,
    toast: ""
  });
  assert.equal(vm.runInContext("activeWorkout.blocks[0].exerciseName", context), "Bench Press");
  assert.equal(vm.runInContext("activeWorkout.id <= MAX_LIVE_LOCAL_WORKOUT_ID", context), true);
  assert.deepEqual(jsonFrom(context, "nav.map(item => item.name)"), ["workouts", "active"]);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(vm.runInContext("liveWorkoutAutoAttachAttempts.size", context), 1);

  const localWorkoutId = vm.runInContext("activeWorkout.id", context);
  assert.equal(await vm.runInContext("refreshLiveWorkoutData(true)", context), true);
  assert.equal(vm.runInContext("activeWorkout.id", context), localWorkoutId);
  assert.equal(vm.runInContext("liveWorkoutAutoAttachAttempts.size", context), 1);
});

test("same-owner sign-in recovers an old-session live queue only after an authoritative exact-room snapshot", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const oldSessionId = "22222222-2222-4222-8222-222222222222";
  const newSessionId = "33333333-3333-4333-8333-333333333333";
  const otherUserId = "44444444-4444-4444-8444-444444444444";
  const otherSessionId = "55555555-5555-4555-8555-555555555555";
  const roomId = `lr_${"e".repeat(32)}`;
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, oldSessionId))},
      refresh_token: "refresh-old", user: { id: "${userId}" }
    });
    state = defaultAppState();
    let recoveryUid = 8_000_000_000_100_000;
    uid = () => ++recoveryUid;
    const recoverySnapshotRaw = ${JSON.stringify(activeLiveSnapshotFixture(roomId))};
    const recoveryInboxRaw = ${JSON.stringify(activeLiveInboxFixture(roomId))};
    const recoveryCreatedAt = Date.now() - 120_000;
    const recoveryStartedAt = recoveryCreatedAt + 60_000;
    const recoveryExpiresAt = recoveryStartedAt + 86_400_000;
    recoverySnapshotRaw.room.createdAt = new Date(recoveryCreatedAt).toISOString();
    recoverySnapshotRaw.room.inviteExpiresAt = new Date(recoveryCreatedAt + 604_800_000).toISOString();
    recoverySnapshotRaw.room.startedAt = new Date(recoveryStartedAt).toISOString();
    recoverySnapshotRaw.room.activeExpiresAt = new Date(recoveryExpiresAt).toISOString();
    recoveryInboxRaw.rooms[0].createdAt = new Date(recoveryCreatedAt).toISOString();
    recoveryInboxRaw.rooms[0].startedAt = new Date(recoveryStartedAt).toISOString();
    recoveryInboxRaw.rooms[0].activeExpiresAt = new Date(recoveryExpiresAt).toISOString();
    recoverySnapshot = window.GymLiveWorkout.snapshot(recoverySnapshotRaw);
    recoveryInbox = window.GymLiveWorkout.inbox(recoveryInboxRaw);
    localStorage.setItem(liveWorkoutReservationKey("${userId}"), JSON.stringify({
      version: 1, userId: "${userId}", sessionId: "${oldSessionId}", role: "participant",
      operationId: "88888888-8888-4888-8888-888888888888",
      roomId: "${roomId}", phase: "active", createdAt: recoveryCreatedAt,
      expiresAt: recoveryExpiresAt
    }));
    workoutDraft = liveDraftFromSnapshot(recoverySnapshot);
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    render = () => {};
    showToast = () => {};
  `, context);
  assert.equal(await vm.runInContext(`startWorkout({
    liveSnapshot: recoverySnapshot,
    liveIdentity: liveSessionIdentity()
  })`, context), true);
  vm.runInContext(`
    const queuedBeforeLogout = window.GymLiveWorkoutState.enqueue(liveWorkoutBinding, {
      clientOperationId: "66666666-6666-4666-8666-666666666666",
      kind: "complete_set", serverSetId: "s_01_01", weight: 80, reps: 8,
      localMutationAt: Date.now()
    });
    if (!persistLiveWorkoutBinding(queuedBeforeLogout)) throw new Error("test queue failed");
    recoveryRawBeforeSessionChange = localStorage.getItem(liveWorkoutBindingKey("${userId}"));
    resetLiveWorkoutContext({ eraseBinding: false });
    clearRemoteSession();
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, newSessionId))},
      refresh_token: "refresh-new", user: { id: "${userId}" }
    });
    reloadActiveWorkoutContext(activeAccount);
    recoveryGatewayCalls = [];
    liveGateway = async (action, payload) => {
      recoveryGatewayCalls.push({ action, payload });
      if (action === "live_inbox") return recoveryInbox;
      if (action === "live_snapshot" && payload.roomId === "${roomId}") return recoverySnapshot;
      throw new Error("unexpected recovery request");
    };
    ensureLiveWorkoutRealtime = async () => false;
    syncWebPushIfEnabled = () => {};
    scheduleLiveWorkoutPoll = () => {};
    recoverFinishedLiveWorkoutIntent = () => false;
    drainLiveWorkoutOperations = async () => true;
  `, context);

  assert.equal(vm.runInContext("loadLiveWorkoutBinding()", context), null);
  assert.equal(await vm.runInContext("refreshLiveWorkoutData(true, null)", context), true);
  assert.deepEqual(jsonFrom(context, "recoveryGatewayCalls.map(call => call.action)"), [
    "live_inbox", "live_snapshot"
  ]);
  assert.equal(vm.runInContext("liveWorkoutBinding.sessionId", context), newSessionId);
  assert.equal(
    vm.runInContext("liveWorkoutBinding.pendingOperations[0].clientOperationId", context),
    "66666666-6666-4666-8666-666666666666"
  );
  assert.notEqual(
    context.localStorage.getItem(`gym-pwa-live-workout-v1:${userId}`),
    vm.runInContext("recoveryRawBeforeSessionChange", context)
  );

  const ownerRaw = context.localStorage.getItem(`gym-pwa-live-workout-v1:${userId}`);
  vm.runInContext(`
    resetLiveWorkoutContext({ eraseBinding: false });
    clearRemoteSession();
    activeAccount = {
      id: "remote-${otherUserId}", userId: "${otherUserId}", remote: "supabase", name: "Other"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(otherUserId, otherSessionId))},
      refresh_token: "refresh-other", user: { id: "${otherUserId}" }
    });
    state = defaultAppState();
    clearActiveWorkoutMemory();
    recoveryGatewayCalls = [];
    const emptyInbox = window.GymLiveWorkout.inbox({ version: 1, invitations: [], rooms: [] });
    liveGateway = async (action, payload) => {
      recoveryGatewayCalls.push({ action, payload });
      if (action === "live_inbox") return emptyInbox;
      throw new Error("another owner must not fetch a stored room");
    };
  `, context);
  assert.equal(await vm.runInContext("refreshLiveWorkoutData(true, null)", context), true);
  assert.deepEqual(jsonFrom(context, "recoveryGatewayCalls.map(call => call.action)"), ["live_inbox"]);
  assert.equal(context.localStorage.getItem(`gym-pwa-live-workout-v1:${userId}`), ownerRaw);
  assert.equal(vm.runInContext("liveWorkoutBinding", context), null);
});

test("an authoritative missing old-session live room closes only that sidecar and keeps the local workout", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const oldSessionId = "22222222-2222-4222-8222-222222222222";
  const newSessionId = "33333333-3333-4333-8333-333333333333";
  const roomId = `lr_${"d".repeat(32)}`;
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    accountEpoch = 23;
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, newSessionId))},
      refresh_token: "refresh-new", user: { id: "${userId}" }
    });
    state = defaultAppState();
    activeWorkout = { id: 700, protectedFixture: true };
    const terminalBinding = window.GymLiveWorkoutState.normalize({
      version: 1, userId: "${userId}", sessionId: "${oldSessionId}",
      roomId: "${roomId}", role: "participant",
      peerProfileId: "p_22222222222222222222222222222222", peerDisplayName: "Friend",
      roomRevision: 3, membershipRevision: 2, progressRevision: 1, localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 }, pendingOperations: [{
        clientOperationId: "77777777-7777-4777-8777-777777777777",
        kind: "finish", expectedProgressRevision: 1, serverSetId: null,
        weight: null, reps: null, localMutationAt: Date.now()
      }]
    });
    localStorage.setItem(
      liveWorkoutBindingKey("${userId}"),
      window.GymLiveWorkoutState.encode(terminalBinding)
    );
    liveWorkoutBinding = null;
    terminalRecoveryCalls = [];
    const terminalEmptyInbox = window.GymLiveWorkout.inbox({
      version: 1, invitations: [], rooms: []
    });
    liveGateway = async (action, payload) => {
      terminalRecoveryCalls.push({ action, payload });
      if (action === "live_inbox") return terminalEmptyInbox;
      if (action === "live_snapshot" && payload.roomId === "${roomId}") {
        const error = new Error("room missing");
        error.status = 404;
        throw error;
      }
      throw new Error("unexpected terminal recovery request");
    };
    ensureLiveWorkoutRealtime = async () => false;
    syncWebPushIfEnabled = () => {};
    scheduleLiveWorkoutPoll = () => {};
    render = () => {};
  `, context);

  assert.equal(await vm.runInContext("refreshLiveWorkoutData(true, null)", context), true);
  assert.deepEqual(jsonFrom(context, "terminalRecoveryCalls.map(call => call.action)"), [
    "live_inbox", "live_snapshot"
  ]);
  assert.equal(context.localStorage.getItem(`gym-pwa-live-workout-v1:${userId}`), null);
  assert.equal(vm.runInContext("activeWorkout.id", context), 700);
  assert.equal(vm.runInContext("activeWorkout.protectedFixture", context), true);
  assert.match(vm.runInContext("liveWorkoutState.error", context), /previous live room/);
});

test("a terminal live snapshot immediately drains the durable local queue", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const roomId = `lr_${"c".repeat(32)}`;
  const terminalSnapshot = activeLiveSnapshotFixture(roomId);
  terminalSnapshot.room.status = "completed";
  terminalSnapshot.room.roomRevision = 4;
  terminalSnapshot.room.closeReason = "completed";
  terminalSnapshot.room.endedAt = "2026-08-10T08:20:00Z";
  terminalSnapshot.participants.forEach(participant => {
    participant.state = "finished";
    participant.finishedAt = "2026-08-10T08:20:00Z";
    participant.progress.finishedAt = "2026-08-10T08:20:00Z";
  });
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    accountEpoch = 24;
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-owner", user: { id: "${userId}" }
    });
    state = defaultAppState();
    state.sessions = [{
      id: 700, startedAt: Date.now() - 60000, note: "", xp: 0,
      sets: [{ id: 701, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 80, reps: 8 }]
    }];
    activeWorkout = null;
    const terminalBinding = window.GymLiveWorkoutState.normalize({
      version: 1, userId: "${userId}", sessionId: "${sessionId}",
      roomId: "${roomId}", role: "participant",
      peerProfileId: "p_22222222222222222222222222222222", peerDisplayName: "Friend",
      roomRevision: 3, membershipRevision: 2, progressRevision: 1, localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 }, pendingOperations: [{
        clientOperationId: "77777777-7777-4777-8777-777777777777",
        kind: "finish", expectedProgressRevision: 1, serverSetId: null,
        weight: null, reps: null, localMutationAt: Date.now()
      }]
    });
    if (!persistLiveWorkoutBinding(terminalBinding)) throw new Error("terminal binding failed");
    const terminalInbox = window.GymLiveWorkout.inbox({ version: 1, invitations: [], rooms: [] });
    const terminalSnapshotValue = window.GymLiveWorkout.snapshot(${JSON.stringify(terminalSnapshot)});
    terminalGatewayCalls = [];
    liveGateway = async (action, payload) => {
      terminalGatewayCalls.push({ action, payload });
      if (action === "live_inbox") return terminalInbox;
      if (action === "live_snapshot") return terminalSnapshotValue;
      if (action === "live_finish") return {
        version: 1, roomId: "${roomId}", result: "closed", status: "expired"
      };
      throw new Error("unexpected terminal queue request");
    };
    ensureLiveWorkoutRealtime = async () => false;
    syncWebPushIfEnabled = () => {};
    scheduleLiveWorkoutPoll = () => {};
    localLiveOperationReflection = () => "reflected";
    render = () => {};
  `, context);

  assert.equal(await vm.runInContext(`refreshLiveWorkoutData(true, "${roomId}")`, context), true);
  const terminalDrain = vm.runInContext("liveWorkoutOperationDrain", context);
  if (terminalDrain) await terminalDrain;
  assert.deepEqual(jsonFrom(context, "terminalGatewayCalls.map(call => call.action)"), [
    "live_inbox", "live_snapshot", "live_finish"
  ]);
  assert.equal(vm.runInContext("liveWorkoutBinding", context), null);
  assert.equal(vm.runInContext("state.sessions[0].id", context), 700);
});

test("offline sign-out clears reusable credentials while preserving owner-bound cloud and live recovery", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-owner", user: { id: "${userId}" }
    });
    state = defaultAppState();
    state.profile.goal = "strength";
    markRemoteStateDirtyBeforeWrite(state);
    const logoutBinding = window.GymLiveWorkoutState.normalize({
      version: 1, userId: "${userId}", sessionId: "${sessionId}",
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", role: "participant",
      peerProfileId: "p_22222222222222222222222222222222", peerDisplayName: "Friend",
      roomRevision: 3, membershipRevision: 2, progressRevision: 1, localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 }, pendingOperations: [{
        clientOperationId: "77777777-7777-4777-8777-777777777777",
        kind: "finish", expectedProgressRevision: 1, serverSetId: null,
        weight: null, reps: null, localMutationAt: Date.now()
      }]
    });
    localStorage.setItem(liveWorkoutBindingKey("${userId}"), window.GymLiveWorkoutState.encode(logoutBinding));
    liveWorkoutBinding = logoutBinding;
    flushPendingLiveWorkoutOperationsForTransition = async () => false;
    flushPendingRemoteSave = async () => { throw new Error("offline"); };
    revokeWebPush = async () => false;
    render = () => {};
    logoutToast = "";
    showToast = message => { logoutToast = message; };
  `, context);
  const rawBefore = context.localStorage.getItem(`gym-pwa-live-workout-v1:${userId}`);
  await vm.runInContext("logoutAccount()", context);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(context.localStorage.getItem(`gym-pwa-live-workout-v1:${userId}`), rawBefore);
  assert.equal(vm.runInContext(`loadSyncBaseline("${userId}").dirty`, context), true);
  assert.match(vm.runInContext("logoutToast", context), /Unsynced owner-bound changes/);
});

test("opening a live push keeps invitation actions visible when a waiting snapshot is available", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    const pushedInvitation = {
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      status: "waiting",
      roomRevision: 1,
      createdAt: "2026-08-10T08:00:00Z",
      inviteExpiresAt: "2026-08-17T08:00:00Z",
      summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
      owner: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" }
    };
    liveWorkoutState = {
      status: "loaded",
      source: "test",
      error: "",
      inbox: window.GymLiveWorkout.inbox({ version: 1, invitations: [pushedInvitation], rooms: [] }),
      snapshot: window.GymLiveWorkout.snapshot({
        version: 1,
        room: {
          roomId: pushedInvitation.roomId,
          status: "waiting",
          roomRevision: 1,
          closeReason: null,
          createdAt: pushedInvitation.createdAt,
          inviteExpiresAt: pushedInvitation.inviteExpiresAt,
          startedAt: null,
          activeExpiresAt: null,
          endedAt: null,
          summary: pushedInvitation.summary
        },
        plan: {
          version: 1,
          exercises: [{
            exerciseId: "e_01",
            catalogKey: "bench_press",
            name: "Bench Press",
            sets: [{ setId: "s_01_01", weight: 80, reps: 8 }]
          }]
        },
        participants: [{
          isSelf: false,
          profile: pushedInvitation.owner,
          role: "owner",
          state: "joined",
          membershipRevision: 1,
          joinedAt: pushedInvitation.createdAt,
          finishedAt: null,
          departedAt: null,
          progress: null
        }, {
          isSelf: true,
          profile: { profileId: "p_11111111111111111111111111111111", displayName: "Me" },
          role: "participant",
          state: "invited",
          membershipRevision: 1,
          joinedAt: null,
          finishedAt: null,
          departedAt: null,
          progress: null
        }]
      })
    };
    modal = { type: "live-workout-room", roomId: pushedInvitation.roomId };
  `, context);
  const markup = vm.runInContext("liveWorkoutRoomMarkup()", context);
  assert.match(markup, /data-action="respond-live-invite" data-decision="accept"/);
  assert.match(markup, /data-decision="decline"/);
  assert.doesNotMatch(markup, /Open synchronized workout|Room unavailable/);
});

test("a finished guest can leave directly from an active snapshot", async () => {
  const context = loadPwaContext();
  vm.runInContext(`
    liveWorkoutState = {
      status: "loaded",
      source: "test",
      error: "",
      inbox: { version: 1, invitations: [], rooms: [] },
      snapshot: {
        version: 1,
        room: {
          roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          status: "active",
          roomRevision: 7,
          closeReason: null,
          createdAt: "2026-08-10T08:00:00Z",
          inviteExpiresAt: "2026-08-17T08:00:00Z",
          startedAt: "2026-08-10T08:05:00Z",
          activeExpiresAt: "2026-08-11T08:05:00Z",
          endedAt: null,
          summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] }
        },
        plan: { version: 1, exercises: [] },
        participants: [{
          isSelf: false,
          profile: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" },
          role: "owner",
          state: "joined",
          membershipRevision: 2,
          joinedAt: "2026-08-10T08:01:00Z",
          finishedAt: null,
          departedAt: null,
          progress: null
        }, {
          isSelf: true,
          profile: { profileId: "p_11111111111111111111111111111111", displayName: "Me" },
          role: "participant",
          state: "finished",
          membershipRevision: 4,
          joinedAt: "2026-08-10T08:01:00Z",
          finishedAt: "2026-08-10T08:30:00Z",
          departedAt: null,
          progress: null
        }]
      }
    };
    modal = { type: "live-workout-room", roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" };
  `, context);

  const markup = vm.runInContext("liveWorkoutRoomMarkup()", context);
  assert.match(markup, /data-action="leave-live-room"/);
  assert.match(markup, /data-membership-revision="4"/);

  vm.runInContext(`
    globalThis.capturedFinishedLeave = null;
    executeLiveWorkoutMutation = async (action, payload) => {
      globalThis.capturedFinishedLeave = { action, payload };
      return {
        version: 1,
        result: "left",
        roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        status: "cancelled",
        roomRevision: 8,
        membershipRevision: 5,
        endedAt: "2026-08-10T08:31:00Z"
      };
    };
    refreshLiveWorkoutData = async () => true;
    showToast = () => {};
  `, context);
  const closed = await vm.runInContext(`closeLiveWorkoutRoom({ dataset: {
    roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    membershipRevision: "4",
    roomRevision: "7"
  } }, "leave")`, context);
  assert.equal(closed, true);
  const captured = jsonFrom(context, "capturedFinishedLeave");
  assert.equal(captured.action, "live_leave");
  assert.equal(captured.payload.roomId, "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
  assert.equal(captured.payload.expectedMembershipRevision, 4);
  assert.match(captured.payload.clientOperationId, /^[0-9a-f-]{36}$/);
});

test("an unimportable live plan stays waiting and never reaches the accept mutation", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-token-test",
      user: { id: "${userId}", email: "owner@example.test" }
    });
    const poisonedInvite = {
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      status: "waiting",
      roomRevision: 1,
      createdAt: "2026-08-10T08:00:00Z",
      inviteExpiresAt: "2026-08-17T08:00:00Z",
      summary: {
        exerciseCount: 2,
        setCount: 2,
        exerciseNames: ["Bench Press", "Жим штанги лежачи"]
      },
      owner: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" }
    };
    liveWorkoutState = {
      status: "loaded",
      source: "test",
      error: "",
      snapshot: null,
      inbox: window.GymLiveWorkout.inbox({ version: 1, invitations: [poisonedInvite], rooms: [] })
    };
    poisonedSnapshot = window.GymLiveWorkout.snapshot({
      version: 1,
      room: {
        roomId: poisonedInvite.roomId,
        status: "waiting",
        roomRevision: 1,
        closeReason: null,
        createdAt: poisonedInvite.createdAt,
        inviteExpiresAt: poisonedInvite.inviteExpiresAt,
        startedAt: null,
        activeExpiresAt: null,
        endedAt: null,
        summary: poisonedInvite.summary
      },
      plan: {
        version: 1,
        exercises: [{
          exerciseId: "e_01",
          name: "Bench Press",
          sets: [{ setId: "s_01_01", weight: 80, reps: 8 }]
        }, {
          exerciseId: "e_02",
          name: "Жим штанги лежачи",
          sets: [{ setId: "s_02_01", weight: 40, reps: 12 }]
        }]
      },
      participants: [{
        isSelf: false,
        profile: poisonedInvite.owner,
        role: "owner",
        state: "joined",
        membershipRevision: 1,
        joinedAt: poisonedInvite.createdAt,
        finishedAt: null,
        departedAt: null,
        progress: null
      }, {
        isSelf: true,
        profile: { profileId: "p_11111111111111111111111111111111", displayName: "Me" },
        role: "participant",
        state: "invited",
        membershipRevision: 1,
        joinedAt: null,
        finishedAt: null,
        departedAt: null,
        progress: null
      }]
    });
    liveGateway = async () => poisonedSnapshot;
    liveAcceptMutationCount = 0;
    executeLiveWorkoutMutation = async () => {
      liveAcceptMutationCount += 1;
      return null;
    };
    render = () => {};
    showToast = message => { poisonedToast = message; };
  `, context);
  const result = await vm.runInContext(`respondLiveWorkoutInvite({ dataset: {
    roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", decision: "accept", revision: "1"
  } })`, context);
  assert.equal(result, false);
  assert.equal(vm.runInContext("liveAcceptMutationCount", context), 0);
  assert.equal(vm.runInContext("liveWorkoutState.inbox.invitations.length", context), 1);
  assert.match(vm.runInContext("poisonedToast", context), /cannot be imported safely/);
});

test("live accept asks once, mutates only after consent, and never overwrites a changed draft", async () => {
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const roomId = `lr_${"a".repeat(32)}`;

  async function runScenario({ confirmResult, changeDraftDuringMutation }) {
    const context = loadPwaContext();
    const activeRaw = activeLiveSnapshotFixture(roomId);
    const waitingRaw = structuredClone(activeRaw);
    waitingRaw.room.status = "waiting";
    waitingRaw.room.roomRevision = 1;
    waitingRaw.room.startedAt = null;
    waitingRaw.room.activeExpiresAt = null;
    waitingRaw.participants[0].progress = null;
    waitingRaw.participants[1].state = "invited";
    waitingRaw.participants[1].membershipRevision = 1;
    waitingRaw.participants[1].joinedAt = null;
    waitingRaw.participants[1].progress = null;
    const invitation = {
      roomId,
      status: "waiting",
      roomRevision: 1,
      createdAt: waitingRaw.room.createdAt,
      inviteExpiresAt: waitingRaw.room.inviteExpiresAt,
      summary: waitingRaw.room.summary,
      owner: waitingRaw.participants[0].profile
    };
    vm.runInContext(`
      activeAccount = {
        id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
      };
      localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
      saveRemoteSession({
        access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
        refresh_token: "refresh-token-test",
        user: { id: "${userId}", email: "owner@example.test" }
      });
      state = defaultAppState();
      workoutDraft = {
        date: "2026-08-13",
        note: "before accept",
        blocks: [{
          exerciseId: 1,
          exerciseName: "Bench Press",
          catalogKey: "bench_press",
          sets: [{ id: 1, weight: "60", reps: "10" }]
        }]
      };
      const testWaitingSnapshot = window.GymLiveWorkout.snapshot(${JSON.stringify(waitingRaw)});
      const testActiveSnapshot = window.GymLiveWorkout.snapshot(${JSON.stringify(activeRaw)});
      liveWorkoutState = {
        status: "loaded",
        source: "test",
        error: "",
        snapshot: null,
        inbox: window.GymLiveWorkout.inbox({
          version: 1,
          invitations: [${JSON.stringify(invitation)}],
          rooms: []
        })
      };
      confirmCount = 0;
      serverMutationCount = 0;
      localStartCount = 0;
      window.confirm = () => { confirmCount += 1; return ${confirmResult}; };
      liveGateway = async () => testWaitingSnapshot;
      executeLiveWorkoutMutation = async () => {
        serverMutationCount += 1;
        ${changeDraftDuringMutation ? 'workoutDraft.note = "changed during await";' : ""}
        return {
          version: 1,
          result: "joined",
          roomId: "${roomId}",
          status: "ready",
          roomRevision: 3,
          membershipRevision: 2,
          endedAt: null
        };
      };
      applyLiveSnapshotProgressToLocal = () => true;
      startWorkout = async () => {
        localStartCount += 1;
        activeWorkout = { id: 700 };
        liveWorkoutBinding = {
          roomId: "${roomId}", localWorkoutId: 700, pendingOperations: []
        };
        return true;
      };
      refreshLiveWorkoutData = async () => {
        liveWorkoutState = { ...liveWorkoutState, snapshot: testActiveSnapshot };
        await ensureLiveWorkoutAttached(testActiveSnapshot, true);
        return true;
      };
      replaceNavigationHistory = () => {};
      render = () => {};
      showToast = message => { lastLiveAcceptToast = message; };
      withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
        acquired: true, value: await operation()
      });
    `, context);
    const result = await vm.runInContext(`respondLiveWorkoutInvite({ dataset: {
      roomId: "${roomId}", decision: "accept", revision: "1"
    } })`, context);
    return {
      result,
      confirmCount: vm.runInContext("confirmCount", context),
      serverMutationCount: vm.runInContext("serverMutationCount", context),
      localStartCount: vm.runInContext("localStartCount", context),
      active: vm.runInContext("activeWorkout !== null", context),
      draftNote: vm.runInContext("workoutDraft?.note", context)
    };
  }

  assert.deepEqual(await runScenario({ confirmResult: false, changeDraftDuringMutation: false }), {
    result: false,
    confirmCount: 1,
    serverMutationCount: 0,
    localStartCount: 0,
    active: false,
    draftNote: "before accept"
  });
  assert.deepEqual(await runScenario({ confirmResult: true, changeDraftDuringMutation: false }), {
    result: true,
    confirmCount: 1,
    serverMutationCount: 1,
    localStartCount: 1,
    active: true,
    draftNote: ""
  });
  assert.deepEqual(await runScenario({ confirmResult: true, changeDraftDuringMutation: true }), {
    result: true,
    confirmCount: 1,
    serverMutationCount: 1,
    localStartCount: 0,
    active: false,
    draftNote: "changed during await"
  });
});

test("a locally finished live workout restores its durable finish intent after reload", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeWorkout = null;
    state.sessions = [{ id: 700, startedAt: 1, sets: [] }];
    liveWorkoutBinding = {
      version: 1,
      userId: "11111111-1111-4111-8111-111111111111",
      sessionId: "22222222-2222-4222-8222-222222222222",
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      role: "owner",
      peerProfileId: "p_22222222222222222222222222222222",
      peerDisplayName: "Friend",
      roomRevision: 3,
      membershipRevision: 1,
      progressRevision: 2,
      localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 },
      pendingOperations: []
    };
    recoveredFinishRequest = null;
    enqueueLiveWorkoutOperation = request => {
      recoveredFinishRequest = request;
      return true;
    };
    recoveredFinishSnapshot = {
      room: { roomId: liveWorkoutBinding.roomId, status: "active" },
      participants: [{
        isSelf: true,
        state: "joined",
        progress: { finishedAt: null }
      }]
    };
  `, context);
  assert.equal(vm.runInContext("recoverFinishedLiveWorkoutIntent(recoveredFinishSnapshot)", context), true);
  assert.deepEqual(jsonFrom(context, "recoveredFinishRequest"), {
    kind: "finish",
    serverSetId: null,
    weight: null,
    reps: null
  });
  vm.runInContext("liveWorkoutBinding.pendingOperations = [{ kind: 'finish' }]", context);
  assert.equal(vm.runInContext("recoverFinishedLiveWorkoutIntent(recoveredFinishSnapshot)", context), false);
});

test("live snapshot reconciliation removes confirmed undos and overlays pending local operations", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = { id: "remote-a", userId: "11111111-1111-4111-8111-111111111111", remote: "supabase", name: "A" };
    activeWorkoutStorageRaw = "before";
    activeWorkout = {
      id: 700,
      revision: 4,
      updatedAt: 1000,
      blocks: [{ id: 10, exerciseName: "Bench Press", sets: [
        { id: 701, weight: 80, reps: 8, completed: true, completedAt: 900 },
        { id: 702, weight: 70, reps: 10, completed: true, completedAt: 950 }
      ] }]
    };
    reconciledBinding = {
      localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701, s_01_02: 702 },
      pendingOperations: [
        { kind: "undo_set", serverSetId: "s_01_01" },
        { kind: "complete_set", serverSetId: "s_01_02", weight: 72.5, reps: 9 }
      ]
    };
    reconciledSnapshot = { participants: [{
      isSelf: true,
      progress: { completedSets: [
        { setId: "s_01_01", weight: 80, reps: 8, completedAt: "2026-08-10T01:00:00Z" }
      ] }
    }] };
    persistActiveWorkoutRecord = value => ({ workout: value, raw: "after" });
  `, context);
  assert.equal(
    vm.runInContext("applyLiveSnapshotProgressToLocal(reconciledSnapshot, reconciledBinding)", context),
    true
  );
  const sets = jsonFrom(context, "activeWorkout.blocks[0].sets");
  assert.deepEqual(sets[0], {
    id: 701, weight: 80, reps: 8, completed: false, completedAt: null
  });
  assert.deepEqual(sets[1], {
    id: 702, weight: 72.5, reps: 9, completed: true, completedAt: 950
  });
});

test("a prepared live completion restores the intended local set before network drain", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeAccount = { id: "local-a", userId: "11111111-1111-4111-8111-111111111111", remote: "supabase", name: "A" };
    activeWorkoutStorageRaw = "before";
    activeWorkout = {
      id: 700,
      revision: 4,
      updatedAt: 1000,
      blocks: [{ id: 10, exerciseName: "Bench Press", sets: [
        { id: 701, weight: 80, reps: 8, completed: false, completedAt: null }
      ] }]
    };
    crashBinding = {
      localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 },
      pendingOperations: [{
        kind: "complete_set", serverSetId: "s_01_01", weight: 82.5, reps: 7,
        localMutationAt: 1786334400000
      }]
    };
    crashSnapshot = { participants: [{
      isSelf: true,
      progress: { completedSets: [] }
    }] };
    persistActiveWorkoutRecord = value => ({ workout: value, raw: "after" });
  `, context);
  assert.equal(
    vm.runInContext("applyLiveSnapshotProgressToLocal(crashSnapshot, crashBinding)", context),
    true
  );
  assert.deepEqual(jsonFrom(context, "activeWorkout.blocks[0].sets[0]"), {
    id: 701,
    weight: 82.5,
    reps: 7,
    completed: true,
    completedAt: 1786334400000
  });
});

test("a late pre-ack live snapshot cannot undo a locally completed set", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    activeWorkoutStorageRaw = "current";
    activeWorkout = {
      id: 700, revision: 5, updatedAt: 2000,
      blocks: [{ id: 10, exerciseName: "Bench Press", sets: [
        { id: 701, weight: 82.5, reps: 7, completed: true, completedAt: 1900 }
      ] }]
    };
    staleBinding = {
      localWorkoutId: 700,
      progressRevision: 5,
      serverToLocalSetIds: { s_01_01: 701 },
      pendingOperations: []
    };
    staleSnapshot = { participants: [{
      isSelf: true,
      progress: { revision: 4, completedSets: [] }
    }] };
    stalePersistCalls = 0;
    persistActiveWorkoutRecord = () => { stalePersistCalls += 1; return null; };
  `, context);
  assert.equal(
    vm.runInContext("applyLiveSnapshotProgressToLocal(staleSnapshot, staleBinding)", context),
    true
  );
  assert.equal(vm.runInContext("stalePersistCalls", context), 0);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets[0].completed", context), true);
});

test("live set and finish intents are persisted before their local mutation commits", () => {
  const recordStart = appSource.indexOf("async function recordActiveSet(setId)");
  const recordEnd = appSource.indexOf("async function undoLatestActiveSet", recordStart);
  const recordSource = appSource.slice(recordStart, recordEnd);
  assert.ok(recordSource.indexOf("prepareLiveSetOperationBatch") <
    recordSource.indexOf("persistActiveWorkoutRecord(next"));

  const bulkStart = appSource.indexOf("async function recordAllActiveSets()");
  const bulkEnd = appSource.indexOf("async function recordActiveSet", bulkStart);
  const bulkSource = appSource.slice(bulkStart, bulkEnd);
  assert.ok(bulkSource.indexOf("prepareLiveSetOperationBatch") <
    bulkSource.indexOf("persistActiveWorkoutRecord(next"));

  const undoStart = appSource.indexOf("async function undoLatestActiveSet(setId)");
  const undoEnd = appSource.indexOf("function activeCompletedEntries", undoStart);
  const undoSource = appSource.slice(undoStart, undoEnd);
  assert.ok(undoSource.indexOf("prepareLiveSetOperationBatch") <
    undoSource.indexOf("persistActiveWorkoutRecord(next"));

  const finishStart = appSource.indexOf("function finishActiveWorkoutLocked");
  const finishEnd = appSource.indexOf("function requestDiscardActiveWorkout", finishStart);
  const finishSource = appSource.slice(finishStart, finishEnd);
  assert.ok(finishSource.indexOf("prepareLiveWorkoutOperationBatch") <
    finishSource.indexOf("persistActiveWorkoutCommit"));
});

test("conflicting remote live progress detaches instead of blindly rebasing", async () => {
  const context = loadPwaContext();
  vm.runInContext(`
    conflictOperation = {
      clientOperationId: "55555555-5555-4555-8555-555555555555",
      kind: "complete_set", expectedProgressRevision: 1, serverSetId: "s_01_01",
      weight: 82.5, reps: 7, localMutationAt: 1786334400000
    };
    liveWorkoutBinding = {
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      localWorkoutId: 700,
      pendingOperations: [conflictOperation]
    };
    liveGateway = async () => ({
      room: { roomId: liveWorkoutBinding.roomId, status: "active", roomRevision: 4 },
      participants: [{
        isSelf: true, state: "joined", membershipRevision: 2,
        progress: {
          revision: 3,
          completedSets: [{ setId: "s_01_01", weight: 100, reps: 2 }],
          undoableSetId: "s_01_01", finishedAt: null
        }
      }]
    });
    conflictToast = "";
    clearLiveWorkoutBinding = () => { liveWorkoutBinding = null; };
    showToast = value => { conflictToast = value; };
    render = () => {};
  `, context);
  assert.equal(
    await vm.runInContext("recoverLiveWorkoutQueue(null, conflictOperation, () => true)", context),
    "detached"
  );
  assert.equal(vm.runInContext("liveWorkoutBinding", context), null);
  assert.match(vm.runInContext("conflictToast", context), /changed on another device/);
});

test("an unresolved live conflict stops after one bounded attempt without a hot loop", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = { id: "remote-a", userId: "${userId}", remote: "supabase", name: "A" };
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-a", user: { id: "${userId}" }
    });
    activeWorkout = { id: 700, blocks: [] };
    liveWorkoutBinding = {
      version: 1, userId: "${userId}", sessionId: "${sessionId}",
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", role: "owner",
      peerProfileId: "p_22222222222222222222222222222222", peerDisplayName: "Friend",
      roomRevision: 2, membershipRevision: 1, progressRevision: 1, localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 },
      pendingOperations: [{
        clientOperationId: "55555555-5555-4555-8555-555555555555",
        kind: "complete_set", expectedProgressRevision: 1, serverSetId: "s_01_01",
        weight: 80, reps: 8, localMutationAt: 1786334400000
      }]
    };
    liveCalls = 0;
    localLiveOperationReflection = () => "reflected";
    liveGateway = async () => { liveCalls += 1; throw Object.assign(new Error("conflict"), { status: 409 }); };
    recoverLiveWorkoutQueue = async () => false;
    transitionToReauthentication = () => false;
    scheduleLiveWorkoutPoll = () => {};
    render = () => {};
  `, context);
  await vm.runInContext("drainLiveWorkoutOperations()", context);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(vm.runInContext("liveCalls", context), 1);
  assert.equal(vm.runInContext("liveWorkoutBinding.pendingOperations.length", context), 1);
  assert.equal(vm.runInContext("liveWorkoutOperationDrain", context), null);
});

test("live attach rolls back its sidecar when the local active workout cannot commit", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = { id: "remote-a", userId: "${userId}", remote: "supabase", name: "A" };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({ access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-a", user: { id: "${userId}" } });
    state = defaultAppState();
    workoutDraft = { startedAt: Date.parse("2026-08-10T01:00:00Z"), note: "", blocks: [{
      exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }]
    }] };
    attachSnapshot = window.GymLiveWorkout.snapshot({
      version: 1,
      room: {
        roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", status: "active", roomRevision: 3,
        closeReason: null, createdAt: "2026-08-10T00:58:00Z",
        inviteExpiresAt: "2026-08-17T00:58:00Z", startedAt: "2026-08-10T01:00:00Z",
        activeExpiresAt: "2026-08-11T01:00:00Z", endedAt: null,
        summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] }
      },
      plan: { version: 1, exercises: [{ exerciseId: "e_01", catalogKey: "bench_press",
        name: "Bench Press", sets: [{ setId: "s_01_01", weight: 80, reps: 8 }] }] },
      participants: [{
        isSelf: false,
        profile: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" },
        role: "owner", state: "joined", membershipRevision: 1,
        joinedAt: "2026-08-10T00:58:00Z", finishedAt: null, departedAt: null,
        progress: { version: 1, revision: 1, completedSets: [], undoableSetId: null, finishedAt: null }
      }, {
        isSelf: true,
        profile: { profileId: "p_11111111111111111111111111111111", displayName: "Me" },
        role: "participant", state: "joined", membershipRevision: 2,
        joinedAt: "2026-08-10T00:59:00Z", finishedAt: null, departedAt: null,
        progress: { version: 1, revision: 1, completedSets: [], undoableSetId: null, finishedAt: null }
      }]
    });
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    persistActiveWorkoutRecord = () => null;
    render = () => {};
    showToast = () => {};
  `, context);
  assert.equal(await vm.runInContext(`startWorkout({
    liveSnapshot: attachSnapshot,
    liveIdentity: liveSessionIdentity()
  })`, context), false);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(vm.runInContext("liveWorkoutBinding", context), null);
  assert.equal(
    vm.runInContext(`localStorage.getItem(liveWorkoutBindingKey("${userId}"))`, context),
    null
  );
});

test("durable owner live-slot reservation survives reload and blocks ordinary start without mutation", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-a", user: { id: "${userId}" }
    });
    state = defaultAppState();
    workoutDraft = { startedAt: Date.now(), note: "", blocks: [{
      exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 0, reps: 8 }]
    }] };
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    render = () => {};
    showToast = () => {};
  `, context);
  assert.equal(await vm.runInContext(`reserveLiveWorkoutSlot({
    version: 1, userId: "${userId}", sessionId: "${sessionId}", role: "owner",
    operationId: "55555555-5555-4555-8555-555555555555",
    roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", phase: "waiting",
    createdAt: Date.now() - 1000, expiresAt: Date.now() + 86400000
  })`, context), true);
  const rawBefore = vm.runInContext(
    `localStorage.getItem(liveWorkoutReservationKey("${userId}"))`,
    context
  );
  assert.equal(await vm.runInContext("startWorkout()", context), false);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(
    vm.runInContext(`localStorage.getItem(liveWorkoutReservationKey("${userId}"))`, context),
    rawBefore
  );
  assert.equal(vm.runInContext("readLiveWorkoutReservation().status", context), "valid");
});

test("invitee reservation wins accept versus ordinary-start race and exact release restores start", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Invitee"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-a", user: { id: "${userId}" }
    });
    state = defaultAppState();
    workoutDraft = { startedAt: Date.now(), note: "", blocks: [{
      exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 0, reps: 8 }]
    }] };
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    render = () => {};
    showToast = () => {};
  `, context);
  const reserved = await vm.runInContext(`reserveLiveWorkoutSlot({
    version: 1, userId: "${userId}", sessionId: "${sessionId}", role: "participant",
    operationId: "55555555-5555-4555-8555-555555555555",
    roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", phase: "waiting",
    createdAt: Date.now() - 1000, expiresAt: Date.now() + 86400000
  })`, context);
  assert.equal(reserved, true);
  assert.equal(await vm.runInContext("startWorkout()", context), false);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(await vm.runInContext(`clearLiveWorkoutSlot(
    "55555555-5555-4555-8555-555555555555",
    "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  )`, context), true);
  assert.equal(await vm.runInContext("startWorkout()", context), true);
  assert.notEqual(vm.runInContext("activeWorkout", context), null);
});

test("expired live slot clears safely while a wrong-session slot stays fail-closed and unchanged", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const oldSessionId = "22222222-2222-4222-8222-222222222222";
  const newSessionId = "33333333-3333-4333-8333-333333333333";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, oldSessionId))},
      refresh_token: "refresh-a", user: { id: "${userId}" }
    });
    state = defaultAppState();
    workoutDraft = { startedAt: Date.now(), note: "", blocks: [{
      exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 0, reps: 8 }]
    }] };
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    render = () => {};
    showToast = () => {};
    localStorage.setItem(liveWorkoutReservationKey("${userId}"), JSON.stringify({
      version: 1, userId: "${userId}", sessionId: "${oldSessionId}", role: "owner",
      operationId: "55555555-5555-4555-8555-555555555555",
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", phase: "waiting",
      createdAt: Date.now() - 2000, expiresAt: Date.now() - 1000
    }));
  `, context);
  assert.equal(await vm.runInContext("startWorkout()", context), true);
  assert.equal(vm.runInContext("readLiveWorkoutReservation().status", context), "absent");

  vm.runInContext(`
    activeWorkout = null;
    removeActiveWorkoutStorage(activeAccount);
    localStorage.setItem(liveWorkoutReservationKey("${userId}"), JSON.stringify({
      version: 1, userId: "${userId}", sessionId: "${oldSessionId}", role: "owner",
      operationId: "66666666-6666-4666-8666-666666666666",
      roomId: "lr_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", phase: "waiting",
      createdAt: Date.now() - 1000, expiresAt: Date.now() + 86400000
    }));
    clearRemoteSession();
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, newSessionId))},
      refresh_token: "refresh-b", user: { id: "${userId}" }
    });
    wrongSessionRaw = localStorage.getItem(liveWorkoutReservationKey("${userId}"));
  `, context);
  assert.equal(await vm.runInContext("startWorkout()", context), false);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(
    vm.runInContext(`localStorage.getItem(liveWorkoutReservationKey("${userId}"))`, context),
    vm.runInContext("wrongSessionRaw", context)
  );
  assert.equal(vm.runInContext("readLiveWorkoutReservation().status", context), "session-mismatch");
});

test("authoritative still-invited inbox releases participant reservation after restart and session change", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const oldSessionId = "22222222-2222-4222-8222-222222222222";
  const newSessionId = "33333333-3333-4333-8333-333333333333";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Invitee"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, newSessionId))},
      refresh_token: "refresh-new", user: { id: "${userId}" }
    });
    state = defaultAppState();
    activeWorkout = null;
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    const restartRoomId = "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const restartCreatedAt = new Date(Date.now() - 60_000).toISOString();
    const restartExpiresAt = new Date(Date.now() + 86_400_000).toISOString();
    restartInbox = window.GymLiveWorkout.inbox({
      version: 1,
      rooms: [],
      invitations: [{
        roomId: restartRoomId,
        status: "waiting",
        roomRevision: 1,
        createdAt: restartCreatedAt,
        inviteExpiresAt: restartExpiresAt,
        summary: { exerciseCount: 1, setCount: 1, exerciseNames: ["Bench Press"] },
        owner: { profileId: "p_22222222222222222222222222222222", displayName: "Friend" }
      }]
    });
    localStorage.setItem(liveWorkoutReservationKey("${userId}"), JSON.stringify({
      version: 1, userId: "${userId}", sessionId: "${oldSessionId}", role: "participant",
      operationId: "55555555-5555-4555-8555-555555555555",
      roomId: restartRoomId, phase: "waiting",
      createdAt: Date.parse(restartCreatedAt), expiresAt: Date.parse(restartExpiresAt)
    }));
  `, context);
  assert.equal(vm.runInContext("readLiveWorkoutReservation().status", context), "session-mismatch");
  assert.equal(await vm.runInContext("reconcileLiveWorkoutSlot(restartInbox)", context), true);
  assert.equal(vm.runInContext("readLiveWorkoutReservation().status", context), "absent");
});

test("deferred authoritative refresh cannot release invitee slot between reserve and accept RPC", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const roomId = "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  const waitingRaw = activeLiveSnapshotFixture(roomId);
  waitingRaw.room.status = "waiting";
  waitingRaw.room.roomRevision = 1;
  waitingRaw.room.startedAt = null;
  waitingRaw.room.activeExpiresAt = null;
  waitingRaw.participants[0].progress = null;
  waitingRaw.participants[1].state = "invited";
  waitingRaw.participants[1].membershipRevision = 1;
  waitingRaw.participants[1].joinedAt = null;
  waitingRaw.participants[1].progress = null;
  const invitation = {
    roomId,
    status: "waiting",
    roomRevision: 1,
    createdAt: waitingRaw.room.createdAt,
    inviteExpiresAt: waitingRaw.room.inviteExpiresAt,
    summary: waitingRaw.room.summary,
    owner: waitingRaw.participants[0].profile
  };
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Invitee"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh", user: { id: "${userId}" }
    });
    state = defaultAppState();
    activeWorkout = null;
    workoutDraft = null;
    const raceInvitation = ${JSON.stringify(invitation)};
    const raceInbox = window.GymLiveWorkout.inbox({
      version: 1, rooms: [], invitations: [raceInvitation]
    });
    const raceSnapshot = window.GymLiveWorkout.snapshot(${JSON.stringify(waitingRaw)});
    liveWorkoutState = {
      status: "loaded", source: "test", error: "", snapshot: null, inbox: raceInbox
    };
    withActiveWorkoutMutationLock = async (_descriptor, operation) => ({
      acquired: true, value: await operation()
    });
    preflightLiveWorkoutInvitation = async () => raceSnapshot;
    prepareLiveRequest = () => ({
      requestId: "55555555-5555-4555-8555-555555555555",
      key: "race", fingerprint: "race", source: "race"
    });
    const realReserveLiveWorkoutSlot = reserveLiveWorkoutSlot;
    let signalRaceReserved;
    let continueRaceReserve;
    raceReserved = new Promise(resolve => { signalRaceReserved = resolve; });
    const raceReserveCanReturn = new Promise(resolve => { continueRaceReserve = resolve; });
    releaseRaceReserve = () => continueRaceReserve();
    reserveLiveWorkoutSlot = async candidate => {
      const reserved = await realReserveLiveWorkoutSlot(candidate);
      signalRaceReserved(reserved);
      await raceReserveCanReturn;
      return reserved;
    };
    executeLiveWorkoutMutation = async () => {
      raceReservationDuringRpc = readLiveWorkoutReservation();
      return null;
    };
    reconcileLiveWorkoutSlotAfterFailedMutation = async () => false;
    render = () => {};
    showToast = () => {};
  `, context);
  const pending = vm.runInContext(`respondLiveWorkoutInvite({ dataset: {
    roomId: "${roomId}", decision: "accept", revision: "1"
  } })`, context);
  assert.equal(await vm.runInContext("raceReserved", context), true);
  assert.notEqual(vm.runInContext("liveWorkoutAcceptReservationInProgress", context), null);
  assert.equal(await vm.runInContext("reconcileLiveWorkoutSlot(raceInbox)", context), true);
  assert.equal(vm.runInContext("readLiveWorkoutReservation().status", context), "valid");
  vm.runInContext("releaseRaceReserve()", context);
  assert.equal(await pending, false);
  assert.equal(vm.runInContext("raceReservationDuringRpc.status", context), "valid");
  assert.equal(vm.runInContext("liveWorkoutAcceptReservationInProgress", context), null);
});

test("a stale live drain cannot clear the next account binding", async () => {
  const context = loadPwaContext();
  const userA = "11111111-1111-4111-8111-111111111111";
  const sessionA = "22222222-2222-4222-8222-222222222222";
  const userB = "33333333-3333-4333-8333-333333333333";
  const sessionB = "44444444-4444-4444-8444-444444444444";
  vm.runInContext(`
    activeAccount = { id: "remote-a", userId: "${userA}", remote: "supabase", name: "A" };
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userA, sessionA))},
      refresh_token: "refresh-a",
      user: { id: "${userA}" }
    });
    liveWorkoutBinding = {
      version: 1, userId: "${userA}", sessionId: "${sessionA}",
      roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", role: "owner",
      peerProfileId: "p_22222222222222222222222222222222", peerDisplayName: "Friend",
      roomRevision: 2, membershipRevision: 1, progressRevision: 1, localWorkoutId: 700,
      serverToLocalSetIds: { s_01_01: 701 },
      pendingOperations: [{
        clientOperationId: "55555555-5555-4555-8555-555555555555",
        kind: "finish", expectedProgressRevision: 1, serverSetId: null, weight: null, reps: null
      }]
    };
    activeWorkout = null;
    state.sessions = [{ id: 700, startedAt: 1, note: "", sets: [] }];
    localLiveOperationReflection = () => "reflected";
    render = () => {};
    scheduleLiveWorkoutPoll = () => {};
    liveGateway = () => new Promise(resolve => { resolveStaleDrain = resolve; });
  `, context);
  const pending = vm.runInContext("drainLiveWorkoutOperations()", context);
  await Promise.resolve();
  vm.runInContext(`
    resetLiveWorkoutContext({ eraseBinding: false });
    clearRemoteSession();
    activeAccount = { id: "remote-b", userId: "${userB}", remote: "supabase", name: "B" };
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userB, sessionB))},
      refresh_token: "refresh-b",
      user: { id: "${userB}" }
    });
    liveWorkoutBinding = {
      version: 1, userId: "${userB}", sessionId: "${sessionB}",
      roomId: "lr_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", role: "participant",
      peerProfileId: "p_33333333333333333333333333333333", peerDisplayName: "Peer",
      roomRevision: 3, membershipRevision: 2, progressRevision: 1, localWorkoutId: 800,
      serverToLocalSetIds: { s_01_01: 801 }, pendingOperations: []
    };
    resolveStaleDrain({ version: 1, result: "closed", roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      status: "expired", roomRevision: 3, endedAt: "2026-08-10T01:00:00Z" });
  `, context);
  await pending;
  assert.equal(
    vm.runInContext("liveWorkoutBinding.roomId", context),
    "lr_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  );
  assert.equal(vm.runInContext("liveWorkoutState.status", context), "idle");
});

test("Web Push permission is user-triggered, account-bound, and revoked without storing subscription secrets", async () => {
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const calls = [];
  let activeSubscription = null;
  let unsubscribeCount = 0;
  let notificationCloseCount = 0;
  let subscribeOptions = null;
  const subscription = {
    options: { applicationServerKey: null },
    toJSON: () => ({
      endpoint: "https://fcm.googleapis.com/fcm/send/abcdefghijklmnopqrstuvwxyz0123456789",
      expirationTime: null,
      keys: { p256dh: `B${"a".repeat(86)}`, auth: "b".repeat(22) }
    }),
    async unsubscribe() {
      unsubscribeCount += 1;
      activeSubscription = null;
      return true;
    }
  };
  const registration = {
    async getNotifications() {
      return [{ close() { notificationCloseCount += 1; } }];
    },
    pushManager: {
      async getSubscription() { return activeSubscription; },
      async subscribe(options) {
        subscribeOptions = options;
        activeSubscription = subscription;
        return subscription;
      }
    }
  };
  const notification = {
    permission: "default",
    async requestPermission() {
      notification.permission = "granted";
      return "granted";
    }
  };
  const context = loadPwaContext({
    push: {
      notification,
      registration,
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    },
    fetchImpl: async (url, options) => {
      const body = JSON.parse(options.body);
      calls.push({ url, body });
      if (String(url).endsWith("/notification_register_installation")) {
        return new Response(JSON.stringify({
          version: 1,
          installationId: body.p_installation_id,
          provider: "web_push",
          environment: "production",
          bindingId: "55555555-5555-4555-8555-555555555555",
          registrationRevision: 1,
          registeredAt: "2026-08-10T01:00:00Z"
        }), { status: 200 });
      }
      return new Response(JSON.stringify({
        version: 1,
        installationId: body.p_installation_id,
        revoked: true
      }), { status: 200 });
    }
  });
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-token-test",
      user: { id: "${userId}", email: "owner@example.test" }
    });
    render = () => {};
  `, context);
  context.testSubscription = subscription;
  assert.equal(vm.runInContext("webPushPublicKeyBytes()?.byteLength", context), 65);
  assert.match(vm.runInContext("webPushInstallationId()", context), /^[0-9a-f-]{36}$/);
  assert.equal(
    vm.runInContext("webPushSubscriptionMaterial(testSubscription).endpoint", context),
    subscription.toJSON().endpoint
  );

  assert.equal(await vm.runInContext("registerWebPush({ prompt: false })", context), false);
  assert.equal(calls.length, 0);
  assert.equal(notification.permission, "default");
  const registrationResult = await vm.runInContext("registerWebPush({ prompt: true })", context);
  assert.equal(registrationResult, true, JSON.stringify({
    calls,
    state: jsonFrom(context, "webPushState"),
    permission: notification.permission,
    subscribed: Boolean(activeSubscription)
  }));
  assert.equal(notification.permission, "granted");
  assert.equal(calls.length, 1);
  assert.equal(vm.runInContext("webPushMutationInProgress", context), false);
  assert.equal(calls[0].body.p_platform, "web");
  assert.equal(calls[0].body.p_provider, "web_push");
  assert.equal(calls[0].body.p_environment, "production");
  assert.equal(subscribeOptions.userVisibleOnly, true);
  assert.equal(new Uint8Array(subscribeOptions.applicationServerKey).byteLength, 65);
  assert.equal(vm.runInContext("webPushPreferenceEnabled()", context), true);
  assert.deepEqual(JSON.parse(JSON.stringify(context.pushBindingValues.get("current"))), {
    version: 1,
    bindingId: "55555555-5555-4555-8555-555555555555",
    ownerId: userId
  });
  const storedValues = context.localStorage.entries().map(([, value]) => value).join("\n");
  assert.equal(storedValues.includes(calls[0].body.p_provider_token), false);
  assert.equal(storedValues.includes(calls[0].body.p_web_push_p256dh), false);
  assert.equal(storedValues.includes(calls[0].body.p_web_push_auth), false);

  assert.equal(await vm.runInContext("revokeWebPush()", context), true);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].body.p_installation_id, calls[0].body.p_installation_id);
  assert.equal(unsubscribeCount, 1);
  assert.equal(notificationCloseCount, 1);
  assert.equal(context.pushBindingValues.has("current"), false);
  assert.equal(vm.runInContext("webPushPreferenceEnabled()", context), false);
});

test("Web Push permission completion cannot bind a superseded account", async () => {
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  let resolvePermission;
  let subscribeCount = 0;
  const calls = [];
  const notification = {
    permission: "default",
    requestPermission() {
      return new Promise(resolve => { resolvePermission = resolve; });
    }
  };
  const context = loadPwaContext({
    push: {
      notification,
      registration: {
        pushManager: {
          async getSubscription() { return null; },
          async subscribe() {
            subscribeCount += 1;
            throw new Error("A stale account must never subscribe.");
          }
        }
      },
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    },
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      throw new Error("A stale account must never reach the registration RPC.");
    }
  });
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-token-test",
      user: { id: "${userId}", email: "owner@example.test" }
    });
    render = () => {};
  `, context);

  const pending = vm.runInContext("registerWebPush({ prompt: true })", context);
  await Promise.resolve();
  vm.runInContext(`
    accountTransitionInProgress = true;
    accountEpoch += 1;
    activeAccount = null;
    clearRemoteSession();
  `, context);
  notification.permission = "granted";
  resolvePermission("granted");

  assert.equal(await pending, false);
  assert.equal(subscribeCount, 0);
  assert.equal(calls.length, 0);
  assert.equal(vm.runInContext("webPushPreferenceEnabled()", context), false);
});

test("remote activation does not publish the new account while binding cleanup is delayed", async () => {
  const userA = "11111111-1111-4111-8111-111111111111";
  const userB = "33333333-3333-4333-8333-333333333333";
  const sessionB = "44444444-4444-4444-8444-444444444444";
  let releaseCleanup;
  const context = loadPwaContext();
  context.delayedBindingCleanup = new Promise(resolve => { releaseCleanup = resolve; });
  vm.runInContext(`
    activeAccount = { id: "remote-${userA}", userId: "${userA}", remote: "supabase", name: "A" };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    fenceWebPushBeforeAccountChange = () => delayedBindingCleanup;
    render = () => {};
  `, context);
  const pending = vm.runInContext(`beginRemoteActivation({
    access_token: ${JSON.stringify(testAccessToken(userB, sessionB))},
    refresh_token: "refresh-b",
    expires_in: 3600,
    expires_at: 4102444800,
    token_type: "bearer",
    user: { id: "${userB}", email: "b@example.test" }
  })`, context);
  await Promise.resolve();
  assert.equal(
    JSON.parse(context.localStorage.getItem("gym-pwa-active-account-v1")).userId,
    userA
  );
  assert.equal(vm.runInContext("activeAccount.userId", context), userA);
  releaseCleanup(true);
  await pending;
  assert.equal(
    JSON.parse(context.localStorage.getItem("gym-pwa-active-account-v1")).userId,
    userB
  );
  assert.equal(vm.runInContext("activeAccount.userId", context), userB);
});

test("delayed push fencing serializes rapid local account activation", async () => {
  let releaseFence;
  const context = loadPwaContext();
  context.delayedPushFence = new Promise(resolve => { releaseFence = resolve; });
  vm.runInContext(`
    let localFenceCalls = 0;
    fenceWebPushBeforeAccountChange = () => {
      localFenceCalls += 1;
      return delayedPushFence;
    };
    render = () => {};
  `, context);
  const first = vm.runInContext('loginAccount("Alpha")', context);
  await Promise.resolve();
  const second = vm.runInContext('loginAccount("Beta")', context);
  assert.equal(vm.runInContext("accountTransitionInProgress", context), true);
  assert.equal(vm.runInContext("localFenceCalls", context), 1);
  releaseFence(true);
  await Promise.all([first, second]);
  assert.equal(vm.runInContext("activeAccount.name", context), "Alpha");
  assert.deepEqual(
    JSON.parse(context.localStorage.getItem("gym-pwa-account-list-v1")).map(account => account.name),
    ["Alpha"]
  );
  assert.equal(vm.runInContext("accountTransitionInProgress", context), false);
});

test("local account activation stays available when IndexedDB and Push are unavailable", async () => {
  const context = loadPwaContext();
  vm.runInContext(`window.indexedDB = undefined; render = () => {};`, context);
  await vm.runInContext('loginAccount("Offline")', context);
  assert.equal(vm.runInContext("activeAccount.name", context), "Offline");
  assert.equal(vm.runInContext("webPushPreferenceEnabled()", context), false);
  assert.equal(vm.runInContext("accountTransitionInProgress", context), false);
});

test("no-IndexedDB remote activation closes notifications and unsubscribes before marker swap", async () => {
  const userA = "11111111-1111-4111-8111-111111111111";
  const userB = "33333333-3333-4333-8333-333333333333";
  const sessionB = "44444444-4444-4444-8444-444444444444";
  let closed = 0;
  let unsubscribed = 0;
  const context = loadPwaContext({
    push: {
      notification: { permission: "granted", requestPermission: async () => "granted" },
      registration: {
        async getNotifications() { return [{ close() { closed += 1; } }]; },
        pushManager: {
          async getSubscription() {
            return { async unsubscribe() { unsubscribed += 1; return true; } };
          }
        }
      },
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    }
  });
  vm.runInContext(`
    window.indexedDB = undefined;
    activeAccount = { id: "remote-${userA}", userId: "${userA}", remote: "supabase", name: "A" };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    localStorage.setItem(WEB_PUSH_ENABLED_KEY, "1");
    render = () => {};
  `, context);
  await vm.runInContext(`beginRemoteActivation({
    access_token: ${JSON.stringify(testAccessToken(userB, sessionB))},
    refresh_token: "refresh-b",
    expires_in: 3600,
    expires_at: 4102444800,
    token_type: "bearer",
    user: { id: "${userB}", email: "b@example.test" }
  })`, context);
  assert.equal(closed, 1);
  assert.equal(unsubscribed, 1);
  assert.equal(vm.runInContext("activeAccount.userId", context), userB);
  assert.equal(vm.runInContext("webPushPreferenceEnabled()", context), false);
});

test("shared push transition sentinel blocks the old owner until the target account prepares", async () => {
  const userA = "11111111-1111-4111-8111-111111111111";
  const userB = "33333333-3333-4333-8333-333333333333";
  const bindingA = "55555555-5555-4555-8555-555555555555";
  const bindingB = "66666666-6666-4666-8666-666666666666";
  const context = loadPwaContext({
    push: {
      binding: { version: 1, ownerId: userA, bindingId: bindingA },
      notification: { permission: "granted", requestPermission: async () => "granted" },
      registration: {
        pushManager: { async getSubscription() { return null; } }
      },
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    }
  });
  assert.equal(
    await vm.runInContext(`beginStoredWebPushTransition("${userB}")`, context),
    true
  );
  assert.equal(context.pushBindingValues.has("current"), false);
  assert.deepEqual(
    JSON.parse(JSON.stringify(context.pushBindingValues.get("transition"))),
    { version: 1, nextOwnerId: userB }
  );
  assert.equal(
    await vm.runInContext(`storeWebPushBinding("${userA}", "${bindingA}")`, context),
    false
  );
  assert.equal(
    await vm.runInContext(`prepareStoredWebPushBinding("${userA}")`, context),
    false
  );
  assert.equal(
    await vm.runInContext(`prepareStoredWebPushBinding("${userB}")`, context),
    true
  );
  assert.equal(context.pushBindingValues.has("transition"), false);
  assert.equal(
    await vm.runInContext(`storeWebPushBinding("${userB}", "${bindingB}")`, context),
    true
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(context.pushBindingValues.get("current"))),
    { version: 1, ownerId: userB, bindingId: bindingB }
  );
});

test("Web Push account switching serializes and safely rebinds the shared endpoint", async () => {
  const userA = "11111111-1111-4111-8111-111111111111";
  const sessionA = "22222222-2222-4222-8222-222222222222";
  const userB = "33333333-3333-4333-8333-333333333333";
  const sessionB = "44444444-4444-4444-8444-444444444444";
  let activeSubscription = null;
  let subscriptionCounter = 0;
  let firstRegistrationResponse;
  const unsubscribed = [];
  const registration = {
    pushManager: {
      async getSubscription() { return activeSubscription; },
      async subscribe() {
        subscriptionCounter += 1;
        const endpoint = `https://fcm.googleapis.com/fcm/send/${"x".repeat(40)}${subscriptionCounter}`;
        const subscription = {
          endpoint,
          options: { applicationServerKey: null },
          toJSON: () => ({
            endpoint,
            expirationTime: null,
            keys: { p256dh: `B${"a".repeat(86)}`, auth: "b".repeat(22) }
          }),
          async unsubscribe() {
            unsubscribed.push(endpoint);
            if (activeSubscription === subscription) activeSubscription = null;
            return true;
          }
        };
        activeSubscription = subscription;
        return subscription;
      }
    }
  };
  let registerCalls = 0;
  const context = loadPwaContext({
    push: {
      notification: { permission: "granted", requestPermission: async () => "granted" },
      registration,
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    },
    fetchImpl: async (url, options) => {
      const body = JSON.parse(options.body);
      if (String(url).endsWith("/notification_register_installation")) {
        registerCalls += 1;
        if (registerCalls === 1) {
          return new Promise(resolve => { firstRegistrationResponse = () => resolve(new Response(JSON.stringify({
            version: 1,
            installationId: body.p_installation_id,
            provider: "web_push",
            environment: "production",
            bindingId: "55555555-5555-4555-8555-555555555555",
            registrationRevision: 1,
            registeredAt: "2026-08-10T01:00:00Z"
          }), { status: 200 })); });
        }
        return new Response(JSON.stringify({
          version: 1,
          installationId: body.p_installation_id,
          provider: "web_push",
          environment: "production",
          bindingId: "66666666-6666-4666-8666-666666666666",
          registrationRevision: 2,
          registeredAt: "2026-08-10T01:01:00Z"
        }), { status: 200 });
      }
      return new Response(JSON.stringify({
        version: 1,
        installationId: body.p_installation_id,
        revoked: true
      }), { status: 200 });
    }
  });
  vm.runInContext(`
    activeAccount = { id: "remote-${userA}", userId: "${userA}", remote: "supabase", name: "A" };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({ access_token: ${JSON.stringify(testAccessToken(userA, sessionA))},
      refresh_token: "refresh-a", user: { id: "${userA}" } });
    render = () => {};
  `, context);
  assert.equal(vm.runInContext("webPushSupported()", context), true);
  assert.equal(vm.runInContext("Boolean(webPushSource())", context), true);
  assert.equal(vm.runInContext("webPushMutationInProgress", context), false);
  assert.equal(vm.runInContext("accountTransitionInProgress", context), false);
  const first = vm.runInContext("registerWebPush({ prompt: false })", context);
  for (let attempt = 0; attempt < 20 && !firstRegistrationResponse; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  assert.equal(typeof firstRegistrationResponse, "function");
  vm.runInContext(`
    accountEpoch += 1;
    resetWebPushContext();
    clearRemoteSession();
    activeAccount = { id: "remote-${userB}", userId: "${userB}", remote: "supabase", name: "B" };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({ access_token: ${JSON.stringify(testAccessToken(userB, sessionB))},
      refresh_token: "refresh-b", user: { id: "${userB}" } });
  `, context);
  const second = vm.runInContext("registerWebPush({ prompt: false })", context);
  firstRegistrationResponse();
  assert.equal(await first, false);
  assert.equal(await second, true);
  assert.equal(registerCalls, 2);
  assert.equal(subscriptionCounter, 1);
  assert.equal(unsubscribed.length, 0);
  assert.equal(activeSubscription?.endpoint.endsWith("1"), true);
  assert.equal(vm.runInContext("webPushState.status", context), "registered");
});

test("a stale tab cannot rebind or unsubscribe the shared browser push endpoint", async () => {
  const userA = "11111111-1111-4111-8111-111111111111";
  const sessionA = "22222222-2222-4222-8222-222222222222";
  const userB = "33333333-3333-4333-8333-333333333333";
  let unsubscribeCount = 0;
  const subscription = {
    options: { applicationServerKey: null },
    toJSON: () => ({
      endpoint: `https://fcm.googleapis.com/fcm/send/${"x".repeat(48)}`,
      expirationTime: null,
      keys: { p256dh: `B${"a".repeat(86)}`, auth: "b".repeat(22) }
    }),
    async unsubscribe() { unsubscribeCount += 1; return true; }
  };
  const context = loadPwaContext({
    push: {
      notification: { permission: "granted", requestPermission: async () => "granted" },
      registration: {
        pushManager: {
          async getSubscription() { return subscription; },
          async subscribe() { throw new Error("stale tab must not subscribe"); }
        }
      },
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    },
    fetchImpl: async () => { throw new Error("stale tab must not call push RPCs"); }
  });
  vm.runInContext(`
    activeAccount = { id: "remote-${userA}", userId: "${userA}", remote: "supabase", name: "A" };
    saveRemoteSession({ access_token: ${JSON.stringify(testAccessToken(userA, sessionA))},
      refresh_token: "refresh-a", user: { id: "${userA}" } });
    localStorage.setItem(AUTH_KEY, JSON.stringify({
      id: "remote-${userB}", userId: "${userB}", remote: "supabase", name: "B"
    }));
    localStorage.setItem(WEB_PUSH_ENABLED_KEY, "1");
    render = () => {};
  `, context);
  assert.equal(vm.runInContext("webPushSource()", context), null);
  assert.equal(vm.runInContext("syncWebPushIfEnabled()", context), false);
  assert.equal(await vm.runInContext("revokeWebPush()", context), false);
  assert.equal(unsubscribeCount, 0);
});

test("a delayed reset cannot unsubscribe a newer account's shared push endpoint", async () => {
  const userA = "11111111-1111-4111-8111-111111111111";
  const userB = "33333333-3333-4333-8333-333333333333";
  let releaseSubscription;
  let getSubscriptionStarted;
  const started = new Promise(resolve => { getSubscriptionStarted = resolve; });
  const delayedSubscription = new Promise(resolve => { releaseSubscription = resolve; });
  let unsubscribeCount = 0;
  const subscription = {
    async unsubscribe() { unsubscribeCount += 1; return true; }
  };
  const context = loadPwaContext({
    push: {
      notification: { permission: "granted", requestPermission: async () => "granted" },
      registration: {
        pushManager: {
          async getSubscription() {
            getSubscriptionStarted();
            return delayedSubscription;
          }
        }
      },
      vapidPublicKey: "BMEAMVQN7DgWWPB_EhMDG_KgW3ElI399HoWuVHMvc6tZpz7sHbRMkSsjRg08DV3tT2jOMUtmfN7UreS1qsbVgqg"
    }
  });
  vm.runInContext(`
    activeAccount = { id: "remote-${userA}", userId: "${userA}", remote: "supabase", name: "A" };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    render = () => {};
    resetWebPushContext();
  `, context);
  await started;
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify({
      id: "remote-${userB}", userId: "${userB}", remote: "supabase", name: "B"
    }));
  `, context);
  releaseSubscription(subscription);
  await vm.runInContext("webPushLifecycleTail", context);
  assert.equal(unsubscribeCount, 0);
});

test("PWA joins only its private Realtime topic and treats broadcasts as refresh hints", async () => {
  const context = loadPwaContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}", userId: "${userId}", remote: "supabase", name: "Owner"
    };
    saveRemoteSession({
      access_token: ${JSON.stringify(testAccessToken(userId, sessionId))},
      refresh_token: "refresh-token-test",
      user: { id: "${userId}" }
    });
    window.GYM_SUPABASE = {
      url: "https://project.supabase.co",
      anonKey: "sb_publishable_test_key"
    };
    let realtimeCalls = [];
    let realtimeMessageCallbacks = {};
    let realtimeRefreshCount = 0;
    class TestRealtimeClient {
      constructor(endpoint, options) {
        realtimeCalls.push({ kind: "client", endpoint, options });
      }
      async setAuth(token) { realtimeCalls.push({ kind: "auth", token }); }
      channel(topic, options) {
        realtimeCalls.push({ kind: "channel", topic, options });
        return {
          on(type, filter, callback) {
            realtimeCalls.push({ kind: "on", type, filter });
            realtimeMessageCallbacks[filter.event] = callback;
            return this;
          },
          subscribe(callback) {
            realtimeCalls.push({ kind: "subscribe" });
            callback("SUBSCRIBED");
            return this;
          }
        };
      }
      async removeChannel() {}
      async disconnect() {}
    }
    window.GymSupabaseRealtime = { RealtimeClient: TestRealtimeClient };
    refreshLiveWorkoutData = async () => { realtimeRefreshCount += 1; return true; };
    render = () => {};
  `, context);
  assert.equal(await vm.runInContext("ensureLiveWorkoutRealtime()", context), true);
  const calls = jsonFrom(context, "realtimeCalls");
  const channel = calls.find(call => call.kind === "channel");
  assert.equal(channel.topic, `gymapp:user:${userId}`);
  assert.deepEqual(channel.options, {
    config: { private: true, broadcast: { ack: false, self: false } }
  });
  assert.deepEqual(
    calls.filter(call => call.kind === "on").map(call => call.filter.event),
    ["gymapp_live_changed", "gymapp_social_changed"]
  );
  vm.runInContext(`realtimeMessageCallbacks.gymapp_live_changed({ payload: {
    version: 1,
    kind: "invite",
    roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    roomRevision: 1
  } })`, context);
  await new Promise(resolve => setTimeout(resolve, 120));
  assert.equal(vm.runInContext("realtimeRefreshCount", context), 1);
  vm.runInContext(`realtimeMessageCallbacks.gymapp_live_changed({ payload: {
    version: 1,
    kind: "invite",
    roomId: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    roomRevision: 1,
    privateWorkout: true
  } })`, context);
  await new Promise(resolve => setTimeout(resolve, 120));
  assert.equal(vm.runInContext("realtimeRefreshCount", context), 1);
  vm.runInContext("clearTimeout(liveWorkoutPollTimer); liveWorkoutPollTimer = null; stopLiveWorkoutRealtime();", context);
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
  assert.equal(vm.runInContext(`loadSocialWorkoutInviteRequestJournal(
    "11111111-1111-4111-8111-111111111111"
  ).length`, context), 1);
  vm.runInContext(`
    socialWorkoutInviteRequests.clear();
    accountEpoch = 13;
  `, context);
  await vm.runInContext(expression, context);
  const attempts = jsonFrom(context, "socialInviteAttempts");
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0].name, "social_send_workout_invite");
  assert.equal(attempts[0].body.p_client_request_id, attempts[1].body.p_client_request_id);
  assert.match(attempts[0].body.p_client_request_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(vm.runInContext("socialWorkoutInviteRequests.size", context), 0);
  assert.equal(vm.runInContext(`loadSocialWorkoutInviteRequestJournal(
    "11111111-1111-4111-8111-111111111111"
  ).length`, context), 0);
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
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111" } });
    const journal = Array.from({ length: MAX_PENDING_SOCIAL_WORKOUT_REQUESTS }, (_, index) => ({
      profileId: "p_22222222222222222222222222222222",
      fingerprint: "1:" + index.toString(16).padStart(16, "0") + ":" +
        (index + 100).toString(16).padStart(16, "0"),
      requestId: "00000000-0000-4000-8000-" + index.toString(16).padStart(12, "0"),
      createdAt: Date.now()
    }));
    if (!saveSocialWorkoutInviteRequestJournal(activeAccount.userId, journal)) {
      throw new Error("fixture journal failed");
    }
  `, context);
  const before = jsonFrom(context,
    "loadSocialWorkoutInviteRequestJournal(activeAccount.userId)"
  );
  assert.throws(
    () => vm.runInContext(`prepareSocialWorkoutInviteRequest(
      "p_22222222222222222222222222222222",
      ${JSON.stringify(sharedWorkoutFixture())}
    )`, context),
    /outcomes are still unknown/
  );
  assert.deepEqual(jsonFrom(context,
    "loadSocialWorkoutInviteRequestJournal(activeAccount.userId)"
  ), before);
});

test("saving unchanged friend privacy accepts the server no-op revision", async () => {
  const context = loadPwaContext();
  const privacyToken = testAccessToken(
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222"
  );
  vm.runInContext(`
    activeAccount = {
      id: "remote-11111111-1111-4111-8111-111111111111",
      userId: "11111111-1111-4111-8111-111111111111",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 13;
    loadRemoteSession = () => ({
      access_token: ${JSON.stringify(privacyToken)},
      user: { id: "11111111-1111-4111-8111-111111111111" }
    });
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

test("a confirmed friend mutation retries only authoritative reads after refresh failure", async () => {
  const context = loadPwaContext();
  const dashboard = socialDashboardFixture();
  const userId = "11111111-1111-4111-8111-111111111111";
  const sessionId = "22222222-2222-4222-8222-222222222222";
  const tokenBeforeRefresh = testAccessToken(userId, sessionId);
  const tokenAfterRefresh = `${testAccessToken(userId, sessionId)}-rotated`;
  vm.runInContext(`
    activeAccount = {
      id: "remote-${userId}",
      userId: "${userId}",
      remote: "supabase",
      name: "Owner"
    };
    accountEpoch = 31;
    confirmedSessionToken = ${JSON.stringify(tokenBeforeRefresh)};
    loadRemoteSession = () => ({
      access_token: confirmedSessionToken,
      user: { id: activeAccount.userId }
    });
    socialState = {
      status: "loaded", source: socialSourceKey(),
      dashboard: parseSocialDashboard(${JSON.stringify(dashboard)}),
      inbox: null, friendCode: "g_a1b2c3d4e5f6",
      inboxPageCount: 0, inboxLoadingMore: false, inboxLoadMoreError: "",
      workoutDetailPrivacy: null, workoutDetailPrivacySupported: false, error: ""
    };
    friendMutationCalls = 0;
    friendRefreshCalls = 0;
    socialRpc = async name => {
      friendMutationCalls += 1;
      if (name !== "social_cancel_friend_request") throw new Error("mutation replayed as read");
      return {
        version: 1,
        friendshipId: "f_33333333333333333333333333333333",
        status: "removed",
        friendshipRevision: 2
      };
    };
    refreshSocialData = async () => {
      friendRefreshCalls += 1;
      if (friendRefreshCalls === 1) {
        confirmedSessionToken = ${JSON.stringify(tokenAfterRefresh)};
        return false;
      }
      completeConfirmedSocialRestoration();
      return true;
    };
    render = () => {};
    showToast = message => { confirmedFriendToast = message; };
  `, context);
  await vm.runInContext(`cancelFriendRequest({ dataset: {
    friendshipId: "f_33333333333333333333333333333333", revision: "1"
  } })`, context);
  assert.equal(vm.runInContext("friendMutationCalls", context), 1);
  assert.equal(vm.runInContext("friendRefreshCalls", context), 1);
  assert.equal(vm.runInContext("socialMutationInProgress", context), true);
  assert.match(vm.runInContext("socialState.error", context), /Change saved/);
  assert.equal(await vm.runInContext("retryConfirmedSocialRestoration()", context), true);
  assert.equal(vm.runInContext("friendMutationCalls", context), 1);
  assert.equal(vm.runInContext("friendRefreshCalls", context), 2);
  assert.equal(vm.runInContext("socialMutationInProgress", context), false);
  assert.match(vm.runInContext("confirmedFriendToast", context), /cancelled/);
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
