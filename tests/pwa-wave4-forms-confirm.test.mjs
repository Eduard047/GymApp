import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const source = await readFile("pwa/app.js", "utf8");
const between = (from, to) => {
  const start = source.indexOf(from);
  assert.notEqual(start, -1, `missing ${from}`);
  const end = source.indexOf(to, start);
  assert.notEqual(end, -1, `missing ${to}`);
  return source.slice(start, end);
};

test("no native window.confirm or bare confirm() remains in the web app", () => {
  assert.equal(/\bwindow\.confirm\s*\(/.test(source), false);
  assert.equal(/(^|[^\w.$])confirm\s*\(/m.test(source), false);
  assert.equal(/\.confirm\s*\(/.test(source), false);
  assert.match(source, /async function confirmSheet\(|function confirmSheet\(/);
});

const languageSource = between("function firstRunLanguageFromLocales(", "function defaultAppState()");

function languageContext(navigator) {
  const context = vm.createContext(navigator === undefined ? {} : { navigator });
  vm.runInContext(languageSource, context);
  return context;
}

test("first-run language follows the browser like iOS and Android: uk, ru, else en", () => {
  const context = languageContext();
  const pick = list => vm.runInContext(`firstRunLanguageFromLocales(${JSON.stringify(list)})`, context);
  assert.equal(pick(["uk-UA", "en-US"]), "uk");
  assert.equal(pick(["ru-UA"]), "ru");
  assert.equal(pick(["ru_RU"]), "ru");
  assert.equal(pick(["de-DE", "ru-RU", "en-GB"]), "ru");
  assert.equal(pick(["de-DE", "fr"]), "en");
  assert.equal(pick(["en-GB", "ru"]), "en");
  assert.equal(pick([]), "en");
  assert.equal(pick(null), "en");
  assert.equal(pick([42, null, "UK"]), "uk");
});

test("detectFirstRunLanguage reads navigator.languages, then navigator.language, and survives no navigator", () => {
  assert.equal(vm.runInContext("detectFirstRunLanguage()", languageContext()), "en");
  assert.equal(
    vm.runInContext("detectFirstRunLanguage()", languageContext({ languages: ["uk-UA", "en-US"], language: "en-US" })),
    "uk"
  );
  assert.equal(
    vm.runInContext("detectFirstRunLanguage()", languageContext({ languages: [], language: "ru-RU" })),
    "ru"
  );
  assert.equal(vm.runInContext("detectFirstRunLanguage()", languageContext({ language: "pl-PL" })), "en");
  const throwing = {};
  Object.defineProperty(throwing, "languages", { get() { throw new Error("blocked"); } });
  assert.equal(vm.runInContext("detectFirstRunLanguage()", languageContext(throwing)), "en");
});

test("only the no-saved-state default uses the detected language", () => {
  assert.match(between("function defaultAppState()", "function ensureBuiltInExerciseCatalog"), /language: detectFirstRunLanguage\(\)/);
  // A stored state keeps its own language: it is read from storage, never re-detected.
  assert.equal((source.match(/detectFirstRunLanguage\(\)/g) || []).length, 2);
});

test("sign-in and sign-up render one real form with autocomplete and a submit button", () => {
  const panel = between('remotePanel = `<section class="panel highlighted auth-panel"><h2>${isSignUp', "return `<div class=\"app-shell auth-shell\">");
  assert.match(panel, /<form id="auth-form" class="auth-form" data-auth-form="\$\{isSignUp \? "signup" : "login"\}" novalidate>/);
  assert.equal(/<form[^>]*\saction=/.test(panel), false, "CSP form-action is none: no action attribute");
  assert.match(panel, /<\/form>\$\{offlineLinkMarkup\(true\)\}/);
  assert.match(panel, /id="login-email"[^>]*autocomplete="username"/);
  assert.match(panel, /id="login-password"[^>]*autocomplete="current-password"/);
  assert.match(panel, /id="signup-email"[^>]*autocomplete="email"/);
  assert.equal((panel.match(/autocomplete="new-password"/g) || []).length, 2);
  assert.match(panel, /<button type="submit" class="button full" data-action="\$\{isSignUp \? "remote-signup" : "remote-login"\}"/);
  // Secondary buttons inside the form must not submit it.
  assert.match(panel, /<button type="button" class="auth-quiet-link auth-forgot-link"/);
  assert.match(source, /class="password-toggle"/);
  assert.equal(/<button class="password-toggle"/.test(source), false);
});

test("the auth form submit handler cancels navigation and reuses the existing actions without logging", () => {
  const handler = between("async function handleAuthFormSubmit(", "function bindEvents(");
  assert.match(handler, /event\.preventDefault\(\)/);
  assert.match(handler, /authRequestInProgress/);
  assert.match(handler, /button\.disabled/);
  assert.equal(/console\./.test(handler), false);
  assert.match(source, /app\.addEventListener\("submit", event => void handleAuthFormSubmit\(event\)\)/);
  // The click on the submit button defers to the submit event so Enter and clicks share one path.
  assert.match(source, /actionElement\?\.type === "submit" && actionElement\.form\?\.dataset\?\.authForm\) return false/);
  // The old Enter keydown shortcut would double-submit now that the form submits itself.
  assert.equal(/app\.querySelector\("#login-password"\)/.test(source), false);
});

test("auth form submit runs the sign-in action once and cancels the default submission", async () => {
  const handlerSource = between("async function handleAuthFormSubmit(", "function bindEvents(");
  const calls = [];
  const context = vm.createContext({
    authRequestInProgress: false,
    handleAppActionClick: (event, button) => { calls.push(button.dataset.action); return true; }
  });
  vm.runInContext(handlerSource, context);
  const button = { disabled: false, dataset: { action: "remote-login" } };
  const form = { dataset: { authForm: "login" }, querySelector: () => button };
  let prevented = 0;
  const event = { target: form, preventDefault: () => { prevented += 1; } };
  await vm.runInContext("handleAuthFormSubmit", context)(event);
  assert.deepEqual(calls, ["remote-login"]);
  assert.equal(prevented, 1);

  button.disabled = true;
  await vm.runInContext("handleAuthFormSubmit", context)(event);
  assert.equal(calls.length, 1, "a disabled submit button blocks the action");
  assert.equal(prevented, 2, "navigation is still cancelled");

  const unrelated = { target: { dataset: {} }, preventDefault: () => { prevented += 1; } };
  await vm.runInContext("handleAuthFormSubmit", context)(unrelated);
  assert.equal(prevented, 2, "other forms are left alone");
});

test("numeric values, exercise names and the account email are marked translate=no after render", () => {
  const guardSource = between("const NO_TRANSLATE_SELECTORS", "function bindEvents(");
  const context = vm.createContext({});
  vm.runInContext(guardSource, context);
  const selectors = vm.runInContext("NO_TRANSLATE_SELECTORS", context);
  for (const required of [".metric-grid strong", ".active-set-summary-text", ".exercise-name", "#pending-confirmation-email"]) {
    assert.ok(selectors.includes(required), required);
  }
  const makeElement = () => {
    const attributes = new Map();
    return {
      getAttribute: name => attributes.get(name) ?? null,
      setAttribute: (name, value) => attributes.set(name, value)
    };
  };
  const elements = [makeElement(), makeElement()];
  elements[1].setAttribute("translate", "no");
  let queried = "";
  const root = { querySelectorAll: selector => { queried = selector; return elements; } };
  const marked = vm.runInContext("applyTranslateGuards", context)(root);
  assert.equal(marked, 1, "already-marked elements are not counted again");
  assert.equal(elements[0].getAttribute("translate"), "no");
  assert.equal(queried, selectors.join(","));
  assert.equal(vm.runInContext("applyTranslateGuards", context)(null), 0);
  assert.match(source, /function bindEvents\(preservedModalFocus = null\) \{\n  applyTranslateGuards\(app\);/);
});
