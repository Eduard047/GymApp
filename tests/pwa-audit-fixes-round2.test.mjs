import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource, progressionSource, russianSource, stylesSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/styles.css", "utf8")
]);

function storage() {
  const values = new Map();
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
}

function context() {
  const localStorage = storage();
  const sessionStorage = storage();
  const app = { innerHTML: "", children: [], querySelectorAll: () => [], querySelector: () => null };
  const document = {
    documentElement: { lang: "en" },
    visibilityState: "visible",
    activeElement: null,
    querySelector: selector => selector === "#app" ? app : null,
    addEventListener() {}
  };
  const sandbox = {
    console, Date, Map, Set, TextEncoder, URL, URLSearchParams,
    crypto: webcrypto, document, navigator: {}, localStorage, sessionStorage,
    requestAnimationFrame: callback => callback(),
    clearTimeout, setTimeout, clearInterval, setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests")),
    window: {
      location: { search: "?access_token=test", hash: "", pathname: "/", replace() {} },
      history: { replaceState() {}, pushState() {}, state: null },
      crypto: webcrypto, localStorage, sessionStorage, document, navigator: {}, addEventListener() {}
    }
  };
  sandbox.window.self = sandbox.window;
  sandbox.window.top = sandbox.window;
  sandbox.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(sandbox);
  vm.runInContext(stateContractSource, sandbox);
  sandbox.window.GymStateContract = sandbox.GymStateContract;
  vm.runInContext(progressionSource, sandbox);
  sandbox.window.GymProgressionRules = sandbox.GymProgressionRules;
  vm.runInContext(russianSource, sandbox);
  vm.runInContext(appSource, sandbox);
  return sandbox;
}

function rule(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`).exec(stylesSource);
  assert.ok(match, `missing CSS rule ${selector}`);
  return match[1];
}

test("an empty exercise library says so and offers Add exercise instead of Clear filters", () => {
  const sandbox = context();
  const markup = JSON.parse(vm.runInContext(`(() => {
    const out = {};
    for (const language of ["en", "uk", "ru"]) {
      state.language = language;
      state.exercises = [];
      out[language] = exercisesScreen();
    }
    state.language = "en";
    state.exercises = [{ id: 1, name: "Bench Press", category: "Chest", equipment: "Barbell", muscle: "Chest" }];
    out.filtered = exercisesScreen();
    return JSON.stringify(out);
  })()`, sandbox));
  assert.match(markup.en, /No exercises yet[\s\S]*Add exercise/);
  assert.match(markup.uk, /Ще немає вправ[\s\S]*Додати вправу/);
  assert.match(markup.ru, /Пока нет упражнений[\s\S]*Добавить упражнение/);
  for (const language of ["en", "uk", "ru"]) {
    assert.doesNotMatch(markup[language], /reset-exercise-filters/);
    assert.match(markup[language], /empty-state-panel[\s\S]*data-action="open-exercise-add"/);
  }
});

test("the empty Progress screen has no weekly review above its hero", () => {
  const sandbox = context();
  const markup = vm.runInContext(`(() => {
    state.sessions = [];
    return progressScreen();
  })()`, sandbox);
  assert.match(markup, /progress-empty-state/);
  assert.doesNotMatch(markup, /weekly-review|weekly-decision/);
  assert.match(markup, /data-action="open-add"/);
});

test("plan screen keeps one filled primary: secondary add button, Apply plan and Replace", () => {
  assert.match(appSource, /class="button secondary exercise-builder-add" data-action="open-workout-exercise-picker"/);
  assert.match(appSource, /class="button secondary full" data-action="apply-smart" data-block="\$\{blockIndex\}">\$\{svg\("auto", "small-icon"\)\}\$\{t\("applySmart"\)\}/);
  assert.match(appSource, /class="button mini secondary" data-action="apply-smart-alternative"[^>]*>\$\{tx3\("Replace", "Замінити", "Заменить"\)\}/);
  assert.doesNotMatch(appSource, /class="button mini" data-action="apply-smart-alternative"/);
  // The single filled primary of the plan screen is the bottom Start workout.
  assert.match(appSource, /<button class="button full save-workout-button" data-action="\$\{primaryAction\}">/);
});

test("Apply plan is the English label and Russian maps to the same wording", () => {
  const sandbox = context();
  const labels = JSON.parse(vm.runInContext(`(() => {
    const out = {};
    for (const language of ["en", "uk", "ru"]) { state.language = language; out[language] = t("applySmart"); }
    return JSON.stringify(out);
  })()`, sandbox));
  assert.deepEqual(labels, { en: "Apply plan", uk: "Застосувати план", ru: "Применить план" });
});

test("accent-on-tint and brand-fill tokens keep contrast in light and dark", () => {
  const root = /:root\s*\{([\s\S]*?)\n\}/.exec(stylesSource)[1];
  assert.match(root, /--brand-fill:\s*#216bd7/i);
  assert.match(root, /--accent-on-tint:\s*#1b5cba/i);
  const dark = /:root\[data-theme="dark"\]\s*\{([\s\S]*?)\n\}/.exec(stylesSource)?.[1] || "";
  assert.match(dark, /--brand-fill:\s*#2e72d2/i);
  assert.match(dark, /--accent-on-tint:\s*var\(--sage\)/);
  const luminance = hex => {
    const channels = [1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16) / 255)
      .map(value => value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  };
  const ratio = (foreground, background) => {
    const [light, dark] = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
    return (light + 0.05) / (dark + 0.05);
  };
  assert.ok(ratio("#ffffff", "#216bd7") >= 4.5, "white on the light accent fill");
  assert.ok(ratio("#ffffff", "#2e72d2") >= 4.5, "white on the dark accent fill");
  assert.ok(ratio("#1b5cba", "#eef4ff") >= 4.5, "accent text on the light blue tint");
});

test("metric values wrap the unit when shrinking alone cannot fit, and stat labels clamp to two lines", () => {
  const sandbox = context();
  const classes = new Set();
  const value = {
    clientWidth: 100,
    style: { fontSize: "" },
    textContent: "1 250 000 кг",
    classList: { add: name => classes.add(name), remove: name => classes.delete(name) },
    get scrollWidth() { return 400; }
  };
  sandbox.document.querySelector("#app").querySelectorAll = selector => selector.includes(".summary-hero-stats strong") ? [value] : [];
  sandbox.window.getComputedStyle = () => ({ fontSize: "22px" });
  vm.runInContext("fitMetricTileValues()", sandbox);
  assert.ok(classes.has("fit-wrap"), "the unit wraps at spaces instead of clipping");
  assert.equal(value.style.fontSize, "17.6px");
  assert.match(rule(".summary-hero-stats span"), /line-clamp:\s*2/);
  assert.match(rule(".summary-hero-stats span"), /-webkit-line-clamp:\s*2/);
});
