import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
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

function loadContext({
  localStorage = createStorage(),
  locks = createWebLocks(),
  trackTimers = false
} = {}) {
  const sessionStorage = createStorage();
  const runtimeNodes = new Map();
  const windowListeners = new Map();
  const timerHandles = new Set();
  const scheduleTimeout = trackTimers
    ? (callback, delay, ...args) => {
      const handle = setTimeout(() => {
        timerHandles.delete(handle);
        callback(...args);
      }, delay);
      timerHandles.add(handle);
      return handle;
    }
    : setTimeout;
  const scheduleInterval = trackTimers
    ? (callback, delay, ...args) => {
      const handle = setInterval(callback, delay, ...args);
      timerHandles.add(handle);
      return handle;
    }
    : setInterval;
  const cancelTimer = trackTimers
    ? handle => {
      timerHandles.delete(handle);
      clearTimeout(handle);
    }
    : clearTimeout;
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
    clearInterval: cancelTimer,
    clearTimeout: cancelTimer,
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
    setInterval: scheduleInterval,
    setTimeout: scheduleTimeout,
    TextDecoder,
    TextEncoder,
    URL,
    URLSearchParams,
    window: {
      addEventListener(type, listener) { windowListeners.set(type, listener); },
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
  const startupActiveWorkout = JSON.parse(vm.runInContext("JSON.stringify(activeWorkout)", context));
  const startupWorkoutDraft = JSON.parse(vm.runInContext("JSON.stringify(workoutDraft)", context));
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
  return {
    appNode,
    context,
    localStorage,
    runtimeNodes,
    startupActiveWorkout,
    startupState,
    startupWorkoutDraft,
    windowListeners,
    disposeTimers() {
      for (const handle of timerHandles) clearTimeout(handle);
      timerHandles.clear();
    }
  };
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

function activeUndoStorageKey(context) {
  return vm.runInContext("activeWorkoutAccountDescriptor().undoKey", context);
}

function activeInputDraftStorageKey(context) {
  return vm.runInContext("activeWorkoutAccountDescriptor().inputDraftKey", context);
}

function activeTimingStorageKey(context) {
  return vm.runInContext("activeWorkoutAccountDescriptor().timingKey", context);
}

function activeRestTransitionStorageKey(context) {
  return vm.runInContext("activeWorkoutAccountDescriptor().restTransitionKey", context);
}

function activeBulkCleanupStorageKey(context) {
  return vm.runInContext("activeWorkoutAccountDescriptor().bulkCleanupKey", context);
}

function unsignedLiveJwt(userId, sessionId) {
  const header = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ sub: userId, session_id: sessionId })).toString("base64url");
  return `${header}.${payload}.test-signature`;
}

async function awaitActiveControlReconciliation(context) {
  await vm.runInContext("activeWorkoutControlReconciliationPromise || Promise.resolve(true)", context);
}

test("starting creates one account-scoped local active draft without changing history or backup", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);

  const key = activeStorageKey(context);
  const stored = JSON.parse(localStorage.getItem(key));
  assert.deepEqual(Object.keys(stored), [
    "version", "owner", "id", "startedAt", "createdAt", "updatedAt", "revision", "note", "blocks"
  ], "the v1 draft root must remain exact-readable by app.v69");
  assert.equal(stored.owner, `local:${LOCAL_ACCOUNT.id}`);
  assert.equal(stored.blocks.length, 1);
  assert.deepEqual(stored.blocks[0].sets.map(set => set.completed), [false, false]);
  assert.equal(new Set([
    stored.id,
    stored.blocks[0].id,
    ...stored.blocks[0].sets.map(set => set.id)
  ]).size, 4, "workout, block and set IDs must be stable and unique");
  assert.equal(vm.runInContext("state.sessions.length", context), 0);
  assert.equal(localStorage.getItem(activeUndoStorageKey(context)), null);

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
  assert.match(vm.runInContext("focusLensCard([])", context), /discard-active-workout/);
});

test("unfinished set input survives reload exactly without entering backups or cloud state", async () => {
  const sharedStorage = createStorage();
  const first = loadContext({ localStorage: sharedStorage });
  await startTwoSetWorkout(first.context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", first.context);

  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(setId))}, activeField: "weight" },
    value: "81,"
  })`, first.context), true);
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(setId))}, activeField: "reps" },
    value: "07"
  })`, first.context), true);

  const inputKey = activeInputDraftStorageKey(first.context);
  const stored = JSON.parse(sharedStorage.getItem(inputKey));
  assert.equal(stored.owner, `local:${LOCAL_ACCOUNT.id}`);
  assert.equal(stored.workoutId, vm.runInContext("activeWorkout.id", first.context));
  assert.deepEqual(stored.entries, [{ setId, weight: "81,", reps: "07" }]);
  assert.equal(Object.hasOwn(JSON.parse(vm.runInContext("exportPayload(false)", first.context)), "activeWorkoutInputDraft"), false);
  assert.equal(Object.hasOwn(vm.runInContext(
    `remoteStateCore(state, "00000000-0000-4000-8000-000000000001")`,
    first.context
  ), "activeWorkoutInputDraft"), false);

  const second = loadContext({ localStorage: sharedStorage });
  vm.runInContext("reloadActiveWorkoutContext()", second.context);
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "weight"
  )`, second.context), "81,");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "reps"
  )`, second.context), "07");
  const markup = vm.runInContext("activeWorkoutScreen()", second.context);
  assert.match(markup, /data-active-field="weight"[^>]*maxlength="64"[^>]*value="81,"/);
  assert.match(markup, /data-active-field="reps"[^>]*maxlength="64"[^>]*value="07"/);
  second.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "81," });
  second.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "07" });
  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, second.context), true);
  assert.equal(sharedStorage.getItem(inputKey), null, "completed set input must be retired durably");
});

test("live-room input is restored after an old-session binding is rebound", async () => {
  const runtime = loadContext({ trackTimers: true });
  const { context, localStorage } = runtime;
  const userId = "00000000-0000-4000-8000-0000000000a1";
  const previousSessionId = "11111111-1111-4111-8111-111111111111";
  const currentSessionId = "22222222-2222-4222-8222-222222222222";
  const roomId = "lw_11111111111111111111111111111111";
  context.__remoteAccount = {
    id: `remote-${userId}`,
    name: "Live owner",
    userId,
    remote: "supabase"
  };
  context.__liveSession = {
    access_token: unsignedLiveJwt(userId, currentSessionId),
    refresh_token: "opaque-refresh-token",
    user: { id: userId, email: "owner@example.com" }
  };
  vm.runInContext(`
    activeAccount = globalThis.__remoteAccount;
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveAccountList([activeAccount]);
    sessionStorage.setItem(REMOTE_SESSION_KEY, JSON.stringify(globalThis.__liveSession));
    state = defaultAppState();
    clearActiveWorkoutMemory();
    saveState({ queueRemote: false, markDirty: false });
  `, context);
  await startTwoSetWorkout(context);
  const workoutId = vm.runInContext("activeWorkout.id", context);
  const firstSetId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  const oldBinding = {
    version: 3,
    userId,
    sessionId: previousSessionId,
    roomId,
    localWorkoutId: workoutId,
    role: "owner",
    peerProfileId: "p_22222222222222222222222222222222",
    peerDisplayName: "Peer",
    roomRevision: 1,
    membershipRevision: 1,
    progressRevision: 0,
    pendingOperations: [],
    serverToLocalSetIds: {}
  };
  context.__oldBinding = oldBinding;
  vm.runInContext(`liveWorkoutBinding = globalThis.__oldBinding;`, context);
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(firstSetId))}, activeField: "weight" },
    value: "81,"
  })`, context), true);
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(firstSetId))}, activeField: "reps" },
    value: "07"
  })`, context), true);

  const bindingKey = `gym-pwa-live-workout-v1:${userId}`;
  localStorage.setItem(bindingKey, JSON.stringify(oldBinding));
  vm.runInContext(`
    clearLiveWorkoutBinding({ erase: false });
    localWorkoutMatchesLiveBinding = () => true;
    window.GymLiveWorkoutState = {
      decode: raw => JSON.parse(raw),
      encode: value => JSON.stringify(value),
      normalize: value => value
    };
  `, context);
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "weight"
  )`, context), "80", "the room-scoped input stays hidden until authoritative rebind");

  context.__identity = { userId, sessionId: currentSessionId };
  context.__inbox = { rooms: [{ roomId, status: "active", memberState: "joined" }] };
  context.__snapshot = {
    room: { roomId, status: "active", roomRevision: 2 },
    participants: [
      { isSelf: true, role: "owner", membershipRevision: 2, progress: { revision: 0 } },
      {
        isSelf: false,
        profile: {
          profileId: "p_22222222222222222222222222222222",
          displayName: "Peer"
        }
      }
    ]
  };
  assert.equal(vm.runInContext(`rebindStoredLiveWorkoutBindingToCurrentSession(
    globalThis.__identity,
    globalThis.__inbox,
    globalThis.__snapshot,
    accountEpoch
  )`, context), true);
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "weight"
  )`, context), "81,");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "reps"
  )`, context), "07");

  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(firstSetId))}, activeField: "weight" },
    value: "82.50"
  })`, context), true);
  const stored = JSON.parse(localStorage.getItem(activeInputDraftStorageKey(context)));
  assert.deepEqual(stored.entries, [{ setId: firstSetId, weight: "82.50", reps: "07" }]);
  runtime.disposeTimers();
});

test("detaching a live workout preserves every raw field under the standalone scope", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const workoutId = vm.runInContext("activeWorkout.id", context);
  const firstSetId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  const secondSetId = vm.runInContext("activeWorkout.blocks[0].sets[1].id", context);
  const roomId = "lw_33333333333333333333333333333333";
  context.__detachedBinding = {
    userId: "00000000-0000-4000-8000-0000000000a1",
    roomId,
    localWorkoutId: workoutId
  };
  vm.runInContext("liveWorkoutBinding = globalThis.__detachedBinding", context);

  for (const [setId, field, value] of [
    [firstSetId, "weight", "81,"],
    [firstSetId, "reps", "07"],
    [secondSetId, "weight", "42.50"]
  ]) {
    context.__input = {
      dataset: { activeSetId: String(setId), activeField: field },
      value
    };
    assert.equal(vm.runInContext("rememberActiveLiveDraftInput(globalThis.__input)", context), true);
  }

  const inputKey = activeInputDraftStorageKey(context);
  assert.equal(JSON.parse(localStorage.getItem(inputKey)).inputScope, roomId);
  assert.equal(vm.runInContext("clearLiveWorkoutBinding()", context), true);
  assert.equal(vm.runInContext("liveWorkoutBinding", context), null);
  assert.equal(vm.runInContext("activeLiveDraftInputs.roomId", context), "standalone");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "weight"
  )`, context), "81,");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "reps"
  )`, context), "07");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[1], "weight"
  )`, context), "42.50");

  let stored = JSON.parse(localStorage.getItem(inputKey));
  assert.equal(stored.inputScope, "standalone");
  const expectedEntries = firstWeight => [
    { setId: firstSetId, weight: firstWeight, reps: "07" },
    { setId: secondSetId, weight: "42.50" }
  ].sort((left, right) => left.setId - right.setId);
  assert.deepEqual(stored.entries, expectedEntries("81,"));

  context.__input = {
    dataset: { activeSetId: String(firstSetId), activeField: "weight" },
    value: "82.25"
  };
  assert.equal(vm.runInContext("rememberActiveLiveDraftInput(globalThis.__input)", context), true);
  stored = JSON.parse(localStorage.getItem(inputKey));
  assert.deepEqual(stored.entries, expectedEntries("82.25"));

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "reps"
  )`, context), "07");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[1], "weight"
  )`, context), "42.50");
});

test("a failed live-detach draft rewrite keeps sibling fields for the next safe retry", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const workoutId = vm.runInContext("activeWorkout.id", context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  const roomId = "lw_44444444444444444444444444444444";
  context.__detachedBinding = {
    userId: "00000000-0000-4000-8000-0000000000a1",
    roomId,
    localWorkoutId: workoutId
  };
  vm.runInContext("liveWorkoutBinding = globalThis.__detachedBinding", context);
  for (const [field, value] of [["weight", "81,"], ["reps", "07"]]) {
    context.__input = {
      dataset: { activeSetId: String(setId), activeField: field },
      value
    };
    assert.equal(vm.runInContext("rememberActiveLiveDraftInput(globalThis.__input)", context), true);
  }

  const inputKey = activeInputDraftStorageKey(context);
  const originalSetItem = localStorage.setItem;
  localStorage.setItem = (key, value) => {
    if (key === inputKey) throw new Error("simulated input sidecar failure");
    originalSetItem(key, value);
  };
  assert.equal(vm.runInContext("clearLiveWorkoutBinding()", context), false);
  assert.equal(vm.runInContext("activeLiveDraftInputs.roomId", context), "standalone");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(
    activeWorkout.blocks[0].sets[0], "reps"
  )`, context), "07");

  localStorage.setItem = originalSetItem;
  context.__input = {
    dataset: { activeSetId: String(setId), activeField: "weight" },
    value: "82.25"
  };
  assert.equal(vm.runInContext("rememberActiveLiveDraftInput(globalThis.__input)", context), true);
  const stored = JSON.parse(localStorage.getItem(inputKey));
  assert.equal(stored.inputScope, "standalone");
  assert.deepEqual(stored.entries, [{ setId, weight: "82.25", reps: "07" }]);
});

test("active set input sidecar rejects foreign, stale, malformed, and oversized data", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  const inputKey = activeInputDraftStorageKey(context);
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(setId))}, activeField: "weight" },
    value: "82.50"
  })`, context), true);
  const valid = JSON.parse(localStorage.getItem(inputKey));

  const rejected = [
    { ...valid, owner: "local:another-owner" },
    { ...valid, workoutId: valid.workoutId + 1 },
    { ...valid, entries: [{ setId: setId + 1000, weight: "999" }] },
    { ...valid, entries: [{ setId, weight: "<script>" }] }
  ];
  for (const candidate of rejected) {
    localStorage.setItem(inputKey, JSON.stringify(candidate));
    vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
    assert.equal(vm.runInContext("activeLiveDraftInputs.values.size", context), 0);
    assert.equal(vm.runInContext(
      `activeLiveDraftInputValue(activeWorkout.blocks[0].sets[0], "weight")`,
      context
    ), "80");
  }

  localStorage.setItem(inputKey, "x".repeat(32 * 1024 + 1));
  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  assert.equal(vm.runInContext("activeLiveDraftInputs.values.size", context), 0);
});

test("startup consumes only a same-account pre-start draft behind a valid active workout", async () => {
  const sharedStorage = createStorage();
  const writer = loadContext({ localStorage: sharedStorage, locks: createWebLocks() });
  await startTwoSetWorkout(writer.context);
  const activeKey = activeStorageKey(writer.context);
  const draftKey = vm.runInContext("workoutDraftAccountDescriptor().storageKey", writer.context);
  vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "stale before-start snapshot",
      blocks: [{
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        sets: [{ weight: "80", reps: "8" }]
      }]
    };
    workoutDraftLiveRecipient = null;
    persistWorkoutDraft();
  `, writer.context);
  assert.notEqual(sharedStorage.getItem(draftKey), null);

  const restarted = loadContext({ localStorage: sharedStorage, locks: createWebLocks() });
  assert.notEqual(restarted.startupActiveWorkout, null);
  assert.equal(restarted.startupWorkoutDraft, null);
  assert.equal(sharedStorage.getItem(draftKey), null, "the durable draft must be pruned, not just hidden in memory");

  sharedStorage.removeItem(activeKey);
  const afterActiveCompleted = loadContext({ localStorage: sharedStorage, locks: createWebLocks() });
  assert.equal(afterActiveCompleted.startupWorkoutDraft, null, "the consumed plan cannot resurrect later");
});

test("a wrong-owner active envelope cannot consume the current account's valid draft", async () => {
  const sharedStorage = createStorage();
  const writer = loadContext({ localStorage: sharedStorage, locks: createWebLocks() });
  await startTwoSetWorkout(writer.context);
  const activeKey = activeStorageKey(writer.context);
  const draftKey = vm.runInContext("workoutDraftAccountDescriptor().storageKey", writer.context);
  vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "keep after invalid active",
      blocks: [{ exerciseName: "Bench Press", sets: [{ weight: "60", reps: "10" }] }]
    };
    workoutDraftLiveRecipient = null;
    persistWorkoutDraft();
  `, writer.context);
  const wrongOwner = JSON.parse(sharedStorage.getItem(activeKey));
  wrongOwner.owner = "local:another-account";
  sharedStorage.setItem(activeKey, JSON.stringify(wrongOwner));

  const restarted = loadContext({ localStorage: sharedStorage, locks: createWebLocks() });
  assert.equal(restarted.startupActiveWorkout, null);
  assert.equal(restarted.startupWorkoutDraft.note, "keep after invalid active");
  assert.notEqual(sharedStorage.getItem(draftKey), null);
});

test("local state migrates legacy exercise controls without enabling them for UI or import", () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  vm.runInContext(`
    const legacy = defaultAppState();
    legacy.exercises = [{ id: 900, name: "Catalog\\u0000Name", catalogKey: "bench_press" }];
    legacy.sessions = [{
      id: 901,
      startedAt: 1760000000000,
      note: "Legacy",
      exerciseNames: ["Explicit\\u001fName"],
      sets: [{
        id: 902,
        exerciseName: "Set\\u0085Name",
        catalogKey: "bench_press",
        weight: 20,
        reps: 8,
        orderIndex: 0
      }]
    }];
    legacy.mappings = Object.create(null);
    legacy.mappings["Map\\u007fName"] = ["chest"];
    globalThis.legacyControlStateRaw = JSON.stringify(legacy);
    localStorage.setItem(activeStorageKey(), globalThis.legacyControlStateRaw);
  `, context);
  localStorage.writes.length = 0;

  assert.throws(
    () => vm.runInContext("validateImportedEnvelope(globalThis.legacyControlStateRaw, defaultAppState())", context),
    /unsupported control characters/
  );
  assert.equal(vm.runInContext("isSupportedExerciseName('Edge\\u0000Name')", context), false);
  assert.equal(vm.runInContext("isSupportedExerciseName('\\nTrimmed-looking name')", context), false);
  runtimeNodes.set("#new-exercise-name", { value: "\nTrimmed-looking name" });
  const exerciseCountBefore = vm.runInContext("state.exercises.length", context);
  vm.runInContext("saveExercise()", context);
  assert.equal(vm.runInContext("state.exercises.length", context), exerciseCountBefore);

  const loaded = JSON.parse(vm.runInContext(
    "JSON.stringify(loadStoredStateBase(activeAccount))",
    context
  ));
  const expectedCatalog = vm.runInContext(
    "GymStateContract.migrateLegacyExerciseNameControls('Catalog\\u0000Name')",
    context
  );
  const expectedSet = vm.runInContext(
    "GymStateContract.migrateLegacyExerciseNameControls('Set\\u0085Name')",
    context
  );
  const expectedMapping = vm.runInContext(
    "normalizeExerciseName(GymStateContract.migrateLegacyExerciseNameControls('Map\\u007fName'))",
    context
  );
  assert.equal(loaded.exercises[0].name, expectedCatalog);
  assert.equal(Object.hasOwn(loaded.exercises[0], "catalogKey"), false);
  assert.equal(loaded.sessions[0].sets[0].exerciseName, expectedSet);
  assert.equal(Object.hasOwn(loaded.sessions[0].sets[0], "catalogKey"), false);
  assert.deepEqual(loaded.mappings[expectedMapping], ["chest"]);

  const persisted = JSON.parse(localStorage.getItem(vm.runInContext("activeStorageKey()", context)));
  assert.equal(persisted.exercises[0].name, expectedCatalog);
  assert.equal(persisted.sessions[0].sets[0].exerciseName, expectedSet);
  assert.equal(localStorage.writes.includes(vm.runInContext("activeStorageKey()", context)), true);
});

test("active draft and commit ledger migrate legacy controls with catalog identity removed", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const descriptor = vm.runInContext("activeWorkoutAccountDescriptor()", context);
  const legacyDraft = JSON.parse(localStorage.getItem(descriptor.storageKey));
  legacyDraft.blocks[0].exerciseName = "Draft\u0000Press";
  legacyDraft.blocks[0].catalogKey = "bench_press";
  const legacyDraftRaw = JSON.stringify(legacyDraft);
  localStorage.setItem(descriptor.storageKey, legacyDraftRaw);
  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutEnvelope(${JSON.stringify(legacyDraftRaw)}, activeAccount)`, context),
    /invalid exercise name/
  );

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  const expectedDraftName = vm.runInContext(
    "GymStateContract.migrateLegacyExerciseNameControls('Draft\\u0000Press')",
    context
  );
  const migratedDraft = JSON.parse(localStorage.getItem(descriptor.storageKey));
  assert.equal(vm.runInContext("activeWorkout.blocks[0].exerciseName", context), expectedDraftName);
  assert.equal(migratedDraft.blocks[0].exerciseName, expectedDraftName);
  assert.equal(Object.hasOwn(migratedDraft.blocks[0], "catalogKey"), false);
  assert.equal(localStorage.getItem(descriptor.recoveryKey), null);

  const committed = structuredClone(migratedDraft);
  committed.blocks[0].exerciseName = "Commit\u0085Row";
  committed.blocks[0].catalogKey = "seated_row";
  committed.blocks[0].sets = [committed.blocks[0].sets[0]];
  committed.blocks[0].sets[0].completed = true;
  committed.blocks[0].sets[0].completedAt = committed.createdAt;
  const legacyLedgerRaw = JSON.stringify({
    version: 1,
    owner: committed.owner,
    workouts: [committed]
  });
  localStorage.setItem(descriptor.commitKey, legacyLedgerRaw);
  const ledger = vm.runInContext("loadActiveWorkoutCommitLedger(activeAccount)", context);
  const expectedCommitName = vm.runInContext(
    "GymStateContract.migrateLegacyExerciseNameControls('Commit\\u0085Row')",
    context
  );
  assert.equal(ledger.ledger.workouts[0].blocks[0].exerciseName, expectedCommitName);
  const migratedLedger = JSON.parse(localStorage.getItem(descriptor.commitKey));
  assert.equal(migratedLedger.workouts[0].blocks[0].exerciseName, expectedCommitName);
  assert.equal(Object.hasOwn(migratedLedger.workouts[0].blocks[0], "catalogKey"), false);
});

test("Back from an active workout returns Home without discarding the local draft", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  const before = localStorage.getItem(key);

  vm.runInContext(`
    nav = [{ name: "workouts" }, { name: "active" }];
    history.state = { gymAppNav: [{ name: "workouts" }, { name: "active" }] };
    back();
  `, context);

  assert.deepEqual(
    JSON.parse(vm.runInContext("JSON.stringify(nav)", context)),
    [{ name: "workouts" }]
  );
  assert.notEqual(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(key), before);
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
  assert.doesNotMatch(markup, /<script\b|<img\b[^>]*\bonerror\s*=/i);
  assert.match(markup, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.match(markup, /&lt;img src=x onerror=alert\(1\)&gt;/);
});

test("recording persists the completed set before starting the durable 180-second primary rest", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [setId, nextSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  const initialMarkup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(initialMarkup, new RegExp(`data-action="record-active-set" data-id="${setId}"`));
  assert.match(initialMarkup, new RegExp(`data-action="record-active-set" data-id="${nextSetId}"`), "every unrecorded set can be logged");
  assert.doesNotMatch(initialMarkup, /data-action="undo-active-set"|data-timer-display=|data-active-set-confirmation/);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "81,5" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "7" });
  localStorage.writes.length = 0;

  await vm.runInContext(`recordActiveSet(${setId})`, context);

  const activeKey = activeStorageKey(context);
  const timerKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  const undoKey = activeUndoStorageKey(context);
  assert.deepEqual(localStorage.writes.slice(0, 5), [
    activeKey,
    undoKey,
    activeRestTransitionStorageKey(context),
    activeTimingStorageKey(context),
    timerKey
  ], "the write-ahead marker must be durable before either rest state key");
  assert.equal(localStorage.getItem(activeRestTransitionStorageKey(context)), null,
    "the marker is removed only after timing and timer readback succeed");
  const stored = JSON.parse(localStorage.getItem(activeKey));
  assert.equal(Object.hasOwn(stored, "undoableSetId"), false);
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
  assert.ok(timer.entries[0].deadlineMillis - stored.blocks[0].sets[0].completedAt >= 179_000);
  assert.ok(timer.entries[0].deadlineMillis - stored.blocks[0].sets[0].completedAt <= 181_000);
  const lifecycleMarkup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(lifecycleMarkup, new RegExp(`data-action="undo-active-set" data-id="${setId}"`));
  assert.match(lifecycleMarkup, new RegExp(`data-action="record-active-set" data-id="${nextSetId}"`));
  assert.match(lifecycleMarkup, /data-action="timer-adjust"[^>]*data-seconds="-15"/);
  assert.match(lifecycleMarkup, /data-action="timer-adjust"[^>]*data-seconds="15"/);
  assert.match(lifecycleMarkup, /data-action="timer-stop"/);
  assert.doesNotMatch(lifecycleMarkup, /Undo last set|Set saved · rest timer|active-workout-timer/);
});

test("recording a bodyweight set accepts blank weight as zero and still starts rest", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "12" });

  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, context), true);
  const stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.deepEqual(
    [stored.blocks[0].sets[0].weight, stored.blocks[0].sets[0].reps, stored.blocks[0].sets[0].completed],
    [0, 12, true]
  );
  const timerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  assert.equal(JSON.parse(localStorage.getItem(timerStorageKey)).entries.length, 1);
});

test("completed active sets are read-only and bulk save cannot rewrite them", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  const [firstSetId, secondSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "81.5" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "7" });
  assert.equal(await vm.runInContext(`recordActiveSet(${firstSetId})`, context), true);

  const recorded = JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks[0].sets[0];
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(markup, new RegExp(`data-active-set-id="${firstSetId}" data-active-field="weight"[^>]*disabled`));
  assert.match(markup, new RegExp(`data-active-set-id="${firstSetId}" data-active-field="reps"[^>]*disabled`));
  assert.doesNotMatch(markup, new RegExp(`data-active-set-id="${secondSetId}" data-active-field="weight"[^>]*disabled`));

  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "999" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "99" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="weight"]`, { value: "83" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="reps"]`, { value: "5" });
  assert.equal(await vm.runInContext(`saveActiveWorkoutExercise(${blockId})`, context), true);

  const saved = JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks[0].sets;
  assert.deepEqual(
    [saved[0].weight, saved[0].reps, saved[0].completedAt],
    [recorded.weight, recorded.reps, recorded.completedAt],
    "bulk save must preserve the already-recorded set exactly"
  );
  assert.deepEqual([saved[1].weight, saved[1].reps, saved[1].completed], [83, 5, true]);
  const fullyRecorded = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(fullyRecorded, /data-action="save-active-exercise"/,
    "like iOS, Finish stays visible when every set is recorded");
});

test("Save exercise and Add set retire stale undo, timing, and rest projections", async () => {
  const saver = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "Structural rest cleanup",
      blocks: [
        {
          exerciseName: "Bench Press",
          catalogKey: "bench_press",
          sets: [{ weight: 80, reps: 8 }, { weight: 82, reps: 6 }]
        },
        {
          exerciseName: "Squat",
          catalogKey: "squat",
          sets: [{ weight: 100, reps: 5 }]
        }
      ]
    };
    startWorkout();
  `, saver.context);
  const [firstSetId, unfinishedFirstBlockSetId, secondBlockSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify([activeWorkout.blocks[0].sets[0].id, activeWorkout.blocks[0].sets[1].id, activeWorkout.blocks[1].sets[0].id])",
    saver.context
  ));
  const secondBlockId = vm.runInContext("activeWorkout.blocks[1].id", saver.context);
  saver.runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "80" });
  saver.runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${firstSetId})`, saver.context), true);
  const timerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", saver.context);
  assert.notEqual(saver.localStorage.getItem(timerStorageKey), null);
  saver.runtimeNodes.set(`[data-active-set-id="${secondBlockSetId}"][data-active-field="weight"]`, { value: "100" });
  saver.runtimeNodes.set(`[data-active-set-id="${secondBlockSetId}"][data-active-field="reps"]`, { value: "5" });
  saver.localStorage.writes.length = 0;

  assert.equal(
    await vm.runInContext(`saveActiveWorkoutExercise(${secondBlockId})`, saver.context),
    true
  );
  const saved = JSON.parse(saver.localStorage.getItem(activeStorageKey(saver.context)));
  assert.equal(saved.blocks[0].sets.find(set => set.id === unfinishedFirstBlockSetId).completed, false);
  assert.equal(saved.blocks[1].sets[0].completed, true);
  assert.ok(
    saver.localStorage.writes.indexOf(activeBulkCleanupStorageKey(saver.context)) <
      saver.localStorage.writes.indexOf(activeStorageKey(saver.context)),
    "control cleanup intent must be durable before the structural main revision"
  );
  assert.equal(saver.localStorage.getItem(activeBulkCleanupStorageKey(saver.context)), null);
  assert.equal(saver.localStorage.getItem(activeUndoStorageKey(saver.context)), null);
  assert.equal(saver.localStorage.getItem(timerStorageKey), null);
  const savedTiming = JSON.parse(saver.localStorage.getItem(activeTimingStorageKey(saver.context)));
  assert.equal(savedTiming.restingUntil, null);
  assert.equal(Number.isSafeInteger(savedTiming.activeSince), true);

  const adder = loadContext();
  await startTwoSetWorkout(adder.context);
  const addBlockId = vm.runInContext("activeWorkout.blocks[0].id", adder.context);
  const addSetId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", adder.context);
  adder.runtimeNodes.set(`[data-active-set-id="${addSetId}"][data-active-field="weight"]`, { value: "80" });
  adder.runtimeNodes.set(`[data-active-set-id="${addSetId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${addSetId})`, adder.context), true);
  const addTimerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", adder.context);
  assert.notEqual(adder.localStorage.getItem(addTimerStorageKey), null);

  assert.equal(await vm.runInContext(`addActiveWorkoutSet(${addBlockId})`, adder.context), true);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets.length", adder.context), 3);
  assert.equal(adder.localStorage.getItem(activeBulkCleanupStorageKey(adder.context)), null);
  assert.equal(adder.localStorage.getItem(activeUndoStorageKey(adder.context)), null);
  assert.equal(adder.localStorage.getItem(addTimerStorageKey), null);
  const addedTiming = JSON.parse(adder.localStorage.getItem(activeTimingStorageKey(adder.context)));
  assert.equal(addedTiming.restingUntil, null);
  assert.equal(Number.isSafeInteger(addedTiming.activeSince), true);
});

test("Add set reports its own action when durable rest cleanup needs recovery", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  vm.runInContext(`
    globalThis.originalBulkCleanupReconciler = reconcileActiveWorkoutBulkCleanupIntent;
    globalThis.bulkCleanupCalls = 0;
    reconcileActiveWorkoutBulkCleanupIntent = (...args) => {
      globalThis.bulkCleanupCalls += 1;
      return globalThis.bulkCleanupCalls === 1
        ? globalThis.originalBulkCleanupReconciler(...args)
        : false;
    };
  `, context);

  assert.equal(await vm.runInContext(`addActiveWorkoutSet(${blockId})`, context), true);
  assert.equal(vm.runInContext("activeWorkoutUi.status", context), "error");
  assert.equal(vm.runInContext("activeWorkoutUi.messageKey", context), "setAddedCleanupFailed");
  const messages = {
    en: "Set added, but old local rest controls could not be fully cleared.",
    uk: "Підхід додано, але старі локальні елементи відпочинку не вдалося повністю очистити."
  };
  for (const [language, message] of Object.entries(messages)) {
    assert.equal(
      vm.runInContext(`state.language = ${JSON.stringify(language)}; activeWorkoutStatusText()`, context),
      message
    );
  }
});

test("the latest completed exercise stays expanded while the next exercise becomes current", async () => {
  const { context, runtimeNodes } = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "Two exercises",
      blocks: [
        { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }] },
        { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 100, reps: 5 }] }
      ]
    };
    startWorkout();
  `, context);
  const [firstSetId, nextSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks.map(block => block.sets[0].id))",
    context
  ));
  vm.runInContext("activeWorkoutScreen()", context); // screen entry happened before the set was recorded
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "80" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${firstSetId})`, context), true);

  const markup = vm.runInContext("activeWorkoutScreen()", context);
  const completedStart = markup.indexOf('active-workout-exercise completed"');
  const currentStart = markup.indexOf('active-workout-exercise current"');
  assert.ok(completedStart >= 0 && currentStart > completedStart);
  const completedMarkup = markup.slice(completedStart, currentStart);
  assert.match(completedMarkup, /<details data-active-block-details="\d+" open>/);
  assert.match(completedMarkup, /data-timer-display=/);
  assert.match(completedMarkup, new RegExp(`data-action="undo-active-set" data-id="${firstSetId}"`));
  assert.match(markup, new RegExp(
    `active-workout-exercise current"><details data-active-block-details="\\d+" open>[\\s\\S]*?data-action="record-active-set" data-id="${nextSetId}"`
  ));
});

test("workout stopwatch includes adjusted rest while its account-bound sidecar tracks rest", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);

  assert.equal(vm.runInContext(`activeWorkoutElapsedMillis(activeWorkout, ${createdAt + 40_000})`, context), 40_000);
  assert.equal(await vm.runInContext(`startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${createdAt + 40_000})`, context), true);
  assert.equal(vm.runInContext(`activeWorkoutElapsedMillis(activeWorkout, ${createdAt + 70_000})`, context), 70_000);
  assert.equal(await vm.runInContext(`adjustExerciseRestTimer(${JSON.stringify(timerKey)}, 15, ${createdAt + 70_000})`, context), true);
  assert.equal(vm.runInContext(`activeWorkoutElapsedMillis(activeWorkout, ${createdAt + 100_000})`, context), 100_000);
  assert.equal(await vm.runInContext(`stopExerciseRestTimer(${JSON.stringify(timerKey)}, ${createdAt + 100_000})`, context), true);
  assert.equal(vm.runInContext(`activeWorkoutElapsedMillis(activeWorkout, ${createdAt + 115_000})`, context), 115_000);

  const timing = JSON.parse(localStorage.getItem(activeTimingStorageKey(context)));
  assert.deepEqual(Object.keys(timing), [
    "version", "owner", "workoutId", "accumulatedActiveMillis", "activeSince", "restingUntil"
  ]);
  assert.equal(timing.owner, `local:${LOCAL_ACCOUNT.id}`);
  assert.equal(timing.workoutId, vm.runInContext("activeWorkout.id", context));
  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  assert.equal(vm.runInContext(`activeWorkoutElapsedMillis(activeWorkout, ${createdAt + 120_000})`, context), 120_000);
  assert.match(vm.runInContext("activeWorkoutScreen()", context), /data-active-workout-elapsed/);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /includes rest/);
});

test("active-workout hero is one brand panel with a combined label, ring and current exercise in every locale", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const expectations = {
    en: { progress: "In progress", now: "Now: Bench Press", sets: "sets", label: "Elapsed 00:00, 0 of 2 sets done, now: Bench Press" },
    uk: { progress: "Триває", now: "Зараз: Bench Press", sets: "підх.", label: "Минуло 00:00, 0 з 2 підходи виконано, зараз: Bench Press" },
    ru: { progress: "Идёт", now: "Сейчас: Bench Press", sets: "подх.", label: "Прошло 00:00, выполнено 0 из 2 подхода, сейчас: Bench Press" }
  };
  for (const [language, copy] of Object.entries(expectations)) {
    const markup = vm.runInContext(
      `state.language = ${JSON.stringify(language)}; activeWorkoutScreen()`,
      context
    );
    assert.match(markup, new RegExp(`class="active-hero-main" role="img" data-active-workout-hero aria-label="[^"]*"`));
    assert.match(markup, /<strong class="active-hero-elapsed" data-active-workout-elapsed>\d{2}:\d{2}<\/strong>/);
    assert.ok(markup.includes(`</span>${copy.progress}</span>`));
    assert.ok(markup.includes(`<strong>0/2</strong><span>${copy.sets}</span>`));
    assert.match(markup, /class="active-hero-copy" aria-hidden="true"/);
    assert.match(markup, /class="active-hero-ring" aria-hidden="true"/);
    assert.doesNotMatch(markup, /role="progressbar"|active-workout-started|active-workout-metrics|<div class="metric-grid/);
    assert.doesNotMatch(markup, /\sstyle=/);
    assert.match(markup, /active-workout-screen-note/);
  }
  const label = language => vm.runInContext(
    `state.language = ${JSON.stringify(language)}; activeWorkoutHeroLabel("14:40", { completed: 3, total: 15 }, "Squat")`,
    context
  );
  assert.equal(label("en"), "Elapsed 14:40, 3 of 15 sets done, now: Squat");
  assert.equal(label("uk"), "Минуло 14:40, 3 з 15 підходів виконано, зараз: Squat");
  assert.equal(label("ru"), "Прошло 14:40, выполнено 3 из 15 подходов, сейчас: Squat");
  assert.equal(vm.runInContext(
    'state.language = "en"; activeWorkoutHeroLabel("00:05", { completed: 2, total: 2 }, "")',
    context
  ), "Elapsed 00:05, 2 of 2 sets done");
  assert.equal(vm.runInContext('state.language = "en"; titleForRoute({ name: "active" })', context), "Workout");
  assert.equal(vm.runInContext('state.language = "uk"; titleForRoute({ name: "active" })', context), "Тренування");
  assert.equal(vm.runInContext('state.language = "ru"; titleForRoute({ name: "active" })', context), "Тренировка");
});

test("active-workout topbar minimizes and the overflow sheet holds Adapt and Discard", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const minimize = vm.runInContext(
    'state.language = "ru"; activeWorkoutMinimizeMarkup()',
    context
  );
  assert.match(minimize, /data-action="back"[^>]*aria-describedby="active-minimize-hint">Свернуть<\/button>/);
  assert.match(minimize, /Сворачивает экран; тренировка продолжает идти, все изменения уже сохранены/);
  assert.match(vm.runInContext('state.language = "uk"; activeWorkoutMinimizeMarkup()', context), />Згорнути<\/button>/);
  assert.match(vm.runInContext('state.language = "en"; activeWorkoutMinimizeMarkup()', context), />Minimize<\/button>/);
  const more = vm.runInContext('state.language = "en"; activeWorkoutMoreButtonMarkup()', context);
  assert.match(more, /data-action="open-active-more"[^>]*aria-label="More workout options"/);

  const sheet = vm.runInContext('state.language = "en"; activeWorkoutMoreSheetMarkup()', context);
  assert.match(sheet, /Adapt workout/);
  for (const reason of ["equipmentUnavailable", "timeCut", "tooHard"]) {
    assert.match(sheet, new RegExp(`data-action="training-adapt" data-reason="${reason}"`));
  }
  assert.match(sheet, /class="button danger full" data-action="discard-active-workout">Discard<\/button>/);
  const screen = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(screen, /training-adapt|discard-active-workout|active-workout-more/);
  const russianSheet = vm.runInContext('state.language = "ru"; activeWorkoutMoreSheetMarkup()', context);
  assert.match(russianSheet, />Удалить<\/button>/);

  vm.runInContext(`modal = { type: "active-more" }; state.language = "en";`, context);
  assert.match(vm.runInContext("modalMarkup()", context), /aria-labelledby="active-more-title"/);
  vm.runInContext("modal = null", context);
});

test("active-workout exercise cards show a set subtitle, a collapsed progress line and no eyebrow or Done pill", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const markup = vm.runInContext('state.language = "en"; activeWorkoutScreen()', context);
  assert.match(markup, /class="active-exercise-open-line">Set 1 of 2<\/p>/);
  assert.match(markup, /class="active-exercise-collapsed-line"><span class="active-exercise-progress">[\s\S]*?0 \/ 2<\/span><\/p>/);
  assert.doesNotMatch(markup, /active-exercise-status/, "the current card has no Up next / Completed status");
  assert.doesNotMatch(markup, /class="eyebrow">Exercise|completed-exercise-badge/);
  const upcoming = language => vm.runInContext(
    `state.language = ${JSON.stringify(language)}; activeWorkoutBlockMarkup(activeWorkout.blocks[0], 1, 0)`,
    context
  );
  assert.match(upcoming("en"), /class="active-exercise-status">Up next · 2 sets<\/span>/);
  assert.match(upcoming("uk"), /Далі · 2 підходи/);
  assert.match(upcoming("ru"), /Далее · 2 подхода/);
  assert.match(upcoming("ru"), /Подход 1 из 2/);
  const completedBlock = vm.runInContext(
    `state.language = "ru"; activeWorkoutBlockMarkup({ ...activeWorkout.blocks[0], sets: activeWorkout.blocks[0].sets.map(set => ({ ...set, completed: true })) }, 0, -1)`,
    context
  );
  assert.match(completedBlock, /class="active-exercise-progress done">[\s\S]*?2 \/ 2<\/span><span class="active-exercise-status">Завершено<\/span>/);
});

test("write-ahead rest marker reconciles crashes between start, adjust, and stop state writes", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  const timerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  const transitionKey = activeRestTransitionStorageKey(context);
  const timingKey = activeTimingStorageKey(context);
  const startAt = createdAt + 40_000;
  const firstDeadline = startAt + 90_000;

  assert.equal(vm.runInContext(`(() => {
    const target = activeWorkoutTimingAfterRestTransition(
      activeWorkout,
      ${firstDeadline},
      ${startAt}
    );
    const marker = persistActiveWorkoutRestTransitionMarker({
      version: 1,
      owner: activeWorkout.owner,
      workoutId: activeWorkout.id,
      workoutRevision: activeWorkout.revision,
      timerKey: ${JSON.stringify(timerKey)},
      transition: "rest",
      transitionAt: ${startAt},
      deadlineMillis: ${firstDeadline},
      timing: target.timing
    }, activeWorkout);
    const timers = Object.create(null);
    timers[${JSON.stringify(timerKey)}] = ${firstDeadline};
    return Boolean(marker && persistExerciseRestTimers(timers, activeAccount, ${startAt}));
  })()`, context), true, "simulate a crash after the ledger write but before timing");
  assert.notEqual(localStorage.getItem(transitionKey), null);
  assert.equal(JSON.parse(localStorage.getItem(timingKey)).activeSince, createdAt);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  let timing = JSON.parse(localStorage.getItem(timingKey));
  let ledger = JSON.parse(localStorage.getItem(timerStorageKey));
  assert.equal(localStorage.getItem(transitionKey), null);
  assert.equal(timing.accumulatedActiveMillis, 40_000);
  assert.equal(timing.activeSince, null);
  assert.equal(timing.restingUntil, firstDeadline);
  assert.equal(ledger.entries[0].deadlineMillis, firstDeadline);

  const adjustAt = createdAt + 70_000;
  const adjustedDeadline = firstDeadline + 15_000;
  assert.equal(vm.runInContext(`(() => {
    const target = activeWorkoutTimingAfterRestTransition(
      activeWorkout,
      ${adjustedDeadline},
      ${adjustAt}
    );
    const marker = persistActiveWorkoutRestTransitionMarker({
      version: 1,
      owner: activeWorkout.owner,
      workoutId: activeWorkout.id,
      workoutRevision: activeWorkout.revision,
      timerKey: ${JSON.stringify(timerKey)},
      transition: "rest",
      transitionAt: ${adjustAt},
      deadlineMillis: ${adjustedDeadline},
      timing: target.timing
    }, activeWorkout);
    return Boolean(marker && persistActiveWorkoutTiming(target.timing, activeWorkout, activeAccount, target.raw));
  })()`, context), true, "simulate a crash after adjusted timing but before the ledger");
  assert.equal(JSON.parse(localStorage.getItem(timerStorageKey)).entries[0].deadlineMillis, firstDeadline);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  timing = JSON.parse(localStorage.getItem(timingKey));
  ledger = JSON.parse(localStorage.getItem(timerStorageKey));
  assert.equal(localStorage.getItem(transitionKey), null);
  assert.equal(timing.restingUntil, adjustedDeadline);
  assert.equal(ledger.entries[0].deadlineMillis, adjustedDeadline);

  const stopAt = createdAt + 100_000;
  assert.equal(vm.runInContext(`(() => {
    const target = activeWorkoutTimingAfterStopTransition(activeWorkout, ${stopAt});
    const marker = persistActiveWorkoutRestTransitionMarker({
      version: 1,
      owner: activeWorkout.owner,
      workoutId: activeWorkout.id,
      workoutRevision: activeWorkout.revision,
      timerKey: ${JSON.stringify(timerKey)},
      transition: "active",
      transitionAt: ${stopAt},
      deadlineMillis: null,
      timing: target.timing
    }, activeWorkout);
    return Boolean(marker && persistExerciseRestTimers(Object.create(null), activeAccount, ${stopAt}));
  })()`, context), true, "simulate a crash after stop removed the ledger but before timing resumed");
  assert.equal(localStorage.getItem(timerStorageKey), null);
  assert.notEqual(JSON.parse(localStorage.getItem(timingKey)).restingUntil, null);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  timing = JSON.parse(localStorage.getItem(timingKey));
  assert.equal(localStorage.getItem(transitionKey), null);
  assert.equal(localStorage.getItem(timerStorageKey), null);
  assert.equal(timing.activeSince, stopAt);
  assert.equal(timing.restingUntil, null);
  assert.equal(vm.runInContext(`activeWorkoutElapsedMillis(activeWorkout, ${createdAt + 120_000})`, context), 120_000,
    "user-facing workout time remains continuous through rest and recovery");
});

test("rest transition marker is exact, account-bound, and never applies a foreign target", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const transitionKey = activeRestTransitionStorageKey(context);
  const timingBefore = localStorage.getItem(activeTimingStorageKey(context));
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  const foreign = vm.runInContext(`(() => {
    const transitionAt = ${createdAt + 10_000};
    const deadlineMillis = transitionAt + 60_000;
    const target = activeWorkoutTimingAfterRestTransition(activeWorkout, deadlineMillis, transitionAt);
    return {
      version: 1,
      owner: "local:another-account",
      workoutId: activeWorkout.id,
      workoutRevision: activeWorkout.revision,
      timerKey: ${JSON.stringify(timerKey)},
      transition: "rest",
      transitionAt,
      deadlineMillis,
      timing: target.timing
    };
  })()`, context);
  localStorage.setItem(transitionKey, JSON.stringify(foreign));

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  assert.equal(localStorage.getItem(transitionKey), null, "foreign marker must be discarded");
  assert.equal(localStorage.getItem(activeTimingStorageKey(context)), timingBefore);
  assert.equal(
    localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)),
    null
  );
  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutRestTransitionEnvelope(${JSON.stringify(foreign)}, activeWorkout)`, context),
    /does not match/
  );
});

test("a queued stale reconciliation cannot overwrite a newer locked rest transition", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const writer = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const observer = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(writer.context);
  vm.runInContext("reloadActiveWorkoutContext()", observer.context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", writer.context);
  const timerKey = vm.runInContext(
    "`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`",
    writer.context
  );
  const transitionAt = createdAt + 40_000;
  const deadline = transitionAt + 90_000;
  assert.equal(vm.runInContext(`(() => {
    const target = activeWorkoutTimingAfterRestTransition(activeWorkout, ${deadline}, ${transitionAt});
    const marker = persistActiveWorkoutRestTransitionMarker({
      version: 1,
      owner: activeWorkout.owner,
      workoutId: activeWorkout.id,
      workoutRevision: activeWorkout.revision,
      timerKey: ${JSON.stringify(timerKey)},
      transition: "rest",
      transitionAt: ${transitionAt},
      deadlineMillis: ${deadline},
      timing: target.timing
    }, activeWorkout);
    const timers = Object.create(null);
    timers[${JSON.stringify(timerKey)}] = ${deadline};
    return Boolean(marker && persistExerciseRestTimers(timers, activeAccount, ${transitionAt}));
  })()`, writer.context), true);

  const newerTransition = vm.runInContext(
    `adjustExerciseRestTimer(${JSON.stringify(timerKey)}, 15, ${createdAt + 70_000})`,
    writer.context
  );
  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", observer.context);
  const staleReconciliation = vm.runInContext(
    "activeWorkoutControlReconciliationPromise || Promise.resolve(true)",
    observer.context
  );
  assert.equal(await newerTransition, true);
  assert.equal(await staleReconciliation, true);
  const ledger = JSON.parse(sharedStorage.getItem(
    vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", writer.context)
  ));
  const timing = JSON.parse(sharedStorage.getItem(activeTimingStorageKey(writer.context)));
  assert.equal(ledger.entries[0].deadlineMillis, deadline + 15_000);
  assert.equal(timing.restingUntil, deadline + 15_000);
  assert.equal(sharedStorage.getItem(activeRestTransitionStorageKey(writer.context)), null);
});

test("two locked tabs apply sequential rest adjustments to the latest durable deadline", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const first = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const second = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(first.context);
  vm.runInContext("reloadActiveWorkoutContext()", second.context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", first.context);
  const timerKey = vm.runInContext(
    "`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`",
    first.context
  );
  const startAt = createdAt + 20_000;
  const initialDeadline = startAt + 90_000;
  const adjustAt = createdAt + 30_000;

  assert.equal(await vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${startAt})`,
    first.context
  ), true);
  assert.equal(
    vm.runInContext(
      `currentExerciseRestTimers(${startAt})[${JSON.stringify(timerKey)}]`,
      second.context
    ),
    initialDeadline,
    "the second tab deliberately caches the original deadline"
  );

  assert.equal(await vm.runInContext(
    `adjustExerciseRestTimer(${JSON.stringify(timerKey)}, 15, ${adjustAt})`,
    first.context
  ), true);
  assert.equal(await vm.runInContext(
    `adjustExerciseRestTimer(${JSON.stringify(timerKey)}, 15, ${adjustAt})`,
    second.context
  ), true);

  const ledger = JSON.parse(sharedStorage.getItem(
    vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", first.context)
  ));
  const timing = JSON.parse(sharedStorage.getItem(activeTimingStorageKey(first.context)));
  assert.equal(ledger.entries[0].deadlineMillis, initialDeadline + 30_000);
  assert.equal(timing.restingUntil, initialDeadline + 30_000);
  assert.equal(sharedStorage.getItem(activeRestTransitionStorageKey(first.context)), null);
});

test("an immediate adjust composes with a pending timing-first rest transition without reload", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext(
    "`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`",
    context
  );
  const startAt = createdAt + 20_000;
  const initialDeadline = startAt + 90_000;
  const adjustAt = createdAt + 30_000;
  const pendingDeadline = initialDeadline + 15_000;

  assert.equal(await vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${startAt})`,
    context
  ), true);
  assert.equal(vm.runInContext(`(() => {
    const target = activeWorkoutTimingAfterRestTransition(
      activeWorkout,
      ${pendingDeadline},
      ${adjustAt}
    );
    const marker = persistActiveWorkoutRestTransitionMarker({
      version: 1,
      owner: activeWorkout.owner,
      workoutId: activeWorkout.id,
      workoutRevision: activeWorkout.revision,
      timerKey: ${JSON.stringify(timerKey)},
      transition: "rest",
      transitionAt: ${adjustAt},
      deadlineMillis: ${pendingDeadline},
      timing: target.timing
    }, activeWorkout);
    return Boolean(marker && persistActiveWorkoutTiming(
      target.timing,
      activeWorkout,
      activeAccount,
      target.raw
    ));
  })()`, context), true, "simulate a crash after timing but before ledger");
  assert.equal(
    JSON.parse(localStorage.getItem(
      vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)
    )).entries[0].deadlineMillis,
    initialDeadline
  );
  assert.equal(JSON.parse(localStorage.getItem(activeTimingStorageKey(context))).restingUntil, pendingDeadline);

  assert.equal(await vm.runInContext(
    `adjustExerciseRestTimer(${JSON.stringify(timerKey)}, 15, ${adjustAt})`,
    context
  ), true);

  const ledger = JSON.parse(localStorage.getItem(
    vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)
  ));
  const timing = JSON.parse(localStorage.getItem(activeTimingStorageKey(context)));
  assert.equal(ledger.entries[0].deadlineMillis, initialDeadline + 30_000);
  assert.equal(timing.restingUntil, initialDeadline + 30_000);
  assert.equal(localStorage.getItem(activeRestTransitionStorageKey(context)), null);
});

test("a stale read-side pruner cannot erase a newer tab's active rest timer", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const writer = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const staleReader = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(writer.context);
  vm.runInContext("reloadActiveWorkoutContext()", staleReader.context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", writer.context);
  const timerKey = vm.runInContext(
    "`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`",
    writer.context
  );
  assert.equal(vm.runInContext(`(() => {
    const timers = Object.create(null);
    timers[${JSON.stringify(timerKey)}] = ${createdAt + 10_000};
    return persistExerciseRestTimers(timers, activeAccount, ${createdAt});
  })()`, staleReader.context), true);
  vm.runInContext(
    `exerciseRestTimerLedger = loadExerciseRestTimerLedger(activeAccount, ${createdAt})`,
    staleReader.context
  );

  assert.equal(await vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${createdAt + 20_000})`,
    writer.context
  ), true);
  const durableAfterStart = sharedStorage.getItem(
    vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", writer.context)
  );
  assert.equal(
    vm.runInContext(`Object.keys(currentExerciseRestTimers(${createdAt + 30_000})).length`, staleReader.context),
    0,
    "the stale tab may prune only its in-memory view"
  );
  assert.equal(sharedStorage.getItem(
    vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", writer.context)
  ), durableAfterStart);
  assert.equal(JSON.parse(durableAfterStart).entries[0].deadlineMillis, createdAt + 110_000);
});

test("timing sidecar rejects a wrong owner and rests more than 30 minutes in the future", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const timingKey = activeTimingStorageKey(context);
  const candidate = JSON.parse(localStorage.getItem(timingKey));
  candidate.activeSince = null;
  candidate.restingUntil = Date.now() + 30 * 60 * 1000 + 60_000;
  localStorage.setItem(timingKey, JSON.stringify(candidate));
  const loaded = vm.runInContext("loadActiveWorkoutTimingRecord(activeWorkout)", context);
  assert.equal(loaded.raw, null);
  assert.equal(loaded.timing.activeSince, vm.runInContext("activeWorkout.createdAt", context));
  assert.equal(localStorage.getItem(timingKey), null, "malformed future timing must fail closed without touching the workout draft");

  candidate.owner = "local:another-account";
  candidate.activeSince = vm.runInContext("activeWorkout.createdAt", context);
  candidate.restingUntil = null;
  localStorage.setItem(timingKey, JSON.stringify(candidate));
  assert.throws(
    () => vm.runInContext(`parseActiveWorkoutTimingEnvelope(${JSON.stringify(candidate)}, activeWorkout)`, context),
    /does not match/
  );
  assert.notEqual(localStorage.getItem(activeStorageKey(context)), null);
});

test("Save all validates every unfinished set and commits one revision without starting rest", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstSetId, secondSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "81,5" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "7" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="weight"]`, { value: "83" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="reps"]`, { value: "5" });
  const restTimerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  const timerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  assert.equal(await vm.runInContext(`startExerciseRestTimer(${JSON.stringify(restTimerKey)}, 90)`, context), true);
  assert.notEqual(localStorage.getItem(timerStorageKey), null);
  localStorage.writes.length = 0;

  assert.equal(await vm.runInContext("recordAllActiveSets()", context), true);
  const stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.equal(stored.revision, 2);
  assert.deepEqual(stored.blocks[0].sets.map(set => [set.completed, set.weight, set.reps]), [
    [true, 81.5, 7],
    [true, 83, 5]
  ]);
  assert.equal(stored.blocks[0].sets[0].completedAt, stored.blocks[0].sets[1].completedAt);
  assert.equal(localStorage.writes.filter(key => key === activeStorageKey(context)).length, 1);
  assert.ok(
    localStorage.writes.indexOf(activeBulkCleanupStorageKey(context)) <
      localStorage.writes.indexOf(activeStorageKey(context)),
    "bulk cleanup intent must be durable before the all-completed main revision"
  );
  assert.equal(localStorage.getItem(activeBulkCleanupStorageKey(context)), null);
  assert.equal(localStorage.getItem(timerStorageKey), null, "Save all must stop an already-running rest without starting a new one");
  const resumedTiming = JSON.parse(localStorage.getItem(activeTimingStorageKey(context)));
  assert.equal(resumedTiming.restingUntil, null);
  assert.equal(Number.isSafeInteger(resumedTiming.activeSince), true);
});

test("Save all treats a blank weight as zero while repetitions remain required", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstSetId, secondSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "8" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="weight"]`, { value: "" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="reps"]`, { value: "" });

  assert.equal(await vm.runInContext("recordAllActiveSets()", context), false);
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).revision, 1);

  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="reps"]`, { value: "12" });
  assert.equal(await vm.runInContext("recordAllActiveSets()", context), true);
  assert.deepEqual(
    JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks[0].sets
      .map(set => [set.weight, set.reps, set.completed]),
    [[0, 8, true], [0, 12, true]]
  );
});

test("a stale tab cannot restart rest after Save all wins the active-workout lock", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const saver = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const staleTimer = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(saver.context);
  vm.runInContext("reloadActiveWorkoutContext()", staleTimer.context);
  const setIds = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    saver.context
  ));
  saver.runtimeNodes.set(`[data-active-set-id="${setIds[0]}"][data-active-field="weight"]`, { value: "80" });
  saver.runtimeNodes.set(`[data-active-set-id="${setIds[0]}"][data-active-field="reps"]`, { value: "8" });
  saver.runtimeNodes.set(`[data-active-set-id="${setIds[1]}"][data-active-field="weight"]`, { value: "82" });
  saver.runtimeNodes.set(`[data-active-set-id="${setIds[1]}"][data-active-field="reps"]`, { value: "6" });
  const timerKey = vm.runInContext(
    "`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`",
    staleTimer.context
  );

  const saveAll = vm.runInContext("recordAllActiveSets()", saver.context);
  const staleStart = vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90)`,
    staleTimer.context
  );
  assert.equal(await saveAll, true);
  assert.equal(await staleStart, false);
  assert.equal(
    sharedStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", saver.context)),
    null
  );
  assert.equal(sharedStorage.getItem(activeRestTransitionStorageKey(saver.context)), null);
  const timing = JSON.parse(sharedStorage.getItem(activeTimingStorageKey(saver.context)));
  assert.equal(timing.restingUntil, null);
  assert.equal(JSON.parse(sharedStorage.getItem(activeStorageKey(saver.context))).revision, 2);
});

test("reload completes durable Save-all cleanup after the main revision was persisted", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  assert.equal(await vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${createdAt + 20_000})`,
    context
  ), true);
  const bulkAt = createdAt + 30_000;
  assert.equal(vm.runInContext(`(() => {
    const loaded = loadActiveWorkoutRecord(activeAccount);
    const next = {
      ...loaded.workout,
      revision: loaded.workout.revision + 1,
      updatedAt: ${bulkAt},
      blocks: loaded.workout.blocks.map(block => ({
        ...block,
        sets: block.sets.map(set => ({ ...set, completed: true, completedAt: ${bulkAt} }))
      }))
    };
    const intent = persistActiveWorkoutBulkCleanupIntent(
      loaded.workout,
      next,
      ${bulkAt},
      activeAccount,
      null
    );
    const stored = intent && persistActiveWorkoutRecord(next, activeAccount, loaded.raw);
    return Boolean(intent && stored);
  })()`, context), true, "simulate a crash immediately after the all-completed main CAS");
  const pendingBulk = JSON.parse(localStorage.getItem(activeBulkCleanupStorageKey(context)));
  assert.deepEqual(Object.keys(pendingBulk), [
    "version", "owner", "workoutId", "fromRevision", "toRevision", "transitionAt", "targetRaw"
  ]);
  assert.equal(pendingBulk.targetRaw, localStorage.getItem(activeStorageKey(context)));
  assert.notEqual(
    localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)),
    null
  );
  assert.notEqual(JSON.parse(localStorage.getItem(activeTimingStorageKey(context))).restingUntil, null);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  assert.equal(localStorage.getItem(activeBulkCleanupStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeRestTransitionStorageKey(context)), null);
  assert.equal(
    localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)),
    null
  );
  const timing = JSON.parse(localStorage.getItem(activeTimingStorageKey(context)));
  assert.equal(timing.activeSince, bulkAt);
  assert.equal(timing.restingUntil, null);
  assert.deepEqual(
    JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks[0].sets.map(set => set.completed),
    [true, true]
  );
});

test("an uncommitted bulk intent is retired without stopping an ordinary rest", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  const deadline = createdAt + 110_000;
  assert.equal(await vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${createdAt + 20_000})`,
    context
  ), true);
  assert.equal(vm.runInContext(`(() => {
    const loaded = loadActiveWorkoutRecord(activeAccount);
    const next = {
      ...loaded.workout,
      revision: loaded.workout.revision + 1,
      updatedAt: ${createdAt + 30_000},
      blocks: loaded.workout.blocks.map(block => ({
        ...block,
        sets: block.sets.map(set => ({
          ...set,
          completed: true,
          completedAt: ${createdAt + 30_000}
        }))
      }))
    };
    return Boolean(persistActiveWorkoutBulkCleanupIntent(
      loaded.workout,
      next,
      ${createdAt + 30_000},
      activeAccount,
      null
    ));
  })()`, context), true);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  assert.equal(localStorage.getItem(activeBulkCleanupStorageKey(context)), null);
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).revision, 1);
  assert.equal(
    JSON.parse(localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)))
      .entries[0].deadlineMillis,
    deadline
  );
  assert.equal(JSON.parse(localStorage.getItem(activeTimingStorageKey(context))).restingUntil, deadline);
});

test("a stale bulk intent cannot clean a different same-revision target envelope", async () => {
  const { context, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const createdAt = vm.runInContext("activeWorkout.createdAt", context);
  const timerKey = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  const deadline = createdAt + 110_000;
  const targetAt = createdAt + 30_000;
  assert.equal(await vm.runInContext(
    `startExerciseRestTimer(${JSON.stringify(timerKey)}, 90, ${createdAt + 20_000})`,
    context
  ), true);
  assert.equal(vm.runInContext(`(() => {
    const loaded = loadActiveWorkoutRecord(activeAccount);
    const intended = {
      ...loaded.workout,
      revision: loaded.workout.revision + 1,
      updatedAt: ${targetAt},
      blocks: loaded.workout.blocks.map(block => ({
        ...block,
        sets: block.sets.map(set => ({ ...set, completed: true, completedAt: ${targetAt} }))
      }))
    };
    const intent = persistActiveWorkoutBulkCleanupIntent(
      loaded.workout,
      intended,
      ${targetAt},
      activeAccount,
      null
    );
    const differentTarget = { ...intended, note: "different individually-completed target" };
    return Boolean(intent && persistActiveWorkoutRecord(differentTarget, activeAccount, loaded.raw));
  })()`, context), true);
  const differentRaw = localStorage.getItem(activeStorageKey(context));
  assert.notEqual(
    JSON.parse(localStorage.getItem(activeBulkCleanupStorageKey(context))).targetRaw,
    differentRaw
  );

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  assert.equal(localStorage.getItem(activeBulkCleanupStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeStorageKey(context)), differentRaw);
  assert.equal(
    JSON.parse(localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)))
      .entries[0].deadlineMillis,
    deadline
  );
  assert.equal(JSON.parse(localStorage.getItem(activeTimingStorageKey(context))).restingUntil, deadline);
});

test("Save all rolls back every set on one invalid field and rejects a stale revision", async () => {
  const invalid = loadContext();
  await startTwoSetWorkout(invalid.context);
  const invalidIds = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    invalid.context
  ));
  invalid.runtimeNodes.set(`[data-active-set-id="${invalidIds[0]}"][data-active-field="weight"]`, { value: "81" });
  invalid.runtimeNodes.set(`[data-active-set-id="${invalidIds[0]}"][data-active-field="reps"]`, { value: "7" });
  invalid.runtimeNodes.set(`[data-active-set-id="${invalidIds[1]}"][data-active-field="weight"]`, { value: "Infinity" });
  invalid.runtimeNodes.set(`[data-active-set-id="${invalidIds[1]}"][data-active-field="reps"]`, { value: "5" });
  const invalidBefore = invalid.localStorage.getItem(activeStorageKey(invalid.context));
  assert.equal(await vm.runInContext("recordAllActiveSets()", invalid.context), false);
  assert.equal(invalid.localStorage.getItem(activeStorageKey(invalid.context)), invalidBefore);
  assert.deepEqual(JSON.parse(invalidBefore).blocks[0].sets.map(set => set.completed), [false, false]);

  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const first = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const stale = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(first.context);
  vm.runInContext("reloadActiveWorkoutContext()", stale.context);
  const [firstId, secondId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    first.context
  ));
  for (const runtime of [first, stale]) {
    runtime.runtimeNodes.set(`[data-active-set-id="${firstId}"][data-active-field="weight"]`, { value: "82" });
    runtime.runtimeNodes.set(`[data-active-set-id="${firstId}"][data-active-field="reps"]`, { value: "6" });
    runtime.runtimeNodes.set(`[data-active-set-id="${secondId}"][data-active-field="weight"]`, { value: "84" });
    runtime.runtimeNodes.set(`[data-active-set-id="${secondId}"][data-active-field="reps"]`, { value: "4" });
  }
  assert.equal(await vm.runInContext(`recordActiveSet(${firstId})`, first.context), true);
  const afterOtherTab = sharedStorage.getItem(activeStorageKey(first.context));
  assert.equal(await vm.runInContext("recordAllActiveSets()", stale.context), false);
  assert.equal(sharedStorage.getItem(activeStorageKey(first.context)), afterOtherTab);
  assert.deepEqual(JSON.parse(afterOtherTab).blocks[0].sets.map(set => set.completed), [true, false]);
});

test("changing language preserves the current route and unsaved workout draft", () => {
  const { context } = loadContext();
  const before = vm.runInContext(`
    nav = [{ name: "workouts" }, { name: "add" }];
    workoutDraft = { startedAt: 123456, note: "keep me", blocks: [{ exerciseName: "Bench Press", sets: [{ weight: "80", reps: "8" }] }] };
    JSON.stringify({ nav, workoutDraft });
  `, context);
  vm.runInContext(`handleAction("set-language", { dataset: { language: "uk" } })`, context);
  assert.equal(vm.runInContext("state.language", context), "uk");
  assert.equal(vm.runInContext("JSON.stringify({ nav, workoutDraft })", context), before);
});

test("smart rest uses exercise roles, supports 15-second adjustment, and keeps one timer", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "Role timers",
      blocks: [
        { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 5 }] },
        { exerciseName: "Lat Pulldown", catalogKey: "lat_pulldown", sets: [{ weight: 55, reps: 8 }] },
        { exerciseName: "Lateral Raise", catalogKey: "lateral_raise", sets: [{ weight: 10, reps: 9 }] }
      ]
    };
    startWorkout();
  `, context);
  const setIds = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks.map(block => block.sets[0].id))",
    context
  ));
  const expectedSeconds = [180, 120, 75];
  const expectedNames = ["Bench Press", "Lat Pulldown", "Lateral Raise"];
  const timerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);

  for (let index = 0; index < setIds.length; index += 1) {
    const setId = setIds[index];
    runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: String(80 - index * 20) });
    runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: String(6 + index) });
    assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, context), true);
    const workout = JSON.parse(localStorage.getItem(activeStorageKey(context)));
    const completed = workout.blocks[index].sets[0];
    const ledger = JSON.parse(localStorage.getItem(timerStorageKey));
    assert.equal(ledger.entries.length, 1, "recording a new set must replace the previous timer");
    assert.equal(ledger.entries[0].exerciseName, expectedNames[index]);
    const duration = ledger.entries[0].deadlineMillis - completed.completedAt;
    assert.ok(duration >= expectedSeconds[index] * 1000 - 1000);
    assert.ok(duration <= expectedSeconds[index] * 1000 + 1000);
  }

  const latestLedger = JSON.parse(localStorage.getItem(timerStorageKey));
  const latestKey = `${latestLedger.entries[0].sessionId}:${latestLedger.entries[0].exerciseName}`;
  const beforeAdjust = latestLedger.entries[0].deadlineMillis;
  assert.equal(await vm.runInContext(`adjustExerciseRestTimer(${JSON.stringify(latestKey)}, 15)`, context), true);
  const afterAdjust = JSON.parse(localStorage.getItem(timerStorageKey)).entries[0].deadlineMillis;
  assert.ok(afterAdjust - beforeAdjust >= 14_000 && afterAdjust - beforeAdjust <= 16_000);
  assert.equal(await vm.runInContext(`stopExerciseRestTimer(${JSON.stringify(latestKey)})`, context), true);
  assert.equal(localStorage.getItem(timerStorageKey), null);

  assert.equal(await vm.runInContext(`startExerciseRestTimer(${JSON.stringify(latestKey)}, 10, 1_000)`, context), true);
  assert.equal(await vm.runInContext(`adjustExerciseRestTimer(${JSON.stringify(latestKey)}, -15, 1_000)`, context), true);
  assert.equal(localStorage.getItem(timerStorageKey), null, "subtracting past zero must stop, not increase, rest");
});

test("reload preserves the valid rest after an individually recorded final set", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "One set",
      blocks: [{
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        sets: [{ weight: 80, reps: 8 }]
      }]
    };
    startWorkout();
  `, context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "80" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, context), true);
  const timerStorageKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  const timerBefore = localStorage.getItem(timerStorageKey);
  assert.notEqual(timerBefore, null);
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", context), setId);
  assert.equal(localStorage.getItem(activeBulkCleanupStorageKey(context)), null);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  await awaitActiveControlReconciliation(context);
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", context), setId);
  assert.equal(localStorage.getItem(timerStorageKey), timerBefore);
  assert.notEqual(JSON.parse(localStorage.getItem(activeTimingStorageKey(context))).restingUntil, null);
});

test("a separate durable marker preserves exactly one latest undo across reload without changing v1 JSON", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstSetId, secondSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "81.5" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "7" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="weight"]`, { value: "83" });
  runtimeNodes.set(`[data-active-set-id="${secondSetId}"][data-active-field="reps"]`, { value: "5" });
  assert.equal(await vm.runInContext(`recordActiveSet(${firstSetId})`, context), true);
  assert.equal(await vm.runInContext(`recordActiveSet(${secondSetId})`, context), true);

  const undoKey = activeUndoStorageKey(context);
  let marker = JSON.parse(localStorage.getItem(undoKey));
  assert.deepEqual(Object.keys(marker), ["version", "owner", "workoutId", "workoutRevision", "setId"]);
  assert.equal(marker.setId, secondSetId);
  assert.equal(Object.hasOwn(JSON.parse(localStorage.getItem(activeStorageKey(context))), "undoableSetId"), false);
  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", context), secondSetId);
  const reloadMarkup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(reloadMarkup, /data-action="undo-active-set"/);
  assert.doesNotMatch(reloadMarkup, /Undo last set/);
  assert.match(reloadMarkup, /class="active-set-undo-key"/);
  assert.match(reloadMarkup, new RegExp(`data-active-set-undoable="${secondSetId}"`));
  assert.match(reloadMarkup, /data-timer-display=/);
  assert.match(reloadMarkup, /data-action="timer-adjust"[^>]*data-seconds="-15"/);
  assert.match(reloadMarkup, /data-action="timer-adjust"[^>]*data-seconds="15"/);
  assert.match(reloadMarkup, /data-action="timer-stop"/);

  assert.equal(await vm.runInContext(`undoLatestActiveSet(${firstSetId})`, context), false);
  assert.equal(await vm.runInContext(`undoLatestActiveSet(${secondSetId})`, context), true);
  let stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.equal(Object.hasOwn(stored, "undoableSetId"), false);
  marker = JSON.parse(localStorage.getItem(undoKey));
  assert.equal(marker.setId, null, "consumption must leave a revision-bound tombstone");
  assert.equal(stored.blocks[0].sets[0].completed, true);
  assert.deepEqual(
    [stored.blocks[0].sets[1].completed, stored.blocks[0].sets[1].weight, stored.blocks[0].sets[1].reps],
    [false, 83, 5]
  );
  assert.equal(localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)), null);

  vm.runInContext("clearActiveWorkoutMemory(); reloadActiveWorkoutContext();", context);
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", context), null);
  assert.equal(await vm.runInContext(`undoLatestActiveSet(${firstSetId})`, context), false,
    "undo must not cascade into older completed sets");
  stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.equal(stored.blocks[0].sets[0].completed, true);
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(markup, /data-action="undo-active-set"|data-active-set-undoable/);
  assert.match(markup, /data-active-field="weight"[^>]*value="83"/);
  assert.match(markup, /data-active-workout-hero aria-label="Elapsed [0-9:]+, 1 of 2 sets done/);
  assert.match(markup, /<strong>1\/2<\/strong><span>sets<\/span>/);
});

test("storage events refresh the separate undo marker across tabs", async () => {
  const sharedStorage = createStorage();
  const sharedLocks = createWebLocks();
  const recorder = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  const observer = loadContext({ localStorage: sharedStorage, locks: sharedLocks });
  await startTwoSetWorkout(recorder.context);
  observer.windowListeners.get("storage")({ key: activeStorageKey(recorder.context) });

  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", recorder.context);
  recorder.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "80" });
  recorder.runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, recorder.context), true);

  observer.windowListeners.get("storage")({ key: activeUndoStorageKey(observer.context) });
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", observer.context), setId);
  assert.match(
    vm.runInContext("activeWorkoutScreen()", observer.context),
    new RegExp(`data-action="undo-active-set" data-id="${setId}"`)
  );

  assert.equal(await vm.runInContext(`undoLatestActiveSet(${setId})`, recorder.context), true);
  observer.windowListeners.get("storage")({ key: activeUndoStorageKey(observer.context) });
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", observer.context), null);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", observer.context), /data-action="undo-active-set"/);
});

async function recordTwoSetWorkoutSet(context, runtimeNodes, setId, weight, reps) {
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: String(weight) });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: String(reps) });
  return vm.runInContext(`recordActiveSet(${setId})`, context);
}

function twoSetIds(context) {
  return JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
}

function completedRowMarkup(markup, setId) {
  const start = markup.indexOf(`<div class="active-set-row completed" data-active-set-row="${setId}"`);
  assert.ok(start >= 0, `completed row ${setId} must render`);
  const nextRow = markup.indexOf('<div class="active-set-row', start + 10);
  return markup.slice(start, nextRow < 0 ? undefined : nextRow);
}

test("one confirmation banner per recorded set reads Recorded without the rest suffix and announces it with the suffix", async () => {
  const expectations = {
    en: ["Recorded: 40 kg × 10", "Undo", " · rest 3:00"],
    uk: ["Записано: 40 кг × 10", "Скасувати", " · відпочинок 3:00"],
    ru: ["Записано: 40 кг × 10", "Отменить", " · отдых 3:00"]
  };
  for (const [language, [message, undo, suffix]] of Object.entries(expectations)) {
    const { context, runtimeNodes } = loadContext();
    await startTwoSetWorkout(context);
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    const [setId] = twoSetIds(context);
    assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, setId, 40, 10), true);

    const confirmation = JSON.parse(vm.runInContext("JSON.stringify(activeSetConfirmation)", context));
    assert.deepEqual(Object.keys(confirmation).sort(), ["announced", "announcement", "message", "setId", "workoutId"]);
    assert.equal(confirmation.setId, setId);
    assert.equal(confirmation.message, message);
    assert.equal(confirmation.announcement, message + suffix);
    assert.equal(vm.runInContext("activeWorkoutUi.messageKey", context), null,
      "the generic success status must not duplicate the banner");

    const markup = vm.runInContext("activeWorkoutScreen()", context);
    const banner = markup.match(/<div class="active-set-confirmation"[\s\S]*?<\/button><\/div>/)?.[0] ?? "";
    assert.ok(banner, `banner markup (${language})`);
    assert.match(banner, new RegExp(`data-active-set-confirmation="${setId}"`));
    assert.ok(banner.includes(`class="active-set-confirmation-text" aria-hidden="true">${message}</span>`));
    assert.doesNotMatch(banner.split('<span class="sr-only"')[0], /rest 3:00|відпочинок 3:00|отдых 3:00/);
    assert.ok(banner.includes(`role="status" aria-live="polite">${message + suffix}</span>`));
    assert.ok(banner.includes(`data-action="undo-active-set" data-id="${setId}">${undo}</button>`));
    assert.match(banner, /data-action="dismiss-active-set-confirmation"/);
    assert.ok(markup.indexOf("active-workout-hero") < markup.indexOf('class="active-set-confirmation"'));
    assert.ok(markup.indexOf('class="active-set-confirmation"') < markup.indexOf('class="active-workout-list"'));
    assert.doesNotMatch(markup, /Smart rest started|Розумний відпочинок/);
  }
});

test("the confirmation is memory only, replaced by the next record, and cleared by undo, dismiss, voice start and route exit", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstId, secondId] = twoSetIds(context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 40, 10), true);
  assert.equal(vm.runInContext("activeSetConfirmation.setId", context), firstId);
  assert.equal(
    [...localStorage.values.values()].some(value => value.includes("Recorded: 40")),
    false,
    "the confirmation text is never persisted"
  );

  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, secondId, 42.5, 8), true);
  assert.equal(vm.runInContext("activeSetConfirmation.setId", context), secondId);
  assert.equal(vm.runInContext("activeSetConfirmation.message", context), "Recorded: 42.5 kg × 8");
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.equal((markup.match(/data-active-set-confirmation=/g) || []).length, 1);

  await vm.runInContext(`handleAction("dismiss-active-set-confirmation", { dataset: {} })`, context);
  assert.equal(vm.runInContext("activeSetConfirmation", context), null);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /data-active-set-confirmation/);

  vm.runInContext(`setActiveSetConfirmation(activeWorkout.id, ${secondId}, 42.5, 8, 0)`, context);
  assert.equal(vm.runInContext("activeSetConfirmation.announcement", context), "Recorded: 42.5 kg × 8",
    "no rest suffix when no rest applies");
  await vm.runInContext(`handleAction("undo-active-set", { dataset: { id: "${secondId}" } })`, context);
  assert.equal(vm.runInContext("activeSetConfirmation", context), null);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets[1].completed", context), false);

  // A banner for a set that is no longer the undoable latest disappears on render.
  vm.runInContext(`setActiveSetConfirmation(activeWorkout.id, ${secondId}, 42.5, 8, 0)`, context);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /data-active-set-confirmation/);
  assert.equal(vm.runInContext("activeSetConfirmation", context), null);

  // Starting a voice command drops the banner before anything else.
  vm.runInContext(`setActiveSetConfirmation(activeWorkout.id, ${firstId}, 40, 10, 0)`, context);
  vm.runInContext(`voiceWorkoutAvailability = async () => ({ status: "unavailable" }); startActiveSetVoiceCommand(${secondId});`, context);
  assert.equal(vm.runInContext("activeSetConfirmation", context), null);

  assert.match(appSource, /if \(current\.name !== "active"\) activeSetConfirmation = null;/);
});

test("a voice-recorded set raises the same single banner and no toast", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [setId] = twoSetIds(context);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "" });
  const ok = await vm.runInContext(`
    globalThis.toastCalls = [];
    showToast = message => { toastCalls.push(message); };
    window.GymVoiceWorkout = { formatWeight: value => String(value) };
    syncActiveSetSteppers = () => {};
    applyActiveSetVoiceLogSet(${setId}, { intent: "logSet", weightKg: 60, reps: 12 })
  `, context);
  assert.equal(ok, true);
  assert.equal(vm.runInContext("toastCalls.length", context), 0);
  assert.equal(vm.runInContext("activeSetConfirmation.message", context), "Recorded: 60 kg × 12");
});

test("the latest completed row is one compact line whose rest controls keep the timer actions", async () => {
  for (const [language, labels] of Object.entries({
    en: ["Rest timer", "Decrease rest by 15 seconds", "Increase rest by 15 seconds", "Stop rest"],
    uk: ["Таймер відпочинку", "Зменшити відпочинок на 15 секунд", "Збільшити відпочинок на 15 секунд", "Зупинити відпочинок"],
    ru: ["Таймер отдыха", "Уменьшить отдых на 15 секунд", "Увеличить отдых на 15 секунд", "Остановить отдых"]
  })) {
    const { context, runtimeNodes } = loadContext();
    await startTwoSetWorkout(context);
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    const [firstId, secondId] = twoSetIds(context);
    assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 80, 8), true);
    const key = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);

    const markup = vm.runInContext("activeWorkoutScreen()", context);
    const row = completedRowMarkup(markup, firstId);
    assert.match(row, /class="active-set-check"/);
    assert.match(row, /class="active-set-summary-text">80 (kg|кг) × 8</);
    assert.ok(row.includes(`role="group" aria-label="${labels[0]}"`));
    assert.match(row, new RegExp(
      `<span class="active-set-rest-time" data-timer-display="${key}" aria-hidden="true">03:00</span>`
    ));
    assert.match(row, /data-action="timer-adjust" data-timer-control="[^"]+" data-seconds="-15" data-key="[^"]+" aria-label="[^"]+"><span>−15<\/span>/);
    assert.match(row, /data-action="timer-adjust" data-timer-control="[^"]+" data-seconds="15" data-key="[^"]+" aria-label="[^"]+"><span>\+15<\/span>/);
    assert.match(row, /data-action="timer-stop" data-timer-control="[^"]+" data-timer-stop="[^"]+" data-key="[^"]+"/);
    for (const label of labels.slice(1)) assert.ok(row.includes(`aria-label="${label}"`), label);
    assert.doesNotMatch(row, /Ready|Готово|Set saved|Undo last set|Підхід збережено|Подход сохранён/);
    assert.doesNotMatch(markup, /active-workout-timer|class="timer-row/);
  }
});

test("rest controls hide at zero instead of showing Ready and are absent once the rest is stopped", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstId] = twoSetIds(context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 80, 8), true);
  const key = vm.runInContext("`${activeWorkout.id}:${activeWorkout.blocks[0].exerciseName}`", context);
  vm.runInContext(`
    globalThis.restContainer = { hidden: false };
    globalThis.restDisplay = {
      dataset: { timerDisplay: ${JSON.stringify(key)} },
      textContent: "",
      closest: selector => selector === "[data-active-rest-controls]" ? restContainer : null
    };
    document.querySelectorAll = selector => selector === "[data-timer-display]" ? [restDisplay] : [];
    updateTimerDisplays();
  `, context);
  assert.equal(vm.runInContext("restContainer.hidden", context), false);
  assert.match(vm.runInContext("restDisplay.textContent", context), /^0[23]:\d\d$/);

  assert.equal(await vm.runInContext(`stopExerciseRestTimer(${JSON.stringify(key)})`, context), true);
  vm.runInContext("restDisplay.textContent = '00:01'; updateTimerDisplays();", context);
  assert.equal(vm.runInContext("restContainer.hidden", context), true);
  assert.equal(vm.runInContext("restDisplay.textContent", context), "00:01", "the display never switches to Ready");
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /data-active-rest-controls|data-timer-display/);
  const styles = await readFile("pwa/styles.css", "utf8");
  assert.match(styles, /\.active-set-rest\[hidden\]\s*\{\s*display:\s*none;/);
});

test("undo without a standing button: latest-only long-press menu, context menu and keyboard action", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstId, secondId] = twoSetIds(context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 80, 8), true);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, secondId, 82.5, 6), true);

  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(markup, /Undo last set|Скасувати останній підхід|Отменить последний подход/);
  const olderRow = completedRowMarkup(markup, firstId);
  const latestRow = completedRowMarkup(markup, secondId);
  assert.doesNotMatch(olderRow, /data-active-set-undoable|undo-active-set|active-set-undo-key/);
  assert.match(latestRow, new RegExp(`data-active-set-undoable="${secondId}"`));
  assert.match(latestRow, new RegExp(
    `<button class="active-set-undo-key" type="button" data-action="undo-active-set" data-id="${secondId}">Undo set</button>`
  ));

  // Menu only for the undoable latest set and never while a set mutation is in flight.
  assert.equal(vm.runInContext(`openActiveSetUndoMenu(${firstId})`, context), false);
  vm.runInContext("activeSetMutationsInFlight = 1", context);
  assert.equal(vm.runInContext(`openActiveSetUndoMenu(${secondId})`, context), false);
  vm.runInContext("activeSetMutationsInFlight = 0", context);

  // contextmenu opens the one-action sheet and suppresses the browser menu.
  let prevented = 0;
  globalThis.__undoRow = { dataset: { activeSetUndoable: String(secondId) } };
  const contextEvent = {
    target: { closest: selector => selector === "[data-active-set-undoable]" ? globalThis.__undoRow : null },
    preventDefault() { prevented += 1; }
  };
  context.__contextEvent = contextEvent;
  vm.runInContext("handleActiveSetContextMenu(__contextEvent)", context);
  assert.equal(prevented, 1);
  assert.equal(vm.runInContext("modal.type", context), "active-set-undo");
  const sheet = vm.runInContext("modalMarkup()", context);
  assert.match(sheet, /aria-labelledby="active-set-undo-title"/);
  assert.match(sheet, new RegExp(
    `data-action="undo-active-set" data-id="${secondId}">Undo set</button>`
  ));
  assert.equal((sheet.match(/data-action="undo-active-set"/g) || []).length, 1);

  await vm.runInContext(`handleAction("undo-active-set", { dataset: { id: "${secondId}" } })`, context);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets[1].completed", context), false);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets[0].completed", context), true);
});

test("long-press opens the undo menu after about half a second and cancels on movement", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstId] = twoSetIds(context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 80, 8), true);
  const row = { dataset: { activeSetUndoable: String(firstId) } };
  context.__pressEvent = clientX => ({
    isPrimary: true,
    button: 0,
    clientX,
    clientY: 10,
    target: { closest: selector => selector === "[data-active-set-undoable]" ? row : null }
  });

  vm.runInContext("beginActiveSetLongPress(__pressEvent(10)); moveActiveSetLongPress(__pressEvent(40));", context);
  assert.equal(vm.runInContext("activeSetLongPress", context), null, "movement cancels the press");
  await new Promise(resolve => setTimeout(resolve, 650));
  assert.equal(vm.runInContext("modal", context), null);

  vm.runInContext("beginActiveSetLongPress(__pressEvent(10)); moveActiveSetLongPress(__pressEvent(12));", context);
  assert.notEqual(vm.runInContext("activeSetLongPress", context), null);
  await new Promise(resolve => setTimeout(resolve, 650));
  assert.equal(vm.runInContext("modal?.type", context), "active-set-undo");
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
  const [setId, unfinishedSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(unfinishedSetId))}, activeField: "reps" },
    value: "6"
  })`, context), true);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "85" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "5" });
  await vm.runInContext(`recordActiveSet(${setId})`, context);
  await vm.runInContext("finishActiveWorkout()", context);

  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets[0].id", context), setId);
  assert.equal(vm.runInContext("state.sessions[0].sets[0].weight", context), 85);
  assert.equal(vm.runInContext("Number.isSafeInteger(state.sessions[0].durationSeconds)", context), true);
  assert.equal(vm.runInContext("state.sessions[0].durationSeconds >= 0", context), true);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(activeStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeUndoStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeInputDraftStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeTimingStorageKey(context)), null);
  assert.equal(localStorage.getItem(vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context)), null);

  const stateKey = vm.runInContext("activeStorageKey()", context);
  const baseState = JSON.parse(localStorage.getItem(stateKey));
  assert.equal(baseState.sessions.length, 0, "Finish must not overwrite the ordinary cross-tab state key");
  const durationRaw = localStorage.getItem(vm.runInContext("activeWorkoutAccountDescriptor().durationKey", context));
  assert.notEqual(durationRaw, null, "duration metadata must be durable outside the legacy state and commit envelopes");
  const durationLedger = JSON.parse(durationRaw);
  assert.deepEqual(Object.keys(durationLedger), ["version", "owner", "items"]);
  assert.deepEqual(Object.keys(durationLedger.items[0]), ["sessionId", "startedAt", "durationSeconds"]);
  const commitRaw = localStorage.getItem(vm.runInContext("activeWorkoutAccountDescriptor().commitKey", context));
  assert.notEqual(commitRaw, null, "completed sets must be durable in the separate commit ledger");
  const commit = JSON.parse(commitRaw);
  assert.deepEqual(Object.keys(commit), ["version", "owner", "workouts"]);
  assert.deepEqual(Object.keys(commit.workouts[0]), [
    "version", "owner", "id", "startedAt", "createdAt", "updatedAt", "revision", "note", "blocks"
  ], "commit entries must remain exact-readable by app.v69");
  assert.equal(Object.hasOwn(commit.workouts[0], "undoableSetId"), false);
  vm.runInContext("state = loadState(activeAccount)", context);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 1);
  const reloaded = loadContext({ localStorage, locks: createWebLocks() });
  assert.equal(reloaded.startupState.sessions.length, 1, "startup must recover committed history before rendering");
  assert.equal(reloaded.startupState.sessions[0].sets[0].id, setId);
  assert.equal(reloaded.startupState.sessions[0].durationSeconds, durationLedger.items[0].durationSeconds);
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
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  const [setId, unfinishedSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(unfinishedSetId))}, activeField: "weight" },
    value: "82.5"
  })`, context), true);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "80" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, context), true);
  assert.notEqual(localStorage.getItem(activeUndoStorageKey(context)), null);
  vm.runInContext("requestDiscardActiveWorkout({ action: 'discard-active-workout' })", context);
  assert.equal(vm.runInContext("modal.type", context), "confirm-discard-active");
  assert.match(vm.runInContext("modalMarkup()", context), /role="alertdialog"/);
  assert.notEqual(localStorage.getItem(key), null, "opening confirmation must not delete anything");

  await vm.runInContext("confirmDiscardActiveWorkout()", context);
  assert.equal(localStorage.getItem(key), null);
  assert.equal(localStorage.getItem(activeUndoStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeInputDraftStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeTimingStorageKey(context)), null);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(vm.runInContext("state.sessions.length", context), 0);
});

test("external active-workout invalidation closes confirmation and restores stable focus", async () => {
  for (const invalidation of ["active-storage", "auth-marker"]) {
    const runtime = loadContext();
    await startTwoSetWorkout(runtime.context);
    let restoredFocus = 0;
    const trigger = {
      dataset: { action: "discard-active-workout" },
      focus() {
        restoredFocus += 1;
        runtime.context.document.activeElement = this;
      }
    };
    runtime.appNode.querySelectorAll = selector => selector === '[data-action="discard-active-workout"]'
      ? [trigger]
      : [];
    vm.runInContext(
      "requestDiscardActiveWorkout({ action: 'discard-active-workout' })",
      runtime.context
    );
    assert.equal(vm.runInContext("modal.type", runtime.context), "confirm-discard-active");

    if (invalidation === "active-storage") {
      const key = activeStorageKey(runtime.context);
      runtime.localStorage.removeItem(key);
      runtime.windowListeners.get("storage")({ key });
    } else {
      const key = vm.runInContext("AUTH_KEY", runtime.context);
      runtime.windowListeners.get("storage")({ key });
    }

    assert.equal(vm.runInContext("modal", runtime.context), null);
    assert.equal(restoredFocus, 1, `${invalidation} must restore the confirmation invoker`);
  }
});

test("account switching clears active memory without exposing or deleting the owner's draft", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const key = activeStorageKey(context);
  const [setId, unfinishedSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    context
  ));
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(unfinishedSetId))}, activeField: "reps" },
    value: "06"
  })`, context), true);
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="weight"]`, { value: "80" });
  runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${setId})`, context), true);
  const undoKey = activeUndoStorageKey(context);
  const inputKey = activeInputDraftStorageKey(context);
  const raw = localStorage.getItem(key);
  const undoRaw = localStorage.getItem(undoKey);
  const inputRaw = localStorage.getItem(inputKey);

  await vm.runInContext("logoutAccount()", context);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(key), raw, "ordinary account switching keeps the owner's recoverable draft");
  assert.equal(localStorage.getItem(undoKey), undoRaw, "ordinary account switching keeps its one-step Undo marker");
  assert.equal(localStorage.getItem(inputKey), inputRaw, "ordinary account switching keeps exact unfinished input");

  vm.runInContext(`
    activeAccount = ${JSON.stringify(LOCAL_ACCOUNT)};
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    state = loadState(activeAccount);
    reloadActiveWorkoutContext(activeAccount);
  `, context);
  assert.equal(vm.runInContext("activeWorkout.owner", context), `local:${LOCAL_ACCOUNT.id}`);
  assert.equal(vm.runInContext("activeWorkoutUndoMarker.setId", context), setId);
  assert.equal(vm.runInContext(
    `activeLiveDraftInputValue(activeWorkout.blocks[0].sets[1], "reps")`,
    context
  ), "06");
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
  const [setId, unfinishedSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))",
    recorder.context
  ));
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(unfinishedSetId))}, activeField: "reps" },
    value: "11"
  })`, recorder.context), true);
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
  assert.equal(sharedStorage.getItem(descriptor.undoKey), null);
  assert.equal(sharedStorage.getItem(descriptor.inputDraftKey), null);
  assert.equal(sharedStorage.getItem(descriptor.timingKey), null);
  assert.equal(sharedStorage.getItem(descriptor.restTransitionKey), null);
  assert.equal(sharedStorage.getItem(descriptor.bulkCleanupKey), null);
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
  assert.throws(
    () => vm.runInContext("parseActiveWorkoutEnvelope({ ...globalThis.__candidate, undoableSetId: null })", context),
    /unsupported fields/
  );

  const recoveryKey = vm.runInContext("activeWorkoutAccountDescriptor().recoveryKey", context);
  const commitKey = vm.runInContext("activeWorkoutAccountDescriptor().commitKey", context);
  const undoKey = activeUndoStorageKey(context);
  const inputKey = activeInputDraftStorageKey(context);
  const timingKey = activeTimingStorageKey(context);
  const restTransitionKey = activeRestTransitionStorageKey(context);
  const bulkCleanupKey = activeBulkCleanupStorageKey(context);
  localStorage.setItem(recoveryKey, localStorage.getItem(key));
  localStorage.setItem(commitKey, JSON.stringify({
    version: 1,
    owner: `local:${LOCAL_ACCOUNT.id}`,
    workouts: []
  }));
  localStorage.setItem(undoKey, JSON.stringify({
    version: 1,
    owner: `local:${LOCAL_ACCOUNT.id}`,
    workoutId: candidate.id,
    workoutRevision: candidate.revision,
    setId: null
  }));
  localStorage.setItem(inputKey, "pending-account-bound-input");
  localStorage.setItem(restTransitionKey, "pending-account-bound-cleanup");
  localStorage.setItem(bulkCleanupKey, "pending-bulk-cleanup");

  context.window.confirm = () => true;
  context.window.prompt = () => "DELETE";
  await vm.runInContext("deleteLocalAccount()", context);
  assert.equal(localStorage.getItem(key), null);
  assert.equal(localStorage.getItem(recoveryKey), null);
  assert.equal(localStorage.getItem(commitKey), null);
  assert.equal(localStorage.getItem(undoKey), null);
  assert.equal(localStorage.getItem(inputKey), null);
  assert.equal(localStorage.getItem(timingKey), null);
  assert.equal(localStorage.getItem(restTransitionKey), null);
  assert.equal(localStorage.getItem(bulkCleanupKey), null);
  assert.equal(vm.runInContext("activeWorkout", context), null);
  assert.equal(localStorage.getItem(`gym-pwa-account:${LOCAL_ACCOUNT.id}`), null);
});

test("four-week programs preserve owner boundaries, schedule and saved-workout links", () => {
  const { context, localStorage } = loadContext();
  assert.equal(vm.runInContext("createTrainingProgram()", context), true);
  const key = vm.runInContext("trainingProgramDescriptor().storageKey", context);
  const original = JSON.parse(localStorage.getItem(key));
  assert.equal(original.slots.length, original.days * 4);
  assert.ok(original.slots.at(-1).date > Date.now());
  for (const mutate of [
    p => { p.owner = "other-owner"; },
    p => { p.slots[1].id = p.slots[0].id; },
    p => { p.slots[0].date = Number.MAX_SAFE_INTEGER; },
    p => { p.slots[0].sessionId = p.slots[1].sessionId = 7; },
    p => { p.goal = "x".repeat(32769); }
  ]) {
    const invalid = structuredClone(original); mutate(invalid);
    context.invalidProgram = JSON.stringify(invalid);
    assert.equal(vm.runInContext("parseTrainingProgram(invalidProgram)", context), null);
    assert.equal(localStorage.getItem(key), JSON.stringify(original));
  }
  vm.runInContext(`
    state.sessions = [{id: 901, startedAt: Date.now(), exercises: []}];
    updateTrainingProgramAction("training-program-link", {dataset:{session:"902"}});
  `, context);
  assert.equal(JSON.parse(localStorage.getItem(key)).slots[0].sessionId, null);
  vm.runInContext('updateTrainingProgramAction("training-program-link", {dataset:{session:"901"}})', context);
  assert.equal(JSON.parse(localStorage.getItem(key)).slots[0].sessionId, 901);
  vm.runInContext('updateTrainingProgramAction("training-program-state", {dataset:{status:"paused"}})', context);
  const paused = localStorage.getItem(key);
  vm.runInContext('updateTrainingProgramAction("training-program-reschedule", {dataset:{}})', context);
  assert.equal(localStorage.getItem(key), paused);
  vm.runInContext('localStorage.removeItem(AUTH_KEY)', context);
  assert.equal(vm.runInContext("createTrainingProgram()", context), false);
  assert.equal(localStorage.getItem(key), paused);
});

test("adaptation preview preserves completed work and only apply commits pending targets", async () => {
  const { context, runtimeNodes, localStorage } = loadContext();
  await startTwoSetWorkout(context);
  const [first, second] = JSON.parse(vm.runInContext("JSON.stringify(activeWorkout.blocks[0].sets.map(s=>s.id))", context));
  runtimeNodes.set(`[data-active-set-id="${first}"][data-active-field="weight"]`, {value:"80"});
  runtimeNodes.set(`[data-active-set-id="${first}"][data-active-field="reps"]`, {value:"8"});
  assert.equal(await vm.runInContext(`recordActiveSet(${first})`, context), true);
  runtimeNodes.set(`[data-active-set-id="${second}"][data-active-field="weight"]`, {value:"85"});
  runtimeNodes.set(`[data-active-set-id="${second}"][data-active-field="reps"]`, {value:"6"});
  const before = localStorage.getItem(activeStorageKey(context));
  vm.runInContext('openTrainingAdaptation("tooHard")', context);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);
  assert.equal(vm.runInContext("modal.candidate.blocks[0].sets[1].weight", context), 82.5);
  assert.equal(await vm.runInContext("applyTrainingAdaptation()", context), true);
  const after = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.deepEqual(after.blocks[0].sets[0], JSON.parse(before).blocks[0].sets[0]);
  assert.equal(after.blocks[0].sets[1].weight, 82.5);
  assert.equal(after.revision, JSON.parse(before).revision + 1);
  assert.equal(await vm.runInContext("applyTrainingAdaptation()", context), false);
});

test("adaptation rejects stale history, live binding and account switching without writing", async () => {
  for (const change of [
    'state.profile.days = 6',
    'liveWorkoutBinding = {localWorkoutId: activeWorkout.id}',
    'localStorage.removeItem(AUTH_KEY)'
  ]) {
    const { context, runtimeNodes, localStorage } = loadContext();
    await startTwoSetWorkout(context);
    for (const set of JSON.parse(vm.runInContext("JSON.stringify(activeWorkout.blocks[0].sets)", context))) {
      runtimeNodes.set(`[data-active-set-id="${set.id}"][data-active-field="weight"]`, {value:String(set.weight)});
      runtimeNodes.set(`[data-active-set-id="${set.id}"][data-active-field="reps"]`, {value:String(set.reps)});
    }
    const key = activeStorageKey(context), before = localStorage.getItem(key);
    vm.runInContext('openTrainingAdaptation("tooHard")', context);
    vm.runInContext(change, context);
    assert.equal(await vm.runInContext("applyTrainingAdaptation()", context), false);
    assert.equal(localStorage.getItem(key), before);
  }
});

test("live personal records follow the shared iOS and Android rules", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const history = (weights, reps, startedAt = 1000) => ({
      id: startedAt,
      startedAt,
      note: "",
      exerciseNames: ["Bench Press"],
      sets: weights.map((weight, index) => ({
        id: startedAt + index + 1,
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        weight,
        reps: reps[index],
        orderIndex: index
      }))
    });
    const workout = sets => ({
      id: 77,
      createdAt: 5000,
      blocks: [{
        id: 1,
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        sets: sets.map(([weight, reps, completedAt], index) => ({
          id: 100 + index,
          weight,
          reps,
          completed: completedAt !== null,
          completedAt
        }))
      }]
    });
    const ids = (sets, sessions) => [...personalRecordSetIds(workout(sets), sessions)].sort();
    return JSON.stringify({
      beats: ids([[85, 3, 6000], [80, 10, 6001], [80, 8, 6002], [120, 5, null]], [history([80, 80], [8, 8])]),
      firstSession: ids([[60, 8, 6000], [70, 8, 6001]], []),
      zeroKilograms: ids([[0, 20, 6000], [5, 8, 6001]], [history([0], [8])]),
      bestSoFar: ids([[90, 5, 6000], [85, 5, 6001], [95, 5, 6002], [95, 5, 6003]], [history([80], [5])]),
      completionOrder: ids([[90, 5, 7000], [90, 5, 6000]], [history([80], [5])]),
      laterHistoryIgnored: ids([[85, 5, 6000]], [history([80], [5]), history([200], [5], 9000)])
    });
  })()`, context));

  assert.deepEqual(result.beats, [100, 101]);
  assert.deepEqual(result.firstSession, []);
  assert.deepEqual(result.zeroKilograms, [101]);
  assert.deepEqual(result.bestSoFar, [100, 102]);
  assert.deepEqual(result.completionOrder, [101]);
  assert.deepEqual(result.laterHistoryIgnored, [100]);
});

test("plate math splits a barbell total per side and is localized", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const lines = (total, language) => {
      state.language = language;
      return plateSummaryLines(plateLoad(total));
    };
    return JSON.stringify({
      plates: [82.5, 100, 140, 22.5, 25].map(total => plateLoad(total).platesPerSide),
      barOnly: plateLoad(20),
      below: [plateLoad(15).status, plateLoad(0).status, plateLoad(Number.NaN).status],
      remainder: plateLoad(83),
      ru: lines(82.5, "ru"),
      ruRemainder: lines(83, "ru"),
      uk: lines(82.5, "uk"),
      en: lines(82.5, "en"),
      ruBelow: lines(15, "ru"),
      enBar: lines(20, "en"),
      barbell: plateCalculatorApplies({ exerciseName: "Bench Press", catalogKey: "bench_press" }),
      dumbbell: plateCalculatorApplies({ exerciseName: "Dumbbell Bench Press", catalogKey: "dumbbell_bench_press" }),
      custom: plateCalculatorApplies({ exerciseName: "Cable Kickback" })
    });
  })()`, context));

  assert.deepEqual(result.plates, [[25, 5, 1.25], [25, 15], [25, 25, 10], [1.25], [2.5]]);
  assert.deepEqual(result.barOnly, { status: "barOnly", platesPerSide: [], remainderPerSide: 0 });
  assert.deepEqual(result.below, ["belowBar", "belowBar", "belowBar"]);
  assert.deepEqual(result.remainder.platesPerSide, [25, 5, 1.25]);
  assert.equal(result.remainder.remainderPerSide, 0.25);
  assert.deepEqual(result.ru, ["На каждую сторону: 25 + 5 + 1,25"]);
  assert.deepEqual(result.ruRemainder, ["На каждую сторону: 25 + 5 + 1,25", "Остаток: 0,25 кг на сторону"]);
  assert.deepEqual(result.uk, ["На кожну сторону: 25 + 5 + 1,25"]);
  assert.deepEqual(result.en, ["Per side: 25 + 5 + 1.25"]);
  assert.deepEqual(result.ruBelow, ["Меньше грифа 20 кг"]);
  assert.deepEqual(result.enBar, ["Bar only (20 kg)"]);
  assert.equal(result.barbell, true);
  assert.equal(result.dumbbell, false);
  assert.equal(result.custom, false);
});

test("friend ghosts keep the latest top set per exercise and read naturally", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const page = (name, items) => ({ friend: { profileId: "p_" + "a".repeat(32), displayName: name }, items });
    const workout = (startedAt, workoutDay, exercises) => ({ startedAt, workoutDay, exercises });
    const exercise = (catalogKey, name, sets) => ({ catalogKey, name, sets: sets.map(([weightKg, reps]) => ({ weightKg, reps })) });
    const ghosts = friendGhostsFromPages([
      page("Олена", [workout("2026-09-22T10:00:00.123Z", "2026-09-22", [
        exercise("bench_press", "Bench Press", [[60, 10]]),
        exercise(null, "Cable Kickback", [[15, 12]])
      ])]),
      page("Саша", [
        workout("2026-09-25T10:00:00Z", "2026-09-25", [exercise("bench_press", "Bench Press", [[80, 8], [85, 8], [85, 6]])]),
        workout("2026-09-20T10:00:00Z", "2026-09-20", [exercise("bench_press", "Bench Press", [[90, 3]])])
      ])
    ]);
    const now = new Date(2026, 8, 28, 12);
    const line = (language, ghost) => {
      state.language = language;
      return friendGhostLine(ghost, now);
    };
    const bench = ghosts.get(exerciseMatchKey({ name: "Bench Press", catalogKey: "bench_press" }));
    const kickback = ghosts.get(exerciseMatchKey({ name: "Cable Kickback" }));
    const friends = Array.from({ length: 12 }, (_, index) => ({
      displayName: "Friend " + index,
      progressUpdatedAt: index === 11 ? "2026-09-27T10:00:00Z" : index === 0 ? null : "2026-09-0" + (index % 9 + 1) + "T10:00:00Z"
    }));
    const chosen = friendGhostsToQuery(friends).map(friend => friend.displayName);
    return JSON.stringify({
      bench: { name: bench.friendName, weight: bench.weightKg, reps: bench.reps },
      kickback: kickback.friendName,
      ru: line("ru", { friendName: "Саша", weightKg: 85, reps: 8, workoutDay: "2026-09-25" }),
      uk: line("uk", { friendName: "Саша", weightKg: 82.5, reps: 5, workoutDay: "2026-09-23" }),
      en: line("en", { friendName: "Саша", weightKg: 82.5, reps: 5, workoutDay: "2026-09-27" }),
      bodyweight: line("ru", { friendName: "Саша", weightKg: 0, reps: 12, workoutDay: "2026-09-28" }),
      oneDayForm: line("ru", { friendName: "Саша", weightKg: 100, reps: 1, workoutDay: "2026-09-07" }),
      chosenCount: chosen.length,
      chosenFirst: chosen[0],
      skipsOldest: !chosen.includes("Friend 0")
    });
  })()`, context));

  assert.deepEqual(result.bench, { name: "Саша", weight: 85, reps: 8 });
  assert.equal(result.kickback, "Олена");
  assert.equal(result.ru, "Саша: 85 × 8 · 3 дня назад");
  assert.equal(result.uk, "Саша: 82,5 × 5 · 5 днів тому");
  assert.equal(result.en, "Саша: 82.5 × 5 · yesterday");
  assert.equal(result.bodyweight, "Саша: 12 повторений · сегодня");
  assert.equal(result.oneDayForm, "Саша: 100 × 1 · 21 день назад");
  assert.equal(result.chosenCount, 10);
  assert.equal(result.chosenFirst, "Friend 11");
  assert.equal(result.skipsOldest, true);
});

test("the current barbell set shows the plate capsule and records show a badge", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(markup, /class="plate-calculator"/);
  assert.match(markup, /<strong>80 kg<\/strong><span>Per side: 25 \+ 5<\/span>/);
  assert.doesNotMatch(markup, /personal-record-badge/);

  // Only a completed row carries the badge (and its accessible label says so).
  vm.runInContext("activeWorkout.blocks[0].sets[0].completed = true", context);
  const recordMarkup = vm.runInContext(`activeWorkoutBlockMarkup(
    activeWorkout.blocks[0], 0, 0, null, null, new Set([activeWorkout.blocks[0].sets[0].id])
  )`, context);
  assert.match(recordMarkup, /personal-record-badge/);
  assert.match(recordMarkup, /aria-label="Set 1 recorded, 80 kg × 8, personal record"/);
});

test("counts and weights read naturally in every language", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const at = language => {
      state.language = language;
      return [countNoun(1, "sets"), countNoun(2, "sets"), countNoun(5, "sets"), countNoun(21, "exercises"),
        countNoun(3, "workouts"), formatLocalizedSetWeight(82.5), formatLocalizedWeightReps(1.25, 8)];
    };
    return JSON.stringify({ en: at("en"), uk: at("uk"), ru: at("ru") });
  })()`, context));

  assert.deepEqual(result.en, ["1 set", "2 sets", "5 sets", "21 exercises", "3 workouts", "82.5 kg", "1.25 kg × 8"]);
  assert.deepEqual(result.uk, ["1 підхід", "2 підходи", "5 підходів", "21 вправа", "3 тренування", "82,5 кг", "1,25 кг × 8"]);
  assert.deepEqual(result.ru, ["1 подход", "2 подхода", "5 подходов", "21 упражнение", "3 тренировки", "82,5 кг", "1,25 кг × 8"]);
});

test("the active workout screen keeps the screen on and releases it when left", async () => {
  const { context } = loadContext();
  const events = [];
  context.navigator.wakeLock = {
    request: async type => {
      events.push(`request:${type}`);
      return {
        release: async () => { events.push("release"); },
        addEventListener() {}
      };
    }
  };
  await startTwoSetWorkout(context);
  vm.runInContext(`nav = [{ name: "active" }]; syncActiveWorkoutWakeLock();`, context);
  await new Promise(resolve => setTimeout(resolve, 0));
  vm.runInContext("syncActiveWorkoutWakeLock();", context);
  assert.deepEqual(events, ["request:screen"]);
  assert.match(vm.runInContext("activeWorkoutScreen()", context), /The screen stays on during the workout/);

  vm.runInContext(`nav = [{ name: "workouts" }]; syncActiveWorkoutWakeLock();`, context);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.deepEqual(events, ["request:screen", "release"]);
});

test("the train-with-a-friend pill follows the shared rules", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const entry = (isCloudAccount, friendCount, pendingInvitationCount, hasBlockingLiveWorkout) =>
      todayFriendEntryState({ isCloudAccount, friendCount, pendingInvitationCount, hasBlockingLiveWorkout });
    return JSON.stringify({
      local: todayFriendTapAction(entry(false, 0, 0, false), false),
      noFriends: todayFriendTapAction(entry(true, 0, 0, false), false),
      pick: todayFriendTapAction(entry(true, 2, 0, false), false),
      invite: entry(true, 2, 3, false),
      inviteTap: todayFriendTapAction(entry(true, 2, 3, false), false),
      live: entry(true, 2, 1, true).kind,
      soloBlocked: todayFriendTapAction(entry(true, 2, 0, false), true),
      soloInvite: todayFriendTapAction(entry(true, 2, 1, false), true)
    });
  })()`, context));

  assert.equal(result.local, "open-account");
  assert.equal(result.noFriends, "open-friends");
  assert.equal(result.pick, "pick-friend");
  assert.deepEqual(result.invite, { kind: "invite", count: 3 });
  assert.equal(result.inviteTap, "open-invites");
  assert.equal(result.live, "hidden");
  assert.equal(result.soloBlocked, "blocked");
  assert.equal(result.soloInvite, "open-invites");
});

test("Today shows the friend pill to beginners and during a solo workout", async () => {
  const { context } = loadContext();
  vm.runInContext(`state.language = "ru"`, context);
  assert.match(vm.runInContext("activationCard()", context), /data-action="today-friend"[^>]*>.*<span>С другом<\/span>/);

  await startTwoSetWorkout(context);
  vm.runInContext(`state.language = "en"; nav = [{ name: "workouts" }]; modal = null;`, context);
  const markup = vm.runInContext("focusLensCard(state.sessions)", context);
  assert.match(markup, /class="today-friend-pill "/);
  assert.match(markup, /Finish your current workout before starting a live workout with a friend/);
  assert.equal(vm.runInContext("openTodayFriendEntry()", context), true);
  assert.equal(vm.runInContext("route().name", context), "workouts");
});

test("a local account's friend pill opens cloud sign-in in Profile", () => {
  const { context } = loadContext();
  vm.runInContext(`nav = [{ name: "workouts" }]; modal = null; profileHubSection = "settings";`, context);
  assert.equal(vm.runInContext("openTodayFriendEntry()", context), true);
  assert.equal(vm.runInContext("route().name", context), "leaderboard");
  assert.equal(vm.runInContext("profileHubSection", context), "training");
});

test("picking a friend from Today opens the live workout editor with that friend", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const userId = "11111111-2222-4333-8444-555555555555";
    const profileId = "p_" + "a".repeat(32);
    activeAccount = { ...activeAccount, remote: "supabase", userId };
    loadRemoteSession = () => ({ user: { id: userId } });
    remoteAuthEnabled = () => true;
    persistWorkoutDraft = () => true;
    socialState.dashboard = { friends: [{ profileId, displayName: "Саша", friendshipId: "f1", friendshipRevision: 4 }] };
    liveWorkoutState.inbox = { invitations: [], rooms: [] };
    nav = [{ name: "workouts" }];
    modal = null;
    const pill = activationCard();
    const opened = openTodayFriendEntry();
    const picker = modalMarkup();
    const stale = startLiveWorkoutDraftForFriend(profileId, () => false);
    const picked = pickTodayFriend({ dataset: { profileId } });
    return JSON.stringify({
      pill: /today-friend-pill/.test(pill),
      opened,
      modalAfterOpen: picker.includes("Саша") && picker.includes('data-action="today-friend-pick"'),
      stale,
      picked,
      recipient: workoutDraftLiveRecipient,
      route: route().name,
      modal
    });
  })()`, context));

  assert.equal(result.pill, true);
  assert.equal(result.opened, true);
  assert.equal(result.modalAfterOpen, true);
  assert.equal(result.stale, false);
  assert.equal(result.picked, true);
  assert.deepEqual(result.recipient, { profileId: "p_" + "a".repeat(32), friendshipId: "f1", friendshipRevision: 4 });
  assert.equal(result.route, "add");
  assert.equal(result.modal, null);
});

test("a live room hides the friend pill", () => {
  const { context } = loadContext();
  const markup = vm.runInContext(`(() => {
    const userId = "11111111-2222-4333-8444-555555555555";
    activeAccount = { ...activeAccount, remote: "supabase", userId };
    loadRemoteSession = () => ({ user: { id: userId } });
    remoteAuthEnabled = () => true;
    liveWorkoutState.inbox = { invitations: [], rooms: [{ roomId: "r1", status: "active" }] };
    return activationCard();
  })()`, context);
  assert.doesNotMatch(markup, /today-friend-pill/);
});

test("metric values shrink to fit their tile instead of wrapping", () => {
  const { context, appNode } = loadContext();
  const values = [
    { clientWidth: 100, scrollWidth: 160, style: { fontSize: "" } },
    { clientWidth: 100, scrollWidth: 90, style: { fontSize: "" } },
    { clientWidth: 100, scrollWidth: 400, style: { fontSize: "" } }
  ];
  appNode.querySelectorAll = selector => selector === ".metric-grid strong" ? values : [];
  vm.runInContext("window", context).getComputedStyle = () => ({ fontSize: "22px" });
  vm.runInContext("fitMetricTileValues()", context);
  assert.equal(values[0].style.fontSize, "13.7px");
  assert.equal(values[1].style.fontSize, "");
  assert.equal(values[2].style.fontSize, "13.2px");
});

test("metric values refit when the window narrows without a new render", async () => {
  const { context, appNode } = loadContext();
  const value = { clientWidth: 200, scrollWidth: 150, style: { fontSize: "" } };
  appNode.querySelectorAll = selector => selector === ".metric-grid strong" ? [value] : [];
  const windowObject = vm.runInContext("window", context);
  windowObject.getComputedStyle = () => ({ fontSize: "22px" });
  let onResize = null;
  const observed = [];
  windowObject.ResizeObserver = class {
    constructor(callback) { onResize = callback; }
    observe(target) { observed.push(target); }
  };
  vm.runInContext("fitMetricTileValues(); fitMetricTileValues();", context);
  assert.equal(observed.length, 1);
  assert.equal(value.style.fontSize, "");

  value.clientWidth = 100;
  onResize();
  onResize();
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(value.style.fontSize, "14.6px");
});

test("training settings live in one sheet and other screens show a summary", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    render = () => {};
    state.profile = { split: "Push Pull Legs", days: 5, goal: "Strength", calories: "Maintenance" };
    state.language = "en";
    const en = trainingSettingsSummaryMarkup();
    state.language = "ru";
    const ru = trainingSettingsSummaryMarkup();
    state.language = "uk";
    const uk = trainingSettingsSummaryMarkup();
    state.language = "en";
    updateProfile({ dataset: { field: "goal", value: "Muscle Gain" } });
    updateProfile({ dataset: { field: "days", value: "3" } });
    updateProfile({ dataset: { field: "days", value: "9" } });
    const sheet = trainingSettingsSheetMarkup();
    return JSON.stringify({
      en, ru, uk, sheet,
      profile: state.profile,
      light: smartWorkoutEffortLabel("Recovery"),
      short: ["Recovery", "Standard", "Hard"].map(activationEffortLabel)
    });
  })()`, context));

  assert.match(result.en, /Strength · Maintenance · 5 workouts a week<\/span><strong>edit/);
  assert.match(result.ru, /5 тренировок в неделю<\/span><strong>изменить/);
  assert.match(result.uk, /5 тренувань на тиждень<\/span><strong>змінити/);
  assert.deepEqual(result.profile, { split: "Push Pull Legs", days: 3, goal: "Muscle Gain", calories: "Maintenance" });
  assert.match(result.sheet, /data-field="goal" data-value="Muscle Gain" aria-pressed="true"/);
  assert.match(result.sheet, /data-field="days" data-value="3" aria-pressed="true"/);
  assert.equal(result.light, "Light");
  assert.deepEqual(result.short, ["Light", "Normal", "Hard"]);
});

test("weight capsule steps follow allowed machine weights and fall back to the nominal 2.5 step", () => {
  const { context } = loadContext();
  const info = (weight, allowed) => JSON.parse(vm.runInContext(
    `JSON.stringify(activeWeightStepInfo(${weight}, ${JSON.stringify(allowed)}))`,
    context
  ));
  const free = info(0, []);
  assert.equal(free.nominal, 2.5);
  assert.deepEqual([free.minus.canMove, free.minus.delta], [false, 2.5]);
  assert.deepEqual([free.plus.canMove, free.plus.delta, free.plus.weight], [true, 2.5, 2.5]);
  const stack = info(10, [5, 7.5, 10, 20]);
  assert.equal(stack.nominal, 2.5);
  assert.deepEqual([stack.minus.weight, stack.minus.delta], [7.5, 2.5]);
  assert.deepEqual([stack.plus.weight, stack.plus.delta], [20, 10]);
  const top = info(20, [5, 7.5, 10, 20]);
  assert.deepEqual([top.plus.canMove, top.plus.delta], [false, 2.5]);
  const uneven = info(30, [10, 30, 40]);
  assert.equal(uneven.nominal, 10);
  assert.deepEqual([uneven.minus.delta, uneven.plus.delta], [20, 10]);
  assert.equal(vm.runInContext("activeStepReps('1', -1)", context), 1);
  assert.equal(vm.runInContext("activeStepReps('8', 1)", context), 9);
  assert.equal(vm.runInContext("activeStepReps('', 1)", context), 1);
});

test("capsule buttons write the draft inputs and keep the row without a re-render", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  const node = (field, value) => {
    const input = { value, dataset: { activeSetId: String(setId), activeField: field } };
    runtimeNodes.set(`[data-active-set-id="${setId}"][data-active-field="${field}"]`, input);
    return input;
  };
  const weight = node("weight", "80");
  const reps = node("reps", "8");
  assert.equal(vm.runInContext(`applyActiveStep(${setId}, "weight", 1)`, context), true);
  assert.equal(weight.value, "82.5");
  assert.equal(vm.runInContext(`applyActiveStep(${setId}, "reps", -1)`, context), true);
  assert.equal(reps.value, "7");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(activeWorkout.blocks[0].sets[0], "weight")`, context), "82.5");
  assert.equal(vm.runInContext(`activeLiveDraftInputValue(activeWorkout.blocks[0].sets[0], "reps")`, context), "7");
  reps.value = "1";
  assert.equal(vm.runInContext(`applyActiveStep(${setId}, "reps", -1)`, context), true);
  assert.equal(reps.value, "1");
  weight.value = "0";
  assert.equal(vm.runInContext(`applyActiveStep(${setId}, "weight", -1)`, context), false);
  assert.equal(weight.value, "0");
});

test("current set card renders the value line, capsules, Log label and previous rules", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(markup, /data-active-field="weight"[^>]*aria-label="Weight for set 1"/);
  assert.match(markup, /class="active-set-reps-input"[^>]*data-active-field="reps"|data-active-field="reps"[^>]*tabindex="-1"/);
  assert.match(markup, /role="group" data-step-field="weight" aria-label="Weight, 80 kg"/);
  assert.match(markup, /role="group" data-step-field="reps" aria-label="Reps, 8"/);
  assert.match(markup, /data-action="active-step-weight"[^>]*data-dir="-1"[^>]*aria-label="Decrease weight by 2.5"/);
  assert.match(markup, /data-action="active-step-reps"[^>]*data-dir="1"[^>]*aria-label="Increase reps"/);
  assert.match(markup, /<span class="active-set-log-label">Log<\/span><span class="active-set-log-rest"> · 3:00<\/span>/);
  assert.match(markup, /data-action="record-active-set" data-id="\d+" aria-label="Log · rest 3:00"/);
  assert.match(markup, /data-voice-phase="idle"/);
  assert.match(markup, /data-action="active-set-voice-start"/);
  assert.doesNotMatch(markup, /active-quick-entry/);
  assert.doesNotMatch(markup, /active-set-voice-listening/);

  const labels = JSON.parse(vm.runInContext(`JSON.stringify([activeSetLogLabels(0), activeSetLogLabels(75)])`, context));
  assert.deepEqual(labels[0], { log: "Log", rest: "", aria: "Log" });
  assert.deepEqual(labels[1], { log: "Log", rest: "1:15", aria: "Log · rest 1:15" });
  vm.runInContext(`state.language = "ru"`, context);
  assert.equal(vm.runInContext("activeSetLogLabels(180).aria", context), "Записать · отдых 3:00");
  vm.runInContext(`state.language = "uk"`, context);
  assert.equal(vm.runInContext("activeSetLogLabels(180).aria", context), "Записати · відпочинок 3:00");
});

test("previous caption hides a zero weight unless bodyweight and repeats without recording", () => {
  const { context } = loadContext();
  const caption = (previous, bodyweight) => JSON.parse(vm.runInContext(
    `JSON.stringify(activePreviousCaption({ previous: ${JSON.stringify(previous)}, repeat: ${JSON.stringify(previous)} }, ${bodyweight}))`,
    context
  ));
  assert.equal(caption({ weight: 60, reps: 8 }, false).text, "previous 60 × 8");
  assert.equal(caption({ weight: 60, reps: 8 }, false).aria, "Repeat previous, 60 kilograms by 8");
  assert.equal(caption({ weight: 0, reps: 8 }, false), null);
  assert.equal(caption({ weight: 0, reps: 8 }, true).text, "previous × 8");
  assert.equal(caption({ weight: 0, reps: 8 }, true).aria, "Repeat previous, 8 bodyweight reps");
  assert.equal(vm.runInContext("activePreviousCaption(null, false)", context), null);
  vm.runInContext(`state.language = "ru"`, context);
  assert.equal(caption({ weight: 60, reps: 8 }, false).text, "прошлый раз 60 × 8");
  vm.runInContext(`state.language = "uk"`, context);
  assert.equal(caption({ weight: 62.5, reps: 8 }, false).text, "минулого разу 62,5 × 8");
});

test("upcoming and completed rows are bare rows that keep their inputs in the DOM", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [firstSetId, secondSetId] = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks[0].sets.map(set => set.id))", context
  ));
  let markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(markup, new RegExp(`class="active-set-row upcoming"[^>]*><details class="active-set-details"[^>]*><summary[^>]*aria-label="Set 2, 82.5 kg × 6"`));
  assert.match(markup, new RegExp(`data-active-set-id="${secondSetId}" data-active-field="weight"[^>]*maxlength="64"[^>]*value="82.5"`));
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="weight"]`, { value: "80" });
  runtimeNodes.set(`[data-active-set-id="${firstSetId}"][data-active-field="reps"]`, { value: "8" });
  assert.equal(await vm.runInContext(`recordActiveSet(${firstSetId})`, context), true);
  markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(markup, /class="active-set-row completed"[^>]*aria-label="Set 1 recorded, 80 kg × 8"/);
  assert.match(markup, /<span class="active-set-summary-text">80 kg × 8<\/span>/);
  assert.match(markup, new RegExp(`data-active-set-id="${firstSetId}" data-active-field="weight"[^>]*disabled`));
});

test("voice phases: idle looks like requesting, listening swaps in transcript and stop, typed shows the field", async () => {
  const { context } = loadContext();
  await startTwoSetWorkout(context);
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[0].id", context);
  const control = () => vm.runInContext(`activeSetVoiceControlMarkup(${setId})`, context);
  const phase = () => vm.runInContext(`activeSetVoicePhase(${setId})`, context);

  const idle = control();
  assert.equal(phase(), "idle");
  vm.runInContext(`activeSetVoice = { generation: 1, setId: ${setId}, listening: false, transcript: "", recognition: null, stopTimer: null }`, context);
  assert.equal(phase(), "idle", "requesting does not change the UI");
  assert.equal(control(), idle);

  vm.runInContext(`activeSetVoice.listening = true; activeSetVoice.transcript = "80 <b>on</b> 8"`, context);
  assert.equal(phase(), "listening");
  const listening = control();
  assert.match(listening, /class="active-set-voice-interim">«80 &lt;b&gt;on&lt;\/b&gt; 8»</);
  assert.match(listening, /Say: &quot;80 by 8&quot;|Say: "80 by 8"/);
  assert.match(listening, /data-action="active-set-voice-stop"[^>]*aria-label="Stop voice command"/);
  assert.match(listening, /Listening…/);
  assert.match(listening, /data-action="active-set-voice-type"[^>]*>Type instead</);
  assert.doesNotMatch(listening, /record-active-set/);

  vm.runInContext(`activeSetVoice = null; activeSetVoiceManual = { setId: ${setId}, text: "" }`, context);
  assert.equal(phase(), "typed");
  let typed = control();
  assert.match(typed, /data-action="active-set-voice-cancel-manual"[^>]*aria-label="Cancel"/);
  assert.match(typed, /placeholder="80 by 8"[^>]*aria-label="Type a command"/);
  assert.match(typed, /data-action="active-set-voice-send"[^>]*aria-label="Send" disabled/);
  vm.runInContext(`activeSetVoiceManual.text = 'x" onfocus="1'`, context);
  typed = control();
  assert.match(typed, /value="x&quot; onfocus=&quot;1"/);
  assert.doesNotMatch(typed, /aria-label="Send" disabled/);
  vm.runInContext(`activeSetVoiceManual = null`, context);
});

// ---- R6 step C2: exercise footer, finish confirmation, "Skip them" ----

async function startFinishWorkout(context, blocks = null) {
  const plan = blocks || [
    { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }, { weight: 82.5, reps: 6 }, { weight: 85, reps: 5 }] },
    { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 100, reps: 5 }] }
  ];
  return vm.runInContext(`
    workoutDraft = { startedAt: Date.now(), note: "Finish flow", blocks: ${JSON.stringify(plan)} };
    startWorkout();
  `, context);
}

function blockSetIds(context, blockIndex = 0) {
  return JSON.parse(vm.runInContext(
    `JSON.stringify(activeWorkout.blocks[${blockIndex}].sets.map(set => set.id))`,
    context
  ));
}

function footerMarkup(markup, blockId) {
  const match = markup.match(new RegExp(`<div class="active-exercise-actions">(?:(?!</div>)[\\s\\S])*?data-block-id="${blockId}"[\\s\\S]*?</div>`));
  return match?.[0] ?? "";
}

test("the exercise footer is two equal columns: dashed + Set leads, solid Finish trails, in every language", async () => {
  const labels = {
    en: ["+ Set", "Add set", "Finish", "Save exercise"],
    uk: ["+ Підхід", "Додати підхід", "Завершити", "Зберегти вправу"],
    ru: ["+ Подход", "Добавить подход", "Завершить", "Сохранить упражнение"]
  };
  for (const [language, [add, addAria, finish, finishAria]] of Object.entries(labels)) {
    const { context } = loadContext();
    await startFinishWorkout(context);
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
    const footer = footerMarkup(vm.runInContext("activeWorkoutScreen()", context), blockId);
    assert.ok(footer, `footer markup (${language})`);
    assert.ok(footer.includes(`class="button active-exercise-add" type="button" data-action="add-active-set" data-block-id="${blockId}" aria-label="${addAria}">${add}</button>`));
    assert.ok(footer.includes(`class="button active-exercise-finish" type="button" data-action="save-active-exercise" data-block-id="${blockId}" aria-label="${finishAria}">${finish}</button>`));
    assert.ok(footer.indexOf("add-active-set") < footer.indexOf("save-active-exercise"));
    assert.doesNotMatch(footer, /<svg/);
  }
  const styles = await readFile("pwa/styles.css", "utf8");
  assert.match(styles, /\.active-exercise-actions\s*\{[^}]*grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\)/);
  assert.match(styles, /\.active-exercise-add\s*\{\s*border:\s*1px dashed color-mix\(in srgb, var\(--brand-fill\) 50%/);
  assert.match(styles, /\.active-exercise-finish\s*\{\s*border:\s*1px solid color-mix\(in srgb, var\(--brand-fill\) 70%/);
  assert.match(styles, /\.active-exercise-actions \.button\s*\{[^}]*min-height:\s*44px;[^}]*border-radius:\s*12px/);
  assert.doesNotMatch(styles, /\.timer-row\b|\.active-set-action\s*\{/, "dead rules are gone");
});

test("the footer is hidden in a live room and Finish plus Add set refuse there", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  const before = localStorage.getItem(activeStorageKey(context));
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /active-exercise-actions|save-active-exercise/);
  assert.equal(vm.runInContext(`beginFinishActiveExercise(${blockId}, null)`, context), false);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(await vm.runInContext(`skipRemainingActiveSets(${blockId})`, context), false);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);
});

test("the finish dialog title uses the right plural in English, Ukrainian and Russian", async () => {
  const titles = {
    en: { 1: "1 set left", 2: "2 sets left", 5: "5 sets left", 21: "21 sets left" },
    uk: { 1: "Залишилось 1 підхід", 2: "Залишилось 2 підходи", 5: "Залишилось 5 підходів", 21: "Залишилось 21 підхід" },
    ru: { 1: "Осталось 1 подход", 2: "Осталось 2 подхода", 5: "Осталось 5 подходов", 21: "Осталось 21 подход" }
  };
  const { context } = loadContext();
  for (const [language, byCount] of Object.entries(titles)) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    for (const [count, title] of Object.entries(byCount)) {
      assert.equal(vm.runInContext(`finishExerciseDialogTitle(${count})`, context), title);
    }
  }
});

test("Finish with unrecorded sets opens the confirmation with Log as planned, Skip them and Cancel and returns focus to Finish", async () => {
  const actions = {
    en: ["Log as planned", "Skip them", "Cancel", "3 sets left"],
    uk: ["Записати як у плані", "Пропустити їх", "Скасувати", "Залишилось 3 підходи"],
    ru: ["Записать как в плане", "Пропустить их", "Отмена", "Осталось 3 подхода"]
  };
  for (const [language, [log, skip, cancel, title]] of Object.entries(actions)) {
    const { context, localStorage } = loadContext();
    await startFinishWorkout(context);
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
    const before = localStorage.getItem(activeStorageKey(context));
    await vm.runInContext(`handleAction("save-active-exercise", { dataset: { action: "save-active-exercise", blockId: "${blockId}" } })`, context);
    assert.equal(vm.runInContext("modal.type", context), "finish-exercise");
    assert.equal(vm.runInContext("modal.blockId", context), blockId);
    assert.deepEqual(JSON.parse(vm.runInContext("JSON.stringify(modal.returnFocus)", context)), {
      action: "save-active-exercise",
      blockId: String(blockId)
    });
    assert.equal(localStorage.getItem(activeStorageKey(context)), before, "opening the dialog never mutates");
    const sheet = vm.runInContext("modalMarkup()", context);
    assert.match(sheet, /role="dialog"[^>]*aria-labelledby="finish-exercise-title"/);
    assert.ok(sheet.includes(`<h2 id="finish-exercise-title">${title}</h2>`));
    const buttons = [...sheet.matchAll(/data-action="(finish-exercise-log|finish-exercise-skip|close-modal)"[^>]*>([^<]*)</g)]
      .filter(match => match[1] !== "close-modal" || match[2] === cancel)
      .map(match => [match[1], match[2]]);
    assert.deepEqual(buttons, [
      ["finish-exercise-log", log],
      ["finish-exercise-skip", skip],
      ["close-modal", cancel]
    ]);
    vm.runInContext("closeModal()", context);
    assert.equal(vm.runInContext("modal", context), null);
    assert.equal(localStorage.getItem(activeStorageKey(context)), before, "Cancel leaves the workout untouched");
  }
});

test("the finish dialog hides Skip them in a live room and when the skip candidate is nil", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context, [
    { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }, { weight: 82.5, reps: 6 }] }
  ]);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  vm.runInContext(`modal = { type: "finish-exercise", blockId: ${blockId} }`, context);
  let sheet = vm.runInContext("modalMarkup()", context);
  assert.match(sheet, /finish-exercise-log/);
  assert.doesNotMatch(sheet, /finish-exercise-skip/, "the only exercise with nothing recorded cannot be skipped");
  assert.equal(vm.runInContext(`activeWorkoutSkipCandidate(activeWorkout, ${blockId})`, context), null);

  const multi = loadContext();
  await startFinishWorkout(multi.context);
  const multiBlockId = vm.runInContext("activeWorkout.blocks[0].id", multi.context);
  vm.runInContext(`modal = { type: "finish-exercise", blockId: ${multiBlockId} }`, multi.context);
  assert.match(vm.runInContext("modalMarkup()", multi.context), /finish-exercise-skip/);
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", multi.context);
  sheet = vm.runInContext("modalMarkup()", multi.context);
  assert.match(sheet, /finish-exercise-log/);
  assert.doesNotMatch(sheet, /finish-exercise-skip/, "live rooms cannot edit the shared plan");
});

test("skip candidate mirrors the shared rule for every block shape", async () => {
  const { context, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [firstId, secondId, thirdId] = blockSetIds(context, 0);
  const firstBlockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  const secondBlockId = vm.runInContext("activeWorkout.blocks[1].id", context);
  const candidate = id => JSON.parse(vm.runInContext(
    `JSON.stringify(activeWorkoutSkipCandidate(activeWorkout, ${id}))`,
    context
  ));
  const unchanged = JSON.parse(vm.runInContext("JSON.stringify(activeWorkout)", context));
  assert.deepEqual(candidate(secondBlockId).blocks.map(block => block.id), [firstBlockId],
    "nothing recorded and not the only exercise: the block is removed");
  assert.equal(candidate(99999999), null, "unknown block");
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 80, 8), true);
  const kept = candidate(firstBlockId).blocks[0];
  assert.deepEqual(kept.sets.map(set => set.id), [firstId], "some recorded: only recorded sets stay");
  assert.equal(kept.sets[0].completed, true);
  assert.deepEqual(JSON.parse(vm.runInContext("JSON.stringify(activeWorkout.blocks[1])", context)), unchanged.blocks[1]);
  for (const id of [secondId, thirdId]) {
    runtimeNodes.set(`[data-active-set-id="${id}"][data-active-field="reps"]`, { value: "5" });
  }
  assert.equal(await vm.runInContext(`saveActiveWorkoutExercise(${firstBlockId})`, context), true);
  assert.equal(candidate(firstBlockId), null, "nothing unrecorded: no candidate");
});

test("Skip them drops unrecorded sets, keeps recorded ones, bumps revision and retires stale sidecars", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [firstId, secondId] = blockSetIds(context, 0);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, firstId, 80, 8), true);
  const timerKey = vm.runInContext("exerciseRestTimerAccountDescriptor().storageKey", context);
  assert.notEqual(localStorage.getItem(timerKey), null);
  assert.equal(vm.runInContext(`rememberActiveLiveDraftInput({
    dataset: { activeSetId: ${JSON.stringify(String(secondId))}, activeField: "reps" },
    value: "06"
  })`, context), true);
  assert.notEqual(localStorage.getItem(activeInputDraftStorageKey(context)), null);
  const beforeRevision = vm.runInContext("activeWorkout.revision", context);
  const beforeUpdatedAt = vm.runInContext("activeWorkout.updatedAt", context);
  const recordedBefore = JSON.parse(vm.runInContext("JSON.stringify(activeWorkout.blocks[0].sets[0])", context));
  localStorage.writes.length = 0;

  vm.runInContext(`modal = { type: "finish-exercise", blockId: ${blockId}, returnFocus: null }`, context);
  assert.equal(await vm.runInContext(`handleAction("finish-exercise-skip", { dataset: {} })`, context), true);
  assert.equal(vm.runInContext("modal", context), null);

  const stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.equal(stored.revision, beforeRevision + 1);
  assert.ok(stored.updatedAt > beforeUpdatedAt);
  assert.deepEqual(stored.blocks[0].sets, [recordedBefore], "the recorded set is preserved exactly");
  assert.equal(stored.blocks.length, 2);
  assert.ok(
    localStorage.writes.indexOf(activeBulkCleanupStorageKey(context)) < localStorage.writes.indexOf(activeStorageKey(context)),
    "cleanup intent is durable before the structural revision"
  );
  assert.equal(localStorage.getItem(activeBulkCleanupStorageKey(context)), null);
  assert.equal(localStorage.getItem(activeUndoStorageKey(context)), null);
  assert.equal(localStorage.getItem(timerKey), null);
  const timing = JSON.parse(localStorage.getItem(activeTimingStorageKey(context)));
  assert.equal(timing.restingUntil, null);
  assert.equal(localStorage.getItem(activeInputDraftStorageKey(context)), null,
    "the draft of the removed set is reconciled away");
  assert.equal(vm.runInContext("activeWorkout.revision", context), beforeRevision + 1);
  assert.equal(vm.runInContext("activeWorkoutUi.messageKey", context), "exerciseSavedSkipped");
  assert.equal(vm.runInContext("activeWorkoutUi.status", context), "success");
  assert.equal(vm.runInContext(`activeCollapsedBlockIds(activeWorkout).has(${blockId})`, context), true);
});

test("Skip them removes the whole block when nothing in it is recorded", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context);
  const secondBlockId = vm.runInContext("activeWorkout.blocks[1].id", context);
  const firstBlockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  const beforeRevision = vm.runInContext("activeWorkout.revision", context);
  assert.equal(await vm.runInContext(`skipRemainingActiveSets(${secondBlockId})`, context), true);
  const stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.deepEqual(stored.blocks.map(block => block.id), [firstBlockId]);
  assert.equal(stored.revision, beforeRevision + 1);
});

test("Skip them refuses the nil cases and live rooms without writing", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context, [
    { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }] }
  ]);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  const before = localStorage.getItem(activeStorageKey(context));
  assert.equal(await vm.runInContext(`skipRemainingActiveSets(${blockId})`, context), false);
  assert.equal(vm.runInContext("activeWorkoutUi.messageKey", context), "skipUnavailable");
  assert.equal(vm.runInContext("activeWorkoutUi.status", context), "error");
  assert.equal(await vm.runInContext("skipRemainingActiveSets(424242)", context), false);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);

  const messages = {
    en: "Can't skip: nothing here can be safely left unrecorded.",
    uk: "Неможливо пропустити: тут нічого не можна безпечно залишити незаписаним.",
    ru: "Нельзя пропустить: здесь нечего безопасно оставить незаписанным."
  };
  for (const [language, message] of Object.entries(messages)) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    assert.equal(vm.runInContext("activeWorkoutStatusText()", context), message);
  }
  const skipped = {
    en: "Exercise saved. Remaining sets skipped.",
    uk: "Вправу збережено. Інші підходи пропущено.",
    ru: "Упражнение сохранено. Остальные подходы пропущены."
  };
  for (const [language, message] of Object.entries(skipped)) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}; activeWorkoutUi = activeWorkoutStatus("success", "exerciseSavedSkipped")`, context);
    assert.equal(vm.runInContext("activeWorkoutStatusText()", context), message);
  }
});

test("Log as planned saves the remaining sets through the existing path and collapses the card", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const ids = blockSetIds(context, 0);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  for (const id of ids) {
    runtimeNodes.set(`[data-active-set-id="${id}"][data-active-field="weight"]`, { value: "70" });
    runtimeNodes.set(`[data-active-set-id="${id}"][data-active-field="reps"]`, { value: "9" });
  }
  vm.runInContext(`modal = { type: "finish-exercise", blockId: ${blockId}, returnFocus: null }`, context);
  assert.equal(await vm.runInContext(`handleAction("finish-exercise-log", { dataset: {} })`, context), true);
  assert.equal(vm.runInContext("modal", context), null);
  const stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.deepEqual(stored.blocks[0].sets.map(set => [set.weight, set.reps, set.completed]), [[70, 9, true], [70, 9, true], [70, 9, true]]);
  assert.equal(vm.runInContext("activeWorkoutUi.messageKey", context), "exerciseSaved");
  assert.match(vm.runInContext("activeWorkoutScreen()", context),
    new RegExp(`<details data-active-block-details="${blockId}" >`), "the saved card renders collapsed");
});

test("Finish with every set recorded collapses the card immediately without dialog, toast or mutation", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startFinishWorkout(context, [
    { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }] },
    { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 100, reps: 5 }] }
  ]);
  const [setId] = blockSetIds(context, 0);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  vm.runInContext("activeWorkoutScreen()", context); // screen entry happened before the set was recorded
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, setId, 80, 8), true);
  vm.runInContext("globalThis.toasts = []; showToast = message => globalThis.toasts.push(message);", context);
  const before = localStorage.getItem(activeStorageKey(context));
  const expandedMarkup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(expandedMarkup, new RegExp(`<details data-active-block-details="${blockId}" open>`),
    "the latest completed exercise starts expanded");

  assert.equal(await vm.runInContext(`handleAction("save-active-exercise", { dataset: { action: "save-active-exercise", blockId: "${blockId}" } })`, context), true);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(vm.runInContext("globalThis.toasts.length", context), 0);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before, "no data mutation");
  assert.equal(vm.runInContext("activeWorkoutUi.messageKey", context), "exerciseSaved");
  const collapsedMarkup = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(collapsedMarkup, new RegExp(`<details data-active-block-details="${blockId}" >`));
  assert.match(collapsedMarkup, new RegExp(`data-action="save-active-exercise" data-block-id="${blockId}"`));

  vm.runInContext(`activeCollapsedBlockIds(activeWorkout).delete(${blockId})`, context);
  assert.match(vm.runInContext("activeWorkoutScreen()", context), new RegExp(`<details data-active-block-details="${blockId}" open>`),
    "opening the card again removes it from the collapsed set");
});

test("the collapsed-card memory is per workout and cleared when the workout leaves", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  vm.runInContext(`collapseActiveExerciseBlock(${blockId})`, context);
  assert.equal(vm.runInContext(`activeCollapsedBlockIds(activeWorkout).has(${blockId})`, context), true);
  vm.runInContext("activeCollapsedBlocks.workoutId = 'another-workout'", context);
  assert.equal(vm.runInContext(`activeCollapsedBlockIds(activeWorkout).size`, context), 0);
  vm.runInContext(`collapseActiveExerciseBlock(${blockId}); clearActiveWorkoutMemory();`, context);
  assert.equal(vm.runInContext("activeCollapsedBlocks.workoutId", context), null);
  assert.equal(vm.runInContext("activeCollapsedBlocks.ids.size", context), 0);
});

test("entering the active workout collapses every exercise except the current and undoable ones, like iOS", async () => {
  const { context, runtimeNodes } = loadContext();
  await startFinishWorkout(context, [
    { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }] },
    { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 100, reps: 5 }] }
  ]);
  const [setId] = blockSetIds(context, 0);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, setId, 80, 8), true);
  assert.equal(vm.runInContext("activeUndoableSetId()", context), setId);
  const collapsedTag = new RegExp(`<details data-active-block-details="${blockId}" >`);
  const openTag = new RegExp(`<details data-active-block-details="${blockId}" open>`);

  // Re-entering with the recorded set still undoable keeps its exercise open, the current one stays open too.
  vm.runInContext("lastScreenRouteName = 'workouts'; activeCollapsedBlocks.seeded = false;", context);
  const undoable = vm.runInContext("screenMarkup({ name: 'active' })", context);
  assert.match(undoable, openTag, "the exercise holding the undoable set stays open");
  assert.match(undoable, /active-workout-exercise current"><details data-active-block-details="\d+" open>/);

  // Once the set is no longer undoable, every screen entry collapses its fully recorded exercise.
  vm.runInContext("activeWorkoutUndoMarker = null; lastScreenRouteName = 'workouts';", context);
  assert.match(vm.runInContext("screenMarkup({ name: 'active' })", context), collapsedTag,
    "entering the route again re-collapses the fully recorded exercise");
  assert.match(vm.runInContext("activeWorkoutScreen()", context), collapsedTag);

  // A card the user opens stays open for the rest of the visit, but the next entry collapses it again.
  vm.runInContext(`activeCollapsedBlockIds(activeWorkout).delete(${blockId})`, context);
  assert.match(vm.runInContext("screenMarkup({ name: 'active' })", context), openTag,
    "user toggles are kept while the route stays active");
  vm.runInContext("lastScreenRouteName = 'workouts';", context);
  assert.match(vm.runInContext("screenMarkup({ name: 'active' })", context), collapsedTag);
});

test("the entry collapse set skips the current and undoable exercises and only lists fully recorded ones", () => {
  const { context } = loadContext();
  const ids = (workout, undoable) => JSON.parse(vm.runInContext(
    `JSON.stringify([...activeEntryCollapsedBlockIds(${JSON.stringify(workout)}, ${JSON.stringify(undoable)})])`,
    context
  ));
  const workout = {
    blocks: [
      { id: 1, sets: [{ id: 10, completed: true }] },
      { id: 2, sets: [{ id: 20, completed: true }] },
      { id: 3, sets: [{ id: 30, completed: true }, { id: 31, completed: false }] },
      { id: 4, sets: [{ id: 40, completed: false }] }
    ]
  };
  assert.deepEqual(ids(workout, null), [1, 2]);
  assert.deepEqual(ids(workout, 20), [1], "the exercise holding the undoable set stays open");
  assert.deepEqual(ids({ blocks: workout.blocks.slice(0, 2) }, null), [1, 2], "nothing left to do: all collapse");
});

test("the recorded-set banner announces once per confirmation", async () => {
  const { context, runtimeNodes } = loadContext();
  await startTwoSetWorkout(context);
  const [setId] = twoSetIds(context);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, setId, 40, 10), true);
  const live = markup => markup.match(/<span class="sr-only" role="status" aria-live="polite">([^<]*)<\/span>/)?.[1];
  assert.equal(live(vm.runInContext("activeWorkoutScreen()", context)), "Recorded: 40 kg × 10 · rest 3:00");
  assert.equal(live(vm.runInContext("activeWorkoutScreen()", context)), "", "an unrelated re-render stays silent");
  assert.equal(live(vm.runInContext("activeWorkoutScreen()", context)), "");
  const next = twoSetIds(context)[1];
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, next, 42.5, 8), true);
  assert.match(live(vm.runInContext("activeWorkoutScreen()", context)), /^Recorded: 42\.5 kg × 8/,
    "a new confirmation announces again");
});

test("logging a set carries its weight to the next unplanned set of the same exercise", async () => {
  const { context, runtimeNodes } = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "",
      blocks: [
        { exerciseName: "Bench Press", catalogKey: "bench_press",
          sets: [{ weight: 0, reps: 8 }, { weight: 0, reps: 8 }, { weight: 50, reps: 8 }, { weight: 0, reps: 8 }] },
        { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 0, reps: 5 }] }
      ]
    };
    startWorkout();
  `, context);
  const weights = () => JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks.map(block => block.sets.map(set => [set.weight, set.reps])))",
    context
  ));
  const ids = JSON.parse(vm.runInContext(
    "JSON.stringify(activeWorkout.blocks.map(block => block.sets.map(set => set.id)))",
    context
  ));
  assert.deepEqual(weights()[0].map(row => row[0]), [0, 0, 50, 0]);

  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, ids[0][0], 60, 6), true);
  assert.deepEqual(weights(), [[[60, 6], [60, 8], [50, 8], [0, 8]], [[0, 5]]],
    "only the next set is filled; reps and other exercises stay untouched");
  const persisted = JSON.parse(vm.runInContext(
    "localStorage.getItem(activeWorkoutAccountDescriptor().storageKey)", context
  ));
  assert.equal(persisted.blocks[0].sets[1].weight, 60, "the carried weight is persisted");

  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, ids[0][1], 62.5, 8), true);
  assert.deepEqual(weights()[0].map(row => row[0]), [60, 62.5, 50, 0],
    "a non-zero planned weight is not overwritten");

  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, ids[0][2], 0, 8), true);
  assert.deepEqual(weights()[0].map(row => row[0]), [60, 62.5, 0, 0], "a 0 kg log carries nothing");

  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, ids[1][0], 100, 5), true);
  assert.deepEqual(weights()[1], [[100, 5]], "the last set of an exercise has no next set to fill");
});

test("saved workout PR badge follows the running-best record rules", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    const session = (id, startedAt, rows) => ({
      id, startedAt, note: "", exerciseNames: ["Bench Press"],
      sets: rows.map(([weight, reps], index) => ({
        id: id * 100 + index, exerciseName: "Bench Press", catalogKey: "bench_press", weight, reps, orderIndex: index
      }))
    });
    const exercise = { name: "Bench Press", catalogKey: "bench_press" };
    const check = (current, history) => {
      state.sessions = [...history, session(50, 9000, current)];
      return isPr(state.sessions.at(-1), exercise);
    };
    return JSON.stringify({
      firstEverWorkout: check([[60, 8], [70, 8]], []),
      beatsHistory: check([[80, 8], [85, 5]], [session(1, 1000, [[80, 8]])]),
      matchesHistory: check([[80, 8], [80, 8]], [session(1, 1000, [[80, 8]])]),
      belowHistory: check([[60, 8]], [session(1, 1000, [[80, 8]])]),
      zeroKilograms: check([[0, 30]], [session(1, 1000, [[0, 8]])]),
      betterEstimateOnly: check([[75, 12]], [session(1, 1000, [[80, 5]])]),
      laterSessionIgnored: check([[85, 5]], [session(1, 1000, [[80, 5]]), session(99, 20000, [[200, 5]])])
    });
  })()`, context));
  assert.equal(result.firstEverWorkout, false, "an exercise's first session never shows a PR");
  assert.equal(result.beatsHistory, true);
  assert.equal(result.matchesHistory, false);
  assert.equal(result.belowHistory, false);
  assert.equal(result.zeroKilograms, false);
  assert.equal(result.betterEstimateOnly, true);
  assert.equal(result.laterSessionIgnored, true);
});

test("Progress defaults to the most logged exercise without writing it to state", () => {
  const { context } = loadContext();
  const result = JSON.parse(vm.runInContext(`(() => {
    state.exercises = [
      { id: 1, name: "Squat", catalogKey: "squat" },
      { id: 2, name: "Bench Press", catalogKey: "bench_press" },
      { id: 3, name: "Deadlift", catalogKey: "deadlift" }
    ];
    const session = (id, startedAt, name) => ({
      id, startedAt, note: "", exerciseNames: [name],
      sets: [{ id: id * 10, exerciseName: name, weight: 50, reps: 5, orderIndex: 0 }]
    });
    const out = {};
    state.sessions = [];
    delete state.progressExerciseId;
    out.noHistory = currentProgressExerciseId();
    out.noHistoryMost = mostLoggedExerciseId();
    state.sessions = [session(1, 1000, "Squat"), session(2, 2000, "Bench Press"), session(3, 3000, "Bench Press")];
    out.mostLogged = currentProgressExerciseId();
    state.sessions = [session(1, 1000, "Squat"), session(2, 2000, "Bench Press"),
      session(3, 3000, "Deadlift"), session(4, 4000, "Squat"), session(5, 5000, "Bench Press"),
      session(6, 6000, "Deadlift")];
    out.tieLatest = currentProgressExerciseId();
    state.progressExerciseId = 1;
    out.explicit = currentProgressExerciseId();
    state.progressExerciseId = 999;
    out.staleFallsBack = currentProgressExerciseId();
    delete state.progressExerciseId;
    currentProgressExerciseId();
    out.untouched = Object.hasOwn(state, "progressExerciseId") ? state.progressExerciseId : "unset";
    out.panelUsesDefault = exerciseProgressPanel().includes("Deadlift");
    return JSON.stringify(out);
  })()`, context));
  assert.equal(result.noHistory, 1, "no history falls back to the first exercise");
  assert.equal(result.noHistoryMost, null);
  assert.equal(result.mostLogged, 2);
  assert.equal(result.tieLatest, 3, "equal counts go to the most recently trained exercise");
  assert.equal(result.explicit, 1);
  assert.equal(result.staleFallsBack, 3);
  assert.equal(result.untouched, "unset");
  assert.equal(result.panelUsesDefault, true);
});

// ---- Log any pending set, delete a pending set, remove an exercise (cross-client parity) ----

function activeRunJson(context, code) {
  return JSON.parse(vm.runInContext(`JSON.stringify(${code})`, context));
}

function undoMarkerSetId(context) {
  return vm.runInContext("activeUndoableSetId(activeWorkout)", context);
}

test("every unrecorded set row in every exercise gets a compact Log button; the first one keeps the current emphasis", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  const bench = blockSetIds(context, 0);
  const squat = blockSetIds(context, 1);
  for (const [language, log, aria] of [
    ["en", "Log", n => `Log set ${n}`],
    ["uk", "Записати", n => `Записати підхід ${n}`],
    ["ru", "Записать", n => `Записать подход ${n}`]
  ]) {
    const markup = vm.runInContext(`state.language = ${JSON.stringify(language)}; activeWorkoutScreen()`, context);
    for (const id of [...bench, ...squat]) {
      assert.match(markup, new RegExp(`data-action="record-active-set" data-id="${id}"`), `${language}: set ${id} is loggable`);
    }
    assert.ok(markup.includes(`aria-label="${aria(2)}"`), `${language}: aria-label on a pending upcoming set`);
    assert.ok(markup.includes(`>${log}</button>`));
    // Only the first unrecorded set of the current exercise is the "current" card.
    assert.equal((markup.match(/active-set-row current/g) || []).length, 1);
    assert.match(markup, new RegExp(`active-set-row current" data-active-set-row="${bench[0]}"`));
  }
});

test("a later pending set can be logged first and the weight carries only within the same exercise", async () => {
  const { context, runtimeNodes } = loadContext();
  await startFinishWorkout(context, [
    { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [{ weight: 80, reps: 8 }, { weight: 0, reps: 8 }, { weight: 0, reps: 8 }] },
    { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 0, reps: 5 }] }
  ]);
  const [first, second, third] = blockSetIds(context, 0);
  const [squat] = blockSetIds(context, 1);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, second, 50, 7), true);
  const sets = activeRunJson(context, "activeWorkout.blocks.map(block => block.sets)");
  assert.equal(sets[0][0].completed, false, "set 1 stays unrecorded");
  assert.equal(sets[0][1].completed, true);
  assert.equal(sets[0][1].weight, 50);
  assert.equal(sets[0][2].weight, 50, "carry-over reaches the next empty set of the same exercise");
  assert.equal(sets[0][0].weight, 80);
  assert.equal(sets[1][0].weight, 0, "other exercises are untouched");
  assert.equal(undoMarkerSetId(context), second, "undo and confirmation behave like logging the current set");
  assert.ok(vm.runInContext(`timerRemaining(activeWorkout.id + ":Bench Press")`, context) > 0, "rest timer starts");
  void first; void third; void squat;
});

test("a pending set shows a visible trash icon, and still long-press and context menu, only where it is allowed", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  const bench = blockSetIds(context, 0);
  const squat = blockSetIds(context, 1);
  for (const language of ["en", "uk", "ru"]) {
    const markup = vm.runInContext(`state.language = ${JSON.stringify(language)}; activeWorkoutScreen()`, context);
    const label = { en: "Delete set", uk: "Видалити підхід", ru: "Удалить подход" }[language];
    for (const [index, id] of bench.entries()) {
      assert.match(markup, new RegExp(`<button class="set-delete-icon" type="button" data-action="delete-active-set" data-id="${id}" aria-label="${label} ${index + 1} ${{ en: "for", uk: "для", ru: "для" }[language]} [^"]+"><svg`), `${language}: trash icon for set ${index + 1}`);
      assert.match(markup, new RegExp(`data-active-set-deletable="${id}"`));
    }
    assert.doesNotMatch(markup, /active-set-delete-key/, "the hidden text key is replaced by the visible icon");
    // Upcoming sets use the shared editor: the values sit inside the capsules, which carry no center labels.
    const upcoming = markup.match(/<div class="active-set-editor">[\s\S]*?<\/div><\/details>/)?.[0] || "";
    assert.match(upcoming, /<div class="set-editor-capsules" data-active-steppers="\d+">/);
    assert.equal((upcoming.match(/class="set-editor-capsule"/g) || []).length, 2);
    assert.match(upcoming, /<span class="set-editor-value"><input class="set-editor-input" data-active-set-id="\d+" data-active-field="weight"/);
    assert.match(upcoming, /<span class="set-editor-value"><input class="set-editor-input" data-active-set-id="\d+" data-active-field="reps"/);
    assert.match(upcoming, /data-action="active-step-weight"/);
    assert.match(upcoming, /data-action="active-step-reps"/);
    assert.doesNotMatch(upcoming, /active-set-capsule-label/);
    assert.doesNotMatch(markup, new RegExp(`data-action="delete-active-set" data-id="${squat[0]}"`), "the only set of an exercise cannot be deleted");
    assert.doesNotMatch(markup, /open-active-set-delete|active-set-delete"/);
    assert.doesNotMatch(markup, new RegExp(`data-active-set-deletable="${squat[0]}"`));
  }
  vm.runInContext("state.language = 'en'", context);
  assert.equal(vm.runInContext(`openActiveSetDeleteMenu(${bench[1]})`, context), true);
  const sheet = vm.runInContext("modalMarkup()", context);
  assert.match(sheet, /role="dialog"/);
  assert.match(sheet, new RegExp(`data-action="delete-active-set" data-id="${bench[1]}">Delete set</button>`));
  assert.match(sheet, /Set 2 · /);
  vm.runInContext("modal = null", context);
  // Guard: a mutation in flight blocks the menu.
  vm.runInContext("activeSetMutationsInFlight = 1", context);
  assert.equal(vm.runInContext(`openActiveSetDeleteMenu(${bench[1]})`, context), false);
  vm.runInContext("activeSetMutationsInFlight = 0", context);
  assert.equal(vm.runInContext(`openActiveSetDeleteMenu(${squat[0]})`, context), false);
  // The gesture target resolves to delete for pending rows and undo for the recorded latest row.
  const target = { closest: selector => selector === "[data-active-set-deletable]" ? { dataset: { activeSetDeletable: String(bench[0]) } } : null };
  context.__target = target;
  assert.deepEqual(activeRunJson(context, "activeSetRowMenuTarget(globalThis.__target)"), { kind: "delete", setId: bench[0] });
});

test("long-pressing a pending row, summary included, opens Delete set and swallows the release click", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  const [first, second] = blockSetIds(context, 0);
  const rowFor = id => ({ dataset: { activeSetDeletable: String(id) } });
  const press = (id, inside = null) => ({
    isPrimary: true,
    button: 0,
    clientX: 5,
    clientY: 5,
    target: {
      closest: selector => selector === "[data-active-set-deletable]" ? rowFor(id)
        : selector.startsWith("button") ? inside : null
    }
  });
  context.__press = press(second);
  vm.runInContext("beginActiveSetLongPress(globalThis.__press)", context);
  await new Promise(resolve => setTimeout(resolve, 600));
  assert.equal(vm.runInContext("modal?.type", context), "active-set-delete");
  assert.equal(vm.runInContext("modal.setId", context), second);
  const calls = [];
  context.__click = { preventDefault: () => calls.push("prevent"), stopPropagation: () => calls.push("stop") };
  vm.runInContext("swallowActiveSetLongPressClick(globalThis.__click)", context);
  assert.deepEqual(calls, ["prevent", "stop"], "the click after the long-press is swallowed");
  vm.runInContext("swallowActiveSetLongPressClick(globalThis.__click)", context);
  assert.equal(calls.length, 2, "only that one click is swallowed");

  // A press on a real button (Log) never starts the gesture; a refused menu swallows nothing.
  vm.runInContext("modal = null", context);
  context.__press = press(first, {});
  vm.runInContext("beginActiveSetLongPress(globalThis.__press)", context);
  await new Promise(resolve => setTimeout(resolve, 600));
  assert.equal(vm.runInContext("modal", context), null);
  vm.runInContext("activeSetMutationsInFlight = 1", context);
  context.__press = press(first);
  vm.runInContext("beginActiveSetLongPress(globalThis.__press)", context);
  await new Promise(resolve => setTimeout(resolve, 600));
  vm.runInContext("activeSetMutationsInFlight = 0", context);
  assert.equal(vm.runInContext("modal", context), null);
  vm.runInContext("swallowActiveSetLongPressClick(globalThis.__click)", context);
  assert.equal(calls.length, 2, "a refused long-press does not eat the next click");
  assert.match(readFileSync("pwa/styles.css", "utf8"), /\.active-set-delete-key:focus-visible/);
});

test("deleting a pending set renumbers the exercise, bumps the revision, persists and keeps undo and rest", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [first, second, third] = blockSetIds(context, 0);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, first, 80, 8), true);
  const revisionBefore = vm.runInContext("activeWorkout.revision", context);
  const timerKey = vm.runInContext(`activeWorkout.id + ":Bench Press"`, context);
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(timerKey)})`, context) > 0);

  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${second})`, context), true);

  assert.deepEqual(blockSetIds(context, 0), [first, third], "later sets are renumbered by position");
  assert.equal(vm.runInContext("activeWorkout.revision", context), revisionBefore + 1);
  assert.equal(localStorage.getItem(activeStorageKey(context)), vm.runInContext("activeWorkoutStorageRaw", context));
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks[0].sets.length, 2);
  assert.equal(undoMarkerSetId(context), first, "the undo target survives deleting an unrecorded set");
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(timerKey)})`, context) > 0, "rest keeps running");
  const markup = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(markup, new RegExp(`data-id="${second}"`));
  assert.match(markup, new RegExp(`aria-label="Log set 2"|aria-label="Weight for set 2"`));
  assert.equal(vm.runInContext("typeof lastToast", context), "undefined", "success is silent");
  assert.equal(vm.runInContext("activeWorkoutStatusText()", context), "");
  // "N sets left" follows the new set count.
  assert.equal(vm.runInContext("activeWorkoutSetCounts(activeWorkout).total", context), 3);
  // Undo still works against the surviving marker.
  assert.equal(await vm.runInContext(`undoLatestActiveSet(${first})`, context), true);
});

test("delete set refuses recorded sets, the last set, a live room, a stale tab and an unknown id", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [first, second] = blockSetIds(context, 0);
  const [squat] = blockSetIds(context, 1);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, first, 80, 8), true);
  const before = localStorage.getItem(activeStorageKey(context));

  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${squat})`, context), false, "only set of the exercise");
  assert.equal(context.lastToast, "An exercise keeps at least one set. Remove the exercise instead.");
  assert.equal(await vm.runInContext("deleteActiveWorkoutSet(999)", context), false, "unknown id");
  assert.equal(await vm.runInContext("deleteActiveWorkoutSet('1')", context), false, "non-integer id");
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${second})`, context), false, "live room");
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /delete-active-set|data-active-set-deletable/);
  vm.runInContext("liveWorkoutBinding = null", context);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before, "refusals never write");

  // Stale: another tab rewrote the stored workout after this tab loaded it.
  const foreign = JSON.parse(before);
  foreign.revision += 1;
  foreign.updatedAt += 1;
  localStorage.setItem(activeStorageKey(context), JSON.stringify(foreign));
  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${second})`, context), false);
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks[0].sets.length, 3, "stale delete changes nothing");
});

test("a recorded set is deleted from the undo sheet after a destructive confirmation", async () => {
  const { context, localStorage, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [first, second, third] = blockSetIds(context, 0);
  const [squat] = blockSetIds(context, 1);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, first, 40, 10), true);
  assert.equal(undoMarkerSetId(context), first);
  const timerKey = vm.runInContext("activeWorkout.id + ':Bench Press'", context);
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(timerKey)})`, context) > 0, "rest timer runs");

  // Undo sheet offers a danger "Delete set" next to "Undo set".
  vm.runInContext("state.language = 'en'", context);
  assert.equal(vm.runInContext(`openActiveSetUndoMenu(${first})`, context), true);
  const undoSheet = vm.runInContext("modalMarkup()", context);
  assert.match(undoSheet, new RegExp(`<button class="button danger full" type="button" data-action="request-delete-active-set" data-id="${first}">Delete set</button>`));
  vm.runInContext("modal = null", context);

  // Confirmation names the exercise and the set; it opens as a destructive alertdialog.
  for (const [language, title, cancel, body] of [
    ["en", "Delete set?", "Cancel", "Set 1: 40 kg × 10"],
    ["uk", "Видалити підхід?", "Скасувати", "Підхід 1: 40 кг × 10"],
    ["ru", "Удалить подход?", "Отмена", "Подход 1: 40 кг × 10"]
  ]) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    assert.equal(vm.runInContext(`requestDeleteActiveSet(${first})`, context), true);
    assert.equal(vm.runInContext("modal.type", context), "confirm-delete-active-set");
    assert.equal(vm.runInContext("isDestructiveConfirmationModal()", context), true);
    const sheet = vm.runInContext("modalMarkup()", context);
    assert.match(sheet, /role="alertdialog"/);
    assert.ok(sheet.includes(`>${title}</h2>`), `${language} title`);
    assert.ok(sheet.includes(`>${cancel}</button>`), `${language} cancel`);
    assert.ok(sheet.includes(body), `${language} body: ${body}`);
    assert.match(sheet, /data-action="confirm-delete-active-set"/);
    vm.runInContext("modal = null", context);
  }
  vm.runInContext("state.language = 'en'", context);
  // Cancelling writes nothing.
  const before = localStorage.getItem(activeStorageKey(context));
  assert.equal(vm.runInContext(`requestDeleteActiveSet(${first})`, context), true);
  vm.runInContext("modal = null", context);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);

  // Confirming removes the undo target: undo marker cleared, rest timer stopped, others untouched.
  assert.equal(vm.runInContext(`requestDeleteActiveSet(${first})`, context), true);
  assert.equal(await vm.runInContext("confirmDeleteActiveSet()", context), true);
  const stored = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  assert.deepEqual(stored.blocks[0].sets.map(set => set.id), [second, third]);
  assert.equal(stored.revision, JSON.parse(before).revision + 1);
  assert.equal(undoMarkerSetId(context), null, "undo target deleted");
  assert.equal(vm.runInContext(`timerRemaining(${JSON.stringify(timerKey)})`, context), 0, "rest timer stopped");
  assert.equal(vm.runInContext("modal", context), null);

  // A recorded set that is not the undo target is deleted without touching the undo marker.
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, third, 50, 7), true);
  assert.equal(undoMarkerSetId(context), third);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, second, 45, 9), true);
  assert.equal(undoMarkerSetId(context), second);
  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${third})`, context), true);
  assert.equal(undoMarkerSetId(context), second, "undo stays on the other recorded set");

  // The last set of an exercise is refused with a toast, in the request and in the writer.
  context.lastToast = "";
  vm.runInContext("activeWorkout.blocks[1].sets[0].completed = true", context);
  assert.equal(vm.runInContext(`activeSetUndoSheetMarkup(${squat})`, context).includes("request-delete-active-set"), true);
  assert.equal(vm.runInContext(`requestDeleteActiveSet(${squat})`, context), false);
  assert.equal(context.lastToast, "An exercise keeps at least one set. Remove the exercise instead.");
  context.lastToast = "";
  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${squat})`, context), false);
  assert.equal(context.lastToast, "An exercise keeps at least one set. Remove the exercise instead.");
  for (const [language, text] of [
    ["uk", "У вправі має залишитися хоча б один підхід. Видаліть вправу."],
    ["ru", "В упражнении должен остаться хотя бы один подход. Удалите упражнение."]
  ]) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    assert.equal(vm.runInContext("activeLastSetToastText()", context), text);
  }
  vm.runInContext("state.language = 'en'", context);

  // A live room refuses both the request and the writer.
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.equal(vm.runInContext(`requestDeleteActiveSet(${second})`, context), false);
  assert.equal(await vm.runInContext(`deleteActiveWorkoutSet(${second})`, context), false);
  assert.doesNotMatch(vm.runInContext(`activeSetUndoSheetMarkup(${second})`, context), /request-delete-active-set/);
  vm.runInContext("liveWorkoutBinding = null", context);
});

test("Remove exercise is offered in the block header only when there are several exercises and no live room", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  const ids = activeRunJson(context, "activeWorkout.blocks.map(block => block.id)");
  for (const [language, name] of [["en", "Exercise options"], ["uk", "Дії з вправою"], ["ru", "Действия с упражнением"]]) {
    const markup = vm.runInContext(`state.language = ${JSON.stringify(language)}; activeWorkoutScreen()`, context);
    for (const [index, id] of ids.entries()) {
      assert.match(markup, new RegExp(`data-action="open-active-exercise-more" data-block-id="${id}" aria-haspopup="dialog" aria-label="${name}: [^"]+"`), `${language} block ${index}`);
    }
  }
  vm.runInContext("state.language = 'en'", context);
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /open-active-exercise-more/);
  assert.equal(vm.runInContext(`openActiveExerciseMoreMenu(${ids[0]})`, context), false);
  vm.runInContext("liveWorkoutBinding = null", context);

  const single = loadContext();
  await startTwoSetWorkout(single.context);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", single.context), /open-active-exercise-more/);
  assert.equal(vm.runInContext("requestRemoveActiveExercise(activeWorkout.blocks[0].id)", single.context), false);
});

test("Remove exercise confirmation names the exercise and counts recorded sets with locale plurals", async () => {
  const { context, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [bench] = [vm.runInContext("activeWorkout.blocks[0].id", context)];
  assert.equal(vm.runInContext(`openActiveExerciseMoreMenu(${bench})`, context), true);
  const more = vm.runInContext("modalMarkup()", context);
  assert.match(more, new RegExp(`data-action="remove-active-exercise" data-block-id="${bench}">Remove exercise</button>`));
  assert.match(more, /class="button danger full"/);
  assert.equal(vm.runInContext(`requestRemoveActiveExercise(${bench})`, context), true);
  assert.equal(vm.runInContext("modal.type", context), "confirm-remove-active-exercise");
  const planned = vm.runInContext("modalMarkup()", context);
  assert.match(planned, /role="alertdialog"/);
  assert.match(planned, />Remove exercise\?<\/h2>/);
  assert.match(planned, /<strong>Bench Press<\/strong>/);
  assert.match(planned, /Its planned sets will be removed from this workout\./);
  assert.match(planned, />Cancel<\/button>/);
  assert.match(planned, /data-action="confirm-remove-active-exercise">Remove<\/button>/);
  vm.runInContext("modal = null", context);

  const expected = {
    en: { 1: "1 recorded set will be removed.", 2: "2 recorded sets will be removed.", 5: "5 recorded sets will be removed." },
    uk: { 1: "1 записаний підхід буде видалено.", 2: "2 записані підходи буде видалено.", 5: "5 записаних підходів буде видалено.", 21: "21 записаний підхід буде видалено." },
    ru: { 1: "1 записанный подход будет удалён.", 2: "2 записанных подхода будут удалены.", 5: "5 записанных подходов будут удалены.", 22: "22 записанных подхода будут удалены." }
  };
  for (const [language, byCount] of Object.entries(expected)) {
    for (const [count, text] of Object.entries(byCount)) {
      assert.equal(
        vm.runInContext(`state.language = ${JSON.stringify(language)}; activeRemoveExerciseBodyText(${count})`, context),
        text
      );
    }
  }
  const titles = {
    uk: ["Видалити вправу?", "Її заплановані підходи буде видалено з цього тренування.", "Видалити", "Скасувати"],
    ru: ["Удалить упражнение?", "Его запланированные подходы будут удалены из этой тренировки.", "Удалить", "Отмена"]
  };
  for (const [language, [title, body, remove, cancel]] of Object.entries(titles)) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    vm.runInContext(`requestRemoveActiveExercise(${bench})`, context);
    const markup = vm.runInContext("modalMarkup()", context);
    assert.ok(markup.includes(`>${title}</h2>`) && markup.includes(body) && markup.includes(`>${remove}</button>`) && markup.includes(`>${cancel}</button>`), language);
    vm.runInContext("modal = null", context);
  }
  vm.runInContext("state.language = 'en'", context);
  void runtimeNodes;
});

test("removing an exercise keeps the undo target and rest of another exercise, and clears them when it owned them", async () => {
  // Case 1: the undo target lives in the kept exercise.
  const kept = loadContext();
  await startFinishWorkout(kept.context);
  const [benchId, squatId] = activeRunJson(kept.context, "activeWorkout.blocks.map(block => block.id)");
  const [squatSet] = blockSetIds(kept.context, 1);
  assert.equal(await recordTwoSetWorkoutSet(kept.context, kept.runtimeNodes, squatSet, 100, 5), true);
  const squatTimer = vm.runInContext(`activeWorkout.id + ":Squat"`, kept.context);
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(squatTimer)})`, kept.context) > 0);
  assert.equal(vm.runInContext(`requestRemoveActiveExercise(${benchId})`, kept.context), true);
  assert.equal(await vm.runInContext("confirmRemoveActiveExercise()", kept.context), true);
  assert.equal(vm.runInContext("modal", kept.context), null);
  assert.deepEqual(activeRunJson(kept.context, "activeWorkout.blocks.map(block => block.exerciseName)"), ["Squat"]);
  assert.equal(undoMarkerSetId(kept.context), squatSet, "undo survives removing another exercise");
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(squatTimer)})`, kept.context) > 0, "rest survives");
  assert.equal(kept.localStorage.getItem(activeStorageKey(kept.context)), vm.runInContext("activeWorkoutStorageRaw", kept.context));
  assert.equal(vm.runInContext("typeof lastToast", kept.context), "undefined", "success is silent");
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", kept.context), /open-active-exercise-more/, "last exercise cannot be removed");
  void squatId;

  // Case 2: the removed exercise owned the undo target and the running rest.
  const owned = loadContext();
  await startFinishWorkout(owned.context);
  const ownedBench = vm.runInContext("activeWorkout.blocks[0].id", owned.context);
  const [benchSet] = blockSetIds(owned.context, 0);
  assert.equal(await recordTwoSetWorkoutSet(owned.context, owned.runtimeNodes, benchSet, 80, 8), true);
  const benchTimer = vm.runInContext(`activeWorkout.id + ":Bench Press"`, owned.context);
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(benchTimer)})`, owned.context) > 0);
  assert.equal(await vm.runInContext(`removeActiveWorkoutExercise(${ownedBench})`, owned.context), true);
  assert.equal(undoMarkerSetId(owned.context), null, "undo target removed with its exercise");
  assert.equal(vm.runInContext(`timerRemaining(${JSON.stringify(benchTimer)})`, owned.context), 0, "its rest timer is stopped");
  assert.deepEqual(activeRunJson(owned.context, "activeWorkout.blocks.map(block => block.exerciseName)"), ["Squat"]);
  assert.equal(vm.runInContext("activeWorkoutSetCounts(activeWorkout).total", owned.context), 1, "set counts follow the removal");
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", owned.context), /undo-active-set/);
});

test("remove exercise refuses the last exercise, a live room, an unknown block and a stale confirmation", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context);
  const [benchId, squatId] = activeRunJson(context, "activeWorkout.blocks.map(block => block.id)");
  const before = localStorage.getItem(activeStorageKey(context));
  assert.equal(await vm.runInContext("removeActiveWorkoutExercise(999)", context), false, "unknown block");
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.equal(await vm.runInContext(`removeActiveWorkoutExercise(${benchId})`, context), false, "live room");
  assert.equal(vm.runInContext(`requestRemoveActiveExercise(${benchId})`, context), false);
  vm.runInContext("liveWorkoutBinding = null", context);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);

  // Stale confirmation: the workout changed after the dialog opened.
  assert.equal(vm.runInContext(`requestRemoveActiveExercise(${benchId})`, context), true);
  const foreign = JSON.parse(before);
  foreign.revision += 1;
  foreign.updatedAt += 1;
  localStorage.setItem(activeStorageKey(context), JSON.stringify(foreign));
  assert.equal(await vm.runInContext("confirmRemoveActiveExercise()", context), false);
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks.length, 2, "stale confirmation removes nothing");

  // Removing down to one exercise, then the last one is refused at the handler.
  const fresh = loadContext();
  await startFinishWorkout(fresh.context);
  const [a, b] = activeRunJson(fresh.context, "activeWorkout.blocks.map(block => block.id)");
  assert.equal(await vm.runInContext(`removeActiveWorkoutExercise(${a})`, fresh.context), true);
  assert.equal(await vm.runInContext(`removeActiveWorkoutExercise(${b})`, fresh.context), false);
  assert.equal(JSON.parse(fresh.localStorage.getItem(activeStorageKey(fresh.context))).blocks.length, 1);
  void squatId;
});

test("delete and remove markup escape untrusted exercise names and the action path is wired", async () => {
  const { context } = loadContext();
  await vm.runInContext(`
    workoutDraft = {
      startedAt: Date.now(),
      note: "n",
      blocks: [
        { exerciseName: "<img src=x onerror=alert(1)>", sets: [{ weight: 10, reps: 8 }, { weight: 10, reps: 8 }] },
        { exerciseName: "Squat", catalogKey: "squat", sets: [{ weight: 100, reps: 5 }] }
      ]
    };
    startWorkout();
  `, context);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  const screen = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(screen, /<img\b[^>]*\bonerror\s*=/i);
  assert.match(screen, /aria-label="Exercise options: &lt;img src=x onerror=alert\(1\)&gt;"/);
  vm.runInContext(`openActiveExerciseMoreMenu(${blockId})`, context);
  assert.doesNotMatch(vm.runInContext("modalMarkup()", context), /<img\b[^>]*\bonerror\s*=/i);
  vm.runInContext("modal = null", context);
  vm.runInContext(`requestRemoveActiveExercise(${blockId})`, context);
  const confirmation = vm.runInContext("modalMarkup()", context);
  assert.doesNotMatch(confirmation, /<img\b[^>]*\bonerror\s*=/i);
  assert.match(confirmation, /&lt;img src=x onerror=alert\(1\)&gt;/);
  vm.runInContext("modal = null", context);
  // Draft values typed into a pending set are untrusted too.
  const setId = vm.runInContext("activeWorkout.blocks[0].sets[1].id", context);
  vm.runInContext(`activeLiveDraftInputs = { roomId: activeWorkoutInputScope(activeWorkout), localWorkoutId: activeWorkout.id, values: new Map([[${setId}, { weight: '<b>9</b>', reps: '"><i>' }]]) }`, context);
  vm.runInContext(`openActiveSetDeleteMenu(${setId})`, context);
  const sheet = vm.runInContext("modalMarkup()", context);
  assert.doesNotMatch(sheet, /<b>9<\/b>|<i>/);

  // The click router reaches the handlers and the destructive modal registry covers the confirmation.
  assert.equal(vm.runInContext("isDestructiveConfirmationModal({ type: 'confirm-remove-active-exercise' })", context), true);
  vm.runInContext("modal = null", context);
  assert.equal(await vm.runInContext(`handleAction("delete-active-set", { dataset: { id: "${setId}" } })`, context), true);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets.length", context), 1);
});

function seedPriorSession(context, { id = 9001, startedOffset = -86400000, sets }) {
  vm.runInContext(`state.sessions.push({
    id: ${id},
    startedAt: activeWorkout.startedAt + (${startedOffset}),
    sets: ${JSON.stringify(sets)}
  })`, context);
}

test("+ Add exercise button follows the live lock, uses the dashed style, and localizes", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  const screen = vm.runInContext("activeWorkoutScreen()", context);
  assert.match(screen, /class="button full saved-workout-add-exercise active-workout-add-exercise"[^>]*data-action="open-workout-exercise-picker" data-picker-target="active-add">\+ Add exercise<\/button>/);
  assert.ok(screen.indexOf("active-workout-add-exercise") > screen.indexOf("active-workout-list"));
  assert.ok(screen.indexOf("active-workout-add-exercise") < screen.indexOf("active-workout-finish"));
  for (const [language, label] of [["uk", "+ Додати вправу"], ["ru", "+ Добавить упражнение"]]) {
    vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
    assert.ok(vm.runInContext("activeWorkoutScreen()", context).includes(`>${label}</button>`), language);
  }
  vm.runInContext("state.language = 'en'", context);
  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.doesNotMatch(vm.runInContext("activeWorkoutScreen()", context), /active-workout-add-exercise|data-picker-target="active-add"/);
  assert.equal(vm.runInContext("openWorkoutExercisePicker('active-add')", context), false, "live room refuses the picker");
  vm.runInContext("liveWorkoutBinding = null", context);
  assert.equal(vm.runInContext("openWorkoutExercisePicker('active-add')", context), true);
  assert.equal(vm.runInContext("modal.target", context), "active-add");
});

test("the active-add picker excludes exercises already in the workout and selecting one appends it", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  assert.equal(vm.runInContext("openWorkoutExercisePicker('active-add')", context), true);
  const names = activeRunJson(context, "workoutExercisePickerRows().map(exercise => exercise.name)");
  assert.ok(names.length > 0);
  assert.ok(!names.includes("Bench Press") && !names.includes("Squat"), "workout exercises are excluded");
  const deadlift = vm.runInContext("state.exercises.find(exercise => exercise.name === 'Deadlift')", context);
  assert.ok(deadlift, "catalog has Deadlift");
  assert.equal(await vm.runInContext(`selectWorkoutExercise(${Number(deadlift.id)})`, context), true);
  assert.equal(vm.runInContext("modal", context), null);
  assert.deepEqual(activeRunJson(context, "activeWorkout.blocks.map(block => block.exerciseName)"), ["Bench Press", "Squat", "Deadlift"]);
});

test("adding an exercise appends 3 pending sets prefilled from the last earlier logged set, else 20 kg x 10", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context);
  seedPriorSession(context, { id: 9001, startedOffset: -172800000, sets: [{ id: 91001, exerciseName: "Deadlift", catalogKey: "deadlift", weight: 100, reps: 5 }] });
  seedPriorSession(context, { id: 9002, startedOffset: -86400000, sets: [{ id: 91002, exerciseName: "Deadlift", catalogKey: "deadlift", weight: 120, reps: 4 }] });
  seedPriorSession(context, { id: 9003, startedOffset: 86400000, sets: [{ id: 91003, exerciseName: "Deadlift", catalogKey: "deadlift", weight: 999, reps: 1 }] });
  const revision = vm.runInContext("activeWorkout.revision", context);
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Deadlift', 'deadlift')", context), true);
  const block = activeRunJson(context, "activeWorkout.blocks[2]");
  assert.equal(block.exerciseName, "Deadlift");
  assert.equal(block.catalogKey, "deadlift");
  assert.equal(block.sets.length, 3);
  assert.ok(block.sets.every(set => set.weight === 120 && set.reps === 4 && set.completed === false && set.completedAt === null));
  assert.equal(new Set(block.sets.map(set => set.id)).size, 3);
  assert.equal(vm.runInContext("activeWorkout.revision", context), revision + 1);
  assert.equal(localStorage.getItem(activeStorageKey(context)), vm.runInContext("activeWorkoutStorageRaw", context));
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks.length, 3);

  // No earlier history: fallback 20 kg x 10.
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Custom Sled Push', null)", context), true);
  const fallback = activeRunJson(context, "activeWorkout.blocks[3]");
  assert.ok(fallback.sets.every(set => set.weight === 20 && set.reps === 10));
});

test("adding an exercise refuses duplicates, the exercise limit and live rooms without writing", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context);
  const before = localStorage.getItem(activeStorageKey(context));
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Bench Press', 'bench_press')", context), false);
  assert.equal(context.lastToast, "This exercise is already in the workout.");
  vm.runInContext("state.language = 'uk'", context);
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Squat', 'squat')", context), false);
  assert.equal(context.lastToast, "Ця вправа вже є в тренуванні.");
  vm.runInContext("state.language = 'ru'", context);
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Squat', 'squat')", context), false);
  assert.equal(context.lastToast, "Это упражнение уже есть в тренировке.");
  vm.runInContext("state.language = 'en'", context);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);

  vm.runInContext("liveWorkoutBinding = { localWorkoutId: activeWorkout.id }", context);
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Deadlift', 'deadlift')", context), false);
  vm.runInContext("liveWorkoutBinding = null", context);
  assert.equal(localStorage.getItem(activeStorageKey(context)), before);

  const limit = vm.runInContext("window.GymStateContract.LIMITS.exercisesPerSession", context);
  const crowded = loadContext();
  await startFinishWorkout(crowded.context, Array.from({ length: limit }, (_, index) => ({
    exerciseName: `Custom ${index}`,
    sets: [{ weight: 10, reps: 5 }]
  })));
  const crowdedBefore = crowded.localStorage.getItem(activeStorageKey(crowded.context));
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Deadlift', 'deadlift')", crowded.context), false);
  assert.equal(crowded.context.lastToast, "This workout has reached the exercise limit.");
  assert.equal(crowded.localStorage.getItem(activeStorageKey(crowded.context)), crowdedBefore);
});

test("adding an exercise refuses a stale tab and changes nothing", async () => {
  const { context, localStorage } = loadContext();
  await startFinishWorkout(context);
  const before = JSON.parse(localStorage.getItem(activeStorageKey(context)));
  const foreign = { ...before, revision: before.revision + 1, updatedAt: before.updatedAt + 1 };
  localStorage.setItem(activeStorageKey(context), JSON.stringify(foreign));
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Deadlift', 'deadlift')", context), false);
  assert.equal(JSON.parse(localStorage.getItem(activeStorageKey(context))).blocks.length, 2);
});

test("adding an exercise keeps the undo target and the running rest timer", async () => {
  const { context, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [benchSet] = blockSetIds(context, 0);
  assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, benchSet, 80, 8), true);
  const timerKey = vm.runInContext(`activeWorkout.id + ":Bench Press"`, context);
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(timerKey)})`, context) > 0);
  assert.equal(undoMarkerSetId(context), benchSet);
  assert.equal(await vm.runInContext("addActiveWorkoutExercise('Deadlift', 'deadlift')", context), true);
  assert.equal(undoMarkerSetId(context), benchSet, "undo marker re-persisted at the new revision for the same set");
  assert.ok(vm.runInContext(`timerRemaining(${JSON.stringify(timerKey)})`, context) > 0, "rest timer survives");
  assert.equal(activeRunJson(context, "activeWorkout.blocks[0].sets[0].completed"), true);
  assert.match(vm.runInContext("activeWorkoutScreen()", context), /undo-active-set/);
});

test("added exercise names are escaped in the active screen", async () => {
  const { context } = loadContext();
  await startFinishWorkout(context);
  assert.equal(await vm.runInContext(`addActiveWorkoutExercise(${JSON.stringify("<img src=x onerror=alert(1)>")}, null)`, context), true);
  const screen = vm.runInContext("activeWorkoutScreen()", context);
  assert.doesNotMatch(screen, /<img\b[^>]*\bonerror\s*=/i);
  assert.match(screen, /&lt;img src=x onerror=alert\(1\)&gt;/);
});

test("+ Set stays available on an expanded fully completed block", async () => {
  const { context, runtimeNodes } = loadContext();
  await startFinishWorkout(context);
  const [benchA, benchB, benchC] = blockSetIds(context, 0);
  for (const [id, weight, reps] of [[benchA, 80, 8], [benchB, 82.5, 6], [benchC, 85, 5]]) {
    assert.equal(await recordTwoSetWorkoutSet(context, runtimeNodes, id, weight, reps), true);
  }
  const screen = vm.runInContext("activeWorkoutScreen()", context);
  const completedBlock = screen.split('<section class="panel highlighted active-workout-exercise ').find(part => part.startsWith("completed"));
  assert.ok(completedBlock, "first block is fully completed");
  assert.match(completedBlock, /<details data-active-block-details="[^"]+" open>/, "latest completed block stays expanded");
  assert.match(completedBlock, /data-action="add-active-set"/);
  const blockId = vm.runInContext("activeWorkout.blocks[0].id", context);
  assert.equal(await vm.runInContext(`addActiveWorkoutSet(${blockId})`, context), true);
  assert.equal(vm.runInContext("activeWorkout.blocks[0].sets.length", context), 4);
});
