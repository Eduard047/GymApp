import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const stateContractSource = await readFile(
  new URL("../pwa/state-contract.js", import.meta.url),
  "utf8"
);
const garminCloudSource = await readFile(
  new URL("../pwa/garmin-cloud-sync.js", import.meta.url),
  "utf8"
);
const appSources = await Promise.all(
  ["app.js", "app.v64.js"].map(async filename => ({
    filename,
    source: await readFile(new URL(`../pwa/${filename}`, import.meta.url), "utf8")
  }))
);

function loadPwaContext(appSource) {
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
      addEventListener() {}
    },
    document: {
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: {},
    history: {
      replaceState() {},
      pushState() {}
    },
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
  context.window.history = context.history;
  context.window.localStorage = context.localStorage;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(garminCloudSource, context);
  context.window.GymGarminCloud = context.GymGarminCloud;
  vm.runInContext(appSource, context);
  return context;
}

function comparisonFixture() {
  const set = (id, exerciseName, weight, reps) => ({
    id,
    exerciseName,
    weight,
    reps,
    orderIndex: id
  });
  return [
    {
      id: 9,
      startedAt: 1_700_000_000_000,
      note: "",
      sets: [set(1, "Bench Press", 50, 10), set(2, "Squat", 80, 5)]
    },
    {
      id: 10,
      startedAt: 1_700_000_000_000,
      note: "",
      sets: [set(3, "Bench Press", 60, 8), set(4, "Squat", 90, 4)]
    },
    {
      id: 11,
      startedAt: 1_700_086_400_000,
      note: "",
      sets: [set(5, "Bench Press", 20, 20)]
    },
    {
      id: 12,
      startedAt: 1_700_172_800_000,
      note: "",
      sets: [
        set(6, "Bench Press", 65, 10),
        set(7, "Squat", 95, 6),
        set(8, "Squat", 95, 5)
      ]
    }
  ];
}

test("current PWA parity bundle remains byte-identical", () => {
  assert.equal(appSources[1].source, appSources[0].source);
});

test("PWA distinguishes planned draft rows from logged rest-timed sets", () => {
  assert.match(appSources[0].source, /data-action="add-set"[^>]*>\$\{t\("addPlannedSet"\)\}<\/button>/);
  assert.match(appSources[0].source, /data-action="detail-add-set"[^>]*>\$\{t\("logSetAndRest"\)\}<\/button>/);
  assert.match(appSources[0].source, /data-action="save-workout"[^>]*>[\s\S]*?t\("saveCompletedWorkout"\)/);
  assert.match(appSources[0].source, /Saving as completed records every row in history and opens the summary/);
});

for (const { filename, source } of appSources) {
  test(`${filename} logs a detail set before starting its rest timer`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      language: "en",
      exercises: [{ id: 1, name: "Bench Press" }],
      sessions: [{
        id: 10,
        startedAt: 1700000000000,
        note: "",
        sets: [{ id: 1, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }],
      mappings: {},
      profile: {}
    };
    render = () => {};
    showToast = message => { globalThis.lastToast = message; };
    saveState = () => { throw new Error("storage unavailable"); };
    detailAddSet(10, "Bench Press");`, context);

    assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
    assert.equal(vm.runInContext("timerRemaining('10:Bench Press')", context), 0);
    assert.equal(
      vm.runInContext("localStorage.getItem(exerciseRestTimerAccountDescriptor().storageKey)", context),
      null
    );
    assert.equal(
      vm.runInContext("globalThis.lastToast", context),
      "Could not log the set. Rest was not started."
    );

    vm.runInContext(`saveState = () => {};
      detailAddSet(10, "Bench Press");`, context);
    assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 2);
    assert.ok(vm.runInContext("timerRemaining('10:Bench Press') > 0", context));
    assert.ok(
      vm.runInContext("localStorage.getItem(exerciseRestTimerAccountDescriptor().storageKey) !== null", context)
    );
    assert.equal(vm.runInContext("t('logSetAndRest')", context), "Log set · rest 90 s");
  });

  test(`${filename} restores bounded rest deadlines outside workout state`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      ...defaultAppState(),
      sessions: [{
        id: 10,
        startedAt: 1700000000000,
        note: "",
        sets: [{ id: 1, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }]
    };
    const startedAt = Date.now();
    if (!startExerciseRestTimer("10:Bench Press", 90, startedAt)) throw new Error("timer start failed");
    globalThis.savedDeadline = currentExerciseRestTimers(startedAt)["10:Bench Press"];
    exerciseRestTimerLedger = null;
    globalThis.restoredDeadline = currentExerciseRestTimers(startedAt + 1000)["10:Bench Press"];
    state.timers = { legacy: 123 };
    saveState({ queueRemote: false, markDirty: false });
    globalThis.persistedWorkoutState = JSON.parse(localStorage.getItem(activeStorageKey()));
    globalThis.exportedWorkoutState = JSON.parse(exportPayload(false));`, context);

    assert.equal(
      vm.runInContext("globalThis.restoredDeadline", context),
      vm.runInContext("globalThis.savedDeadline", context)
    );
    assert.equal(vm.runInContext("Object.hasOwn(globalThis.persistedWorkoutState, 'timers')", context), false);
    assert.equal(vm.runInContext("Object.hasOwn(globalThis.exportedWorkoutState, 'timers')", context), false);
    assert.equal(
      vm.runInContext(
        "Object.hasOwn(remoteStateCore(state, '00000000-0000-4000-8000-000000000001'), 'timers')",
        context
      ),
      false
    );
  });

  test(`${filename} rejects malformed timers and prunes stale timers`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      ...defaultAppState(),
      sessions: [{
        id: 10,
        startedAt: 1700000000000,
        note: "",
        sets: [{ id: 1, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }]
    };
    globalThis.timerStorageKey = exerciseRestTimerAccountDescriptor().storageKey;
    localStorage.setItem(globalThis.timerStorageKey, JSON.stringify({
      version: 1,
      owner: "another-account",
      entries: []
    }));
    globalThis.malformedTimers = loadExerciseRestTimerLedger(null, Date.now()).timers;
    globalThis.malformedValueAfterLoad = localStorage.getItem(globalThis.timerStorageKey);
    localStorage.setItem(globalThis.timerStorageKey, JSON.stringify({
      version: 1,
      owner: "guest",
      entries: [{
        sessionId: 10,
        exerciseName: "Bench Press",
        deadlineMillis: Date.now() - 1
      }]
    }));
    globalThis.staleTimers = loadExerciseRestTimerLedger(null, Date.now()).timers;
    globalThis.staleValueAfterLoad = localStorage.getItem(globalThis.timerStorageKey);`, context);

    assert.equal(vm.runInContext("Object.keys(globalThis.malformedTimers).length", context), 0);
    assert.equal(vm.runInContext("globalThis.malformedValueAfterLoad", context), null);
    assert.equal(vm.runInContext("Object.keys(globalThis.staleTimers).length", context), 0);
    assert.equal(vm.runInContext("globalThis.staleValueAfterLoad", context), null);
  });

  test(`${filename} keeps rest timers isolated by account`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      ...defaultAppState(),
      sessions: [{
        id: 10,
        startedAt: 1700000000000,
        note: "",
        sets: [{ id: 1, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }]
    };
    globalThis.firstAccount = {
      id: "local-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      name: "First",
      localIdVersion: 2
    };
    globalThis.secondAccount = {
      id: "local-v2-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      name: "Second",
      localIdVersion: 2
    };
    activeAccount = globalThis.firstAccount;
    exerciseRestTimerLedger = null;
    if (!startExerciseRestTimer("10:Bench Press", 90)) throw new Error("timer start failed");
    globalThis.firstRemaining = timerRemaining("10:Bench Press");
    globalThis.firstStorageKey = exerciseRestTimerAccountDescriptor().storageKey;
    activeAccount = globalThis.secondAccount;
    globalThis.secondRemaining = timerRemaining("10:Bench Press");
    globalThis.secondStorageKey = exerciseRestTimerAccountDescriptor().storageKey;
    activeAccount = globalThis.firstAccount;
    globalThis.restoredFirstRemaining = timerRemaining("10:Bench Press");`, context);

    assert.ok(vm.runInContext("globalThis.firstRemaining > 0", context));
    assert.equal(vm.runInContext("globalThis.secondRemaining", context), 0);
    assert.ok(vm.runInContext("globalThis.restoredFirstRemaining > 0", context));
    assert.notEqual(
      vm.runInContext("globalThis.firstStorageKey", context),
      vm.runInContext("globalThis.secondStorageKey", context)
    );
  });

  test(`${filename} keeps a logged set when only timer persistence fails`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      ...defaultAppState(),
      sessions: [{
        id: 10,
        startedAt: 1700000000000,
        note: "",
        sets: [{ id: 1, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }]
    };
    render = () => {};
    showToast = message => { globalThis.lastToast = message; };
    saveState = () => {};
    const originalSetItem = localStorage.setItem;
    localStorage.setItem = (key, value) => {
      if (String(key).startsWith(EXERCISE_REST_TIMER_PREFIX)) throw new Error("timer storage unavailable");
      originalSetItem(key, value);
    };
    detailAddSet(10, "Bench Press");`, context);

    assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 2);
    assert.equal(vm.runInContext("timerRemaining('10:Bench Press')", context), 0);
    assert.equal(
      vm.runInContext("globalThis.lastToast", context),
      "Set logged, but the rest timer could not be saved."
    );
  });

  test(`${filename} compares the latest earlier workout with an exact exercise signature`, () => {
    const context = loadPwaContext(source);
    const sessions = comparisonFixture();
    vm.runInContext(`state = {
      language: "en",
      exercises: [],
      sessions: ${JSON.stringify(sessions)},
      mappings: {},
      profile: {}
    }`, context);

    const result = JSON.parse(
      vm.runInContext("JSON.stringify(workoutComparisonForSession(state.sessions[3]))", context)
    );
    assert.equal(result.previousStartedAt, sessions[1].startedAt);
    assert.equal(result.matchedExerciseCount, 2);
    assert.deepEqual(result.metrics, [
      { label: "Sets", current: 3, previous: 2 },
      { label: "Reps", current: 21, previous: 12 },
      { label: "Volume", current: 1695, previous: 840 }
    ]);
  });

  test(`${filename} rejects oversized comparison input without mutating session state`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      language: "en",
      exercises: [],
      sessions: [{ id: 1, startedAt: 1700000000000, note: "", sets: [] }],
      mappings: {},
      profile: {}
    };
    state.sessions[0].sets.length =
      window.GymStateContract.LIMITS.exercisesPerSession *
      window.GymStateContract.LIMITS.setsPerExercise + 1;`, context);

    assert.equal(vm.runInContext("comparableWorkoutSnapshot(state.sessions[0])", context), null);
    assert.equal(
      vm.runInContext(
        "state.sessions[0].sets.length",
        context
      ),
      10001
    );
  });

  test(`${filename} rejects non-finite and out-of-range comparison metrics`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = {
      language: "en",
      exercises: [],
      sessions: [{
        id: 1,
        startedAt: 1700000000000,
        note: "",
        sets: [{
          id: 1,
          exerciseName: "Bench Press",
          weight: Infinity,
          reps: 8,
          orderIndex: 1
        }]
      }],
      mappings: {},
      profile: {}
    }`, context);
    assert.equal(vm.runInContext("comparableWorkoutSnapshot(state.sessions[0])", context), null);

    vm.runInContext("state.sessions[0].sets[0].weight = 60; state.sessions[0].sets[0].reps = 10001", context);
    assert.equal(vm.runInContext("comparableWorkoutSnapshot(state.sessions[0])", context), null);
  });

  test(`${filename} renders escaped partial Garmin set intervals`, () => {
    const context = loadPwaContext(source);
    vm.runInContext('state.language = "en"', context);
    const parsed = JSON.parse(vm.runInContext(`JSON.stringify(parseGarminWorkoutMetrics(
      "Garmin · Completed 2/3 sets · S1 I0-42s K4.5/5 Z0/0/12/20/10/0s · S+1"
    ))`, context));
    assert.deepEqual(parsed.completion, { completedSets: 2, plannedSets: 3 });
    assert.equal(parsed.omittedSetIntervalCount, 1);
    const html = vm.runInContext(`garminWorkoutMetricsCard(${JSON.stringify(parsed)}, 9)`, context);
    assert.match(html, /Original Garmin result: completed 2 of 3 planned sets/);
    assert.match(html, /Chronological watch set intervals/);
    assert.match(html, /Watch S1, S2, … follow completion order and may differ from the exercise grouping below/);
    assert.match(html, /Read from the workout note; imported or manually edited notes are not proof of watch origin/);
    assert.match(html, /Set metric rows omitted from the bounded workout note: 1/);
    assert.match(html, /Watch S1 · 0–42s · Gym 4\.5 kcal · Garmin 5 kcal · Z2 12s/);

    const hostile = {
      ...parsed,
      sets: [{
        index: 1,
        interval: {
          startSeconds: '<img src=x onerror="alert(1)">',
          endSeconds: 42,
          gymCalories: '<svg onload="alert(2)">',
          garminCalories: null,
          zoneSeconds: [0, 0, 0, 1, 0, 0]
        }
      }]
    };
    const escaped = vm.runInContext(
      `garminWorkoutMetricsCard(${JSON.stringify(hostile)}, 2)`,
      context
    );
    assert.doesNotMatch(escaped, /<img|<svg/);
    assert.match(escaped, /&lt;img/);
    assert.match(escaped, /&lt;svg/);
  });

  test(`${filename} does not fall back to permissive Garmin UI for a rejected note`, () => {
    const context = loadPwaContext(source);
    const malformed = "Garmin · Duration 1:00 · S1 I0-10s Kbad Z0/0/0/10/0/0s";
    vm.runInContext(`state = {
      language: "en",
      exercises: [{ id: 1, name: "Bench Press" }],
      sessions: [{
        id: 10,
        startedAt: 1700000000000,
        note: ${JSON.stringify(malformed)},
        sets: [{ id: 1, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }],
      mappings: {},
      profile: {},
      timers: {}
    }`, context);

    assert.equal(vm.runInContext("parseGarminWorkoutMetrics(state.sessions[0].note)", context), null);
    const html = vm.runInContext("detailScreen(10)", context);
    assert.doesNotMatch(html, /garmin-metrics|Garmin strength metrics/);
    assert.match(html, /Log set · rest 90 s/);
  });
}

test("PWA screen composition follows the current Android information hierarchy", () => {
  const source = appSources[0].source;
  assert.doesNotMatch(source, /focus-recent/);
  assert.match(source, /exerciseMuscleBreakdownCard\(selected, true\)/);
  assert.match(source, /class="hero-panel missions-rank-hero"/);
  assert.match(source, /summary: missionSummary\(template, cadence\)/);
  assert.match(source, /class="panel highlighted smart-coach-panel"/);
  assert.equal(source.match(/\$\{workoutComparisonCard\(session\)\}/g)?.length, 2);
});
