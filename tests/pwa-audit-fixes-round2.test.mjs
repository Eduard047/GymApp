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

test("large-text layout: comparison tiles reflow, header actions wrap, icons never shrink, stat labels hyphenate", () => {
  assert.match(rule(".workout-comparison-card"), /grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  assert.match(rule(".workout-comparison-card .metric-grid"), /auto-fit,\s*minmax\(min\(100%,\s*8\.5rem\),\s*1fr\)/);
  assert.match(rule(".workout-comparison-card .metric-grid > div"), /min-width:\s*0/);
  assert.match(rule(".exercise-builder-heading"), /flex-wrap:\s*wrap/);
  assert.match(rule(".small-icon"), /flex-shrink:\s*0/);
  assert.match(rule(".summary-hero-stats span"), /hyphens:\s*auto/);
  assert.match(rule(".summary-hero-stats span"), /overflow-wrap:\s*break-word/);
});

test("summary metrics tiles go one per row when two do not fit, and keep two columns at normal text", () => {
  assert.match(rule(".summary-metrics .metric-grid"), /repeat\(auto-fit,\s*minmax\(min\(100%,\s*8\.5rem\),\s*1fr\)\)/);
});

test("hero stats and feedback chips are three per row or one per row, never two plus one", () => {
  for (const [selector, container] of [[".summary-hero-stats", ".summary-hero"], [".segmented.workout-feedback-options", ".workout-feedback"]]) {
    assert.match(rule(selector), /grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/);
    assert.match(rule(container), /container-type:\s*inline-size/);
    assert.ok(stylesSource.includes(`@container (max-width: 14.5rem) {\n  ${selector} { grid-template-columns: 1fr; }`), `${selector} stacks in a narrow container`);
  }
  assert.doesNotMatch(rule(".summary-hero-stats"), /auto-fit/);
});

test("the summary hero grid column cannot grow past the card at large text", () => {
  assert.match(rule(".summary-hero"), /grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  assert.match(rule(".summary-hero-title > div"), /min-width:\s*0/);
  assert.doesNotMatch(rule(".summary-hero .summary-hero-title h2"), /hyphens/, "headings wrap by words, never by syllables");
  assert.match(rule(".summary-hero .summary-hero-title h2"), /overflow-wrap:\s*break-word/);
});

test("large text: history rows and navigators wrap by words, rows and heading controls drop under the text, titles never break inside a word", () => {
  const last = selector => {
    const re = new RegExp(`${selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\{([^}]*)\\}`, "g");
    return [...stylesSource.matchAll(re)].map(m => m[1]).at(-1) || "";
  };
  for (const selector of [".training-history-row strong", ".training-history-current strong", ".month-nav-month"]) {
    const rules = [...stylesSource.matchAll(/([^{}]+)\{([^}]*)\}/g)].filter(m => m[1].split(",").some(part => part.trim().endsWith(selector)));
    assert.ok(rules.at(-1)[2].includes("white-space: normal"), `${selector} wraps instead of an ellipsis`);
  }
  assert.match(last(".screen-copy h2"), /font-size:\s*min\(2rem,\s*9vw\)/);
  assert.match(last(".exercise-card-head"), /flex-wrap:\s*wrap/);
  assert.match(last(".draft-exercise-head"), /flex-wrap:\s*wrap/);
  assert.match(last(".smart-coach-header"), /flex-wrap:\s*wrap/);
  assert.match(last(".weekly-summary-metrics"), /auto-fit/);
  assert.match(last(".achievement-gallery"), /auto-fit/);
  assert.match(last(".progress-hub"), /container-type:\s*inline-size/);
  assert.ok(stylesSource.includes("@container (max-width: 14rem) {\n  .progress-hub-switch {"), "progress tabs stack in a narrow container");
});

test("badge names break at word boundaries and number names keep their digits together; two-column metric values wrap by words", () => {
  const last = selector => {
    const re = new RegExp(`${selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\{([^}]*)\\}`, "g");
    return [...stylesSource.matchAll(re)].map(m => m[1]).at(-1) || "";
  };
  assert.ok(stylesSource.includes(".achievement-name { overflow-wrap: break-word; hyphens: none; }"), "badge names break at word boundaries");
  assert.match(last(".metric-grid:not(.three) strong"), /white-space:\s*normal/);
  assert.ok(russianSource.includes('"Объём 10\\u00A0000"') && russianSource.includes('"Объём 50\\u00A0000"'), "volume badge names keep 10 000 together");
});

test("large text: single-column grids are bounded to the screen, rank names scale instead of breaking, the language row wraps its value", () => {
  assert.ok(/\.profile-hub-panel,[\s\S]*?\.account-identity \{ grid-template-columns: minmax\(0, 1fr\); \}/.test(stylesSource), "grids use minmax(0, 1fr)");
  assert.ok(stylesSource.includes(".solo-identity-row h2 { font-size: min(1.375rem, 8vw);"), "solo rank title scales with the width");
  assert.ok(stylesSource.includes(".rank-hero.hero-panel .rank-hero-title { font-size: min(1.75rem, 5.6vw);"), "rank hero title scales with the width");
  assert.ok(stylesSource.includes(".settings-language .settings-row { flex-wrap: wrap;"), "language value drops under the label");
});

test("large text: row titles scale, three-tile and period rows reflow, bar rows keep their label column readable", () => {
  assert.ok(stylesSource.includes(".settings-row-text strong { font-size: min(1rem, 6vw); }"));
  assert.ok(stylesSource.includes(".metric-grid.three { grid-template-columns: repeat(auto-fit, minmax(min(100%, 5.5rem), 1fr)); }"));
  assert.ok(stylesSource.includes(".period-tabs { grid-template-columns: repeat(auto-fit, minmax(min(100%, 5.5rem), 1fr)); }"));
  assert.ok(stylesSource.includes(".bar-row { grid-template-columns: minmax(min-content, 5.75rem) minmax(0, 1fr); }"));
});
