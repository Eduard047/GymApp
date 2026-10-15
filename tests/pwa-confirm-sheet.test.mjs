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
  const windowListeners = new Map();
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
      addEventListener(type, listener) { windowListeners.set(type, listener); },
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
  context.windowListeners = windowListeners;
  return context;
}

const settled = promise => {
  const box = { done: false, value: undefined };
  promise.then(value => { box.done = true; box.value = value; });
  return box;
};
const flush = () => new Promise(resolve => setImmediate(resolve));

function openConfirm(context, options = {}) {
  context.__options = { title: "T", body: "B", confirmLabel: "Go", cancelLabel: "No", destructive: true, ...options };
  const box = settled(vm.runInContext("confirmSheet(__options)", context));
  return box;
}

test("confirmSheet resolves true only from the confirm button and restores the underlying sheet", async () => {
  const context = loadContext();
  vm.runInContext(`modal = { type: "history", exercise: null };`, context);
  const box = openConfirm(context);
  await flush();
  assert.equal(box.done, false);
  assert.equal(vm.runInContext("modal.type", context), "confirm-sheet");
  assert.equal(vm.runInContext("modal.returnModal.type", context), "history");
  await vm.runInContext(`handleAction("confirm-sheet-accept", {})`, context);
  await flush();
  assert.deepEqual(box, { done: true, value: true });
  assert.equal(vm.runInContext("modal.type", context), "history");
  assert.equal(vm.runInContext("confirmSheetPending", context), null);
});

const falseTeardowns = {
  "cancel button": `handleAction("cancel-destructive", {})`,
  "Esc / scrim tap / drag dismissal (dismissSheet)": `dismissSheet()`,
  "closeModal": `closeModal()`,
  "external update dismissal": `dismissModalAfterExternalUpdate()`,
  "another modal replacing it": `modal = { type: "history", exercise: null }; render();`,
  "sign-out": `activeAccount = null; modal = null; render();`,
  "account/profile switch": `activeAccount = { ...activeAccount, id: "local-v2-22222222222222222222222222222222" }; render();`,
  "popstate-style modal clear": `modal = null; render();`
};

for (const [name, script] of Object.entries(falseTeardowns)) {
  test(`confirmSheet resolves false on ${name}`, async () => {
    const context = loadContext();
    const box = openConfirm(context);
    await flush();
    assert.equal(box.done, false);
    vm.runInContext(script, context);
    await flush();
    assert.deepEqual(box, { done: true, value: false });
    assert.equal(vm.runInContext("confirmSheetPending", context), null);
    assert.notEqual(vm.runInContext("modal?.type", context), "confirm-sheet");
  });
}

test("a second confirmSheet resolves the first with false and only the second can confirm", async () => {
  const context = loadContext();
  const first = openConfirm(context, { title: "First" });
  const second = openConfirm(context, { title: "Second" });
  await flush();
  assert.deepEqual(first, { done: true, value: false });
  assert.equal(second.done, false);
  assert.equal(vm.runInContext("modal.title", context), "Second");
  await vm.runInContext(`handleAction("confirm-sheet-accept", {})`, context);
  await flush();
  assert.deepEqual(second, { done: true, value: true });
});

test("drag-dismiss decision maps to the same false outcome as cancel", async () => {
  const context = loadContext();
  assert.equal(vm.runInContext(`sheetDismissDecision({ distance: 10, height: 300, velocity: 0.9 })`, context), "dismiss");
  const box = openConfirm(context);
  await flush();
  vm.runInContext(`dismissSheet()`, context);
  await flush();
  assert.deepEqual(box, { done: true, value: false });
});

test("confirm sheet markup is an escaped alertdialog with no inline styles", () => {
  const context = loadContext();
  context.__sheet = { title: `<b>"x"</b>`, body: `<img src=x onerror=1>`, confirmLabel: "<i>Go</i>", cancelLabel: "No", destructive: true };
  const markup = vm.runInContext("confirmSheetMarkup(__sheet)", context);
  assert.match(markup, /role="alertdialog"/);
  assert.match(markup, /aria-describedby="confirm-sheet-description"/);
  assert.match(markup, /data-action="cancel-destructive" data-modal-initial-focus/);
  assert.match(markup, /class="button danger full" data-action="confirm-sheet-accept"/);
  assert.doesNotMatch(markup, /<img|<b>|<i>|\sstyle=/);
});

test("app.js has no native confirm dialog and every former call site awaits confirmSheet", () => {
  assert.doesNotMatch(appSource, /window\.confirm/);
  assert.doesNotMatch(appSource, /\bconfirm\(/);
  assert.ok((appSource.match(/await confirmSheet\(/g) || []).length >= 15);
  assert.match(appSource, /sheet-open/);
});
