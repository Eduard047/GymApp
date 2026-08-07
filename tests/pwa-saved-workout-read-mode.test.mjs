import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile(new URL("../pwa/app.js", import.meta.url), "utf8");
const stateContractSource = await readFile(new URL("../pwa/state-contract.js", import.meta.url), "utf8");
const garminCloudSource = await readFile(new URL("../pwa/garmin-cloud-sync.js", import.meta.url), "utf8");

function loadPwaContext() {
  const values = new Map();
  let secureIdCounter = 10_000;
  const appElement = {
    innerHTML: "",
    classList: { toggle() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    children: []
  };
  const context = {
    console,
    Date,
    Intl,
    Map,
    Set,
    TextEncoder,
    URLSearchParams,
    window: {
      location: { search: "", hash: "", replace() {} },
      addEventListener() {},
      confirm: () => true,
      crypto: {
        getRandomValues(words) {
          secureIdCounter += 1;
          words[0] = 0;
          words[1] = secureIdCounter;
          return words;
        }
      }
    },
    document: {
      documentElement: { lang: "en" },
      querySelector() { return appElement; }
    },
    navigator: {},
    history: {
      state: null,
      replaceState() {},
      pushState() {},
      back() {}
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

function installWorkoutFixture(context) {
  vm.runInContext(`
    state = {
      ...defaultAppState(),
      language: "en",
      exercises: [
        { id: 101, name: "Bench Press" },
        { id: 102, name: "Squat" },
        { id: 103, name: "Lat Pulldown" }
      ],
      sessions: [{
        id: 201,
        startedAt: 1700000000000,
        note: "",
        sets: [
          { id: 301, exerciseName: "Bench Press", weight: 60, reps: 10, orderIndex: 0 },
          { id: 302, exerciseName: "Bench Press", weight: 65, reps: 8, orderIndex: 1 },
          { id: 303, exerciseName: "Squat", weight: 90, reps: 5, orderIndex: 0 }
        ]
      }],
      mappings: {}
    };
    nav = [{ name: "workouts" }, { name: "detail", id: 201 }];
    workoutDetailEditSessionId = null;
  `, context);
}

test("saved workout opens as compact read-only cards with no live controls", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  const html = vm.runInContext("detailScreen(201)", context);

  assert.match(html, /READ MODE/);
  assert.match(html, /data-action="edit-workout"/);
  assert.equal((html.match(/data-saved-workout-exercise/g) || []).length, 2);
  assert.equal((html.match(/aria-expanded="false"/g) || []).length, 2);
  assert.doesNotMatch(html, /<details[^>]*data-saved-workout-exercise[^>]*\sopen(?:\s|>)/);
  assert.match(html, /2 sets · 18 reps · 1,120 kg volume/);
  assert.match(html, /1 set · 5 reps · 450 kg volume/);
  assert.doesNotMatch(html, /data-action="(?:delete-session|delete-set|edit-set|add-saved-workout-set|timer|detail-add-set)"/);
  assert.match(html, /data-action="share-session"/);
});

test("saved workout edit mode gates mutations and adds a set without a rest callback", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext("workoutDetailEditSessionId = 201", context);
  const html = vm.runInContext("detailScreen(201)", context);

  assert.match(html, /EDIT MODE/);
  assert.match(html, /data-action="delete-session"/);
  assert.match(html, /data-action="open-workout-exercise-picker"/);
  assert.match(html, /data-action="add-saved-workout-set"/);
  assert.match(html, /data-action="edit-set"/);
  assert.match(html, /data-action="delete-set"/);
  assert.doesNotMatch(html, /data-action="timer"|detail-add-set|Exercise Rest/);

  vm.runInContext(`
    render = () => {};
    saveState = () => {};
    showToast = message => { globalThis.lastToast = message; };
    globalThis.added = addSavedWorkoutSet(201, "Bench Press");
  `, context);
  assert.equal(vm.runInContext("globalThis.added", context), true);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 4);
  assert.equal(vm.runInContext("globalThis.lastToast", context), "Set added without starting rest.");

  vm.runInContext("workoutDetailEditSessionId = null", context);
  assert.equal(vm.runInContext("addSavedWorkoutSet(201, 'Bench Press')", context), false);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 4);
});

test("Garmin metrics and insights are collapsed behind Watch metrics", () => {
  const context = loadPwaContext();
  const header = vm.runInContext(`garminWorkoutHeader(
    { id: 201, startedAt: 1700000000000, note: "" },
    { duration: "42:10" },
    [{ name: "Bench Press", sets: [{ id: 301, weight: 60, reps: 10 }] }],
    false
  )`, context);
  const html = vm.runInContext(`garminWorkoutMetricsCard({
    duration: "42:10",
    gymCalories: 210,
    garminCalories: 180,
    avgHeartRate: 128,
    maxHeartRate: 166,
    heartRateZone: "Z4",
    completion: null,
    omittedSetIntervalCount: null,
    sets: []
  }, 3)`, context);

  assert.match(header, /<strong>1 set<\/strong><small>1 exercise<\/small>/);
  assert.match(html, /^<details class="panel garmin-metrics garmin-metrics-disclosure">/);
  assert.doesNotMatch(html, /^<details[^>]*\sopen(?:\s|>)/);
  assert.match(html, />Watch metrics<\/h2>/);
  assert.match(html, /128 bpm/);
  assert.match(html, /180 kcal/);
});

test("Progress is read-only and uses a compact bounded searchable picker", () => {
  const context = loadPwaContext();
  const exercises = Array.from({ length: 95 }, (_, index) => ({
    id: index + 1,
    name: index === 94 ? '<img src=x onerror="alert(1)">' : `Custom Exercise ${index + 1}`
  }));
  vm.runInContext(`
    state = {
      ...defaultAppState(),
      language: "en",
      exercises: ${JSON.stringify(exercises)},
      sessions: [],
      mappings: {},
      progressExerciseId: 1
    };
    progressExerciseSearchQuery = "";
  `, context);

  const screen = vm.runInContext("progressScreen()", context);
  assert.match(screen, /data-action="open-progress-exercise-picker"/);
  assert.doesNotMatch(screen, /progress-exercise-options|data-action="delete-set"/);

  const sheet = vm.runInContext("progressExercisePickerSheetMarkup()", context);
  assert.equal((sheet.match(/<article class="progress-exercise-option/g) || []).length, 80);
  assert.match(sheet, /15 more matches\. Refine the search to see them\./);
  assert.doesNotMatch(sheet, /<img src=x onerror=/);
  assert.match(sheet, /&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt;/);

  const history = vm.runInContext(`progressHistoryCard({
    session: { id: 4, startedAt: 1700000000000 },
    sets: [{ id: 5, weight: 50, reps: 10 }]
  })`, context);
  assert.doesNotMatch(history, /data-action="delete-set"|data-action="edit-set"/);
});

test("workout history scroll position survives detail navigation", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    globalThis.scroller = { dataset: { scrollKey: "workouts:root" }, scrollTop: 428 };
    app.querySelector = () => globalThis.scroller;
    rememberVisibleScroll();
    globalThis.scroller = { dataset: { scrollKey: "detail:201" }, scrollTop: 0 };
    restoreVisibleScroll();
    globalThis.detailTop = globalThis.scroller.scrollTop;
    globalThis.scroller = { dataset: { scrollKey: "workouts:root" }, scrollTop: 0 };
    restoreVisibleScroll();
    globalThis.restoredTop = globalThis.scroller.scrollTop;
  `, context);

  assert.equal(vm.runInContext("globalThis.detailTop", context), 0);
  assert.equal(vm.runInContext("globalThis.restoredTop", context), 428);
});

test("saved-workout details bind exclusive expansion and synchronize aria-expanded", () => {
  assert.match(appSource, /details\[data-saved-workout-exercise\]/);
  assert.match(appSource, /if \(other !== details && other\.open\) other\.open = false/);
  assert.match(appSource, /setAttribute\("aria-expanded", String\(item\.open\)\)/);
});
