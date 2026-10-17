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

function fakeForm(values) {
  const log = { focused: [], preventDefault: 0 };
  const inputs = Object.entries(values).map(([name, value]) => ({
    name,
    value,
    attributes: new Map(),
    setAttribute(key, attributeValue) { this.attributes.set(key, attributeValue); },
    removeAttribute(key) { this.attributes.delete(key); },
    focus() { log.focused.push(name); }
  }));
  const error = { textContent: "", hidden: true };
  const submit = { attributes: new Map(), setAttribute(key, value) { this.attributes.set(key, value); } };
  const form = {
    dataset: { sheetForm: "true" },
    log,
    inputs,
    error,
    submit,
    querySelector(selector) {
      const field = /^\[data-sheet-field="([^"]+)"\]$/.exec(selector);
      if (field) return inputs.find(input => input.name === field[1]) || null;
      if (selector === "#confirm-sheet-error") return error;
      if (selector === "[data-sheet-submit]") return submit;
      return null;
    },
    querySelectorAll(selector) {
      if (selector === "input") return inputs;
      if (selector === "[aria-invalid]") return inputs.filter(input => input.attributes.has("aria-invalid"));
      return [];
    }
  };
  return form;
}

const deleteFields = `[
  { name: "confirmation", kind: "text", label: "Type DELETE to confirm", exact: "DELETE", exactMessage: "Type DELETE exactly to confirm.", maxLength: 32 },
  { name: "password", kind: "password", label: "Current password", required: true, requiredMessage: "Enter your current password.", maxBytes: 1024, maxBytesMessage: "Current password is too long." }
]`;

function openFieldSheet(context, fields = deleteFields) {
  const box = settled(vm.runInContext(
    `promptSheet({ title: "Delete cloud account?", body: "Type DELETE", confirmLabel: "Delete account", cancelLabel: "Cancel", destructive: true, fields: ${fields} })`,
    context
  ));
  return box;
}

const submitEvent = form => ({ target: form, preventDefault() { form.log.preventDefault += 1; } });

test("app.js no longer calls window.prompt or prompt()", () => {
  assert.doesNotMatch(appSource, /\bwindow\.prompt\b/);
  assert.doesNotMatch(appSource, /(?<![A-Za-z0-9_$.])prompt\(/);
  assert.doesNotMatch(appSource, /window\.alert|\balert\(/);
});

test("the account deletion sheet is a masked, destructive, DELETE-gated field sheet", () => {
  const start = appSource.indexOf("async function deleteCloudAccount()");
  const end = appSource.indexOf("// The destructive confirmation (including the typed DELETE step)");
  const source = appSource.slice(start, end);
  assert.match(source, /await promptSheet\(\{[\s\S]*destructive: true[\s\S]*exact: "DELETE"/);
  assert.match(source, /name: "password",\s*kind: "password"/);
  assert.match(source, /if \(typed !== "DELETE"\)/);
  assert.match(source, /currentPassword = "";\s*const reauthenticated = await reauthentication;/);
  assert.match(source, /if \(entry\) entry\.password = "";/);
  // The password never reaches a log, toast, diagnostic, URL or attribute on this path.
  assert.doesNotMatch(source, /console\.|reportDiagnostic|diagnostic/i);
  assert.doesNotMatch(source, /showToast\([^)]*currentPassword/);
  assert.doesNotMatch(source, /\$\{currentPassword\}|encodeURIComponent\(currentPassword|dataset[^;]*currentPassword|setAttribute\([^)]*currentPassword/);
  assert.equal((source.match(/currentPassword/g) || []).length > 0, true);
});

test("the password field markup is type=password with current-password autocomplete and a form without an action", () => {
  const context = loadContext();
  openFieldSheet(context);
  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /<input id="confirm-sheet-field-password" type="password" data-sheet-field="password" data-sheet-secret autocomplete="current-password"/);
  assert.match(markup, /<form class="confirm-sheet-form" data-sheet-form="true" novalidate>/);
  assert.doesNotMatch(markup, /<form[^>]*\saction=/);
  assert.match(markup, /class="password-toggle"[^>]*data-action="toggle-password-visibility"/);
  assert.match(markup, /role="alertdialog"/);
  assert.match(markup, /id="confirm-sheet-field-confirmation" data-sheet-field="confirmation" autocomplete="off"[^>]* data-modal-initial-focus/);
  assert.match(markup, /<button type="button" class="button ghost full" data-action="cancel-destructive">Cancel<\/button>/);
  assert.match(markup, /<button type="submit" class="button danger full" data-sheet-submit>Delete account<\/button>/);
  assert.match(markup, /id="confirm-sheet-error" role="alert" hidden/);
  assert.doesNotMatch(markup, /\svalue=/);
  assert.doesNotMatch(markup, /\sstyle=/);
});

test("the typed DELETE gate is case-sensitive and shows an inline error without a password", async () => {
  const context = loadContext();
  const box = openFieldSheet(context);
  await flush();
  const form = fakeForm({ confirmation: "delete", password: "Secret-Pass-1!" });
  assert.equal(vm.runInContext("handleSheetFormSubmit", context)(submitEvent(form)), false);
  assert.equal(form.log.preventDefault, 1);
  assert.equal(box.done, false, "a wrong confirmation must not resolve the sheet");
  assert.equal(form.error.hidden, false);
  assert.equal(form.error.textContent, "Type DELETE exactly to confirm.");
  assert.equal(form.error.textContent.includes("Secret-Pass-1!"), false);
  assert.equal(form.inputs[0].attributes.get("aria-invalid"), "true");
  assert.deepEqual(form.log.focused, ["confirmation"]);
  // Surrounding whitespace is not ignored by this gate, exactly like the old prompt comparison.
  form.inputs[0].value = " DELETE";
  assert.equal(vm.runInContext("submitPromptSheet", context)(form), false);
  assert.equal(box.done, false);
});

test("an empty or oversized password is rejected inline and never echoed", async () => {
  const context = loadContext();
  const box = openFieldSheet(context);
  await flush();
  const empty = fakeForm({ confirmation: "DELETE", password: "" });
  assert.equal(vm.runInContext("submitPromptSheet", context)(empty), false);
  assert.equal(empty.error.textContent, "Enter your current password.");
  const long = "p".repeat(1025);
  const tooLong = fakeForm({ confirmation: "DELETE", password: long });
  assert.equal(vm.runInContext("submitPromptSheet", context)(tooLong), false);
  assert.equal(tooLong.error.textContent, "Current password is too long.");
  assert.equal(tooLong.error.textContent.includes("ppp"), false);
  assert.equal(box.done, false);
  // The multi-byte limit counts UTF-8 bytes, not characters.
  const wide = fakeForm({ confirmation: "DELETE", password: "é".repeat(513) });
  assert.equal(vm.runInContext("submitPromptSheet", context)(wide), false);
});

test("a valid submit resolves once, clears every input and closes the sheet; a second submit is ignored", async () => {
  const context = loadContext();
  const box = openFieldSheet(context);
  await flush();
  const form = fakeForm({ confirmation: "DELETE", password: "Secret-Pass-1!" });
  assert.equal(vm.runInContext("submitPromptSheet", context)(form), true);
  await flush();
  assert.deepEqual({ ...box.value }, { confirmation: "DELETE", password: "Secret-Pass-1!" });
  assert.deepEqual(form.inputs.map(input => input.value), ["", ""], "the field values are cleared as soon as the sheet submits");
  assert.equal(form.submit.attributes.has("disabled"), true);
  assert.equal(vm.runInContext("confirmSheetPending", context), null);
  assert.notEqual(vm.runInContext("modal?.type", context), "confirm-sheet");
  // Enter pressed again, or a second click, reaches no pending sheet.
  const again = fakeForm({ confirmation: "DELETE", password: "Secret-Pass-1!" });
  assert.equal(vm.runInContext("handleSheetFormSubmit", context)(submitEvent(again)), false);
  assert.equal(again.log.preventDefault, 1);
  assert.equal(JSON.stringify(vm.runInContext("modal", context) ?? null).includes("Secret-Pass-1!"), false);
});

test("the submit guard rejects a re-entrant submit while the first one is being accepted", async () => {
  const context = loadContext();
  openFieldSheet(context);
  await flush();
  vm.runInContext("confirmSheetPending.submitted = true", context);
  const form = fakeForm({ confirmation: "DELETE", password: "x" });
  assert.equal(vm.runInContext("submitPromptSheet", context)(form), false);
  assert.deepEqual(form.inputs.map(input => input.value), ["DELETE", "x"], "a rejected submit does not consume the fields");
});

const nullTeardowns = {
  "cancel button": `handleAction("cancel-destructive", {})`,
  "Esc / scrim / drag dismissal": `dismissSheet()`,
  "closeModal": `closeModal()`,
  "sign-out": `activeAccount = null; modal = null; render();`,
  "account switch": `activeAccount = { ...activeAccount, id: "local-v2-22222222222222222222222222222222" }; render();`,
  "another modal replacing it": `modal = { type: "history", exercise: null }; render();`
};

for (const [name, script] of Object.entries(nullTeardowns)) {
  test(`a field sheet resolves null on ${name} and holds no entered value`, async () => {
    const context = loadContext();
    const box = openFieldSheet(context);
    await flush();
    vm.runInContext(script, context);
    await flush();
    assert.deepEqual(box, { done: true, value: null });
    assert.equal(vm.runInContext("confirmSheetPending", context), null);
  });
}

test("a field sheet cannot be accepted through the plain confirm action", async () => {
  const context = loadContext();
  const box = openFieldSheet(context);
  await flush();
  assert.equal(vm.runInContext(`acceptConfirmSheet()`, context), false);
  assert.equal(box.done, false);
});

test("closeModal and pagehide clear the sheet password input", () => {
  const context = loadContext();
  const input = { value: "Secret-Pass-1!" };
  context.runtimeNodes.set("#confirm-sheet-field-password", input);
  vm.runInContext("clearSensitiveAuthDrafts()", context);
  assert.equal(input.value, "");
});

test("a display field keeps the token out of the markup and wipes it once the sheet settles", async () => {
  const context = loadContext();
  const box = settled(vm.runInContext(
    `promptSheet({ title: "T", body: "B", fields: [{ name: "token", kind: "display", label: "Token", displayValue: "gymcap-SECRET-TOKEN" }] })`,
    context
  ));
  await flush();
  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /readonly data-sheet-display="token" data-sheet-secret/);
  assert.equal(markup.includes("gymcap-SECRET-TOKEN"), false);
  assert.equal(context.appNode.innerHTML.includes("gymcap-SECRET-TOKEN"), false);
  const input = { value: "", addEventListener() {} };
  vm.runInContext("confirmSheetFillDisplayFields", context)({ querySelector: selector => selector === '[data-sheet-display="token"]' ? input : null });
  assert.equal(input.value, "gymcap-SECRET-TOKEN");
  const modalFields = vm.runInContext("modal.fields", context);
  assert.equal(vm.runInContext("submitPromptSheet", context)(fakeForm({})), true);
  await flush();
  assert.deepEqual({ ...box.value }, {});
  assert.equal(modalFields[0].displayValue, "", "the displayed token is wiped from the settled sheet state");
});

test("the device choice sheet returns the chosen option and rejects unknown values", async () => {
  const context = loadContext();
  const box = settled(vm.runInContext(
    `promptSheet({ title: "T", body: "B", fields: [{ name: "device", kind: "choice", label: "Watch", options: [{ value: "0", label: "1. A" }, { value: "1", label: "2. B <i>" }] }] })`,
    context
  ));
  await flush();
  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /<select id="confirm-sheet-field-device" data-sheet-field="device" data-modal-initial-focus>/);
  assert.match(markup, /<option value="1">2\. B &lt;i&gt;<\/option>/);
  const bad = fakeForm({ device: "9" });
  assert.equal(vm.runInContext("submitPromptSheet", context)(bad), false);
  assert.equal(box.done, false);
  assert.equal(vm.runInContext("submitPromptSheet", context)(fakeForm({ device: "1" })), true);
  await flush();
  assert.deepEqual({ ...box.value }, { device: "1" });
});

test("the Garmin token sheets show the token read-only without copying it and keep cancel-to-revoke semantics", () => {
  for (const marker of ["body: tokenPrompt", "displayValue: device.device_token", "displayValue: rawToken"]) {
    assert.ok(appSource.includes(marker), marker);
  }
  assert.doesNotMatch(appSource, /clipboard[^;]*(?:device_token|rawToken|deviceToken)/);
  const pairing = appSource.slice(appSource.indexOf("const tokenPrompt = tx(\n    \"Copy this Garmin pairing token"));
  assert.match(pairing, /if \(acknowledged === null\) \{\s*try \{\s*await revokeGarminDeviceById\(session, device\.id\);/);
  assert.match(appSource, /rawToken = null;\s*if \(acknowledged === null\) \{\s*throw userVisibleError\(\s*"The replacement Garmin token was not confirmed\./);
  assert.doesNotMatch(appSource, /console\.[a-z]+\([^)]*(?:rawToken|device_token|currentPassword)/);
});

test("the Garmin watch chooser is a choice sheet limited to five devices", () => {
  const start = appSource.indexOf("async function chooseGarminDeviceForRecovery(");
  const end = appSource.indexOf("async function recoverGarminDeviceBinding(");
  const source = appSource.slice(start, end);
  assert.match(source, /devices\.slice\(0, 5\)/);
  assert.match(source, /kind: "choice"/);
  assert.match(source, /\/\^\[0-4\]\$\/\.test\(selected\.device\)/);
});

async function deletionContext(promptResult, requests) {
  const context = loadContext();
  vm.runInContext(`
    activeAccount = { id: "remote-owner", userId: "11111111-1111-4111-8111-111111111111", name: "Owner", remote: "supabase" };
    accountEpoch = 7;
    normalizeStoredAccount = account => account;
    loadRemoteSession = () => ({ user: { id: "11111111-1111-4111-8111-111111111111", email: "owner@example.com" } });
    supabaseRequest = async (...args) => { __requests.push(args); throw new Error("stop after request"); };
  `, Object.assign(context, { __requests: requests }));
  context.confirmSheet = async () => true;
  context.promptSheet = async () => promptResult;
  context.toasts = [];
  vm.runInContext(`showToast = message => { toasts.push(message); }`, context);
  return context;
}

test("cancelling the field sheet cancels the deletion and sends no request", async () => {
  const requests = [];
  const context = await deletionContext(null, requests);
  await vm.runInContext("deleteCloudAccount()", context);
  assert.equal(requests.length, 0);
  assert.deepEqual(context.toasts, ["Account deletion cancelled."]);
});

test("a wrong DELETE returned by the sheet still sends no request", async () => {
  const requests = [];
  const context = await deletionContext({ confirmation: "delete", password: "Secret-Pass-1!" }, requests);
  await vm.runInContext("deleteCloudAccount()", context);
  assert.equal(requests.length, 0);
  assert.deepEqual(context.toasts, ["Account deletion cancelled."]);
});

test("an empty password returned by the sheet cancels the deletion", async () => {
  const requests = [];
  const context = await deletionContext({ confirmation: "DELETE", password: "" }, requests);
  await vm.runInContext("deleteCloudAccount()", context);
  assert.equal(requests.length, 0);
  assert.deepEqual(context.toasts, ["Account deletion cancelled."]);
});

test("the collected password goes only into the re-authentication body and the result object is emptied", async () => {
  const requests = [];
  const entry = { confirmation: "DELETE", password: "Secret-Pass-1!" };
  const context = await deletionContext(entry, requests);
  await vm.runInContext("deleteCloudAccount()", context);
  assert.equal(requests.length, 1);
  assert.equal(requests[0][0], "/auth/v1/token?grant_type=password");
  assert.deepEqual(JSON.parse(requests[0][1].body), { email: "owner@example.com", password: "Secret-Pass-1!" });
  assert.equal(entry.password, "", "the resolved object no longer holds the password once the request is issued");
  assert.equal(context.toasts.some(message => String(message).includes("Secret-Pass-1!")), false);
});

test("an account switch while the field sheet is open sends no request and shows no toast", async () => {
  const requests = [];
  const context = await deletionContext({ confirmation: "DELETE", password: "Secret-Pass-1!" }, requests);
  context.promptSheet = async () => {
    vm.runInContext("accountEpoch += 1", context);
    return { confirmation: "DELETE", password: "Secret-Pass-1!" };
  };
  await vm.runInContext("deleteCloudAccount()", context);
  assert.equal(requests.length, 0);
  assert.deepEqual(context.toasts, []);
});

test("an accepted confirm sheet hands its return focus to the next sheet opened in the same turn", async () => {
  const context = loadContext();
  vm.runInContext(`
    modal = null;
    confirmSheet({ title: "A", destructive: true });
    modal.returnFocus = { action: "delete-account" };
  `, context);
  vm.runInContext(`normalizedStableActionReturnFocus = value => value`, context);
  vm.runInContext(`acceptConfirmSheet()`, context);
  vm.runInContext(`promptSheet({ title: "B", fields: [{ name: "x", kind: "text", label: "X" }] })`, context);
  assert.deepEqual({ ...vm.runInContext("modal.returnFocus", context) }, { action: "delete-account" });
});

test("sheet field descriptors are bounded and sanitised", () => {
  const context = loadContext();
  const fields = vm.runInContext(`normalizeSheetFields([
    { name: "__proto__", kind: "text", label: "bad" },
    { name: "ok", kind: "text", label: "ok", maxLength: 99999 },
    { name: "ok", kind: "text", label: "duplicate" },
    { name: "kind", kind: "script", label: "bad kind" },
    { name: "empty", kind: "choice", label: "no options", options: [] },
    { name: "b", kind: "text", label: "b" },
    { name: "c", kind: "text", label: "c" },
    { name: "d", kind: "text", label: "d" }
  ])`, context);
  assert.deepEqual([...fields].map(field => field.name), ["ok", "b", "c"]);
  assert.equal(fields[0].maxLength, 1024);
});

test("the shipped v142 bundle is a byte copy of the working file and the field-sheet styles ship in styles.v114", async () => {
  assert.equal(appSource, await readFile("pwa/app.v145.js", "utf8"));
  const [styles, shipped] = await Promise.all([readFile("pwa/styles.css", "utf8"), readFile("pwa/styles.v114.css", "utf8")]);
  assert.equal(styles, shipped);
  assert.match(shipped, /\.confirm-sheet-error \{[^}]*color: var\(--danger\)/);
});
