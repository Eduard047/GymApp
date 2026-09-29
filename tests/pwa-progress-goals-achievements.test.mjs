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
  vm.runInContext(appSource, sandbox);
  return sandbox;
}

function progressPanel(language, withSessions) {
  const sandbox = context();
  return vm.runInContext(`(() => {
    state = {
      ...defaultAppState(),
      language: ${JSON.stringify(language)},
      exercises: [{ id: 1, name: "Bench Press" }],
      mappings: {},
      progressExerciseId: 1,
      sessions: ${withSessions
        ? `[{ id: 1, startedAt: Date.now() - 1000, note: "", exerciseNames: ["Bench Press"], sets: [{ id: 100, exerciseName: "Bench Press", weight: 60, reps: 8, orderIndex: 0 }] }]`
        : "[]"}
    };
    monthOffsets[activeMonthScope()] = 0;
    return exerciseProgressPanel();
  })()`, sandbox);
}

function run(language, code) {
  const sandbox = context();
  return vm.runInContext(`(() => { state = { ...defaultAppState(), language: ${JSON.stringify(language)} }; ${code} })()`, sandbox);
}

test("X1 exercise progress uses the inline month navigator and the card switcher is gone", () => {
  const panel = progressPanel("en", true);
  assert.ok(panel.startsWith('<div class="month-navigator-inline">'));
  assert.equal((panel.match(/month-navigator-inline/g) || []).length, 1);
  assert.doesNotMatch(appSource, /function monthSwitcher|monthSwitcher\(\)/);
  assert.doesNotMatch(stylesSource, /\.month-switcher|\.month-current-button/);
  assert.ok(progressPanel("en", false).startsWith('<div class="month-navigator-inline">'));
});

test("X2 muscle breakdown drops the duplicate exercise name and shows a groups pill", () => {
  const sandbox = context();
  const markup = vm.runInContext(`(() => {
    state = { ...defaultAppState(), language: "ru" };
    const exercise = state.exercises.find(item => item.name === "Bench Press") || state.exercises[0];
    return exerciseMuscleBreakdownCard(exercise, true);
  })()`, sandbox);
  assert.match(markup, /<h3>Распределение по мышцам<\/h3><span class="pill exercise-muscle-groups-pill"><svg[^>]*>.*?<\/svg>\d+ (группа|группы|групп)<\/span>/);
  assert.doesNotMatch(markup, /<p>/);
  assert.match(run("uk", `return countNoun(3, "groups") + "|" + countNoun(5, "groups") + "|" + countNoun(1, "groups");`), /^3 групи\|5 груп\|1 група$/);
  assert.equal(run("en", `return countNoun(1, "groups") + "|" + countNoun(2, "groups");`), "1 group|2 groups");
  assert.equal(run("ru", `return countNoun(2, "groups") + "|" + countNoun(11, "groups");`), "2 группы|11 групп");
  assert.match(appSource, /exerciseMuscleBreakdownCard\(selected, true\)/);
  assert.match(stylesSource, /\.exercise-muscle-breakdown-heading \{[^}]*display: flex;[^}]*flex-wrap: wrap;/);
});

test("X3 a month without data keeps the summary and shows one empty state", () => {
  const empty = progressPanel("en", false);
  assert.match(empty, /Progress Summary/);
  assert.doesNotMatch(empty, /progress-spotlight|trend-panel|Workout History|Visual Trends/);
  assert.match(empty, /progress-month-empty/);
  assert.match(empty, /<h2>No progress this month<\/h2><p>Log sets for the selected exercise to unlock trends\.<\/p>/);
  assert.match(progressPanel("uk", false), /Немає прогресу за цей місяць[\s\S]*Додай підходи для вибраної вправи, щоб відкрити тренди\./);
  assert.match(progressPanel("ru", false), /В этом месяце прогресса пока нет[\s\S]*Запиши подходы выбранного упражнения, чтобы открыть тренды\./);
  const filled = progressPanel("en", true);
  assert.match(filled, /progress-spotlight[\s\S]*trend-panel[\s\S]*<h2>Workout History<\/h2>/);
  assert.doesNotMatch(filled, /progress-month-empty/);
  // spotlight() keeps its own empty branch.
  assert.match(appSource, /Log sets for \$\{displayName\} to unlock trends\./);
});

test("X4 session subtitles use the pluralised noun in every language", () => {
  assert.match(progressPanel("en", true), /<p>1 session in the selected month\.<\/p>/);
  assert.match(progressPanel("en", true), /Last 1 session in the selected month\./);
  assert.match(progressPanel("uk", true), /1 сесія у вибраному місяці\./);
  assert.match(progressPanel("uk", true), /Останні 1 сесія у вибраному місяці\./);
  assert.match(progressPanel("ru", true), /1 сессия в выбранном месяце\./);
  assert.match(progressPanel("ru", true), /Последние 1 сессия в выбранном месяце\./);
  assert.equal(run("ru", `return countNoun(5, "sessions") + "|" + countNoun(3, "sessions");`), "5 сессий|3 сессии");
  assert.equal(run("uk", `return countNoun(5, "sessions") + "|" + countNoun(2, "sessions");`), "5 сесій|2 сесії");
  assert.doesNotMatch(progressPanel("ru", true), /сек\.|тренувань|Останні/);
});

test("Exercise picker card holds thumbnail, name, logged sessions and the picker trigger", () => {
  const panel = progressPanel("en", true);
  assert.match(panel, /<section class="panel progress-exercise-picker"><h2 class="progress-picker-title">Choose an exercise<\/h2><div class="progress-picker-selected">[\s\S]*<button type="button" class="progress-picker-change" data-action="open-progress-exercise-picker"[^>]*aria-label="Change exercise: Bench Press\. 1 logged sessions"[\s\S]*<strong>Bench Press<\/strong><small>1 logged sessions<\/small>/);
  assert.equal((panel.match(/data-action="open-progress-exercise-picker"/g) || []).length, 1);
  assert.doesNotMatch(panel, /SELECTED EXERCISE|ОБРАНА ВПРАВА/);
  assert.match(progressPanel("ru", true), /Записано сессий: 1/);
  assert.match(progressPanel("uk", true), /Записано сесій: 1/);
});

test("G1 the missions hero is one compact tappable row that opens ranks", () => {
  for (const [language, summary, hint] of [
    ["en", /Level 1 · [^<·]+ · 0 XP/, "Opens ranks"],
    ["uk", /Рівень 1 · [^<·]+ · 0 XP/, "Відкриває ранги"],
    ["ru", /Уровень 1 · [^<·]+ · 0 XP/, "Открывает ранги"]
  ]) {
    const screen = run(language, "return missionsScreen();");
    assert.match(screen, /^<div class="settings-panel missions-rank-panel"><button type="button" class="settings-row" data-action="open-ranks" aria-label="/);
    assert.match(screen, summary);
    assert.ok(screen.includes(`. ${hint}"`), language);
    assert.match(screen, /settings-row-icon"><svg[\s\S]*settings-row-trailing" aria-hidden="true"><svg/);
    assert.doesNotMatch(screen, /missions-rank-hero|hero-panel|TOTAL XP|Week streak/);
  }
  assert.doesNotMatch(stylesSource, /missions-rank-hero|missions-rank-head|missions-rank-action/);
  assert.match(stylesSource, /\.missions-rank-panel \.settings-row \{[^}]*min-height: 48px/);
});

test("G2 mission period tabs use short labels and a period tablist name", () => {
  for (const [language, labels, listName] of [
    ["en", ["Day", "Week", "Month"], "Mission period"],
    ["uk", ["День", "Тиждень", "Місяць"], "Період місій"],
    ["ru", ["День", "Неделя", "Месяц"], "Период миссий"]
  ]) {
    const screen = run(language, "return missionsScreen();");
    assert.ok(screen.includes(`role="tablist" aria-label="${listName}"`), language);
    const tabs = [...screen.matchAll(/data-action="mission-period" data-period="[a-z]+"><strong>([^<]+)<\/strong>/g)].map(match => match[1]);
    assert.deepEqual(tabs, labels, language);
    assert.equal((screen.match(/role="tab"/g) || []).length, 3);
    assert.match(screen, /id="mission-tab-daily"[^>]+aria-controls="mission-panel-daily"/);
  }
});

const missionFixture = done => `missionCard({
  done: ${done}, title: "Daily check-in", summary: "Log one workout", cadenceLabel: "Daily",
  progressLabel: "should not render", progress: ${done ? 1 : 0}, target: 1
})`;

test("G3 mission cards show the counter beside the title and the bar under the description", () => {
  const open = run("en", `return ${missionFixture(false)};`);
  assert.match(open, /<div class="mission-card-copy"><h3>Daily check-in<\/h3><p>Log one workout<\/p><\/div><div class="mission-card-counter"><span class="mission-counter">0 \/ 1<\/span><\/div><\/div><div class="progress"><span class="percentage-0"><\/span><\/div><\/article>/);
  assert.doesNotMatch(open, /mission-progress-label|should not render|Completed|\+\d+ XP/);
  const done = run("ru", `return ${missionFixture(true)};`);
  assert.match(done, /mission-counter">1 \/ 1<\/span><span class="pill mission-completed-pill"><svg[^>]*>.*?<\/svg>Выполнено<\/span>/);
  assert.match(done, /class="mission-row highlighted"/);
  assert.match(run("uk", `return ${missionFixture(true)};`), /Виконано<\/span>/);
  assert.match(stylesSource, /\.mission-row \{[^}]*gap: 9px;[^}]*padding: 13px 16px;/);
  assert.doesNotMatch(stylesSource, /mission-progress-label/);
});

test("G4 mission icons stay brand blue and the bar is mint until completed", () => {
  assert.match(stylesSource, /\.mission-card-icon \{[^}]*color: var\(--primary\);/);
  assert.doesNotMatch(stylesSource, /\.mission-card-icon\.complete/);
  assert.match(stylesSource, /\.mission-row \.progress span \{ background: var\(--mint\); \}/);
  assert.match(stylesSource, /\.mission-row\.highlighted \.progress span \{ background: var\(--primary\); \}/);
});

test("A1-A4 achievements render a header, a three column ring grid and tile buttons", () => {
  for (const [language, eyebrow, title, caption, locked] of [
    ["en", "Achievements", "Your badge collection", "Unlocked collection", "Locked"],
    ["uk", "Досягнення", "Твоя колекція відзнак", "Відкрита колекція", "Заблоковано"],
    ["ru", "Достижения", "Твоя коллекция значков", "Открытая коллекция", "Закрыто"]
  ]) {
    const screen = run(language, "return missionsScreen();");
    assert.ok(screen.includes(`<span class="achievements-eyebrow">${eyebrow}</span><h2 id="achievements-title">${title}</h2>`), language);
    assert.ok(screen.includes(`0 / 12</span><span class="achievements-summary-caption">${caption}</span>`), language);
    assert.equal((screen.match(/<button type="button" class="achievement-tile /g) || []).length, 12);
    assert.equal((screen.match(/data-action="open-achievement" data-achievement-id="/g) || []).length, 12);
    assert.match(screen, new RegExp(`aria-label="[^"]+, ${locked}, 0 / 1"`));
    assert.equal((screen.match(/class="achievement-lock"/g) || []).length, 12);
    assert.doesNotMatch(screen, /achievement-card|achievement-medallion|<article class="panel achievement/);
  }
  assert.doesNotMatch(run("en", "return missionsScreen();"), /every badge has a stable|unlock date/i);
  const tile = run("en", "return achievementTileMarkup(achievementDefinitions()[0]);");
  assert.match(tile, /<circle class="achievement-ring-track" cx="30" cy="30" r="28" pathLength="100"\/>/);
  assert.doesNotMatch(tile, /achievement-ring-arc| style=/);
  const unlocked = run("en", `state.sessions = [{ id: 1, startedAt: Date.now(), note: "", exerciseNames: [], sets: [] }];
    return achievementTileMarkup(achievementDefinitions()[0]);`);
  assert.match(unlocked, /class="achievement-tile rarity-common unlocked"/);
  assert.match(unlocked, /<circle class="achievement-ring-arc" cx="30" cy="30" r="28" pathLength="100" stroke-dasharray="100 100" transform="rotate\(-90 30 30\)"\/>/);
  assert.match(unlocked, /aria-label="First Workout, Unlocked, 1 \/ 1"/);
  assert.doesNotMatch(unlocked, /achievement-lock/);
  assert.match(stylesSource, /\.achievement-gallery \{[^}]*repeat\(3, minmax\(0, 1fr\)\)/);
  assert.match(stylesSource, /@media \(max-width: 340px\) \{\s*\.achievement-gallery \{ grid-template-columns: repeat\(2/);
  assert.match(stylesSource, /\.achievement-ring \{[^}]*width: 60px;[^}]*height: 60px;/);
  assert.match(stylesSource, /\.achievement-ring-track,\s*\.achievement-ring-arc \{ fill: none; stroke-width: 4; \}/);
  assert.match(stylesSource, /\.achievement-tile\.locked \.achievement-icon \{[^}]*opacity: 0\.4/);
  assert.match(stylesSource, /\.achievement-tile\.locked \.achievement-name \{ opacity: 0\.55; \}/);
  assert.match(stylesSource, /\.achievement-disc \{[^}]*width: 84px;[^}]*height: 84px;/);
});

test("A4 achievement details open through a modal sheet and unknown ids are ignored", async () => {
  const sandbox = context();
  const result = vm.runInContext(`(async () => {
    state = { ...defaultAppState(), language: "ru" };
    progressHubSection = "goals";
    nav = [{ name: "progress" }];
    const el = id => ({ dataset: { achievementId: id } });
    const opened = await handleAction("open-achievement", el("workout_5"));
    const type = modal && modal.type;
    const id = modal && modal.achievementId;
    const sheet = modalMarkup();
    modal = null;
    const rejected = await handleAction("open-achievement", el("nope"));
    const missing = await handleAction("open-achievement", { dataset: {} });
    return { type, id, sheet, rejected, missing, after: modal, focusable: STABLE_FOCUS_ACTIONS.has("open-achievement"), sheetMissing: achievementSheetMarkup("nope") };
  })()`, sandbox);
  const value = await result;
  assert.equal(value.focusable, true);
  assert.equal(value.sheetMissing, "");
  assert.equal(value.rejected, false);
  assert.equal(value.missing, false);
  assert.equal(value.after, null);
  assert.equal(value.type, "achievement-detail");
  assert.equal(value.id, "workout_5");
  assert.match(value.sheet, /role="dialog"[^>]+aria-labelledby="achievement-sheet-title"/);
  const sheet = run("ru", `return achievementSheetMarkup("workout_5");`);
  assert.match(sheet, /class="achievement-sheet rarity-common locked"/);
  assert.match(sheet, /class="achievement-disc" aria-hidden="true"><svg/);
  assert.match(sheet, /<h2 id="achievement-sheet-title">[^<]+<\/h2>/);
  assert.match(sheet, /class="pill achievement-rarity-pill">[^<]+<\/span>/);
  assert.match(sheet, /<strong class="achievement-sheet-count">0 \/ 5<\/strong>/);
  assert.match(sheet, /achievement-sheet-status"><svg[^>]*>.*?<\/svg>Закрыто<\/p>/);
  assert.doesNotMatch(sheet, /XP|unlock date/i);
  assert.match(run("uk", `return achievementSheetMarkup("workout_5");`), /Заблоковано<\/p>/);
  const missions = run("en", "return missionsScreen();");
  assert.doesNotMatch(missions, /achievement-sheet|role="dialog"/);
  assert.match(appSource, /if \(modal\.type === "achievement-detail"\) \{[\s\S]*bottomSheet\(sheet, "achievement-sheet-title"\)/);
  assert.match(appSource, /"open-achievement"/);
  assert.match(appSource, /"pickerTarget", "name", "achievementId"/);
});

test("Progress picker thumbnail keeps a 76x64 size and a small play badge; mission tabs stay centred", () => {
  assert.match(stylesSource, /\.exercise-media-thumb\.progress \.exercise-media-play \{[^}]*width: 28px;[^}]*height: 28px;/);
  assert.match(stylesSource, /\.progress-picker-selected \.exercise-media-thumb\.progress \{[^}]*width: 76px;[^}]*height: 64px;/);
  assert.match(stylesSource, /\.segmented\.mission-period-tabs button \{[^}]*place-items: center;[^}]*text-align: center;/);
  assert.match(stylesSource, /\.segmented\.mission-period-tabs button\.selected \{[^}]*text-align: center;/);
});
