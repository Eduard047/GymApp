import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [contractSource, androidDates, androidToday, androidViewModel, androidWorkoutDao,
  androidEnglish, androidUkrainian, androidRussian, iosDates, iosToday, iosWorkoutStore,
  pwaApp, pwaStyles, pwaRussian, pwaLiveWorkout, pwaIndex, pwaServiceWorker,
  pwaAppBundle, pwaStyleBundle, pwaRussianBundle, pwaLiveWorkoutBundle] =
  await Promise.all([
    readFile("shared/visible-date-today-metrics-v1.json", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/util/DateTimeUtils.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/WorkoutListScreen.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/WorkoutListViewModel.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/data/dao/WorkoutDao.kt", "utf8"),
    readFile("app/src/main/res/values/strings.xml", "utf8"),
    readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
    readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/App/AppLanguage.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/UI/Screens/WorkoutsView.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/Data/WorkoutStore.swift", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/styles.css", "utf8"),
    readFile("pwa/russian-text.js", "utf8"),
    readFile("pwa/live-workout.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/sw.js", "utf8"),
    readFile("pwa/app.v94.js", "utf8"),
    readFile("pwa/styles.v76.css", "utf8"),
    readFile("pwa/russian-text.v83.js", "utf8"),
    readFile("pwa/live-workout.v3.js", "utf8")
  ]);

const contract = JSON.parse(contractSource);

const nativeDateSurfaces = Object.fromEntries(await Promise.all([
  "app/src/main/java/com/example/gymapp/ui/screens/WorkoutDetailScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/PostWorkoutSummaryScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/AddWorkoutScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/FriendWorkoutPickerSheet.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/PersistedDeleteConfirmationDialogs.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/ExerciseProgressScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/ExerciseListScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt",
  "app/src/main/java/com/example/gymapp/ui/viewmodel/ExerciseProgressViewModel.kt",
  "ios/GymApp-iOS/GymApp/UI/Screens/AddWorkoutView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/WorkoutDetailView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/ProgressView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/LeaderboardView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/AccountSettingsView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/ActiveWorkoutView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/ExercisesView.swift",
  "ios/GymApp-iOS/GymApp/UI/Screens/PostWorkoutSummaryView.swift",
  "ios/GymApp-iOS/GymApp/UI/Components/WorkoutDashboardComponents.swift",
  "ios/GymApp-iOS/GymApp/Services/ExportService.swift"
].map(async path => [path, await readFile(path, "utf8")])));

test("visible date contract requires weekday without changing relative or timestamp labels", () => {
  assert.equal(contract.productVersion, "3.1.1");
  assert.deepEqual(contract.clients, ["android", "ios", "pwa"]);
  assert.equal(contract.visibleCalendarDate.includeLocalizedWeekday, true);
  assert.deepEqual(contract.visibleCalendarDate.supportedLanguages, ["en", "uk", "ru"]);
  assert.deepEqual(contract.visibleCalendarDate.excludedSurfaces, [
    "todayAndYesterdayLabels",
    "monthOnlySelectors",
    "timeOnlyLabels",
    "durationsAndTimers",
    "statusTimestamps",
    "calendarCellsWithAnAlreadyVisibleWeekdayHeader"
  ]);
});

test("native date helpers expose compact and expanded weekday styles", () => {
  assert.match(androidDates, /DateTimeFormatter\.ofPattern\("EEE, d MMM yyyy", locale\)/);
  assert.match(androidDates, /DateTimeFormatter\.ofPattern\("EEEE, d MMMM yyyy", locale\)/);
  assert.match(iosDates, /weekday\(date == \.long \? \.wide : \.abbreviated\)/);
  assert.match(iosDates, /func gymFormattedTimestamp\(/);
});

test("native visible date surfaces use weekday formatters and preserve explicit exclusions", () => {
  const source = path => nativeDateSurfaces[path];

  assert.match(source("app/src/main/java/com/example/gymapp/ui/screens/WorkoutDetailScreen.kt"), /DateTimeUtils\.formatLongDate/);
  assert.match(source("app/src/main/java/com/example/gymapp/ui/screens/PostWorkoutSummaryScreen.kt"), /DateTimeUtils\.formatLongDate/);
  for (const path of [
    "app/src/main/java/com/example/gymapp/ui/screens/AddWorkoutScreen.kt",
    "app/src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt",
    "app/src/main/java/com/example/gymapp/ui/screens/FriendWorkoutPickerSheet.kt",
    "app/src/main/java/com/example/gymapp/ui/screens/PersistedDeleteConfirmationDialogs.kt",
    "app/src/main/java/com/example/gymapp/ui/screens/ExerciseProgressScreen.kt"
  ]) {
    assert.match(source(path), /DateTimeUtils\.formatDate/);
  }
  assert.match(source("app/src/main/java/com/example/gymapp/ui/screens/ExerciseListScreen.kt"), /DateTimeUtils\.formatDate\(sessionTimestamp, locale\)/);
  assert.match(source("app/src/main/java/com/example/gymapp/ui/viewmodel/ExerciseProgressViewModel.kt"), /ofPattern\("EEEEE d", locale\)/);
  assert.match(source("app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt"), /DateFormat\.getDateTimeInstance/);

  for (const path of [
    "ios/GymApp-iOS/GymApp/UI/Screens/ProgressView.swift",
    "ios/GymApp-iOS/GymApp/UI/Screens/ExercisesView.swift",
    "ios/GymApp-iOS/GymApp/UI/Screens/PostWorkoutSummaryView.swift"
  ]) {
    assert.match(source(path), /gymFormattedDate\(/);
  }
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Screens/AddWorkoutView.swift"), /gymFormattedWeekday\(date\)/);
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Screens/WorkoutDetailView.swift"), /gymFormattedWeekday\(date\)/);
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Screens/LeaderboardView.swift"), /\.weekday\(\.abbreviated\)/);
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Screens/ProgressView.swift"), /\.weekday\(\.narrow\)\.day\(\)/);
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Screens/AccountSettingsView.swift"), /gymFormattedTimestamp\(/);
  assert.match(source("ios/GymApp-iOS/GymApp/Services/ExportService.swift"), /gymFormattedTimestamp\(/);
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Screens/ActiveWorkoutView.swift"), /date: \.omitted, time: \.shortened/);
  assert.match(source("ios/GymApp-iOS/GymApp/UI/Components/WorkoutDashboardComponents.swift"), /gymFormattedDateWithoutWeekday\(/);
});

test("Today hero has the same ordered concise metrics on both native clients", () => {
  assert.deepEqual(contract.todayHero.metricOrder, [
    "totalWorkouts", "weekStreak", "totalVolume"
  ]);
  assert.equal(contract.todayHero.layout.columns, 3);
  assert.equal(contract.todayHero.source.completedCanonicalHistoryOnly, true);
  assert.equal(contract.todayHero.source.activeDraftCounted, false);
  assert.equal(contract.todayHero.totalVolume.maximumDisplayValue, 1_000_000_000_000_000);

  for (const label of Object.values(contract.todayHero.labels)) {
    assert.ok(androidEnglish.includes(label.en));
    assert.ok(androidUkrainian.includes(label.uk));
    assert.ok(androidRussian.includes(label.ru));
    assert.match(iosToday, new RegExp(label.en.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.match(iosToday, new RegExp(label.uk.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    assert.match(iosToday, new RegExp(label.ru.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  assert.match(androidEnglish, /<string name="focus_lens_week_streak">Week streak<\/string>/);
  assert.match(androidUkrainian, /<string name="focus_lens_week_streak">Серія тижнів<\/string>/);
  assert.match(androidRussian, /<string name="focus_lens_week_streak">Серия недель<\/string>/);

  assert.match(androidToday, /TodayHeroMetricsRow\(/);
  assert.match(iosToday, /todayHeroMetricsRow/);
  assert.doesNotMatch(androidToday, /focus_lens_active_workout_supporting/);
  assert.match(androidViewModel, /sessions = allSessions/);
  assert.match(androidWorkoutDao, /HAVING COUNT\(se\.id\) > 0/);
  assert.match(iosToday, /sessions: store\.workoutSummaries/);
  assert.match(iosWorkoutStore, /\.filter \{ \$0\.setCount > 0 \}/);
  assert.match(androidViewModel, /MAX_TODAY_HERO_VOLUME = 1_000_000_000_000_000\.0/);
  assert.match(iosToday, /maximumTodayHeroVolume = 1_000_000_000_000_000\.0/);
});

test("Today completion and weekly summary have one local-calendar contract", () => {
  assert.deepEqual(contract.todayState.precedence, [
    "activeWorkout", "completedToday", "restOrRecovery", "recommendedPlan"
  ]);
  assert.equal(
    contract.todayState.completedTodaySource,
    "completedCanonicalHistoryInCurrentLocalCalendarDay"
  );
  assert.deepEqual(contract.todayState.completedTodaySuppresses, [
    "recoveryCard", "trainAnyway", "recommendedPlanActions"
  ]);
  assert.deepEqual(contract.todayState.completedTodayActionsInOrder, ["createAnotherWorkout"]);
  assert.deepEqual(contract.todayState.retainedDraftActionOverride, {
    actionsInOrder: ["continuePlan"],
    createAnotherWorkoutSuppressed: true,
    opensSameAccountRetainedDraft: true
  });
  assert.equal(contract.weeklySummary.calendar, "localMondayStartSevenDayWeek");
  assert.equal(contract.weeklySummary.dayMarkers, 7);
  assert.equal(
    contract.weeklySummary.headerMetric,
    "completedTrainingDaysVsProfileTarget"
  );
  assert.deepEqual(contract.weeklySummary.metricsInOrder, [
    "completedWorkouts", "trainingMinutes", "totalVolume"
  ]);
  assert.equal(
    contract.weeklySummary.metricValueStyle,
    "localizedWholeNumberWithoutRepeatedUnitSuffix"
  );
  for (const copy of [
    contract.todayState.completedTodayCopy.title,
    contract.todayState.completedTodayCopy.body,
    ...Object.values(contract.weeklySummary.labels)
  ]) {
    assert.ok(
      androidEnglish.includes(copy.en) || androidEnglish.includes(copy.en.replaceAll("'", "\\'")),
      `Android EN is missing ${copy.en}`
    );
    assert.ok(androidUkrainian.includes(copy.uk), `Android UK is missing ${copy.uk}`);
    assert.ok(androidRussian.includes(copy.ru), `Android RU is missing ${copy.ru}`);
    assert.ok(iosToday.includes(copy.en), `iOS EN is missing ${copy.en}`);
    assert.ok(iosToday.includes(copy.uk), `iOS UK is missing ${copy.uk}`);
    assert.ok(iosToday.includes(copy.ru), `iOS RU is missing ${copy.ru}`);
    assert.ok(pwaApp.includes(copy.en), `PWA EN is missing ${copy.en}`);
    assert.ok(pwaApp.includes(copy.uk), `PWA UK is missing ${copy.uk}`);
    assert.ok(pwaApp.includes(copy.ru), `PWA RU is missing ${copy.ru}`);
  }
  assert.equal(
    contract.weeklySummary.trainingMinutes.fallbackEstimatePerSession,
    "min(90,max(10,exerciseCount*3+setCount*2))"
  );
  assert.equal(contract.weeklySummary.trainingMinutes.minimumPerSession, 10);
  assert.equal(contract.weeklySummary.trainingMinutes.maximumPerSession, 90);
});

test("PWA date and Today helpers implement the shared localized, history-only contract", () => {
  assert.match(pwaApp, /const DEFAULT_CALENDAR_DATE_OPTIONS = Object\.freeze\(\{[\s\S]*weekday: "short"/);
  assert.match(pwaApp, /function socialDayLabel\(day\)[\s\S]*weekday: "short"[\s\S]*timeZone: "UTC"/);
  assert.match(pwaApp, /weekday: "narrow", day: "numeric"/);
  assert.match(pwaApp, /workout-date-weekday[^\n]+fmtDate\(draft\.startedAt, \{ weekday: "long" \}\)/);
  assert.match(pwaApp, /function todayPlanDashboardMetrics\(\)[\s\S]*session\.sets\.length > 0[\s\S]*totalWorkouts:[\s\S]*weeklyStreak:[\s\S]*totalVolume:/);
  assert.match(pwaApp, /function boundedTodayMetric\(value, maximum\)[\s\S]*Number\.isFinite\(numeric\)/);
  assert.match(pwaApp, /function formatTodayMetric\(value, compact = true\)[\s\S]*notation: "compact"[\s\S]*maximumFractionDigits: 1/);

  for (const label of Object.values(contract.todayHero.labels)) {
    assert.ok(pwaApp.includes(label.en));
    assert.ok(pwaApp.includes(label.uk));
    assert.ok(pwaRussian.includes(label.ru));
  }

  const rhythm = pwaApp.indexOf("function focusLensCard(sessions)");
  const metrics = pwaApp.indexOf("${launch ? smartPlanMetricsMarkup(launch.plan) : \"\"}", rhythm);
  const actions = pwaApp.indexOf("focus-lens-actions plan-actions", metrics);
  assert.ok(rhythm >= 0 && rhythm < metrics && metrics < actions);
  assert.match(pwaStyles, /\.focus-lens-plan-metrics \{[\s\S]*grid-template-columns: repeat\(3, minmax\(0, 1fr\)\)/);
  assert.match(pwaStyles, /\.focus-lens-plan-metrics strong \{[\s\S]*white-space: nowrap/);
  assert.match(pwaStyles, /\.focus-lens-plan-metrics span \{[\s\S]*-webkit-line-clamp: 2/);

  assert.deepEqual(contract.pwaReleaseCoupling, {
    appBundle: "app.v94.js",
    styleBundle: "styles.v76.css",
    russianBundle: "russian-text.v83.js",
    liveWorkoutBundle: "live-workout.v3.js",
    serviceWorkerCache: "gym-pwa-v131"
  });
  assert.match(pwaIndex, /src="\.\/app\.v94\.js"/);
  assert.match(pwaIndex, /href="\.\/styles\.v76\.css"/);
  assert.match(pwaIndex, /src="\.\/russian-text\.v83\.js"/);
  assert.match(pwaIndex, /src="\.\/live-workout\.v3\.js"/);
  assert.match(pwaServiceWorker, /CACHE_VERSION = "v131"/);
  assert.match(pwaServiceWorker, /"\.\/app\.v94\.js"/);
  assert.match(pwaServiceWorker, /"\.\/styles\.v76\.css"/);
  assert.match(pwaServiceWorker, /"\.\/russian-text\.v83\.js"/);
  assert.match(pwaServiceWorker, /"\.\/live-workout\.v3\.js"/);
  assert.equal(pwaAppBundle, pwaApp);
  assert.equal(pwaStyleBundle, pwaStyles);
  assert.equal(pwaRussianBundle, pwaRussian);
  assert.equal(pwaLiveWorkoutBundle, pwaLiveWorkout);
});
