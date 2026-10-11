import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource, russianSource, progressionRulesSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8")
]);

function loadPwaContext() {
  const values = new Map();
  const localStorage = {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
  const context = {
    console, Date, Map, Set, TextEncoder, URL, URLSearchParams,
    window: { location: { search: "?access_token=test", hash: "", replace() {} }, addEventListener() {} },
    document: {
      documentElement: { lang: "en" },
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: {},
    localStorage,
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
  return context;
}

const context = loadPwaContext();

function title(language, cadence, family, goal) {
  context.__language = language;
  return vm.runInContext(`(() => {
    state = { ...defaultAppState(), language: __language };
    return missionCountedTitle({ family: ${JSON.stringify(family)}, goal: ${goal} }, ${JSON.stringify(cadence)});
  })()`, context);
}

test("ru and uk mission titles on workout screens use the right plural form", () => {
  const ru = (cadence, family) => [1, 2, 5, 21].map(goal => title("ru", cadence, family, goal));
  const uk = (cadence, family) => [1, 2, 5, 21].map(goal => title("uk", cadence, family, goal));
  assert.deepEqual(ru("weekly", "workouts"), ["1 тренировка за неделю", "2 тренировки за неделю", "5 тренировок за неделю", "21 тренировка за неделю"]);
  assert.deepEqual(ru("monthly", "workouts"), ["1 тренировка за месяц", "2 тренировки за месяц", "5 тренировок за месяц", "21 тренировка за месяц"]);
  assert.deepEqual(ru("weekly", "sets"), ["1 подход за неделю", "2 подхода за неделю", "5 подходов за неделю", "21 подход за неделю"]);
  assert.deepEqual(uk("weekly", "sets"), ["Тиждень на 1 підхід", "Тиждень на 2 підходи", "Тиждень на 5 підходів", "Тиждень на 21 підхід"]);
  assert.deepEqual(uk("monthly", "sets"), ["Місяць на 1 підхід", "Місяць на 2 підходи", "Місяць на 5 підходів", "Місяць на 21 підхід"]);
  assert.deepEqual(ru("daily", "sets"), ["Цель: 1 подход", "Цель: 2 подхода", "Цель: 5 подходов", "Цель: 21 подход"]);
  assert.deepEqual(uk("daily", "sets"), ["Ціль: 1 підхід", "Ціль: 2 підходи", "Ціль: 5 підходів", "Ціль: 21 підхід"]);
  assert.deepEqual(ru("daily", "exercises"), ["1 упражнение сегодня", "2 упражнения сегодня", "5 упражнений сегодня", "21 упражнение сегодня"]);
  assert.deepEqual(ru("weekly", "exercises"), ["1 упражнение за неделю", "2 упражнения за неделю", "5 упражнений за неделю", "21 упражнение за неделю"]);
  assert.deepEqual(uk("weekly", "exercises"), ["1 вправа за тиждень", "2 вправи за тиждень", "5 вправ за тиждень", "21 вправа за тиждень"]);
  assert.deepEqual(uk("monthly", "exercises"), ["1 вправа за місяць", "2 вправи за місяць", "5 вправ за місяць", "21 вправа за місяць"]);
  assert.deepEqual(ru("weekly", "active-days"), ["1 активный день", "2 активных дня", "5 активных дней", "21 активный день"]);
  assert.deepEqual(ru("monthly", "max-session-sets"), ["Лучшая сессия: 1 подход", "Лучшая сессия: 2 подхода", "Лучшая сессия: 5 подходов", "Лучшая сессия: 21 подход"]);
  assert.deepEqual(ru("monthly", "max-session-exercises"), ["Лучшая сессия: 1 упражнение", "Лучшая сессия: 2 упражнения", "Лучшая сессия: 5 упражнений", "Лучшая сессия: 21 упражнение"]);
  // English and label-style titles keep the catalog text.
  assert.equal(title("en", "weekly", "sets", 2), null);
  assert.equal(title("uk", "weekly", "workouts", 2), null);
});

test("mission() builds the localized counted title and keeps English unchanged", () => {
  context.__language = "ru";
  const ruTitle = vm.runInContext(`(() => {
    state = { ...defaultAppState(), language: __language };
    const template = weeklyMissionCatalog().find(item => item.family === "workouts" && item.goal === 2);
    return mission(template, "weekly", weeklyMissionStats([]), []).title;
  })()`, context);
  assert.equal(ruTitle, "2 тренировки за неделю");
  context.__language = "en";
  const enTitle = vm.runInContext(`(() => {
    state = { ...defaultAppState(), language: __language };
    const template = weeklyMissionCatalog().find(item => item.family === "workouts" && item.goal === 2);
    return mission(template, "weekly", weeklyMissionStats([]), []).title;
  })()`, context);
  assert.equal(enTitle, "2-workout week");
});

test("active workout progress label uses the genitive after из/із", () => {
  const label = (language, completed, total) => {
    context.__language = language;
    return vm.runInContext(`(() => { state = { ...defaultAppState(), language: __language }; return activeWorkoutProgressLabel(${completed}, ${total}); })()`, context);
  };
  assert.deepEqual([1, 2, 5, 21].map(total => label("ru", 1, total)), ["Выполнено 1 из 1 подхода", "Выполнено 1 из 2 подходов", "Выполнено 1 из 5 подходов", "Выполнено 1 из 21 подхода"]);
  assert.deepEqual([1, 2, 5, 21].map(total => label("uk", 1, total)), ["Виконано 1 із 1 підходу", "Виконано 1 із 2 підходів", "Виконано 1 із 5 підходів", "Виконано 1 із 21 підходу"]);
  assert.equal(label("en", 1, 2), "Completed 1 of 2 sets");
});

test("plan header pill counts exercises with the right plural", () => {
  const pill = (language, selected) => {
    context.__language = language;
    return vm.runInContext(`(() => { state = { ...defaultAppState(), language: __language }; return exerciseBuilderHeadingMarkup({}, ${selected}, 5); })()`, context);
  };
  assert.match(pill("ru", 2), /2 упражнения · 5 подходов/);
  assert.match(pill("ru", 21), /21 упражнение · 5 подходов/);
  assert.match(pill("uk", 5), /5 вправ · 5 підходів/);
  assert.match(pill("en", 1), /1 exercise · 5 sets/);
});
