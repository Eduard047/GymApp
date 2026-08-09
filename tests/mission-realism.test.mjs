import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [
  appSource,
  stateContractSource,
  russianSource,
  progressionRulesSource,
  androidMissionsScreenSource,
  androidPostWorkoutScreenSource,
  androidWorkoutListViewModelSource,
  androidAdaptiveMissionBoardSource,
  androidPostWorkoutViewModelSource
] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/MissionsScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/PostWorkoutSummaryScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/WorkoutListViewModel.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/AdaptiveMissionBoard.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/PostWorkoutSummaryViewModel.kt", "utf8")
]);

function loadPwaContext() {
  const values = new Map();
  const localStorage = {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
  const context = {
    console,
    Date,
    Map,
    Set,
    TextEncoder,
    URL,
    URLSearchParams,
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {}
    },
    document: {
      documentElement: { lang: "en" },
      querySelector() {
        return { innerHTML: "", querySelectorAll: () => [], querySelector: () => null };
      }
    },
    navigator: {},
    localStorage,
    requestAnimationFrame: callback => callback(),
    clearTimeout,
    setTimeout,
    clearInterval,
    setInterval,
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

test("mission board stays focused and has attainable cold-start targets", () => {
  const context = loadPwaContext();
  vm.runInContext("state = { ...defaultAppState(), sessions: [] }", context);

  const counts = JSON.parse(vm.runInContext("JSON.stringify(Object.fromEntries(Object.entries(missionGroups()).map(([key, value]) => [key, value.length])))", context));
  assert.deepEqual(counts, { daily: 3, weekly: 3, monthly: 2 });
  assert.equal(vm.runInContext('missionTargetForFamily("daily", "exercises", {})', context), 3);
  assert.equal(vm.runInContext('missionTargetForFamily("daily", "sets", {})', context), 8);
  assert.equal(vm.runInContext('missionTargetForFamily("weekly", "workouts", {})', context), 3);
  assert.equal(vm.runInContext('missionTargetForFamily("weekly", "active-days", {})', context), 2);
  assert.equal(vm.runInContext('missionTargetForFamily("weekly", "sets", {})', context), 24);
  assert.equal(vm.runInContext('missionTargetForFamily("weekly", "volume", {})', context), 7_500);
  assert.equal(vm.runInContext('missionTargetForFamily("monthly", "workouts", {})', context), 8);
  assert.equal(vm.runInContext('missionTargetForFamily("monthly", "sets", {})', context), 64);
  assert.equal(
    vm.runInContext(`(() => {
      const catalog = dailyMissionCatalog();
      return new Set(missionGroups().daily.map(item =>
        missionSelectionMetric(catalog.find(template => template.id === item.id).family)
      )).size;
    })()`, context),
    3
  );
});

test("overlapping mission target fallbacks and bounds match the native board", () => {
  const context = loadPwaContext();
  const cases = [
    ["daily", "exercises", "typicalDayExercises", 3, 10],
    ["daily", "sets", "typicalDaySets", 8, 22],
    ["weekly", "workouts", "typicalWeekWorkouts", 2, 3],
    ["weekly", "active-days", "typicalWeekActiveDays", 2, 3],
    ["weekly", "sets", "typicalWeekSets", 16, 48],
    ["monthly", "workouts", "typicalMonthWorkouts", 6, 14],
    ["monthly", "sets", "typicalMonthSets", 48, 160]
  ];
  for (const [cadence, family, historyKey, minimum, maximum] of cases) {
    assert.equal(
      vm.runInContext(`missionTargetForFamily("${cadence}", "${family}", { ${historyKey}: 1 })`, context),
      minimum
    );
    assert.equal(
      vm.runInContext(`missionTargetForFamily("${cadence}", "${family}", { ${historyKey}: 1000000 })`, context),
      maximum
    );
  }

  assert.match(androidAdaptiveMissionBoardSource, /"exercises" -> boundedTarget\(history\.typicalDayExercises, fallback = 3, min = 3, max = 10\)/);
  assert.match(androidAdaptiveMissionBoardSource, /"sets" -> boundedTarget\(history\.typicalDaySets, fallback = 8, min = 8, max = 22\)/);
  assert.match(androidAdaptiveMissionBoardSource, /"workouts" -> boundedTarget\(history\.typicalWeekWorkouts, fallback = 3, min = 2, max = 3\)/);
  assert.match(androidAdaptiveMissionBoardSource, /"active-days" -> boundedTarget\(history\.typicalWeekActiveDays, fallback = 2, min = 2, max = 3\)/);
  assert.match(androidAdaptiveMissionBoardSource, /"sets" -> boundedTarget\(history\.typicalWeekSets, fallback = 24, min = 16, max = 48\)/);
  assert.match(androidAdaptiveMissionBoardSource, /"workouts" -> boundedTarget\(history\.typicalMonthWorkouts, fallback = 8, min = 6, max = 14\)/);
  assert.match(androidAdaptiveMissionBoardSource, /"sets" -> boundedTarget\(history\.typicalMonthSets, fallback = 64, min = 48, max = 160\)/);
});

test("one exceptional workout does not set every future mission target", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    const missionTestNow = new Date(2026, 7, 9, 12).getTime();
    const missionTestSession = (id, daysAgo, setCount) => ({
      id,
      startedAt: missionTestNow - daysAgo * 86400000,
      note: "",
      sets: Array.from({ length: setCount }, (_, index) => ({
        id: id * 100 + index,
        exerciseName: index % 2 ? "Squat" : "Bench Press",
        weight: 20,
        reps: 8
      }))
    });
    state = {
      ...defaultAppState(),
      sessions: [
        missionTestSession(1, 1, 10),
        missionTestSession(2, 3, 10),
        missionTestSession(3, 5, 12),
        missionTestSession(4, 7, 80)
      ]
    };
  `, context);

  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalDaySets", context), 10);
  assert.equal(
    vm.runInContext('missionTargetForFamily("daily", "sets", missionHistoryStats(missionTestNow))', context),
    10
  );
  assert.equal(
    vm.runInContext('typicalMissionValue([{ value: 8 }, { value: 10 }, { value: 12 }, { value: 80 }], "value", 10)', context),
    10
  );
});

test("one lone recent outlier cannot raise day or session fallbacks", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    const missionTestNow = new Date(2026, 7, 9, 12).getTime();
    state = {
      ...defaultAppState(),
      sessions: [{
        id: 1,
        startedAt: new Date(2026, 7, 8, 12).getTime(),
        note: "",
        sets: Array.from({ length: 80 }, (_, index) => ({
          id: index + 1,
          exerciseName: index % 2 ? "Squat" : "Bench Press",
          weight: 20,
          reps: 8
        }))
      }]
    };
  `, context);

  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalDaySets", context), 8);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalSessionSets", context), 10);
  assert.equal(vm.runInContext('typicalMissionValue([{ value: 80 }], "value", 8)', context), 8);
  assert.equal(vm.runInContext('typicalMissionValue([{ value: 6 }], "value", 8)', context), 8);
});

test("mission baselines ignore stale history and current incomplete week and month", () => {
  const context = loadPwaContext();
  vm.runInContext(`
    const missionTestNow = new Date(2026, 7, 9, 12).getTime();
    const missionTestSessionAt = (id, year, month, day, setCount) => ({
      id,
      startedAt: new Date(year, month, day, 12).getTime(),
      note: "",
      sets: Array.from({ length: setCount }, (_, index) => ({
        id: id * 100 + index,
        exerciseName: index % 2 ? "Squat" : "Bench Press",
        weight: 20,
        reps: 8
      }))
    });
    state = {
      ...defaultAppState(),
      sessions: [
        missionTestSessionAt(1, 2026, 0, 31, 120),
        missionTestSessionAt(2, 2026, 5, 15, 20),
        missionTestSessionAt(3, 2026, 6, 20, 10),
        missionTestSessionAt(4, 2026, 6, 29, 12),
        missionTestSessionAt(5, 2026, 7, 5, 80),
        missionTestSessionAt(6, 2026, 7, 9, 500)
      ]
    };
  `, context);

  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalDaySets", context), 12);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalSessionSets", context), 12);
  assert.equal(
    vm.runInContext('missionTargetForFamily("daily", "sets", missionHistoryStats(missionTestNow))', context),
    12
  );
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalWeekSets", context), 12);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalMonthSets", context), 20);
  assert.equal(vm.runInContext("dayKey(missionCalendarWindows(missionTestNow).dayStartInclusive)", context), "2026-6-28");
  assert.equal(
    vm.runInContext("dayKey(missionCalendarWindows(missionTestNow).currentDayStartExclusive)", context),
    "2026-8-9"
  );

  vm.runInContext(`
    state = {
      ...defaultAppState(),
      sessions: [missionTestSessionAt(7, 2026, 0, 31, 120)]
    };
  `, context);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalDaySets", context), 8);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalWeekSets", context), 24);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalMonthSets", context), 64);
  assert.equal(vm.runInContext("missionHistoryStats(missionTestNow).typicalSessionSets", context), 10);
  assert.equal(
    vm.runInContext('missionTargetForFamily("monthly", "sets", missionHistoryStats(missionTestNow))', context),
    64
  );
});

test("mission copy uses target-aware English, Ukrainian, and Russian count forms", () => {
  const context = loadPwaContext();
  const copyFor = language => {
    vm.runInContext(`state = { ...defaultAppState(), language: "${language}", sessions: [] }`, context);
    return JSON.parse(vm.runInContext(`JSON.stringify({
      daySummary: missionSummary({ family: "days-10-sets", goal: 1 }, "weekly"),
      threeWorkoutSummary: missionSummary({ family: "workouts", goal: 3 }, "weekly"),
      eightWorkoutSummary: missionSummary({ family: "workouts", goal: 8 }, "monthly"),
      dayProgress: mission({
        id: "day-copy", family: "active-days", goal: 1,
        unitEn: "days", unitUk: "днів", titleEn: "Day", titleUk: "День",
        progress: () => 0
      }, "weekly", {}, {}).progressLabel,
      threeWorkoutProgress: mission({
        id: "three-workout-copy", family: "workouts", goal: 3,
        unitEn: "workouts", unitUk: "тренування", titleEn: "Workouts", titleUk: "Тренування",
        progress: () => 0
      }, "weekly", {}, {}).progressLabel,
      eightWorkoutProgress: mission({
        id: "eight-workout-copy", family: "workouts", goal: 8,
        unitEn: "workouts", unitUk: "тренування", titleEn: "Workouts", titleUk: "Тренування",
        progress: () => 0
      }, "monthly", {}, {}).progressLabel
    })`, context));
  };

  assert.deepEqual(copyFor("en"), {
    daySummary: "Hit 10 sets on 1 day this week.",
    threeWorkoutSummary: "Complete 3 workouts this week.",
    eightWorkoutSummary: "Complete 8 workouts this month.",
    dayProgress: "0 / 1 day",
    threeWorkoutProgress: "0 / 3 workouts",
    eightWorkoutProgress: "0 / 8 workouts"
  });
  assert.deepEqual(copyFor("uk"), {
    daySummary: "Зроби 10 підходів у 1 день цього тижня.",
    threeWorkoutSummary: "Заверши 3 тренування цього тижня.",
    eightWorkoutSummary: "Заверши 8 тренувань цього місяця.",
    dayProgress: "0 / 1 день",
    threeWorkoutProgress: "0 / 3 тренування",
    eightWorkoutProgress: "0 / 8 тренувань"
  });
  assert.deepEqual(copyFor("ru"), {
    daySummary: "Выполни 10 подходов в 1 день на этой неделе.",
    threeWorkoutSummary: "Заверши 3 тренировки на этой неделе.",
    eightWorkoutSummary: "Заверши 8 тренировок в этом месяце.",
    dayProgress: "0 / 1 день",
    threeWorkoutProgress: "0 / 3 тренировки",
    eightWorkoutProgress: "0 / 8 тренировок"
  });
});

test("mission presentation does not claim XP that progression does not award", () => {
  const context = loadPwaContext();
  const missionMarkup = vm.runInContext(`missionCard({
    cadenceLabel: "Daily",
    done: true,
    title: "Daily check-in",
    summary: "Complete one workout today.",
    progress: 1,
    target: 1,
    progressLabel: "1 / 1 workout"
  })`, context);
  const summaryMarkup = vm.runInContext(`summaryRewardsSection({
    missions: [{ title: "Daily check-in", supporting: "Complete one workout today.", badge: "Mission" }],
    badges: []
  })`, context);

  assert.doesNotMatch(missionMarkup, /\+\d+\s*XP/i);
  assert.doesNotMatch(summaryMarkup, /\+\d+\s*XP|What you unlocked|>Rewards</i);
  assert.match(summaryMarkup, />Progress<.*>Missions</s);
  assert.doesNotMatch(appSource, /function missionXpReward\b/);

  assert.doesNotMatch(androidMissionsScreenSource, /mission\.xpReward|post_workout_xp_gain/);
  assert.doesNotMatch(androidPostWorkoutScreenSource, /mission\.rewardXp/);
  assert.doesNotMatch(androidWorkoutListViewModelSource, /val xpReward: Int|val missionXp: Int/);
  const completedMissionModel = androidPostWorkoutViewModelSource.match(
    /data class CompletedMissionUiState\([\s\S]*?\n\)/
  )?.[0] || "";
  assert.doesNotMatch(completedMissionModel, /rewardXp/);
});
