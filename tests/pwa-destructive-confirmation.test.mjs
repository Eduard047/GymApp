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
  assert.match(appSource, /inertModalBackground\(modalElement\)/);
  assert.match(appSource, /element\.inert = true/);
  assert.match(appSource, /focusStableScreenContext\(\)/);
  assert.match(appSource, /formatLocalizedSetWeight\(location\.set\.weight\)/);
  assert.doesNotMatch(appSource, /Number\(location\.set\.weight\)\.toFixed\(1\) kg/);
  const labelledDeleteSets = appSource.match(
    /data-action="delete-set"[^>]+data-session="[^>]+aria-label="\$\{txAttr\("Delete set"/g
  ) || [];
  assert.equal(labelledDeleteSets.length, 1, "saved-set deletion must exist only in detail edit mode");
});

test("Today can confirm cancelling its retained plan without deleting workout history", () => {
  const context = loadContext();
  vm.runInContext(`
    state.sessions = [{
      id: 41,
      startedAt: Date.UTC(2026, 7, 26, 12),
      blocks: [{ exerciseName: "Bench Press", sets: [{ weight: 50, reps: 10 }] }]
    }];
    saveState({ queueRemote: false, markDirty: false });
    workoutDraft = createDraft();
    workoutDraft.blocks = [{ exerciseName: "Squat", sets: [{ weight: "", reps: "8" }] }];
    persistWorkoutDraft();
    nav = [{ name: "workouts" }];
    render = () => true;
  `, context);

  assert.equal(vm.runInContext(`requestDiscardWorkoutDraft({ action: "cancel-retained-plan" }, "today")`, context), true);
  assert.equal(vm.runInContext("modal.type", context), "confirm-discard-plan");
  assert.equal(vm.runInContext("modal.intent.routeName", context), "workouts");
  assert.equal(vm.runInContext("confirmDiscardWorkoutDraft()", context), true);
  assert.equal(vm.runInContext("workoutDraft", context), null);
  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].id", context), 41);
});

test("saved-plan cancellation stays bound to the route that requested it", () => {
  const context = loadContext();
  vm.runInContext(`
    workoutDraft = createDraft();
    workoutDraft.blocks = [{ exerciseName: "Squat", sets: [{ weight: "", reps: "8" }] }];
    persistWorkoutDraft();
    nav = [{ name: "workouts" }];
    render = () => true;
    requestDiscardWorkoutDraft({ action: "cancel-retained-plan" }, "today");
    nav = [{ name: "workouts" }, { name: "add" }];
  `, context);

  assert.equal(vm.runInContext("confirmDiscardWorkoutDraft()", context), false);
  assert.notEqual(vm.runInContext("workoutDraft", context), null);
});

test("ordinary dialogs focus an internal control, close on Escape, and restore their invoker", () => {
  const context = loadContext();
  let restoredFocus = false;
  const screenBackground = { inert: false };
  const header = { inert: false };
  const navigation = { inert: false };
  const invoker = {
    dataset: { action: "open-exercise-more", id: "7001" },
    focus() {
      restoredFocus = true;
      context.document.activeElement = this;
    }
  };
  const focusTarget = {
    focus() { context.document.activeElement = this; }
  };
  const listeners = new Map();
  const modalElement = {
    inert: false,
    addEventListener(type, listener) { listeners.set(type, listener); },
    contains(element) { return element === focusTarget; },
    focus() { context.document.activeElement = this; },
    getAttribute() { return null; },
    hasAttribute() { return false; },
    querySelector() { return focusTarget; },
    querySelectorAll() { return [focusTarget]; },
    setAttribute() {}
  };
  const screen = { children: [screenBackground, modalElement] };
  const shell = { children: [header, screen, navigation] };
  modalElement.parentElement = screen;
  screenBackground.parentElement = screen;
  screen.parentElement = shell;
  header.parentElement = shell;
  navigation.parentElement = shell;
  shell.parentElement = context.appNode;
  context.appNode.children = [shell];
  context.runtimeNodes.set(".modal", modalElement);
  context.runtimeLists.set('[data-action="open-exercise-more"]', [invoker]);
  vm.runInContext(`
    render = () => true;
    modal = {
      type: "template",
      returnFocus: { action: "open-exercise-more", id: 7001 }
    };
    bindEvents();
  `, context);

  assert.equal(screenBackground.inert, true);
  assert.equal(header.inert, true);
  assert.equal(navigation.inert, true);
  assert.notEqual(modalElement.inert, true);
  assert.notEqual(screen.inert, true);
  assert.notEqual(shell.inert, true);
  assert.equal(context.document.activeElement, focusTarget);
  const escapeEvent = {
    key: "Escape",
    prevented: false,
    preventDefault() { this.prevented = true; }
  };
  listeners.get("keydown")(escapeEvent);
  assert.equal(escapeEvent.prevented, true);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(restoredFocus, true);
});

test("user-opened generic sheets capture and restore their rendered trigger", async () => {
  const context = loadContext();
  let restoredFocus = false;
  const listeners = new Map();
  const trigger = {
    dataset: { action: "change-password" },
    addEventListener(type, listener) { listeners.set(type, listener); },
    focus() { restoredFocus = true; }
  };
  context.runtimeLists.set("[data-action]", [trigger]);
  context.runtimeLists.set('[data-action="change-password"]', [trigger]);
  vm.runInContext("render = () => true; bindEvents();", context);

  await listeners.get("click")({ stopPropagation() {} });

  assert.equal(vm.runInContext("modal.type", context), "change-password");
  assert.equal(vm.runInContext("modal.returnFocus.action", context), "change-password");
  vm.runInContext("closeModal()", context);
  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(restoredFocus, true);
});

test("real app shells reuse one delegated click listener across root renders", async () => {
  const context = loadContext();
  let rootClickListener = null;
  let rootClickBindings = 0;
  let directClickBindings = 0;
  const trigger = {
    dataset: { action: "change-password" },
    closest(selector) { return selector === "[data-action]" ? this : null; },
    addEventListener(type) {
      if (type === "click") directClickBindings += 1;
    }
  };
  context.appNode.addEventListener = (type, listener) => {
    if (type === "click") {
      rootClickBindings += 1;
      rootClickListener = listener;
    }
  };
  context.runtimeLists.set("[data-action]", [trigger]);
  vm.runInContext("render = () => true; bindEvents(); bindEvents();", context);

  assert.equal(rootClickBindings, 1);
  assert.equal(directClickBindings, 0);
  rootClickListener({ target: trigger, stopPropagation() {} });
  await Promise.resolve();
  assert.equal(vm.runInContext("modal.type", context), "change-password");
});

test("async sheets bind return focus before their network work resolves", async () => {
  const context = loadContext();
  let restoredFocus = false;
  let resolveNetwork;
  const listeners = new Map();
  const trigger = {
    dataset: {
      action: "open-friend",
      profileId: "p_11111111111111111111111111111111"
    },
    addEventListener(type, listener) { listeners.set(type, listener); },
    focus() { restoredFocus = true; }
  };
  context.runtimeLists.set("[data-action]", [trigger]);
  context.runtimeLists.set('[data-action="open-friend"]', [trigger]);
  context.pendingNetwork = new Promise(resolve => { resolveNetwork = resolve; });
  vm.runInContext(`
    render = () => true;
    handleAction = async () => {
      modal = {
        type: "friend-detail",
        profileId: "p_11111111111111111111111111111111"
      };
      render();
      await pendingNetwork;
      return true;
    };
    bindEvents();
  `, context);

  const click = listeners.get("click")({ stopPropagation() {} });
  assert.equal(vm.runInContext("modal.returnFocus.action", context), "open-friend");
  assert.equal(
    vm.runInContext("modal.returnFocus.profileId", context),
    "p_11111111111111111111111111111111"
  );
  vm.runInContext("closeModal()", context);
  assert.equal(restoredFocus, true, "the trigger is restored while the network request is unresolved");
  resolveNetwork(true);
  await click;
  assert.equal(vm.runInContext("modal", context), null);
});

test("actions that close a modal restore its invoker before or after async work", async () => {
  for (const closesSynchronously of [true, false]) {
    const context = loadContext();
    let invokerFocused = 0;
    let resolveNetwork;
    const listeners = new Map();
    const action = {
      dataset: { action: "submit-password-change" },
      addEventListener(type, listener) { listeners.set(type, listener); }
    };
    const invoker = {
      dataset: { action: "change-password" },
      focus() { invokerFocused += 1; }
    };
    context.runtimeLists.set("[data-action]", [action]);
    context.runtimeLists.set('[data-action="change-password"]', [invoker]);
    context.pendingNetwork = new Promise(resolve => { resolveNetwork = resolve; });
    vm.runInContext(`
      render = () => true;
      modal = { type: "change-password", returnFocus: { action: "change-password" } };
      handleAction = async () => {
        if (${closesSynchronously}) {
          modal = null;
          render();
        } else {
          await pendingNetwork;
          modal = null;
          render();
        }
        return true;
      };
      bindEvents();
    `, context);

    const click = listeners.get("click")({ stopPropagation() {} });
    if (closesSynchronously) {
      assert.equal(invokerFocused, 1);
      resolveNetwork(true);
    } else {
      assert.equal(invokerFocused, 0);
      resolveNetwork(true);
    }
    await click;
    assert.ok(invokerFocused >= 1);
    assert.equal(vm.runInContext("modal", context), null);
  }

  const fallback = loadContext();
  let stableFallback = 0;
  const listeners = new Map();
  const action = {
    dataset: { action: "submit-password-change" },
    addEventListener(type, listener) { listeners.set(type, listener); }
  };
  fallback.runtimeLists.set("[data-action]", [action]);
  vm.runInContext(`
    render = () => true;
    focusStableScreenContext = () => { globalThis.stableFallback += 1; };
    globalThis.stableFallback = 0;
    modal = { type: "change-password" };
    handleAction = async () => { modal = null; render(); return true; };
    bindEvents();
  `, fallback);
  await listeners.get("click")({ stopPropagation() {} });
  stableFallback = vm.runInContext("globalThis.stableFallback", fallback);
  assert.ok(stableFallback >= 1);
});

test("background live conflict closes its sheet and restores the room trigger", () => {
  const context = loadContext();
  let restoredFocus = 0;
  const trigger = {
    dataset: { action: "open-live-room", roomId: "11111111-1111-4111-8111-111111111111" },
    focus() {
      restoredFocus += 1;
      context.document.activeElement = this;
    }
  };
  context.runtimeLists.set('[data-action="open-live-room"]', [trigger]);
  vm.runInContext(`
    render = () => true;
    showToast = () => true;
    modal = {
      type: "live-workout-room",
      roomId: "11111111-1111-4111-8111-111111111111",
      returnFocus: {
        action: "open-live-room",
        roomId: "11111111-1111-4111-8111-111111111111"
      }
    };
    detachLiveWorkoutAfterConflict("liveRoomInactive");
  `, context);

  assert.equal(vm.runInContext("modal", context), null);
  assert.equal(restoredFocus, 1);
});

test("Enter submits password flows through the generic focus lifecycle", async () => {
  for (const outcome of ["success", "reauth"]) {
    const context = loadContext();
    let invokerFocused = 0;
    const submitListeners = new Map();
    const repeatListeners = new Map();
    const invoker = {
      dataset: { action: "change-password" },
      focus() { invokerFocused += 1; }
    };
    const submit = {
      dataset: { action: "submit-password-change" },
      addEventListener(type, listener) { submitListeners.set(type, listener); },
      click() {
        this.clickPromise = submitListeners.get("click")({ stopPropagation() {} });
        return this.clickPromise;
      }
    };
    const repeat = {
      addEventListener(type, listener) { repeatListeners.set(type, listener); }
    };
    context.runtimeLists.set("[data-action]", [submit]);
    context.runtimeLists.set('[data-action="change-password"]', [invoker]);
    context.runtimeNodes.set('[data-action="submit-password-change"]', submit);
    context.runtimeNodes.set("#change-repeat-password", repeat);
    vm.runInContext(`
      render = () => true;
      modal = { type: "change-password", returnFocus: { action: "change-password" } };
      handleAction = async action => {
        if (action !== "submit-password-change") return false;
        modal = ${outcome === "success"
          ? "null"
          : "{ type: 'change-password', reauthRequired: true }"};
        render();
        return true;
      };
      bindEvents();
    `, context);

    const enter = {
      key: "Enter",
      prevented: false,
      preventDefault() { this.prevented = true; }
    };
    repeatListeners.get("keydown")(enter);
    assert.equal(enter.prevented, true);
    await submit.clickPromise;

    if (outcome === "success") {
      assert.equal(vm.runInContext("modal", context), null);
      assert.equal(invokerFocused, 1);
    } else {
      assert.equal(vm.runInContext("modal.reauthRequired", context), true);
      assert.equal(vm.runInContext("modal.returnFocus.action", context), "change-password");
      vm.runInContext("closeModal()", context);
      assert.equal(invokerFocused, 1);
    }
  }
});

test("Back and browser history scrub rendered password values before dismissing", () => {
  for (const dismissal of ["back", "popstate"]) {
    const context = loadContext();
    const sensitive = [
      "#change-current-password",
      "#change-password-nonce",
      "#change-new-password",
      "#change-repeat-password"
    ].map(selector => {
      const input = { value: `${dismissal}-secret` };
      context.runtimeNodes.set(selector, input);
      return input;
    });
    vm.runInContext(`
      render = () => true;
      nav = [{ name: "workouts" }];
      modal = { type: "change-password", returnFocus: { action: "change-password" } };
    `, context);

    if (dismissal === "back") {
      vm.runInContext("back()", context);
    } else {
      context.windowListeners.get("popstate")({
        state: { gymAppNav: [{ name: "missions" }] }
      });
    }

    assert.equal(vm.runInContext("modal", context), null);
    assert.deepEqual(sensitive.map(input => input.value), ["", "", "", ""]);
  }
});

test("modal rerenders preserve the focused descendant and validate inherited return focus", () => {
  const context = loadContext();
  const oldField = { id: "friend-detail-filter", dataset: {} };
  const oldModalElement = {
    contains: element => element === oldField,
    querySelectorAll: selector => selector === "[id]" ? [oldField] : [oldField]
  };
  context.runtimeNodes.set(".modal", oldModalElement);
  context.document.activeElement = oldField;
  vm.runInContext(`
    modal = {
      type: "friend-detail",
      profileId: "p_11111111111111111111111111111111",
      autoFocus: false,
      returnFocus: {
        action: "open-friend",
        profileId: "p_11111111111111111111111111111111"
      }
    };
    preservedModalFocus = captureModalDescendantFocus();
    modal = friendDetailModal("p_11111111111111111111111111111111", modal);
  `, context);
  assert.equal(vm.runInContext("modal.autoFocus", context), false);
  assert.equal(vm.runInContext("modal.returnFocus.action", context), "open-friend");

  let restored = false;
  const newField = {
    id: "friend-detail-filter",
    dataset: {},
    hidden: false,
    getAttribute: () => null,
    focus() {
      restored = true;
      context.document.activeElement = this;
    }
  };
  const listeners = new Map();
  const newModalElement = {
    contains: element => element === newField,
    querySelectorAll: selector => selector === "[id]" ? [newField] : [newField],
    addEventListener(type, listener) { listeners.set(type, listener); },
    getAttribute: () => null,
    hasAttribute: () => false,
    setAttribute() {},
    focus() {}
  };
  context.runtimeNodes.set(".modal", newModalElement);
  context.appNode.children = [newModalElement];
  vm.runInContext("bindEvents(preservedModalFocus)", context);
  assert.equal(restored, true);
  assert.equal(context.document.activeElement, newField);

  let fallbackFocused = false;
  const enabledClose = {
    id: "modal-close",
    dataset: { action: "close-modal" },
    hidden: false,
    closest: () => null,
    getAttribute: () => null,
    focus() {
      fallbackFocused = true;
      context.document.activeElement = this;
    }
  };
  const disabledReplacement = {
    id: "friend-detail-filter",
    dataset: { action: "submit-password-change" },
    disabled: true,
    hidden: false,
    closest: () => null,
    getAttribute: () => null,
    focus() { throw new Error("a disabled replacement must not receive focus"); }
  };
  const disabledModalElement = {
    contains: element => element === enabledClose || element === disabledReplacement,
    querySelectorAll: selector => selector === "[data-action]"
      ? [enabledClose, disabledReplacement]
      : [enabledClose],
    addEventListener() {},
    hasAttribute: () => false,
    setAttribute() {},
    focus() {}
  };
  context.runtimeNodes.set(".modal", disabledModalElement);
  context.appNode.children = [disabledModalElement];
  context.document.activeElement = newField;
  vm.runInContext(`
    modal.autoFocus = false;
    bindEvents({ kind: "id", id: "friend-detail-filter" });
  `, context);
  assert.equal(fallbackFocused, true);
  assert.equal(context.document.activeElement, enabledClose);

  vm.runInContext(`
    modal = friendDetailModal(
      "p_11111111111111111111111111111111",
      { type: "friend-detail", returnFocus: { action: "not-allowed", profileId: "x" } }
    );
  `, context);
  assert.equal(vm.runInContext("Object.hasOwn(modal, 'returnFocus')", context), false);
});

test("hidden modal inputs never become focus-trap endpoints", () => {
  const context = loadContext();
  const closeButton = {
    hidden: false,
    getAttribute: () => null,
    focus() { context.document.activeElement = this; }
  };
  const hiddenFileInput = {
    hidden: true,
    getAttribute: () => null,
    focus() { throw new Error("hidden input must not receive focus"); }
  };
  context.testModalElement = {
    contains: element => element === closeButton || element === hiddenFileInput,
    querySelectorAll: () => [closeButton, hiddenFileInput]
  };
  context.document.activeElement = closeButton;
  for (const shiftKey of [false, true]) {
    context.testTabEvent = {
      key: "Tab",
      shiftKey,
      prevented: false,
      preventDefault() { this.prevented = true; }
    };
    vm.runInContext("handleDestructiveModalKeydown(testModalElement, testTabEvent)", context);
    assert.equal(context.testTabEvent.prevented, true);
    assert.equal(context.document.activeElement, closeButton);
  }
});

test("exercise filter and More sheets restore stable invokers, including a nested picker return", async () => {
  const context = loadContext();
  let filterFocused = 0;
  let moreFocused = 0;
  let sortFocused = 0;
  let muscleFocused = 0;
  let resetFocused = 0;
  const filterTrigger = {
    dataset: { action: "open-exercise-filters" },
    focus() { filterFocused += 1; }
  };
  const moreTrigger = {
    dataset: { action: "open-exercise-more", id: "7001" },
    focus() { moreFocused += 1; }
  };
  const sortTrigger = {
    dataset: { action: "exercise-sort", sort: "most" },
    focus() { sortFocused += 1; }
  };
  const muscleTrigger = {
    dataset: { action: "exercise-muscle-filter", filter: "chest" },
    focus() { muscleFocused += 1; }
  };
  const resetTrigger = {
    dataset: { action: "reset-exercise-filters" },
    focus() { resetFocused += 1; }
  };
  context.runtimeLists.set('[data-action="open-exercise-filters"]', [filterTrigger]);
  context.runtimeLists.set('[data-action="open-exercise-more"]', [moreTrigger]);
  context.runtimeLists.set('[data-action="exercise-sort"]', [sortTrigger]);
  context.runtimeLists.set('[data-action="exercise-muscle-filter"]', [muscleTrigger]);
  context.runtimeLists.set('[data-action="reset-exercise-filters"]', [resetTrigger]);
  context.filterInvoker = { dataset: { action: "open-exercise-filters" } };
  context.moreInvoker = { dataset: { action: "open-exercise-more", id: "7001" } };
  context.sortInvoker = { dataset: { action: "exercise-sort", sort: "most" } };
  context.muscleInvoker = { dataset: { action: "exercise-muscle-filter", filter: "chest" } };
  context.resetInvoker = { dataset: { action: "reset-exercise-filters" } };
  vm.runInContext(`
    render = () => true;
    nav = [{ name: "exercises" }];
    state.exercises = [{ id: 7001, name: "Bench Press" }];
    saveState({ queueRemote: false, markDirty: false });
    modal = { type: "workout-exercise-picker", target: "draft-new", autoFocus: true };
  `, context);

  await vm.runInContext(`handleAction("open-exercise-filters", globalThis.filterInvoker)`, context);
  assert.equal(vm.runInContext("modal.type", context), "exercise-filters");
  assert.equal(vm.runInContext("modal.returnModal.type", context), "workout-exercise-picker");
  assert.equal(vm.runInContext("modal.returnModal.autoFocus", context), false);
  await vm.runInContext(`handleAction("apply-exercise-filters", { dataset: {} })`, context);
  assert.equal(vm.runInContext("modal.type", context), "workout-exercise-picker");
  assert.equal(filterFocused, 1);

  vm.runInContext("modal = { type: 'exercise-filters', autoFocus: false }", context);
  await vm.runInContext(`handleAction("exercise-sort", globalThis.sortInvoker)`, context);
  assert.equal(vm.runInContext("exerciseSortMode", context), "most");
  assert.equal(sortFocused, 1);
  await vm.runInContext(`handleAction("exercise-muscle-filter", globalThis.muscleInvoker)`, context);
  assert.equal(vm.runInContext("exerciseMuscleFilter", context), "chest");
  assert.equal(muscleFocused, 1);
  await vm.runInContext(`handleAction("reset-exercise-filters", globalThis.resetInvoker)`, context);
  assert.equal(vm.runInContext("exerciseSortMode", context), "name");
  assert.equal(vm.runInContext("exerciseMuscleFilter", context), "all");
  assert.equal(resetFocused, 1);

  vm.runInContext("modal = null", context);
  await vm.runInContext(`handleAction("open-exercise-more", globalThis.moreInvoker)`, context);
  assert.equal(vm.runInContext("modal.returnFocus.id", context), 7001);
  vm.runInContext("closeModal()", context);
  assert.equal(moreFocused, 1);

  for (const [action, dataset, expectedType] of [
    ["exercise-history", { id: "7001" }, "history"],
    ["map-exercise", { name: "Bench Press" }, "map"],
    ["configure-load-profile", { id: "7001" }, "load-profile"],
    ["rename-exercise", { id: "7001" }, "rename"]
  ]) {
    await vm.runInContext(`handleAction("open-exercise-more", globalThis.moreInvoker)`, context);
    context.childInvoker = { dataset };
    await vm.runInContext(`handleAction(${JSON.stringify(action)}, globalThis.childInvoker)`, context);
    assert.equal(vm.runInContext("modal.type", context), expectedType);
    assert.equal(vm.runInContext("modal.returnFocus.id", context), 7001);
    vm.runInContext("closeModal()", context);
  }
  assert.equal(moreFocused, 5);

  await vm.runInContext(`handleAction("open-exercise-more", globalThis.moreInvoker)`, context);
  await vm.runInContext(`handleAction("delete-exercise", { dataset: { id: "7001" } })`, context);
  assert.equal(vm.runInContext("modal.type", context), "confirm-delete-exercise");
  assert.equal(vm.runInContext("modal.intent.returnFocus.action", context), "open-exercise-more");
  vm.runInContext("closeModal()", context);
  assert.equal(moreFocused, 6);
});

test("the hidden SVG map has an equivalent localized keyboard muscle selector", async () => {
  const context = loadContext();
  const markup = vm.runInContext(`(() => {
    state.language = "ru";
    selectedMuscle = "chest";
    return muscleMapSelectionList([
      { id: "chest", label: "Грудь", load: 120 },
      { id: "lats", label: "Широчайшие", load: 80 }
    ]);
  })()`, context);
  assert.match(markup, /role="group" aria-label="Выбрать группу мышц"/);
  assert.match(markup, /data-action="select-muscle" data-id="chest" aria-pressed="true"/);
  assert.match(markup, /data-action="select-muscle" data-id="lats" aria-pressed="false"/);
  vm.runInContext("render = () => true; selectedMuscle = null", context);
  assert.equal(
    await vm.runInContext(`handleAction("select-muscle", { dataset: { id: "not-a-muscle" } })`, context),
    false
  );
  assert.equal(vm.runInContext("selectedMuscle", context), null);
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

test("full import remains pending until confirmation and is account and state bound", async () => {
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

  vm.runInContext("modal = { type: 'import' }; applyImport(); accountEpoch += 1", context);
  await vm.runInContext("confirmImport()", context);
  assert.equal(vm.runInContext("JSON.stringify(state)", context), beforeState);
  assert.equal(storedState(context), beforeStored);

  vm.runInContext("modal = { type: 'import' }; applyImport()", context);
  await vm.runInContext("confirmImport()", context);
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
