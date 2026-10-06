import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile(new URL("../pwa/app.js", import.meta.url), "utf8");
const stateContractSource = await readFile(new URL("../pwa/state-contract.js", import.meta.url), "utf8");
const garminCloudSource = await readFile(new URL("../pwa/garmin-cloud-sync.js", import.meta.url), "utf8");
const russianTextSource = await readFile(new URL("../pwa/russian-text.js", import.meta.url), "utf8");

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
  vm.runInContext(russianTextSource, context);
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

test("saved workout read mode uses the live card with completed-style set rows", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  const html = vm.runInContext("detailScreen(201)", context);

  assert.doesNotMatch(html, /READ MODE|EDIT MODE|saved-workout-mode|saved-workout-table|<table/);
  assert.equal((html.match(/data-action="edit-workout"/g) || []).length, 1);
  assert.match(html, /<section class="hero-panel workout-detail-hero">[\s\S]*data-action="edit-workout"[\s\S]*<\/section>/);
  assert.equal((html.match(/data-saved-workout-exercise/g) || []).length, 2);
  assert.doesNotMatch(html, /<details[^>]*data-saved-workout-exercise[^>]*\sopen(?:\s|>)/);
  assert.match(html, /2 sets · 18 reps · 1,120 kg volume/);
  assert.match(html, /1 set · 5 reps · 450 kg volume/);
  assert.equal((html.match(/class="active-set-row completed saved-set-row"/g) || []).length, 3);
  assert.match(html, /<span class="active-set-summary-text">60 kg × 10<\/span>/);
  assert.match(html, /exercise-media-thumb/);
  assert.doesNotMatch(html, /data-action="(?:delete-session|delete-set|edit-set|add-saved-workout-set|open-saved-exercise-more|open-workout-exercise-picker|save-saved-set|timer|detail-add-set)"/);
  assert.doesNotMatch(html, /saved-workout-details|data-saved-detail/);
  assert.match(html, /data-action="share-session"/);
});

test("saved read mode badges only the set that beats the earlier history", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    state.sessions.unshift({
      id: 200, startedAt: 1690000000000, note: "",
      sets: [{ id: 290, exerciseName: "Bench Press", weight: 60, reps: 10, orderIndex: 0 }]
    });
  `, context);
  const html = vm.runInContext("detailScreen(201)", context);
  assert.equal((html.match(/personal-record-badge/g) || []).length, 1);
  const recordRow = html.match(/<div class="active-set-row completed saved-set-row" data-saved-set-row="302"[\s\S]*?<\/div><\/div><\/div>/)?.[0] || "";
  assert.match(recordRow, /personal-record-badge/);
  assert.equal(vm.runInContext("isPr(state.sessions[1], { name: 'Bench Press' })", context), true);
});

test("saved workout edit mode shows numbered rows, inline editors, menus and dashed add buttons", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext("workoutDetailEditSessionId = 201", context);
  const html = vm.runInContext("detailScreen(201)", context);

  assert.doesNotMatch(html, /READ MODE|EDIT MODE|saved-workout-mode|saved-workout-table|data-action="edit-set"|apply-edit-set/);
  assert.equal((html.match(/data-action="finish-workout-edit"/g) || []).length, 1);
  assert.doesNotMatch(html, /data-action="edit-workout"/);
  assert.match(html, /data-action="delete-session"/);
  assert.match(html, /<span class="active-set-index" aria-hidden="true">2<\/span>/);
  assert.equal((html.match(/data-saved-set-deletable=/g) || []).length, 3);
  // One editor layout: two equal capsules with the value inputs inside, and a visible trash icon.
  assert.equal((html.match(/class="set-editor-capsules"/g) || []).length, 3);
  assert.equal((html.match(/class="set-editor-capsule"/g) || []).length, 6);
  assert.match(html, /<div class="set-editor-capsule" role="group" data-step-field="weight"[^>]*>[\s\S]*?<span class="set-editor-value"><input class="set-editor-input" data-saved-set-id="\d+" data-saved-field="weight"[^>]*><span class="set-editor-unit" aria-hidden="true">kg<\/span><\/span>/);
  assert.match(html, /<span class="set-editor-value"><input class="set-editor-input" data-saved-set-id="\d+" data-saved-field="reps"/);
  assert.doesNotMatch(html, /active-set-capsule-label|active-set-value-line|data-saved-reps-display/);
  assert.match(html, /<button class="set-delete-icon" type="button" data-action="delete-set" data-id="\d+" data-session="201" aria-label="Delete set 1 for Bench Press"><svg/);
  assert.equal((html.match(/class="set-delete-icon"/g) || []).length, 3);
  assert.equal((html.match(/data-action="save-saved-set"/g) || []).length, 3);
  assert.match(html, /data-action="saved-step-weight"[^>]*aria-label="Increase weight by 2\.5"/);
  assert.match(html, /data-action="saved-step-reps"/);
  assert.equal((html.match(/data-action="add-saved-workout-set"/g) || []).length, 2);
  assert.match(html, /\+ Set<\/button>/);
  assert.equal((html.match(/data-action="open-saved-exercise-more"/g) || []).length, 2);
  assert.match(html, /aria-label="Exercise options: Bench Press"/);
  assert.match(html, /class="button full saved-workout-add-exercise"[^>]*data-action="open-workout-exercise-picker"[^>]*>\+ Add exercise<\/button>/);
  assert.doesNotMatch(html, /Add Exercise to This Workout/);
  assert.match(html, /<section class="panel saved-workout-details"[\s\S]*Date and note[\s\S]*data-saved-detail-date value="2023-11-15"/);
  assert.match(html, /data-saved-details-save disabled>Save<\/button>/);
  assert.ok(html.indexOf("saved-workout-details") < html.indexOf("saved-workout-exercise-list"));
  assert.ok(html.indexOf("saved-workout-exercise-list") < html.indexOf("saved-workout-add-exercise"));

  vm.runInContext("state.language = 'uk'", context);
  const uk = vm.runInContext("detailScreen(201)", context);
  assert.match(uk, /Дата і нотатка/);
  assert.match(uk, /\+ Додати вправу/);
  assert.match(uk, /Видалити підхід 1 для/);
  vm.runInContext("state.language = 'ru'", context);
  const ru = vm.runInContext("detailScreen(201)", context);
  assert.match(ru, /Дата и заметка/);
  assert.match(ru, /\+ Добавить упражнение/);
  assert.match(ru, /Удалить подход 1 для/);
});

test("saved workout edit mode gates mutations and adds a set without a rest callback", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext("workoutDetailEditSessionId = 201", context);

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

test("inline set editor saves valid values, rejects invalid drafts and rolls back a failed save", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    workoutDetailEditSessionId = 201;
    render = () => {};
    saveState = () => {};
    showToast = message => { globalThis.lastToast = message; };
    savedEditUiFor(201).drafts.set(301, { weight: "62,5", reps: "12" });
    savedEditUiFor(201).expanded.add(301);
  `, context);
  assert.match(vm.runInContext("detailScreen(201)", context), /data-saved-set-details="301" open/);
  assert.match(vm.runInContext("detailScreen(201)", context), /data-saved-field="weight"[^>]*value="62,5"/);
  assert.equal(vm.runInContext("saveSavedSet(301, 201)", context), true);
  assert.equal(vm.runInContext("state.sessions[0].sets[0].weight", context), 62.5);
  assert.equal(vm.runInContext("state.sessions[0].sets[0].reps", context), 12);
  assert.equal(vm.runInContext("savedEditUiFor(201).drafts.has(301)", context), false);
  assert.equal(vm.runInContext("savedEditUiFor(201).expanded.has(301)", context), false);

  for (const [weight, reps] of [["-1", "5"], ["abc", "5"], ["60", "0"], ["60", "1.5"], ["60", ""],
    [String(context.window.GymStateContract.LIMITS.weightMax + 1), "5"],
    ["60", String(context.window.GymStateContract.LIMITS.repsMax + 1)]]) {
    vm.runInContext(`savedEditUiFor(201).drafts.set(302, { weight: ${JSON.stringify(weight)}, reps: ${JSON.stringify(reps)} })`, context);
    assert.equal(vm.runInContext("saveSavedSet(302, 201)", context), undefined, `${weight} x ${reps}`);
    assert.equal(vm.runInContext("state.sessions[0].sets[1].weight", context), 65);
    assert.equal(vm.runInContext("state.sessions[0].sets[1].reps", context), 8);
  }

  vm.runInContext(`
    savedEditUiFor(201).drafts.set(302, { weight: "70", reps: "6" });
    saveState = () => { throw new Error("quota"); };
  `, context);
  assert.equal(vm.runInContext("saveSavedSet(302, 201)", context), undefined);
  assert.equal(vm.runInContext("state.sessions[0].sets[1].weight", context), 65);
  assert.equal(vm.runInContext("state.sessions[0].sets[1].reps", context), 8);

  vm.runInContext("workoutDetailEditSessionId = null", context);
  assert.equal(vm.runInContext("saveSavedSet(302, 201)", context), false);
});

test("saved steppers move weight by 2.5 and reps by 1 inside the draft inputs", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    workoutDetailEditSessionId = 201;
    nav = [{ name: "workouts" }, { name: "detail", id: 201 }];
    const weight = { value: "60", dataset: { savedSetId: "301", savedField: "weight" } };
    const reps = { value: "10", dataset: { savedSetId: "301", savedField: "reps" } };
    app.querySelector = selector => selector.includes('data-saved-field="weight"') ? weight
      : selector.includes('data-saved-field="reps"') ? reps : null;
    globalThis.weightInput = weight;
    globalThis.repsInput = reps;
  `, context);
  assert.equal(vm.runInContext("applySavedStep(301, 'weight', 1)", context), true);
  assert.equal(vm.runInContext("weightInput.value", context), "62.5");
  assert.equal(vm.runInContext("applySavedStep(301, 'reps', -1)", context), true);
  assert.equal(vm.runInContext("repsInput.value", context), "9");
  assert.deepEqual(JSON.parse(vm.runInContext("JSON.stringify(savedEditUiFor(201).drafts.get(301))", context)), { weight: "62.5", reps: "9" });
  assert.equal(vm.runInContext("state.sessions[0].sets[0].weight", context), 60);
  vm.runInContext("workoutDetailEditSessionId = null", context);
  assert.equal(vm.runInContext("applySavedStep(301, 'weight', 1)", context), false);
});

test("date and note panel keeps the time of day, trims and bounds the note, and keeps Garmin notes read-only", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    workoutDetailEditSessionId = 201;
    render = () => {};
    saveState = () => {};
    showToast = message => { globalThis.lastToast = message; };
    globalThis.original = state.sessions[0].startedAt;
    const date = { value: "2023-11-10" };
    const note = { value: "  Felt strong  " };
    app.querySelector = selector => selector.includes("detail-date") ? date : selector.includes("detail-note") ? note : null;
    globalThis.dateInput = date;
    globalThis.noteInput = note;
  `, context);
  assert.equal(vm.runInContext("saveSavedWorkoutDetails(201)", context), true);
  assert.equal(vm.runInContext("state.sessions[0].note", context), "Felt strong");
  const moved = vm.runInContext("state.sessions[0].startedAt", context);
  const originalDate = new Date(vm.runInContext("original", context));
  const movedDate = new Date(moved);
  assert.equal(movedDate.getDate(), 10);
  assert.deepEqual(
    [movedDate.getHours(), movedDate.getMinutes(), movedDate.getSeconds()],
    [originalDate.getHours(), originalDate.getMinutes(), originalDate.getSeconds()]
  );

  vm.runInContext(`dateInput.value = localDateInputValue(state.sessions[0].startedAt); noteInput.value = "   ";`, context);
  assert.equal(vm.runInContext("saveSavedWorkoutDetails(201)", context), true);
  assert.equal(vm.runInContext("Object.hasOwn(state.sessions[0], 'note')", context), false);

  const before = vm.runInContext("state.sessions[0].startedAt", context);
  vm.runInContext(`dateInput.value = "2999-01-01"`, context);
  assert.equal(vm.runInContext("saveSavedWorkoutDetails(201)", context), undefined);
  assert.equal(vm.runInContext("state.sessions[0].startedAt", context), before);
  vm.runInContext(`dateInput.value = localDateInputValue(state.sessions[0].startedAt); noteInput.value = "x".repeat(SAVED_WORKOUT_NOTE_MAX_CHARACTERS + 1)`, context);
  assert.equal(vm.runInContext("saveSavedWorkoutDetails(201)", context), undefined);
  assert.equal(vm.runInContext("Object.hasOwn(state.sessions[0], 'note')", context), false);

  vm.runInContext(`
    noteInput.value = "kept";
    saveState = () => { throw new Error("quota"); };
  `, context);
  assert.equal(vm.runInContext("saveSavedWorkoutDetails(201)", context), undefined);
  assert.equal(vm.runInContext("Object.hasOwn(state.sessions[0], 'note')", context), false);

  const garminNote = "Garmin · Duration 12:34 · Gym kcal 40 · Garmin kcal 38 · Avg HR 130 · Max HR 165 · HR zone Z3";
  vm.runInContext(`
    saveState = () => {};
    state.sessions[0].note = ${JSON.stringify(garminNote)};
    dateInput.value = "2023-11-09";
    noteInput.value = "tampered";
  `, context);
  const panel = vm.runInContext("detailScreen(201)", context);
  assert.match(panel, /<textarea[^>]*data-saved-detail-note[^>]*readonly>/);
  assert.match(panel, /stays read-only/);
  assert.equal(vm.runInContext("saveSavedWorkoutDetails(201)", context), true);
  assert.equal(vm.runInContext("state.sessions[0].note", context), garminNote);
  assert.equal(new Date(vm.runInContext("state.sessions[0].startedAt", context)).getDate(), 9);
});

test("date and note panel escapes the stored note and bounds the textarea", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    workoutDetailEditSessionId = 201;
    state.sessions[0].note = '</textarea><img src=x onerror="alert(1)">';
  `, context);
  const html = vm.runInContext("detailScreen(201)", context);
  assert.doesNotMatch(html, /<img src=x onerror=/);
  assert.match(html, /&lt;\/textarea&gt;&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt;/);
  assert.match(html, /data-saved-detail-note maxlength="4000"/);
});

test("saved exercise names and notes stay escaped in the rebuilt card", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    workoutDetailEditSessionId = 201;
    state.sessions[0].sets[2].exerciseName = '"><img src=x onerror=alert(1)>';
  `, context);
  const html = vm.runInContext("detailScreen(201)", context);
  assert.doesNotMatch(html, /<img src=x onerror=/);
  assert.match(html, /&quot;&gt;&lt;img src=x onerror=alert\(1\)&gt;/);
});

test("remove exercise is offered only while another exercise with sets remains", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`workoutDetailEditSessionId = 201; state.sessions[0].sets = state.sessions[0].sets.filter(set => set.exerciseName === "Bench Press")`, context);
  const html = vm.runInContext("detailScreen(201)", context);
  assert.doesNotMatch(html, /open-saved-exercise-more/);
  assert.match(html, /data-action="add-saved-workout-set"/);
  assert.equal(vm.runInContext("openSavedExerciseMoreMenu(201, 'Bench Press')", context), false);
  assert.equal(vm.runInContext("requestRemoveSavedExercise(201, 'Bench Press')", context), false);
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

test("Garmin free activity stays metrics-only in history and detail", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    state = {
      ...defaultAppState(),
      language: "en",
      exercises: [{ id: 101, name: "Bench Press" }],
      sessions: [{
        id: 901,
        startedAt: 1700000000000,
        durationSeconds: 754,
        note: "Garmin · Duration 12:34 · Gym kcal 40 · Garmin kcal 38 · Avg HR 130 · Max HR 165 · HR zone Z3",
        sets: []
      }],
      mappings: {}
    };
    nav = [{ name: "workouts" }, { name: "detail", id: 901 }];
    workoutDetailEditSessionId = null;
  `, context);

  const history = vm.runInContext("workoutItem(state.sessions[0])", context);
  const detail = vm.runInContext("detailScreen(901)", context);

  assert.match(history, /GARMIN · FREE/);
  assert.match(history, /Free workout/);
  assert.match(history, /12:34/);
  assert.doesNotMatch(history, /Exercises|Sets|Volume|Note:/);

  assert.match(detail, /Activity only/);
  assert.match(detail, /12:34/);
  assert.match(detail, /40 kcal/);
  assert.match(detail, /130 bpm/);
  assert.match(detail, /data-action="delete-session"/);
  assert.match(detail, /data-action="edit-workout"/);
  assert.match(detail, /Add exercises/);
  assert.doesNotMatch(detail, /data-action="(?:share-session|add-saved-workout-set|edit-set|delete-set)"/);
  assert.doesNotMatch(detail, /Exercises|Sets|Reps|Volume|Garmin · Duration/);
});

test("Garmin strength history replaces telemetry with a compact label and preserves a separable note", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    state = {
      ...defaultAppState(),
      language: "en",
      exercises: [{ id: 101, name: "Bench Press" }],
      sessions: [{
        id: 902,
        startedAt: 1700000000000,
        note: "Garmin · Duration 12:34 · Gym kcal 40 · Garmin kcal 38 · Avg HR 130 · Max HR 165 · HR zone Z3",
        sets: [{ id: 903, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }]
      }],
      mappings: {}
    };
  `, context);

  const telemetryOnly = vm.runInContext("workoutItem(state.sessions[0])", context);
  assert.match(telemetryOnly, /Garmin workout metrics/);
  assert.doesNotMatch(telemetryOnly, /Duration 12:34|Avg HR 130|HR zone Z3/);

  vm.runInContext(`state.sessions[0].note += "\\nFelt strong <ScRiPt>alert(1)</sCrIpT>"`, context);
  const withUserNote = vm.runInContext("workoutItem(state.sessions[0])", context);
  assert.match(withUserNote, /Garmin workout metrics · Note: Felt strong/);
  assert.match(withUserNote, /&lt;ScRiPt&gt;alert\(1\)&lt;\/sCrIpT&gt;/);
  assert.doesNotMatch(withUserNote, /<script\b/i);

  vm.runInContext(`state.language = "ru"`, context);
  assert.match(
    vm.runInContext("workoutItem(state.sessions[0])", context),
    /Показатели тренировки Garmin · Заметка: Felt strong/
  );
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
    progressHubSection = "exercises";
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

test("saved workout cards keep their own open state and no longer force exclusive expansion", () => {
  assert.doesNotMatch(appSource, /if \(other !== details && other\.open\) other\.open = false/);
  assert.match(appSource, /details\[data-saved-workout-exercise\]/);
  assert.match(appSource, /\.open\.set\(key, details\.open\)/);
});

test("free workout enrichment preserves watch metrics through save and sync replay", () => {
  const context = loadPwaContext();
  installWorkoutFixture(context);
  vm.runInContext(`
    activeAccount = { id: "free-workout-owner", name: "Local", remote: false };
    state.sessions[0].sets = [];
    state.sessions[0].durationSeconds = 754;
    state.sessions[0].note = "Garmin · Duration 12:34 · Gym kcal 40 · Garmin kcal 38 · Avg HR 130 · Max HR 165 · HR zone Z3";
    globalThis.original = { ...state.sessions[0] };
    globalThis.exactItems = activityOnlySyncItems(state);
    render = () => {};
    queueRemoteSave = () => {};
    showToast = message => { globalThis.lastToast = message; };
  `, context);
  assert.equal(vm.runInContext("quickAddExercise(101, 201)", context), false);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 0);
  vm.runInContext("workoutDetailEditSessionId = 201", context);
  assert.match(vm.runInContext("detailScreen(201)", context), /data-action="open-workout-exercise-picker"/);
  assert.equal(vm.runInContext("quickAddExercise(101, 201)", context), true);
  vm.runInContext(`
    state.sessions[0].sets[0].weight = 55;
    state.sessions[0].sets[0].reps = 12;
    saveState();
    globalThis.saved = JSON.parse(localStorage.getItem(activeStorageKey()));
    globalThis.replayed = installActivityOnlyItems(state, exactItems);
  `, context);
  assert.equal(vm.runInContext("saved.sessions[0].sets[0].weight", context), 55);
  assert.equal(vm.runInContext("replayed.sessions.length", context), 1);
  assert.equal(vm.runInContext("replayed.sessions[0].sets[0].reps", context), 12);
  for (const key of ["id", "startedAt", "durationSeconds", "note"]) {
    assert.equal(vm.runInContext(`replayed.sessions[0].${key} === original.${key}`, context), true);
  }
  assert.equal(vm.runInContext("JSON.stringify(activityOnlySyncItems(state, exactItems)) === JSON.stringify(exactItems)", context), true);
  assert.equal(vm.runInContext("loadWorkoutDurationLedger(activeAccount).ledger.items[0].durationSeconds", context), 754);
  vm.runInContext(`
    state.sessions = [{ ...original, sets: [] }];
    localStorage.setItem = () => { throw new Error("quota"); };
  `, context);
  vm.runInContext("quickAddExercise(102, 201)", context);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 0);
  assert.equal(vm.runInContext("state.sessions[0].note === original.note", context), true);
  vm.runInContext("workoutDetailEditSessionId = null", context);
  assert.equal(vm.runInContext("quickAddExercise(101, 201)", context), false);
});
