import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, russianSource, stateContractSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8")
]);

const LOCAL_ACCOUNT_ID = "local-v2-11111111111111111111111111111111";

function createStorage() {
  const values = new Map();
  let failNextSetKey = null;
  return {
    values,
    getItem: key => values.get(key) ?? null,
    setItem(key, value) {
      if (key === failNextSetKey) {
        failNextSetKey = null;
        throw new Error(`synthetic storage failure for ${key}`);
      }
      values.set(key, String(value));
    },
    removeItem: key => values.delete(key),
    failNextSet(key) {
      failNextSetKey = key;
    }
  };
}

function loadContext(options = {}) {
  const localStorage = options.localStorage || createStorage();
  const sessionStorage = createStorage();
  const runtimeNodes = new Map();
  const runtimeLists = new Map();
  const appNode = {
    innerHTML: "",
    children: [],
    classList: { toggle() {} },
    querySelectorAll: selector => runtimeLists.get(selector) || [],
    querySelector: selector => runtimeNodes.get(selector) || null
  };
  const context = {
    AbortController,
    atob,
    btoa,
    clearInterval,
    clearTimeout,
    console,
    crypto: webcrypto,
    Date,
    document: {
      activeElement: null,
      documentElement: { lang: "en" },
      querySelector: selector => selector === "#app" ? appNode : (runtimeNodes.get(selector) || null)
    },
    fetch: () => Promise.reject(new Error("network disabled in destructive confirmation tests")),
    history: { replaceState() {}, pushState() {}, state: null },
    localStorage,
    Map,
    navigator: {},
    Promise,
    requestAnimationFrame: callback => callback(),
    Response,
    sessionStorage,
    Set,
    setInterval,
    setTimeout,
    TextDecoder,
    TextEncoder,
    URL,
    URLSearchParams,
    window: {
      addEventListener() {},
      location: { search: "?access_token=test", hash: "", pathname: "/", replace() {} },
      GymProgressionRules: {
        MAX_SUPPORTED_XP: 2147483647,
        sessionXP: () => 0,
        requirementForLevel: () => 200,
        cumulativeXPForLevel: () => 0,
        levelProgress: () => ({
          level: 1,
          currentLevelXp: 0,
          xpForNextLevel: 200,
          progressFraction: 0
        }),
        currentWeeklyStreak: () => 0,
        bestWeeklyStreakDuring: () => 0
      }
    }
  };
  context.window.crypto = webcrypto;
  context.window.document = context.document;
  context.window.history = context.history;
  context.window.localStorage = localStorage;
  context.window.navigator = context.navigator;
  context.window.self = context.window;
  context.window.sessionStorage = sessionStorage;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(russianSource, context);
  vm.runInContext(appSource, context);
  vm.runInContext(`
    activeAccount = {
      id: ${JSON.stringify(LOCAL_ACCOUNT_ID)},
      name: "Owner",
      localIdVersion: LOCAL_ACCOUNT_ID_VERSION
    };
    accountEpoch = 7;
    state = defaultAppState();
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveAccountList([activeAccount]);
    saveState({ queueRemote: false, markDirty: false });
  `, context);
  context.appNode = appNode;
  context.localStorage = localStorage;
  context.runtimeLists = runtimeLists;
  context.runtimeNodes = runtimeNodes;
  return context;
}

function storedState(context) {
  return context.localStorage.getItem(`gym-pwa-account:${LOCAL_ACCOUNT_ID}`);
}

test("destructive controls use explicit accessible in-app confirmation markup", () => {
  assert.match(appSource, /requestedRole === "alertdialog"/);
  assert.match(appSource, /data-action="cancel-destructive" data-modal-initial-focus/);
  assert.match(appSource, /data-action="confirm-delete-exercise"/);
  assert.match(appSource, /data-action="confirm-delete-set"/);
  assert.match(appSource, /data-action="confirm-import"/);
  assert.match(appSource, /event\.target === modalElement/);
  assert.match(appSource, /handleDestructiveModalKeydown/);
  assert.match(appSource, /aria-describedby=/);
  assert.match(appSource, /delete-exercise-confirm-target delete-exercise-confirm-description/);
  assert.match(appSource, /delete-set-confirm-target delete-set-confirm-detail delete-set-confirm-description/);
  assert.match(appSource, /element\.inert = true/);
  assert.match(appSource, /focusStableScreenContext\(\)/);
  assert.match(appSource, /formatLocalizedSetWeight\(location\.set\.weight\)/);
  assert.doesNotMatch(appSource, /Number\(location\.set\.weight\)\.toFixed\(1\) kg/);
  const labelledDeleteSets = appSource.match(
    /data-action="delete-set"[^>]+data-session="[^>]+aria-label="\$\{txAttr\("Delete set"/g
  ) || [];
  assert.ok(labelledDeleteSets.length >= 3, "every persisted-set delete control needs an accessible name");
});

test("exercise deletion cancels without persistence and rejects stale account intent", () => {
  const context = loadContext();
  let successContextFocused = false;
  let emptyTopbarFocused = false;
  const heading = {
    hasAttribute: () => false,
    setAttribute() {},
    focus() { successContextFocused = true; }
  };
  context.runtimeNodes.set("main[data-scroll-key]", {
    dataset: { scrollKey: "test" },
    scrollTop: 0,
    addEventListener() {},
    querySelector: selector => selector === "h2" ? heading : null
  });
  context.runtimeNodes.set(".topbar h1", {
    textContent: "",
    focus() { emptyTopbarFocused = true; }
  });
  vm.runInContext(`
    state.exercises.push({ id: 9001, name: "Custom <img src=x>" });
    saveState({ queueRemote: false, markDirty: false });
  `, context);
  const before = storedState(context);

  vm.runInContext("deleteExercise(9001)", context);
  assert.equal(vm.runInContext("modal.type", context), "confirm-delete-exercise");
  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /role="alertdialog"/);
  assert.match(markup, /Custom &lt;img src=x&gt;/);
  assert.doesNotMatch(markup, /<img src=x>/);
  vm.runInContext("closeModal()", context);
  assert.equal(storedState(context), before);
  assert.equal(vm.runInContext("state.exercises.some(item => item.id === 9001)", context), true);
  assert.equal(vm.runInContext("remoteSaveTimer", context), null);

  vm.runInContext("deleteExercise(9001); accountEpoch += 1; confirmDeleteExercise()", context);
  assert.equal(storedState(context), before);
  assert.equal(vm.runInContext("state.exercises.some(item => item.id === 9001)", context), true);

  vm.runInContext("deleteExercise(9001); confirmDeleteExercise()", context);
  assert.equal(vm.runInContext("state.exercises.some(item => item.id === 9001)", context), false);
  assert.equal(JSON.parse(storedState(context)).exercises.some(item => item.id === 9001), false);
  assert.equal(successContextFocused, true);
  assert.equal(emptyTopbarFocused, false);
});

test("set deletion cancels cleanly and fails closed when the workout impact changes", () => {
  const context = loadContext();
  vm.runInContext(`
    state.sessions.push({
      id: 8001,
      startedAt: 1760000000000,
      note: "Safety test",
      sets: [
        { id: 8101, exerciseName: "Squat", catalogKey: "squat", weight: 100, reps: 5, orderIndex: 0 },
        { id: 8102, exerciseName: "Squat", catalogKey: "squat", weight: 90, reps: 10, orderIndex: 1 }
      ]
    });
    saveState({ queueRemote: false, markDirty: false });
  `, context);
  const before = storedState(context);

  vm.runInContext("deleteSet(8101, 8001)", context);
  assert.equal(vm.runInContext("modal.type", context), "confirm-delete-set");
  assert.match(vm.runInContext("modalMarkup()", context), /role="alertdialog"/);
  vm.runInContext("closeModal()", context);
  assert.equal(storedState(context), before);
  assert.equal(vm.runInContext("setLocation(8101, 8001) !== null", context), true);

  vm.runInContext("deleteSet(8101, 8001); setLocation(8102, 8001).set.reps = 11; confirmDeleteSet()", context);
  assert.equal(storedState(context), before);
  assert.equal(vm.runInContext("setLocation(8101, 8001) !== null", context), true);

  vm.runInContext("setLocation(8102, 8001).set.reps = 10; deleteSet(8101, 8001); confirmDeleteSet()", context);
  assert.equal(vm.runInContext("setLocation(8101, 8001)", context), null);
  assert.deepEqual(JSON.parse(storedState(context)).sessions[0].sets.map(set => set.id), [8102]);
});

test("set deletion preview localizes its decimal number and weight unit", () => {
  const context = loadContext();
  vm.runInContext(`
    state.sessions = [{
      id: 8151,
      startedAt: 1760000000000,
      note: "Localized preview",
      sets: [{ id: 8152, exerciseName: "Squat", catalogKey: "squat", weight: 42.5, reps: 8, orderIndex: 0 }]
    }];
  `, context);

  const cases = new Map([
    ["en", "42.5 kg × 8"],
    ["uk", "42,5 кг × 8"],
    ["ru", "42,5 кг × 8"]
  ]);
  for (const [language, expected] of cases) {
    vm.runInContext(`
      state.language = ${JSON.stringify(language)};
      saveState({ queueRemote: false, markDirty: false });
      deleteSet(8152, 8151);
    `, context);
    const detail = vm.runInContext("modal.intent.preview.detail", context);
    assert.ok(detail.endsWith(expected), `${language}: ${detail}`);
    vm.runInContext("modal = null", context);
  }
});

test("set deletion is bound to its session when imported set IDs collide", () => {
  const context = loadContext();
  vm.runInContext(`
    state.sessions = [
      {
        id: 8201,
        startedAt: 1760000000000,
        note: "First",
        sets: [{ id: 8301, exerciseName: "Squat", weight: 100, reps: 5, orderIndex: 0 }]
      },
      {
        id: 8202,
        startedAt: 1760100000000,
        note: "Second",
        sets: [{ id: 8301, exerciseName: "Deadlift", weight: 120, reps: 3, orderIndex: 0 }]
      }
    ];
    saveState({ queueRemote: false, markDirty: false });
    deleteSet(8301, 8202);
  `, context);

  assert.equal(vm.runInContext("modal.type", context), "confirm-delete-set");
  assert.match(vm.runInContext("modalMarkup()", context), /Deadlift/);
  vm.runInContext("confirmDeleteSet()", context);
  const saved = JSON.parse(storedState(context));
  assert.deepEqual(saved.sessions[0].sets.map(set => set.exerciseName), ["Squat"]);
  assert.deepEqual(saved.sessions[1].sets, []);
});

test("same-account state saved by another tab invalidates an open confirmation", () => {
  const sharedStorage = createStorage();
  const firstTab = loadContext({ localStorage: sharedStorage });
  const secondTab = loadContext({ localStorage: sharedStorage });
  const fixture = `state.sessions = [{
    id: 8401,
    startedAt: 1760000000000,
    note: "Shared",
    sets: [{ id: 8501, exerciseName: "Squat", weight: 100, reps: 5, orderIndex: 0 }]
  }]; saveState({ queueRemote: false, markDirty: false });`;
  vm.runInContext(fixture, firstTab);
  vm.runInContext(fixture, secondTab);

  vm.runInContext("deleteSet(8501, 8401)", firstTab);
  vm.runInContext("state.sessions[0].note = 'Newer tab edit'; saveState({ queueRemote: false, markDirty: false })", secondTab);
  const newerStoredState = storedState(secondTab);
  vm.runInContext("confirmDeleteSet()", firstTab);

  assert.equal(storedState(firstTab), newerStoredState);
  assert.equal(JSON.parse(newerStoredState).sessions[0].sets.length, 1);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", firstTab), 1);

  vm.runInContext("deleteSet(8501, 8401)", firstTab);
  assert.equal(vm.runInContext("modal", firstTab), null);
  assert.equal(storedState(firstTab), newerStoredState);
});

test("duplicate exercise and session IDs fail closed without deleting several rows", () => {
  const context = loadContext();
  let confirmCalls = 0;
  context.window.confirm = () => {
    confirmCalls += 1;
    return true;
  };
  vm.runInContext(`
    state.exercises.push({ id: 8601, name: "Duplicate A" }, { id: 8601, name: "Duplicate B" });
    state.sessions = [
      { id: 8701, startedAt: 1760000000000, note: "A", sets: [] },
      { id: 8701, startedAt: 1760100000000, note: "B", sets: [] }
    ];
    saveState({ queueRemote: false, markDirty: false });
  `, context);
  const before = storedState(context);

  vm.runInContext("deleteExercise(8601); deleteSession(8701)", context);

  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(confirmCalls, 0);
  assert.equal(storedState(context), before);
  assert.equal(vm.runInContext("state.exercises.filter(item => item.id === 8601).length", context), 2);
  assert.equal(vm.runInContext("state.sessions.filter(item => item.id === 8701).length", context), 2);
});

test("destructive alertdialog traps focus, closes on Escape, and restores its invoker", () => {
  const context = loadContext();
  let restoredFocus = false;
  const invoker = {
    dataset: { action: "delete-exercise", id: "8801" },
    focus() { restoredFocus = true; }
  };
  context.runtimeLists.set('[data-action="delete-exercise"]', [invoker]);
  vm.runInContext(`
    state.exercises.push({ id: 8801, name: "Focus Test" });
    saveState({ queueRemote: false, markDirty: false });
    deleteExercise(8801, { action: "delete-exercise", id: 8801 });
  `, context);

  const buttons = Array.from({ length: 3 }, () => ({
    getAttribute: () => null,
    focus() { context.document.activeElement = this; }
  }));
  context.testModalElement = {
    contains: element => buttons.includes(element),
    querySelectorAll: () => buttons
  };
  context.document.activeElement = buttons.at(-1);
  context.testTabEvent = {
    key: "Tab",
    shiftKey: false,
    prevented: false,
    preventDefault() { this.prevented = true; }
  };
  vm.runInContext("handleDestructiveModalKeydown(testModalElement, testTabEvent)", context);
  assert.equal(context.testTabEvent.prevented, true);
  assert.equal(context.document.activeElement, buttons[0]);

  context.testEscapeEvent = {
    key: "Escape",
    prevented: false,
    preventDefault() { this.prevented = true; }
  };
  vm.runInContext("handleDestructiveModalKeydown(testModalElement, testEscapeEvent)", context);
  assert.equal(context.testEscapeEvent.prevented, true);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(restoredFocus, true);
});

test("full import remains pending until confirmation and is account and state bound", () => {
  const context = loadContext();
  let successContextFocused = false;
  let emptyTopbarFocused = false;
  const heading = {
    hasAttribute: () => false,
    setAttribute() {},
    focus() { successContextFocused = true; }
  };
  context.runtimeNodes.set("main[data-scroll-key]", {
    dataset: { scrollKey: "test" },
    scrollTop: 0,
    addEventListener() {},
    querySelector: selector => selector === "h2" ? heading : null
  });
  context.runtimeNodes.set(".topbar h1", {
    textContent: "",
    focus() { emptyTopbarFocused = true; }
  });
  const backup = {
    schemaVersion: 2,
    owner: { accountId: LOCAL_ACCOUNT_ID, userId: null, email: null, remote: false },
    language: "en",
    catalogSeedVersion: 2,
    exercises: [{ id: 9101, name: "Imported Row" }],
    sessions: [{
      id: 9201,
      startedAt: 1760000000000,
      note: "Imported workout",
      sets: [{ id: 9301, exerciseName: "Imported Row", weight: 42.5, reps: 8, orderIndex: 0 }]
    }],
    mappings: { "imported row": ["upperBack"] },
    profile: { split: "Upper / Lower", days: 4, goal: "Strength", calories: "Maintenance" }
  };
  context.runtimeNodes.set("#import-json", { value: JSON.stringify(backup) });
  const beforeState = vm.runInContext("JSON.stringify(state)", context);
  const beforeStored = storedState(context);

  vm.runInContext("modal = { type: 'import' }; applyImport()", context);
  assert.equal(vm.runInContext("modal.type", context), "confirm-import");
  assert.equal(vm.runInContext("JSON.stringify(state)", context), beforeState);
  assert.equal(storedState(context), beforeStored);
  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /role="alertdialog"/);
  assert.match(markup, /Replace with backup/);
  vm.runInContext("closeModal()", context);
  assert.equal(storedState(context), beforeStored);

  vm.runInContext("modal = { type: 'import' }; applyImport(); accountEpoch += 1; confirmImport()", context);
  assert.equal(vm.runInContext("JSON.stringify(state)", context), beforeState);
  assert.equal(storedState(context), beforeStored);

  vm.runInContext("modal = { type: 'import' }; applyImport(); confirmImport()", context);
  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].id", context), 9201);
  assert.equal(JSON.parse(storedState(context)).sessions[0].sets[0].id, 9301);
  assert.equal(successContextFocused, true);
  assert.equal(emptyTopbarFocused, false);
});

test("import rejects duplicate exercise, workout, or set IDs before confirmation", () => {
  const context = loadContext();
  const backup = () => ({
    schemaVersion: 2,
    owner: { accountId: LOCAL_ACCOUNT_ID, userId: null, email: null, remote: false },
    language: "en",
    catalogSeedVersion: 2,
    exercises: [{ id: 9101, name: "A" }, { id: 9102, name: "B" }],
    sessions: [
      {
        id: 9201,
        startedAt: 1760000000000,
        note: "A",
        sets: [{ id: 9301, exerciseName: "A", weight: 10, reps: 5, orderIndex: 0 }]
      },
      {
        id: 9202,
        startedAt: 1760100000000,
        note: "B",
        sets: [{ id: 9302, exerciseName: "B", weight: 20, reps: 5, orderIndex: 0 }]
      }
    ],
    mappings: {},
    profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
  });
  const duplicateExercises = backup();
  duplicateExercises.exercises[1].id = duplicateExercises.exercises[0].id;
  const duplicateSessions = backup();
  duplicateSessions.sessions[1].id = duplicateSessions.sessions[0].id;
  const duplicateSets = backup();
  duplicateSets.sessions[1].sets[0].id = duplicateSets.sessions[0].sets[0].id;
  const importInput = { value: "" };
  context.runtimeNodes.set("#import-json", importInput);
  const before = storedState(context);

  for (const invalidBackup of [duplicateExercises, duplicateSessions, duplicateSets]) {
    importInput.value = JSON.stringify(invalidBackup);
    vm.runInContext("modal = { type: 'import' }; applyImport()", context);
    assert.equal(vm.runInContext("modal.type", context), "import");
    assert.equal(storedState(context), before);
  }
});

test("failed destructive cloud persistence restores account state and sync metadata", () => {
  const context = loadContext();
  const userId = "11111111-1111-4111-8111-111111111111";
  const accountId = `remote-${userId}`;
  vm.runInContext(`
    activeAccount = {
      id: ${JSON.stringify(accountId)},
      name: "Cloud Owner",
      email: "owner@example.test",
      userId: ${JSON.stringify(userId)},
      remote: "supabase"
    };
    accountEpoch += 1;
    state = defaultAppState();
    state.exercises.push({ id: 9401, name: "Rollback Test" });
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveState({ queueRemote: false, markDirty: false });
    const initialFingerprint = remoteStateFingerprint(state, activeAccount.userId);
    saveSyncBaseline({
      version: 1,
      userId: activeAccount.userId,
      remoteExists: true,
      revision: "2026-07-22T10:00:00Z",
      syncedFingerprint: initialFingerprint,
      localFingerprint: initialFingerprint,
      dirty: false,
      pending: null,
      updatedAt: 1
    });
    deleteExercise(9401);
  `, context);
  const stateKey = `gym-pwa-account:${accountId}`;
  const baselineKey = `gym-pwa-sync-baseline-v1:${userId}`;
  const beforeState = context.localStorage.getItem(stateKey);
  const beforeBaseline = context.localStorage.getItem(baselineKey);
  context.localStorage.failNextSet(stateKey);

  vm.runInContext("confirmDeleteExercise()", context);

  assert.equal(context.localStorage.getItem(stateKey), beforeState);
  assert.equal(context.localStorage.getItem(baselineKey), beforeBaseline);
  assert.equal(vm.runInContext("state.exercises.some(item => item.id === 9401)", context), true);
  assert.equal(vm.runInContext("remoteSaveTimer", context), null);
});

test("a backup for another account never reaches destructive confirmation", () => {
  const context = loadContext();
  const wrongOwner = {
    schemaVersion: 2,
    owner: { accountId: "local-v2-22222222222222222222222222222222", remote: false },
    language: "en",
    catalogSeedVersion: 2,
    exercises: [],
    sessions: [],
    mappings: {},
    profile: { split: "Push Pull Legs", days: 4, goal: "Balanced", calories: "Maintenance" }
  };
  context.runtimeNodes.set("#import-json", { value: JSON.stringify(wrongOwner) });
  const before = storedState(context);

  vm.runInContext("modal = { type: 'import' }; applyImport()", context);
  assert.equal(vm.runInContext("modal.type", context), "import");
  assert.equal(storedState(context), before);
});
