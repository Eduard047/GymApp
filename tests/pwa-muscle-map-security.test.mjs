import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const stateContractSource = await readFile(new URL("../pwa/state-contract.js", import.meta.url), "utf8");
const appSources = await Promise.all(
  ["app.js", "app.v60.js"].map(async filename => ({
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

test("current PWA bundles remain byte-identical", () => {
  assert.equal(appSources[1].source, appSources[0].source);
});

for (const { filename, source } of appSources) {
  test(`${filename} ignores inherited exact-map properties for imported exercise names`, () => {
    const context = loadPwaContext(source);
    vm.runInContext(`state = normalizeImportedState({
      language: "en",
      exercises: [{ id: 91, name: "constructor" }],
      sessions: [{
        id: 92,
        startedAt: Date.now(),
        note: "",
        exerciseNames: ["constructor"],
        sets: [{
          id: 93,
          exerciseName: "constructor",
          weight: 10,
          reps: 10,
          orderIndex: 0
        }]
      }],
      mappings: {},
      profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
    }, defaultAppState())`, context);

    assert.equal(vm.runInContext('state.exercises[0].name', context), "constructor");
    assert.deepEqual(jsonFrom(context, 'contributionFor(state.exercises[0])'), []);
    assert.deepEqual(jsonFrom(context, 'mappingFor(state.exercises[0])'), []);
    assert.equal(Array.isArray(jsonFrom(context, 'muscleStats(state.sessions)')), true);

    for (const inheritedName of ["constructor", " Constructor "]) {
      assert.deepEqual(
        jsonFrom(context, `contributionFor({ name: ${JSON.stringify(inheritedName)} })`),
        [],
        inheritedName
      );
    }
  });

  test(`${filename} preserves own exact mappings and inference fallback`, () => {
    const context = loadPwaContext(source);
    const exact = jsonFrom(context, 'contributionFor({ name: "Присід зі штангою" })');
    const inferred = jsonFrom(context, 'contributionFor({ name: "My custom bicep curl" })');

    assert.deepEqual(exact.find(item => item.muscleId === "abs"), { muscleId: "abs", weight: 0.2 });
    assert.equal(inferred.some(item => item.muscleId === "biceps" && item.weight === 1), true);
    assert.equal(inferred.some(item => item.muscleId === "forearms" && item.weight === 0.25), true);
  });
}
