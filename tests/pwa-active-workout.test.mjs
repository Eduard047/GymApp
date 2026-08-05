import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8")
]);

const LOCAL_ACCOUNT = Object.freeze({
  id: "local-v2-11111111111111111111111111111111",
  name: "Active owner",
  localIdVersion: 2
});

function createStorage(values = new Map()) {
  const writes = [];
  return {
    values,
    writes,
    get length() { return values.size; },
    key(index) { return [...values.keys()][index] ?? null; },
    getItem: key => values.get(key) ?? null,
    setItem(key, value) {
      writes.push(key);
      values.set(key, String(value));
    },
    removeItem: key => values.delete(key)
  };
}

function createWebLocks() {
  const tails = new Map();
  return {
    request(name, options, callback) {
      const previous = tails.get(name) || Promise.resolve();
      const run = previous.catch(() => {}).then(() => {
        if (options?.signal?.aborted) throw new DOMException("Lock request aborted.", "AbortError");
        return callback({ name, mode: "exclusive" });
      });
      tails.set(name, run.catch(() => {}));
      return run;
    }
  };
}

function loadContext({ localStorage = createStorage(), locks = createWebLocks() } = {}) {
  const sessionStorage = createStorage();
  const runtimeNodes = new Map();
  const appNode = {
    innerHTML: "",
    children: [],
    classList: { toggle() {} },
    querySelector: selector => runtimeNodes.get(selector) || null,
    querySelectorAll: () => []
  };
  const progression = {
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
  };
  const context = {
    AbortController,
    atob,
    btoa,
    clearInterval,
    clearTimeout,
    console,
    crypto: webcrypto,
    CSS: { escape: String },
    Date,
    document: {
      activeElement: null,
      documentElement: { lang: "en" },
      querySelector: selector => selector === "#app" ? appNode : (runtimeNodes.get(selector) || null),
      querySelectorAll: () => []
    },
    fetch: () => Promise.reject(new Error("network disabled in active workout tests")),
    history: { replaceState() {}, pushState() {}, state: null },
    localStorage,
    Map,
    navigator: locks ? { locks } : {},
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
      location: { search: "", hash: "", pathname: "/", replace() {} },
      GymProgressionRules: progression
    }
  };
  Object.assign(context.window, {
    crypto: webcrypto,
    document: context.document,
    history: context.history,
    localStorage,
    navigator: context.navigator,
    requestAnimationFrame: context.requestAnimationFrame,
    self: null,
    sessionStorage,
    top: null
  });
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(appSource, context);
  const startupState = JSON.parse(vm.runInContext("JSON.stringify(state)", context));
  vm.runInContext(`
    activeAccount = ${JSON.stringify(LOCAL_ACCOUNT)};
    state = defaultAppState();
    clearActiveWorkoutMemory();
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveAccountList([activeAccount]);
    saveState({ queueRemote: false, markDirty: false });
    render = () => {};
    showToast = message => { globalThis.lastToast = message; };
  `, context);
  localStorage.writes.length = 0;
  return { appNode, context, localStorage, runtimeNodes, startupState };
}

async function startTwoSetWorkout(context) {
  return vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "Local active note",
      blocks: [{
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        sets: [{ weight: 80, reps: 8 }, { weight: 82.5, reps: 6 }]
      }]
    };
    startWorkout();
  `, context);
}

function activeStorageKey(context) {
  return vm.runInContext("activeWorkoutAccountDescriptor().storageKey", context);
}

test("starting creates one account-scoped local active draft without changing history or backup", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);

  const key = activeStorageKey(context);
  const stored = JSON.parse(localStorage.getItem(key));
  assert.equal(stored.owner, `local:${LOCAL_ACCOUNT.id}`);
  assert.equal(stored.blocks.length, 1);
  assert.deepEqual(stored.blocks[0].sets.map(set => set.completed), [false, false]);
  assert.equal(new Set([
    stored.id,
    stored.blocks[0].id,
    ...stored.blocks[0].sets.map(set => set.id)
  ]).size, 4, "workout, block and set IDs must be stable and unique");
  assert.equal(vm.runInContext("state.sessions.length", context), 0);

  const backup = vm.runInContext("JSON.parse(exportPayload(false))", context);
  assert.equal(Object.hasOwn(backup, "activeWorkout"), false);
  assert.equal(backup.sessions.length, 0);
  const cloudCore = vm.runInContext(
    `remoteStateCore(state, "00000000-0000-4000-8000-000000000001")`,
    context
  );
  assert.equal(Object.hasOwn(cloudCore, "activeWorkout"), false);
  assert.equal(cloudCore.sessions.length, 0);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets.length", context), 2);
  assert.match(vm.runInContext("focusLensCard([])", context), /continue-active-workout/);
});

test("active workout markup escapes untrusted exercise names and notes", async () => {
  const { context } = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "</p><script>alert(1)</script>",
      blocks: [{
        exerciseName: "<img src=x onerror=alert(1)>",
        sets: [{ weight: 10, reps: 8 }]
      }]
    };
    startWorkout();
  `, context);
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(markup, /<script>|<img src=x onerror=/);
  assert.match(markup, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.match(markup, /&lt;img src=x onerror=alert\(1\)&gt;/);
});

test("recording persists the completed set before starting the durable 90-second rest", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "81,5" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "7" });
  localStorage.writes.length = 0;

  await vm.runInContext(`recordActiveSet(${setId})`, context);

  const activeKey = activeStorageKey(context);
  const timerKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  assert.deepEqual(localStorage.writes.slice(0, 2), [activeKey, timerKey]);
  const stored = JSON.parse(localStorage.getItem(activeKey));
  assert.deepEqual(stored.blocks[0].sets[0], {
    id: setId,
    weight: 81.5,
    reps: 7,
    completed: true,
    completedAt: stored.blocks[0].sets[0].completedAt
  });
  assert.equal(Number.isSafeInteger(stored.blocks[0].sets[0].completedAt), true);
  const timer = JSON.parse(localStorage.getItem(timerKey));
  assert.equal(timer.entries.length, 1);
  assert.equal(timer.entries[0].sessionId, stored.id);
  assert.equal(timer.entries[0].exerciseName, "Bench Press");
  assert.ok(timer.entries[0].deadlineMillis - stored.blocks[0].sets[0].completedAt >= 89_000);
  assert.ok(timer.entries[0].deadlineMillis - stored.blocks[0].sets[0].completedAt <= 91_000);
});

test("overlapping Web Lock records serialize without a lost set or false success", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const first = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const second = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(first.context);
  vm.runInContext("reloadActiveWorkoutContext()", second.context);

  const [firstSetId, secondSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    first.context
  ));
  first.runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "81" });
  first.runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "7" });
  second.runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="weight"]`, { value: "83" });
  second.runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="reps"]`, { value: "5" });

  const firstRecord = vm.runInContext(`recordActiveSet(${firstSetId})`, first.context);
  const secondRecord = vm.runInContext(`recordActiveSet(${secondSetId})`, second.context);
  assert.deepEqual(await Promise.all([firstRecord, secondRecord]), [true, true]);

  const stored = JSON.parse(sharedStorage.getItem(activeStorageKey(first.context)));
  assert.equal(stored.revision, 3);
  assert.deepEqual(stored.blocks[0].sets.map(set => set.completed), [true, true]);
  assert.deepEqual(stored.blocks[0].sets.map(set => [set.weight, set.reps]), [[81, 7], [83, 5]]);
});

test("a browser without Web Locks fails closed without changing the draft", async () => {
  const sharedStorage = createStorage();
  const supported = loadContext({ localStorage: sharedStorage });
  await startTwoSetWorkout(supported.context);
  const unsupported = loadContext({ localStorage: sharedStorage, locks: null });
  vm.runInContext("reloadActiveWorkoutContext()", unsupported.context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", unsupported.context);
  unsupported.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "81" });
  unsupported.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "7" });
  const before = sharedStorage.getItem(activeStorageKey(unsupported.context));

  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, unsupported.context), false);
  assert.equal(sharedStorage.getItem(activeStorageKey(unsupported.context)), before);
});

test("finish commits only recorded sets and clears the local active draft without duplication", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "85" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "5" });
  await vm.runInContext(`recordActiveSet(${setId})`, context);
  await vm.runInContext("finishActiveWorkout()", context);

  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets[0].id", context), setId);
  assert.equal(vm.runInContext("state.sessions[0].sets[0].weight", context), 85);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(activeStorageKey(context)), null);
  assert.equal(localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)), null);

  const stateKey = vm.runInContext("activeStorageKey()", context);
  const baseState = JSON.parse(localStorage.getItem(stateKey));
  assert.equal(baseState.sessions.length, 0, "Finish must not overwrite the ordinary cross-tab state key");
  assert.notEqual(
    localStorage.getItem(vm.runInContext("activeWorkoutAccountDescriptor().commitKey", context)),
    null,
    "completed sets must be durable in the separate commit ledger"
  );
  vm.runInContext("state = loadState(activeAccount)", context);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
  const reloaded = loadContext({ localStorage, locks: createWebLocks() });
  assert.equal(reloaded.startupState.sessions.length, 1, "startup must recover committed history before rendering");
  assert.equal(reloaded.startupState.sessions[0].sets[0].id, setId);
});

test("retrying Finish after draft-cleanup failure is idempotent", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "90" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "4" });
  await vm.runInContext(`recordActiveSet(${setId})`, context);
  await vm.runInContext(`
    globalThis.__removeActiveWorkoutStorage = removeActiveWorkoutStorage;
    removeActiveWorkoutStorage = () => false;
    finishActiveWorkout();
  `, context);
  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
  assert.notEqual(vm.runInContext("activeWorkout", context), null);

  await vm.runInContext(`
    removeActiveWorkoutStorage = globalThis.__removeActiveWorkoutStorage;
    finishActiveWorkout();
  `, context);
  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
  assert.equal(vm.runInContext("activeWorkout", context), null);
});

test("Finish materializes destructive history changes before retiring the ledger so reload cannot resurrect data", async () => {
  const workoutRuntime = loadContext();
  await startTwoSetWorkout(workoutRuntime.context);
  const workoutSetId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", workoutRuntime.context);
  workoutRuntime.runtimeNodes.set(`[data-active-set-id="${workoutSetId}"][data-active-field="weight"]`, { value: "90" });
  workoutRuntime.runtimeNodes.set(`[data-active-set-id="${workoutSetId}"][data-active-field="reps"]`, { value: "4" });
  await vm.runInContext(`recordActiveSet(${workoutSetId})`, workoutRuntime.context);
  await vm.runInContext("finishActiveWorkout()", workoutRuntime.context);
  const workoutId = vm.runInContext("state.sessions[0].id", workoutRuntime.context);
  workoutRuntime.context.window.confirm = () => true;
  await vm.runInContext(`deleteSession(${workoutId})`, workoutRuntime.context);
  assert.equal(
    workoutRuntime.localStorage.getItem(vm.runInContext("activeWorkoutAccountDescriptor().commitKey", workoutRuntime.context)),
    null,
    "the workout commit must retire only after its deletion is materialized in ordinary state"
  );
  assert.equal(
    JSON.parse(workoutRuntime.localStorage.getItem(vm.runInContext("activeStorageKey()", workoutRuntime.context))).sessions.length,
    0
  );
  vm.runInContext("state = loadState(activeAccount)", workoutRuntime.context);
  assert.equal(vm.runInContext("state.sessions.length", workoutRuntime.context), 0);

  const setRuntime = loadContext();
  await startTwoSetWorkout(setRuntime.context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", setRuntime.context);
  setRuntime.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "92.5" });
  setRuntime.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "3" });
  await vm.runInContext(`recordActiveSet(${setId})`, setRuntime.context);
  await vm.runInContext("finishActiveWorkout()", setRuntime.context);
  const sessionId = vm.runInContext("state.sessions[0].id", setRuntime.context);
  vm.runInContext(`deleteSet(${setId}, ${sessionId})`, setRuntime.context);
  await vm.runInContext("confirmDeleteSet()", setRuntime.context);
  assert.equal(
    setRuntime.localStorage.getItem(vm.runInContext("activeWorkoutAccountDescriptor().commitKey", setRuntime.context)),
    null,
    "the set commit must retire only after the set deletion is materialized in ordinary state"
  );
  assert.equal(
    JSON.parse(setRuntime.localStorage.getItem(vm.runInContext("activeStorageKey()", setRuntime.context))).sessions[0].sets.length,
    0
  );
  vm.runInContext("state = loadState(activeAccount)", setRuntime.context);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", setRuntime.context), 0);
});

test("Finish preserves an overlapping ordinary history write without a false success", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "75" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "9" });
  await vm.runInContext(`recordActiveSet(${setId})`, context);

  const stateKey = vm.runInContext("activeStorageKey()", context);
  const externalState = JSON.parse(localStorage.getItem(stateKey));
  externalState.sessions.push({
    id: 222,
    startedAt: Date.now() - 60_000,
    note: "other tab",
    sets: [{ id: 333, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 60, reps: 10, orderIndex: 0 }]
  });
  localStorage.setItem(stateKey, JSON.stringify(externalState));

  assert.equal(await vm.runInContext("finishActiveWorkout()", context), true);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(vm.runInContext("state.sessions.length", context), 2);
  assert.deepEqual(
    JSON.parse(vm.runInContext("JSON.stringify(state.sessions.map(session => session.id).sort())", context)),
    [222, vm.runInContext("state.sessions.find(session => session.id !== 222).id", context)].sort()
  );
  const persistedBase = JSON.parse(localStorage.getItem(stateKey));
  assert.equal(persistedBase.sessions.length, 1, "the other tab's base write must remain byte-authoritative");
  assert.equal(persistedBase.sessions[0].id, 222);
  vm.runInContext("state = loadState(activeAccount)", context);
  assert.equal(vm.runInContext("state.sessions.length", context), 2, "reload must merge the durable Finish commit");
});

test("discard requires confirmation and removes only the local active draft", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  vm.runInContext("requestDiscardActiveWorkout({ action: 'discard-active-workout' })", context);
  assert.equal(vm.runInContext("modal.type", context), "confirm-discard-active");
  assert.match(vm.runInContext("modalMarkup()", context), /role="alertdialog"/);
  assert.notEqual(localStorage.getItem(key), null, "opening confirmation must not delete anything");

  await vm.runInContext("confirmDiscardActiveWorkout()", context);
  assert.equal(localStorage.getItem(key), null);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(vm.runInContext("state.sessions.length", context), 0);
});

test("account switching clears active memory without exposing or deleting the owner's draft", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  const raw = localStorage.getItem(key);

  await vm.runInContext("logoutAccount()", context);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(key), raw, "ordinary account switching keeps the owner's recoverable draft");

  vm.runInContext(`
    activeAccount = ${JSON.stringify(LOCAL_ACCOUNT)};
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    state = loadState(activeAccount);
    reloadActiveWorkoutContext(activeAccount);
  `, context);
  assert.equal(vm.runInContext("activeWorkout.owner", context), `local:${LOCAL_ACCOUNT.id}`);
});

test("active mutation refuses a stale in-memory account after its auth marker changes", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  const raw = localStorage.getItem(key);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "95" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "3" });
  localStorage.removeItem(vm.runInContext("AUTH_KEY", context));

  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, context), false);
  assert.equal(localStorage.getItem(key), raw);
  assert.equal(
    localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor(activeAccount).storageKey", context)),
    null
  );
});

test("account deletion serialized ahead of a record cannot leave an orphan draft", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const recorder = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const deleter = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(recorder.context);
  vm.runInContext("reloadActiveWorkoutContext()", deleter.context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", recorder.context);
  recorder.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "100" });
  recorder.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "2" });
  deleter.context.window.confirm = () => true;
  deleter.context.window.prompt = () => "DELETE";

  const deletion = vm.runInContext("deleteLocalAccount()", deleter.context);
  const recording = vm.runInContext(`recordActiveSet(${setId})`, recorder.context);
  await deletion;
  assert.equal(await recording, false);
  const descriptor = vm.runInContext("activeWorkoutAccountDescriptor(activeAccount)", recorder.context);
  assert.equal(sharedStorage.getItem(descriptor.storageKey), null);
  assert.equal(sharedStorage.getItem(descriptor.recoveryKey), null);
  assert.equal(sharedStorage.getItem(descriptor.commitKey), null);
  assert.equal(sharedStorage.getItem(vm.runInContext("AUTH_KEY", recorder.context)), null);
});

test("future and malformed active drafts are preserved in bounded account recovery storage", async () => {
  const futureRuntime = loadContext();
  await startTwoSetWorkout(futureRuntime.context);
  const activeKey = activeStorageKey(futureRuntime.context);
  const recoveryKey = vm.runInContext("activeWorkoutAccountDescriptor().recoveryKey", futureRuntime.context);
  const future = JSON.parse(futureRuntime.localStorage.getItem(activeKey));
  future.version = 2;
  const futureRaw = JSON.stringify(future);
  futureRuntime.localStorage.setItem(activeKey, futureRaw);
  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", futureRuntime.context);
  await new Promise(resolve => setTimeout(resolve, 0));

  assert.equal(vm.runInContext("activeWorkout", futureRuntime.context), null);
  assert.equal(futureRuntime.localStorage.getItem(activeKey), futureRaw, "future data must remain at its source key");
  assert.equal(futureRuntime.localStorage.getItem(recoveryKey), futureRaw, "future data must have an exact recovery copy");
  assert.equal(Object.hasOwn(vm.runInContext("JSON.parse(exportPayload(false))", futureRuntime.context), "activeWorkout"), false);

  const malformedRuntime = loadContext();
  const malformedKey = activeStorageKey(malformedRuntime.context);
  const malformedRecoveryKey = vm.runInContext(
    "activeWorkoutAccountDescriptor().recoveryKey",
    malformedRuntime.context
  );
  const malformedRaw = '{"version":1,"partial":';
  malformedRuntime.localStorage.setItem(malformedKey, malformedRaw);
  vm.runInContext("reloadActiveWorkoutContext()", malformedRuntime.context);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(malformedRuntime.localStorage.getItem(malformedKey), malformedRaw);
  assert.equal(malformedRuntime.localStorage.getItem(malformedRecoveryKey), malformedRaw);

  const secondMalformedRaw = '{"version":2,"newer":"partial"';
  malformedRuntime.localStorage.setItem(malformedKey, secondMalformedRaw);
  vm.runInContext("reloadActiveWorkoutContext()", malformedRuntime.context);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(
    malformedRuntime.localStorage.getItem(malformedRecoveryKey),
    malformedRaw,
    "a bounded recovery slot must never overwrite an earlier incompatible draft"
  );
  assert.equal(malformedRuntime.localStorage.getItem(malformedKey), secondMalformedRaw);

  malformedRuntime.localStorage.removeItem(malformedRecoveryKey);
  const oversizedRaw = "x".repeat(vm.runInContext("MAX_ACTIVE_WORKOUT_STORAGE_BYTES + 1", malformedRuntime.context));
  malformedRuntime.localStorage.setItem(malformedKey, oversizedRaw);
  vm.runInContext("reloadActiveWorkoutContext()", malformedRuntime.context);
  assert.equal(malformedRuntime.localStorage.getItem(malformedKey), oversizedRaw);
  assert.equal(malformedRuntime.localStorage.getItem(malformedRecoveryKey), null);

  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const first = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const second = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const sharedKey = activeStorageKey(first.context);
  const sharedRecoveryKey = vm.runInContext("activeWorkoutAccountDescriptor().recoveryKey", first.context);
  const firstRaw = '{"version":2,"from":"first"}';
  const secondRaw = '{"version":3,"from":"second"}';
  sharedStorage.setItem(sharedKey, firstRaw);
  vm.runInContext("reloadActiveWorkoutContext()", first.context);
  sharedStorage.setItem(sharedKey, secondRaw);
  vm.runInContext("reloadActiveWorkoutContext()", second.context);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(sharedStorage.getItem(sharedRecoveryKey), firstRaw, "serialized first recovery copy must not be overwritten");
  assert.equal(sharedStorage.getItem(sharedKey), secondRaw, "the newer incompatible source must remain untouched");
});

test("active parser rejects wrong owners, non-finite values, oversized rows, and account deletion purges the draft", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  const candidate = JSON.parse(localStorage.getItem(key));
  context.__candidate = candidate;

  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutEnvelope({ ...globalThis.__candidate, owner: "local:someone-else" })`, context),
    /owner or version/
  );
  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutEnvelope({
      ...globalThis.__candidate,
      blocks: [{
        ...globalThis.__candidate.blocks[0],
        sets: [{ ...globalThis.__candidate.blocks[0].sets[0], weight: Infinity }]
      }]
    })`, context),
    /invalid weight/
  );
  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutEnvelope({
      ...globalThis.__candidate,
      blocks: [{
        ...globalThis.__candidate.blocks[0],
        sets: Array.from({ length: GymStateContract.LIMITS.setsPerExercise + 1 }, (_, index) => ({
          id: 700000 + index,
          weight: 10,
          reps: 8,
          completed: false,
          completedAt: null
        }))
      }]
    })`, context),
    /invalid set list/
  );
  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutEnvelope("x".repeat(MAX_ACTIVE_WORKOUT_STORAGE_BYTES + 1))`, context),
    /oversized/
  );

  const recoveryKey = vm.runInContext("activeWorkoutAccountDescriptor().recoveryKey", context);
  const commitKey = vm.runInContext("activeWorkoutAccountDescriptor().commitKey", context);
  localStorage.setItem(recoveryKey, localStorage.getItem(key));
  localStorage.setItem(commitKey, JSON.stringify({
    version: 1,
    owner: `local:${LOCAL_ACCOUNT.id}`,
    workouts: []
  }));

  context.window.confirm = () => true;
  context.window.prompt = () => "DELETE";
  await vm.runInContext("deleteLocalAccount()", context);
  assert.equal(localStorage.getItem(key), null);
  assert.equal(localStorage.getItem(recoveryKey), null);
  assert.equal(localStorage.getItem(commitKey), null);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(`gym-pwa-account:${LOCAL_ACCOUNT.id}`), null);
});
