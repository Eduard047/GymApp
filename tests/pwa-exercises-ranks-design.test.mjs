import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, russianSource, stateContractSource, progressionRulesSource, stylesSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8"),
  readFile("pwa/styles.css", "utf8")
]);

function createStorage() {
  const values = new Map();
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
}

function loadPwaContext(language = "en") {
  const localStorage = createStorage();
  const sessionStorage = createStorage();
  const context = {
    console, Date, Map, Set, TextEncoder, URL, URLSearchParams,
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {},
      sessionStorage
    },
    document: {
      documentElement: { lang: "en" },
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: {},
    localStorage,
    sessionStorage,
    requestAnimationFrame: callback => callback(),
    clearTimeout, setTimeout, clearInterval, setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests"))
  };
  context.window.document = context.document;
  context.window.navigator = context.navigator;
  context.window.localStorage = localStorage;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(progressionRulesSource, context);
  context.window.GymProgressionRules = context.GymProgressionRules;
  vm.runInContext(russianSource, context);
  vm.runInContext(appSource, context);
  vm.runInContext(`state.language = ${JSON.stringify(language)}`, context);
  return context;
}

function run(context, code) {
  return vm.runInContext(code, context);
}

test("Exercises header carries a compact circular add icon button instead of a full-width button", () => {
  const context = loadPwaContext();
  const screen = run(context, "exercisesScreen()");
  assert.match(screen, /<button class="exercise-add-button" data-action="open-exercise-add" aria-label="[^"]+">/);
  assert.doesNotMatch(screen, /button full exercise-add-button/);
  assert.match(stylesSource, /\.exercise-add-button\s*\{[\s\S]*?width:\s*44px;[\s\S]*?height:\s*44px;[\s\S]*?border-radius:\s*50%;[\s\S]*?background:\s*var\(--brand-fill\)/);
  assert.match(screen, /reset-exercise-filters|exercise-row/);
});

test("filter trigger counts only favorites, category and sort and shows a dot only when customized", () => {
  const context = loadPwaContext();
  const trigger = () => run(context, "exerciseFilterControls()");
  let markup = trigger();
  assert.match(markup, /aria-label="Filters, 0 active"/);
  assert.doesNotMatch(markup, /exercise-filter-dot/);
  assert.doesNotMatch(markup, /class="exercise-filter-trigger active"/);
  assert.match(markup, /aria-haspopup="menu" aria-expanded="false"/);
  assert.doesNotMatch(markup, /role="menu"/);

  run(context, 'exerciseMuscleFilter = "chest"');
  markup = trigger();
  assert.match(markup, /aria-label="Filters, 0 active"/);
  assert.doesNotMatch(markup, /exercise-filter-dot/);
  run(context, 'exerciseMuscleFilter = "all"');

  run(context, "exerciseFavoritesOnly = true");
  markup = trigger();
  assert.match(markup, /aria-label="Filters, 1 active"/);
  assert.match(markup, /exercise-filter-trigger active/);
  assert.match(markup, /<span class="exercise-filter-dot" aria-hidden="true">/);

  run(context, 'exerciseBodyFilter = "upper"; exerciseSortMode = "most"');
  assert.match(trigger(), /aria-label="Filters, 3 active"/);
});

test("filter menu holds Favorites, Category and Sort and localizes the favorites word for Russian", () => {
  const english = loadPwaContext("en");
  run(english, "exerciseFilterMenuOpen = true; exerciseBodyFilter = 'core'");
  const markup = run(english, "exerciseFilterControls()");
  assert.match(markup, /role="menu"/);
  assert.match(markup, /role="menuitemcheckbox" aria-checked="false" data-action="exercise-favorites-filter"/);
  assert.match(markup, /Favorites/);
  assert.match(markup, />Category</);
  assert.match(markup, />Sort</);
  assert.match(markup, /role="menuitemradio" aria-checked="true" data-action="exercise-body-filter" data-filter="core"/);
  assert.equal((markup.match(/data-action="exercise-sort"/g) || []).length, 3);
  assert.equal((markup.match(/data-action="exercise-body-filter"/g) || []).length, 4);

  const russian = loadPwaContext("ru");
  run(russian, "exerciseFilterMenuOpen = true");
  const russianMarkup = run(russian, "exerciseFilterControls()");
  assert.match(russianMarkup, />Избранное</);
  assert.match(russianMarkup, />Категория</);
  assert.match(russianMarkup, />Сортировка</);
});

test("muscle chips are the single visible chip row and work without a modal", async () => {
  const context = loadPwaContext();
  const markup = run(context, "exerciseFilterControls()");
  assert.match(markup, /class="filter-scroll exercise-muscle-chips" role="group" aria-label="Primary exercise filters"/);
  assert.match(markup, /data-action="exercise-muscle-filter" data-filter="all"/);
  assert.doesNotMatch(markup, /favorite-filter/);
  assert.doesNotMatch(markup, /data-action="exercise-body-filter"/);

  run(context, "render = () => true; modal = null; exerciseFilterMenuOpen = false;");
  await run(context, `handleAction("exercise-muscle-filter", { dataset: { action: "exercise-muscle-filter", filter: "chest" } })`);
  assert.equal(run(context, "exerciseMuscleFilter"), "chest");
  await run(context, `handleAction("exercise-muscle-filter", { dataset: { action: "exercise-muscle-filter", filter: "all" } })`);
  assert.equal(run(context, "exerciseMuscleFilter"), "all");

  assert.match(stylesSource, /\.exercise-muscle-chips \.chip\s*\{[\s\S]*?background:\s*var\(--surface-2\);[\s\S]*?font-weight:\s*400;/);
  assert.match(stylesSource, /\.exercise-muscle-chips \.chip\.selected\s*\{[\s\S]*?background:\s*var\(--brand-fill\);[\s\S]*?font-weight:\s*600;/);
});

test("choosing a menu item applies the filter, closes the menu and Escape/outside dismissal is wired", async () => {
  const context = loadPwaContext();
  run(context, "render = () => true; modal = null; exerciseFilterMenuOpen = true;");
  await run(context, `handleAction("exercise-favorites-filter", { dataset: {} })`);
  assert.equal(run(context, "exerciseFavoritesOnly"), true);
  assert.equal(run(context, "exerciseFilterMenuOpen"), false);
  run(context, "exerciseFilterMenuOpen = true;");
  await run(context, `handleAction("exercise-sort", { dataset: { sort: "least" } })`);
  assert.equal(run(context, "exerciseSortMode"), "least");
  assert.equal(run(context, "exerciseFilterMenuOpen"), false);
  assert.match(appSource, /if \(event\.key === "Escape"\) dismissExerciseFilterMenu\(true\);/);
  assert.match(appSource, /closest\?\.\("\.exercise-filter-menu-wrap"\)/);
});

test("exercise rows are one compact line with thumbnail, name, heart and More only", () => {
  const context = loadPwaContext();
  const row = run(context, "exerciseRow(state.exercises[0])");
  assert.match(row, /exercise-media-thumb compact exercise-list-thumb/);
  assert.match(row, /<h3 class="exercise-name">/);
  assert.match(row, /data-action="toggle-exercise-favorite"[^>]*aria-pressed="false"/);
  assert.match(row, /data-action="open-exercise-more"[^>]*aria-haspopup="dialog"/);
  assert.doesNotMatch(row, /class="pill"|exercise-metrics|exercise-card-actions|data-action="exercise-history"/);
  assert.equal((row.match(/<button/g) || []).length, 3);
  assert.match(stylesSource, /\.exercise-media-thumb\.exercise-list-thumb\s*\{[\s\S]*?width:\s*60px;[\s\S]*?height:\s*60px;/);
  assert.match(stylesSource, /\.exercise-list-thumb \.exercise-media-play\s*\{[\s\S]*?width:\s*20px;[\s\S]*?height:\s*20px;/);
  assert.match(stylesSource, /\.exercise-row \.exercise-name\s*\{[\s\S]*?-webkit-line-clamp:\s*2;/);
  assert.match(stylesSource, /\.exercise-row-actions\s*\{[\s\S]*?gap:\s*0;/);
});

test("More sheet holds History, Muscle groups, Machine weights, Rename for custom exercises only, and Delete", () => {
  const context = loadPwaContext();
  run(context, `state.exercises.push({ id: 987654, name: "My Custom Lift" })`);
  const builtInId = run(context, "state.exercises.find(exercise => builtInExerciseFor(exercise)).id");
  const builtIn = run(context, `exerciseMoreSheetMarkup(${builtInId})`);
  const custom = run(context, "exerciseMoreSheetMarkup(987654)");
  for (const action of ["exercise-history", "map-exercise", "configure-load-profile", "delete-exercise"]) {
    assert.match(builtIn, new RegExp(`data-action="${action}"`));
    assert.match(custom, new RegExp(`data-action="${action}"`));
  }
  assert.doesNotMatch(builtIn, /data-action="rename-exercise"/);
  assert.match(custom, /data-action="rename-exercise"/);
});

test("Ranks hero states the XP still needed with the next rank name and hides the caption at max rank", () => {
  for (const [language, pattern, level] of [
    ["en", /XP to [A-Z][^<]+<\/p>/, /Level 1 · 100 XP/],
    ["uk", /XP до «[^»]+»/, /Рівень 1 · 100 XP/],
    ["ru", /XP до «Начинающий»/, /Уровень 1 · 100 XP/]
  ]) {
    const context = loadPwaContext(language);
    run(context, "totalXp = () => 100");
    const screen = run(context, "ranksScreen()");
    assert.match(screen, /<h2 class="rank-hero-title">/);
    assert.match(screen, level);
    assert.match(screen, pattern);
    assert.doesNotMatch(screen, /Next: |Наступний ранг|Поточний ранг:/);
    assert.match(screen, /<p class="rank-hero-caption">/);
  }
  const maxed = loadPwaContext("en");
  run(maxed, "totalXp = () => 100000000");
  const screen = run(maxed, "ranksScreen()");
  assert.doesNotMatch(screen, /rank-hero-caption|rank-hero-track|rank-row-track/);
  assert.match(stylesSource, /\.rank-hero \.rank-hero-track\s*\{[\s\S]*?rgba\(255, 255, 255, 0\.25\)/);
});

test("Ranks ladder is one list with one progress bar on the next rank and a current row without a pill", () => {
  const context = loadPwaContext("en");
  run(context, "totalXp = () => 100");
  const screen = run(context, "ranksScreen()");
  assert.equal((screen.match(/<ul class="rank-ladder" role="list"/g) || []).length, 1);
  assert.equal((screen.match(/<li class="rank-row/g) || []).length, 35);
  assert.equal((screen.match(/rank-row-track/g) || []).length, 1);
  assert.equal((screen.match(/aria-current="true"/g) || []).length, 1);
  assert.match(screen, /rank-row current unlocked" role="listitem" aria-current="true"/);
  assert.doesNotMatch(screen, /class="pill"/);
  assert.match(screen, /<span class="sr-only">, Current<\/span>/);
  assert.match(screen, /Level 3 · from [\d,.   ]+ XP/);
  assert.match(screen, /<span class="rank-remaining">[\d,.   ]+ XP to go<\/span>/);
  const nextRow = screen.match(/<li class="rank-row [^>]*>(?:(?!<\/li>)[\s\S])*rank-row-track[\s\S]*?<\/li>/)[0];
  assert.match(nextRow, /Starter/);
  assert.match(nextRow, /rank-icon[^>]*>[\s\S]*?<\/span>/);
  assert.equal((screen.match(/M6 11h12v10H6z/g) || []).length, 34);
});

test("Russian rank names follow the cross-client catalog, including Warborn", () => {
  const context = loadPwaContext("ru");
  const titles = JSON.parse(run(context, "JSON.stringify(rankDefinitions.map(rank => [rank.id, rank.titleRu]))"));
  assert.equal(titles.length, 35);
  assert.equal(titles.find(([id]) => id === "warborn")[1], "Рождённый воином");
  assert.equal(titles.find(([id]) => id === "cosmic-warlord")[1], "Космический воевода");
  assert.equal(titles.find(([id]) => id === "rookie")[1], "Новичок");
  run(context, "totalXp = () => 100000000");
  assert.equal(run(context, "rankTitle()"), "Космический воевода");
  assert.match(run(context, "ranksScreen()"), /Рождённый воином/);
  assert.equal(context.window.GymRussianText.translate("Warborn"), "Рождённый воином");
});

test("iOS wording: short Rename/Delete labels and heart labels that name the exercise", () => {
  for (const [language, rename, del, add] of [
    ["en", ">Rename<", ">Delete<", /aria-label="Add My Custom Lift to favorites"/],
    ["uk", ">Перейменувати<", ">Видалити<", /aria-label="Додати «My Custom Lift» до улюблених"/],
    ["ru", ">Переименовать<", ">Удалить<", /aria-label="Добавить «My Custom Lift» в избранное"/]
  ]) {
    const context = loadPwaContext(language);
    run(context, `state.exercises.push({ id: 987654, name: "My Custom Lift" })`);
    const sheet = run(context, "exerciseMoreSheetMarkup(987654)");
    assert.ok(sheet.includes(rename), `${language} rename`);
    assert.ok(sheet.includes(del), `${language} delete`);
    assert.doesNotMatch(sheet, /Rename exercise|Delete exercise|Переименовать упражнение|Удалить упражнение/);
    const row = run(context, "exerciseRow(state.exercises.find(exercise => exercise.id === 987654))");
    assert.match(row, add);
  }
  const context = loadPwaContext("ru");
  run(context, `state.exercises.push({ id: 987655, name: "My Custom Lift", favorite: true })`);
  const row = run(context, "exerciseRow(state.exercises.find(exercise => exercise.id === 987655))");
  assert.match(row, /aria-label="Удалить «My Custom Lift» из избранного"/);
});

test("filter trigger is an outline circle when inactive and filled when active", () => {
  assert.match(stylesSource, /\.exercise-filter-trigger\s*\{[\s\S]*?border:\s*1\.5px solid var\(--outline-variant\);[\s\S]*?border-radius:\s*50%;/);
  assert.match(stylesSource, /\.exercise-filter-trigger\.active\s*\{[\s\S]*?background:\s*var\(--brand-fill\);/);
});

test("training settings summary wraps instead of forcing its container wider", () => {
  assert.match(stylesSource, /\.training-settings-summary span\s*\{[\s\S]*?min-width:\s*0;[\s\S]*?white-space:\s*normal;[\s\S]*?-webkit-line-clamp:\s*2;/);
  assert.match(stylesSource, /\.training-settings-summary\s*\{[\s\S]*?min-width:\s*0;[\s\S]*?max-width:\s*100%;/);
  assert.match(stylesSource, /\.activation-options-content\s*\{[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\);/);
  assert.match(stylesSource, /\.training-settings-summary strong \{ flex: none;/);
});

test("first-plan metric labels grow to two lines instead of being clipped", () => {
  const labelRule = stylesSource.match(/\.focus-lens-plan-metrics span\s*\{[^}]*-webkit-line-clamp: 2;[^}]*\}/)?.[0] || "";
  assert.ok(labelRule, "label rule with two-line clamp");
  assert.doesNotMatch(labelRule, /max-height/);
});
