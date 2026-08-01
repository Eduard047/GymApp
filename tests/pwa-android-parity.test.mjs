import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const stateContractSource = await readFile(
  new URL("../pwa/state-contract.js", import.meta.url),
  "utf8"
);
const appSources = await Promise.all(
  ["app.js", "app.v59.js"].map(async filename => ({
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

for (const { filename, source } of appSources) {
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
