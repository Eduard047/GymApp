import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource, progressionSource, russianSource, stylesSource] =
  await Promise.all([
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
  const app = {
    innerHTML: "",
    children: [],
    querySelectorAll: () => [],
    querySelector: () => null
  };
  const document = {
    documentElement: { lang: "en" },
    visibilityState: "visible",
    activeElement: null,
    querySelector: selector => selector === "#app" ? app : null,
    addEventListener() {}
  };
  const sandbox = {
    console,
    Date,
    Intl,
    Map,
    Set,
    TextEncoder,
    URL,
    URLSearchParams,
    crypto: webcrypto,
    document,
    navigator: {},
    localStorage,
    sessionStorage,
    requestAnimationFrame: callback => callback(),
    clearTimeout,
    setTimeout,
    clearInterval,
    setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests")),
    window: {
      location: { search: "?access_token=test", hash: "", pathname: "/", replace() {} },
      history: { replaceState() {}, pushState() {}, state: null },
      crypto: webcrypto,
      localStorage,
      sessionStorage,
      document,
      navigator: {},
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

function plain(value) {
  return JSON.parse(JSON.stringify(value));
}

test("PWA calendar date helpers render localized weekdays in EN, UK, and RU", () => {
  const sandbox = context();
  const timestamp = Date.UTC(2026, 7, 13, 12, 0, 0);
  for (const [language, locale] of [["en", "en-US"], ["uk", "uk-UA"], ["ru", "ru-RU"]]) {
    const formatted = vm.runInContext(`state.language = ${JSON.stringify(language)}; fmtDate(${timestamp})`, sandbox);
    const expected = new Intl.DateTimeFormat(locale, {
      weekday: "short", month: "short", day: "numeric", year: "numeric"
    }).format(new Date(timestamp));
    assert.equal(formatted, expected, language);
    assert.equal(new Intl.DateTimeFormat(locale, {
      weekday: "short", month: "short", day: "numeric", year: "numeric"
    }).formatToParts(new Date(timestamp)).some(part => part.type === "weekday"), true);

    const social = vm.runInContext(`socialDayLabel("2026-08-13")`, sandbox);
    const expectedSocial = new Intl.DateTimeFormat(locale, {
      weekday: "short", year: "numeric", month: "short", day: "numeric", timeZone: "UTC"
    }).format(new Date("2026-08-13T12:00:00.000Z"));
    assert.equal(social, expectedSocial, `${language} friend UTC day`);
  }
});

test("all PWA workout, friend, template, record, and progress calendar surfaces use weekday formatters", () => {
  assert.match(appSource, /workout-title[^\n]+fmtDate\(session\.startedAt\)/);
  assert.match(appSource, /workout-detail-hero[^\n]+fmtDate\(session\.startedAt\)/);
  assert.match(appSource, /summary-hero[^\n]+fmtDate\(session\.startedAt\)/);
  assert.match(appSource, /modal\.type === "template"[^\n]+fmtDate\(session\.startedAt\)/);
  assert.match(appSource, /friend-workout-history-row[^\n]+socialDayLabel\(workout\.workoutDay\)/);
  assert.match(appSource, /friend-record-row[^\n]+socialDayLabel\(record\.lastWorkoutDay\)/);
  assert.match(appSource, /friend-workout-detail[^\n]+socialDayLabel\(workout\.workoutDay\)/);
  assert.match(appSource, /weekday: "long", day: "numeric", month: "long"/);
  assert.match(appSource, /weekday: "narrow", day: "numeric"/);
  assert.match(appSource, /workout-date-weekday[^\n]+fmtDate\(draft\.startedAt, \{ weekday: "long" \}\)/);
  assert.match(appSource, /Exported: \$\{fmtDate\(data\.exportedAt, \{[\s\S]{0,180}weekday: "short"/);

  assert.match(appSource, /fmtDate\(monthDate\(\)\.getTime\(\), \{ month: "long", year: "numeric" \}\)/);
  assert.match(appSource, /Last watch sync[\s\S]{0,300}dateStyle: "medium", timeStyle: "short"/);
  assert.match(appSource, /workout-date-today[^\n]+Today/);
});

test("progress chart labels include a localized narrow weekday within the selected month", () => {
  const sandbox = context();
  const timestamp = Date.UTC(2026, 7, 13, 12, 0, 0);
  for (const [language, locale] of [["en", "en-US"], ["uk", "uk-UA"], ["ru", "ru-RU"]]) {
    const label = vm.runInContext(`(() => {
      state.language = ${JSON.stringify(language)};
      return progressChartPoints([{ session: { startedAt: ${timestamp} }, sets: [{ weight: 40, reps: 8 }] }])[0].label;
    })()`, sandbox);
    const expected = new Intl.DateTimeFormat(locale, {
      weekday: "narrow", day: "numeric"
    }).format(new Date(timestamp));
    assert.equal(label, expected, language);
  }
});

test("Today plan metrics are history-only, finite, bounded, zero-safe, and ordered", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    state.profile = { split: "Upper / Lower", days: 4, goal: "Strength", calories: "Maintenance" };
    state.sessions = [];
    activeWorkout = { id: 99, blocks: [{ sets: [{ weight: 100, reps: 10, completed: true }] }] };
    const empty = todayPlanDashboardMetrics();
    state.sessions = [{ startedAt: Date.now(), sets: [{ weight: Infinity, reps: 10 }] }];
    const malformed = todayPlanDashboardMetrics();
    const many = Array.from({ length: GymStateContract.LIMITS.sessions + 1 }, (_, index) => ({
      id: index + 1, startedAt: Date.now() - index,
      sets: [{ id: index + 1, exerciseName: "Bench Press", weight: 0, reps: 1 }]
    }));
    state.sessions = many;
    const bounded = todayPlanDashboardMetrics();
    state.sessions = [];
    state.language = "en";
    const en = todayPlanMetricsMarkup();
    state.language = "uk";
    const uk = todayPlanMetricsMarkup();
    state.language = "ru";
    const ru = todayPlanMetricsMarkup();
    return {
      empty, malformed, bounded, en, uk, ru,
      nonFinite: boundedTodayMetric(NaN, 10),
      negative: boundedTodayMetric(-1, 10),
      upper: boundedTodayMetric(Number.MAX_SAFE_INTEGER, 1_000_000_000_000_000)
    };
  })()`, sandbox));

  assert.deepEqual(result.empty, { totalWorkouts: 0, weeklyStreak: 0, totalVolume: 0 });
  assert.equal(result.malformed.totalVolume, 0);
  assert.equal(result.bounded.totalWorkouts, 5000);
  assert.equal(result.nonFinite, 0);
  assert.equal(result.negative, 0);
  assert.equal(result.upper, 1_000_000_000_000_000);

  for (const [markup, labels] of [
    [result.en, ["Total workouts", "Week streak", "Total volume"]],
    [result.uk, ["Усього тренувань", "Серія тижнів", "Загальний обсяг"]],
    [result.ru, ["Всего тренировок", "Серия недель", "Общий объём"]]
  ]) {
    let cursor = -1;
    for (const label of labels) {
      const next = markup.indexOf(label);
      assert.ok(next > cursor, `${label} is visible in canonical order`);
      cursor = next;
    }
    assert.equal((markup.match(/<strong>0<\/strong>/g) || []).length, 3);
  }
});

test("Today keeps only exact-plan metrics while global progress metrics live in Progress", () => {
  assert.match(stylesSource, /\.focus-lens-plan-metrics \{[\s\S]*grid-template-columns: repeat\(3, minmax\(0, 1fr\)\)/);
  assert.match(stylesSource, /\.focus-lens-plan-metrics strong \{[\s\S]*white-space: nowrap/);
  assert.match(stylesSource, /\.focus-lens-plan-metrics span \{[\s\S]*font-size: 11px[\s\S]*-webkit-line-clamp: 2/);
  const focus = appSource.indexOf("function focusLensCard(");
  const metrics = appSource.indexOf("smartPlanMetricsMarkup(launch.plan)", focus);
  const actions = appSource.indexOf("focus-lens-actions plan-actions", metrics);
  const progress = appSource.indexOf("function progressScreen()");
  const progressEnd = appSource.indexOf("function exerciseProgressPanel()", progress);
  assert.ok(focus >= 0 && focus < metrics && metrics < actions);
  assert.doesNotMatch(appSource.slice(focus, actions), /todayPlanMetricsMarkup|Weekly rhythm/);
  assert.match(appSource.slice(progress, progressEnd), /overviewCards\(selectedMonthSessions\(\)\)/);
});
