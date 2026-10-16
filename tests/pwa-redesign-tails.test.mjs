import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [
  appSource, appBundle, stateContractSource, progressionSource, russianSource,
  confirmedHtml, confirmedCss, confirmedBundle, workoutHtml, landingCss, landingBundle,
  worker
] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/app.v137.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/confirmed.html", "utf8"),
  readFile("pwa/confirmed.css", "utf8"),
  readFile("pwa/confirmed.v59.css", "utf8"),
  readFile("pwa/workout/index.html", "utf8"),
  readFile("pwa/workout/landing.css", "utf8"),
  readFile("pwa/workout/landing.v3.css", "utf8"),
  readFile("pwa/sw.js", "utf8")
]);

const pages = [
  ["confirmed", confirmedCss],
  ["workout landing", landingCss]
];

function declarations(css, property) {
  return [...css.matchAll(new RegExp(`(?:^|[\\s{;])${property}\\s*:\\s*([^;}]+)`, "g"))].map(match => match[1].trim());
}

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
  vm.runInContext(appSource, sandbox);
  return sandbox;
}

test("the confirmation and workout pages use only the DESIGN radius tokens", () => {
  for (const [name, css] of pages) {
    const radii = declarations(css, "border-radius");
    assert.ok(radii.length > 0, name);
    for (const value of radii) {
      assert.match(value, /^var\(--radius-(?:xs|control|compact|panel|capsule)\)$/, `${name}: ${value}`);
    }
    const tokens = Object.fromEntries(
      [...css.matchAll(/--radius-(xs|control|compact|panel|capsule):\s*(\d+)px/g)].map(match => [match[1], Number(match[2])])
    );
    for (const [token, px] of Object.entries({ control: 18, panel: 26, capsule: 999 })) {
      assert.equal(tokens[token], px, `${name} --radius-${token}`);
    }
    if (tokens.compact !== undefined) assert.equal(tokens.compact, 20, `${name} --radius-compact`);
    if (tokens.xs !== undefined) assert.equal(tokens.xs, 14, `${name} --radius-xs`);
  }
});

test("the confirmation and workout pages are flat: no shadows, gradients or blur", () => {
  for (const [name, css] of pages) {
    assert.deepEqual(declarations(css, "box-shadow"), [], `${name} box-shadow`);
    assert.doesNotMatch(css, /drop-shadow|text-shadow/, name);
    assert.doesNotMatch(css, /gradient\(/, name);
    assert.doesNotMatch(css, /backdrop-filter/, name);
  }
});

test("the confirmation and workout pages size text in rem and pair controls with focus rings", () => {
  for (const [name, css] of pages) {
    for (const size of declarations(css, "font-size")) {
      assert.doesNotMatch(size, /\d\s*px/, `${name}: ${size}`);
    }
    assert.match(css, /\.button:focus-visible/, name);
    assert.match(css, /@media \(prefers-contrast: more\)/, name);
    assert.match(css, /var\(--radius-capsule\)/, name);
  }
  for (const value of declarations(confirmedCss, "min-height").concat(declarations(landingCss, "min-height"))) {
    assert.doesNotMatch(value, /^(?:[0-9]|[1-3][0-9]|4[0-3])px$/, value);
  }
});

test("the dark palette uses the DESIGN tokens", () => {
  assert.match(landingCss, /--background: #071321;/);
  assert.match(landingCss, /--surface: #0d1d30;/);
  assert.match(landingCss, /--hairline: #263e59;/);
  assert.match(landingCss, /--accent-fill: #2e72d2;/);
  assert.match(confirmedCss, /@media \(prefers-color-scheme: dark\) \{[\s\S]*--background: #071321;[\s\S]*--surface: #0d1d30;/);
  assert.match(confirmedCss, /:root \{[\s\S]*?--background: #f7faff;[\s\S]*?--surface: #ffffff;/);
  assert.match(confirmedCss, /html\.frame-pending body \{ visibility: hidden !important; \}/);
  assert.match(landingCss, /html\.frame-pending body \{ visibility: hidden !important; \}/);
});

test("both pages ship their restyled sheets as immutable bundles under the same strict CSP", () => {
  assert.equal(confirmedBundle, confirmedCss);
  assert.equal(landingBundle, landingCss);
  assert.match(confirmedHtml, /href="\.\/confirmed\.v59\.css"/);
  assert.match(workoutHtml, /href="\.\/landing\.v3\.css"/);
  assert.match(confirmedHtml, /style-src 'self'/);
  assert.match(workoutHtml, /style-src 'self'/);
  for (const html of [confirmedHtml, workoutHtml]) {
    assert.doesNotMatch(html, /<style\b|\sstyle=|unsafe-inline/);
  }
  assert.match(worker, /"\.\/confirmed\.v59\.css"/);
  assert.match(worker, /"\.\/workout\/landing\.v3\.css"/);
  assert.doesNotMatch(worker, /confirmed\.v56\.css|landing\.v2\.css/);
});

test("the onboarding coach is left out of the render while a sheet is open and returns afterwards", () => {
  assert.equal(appBundle, appSource);
  assert.match(appSource, /\$\{onboardingCoachVisible\(\) \? onboardingTourMarkup\(\) : ""\}/);
  assert.doesNotMatch(appSource, /\$\{onboardingTour \? onboardingTourMarkup\(\) : ""\}/);

  const sandbox = context();
  const result = JSON.parse(JSON.stringify(vm.runInContext(`(() => {
    globalThis.history = window.history;
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    activeWorkout = null;
    pendingSharedWorkout = null;
    onboardingTour = null;
    modal = null;
    const started = initializeOnboardingTour(true);
    const stepBefore = onboardingTour.stepIndex;
    const withoutSheet = onboardingCoachVisible();
    modal = { type: "language" };
    const withSheet = onboardingCoachVisible();
    const tourKept = Boolean(onboardingTour) && onboardingTour.stepIndex === stepBefore;
    modal = null;
    const afterClose = onboardingCoachVisible();
    const markup = onboardingTourMarkup();
    onboardingTour = null;
    const noTour = onboardingCoachVisible();
    return { started, withoutSheet, withSheet, tourKept, afterClose, noTour, hasCoach: markup.includes("onboarding-coach") };
  })()`, sandbox)));

  assert.deepEqual(result, {
    started: true,
    withoutSheet: true,
    withSheet: false,
    tourKept: true,
    afterClose: true,
    noTour: false,
    hasCoach: true
  });
});
