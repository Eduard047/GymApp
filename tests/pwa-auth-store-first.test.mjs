import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stylesSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/styles.css", "utf8")
]);

function slice(startMarker, endMarker) {
  const start = appSource.indexOf(startMarker);
  const end = appSource.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0 && end > start, `${startMarker} must precede ${endMarker}`);
  return appSource.slice(start, end);
}

function authContext(overrides = {}) {
  const context = vm.createContext({
    state: { language: "en" },
    authMode: "login",
    authPanelExpanded: false,
    authNotice: null,
    authRequestInProgress: false,
    pendingEmailConfirmation: null,
    pendingSharedWorkout: null,
    modal: null,
    PRIVACY_URL: "https://example.test/privacy",
    SUPPORT_URL: "https://example.test/support",
    authDrafts: {
      login: { email: "", password: "" },
      signup: { email: "", emailConfirm: "", password: "", passwordConfirm: "", name: "" },
      forgot: { email: "" }
    },
    accountList: () => [],
    remoteAuthEnabled: () => true,
    languageSelectorMarkup: () => "",
    storeDownloadPanel: () => "<section class=\"store-card\"></section>",
    sharedWorkoutPreviewMarkup: () => "",
    window: {},
    emailConfirmationPanel: footer => `<section class="auth-panel">${footer}</section>`,
    escapeHtml: value => String(value),
    escapeAttr: value => String(value).replace(/"/g, "&quot;"),
    txAttr: (en, uk) => en,
    svg: (name, cls = "") => `<svg class="${cls}" data-icon="${name}"></svg>`,
    ...overrides
  });
  vm.runInContext(
    `${slice("function tx(en, uk)", "const ACTIVE_WORKOUT_STATUS_MESSAGES")}\n` +
    `${slice("function loginScreen()", "function storeDownloadPanel()")}\n` +
    `${slice("function effectiveTheme()", "function emailConfirmationPanel(")}\n` +
    "globalThis.loginScreen = loginScreen;",
    context
  );
  context.ru = text => text;
  return context;
}

const render = context => vm.runInContext("loginScreen()", context);
const expandedState = context => vm.runInContext("authPanelExpanded", context);

test("the store card renders before the collapsed sign-in disclosure", () => {
  const html = render(authContext());
  const store = html.indexOf('class="store-card"');
  const toggle = html.indexOf('data-action="toggle-auth-panel"');
  const body = html.indexOf('id="auth-panel-body"');
  const legal = html.indexOf("auth-legal-card");
  assert.ok(store > html.indexOf("auth-brand-panel"), "store card follows the header");
  assert.ok(store < toggle && toggle < body && body < legal, "store, toggle, form body, legal card in order");
  assert.match(html, /id="auth-panel-toggle"[^>]*aria-expanded="false" aria-controls="auth-panel-body"/);
  assert.match(html, /<strong>Sign in to the web version<\/strong>/);
  assert.match(html, /<div id="auth-panel-body" class="auth-access-body" hidden>/);
  assert.equal(expandedState(authContext()), false);
});

test("the pending shared workout panel stays above the store card", () => {
  const html = render(authContext({ pendingSharedWorkout: { id: "w" } }));
  assert.ok(html.indexOf("shared-workout-pending") < html.indexOf('class="store-card"'));
});

test("the disclosure localizes its title", () => {
  const context = authContext();
  context.state.language = "uk";
  assert.ok(render(context).includes("Увійти у вебверсію"));
  context.state.language = "ru";
  assert.ok(render(context).includes("Войти в веб-версию"));
});

test("an expanded disclosure drops the hidden attribute and reports aria-expanded", () => {
  const context = authContext({ authPanelExpanded: true });
  const html = render(context);
  assert.match(html, /aria-expanded="true" aria-controls="auth-panel-body"/);
  assert.match(html, /<div id="auth-panel-body" class="auth-access-body">/);
  assert.match(html, /data-action="remote-login"/);
});

for (const [name, overrides] of [
  ["a notice", { authNotice: { text: "Check your email", isError: false } }],
  ["password reset", { authMode: "forgot" }],
  ["a pending email confirmation", { pendingEmailConfirmation: { email: "a@b.test" } }],
  ["a pending shared workout", { pendingSharedWorkout: { id: "w" } }],
  ["standalone display mode", { window: { matchMedia: query => ({ matches: query === "(display-mode: standalone)" }) } }],
  ["iOS home-screen mode", { navigator: { standalone: true } }]
]) {
  test(`${name} opens the sign-in panels without a toggle and latches them open`, () => {
    const context = authContext(overrides);
    const html = render(context);
    assert.doesNotMatch(html, /data-action="toggle-auth-panel"/);
    assert.match(html, /<div class="auth-access">/);
    assert.ok(html.indexOf('class="store-card"') < html.indexOf('class="auth-access"'));
    assert.equal(expandedState(context), true, "forced expansion is remembered");
    vm.runInContext("authNotice = null; authMode = 'login'; pendingEmailConfirmation = null; pendingSharedWorkout = null; window = {}; globalThis.navigator = undefined;", context);
    const after = render(context);
    assert.match(after, /aria-expanded="true"/, "stays open after the reason goes away");
  });
}

test("without remote auth only the offline link shows, with no disclosure", () => {
  const html = render(authContext({ remoteAuthEnabled: () => false }));
  assert.doesNotMatch(html, /toggle-auth-panel/);
  assert.match(html, /data-action="open-offline-account"/);
  assert.ok(html.indexOf('class="store-card"') < html.indexOf("auth-offline-row"));
});

test("the toggle action, reset and focus handling are wired into the app", () => {
  assert.match(appSource, /^let authPanelExpanded = false;$/m);
  assert.match(appSource, /function clearAuthDrafts\(\) \{\s*authMode = "login";\s*authPanelExpanded = false;/);
  const action = appSource.slice(appSource.indexOf('if (action === "toggle-auth-panel")'));
  const body = action.slice(0, action.indexOf('if (action === "remote-login")'));
  assert.match(body, /authPanelExpanded = !authPanelExpanded;\s*render\(\);/);
  assert.match(body, /#auth-panel-body input/);
  assert.match(body, /#auth-panel-toggle/);
  const forced = appSource.slice(appSource.indexOf("function authPanelForcedOpen()"));
  const forcedBody = forced.slice(0, forced.indexOf("\n}\n"));
  for (const condition of ["authNotice?.text", 'authMode === "forgot"', "pendingEmailConfirmation", "pendingSharedWorkout", "display-mode: standalone", "navigator.standalone === true"]) {
    assert.ok(forcedBody.includes(condition), condition);
  }
});

test("the disclosure row is at least 44px, rotates its chevron and honours reduced motion", () => {
  assert.match(stylesSource, /\.auth-disclosure-toggle \{ min-height: 56px;/);
  assert.match(stylesSource, /\.auth-disclosure-toggle\[aria-expanded="true"\] \.settings-row-trailing svg \{ transform: rotate\(180deg\); \}/);
  assert.match(stylesSource, /@media \(prefers-reduced-motion: reduce\) \{\s*\.auth-disclosure-toggle \.settings-row-trailing svg \{ transition: none; \}/);
  assert.doesNotMatch(stylesSource.slice(stylesSource.indexOf(".auth-access {"), stylesSource.indexOf(".auth-divider")), /gradient/i);
});

test("store buttons and profile links use one neutral smartphone glyph, never a store logo", () => {
  assert.match(appSource, /^  smartphone: "M/m);
  assert.doesNotMatch(appSource, /apple-logo|google-play"|appleLogo|googlePlayLogo/);
  const panel = slice("function storeDownloadPanel()", "function themePreferencePanel(");
  assert.equal((panel.match(/svg\("smartphone", "store-download-icon store-download-icon-line"\)/g) || []).length, 2);
  assert.match(panel, /svg\("watch", "store-download-icon"\)/);
  assert.match(appSource, /settingsRowMarkup\(\{ icon: "smartphone", title: tx3\("App Store"/);
  assert.match(appSource, /settingsRowMarkup\(\{ icon: "smartphone", title: tx3\("Google Play"/);
  assert.match(stylesSource, /\.store-download-icon\.store-download-icon-line \{\s*fill: none;\s*stroke: currentColor;/);
});
