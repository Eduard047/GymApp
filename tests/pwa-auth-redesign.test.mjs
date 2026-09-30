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

function block(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = stylesSource.match(new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`));
  assert.ok(match, `${selector} rule must exist`);
  return match[1];
}

function authContext(overrides = {}) {
  const context = vm.createContext({
    state: { language: "en" },
    authMode: "login",
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
    languageSelectorMarkup: () => "<div class=\"language-selector\"></div>",
    storeDownloadPanel: () => "",
    themePreferencePanel: () => "",
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
    "globalThis.loginScreen = loginScreen; globalThis.togglePasswordVisibility = togglePasswordVisibility;" +
    "globalThis.offlineAccountSheetMarkup = offlineAccountSheetMarkup;",
    context
  );
  context.ru = text => text;
  return context;
}

test("auth header is a compact brand-gradient identity strip", () => {
  const panel = block(".auth-brand-panel");
  assert.match(panel, /grid-template-columns:\s*48px minmax\(0, 1fr\) 48px;/);
  assert.match(panel, /gap:\s*12px;/);
  assert.match(panel, /padding:\s*10px 16px;/);
  assert.match(panel, /linear-gradient\(135deg, var\(--brand-fill\) 0%, var\(--brand-fill-bright\) 100%\)/);
  assert.match(block(".auth-brand-mark"), /width:\s*48px;[\s\S]*height:\s*48px;/);
  assert.match(appSource, /class="auth-brand-mark" src="\.\/icon-192\.png" width="48" height="48"/);
  assert.match(block(".auth-wordmark"), /font-size:\s*22px;\s*font-weight:\s*700;\s*line-height:\s*28px;/);
});

test("auth primary actions use the brand fill with white text in both themes", () => {
  assert.match(
    stylesSource,
    /\.auth-panel \.button:not\(\.ghost\):not\(\.secondary\),\s*\.offline-account-sheet \.button:not\(\.ghost\):not\(\.secondary\)\s*\{[^}]*color:\s*#ffffff;[^}]*background:\s*var\(--brand-fill\);/
  );
});

test("sign-in and sign-up share a segmented picker with a single primary action", () => {
  const context = authContext();
  const login = vm.runInContext("loginScreen()", context);
  assert.match(login, /<h2>Welcome back<\/h2>/);
  assert.match(login, /class="segmented auth-mode-switch" role="radiogroup"/);
  assert.match(login, /role="radio" aria-checked="true" class="selected" data-mode="login"><strong>Sign in<\/strong>/);
  assert.match(login, /role="radio" aria-checked="false" data-action="auth-mode" data-mode="signup"[^>]*><strong>Sign up<\/strong>/);
  assert.equal((login.match(/data-action="remote-login"/g) || []).length, 1);
  assert.doesNotMatch(login, /button ghost/);
  assert.match(login, /data-action="remote-login"[^>]*>Sign in<\/button>/);
  assert.match(login, /class="auth-quiet-link auth-forgot-link" data-action="auth-mode" data-mode="forgot"/);

  context.authMode = "signup";
  const signup = vm.runInContext("loginScreen()", context);
  assert.match(signup, /<h2>Create account<\/h2>/);
  assert.match(signup, /aria-checked="true" class="selected" data-mode="signup"/);
  assert.match(signup, /aria-checked="false" data-action="auth-mode" data-mode="login"/);
  assert.match(signup, /data-action="remote-signup"[^>]*>Create account<\/button>/);
  assert.doesNotMatch(signup, /auth-forgot-link/);
  assert.doesNotMatch(signup, /Log in instead/);
});

test("auth mode labels are localized like the iOS screen", () => {
  const context = authContext();
  context.state.language = "uk";
  const uk = vm.runInContext("loginScreen()", context);
  for (const label of ["З поверненням", "Увійти", "Зареєструватися", "Політика конфіденційності", "Підтримка", "Забули пароль?", "Показати поле «пароль»"]) {
    assert.ok(uk.includes(label), label);
  }
  context.state.language = "ru";
  const ru = vm.runInContext("loginScreen()", context);
  for (const label of ["С возвращением", "Войти", "Регистрация", "Политика конфиденциальности", "Поддержка", "Показать поле «пароль»"]) {
    assert.ok(ru.includes(label), label);
  }
  context.authMode = "signup";
  const ruSignup = vm.runInContext("loginScreen()", context);
  assert.ok(ruSignup.includes("Показать поле «повторите пароль»"));
  assert.ok(ruSignup.includes("Скрыть поле «повторите пароль»"));
});

test("password inputs are wrapped with an absolutely positioned 44px visibility toggle", () => {
  const context = authContext();
  const login = vm.runInContext("loginScreen()", context);
  assert.equal((login.match(/class="password-toggle"/g) || []).length, 1);
  assert.match(login, /<input id="login-password"[^>]*type="password"[^>]*maxlength="1024"/);
  assert.match(login, /aria-pressed="false" aria-label="Show password" data-show-label="Show password" data-hide-label="Hide password"/);
  context.authMode = "signup";
  const signup = vm.runInContext("loginScreen()", context);
  assert.equal((signup.match(/class="password-toggle"/g) || []).length, 2);
  assert.match(signup, /aria-label="Show repeat password"/);
  assert.match(appSource, /eye: "M/);
  assert.match(appSource, /eyeOff: "M/);
  assert.match(block(".password-field-control input"), /padding-inline-end:\s*48px;/);
  const toggle = block(".password-toggle");
  assert.match(toggle, /position:\s*absolute;/);
  assert.match(toggle, /width:\s*44px;[\s\S]*height:\s*44px;/);
  // The toggle must not inflate the field: inputs keep the shared 56px height and no extra wrapper padding.
  assert.doesNotMatch(block(".password-field-control"), /padding|min-height|height/);
});

test("password toggle flips type and accessible labels in place without rendering or persisting", () => {
  const context = authContext();
  const attributes = {};
  const input = { type: "password", value: "secret" };
  const button = {
    dataset: { showLabel: "Show password", hideLabel: "Hide password" },
    setAttribute(name, value) { attributes[name] = value; },
    closest: selector => selector === ".password-field-control" ? { querySelector: () => input } : null
  };
  assert.equal(context.togglePasswordVisibility(button), true);
  assert.equal(input.type, "text");
  assert.equal(attributes["aria-pressed"], "true");
  assert.equal(attributes["aria-label"], "Hide password");
  assert.equal(input.value, "secret");
  assert.equal(context.togglePasswordVisibility(button), true);
  assert.equal(input.type, "password");
  assert.equal(attributes["aria-pressed"], "false");
  assert.equal(attributes["aria-label"], "Show password");
  assert.equal(context.togglePasswordVisibility({ closest: () => null, dataset: {} }), false);

  const handler = appSource.match(/if \(action === "toggle-password-visibility"\) return togglePasswordVisibility\(el\);/);
  assert.ok(handler, "toggle is dispatched through the delegated action handler");
  const body = slice("function togglePasswordVisibility(", "function storeDownloadPanel()");
  assert.doesNotMatch(body, /render\(|localStorage|sessionStorage|authDrafts/);
  // A mode switch re-renders every password input as type=password.
  assert.match(vm.runInContext("loginScreen()", context), /type="password"/);
});

test("continue offline and forgot password are quiet text links, not buttons", () => {
  const context = authContext();
  const login = vm.runInContext("loginScreen()", context);
  assert.match(login, /<hr class="auth-divider"><button type="button" class="auth-quiet-link auth-offline-button" data-action="open-offline-account"[^>]*><svg class="small-icon" data-icon="phone">/);
  assert.doesNotMatch(login, /class="button secondary full auth-offline-button"/);
  const quiet = block(".auth-quiet-link");
  assert.match(quiet, /min-height:\s*44px;/);
  assert.match(quiet, /color:\s*var\(--muted\);/);
  assert.match(quiet, /background:\s*transparent;/);
  assert.match(quiet, /border:\s*0;/);
  const forgot = block(".auth-quiet-link.auth-forgot-link");
  assert.match(forgot, /color:\s*var\(--sage\);/);
  assert.match(forgot, /font-weight:\s*500;/);
  assert.match(quiet, /font-size:\s*15px;/);
  // Without cloud auth the offline link still renders, standalone.
  context.remoteAuthEnabled = () => false;
  const offlineOnly = vm.runInContext("loginScreen()", context);
  assert.match(offlineOnly, /<div class="auth-offline-row"><button/);
});

test("legal links stay single-line 44px targets in one row or a stacked list", () => {
  const login = vm.runInContext("loginScreen()", authContext());
  assert.match(login, /<a class="auth-link" href="https:\/\/example\.test\/privacy"[^>]*><svg class="small-icon" data-icon="privacy"><\/svg><span>Privacy Policy<\/span><\/a>/);
  assert.match(login, /<a class="auth-link" href="https:\/\/example\.test\/support"[^>]*><svg class="small-icon" data-icon="help"><\/svg><span>Support<\/span><\/a>/);
  const links = block(".auth-links");
  assert.match(links, /flex-wrap:\s*wrap;/);
  assert.match(links, /gap:\s*0 28px;/);
  const link = stylesSource.match(/\.auth-links a,\s*\.auth-link\s*\{([^}]*)\}/)?.[1] || "";
  assert.match(link, /display:\s*inline-flex;/);
  assert.match(link, /min-height:\s*44px;/);
  assert.match(link, /white-space:\s*nowrap;/);
  assert.match(stylesSource, /@media \(max-width: 360px\)\s*\{\s*\.auth-links\s*\{\s*flex-direction:\s*column;/);
  assert.match(block(".auth-legal-card"), /gap:\s*4px;/);
  assert.match(login, /<details class="auth-secondary-details">/);
});

test("offline sheet has no nested card, a brand primary, and a quiet Cancel", () => {
  const sheet = vm.runInContext("offlineAccountSheetMarkup()", authContext());
  assert.doesNotMatch(sheet, /class="[^"]*\bpanel\b/);
  assert.match(sheet, /<button class="button full" data-action="continue-offline" data-modal-initial-focus>Continue offline<\/button>/);
  assert.match(sheet, /<button type="button" class="auth-quiet-link" data-action="close-modal">Cancel<\/button>/);
  assert.doesNotMatch(sheet, /button ghost full/);
  assert.doesNotMatch(block(".offline-account-sheet"), /border|box-shadow|background/);
});
