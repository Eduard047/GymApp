import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource, progressionSource, russianSource, regionsSource, stylesSource] =
  await Promise.all([
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/state-contract.js", "utf8"),
    readFile("pwa/progression-rules.js", "utf8"),
    readFile("pwa/russian-text.js", "utf8"),
    readFile("pwa/muscle-regions.js", "utf8"),
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
    console, Date, Intl, Map, Set, TextEncoder, URL, URLSearchParams,
    crypto: webcrypto, document, navigator: {}, localStorage, sessionStorage,
    requestAnimationFrame: callback => callback(),
    clearTimeout, setTimeout, clearInterval, setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests")),
    window: {
      location: { search: "?access_token=test", hash: "", pathname: "/", replace() {} },
      history: { replaceState() {}, pushState() {}, state: null },
      crypto: webcrypto, localStorage, sessionStorage, document, navigator: {},
      addEventListener() {}
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
  vm.runInContext(regionsSource, sandbox);
  vm.runInContext(appSource, sandbox);
  return sandbox;
}

const run = (language, code) => {
  const sandbox = context();
  return JSON.parse(vm.runInContext(`state.language = ${JSON.stringify(language)}; JSON.stringify((() => { ${code} })())`, sandbox));
};

test("weights follow the interface locale: comma and kg in RU, dot in EN", () => {
  assert.equal(run("ru", "return formatSetWeight(67.5);"), "67,5");
  assert.equal(run("en", "return formatSetWeight(67.5);"), "67.5");
  assert.equal(run("ru", "return formatSetWeight(24);"), "24");
  assert.equal(run("ru", "return formatLocalizedSetWeight(2.5);"), "2,5 кг");
  assert.equal(run("ru", "return formatSetWeightRaw(62.5);"), "62.5");
});

test("the plan weight field shows the locale decimal mark while the draft keeps parsing both marks", () => {
  const markup = run("ru", `
    const block = { exerciseName: "Bench Press", catalogKey: "bench_press", sets: [] };
    return draftSetRowMarkup(block, 0, { weight: "62.5", reps: "8" }, 0, null);`);
  assert.match(markup, /data-field="weight" value="62,5"/);
  assert.equal(run("ru", `return activeStepWeightValue("62,5");`), 62.5);
});

test("machine weights are listed with semicolons and a decimal comma in RU and UK, and parsed back", () => {
  assert.equal(run("ru", "return loadProfileWeightsText([20, 22.5, 25]);"), "20; 22,5; 25");
  assert.equal(run("uk", "return loadProfileWeightsText([20, 22.5]);"), "20; 22,5");
  assert.equal(run("en", "return loadProfileWeightsText([20, 22.5, 25]);"), "20, 22.5, 25");
  assert.deepEqual(run("ru", `return parsedLoadProfileWeights("20; 22,5; 25");`), [20, 22.5, 25]);
  assert.deepEqual(run("ru", `return parsedLoadProfileWeights("20, 22.5");`), [20, 22.5]);
  assert.equal(run("ru", `return parsedLoadProfileWeights("22,5,6");`), null);
  assert.deepEqual(run("en", `return parsedLoadProfileWeights("45,50;55");`), [45, 50, 55]);
  assert.doesNotMatch(appSource, /data-step="2\.5">2\.5 kg<|data-step="5">5 kg</);
});

test("the exercise history table carries the weight unit in the locale format", () => {
  const markup = run("ru", `
    const session = { id: 1, startedAt: Date.UTC(2026, 8, 28, 12) };
    return progressHistoryCard({ session, sets: [{ weight: 24, reps: 10 }, { weight: 22.5, reps: 8 }] });`);
  assert.match(markup, /<span>24 кг<\/span>/);
  assert.match(markup, /<span>22,5 кг<\/span>/);
  assert.doesNotMatch(markup, /24\.0/);
});

test("the Smart Coach set summary keeps each set whole and drops the pipe separators", () => {
  const markup = run("ru", `return smartPanel({ kind: "Progression", loadMode: "Weighted", sets: [{ weight: 67.5, reps: 8 }, { weight: 67.5, reps: 7 }] }, 0);`);
  assert.equal((markup.match(/<span class="smart-set">67,5 кг × \d<\/span>/g) || []).length, 2);
  assert.doesNotMatch(markup, / \| /);
  assert.match(stylesSource, /\.smart-set \{[^}]*white-space: nowrap/);
});

test("store badges and eyebrows are sentence case, not typed in capitals", () => {
  assert.doesNotMatch(appSource, /GET IT ON|AVAILABLE ON|YOUR FIRST PLAN|FIRST WORKOUT|СКАЧАТЬ В|ДОСТУПНО В|ТВОЙ ПЕРВЫЙ|ПЕРВАЯ ТРЕНИРОВКА|ТВІЙ ПЕРШИЙ|ПЕРШЕ ТРЕНУВАННЯ|ЗАВАНТАЖИТИ В/);
  assert.match(appSource, /tx3\("Get it on", "Завантажити в", "Скачать в"\)/);
  assert.match(appSource, /tx3\("Your first plan", "Твій перший план", "Твой первый план"\)/);
  assert.match(appSource, /tx3\("First workout", "Перше тренування", "Первая тренировка"\)/);
});

test("the rank row keeps level and rank on the title line and the XP total as its subtitle", () => {
  const nbsp = " ";
  const screen = run("ru", "return missionsScreen();");
  assert.match(screen, new RegExp(`<strong>Уровень 1${nbsp}·${nbsp}[^<·]+</strong><small>0${nbsp}XP</small>`));
});

test("the comparison card keeps the previous value whole and has no dangling separator", () => {
  assert.match(appSource, /<small><span class="nowrap">\$\{tx3\("Previous", "Раніше", "Раньше"\)\} \$\{amount\(previous\)\}\$\{unitSuffix\}<\/span> <span class="nowrap comparison-delta/);
  assert.doesNotMatch(appSource, /\$\{unitSuffix\} · <span class="nowrap comparison-delta/);
});

test("body map regions announce the localized muscle group, not the English region name", () => {
  const markup = run("ru", `
    const data = muscles.map(([id]) => ({ id, label: muscleLabel(id), load: 100, weight: 1 }));
    return sourceBodyMapSvg(data, 100);`);
  assert.doesNotMatch(markup, /Left |Right |Shoulder|Biceps|Quads/);
  assert.match(markup, /<title>Плечи · 100 нагрузка<\/title>/);
});

test("muscle chips show the value only and expose the unit through the accessible name", () => {
  const markup = run("ru", `return muscleMapSelectionList([{ id: "chest", label: "Грудь", load: 2797 }]);`);
  assert.match(markup, /<small>2 797<\/small>|<small>2 797<\/small>/);
  assert.match(markup, /aria-label="Грудь: 2.797 нагрузка"/);
});

test("metric values on Today fit through the shared fitter", () => {
  assert.match(appSource, /METRIC_TILE_VALUE_SELECTOR = "\.metric-grid strong, \.weekly-summary-metrics strong, \.summary-hero-stats strong"/);
  assert.match(stylesSource, /\.weekly-summary-metrics strong \{[^}]*white-space: nowrap/);
});

test("lifetime tiles reserve a two-line label slot and align values", () => {
  assert.match(stylesSource, /\.lifetime-progress-card \.metric-grid\.tile-emphasized span \{[^}]*min-height: 2\.25rem/);
  assert.match(stylesSource, /\.lifetime-progress-card \.metric-grid\.tile-emphasized strong \{[^}]*margin-top: auto/);
});

test("the screen gutter is the 16px DESIGN gutter on every root screen", () => {
  assert.match(stylesSource, /\n\.screen \{[^}]*padding: 10px 16px;/);
  assert.match(stylesSource, /\.workouts-screen-copy \{[^}]*margin: 10px 16px 12px;/);
  assert.match(stylesSource, /\.workouts-controls \.segmented \{ margin: 0 16px 10px; \}/);
  assert.match(stylesSource, /\.workouts-scroll \{[^}]*padding: 0 16px var\(--bottom-nav-clearance\);/);
  assert.match(stylesSource, /\.screen-leaderboard \{[^}]*padding-right: 16px;[^}]*padding-left: 16px;/);
  assert.match(stylesSource, /\.exercise-builder-heading \{[^}]*padding: 2px 0;/);
});

test("secondary text meets 4.5:1 on tonal fills and no text is set below 11px", () => {
  assert.match(stylesSource, /--muted: #596881;/);
  assert.match(stylesSource, /\.workout-exercise-picker-row \.button\.secondary \{ color: var\(--hero-accent-text\); \}/);
  for (const match of stylesSource.matchAll(/font-size:\s*([\d.]+)(rem|px)/g)) {
    const px = match[2] === "rem" ? Number(match[1]) * 16 : Number(match[1]);
    assert.ok(px >= 11, `font-size ${match[0]} is below 11px`);
  }
});

test("the builder header, search inputs and coach chevron use full 44px targets", () => {
  assert.match(stylesSource, /\.button\.exercise-builder-add,\n\.button\.exercise-builder-voice \{[^}]*width: 44px;/);
  assert.match(stylesSource, /\.exercise-search-field input\[type="search"\] \{[^}]*min-height: 44px;/);
  assert.match(stylesSource, /\.smart-coach-chevron \{[^}]*min-width: 44px;/);
});

test("legal links wrap instead of truncating and the exercise menu Delete is an outline row", () => {
  assert.match(stylesSource, /a\.settings-row \.settings-row-text strong \{[^}]*white-space: normal;/);
  assert.match(stylesSource, /\.account-identity-text span \{[^}]*overflow-wrap: anywhere;/);
  assert.doesNotMatch(stylesSource, /\.account-identity-text span \{[^}]*text-overflow: ellipsis/);
  assert.match(stylesSource, /\.exercise-more-actions \.button\.danger \{[^}]*background: transparent;/);
  assert.match(stylesSource, /\.button\.danger \{\n  color: var\(--on-danger\);\n  background: var\(--danger\);/);
});

test("the feedback panel keeps the 16px panel padding and the desktop Today actions share one width", () => {
  assert.match(stylesSource, /\.panel\.compact\.workout-feedback \{ padding: 16px; \}/);
  assert.match(stylesSource, /\.focus-lens\.completed\.compact \.focus-lens-actions \{ max-width: none; grid-template-columns: minmax\(0, 1fr\); \}/);
  assert.match(stylesSource, /\.screen-workouts \.workouts-screen-copy \{ padding-inline: 16px; \}/);
});
