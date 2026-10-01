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

  const ukrainianLongDate = vm.runInContext(`(() => {
    state.language = "uk";
    return fmtLongDate(new Date(2026, 7, 15, 12).getTime());
  })()`, sandbox);
  assert.match(ukrainianLongDate, /15 серпня/);
  assert.doesNotMatch(ukrainianLongDate, /15 серпень/);
});

test("all PWA workout, friend, template, record, and progress calendar surfaces use weekday formatters", () => {
  assert.match(appSource, /workout-title[^\n]+fmtDate\(session\.startedAt\)/);
  assert.match(appSource, /workout-detail-hero[^\n]+fmtLongDate\(session\.startedAt\)/);
  assert.match(appSource, /garmin-header[^\n]+fmtLongDate\(session\.startedAt\)/);
  assert.match(appSource, /function summaryHeroMarkup[\s\S]{0,400}fmtShortDate\(session\.startedAt\)/);
  assert.match(appSource, /modal\.type === "template"[^\n]+fmtDate\(session\.startedAt\)/);
  assert.match(appSource, /friend-workout-history-row[^\n]+socialDayLabel\(workout\.workoutDay\)/);
  assert.match(appSource, /friend-record-row[^\n]+socialDayLabel\(record\.lastWorkoutDay\)/);
  assert.match(appSource, /friend-workout-detail[^\n]+socialDayLabel\(workout\.workoutDay\)/);
  assert.match(appSource, /weekday: "long", day: "numeric", month: "long"/);
  assert.match(appSource, /function fmtChartAxisDate\(value\)[\s\S]{0,120}day: "numeric", month: "short"/);
  assert.match(appSource, /workout-date-weekday[^\n]+fmtDate\(draft\.startedAt, \{ weekday: "long" \}\)/);
  assert.match(appSource, /Exported: \$\{fmtDate\(data\.exportedAt, \{[\s\S]{0,180}weekday: "short"/);

  assert.match(appSource, /fmtDate\(monthDate\(\)\.getTime\(\), \{ month: "long", year: "numeric" \}\)/);
  assert.match(appSource, /Last watch sync[\s\S]{0,300}dateStyle: "medium", timeStyle: "short"/);
  assert.match(appSource, /workout-date-today[^\n]+Today/);
});

test("progress chart axis labels are day and short month without a weekday initial", () => {
  const sandbox = context();
  const timestamp = Date.UTC(2026, 7, 11, 12, 0, 0); // a Tuesday: the old format read "11 T"
  const expectedLabels = { en: "Aug 11", uk: "11 серп.", ru: "11 авг." };
  for (const [language, locale] of [["en", "en-US"], ["uk", "uk-UA"], ["ru", "ru-RU"]]) {
    const label = vm.runInContext(`(() => {
      state.language = ${JSON.stringify(language)};
      return progressChartPoints([{ session: { startedAt: ${timestamp} }, sets: [{ weight: 40, reps: 8 }] }])[0].label;
    })()`, sandbox);
    const expected = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" })
      .format(new Date(timestamp));
    assert.equal(label, expected, language);
    assert.equal(label, expectedLabels[language], language);
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

test("Today keeps plan metrics separate and renders one compact training history surface", () => {
  assert.match(stylesSource, /\.focus-lens-plan-metrics \{[\s\S]*grid-template-columns: repeat\(3, minmax\(0, 1fr\)\)/);
  assert.match(stylesSource, /\.focus-lens-plan-metrics strong \{[\s\S]*white-space: nowrap/);
  assert.match(stylesSource, /\.focus-lens-plan-metrics span \{[\s\S]*font-size: 12px[\s\S]*-webkit-line-clamp: 2/);
  const focus = appSource.indexOf("function focusLensCard(");
  const focusEnd = appSource.indexOf("\nasync function startPreparedSmartWorkout", focus);
  const focusBody = appSource.slice(focus, focusEnd);
  const details = appSource.indexOf("function focusLensDetailsMarkup(");
  const detailsEnd = appSource.indexOf("\nfunction focusLensCard(", details);
  const detailsBody = appSource.slice(details, detailsEnd);
  assert.equal((detailsBody.match(/todayPlanMetricsMarkup\(\)/g) || []).length, 1);
  assert.doesNotMatch(detailsBody, /weeklyWorkoutSummaryMarkup/);
  const workouts = appSource.indexOf("function workoutsScreen()");
  const workoutsEnd = appSource.indexOf("\nfunction overviewCards(", workouts);
  const workoutsBody = appSource.slice(workouts, workoutsEnd);
  const focusOverview = workoutsBody.indexOf("${focusOverview(sessions)}");
  const trainingHistory = workoutsBody.indexOf("${trainingHistoryMarkup()}");
  assert.ok(focusOverview >= 0 && focusOverview < trainingHistory);
  assert.equal((workoutsBody.match(/trainingHistoryMarkup\(\)/g) || []).length, 1);
  assert.doesNotMatch(workoutsBody, /weeklyWorkoutSummaryMarkup\(\)|\$\{monthSwitcher\(\)\}/);
  assert.equal((focusBody.match(/focusLensDetailsMarkup\(/g) || []).length, 2);
  const completedStart = focusBody.indexOf("const completedToday");
  const completedEnd = focusBody.indexOf("const decision", completedStart);
  const completedBranch = focusBody.slice(completedStart, completedEnd);
  assert.match(completedBranch, /data-action="open-blank-add"/);
  assert.equal((completedBranch.match(/data-action=/g) || []).length, 1);
  assert.doesNotMatch(completedBranch, /focusLensDetailsMarkup|todayPlanMetricsMarkup/);
  assert.doesNotMatch(completedBranch, /start-recommended|edit-recommended|Train anyway|open-add/);
  const progress = appSource.indexOf("function progressScreen()");
  const progressEnd = appSource.indexOf("function exerciseProgressPanel()", progress);
  assert.ok(focus >= 0 && focus < focusEnd);
  assert.match(appSource.slice(progress, progressEnd), /overviewCards\(selectedMonthSessions\(\)\)/);
});

test("weekly Today summary uses a local Monday week and the cross-client estimate", () => {
  const sandbox = context();
  const summary = plain(vm.runInContext(`(() => {
    state.profile.days = 4;
    const now = new Date(2026, 7, 12, 20, 0, 0).getTime();
    const session = (id, timestamp, sets, note = "", durationSeconds = null) => ({
      id, startedAt: timestamp, sets, note, ...(durationSeconds === null ? {} : { durationSeconds })
    });
    const set = (id, exerciseName, weight, reps) => ({ id, exerciseName, weight, reps });
    const cappedSets = Array.from({ length: 30 }, (_, index) =>
      set(100 + index, "Exercise " + index, 1, 1));
    return currentWeekWorkoutSummary(now, [
      session(
        1,
        new Date(2026, 7, 10, 10).getTime(),
        [set(1, "Bench Press", 100, 5)],
        "Garmin · Duration 1:00:01"
      ),
      session(2, new Date(2026, 7, 12, 8).getTime(), [
        set(2, "Squat", 10, 10), set(3, "Squat", 20, 5), set(4, "Row", 30, 1)
      ], "", 95),
      session(3, new Date(2026, 7, 12, 9).getTime(), cappedSets),
      session(4, new Date(2026, 7, 9, 10).getTime(), [set(200, "Old", 999, 1)]),
      session(5, new Date(2026, 7, 13, 10).getTime(), [set(201, "Future", 999, 1)])
    ]);
  })()`, sandbox));

  assert.equal(summary.days.length, 7);
  assert.deepEqual(summary.days.map(day => day.trained), [true, false, true, false, false, false, false]);
  assert.deepEqual(summary.days.map(day => day.today), [false, false, true, false, false, false, false]);
  assert.equal(summary.completedWorkouts, 3);
  assert.equal(summary.completedTrainingDays, 2);
  assert.equal(summary.targetTrainingDays, 4);
  assert.equal(summary.trainingMinutes, 153);
  assert.equal(summary.totalVolume, 760);
  const sandboxDuration = context();
  assert.equal(vm.runInContext(`measuredWorkoutMinutes({ note: "Garmin · Duration 0:00" })`, sandboxDuration), null);
  assert.equal(vm.runInContext(`measuredWorkoutMinutes({ durationSeconds: 0, sets: [] })`, sandboxDuration), 0);
  assert.equal(vm.runInContext(`estimatedWorkoutMinutes({ note: "not Garmin", sets: [] })`, sandboxDuration), 10);
});

test("completed Today takes precedence and offers one follow-up action", () => {
  const sandbox = context();
  const markup = vm.runInContext(`(() => {
    activeWorkout = null;
    state.language = "en";
    state.sessions = [{
      id: 1,
      startedAt: Date.now(),
      sets: [{ id: 1, exerciseName: "Bench Press", weight: 50, reps: 8 }]
    }];
    return focusLensCard(state.sessions);
  })()`, sandbox);
  assert.match(markup, /TODAY COMPLETE/);
  assert.match(markup, /data-action="open-blank-add"/);
  // The "With a friend" pill is a separate entry point, not a new-plan action.
  assert.match(markup, /data-action="today-friend"/);
  assert.equal((markup.match(/data-action="(?!today-friend")/g) || []).length, 1);
  assert.doesNotMatch(markup, /start-recommended|edit-recommended|Train anyway|data-action="open-add"/);
});

test("retained drafts visibly override every Today and first-activation new-plan action", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeWorkout = null;
    state.language = "en";
    workoutDraft = {
      startedAt: Date.now(),
      note: "continue me",
      blocks: [{ exerciseName: "Bench Press", sets: [{ weight: "50", reps: "8" }] }]
    };
    state.sessions = [{
      id: 1,
      startedAt: Date.now(),
      sets: [{ id: 1, exerciseName: "Bench Press", weight: 50, reps: 8 }]
    }];
    const completed = focusLensCard(state.sessions);
    state.sessions = [];
    const recommended = focusLensCard(state.sessions);
    const activation = activationCard();
    return { completed, recommended, activation };
  })()`, sandbox));

  for (const markup of [result.completed, result.recommended, result.activation]) {
    assert.match(markup, /Continue plan/);
    assert.match(markup, /Cancel plan/);
    assert.match(markup, /data-action="cancel-retained-plan"/);
    assert.equal((markup.match(/data-action="(?!today-friend")/g) || []).length, 2);
    assert.doesNotMatch(markup, /Add another workout|Start plan|Train anyway|Create manually/);
  }
});

test("training history switches between one weekly and one monthly filtered list", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    const now = new Date(2026, 7, 15, 12, 0, 0).getTime();
    const set = (id, exerciseName) => ({ id, exerciseName, weight: 50, reps: 8, orderIndex: 0 });
    state.sessions = [
      { id: 1, startedAt: new Date(2026, 6, 30, 8).getTime(), note: "", sets: [set(11, "Squat")] },
      { id: 2, startedAt: new Date(2026, 7, 5, 8).getTime(), note: "", sets: [set(21, "Bench Press")] },
      { id: 3, startedAt: new Date(2026, 7, 12, 8).getTime(), note: "", sets: [set(31, "Cable Row")] },
      { id: 4, startedAt: new Date(2026, 7, 15, 18).getTime(), note: "", sets: [set(41, "Future")] }
    ];
    const week = currentWeekWorkoutSummary(now, state.sessions, -1);
    const month = currentMonthWorkoutSummary(now, state.sessions, 0);
    return {
      weekIds: week.workouts.map(item => item.id),
      monthIds: month.workouts.map(item => item.id),
      monthDays: month.completedTrainingDays,
      monthCells: month.days.length
    };
  })()`, sandbox));

  assert.deepEqual(result.weekIds, [2]);
  assert.deepEqual(result.monthIds, [3, 2]);
  assert.equal(result.monthDays, 2);
  assert.ok(result.monthCells >= 28 && result.monthCells <= 42);
  assert.match(appSource, /data-action="history-period" data-period="week"/);
  assert.match(appSource, /data-action="history-period" data-period="month"/);
  assert.match(stylesSource, /\.training-history-list/);
  assert.match(stylesSource, /\.training-history-row/);
});

test("pre-start draft storage is bounded, exact, account/session-bound, and fail-closed", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = {
      id: "local-v2-0123456789abcdef0123456789abcdef",
      name: "Draft Test",
      localIdVersion: 2
    };
    const descriptor = workoutDraftAccountDescriptor();
    const stateKey = activeStorageKey();
    localStorage.setItem(stateKey, "preserve-account-state");
    workoutDraft = {
      startedAt: Date.now(),
      note: "keep me",
      blocks: [{ exerciseName: "Bench Press", sets: [{ weight: "50", reps: "8" }] }]
    };
    const saved = persistWorkoutDraft();
    const raw = localStorage.getItem(descriptor.storageKey);
    workoutDraft = null;
    const restored = loadStoredWorkoutDraftRecord();

    const unknownField = { ...JSON.parse(raw), unexpected: true };
    localStorage.setItem(descriptor.storageKey, JSON.stringify(unknownField));
    const malformed = loadStoredWorkoutDraftRecord();
    const malformedRemoved = localStorage.getItem(descriptor.storageKey) === null;

    localStorage.setItem(descriptor.storageKey, "x".repeat(MAX_WORKOUT_DRAFT_STORAGE_BYTES + 1));
    const oversized = loadStoredWorkoutDraftRecord();
    return {
      saved,
      owner: JSON.parse(raw).owner,
      sessionId: JSON.parse(raw).sessionId,
      restored,
      malformed,
      malformedRemoved,
      oversized,
      oversizedRemoved: localStorage.getItem(descriptor.storageKey) === null,
      accountState: localStorage.getItem(stateKey)
    };
  })()`, sandbox));

  assert.equal(result.saved, true);
  assert.match(result.owner, /^local:/);
  assert.equal(result.sessionId, result.owner.slice("local:".length));
  assert.equal(result.restored.draft.note, "keep me");
  assert.equal(result.malformed, null);
  assert.equal(result.malformedRemoved, true);
  assert.equal(result.oversized, null);
  assert.equal(result.oversizedRemoved, true);
  assert.equal(result.accountState, "preserve-account-state");
});

test("draft navigation persists and direct LIVE creation stays bound to the selected friend", () => {
  const goRootStart = appSource.indexOf("function goRoot(");
  const goRoot = appSource.slice(goRootStart, appSource.indexOf("\nfunction svg", goRootStart));
  const popstate = appSource.slice(appSource.indexOf('window.addEventListener("popstate"'), appSource.indexOf('window.addEventListener("resize"'));
  assert.match(goRoot, /persistWorkoutDraft\(\)/);
  assert.doesNotMatch(goRoot, /workoutDraft = null/);
  assert.match(popstate, /persistWorkoutDraft\(\)/);
  assert.doesNotMatch(popstate, /workoutDraft = null/);
  assert.match(appSource, /data-action="create-live-workout-for-friend"/);
  assert.match(appSource, /workoutDraftLiveRecipient = \{[\s\S]{0,160}friendshipRevision: friend\.friendshipRevision/);
  assert.match(appSource, /await refreshSocialData\(true\)/);
  assert.match(appSource, /friend\.friendshipRevision === recipient\.friendshipRevision/);
  assert.match(appSource, /data-action="\$\{primaryAction\}"/);
  assert.match(appSource, /const primaryAction = liveRecipient \? "send-draft-live-invite" : "start-workout"/);
  assert.match(appSource, /const sent = await sendLiveWorkoutPlan\(recipient\.profileId, plan, \{[\s\S]{0,180}draftFingerprint: sentDraftFingerprint[\s\S]{0,180}recipientFingerprint: canonicalValueFingerprint\(recipient\)/);
  assert.match(appSource, /currentFingerprint === sentDraftFingerprint[\s\S]{0,80}clearWorkoutDraft\(\)/);
  assert.match(appSource, /\$\{liveRecipient \? "" : `<section class="subpanel"><h3>\$\{tx\("Save as completed"/);

  const sandbox = context();
  const navigationUrl = vm.runInContext(`(() => {
    window.GymLiveWorkout = { patterns: { ROOM_ID: /^lr_[0-9a-f]{32}$/ } };
    return liveWorkoutNavigationUrl("lr_0123456789abcdef0123456789abcdef");
  })()`, sandbox);
  const parsed = new URL(navigationUrl);
  assert.equal(parsed.origin, "https://gymapptracker.com");
  assert.deepEqual([...parsed.searchParams.keys()].sort(), ["notification", "room"]);
  assert.equal(parsed.searchParams.get("notification"), "live");
  assert.equal(parsed.searchParams.has("token"), false);
});

test("Today and recommendation re-entry resume a retained draft without dropping its LIVE binding", () => {
  const openBlankStart = appSource.indexOf('if (action === "open-blank-add")');
  const openBlankEnd = appSource.indexOf('if (action === "continue-active-workout")', openBlankStart);
  const openBlank = appSource.slice(openBlankStart, openBlankEnd);
  assert.match(openBlank, /resumeRetainedWorkoutDraft\(\)/);
  assert.doesNotMatch(openBlank, /clearWorkoutDraft\(\)/);

  const launchStart = appSource.indexOf("function launchPreparedSmartWorkout(");
  const launchEnd = appSource.indexOf("\nfunction generateSmartWorkout", launchStart);
  const launch = appSource.slice(launchStart, launchEnd);
  assert.match(launch, /replaceRetainedDraft = false/);
  assert.match(launch, /if \(workoutDraft && !replaceRetainedDraft\) return resumeRetainedWorkoutDraft\(\)/);
  const activationStart = appSource.indexOf("function completeFirstWorkoutActivation(");
  const activationEnd = appSource.indexOf("\nasync function startFirstWorkoutActivation", activationStart);
  const activation = appSource.slice(activationStart, activationEnd);
  const retainedGuard = activation.indexOf("if (workoutDraft) return resumeRetainedWorkoutDraft();");
  const activationCommit = activation.indexOf("setActivationDismissed(true)");
  assert.ok(retainedGuard >= 0 && retainedGuard < activationCommit);

  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = {
      id: "local-v2-0123456789abcdef0123456789abcdef",
      name: "Draft Test",
      localIdVersion: 2
    };
    activeWorkout = null;
    nav = [{ name: "workouts" }];
    modal = { type: "history" };
    languageMenuOpen = true;
    workoutDraft = {
      startedAt: Date.now(),
      note: "keep the exact plan",
      blocks: [{ exerciseName: "Bench Press", sets: [{ weight: "50", reps: "8" }] }]
    };
    workoutDraftLiveRecipient = {
      profileId: "p_0123456789abcdef0123456789abcdef",
      friendshipId: "f_0123456789abcdef0123456789abcdef",
      friendshipRevision: 7
    };
    let persisted = 0;
    let historyPushes = 0;
    let renders = 0;
    persistWorkoutDraft = () => { persisted += 1; return true; };
    pushNavigationHistory = () => { historyPushes += 1; };
    render = () => { renders += 1; };
    const resumed = resumeRetainedWorkoutDraft();
    return {
      resumed,
      persisted,
      historyPushes,
      renders,
      nav,
      modal,
      languageMenuOpen,
      draft: workoutDraft,
      recipient: workoutDraftLiveRecipient
    };
  })()`, sandbox));

  assert.equal(result.resumed, true);
  assert.equal(result.persisted, 1);
  assert.equal(result.historyPushes, 1);
  assert.equal(result.renders, 1);
  assert.deepEqual(result.nav, [{ name: "workouts" }, { name: "add" }]);
  assert.equal(result.modal, null);
  assert.equal(result.languageMenuOpen, false);
  assert.equal(result.draft.note, "keep the exact plan");
  assert.equal(result.recipient.friendshipId, "f_0123456789abcdef0123456789abcdef");
  assert.equal(result.recipient.friendshipRevision, 7);
});

test("privacy-preserving LIVE unavailability keeps the selected friend binding for retry", async () => {
  const sandbox = context();
  const result = plain(await vm.runInContext(`(async () => {
    const userId = "00000000-0000-4000-8000-000000000001";
    const sessionId = "00000000-0000-4000-8000-000000000002";
    const profileId = "p_0123456789abcdef0123456789abcdef";
    const friendshipId = "f_0123456789abcdef0123456789abcdef";
    socialState.dashboard = {
      friends: [{ profileId, friendshipId, friendshipRevision: 7, displayName: "Retry Friend" }]
    };
    activeWorkout = null;
    workoutDraft = { startedAt: Date.now(), note: "retry", blocks: [] };
    workoutDraftLiveRecipient = { profileId, friendshipId, friendshipRevision: 7 };
    normalizeSocialWorkoutPlan = value => value;
    prepareLiveRequest = () => ({ requestId: "00000000-0000-4000-8000-000000000003" });
    liveSessionIdentity = () => ({ userId, sessionId });
    reserveLiveWorkoutSlot = async () => true;
    executeLiveWorkoutMutation = async () => ({
      result: "submitted_or_unavailable",
      roomId: null
    });
    clearLiveWorkoutSlot = async () => true;
    refreshLiveWorkoutData = async () => {};
    render = () => {};
    showToast = () => {};
    window.GymLiveWorkout = { sendResult: value => value };
    let persisted = 0;
    persistWorkoutDraft = () => { persisted += 1; return true; };
    const sent = await sendLiveWorkoutPlan(profileId, { exercises: [] });
    return { sent, persisted, recipient: workoutDraftLiveRecipient, draft: workoutDraft };
  })()`, sandbox));

  assert.equal(result.sent, true);
  assert.equal(result.persisted, 0);
  assert.deepEqual(result.recipient, {
    profileId: "p_0123456789abcdef0123456789abcdef",
    friendshipId: "f_0123456789abcdef0123456789abcdef",
    friendshipRevision: 7
  });
  assert.equal(result.draft.note, "retry");
});

test("authoritative friendship mismatch cannot downgrade a LIVE-bound draft to solo", async () => {
  const sandbox = context();
  const result = plain(await vm.runInContext(`(async () => {
    const userId = "00000000-0000-4000-8000-000000000001";
    const recipient = {
      profileId: "p_0123456789abcdef0123456789abcdef",
      friendshipId: "f_0123456789abcdef0123456789abcdef",
      friendshipRevision: 7
    };
    accountEpoch = 12;
    activeAccount = { remote: "supabase", userId };
    activeWorkout = null;
    workoutDraft = { startedAt: Date.now(), note: "keep live", blocks: [] };
    workoutDraftLiveRecipient = { ...recipient };
    socialState.dashboard = {
      friends: [{ ...recipient, friendshipRevision: 8, displayName: "Recreated Friend" }]
    };
    boundWorkoutDraftLiveRecipient = () => ({ ...workoutDraftLiveRecipient });
    refreshSocialData = async () => true;
    let sends = 0;
    sendLiveWorkoutPlan = async () => { sends += 1; return true; };
    let renders = 0;
    render = () => { renders += 1; };
    showToast = () => {};
    const sent = await sendWorkoutDraftLiveInvite();
    return {
      sent,
      sends,
      renders,
      draft: workoutDraft,
      recipient: workoutDraftLiveRecipient
    };
  })()`, sandbox));

  assert.equal(result.sent, false);
  assert.equal(result.sends, 0);
  assert.equal(result.renders, 3);
  assert.equal(result.draft.note, "keep live");
  assert.deepEqual(result.recipient, {
    profileId: "p_0123456789abcdef0123456789abcdef",
    friendshipId: "f_0123456789abcdef0123456789abcdef",
    friendshipRevision: 7
  });
});

test("direct LIVE preflight gates repeat taps and preserves edits made after the sent snapshot", async () => {
  const sandbox = context();
  const repeat = plain(await vm.runInContext(`(async () => {
    const userId = "00000000-0000-4000-8000-000000000001";
    const recipient = {
      profileId: "p_0123456789abcdef0123456789abcdef",
      friendshipId: "f_0123456789abcdef0123456789abcdef",
      friendshipRevision: 7
    };
    accountEpoch = 3;
    activeAccount = { remote: "supabase", userId };
    activeWorkout = null;
    workoutDraft = { startedAt: Date.now(), note: "original", blocks: [] };
    workoutDraftLiveRecipient = { ...recipient };
    socialState.dashboard = { friends: [{ ...recipient, displayName: "Friend" }] };
    boundWorkoutDraftLiveRecipient = () => ({ ...workoutDraftLiveRecipient });
    let releaseRefresh;
    refreshSocialData = () => new Promise(resolve => { releaseRefresh = resolve; });
    sharedWorkoutPlanFromDraft = () => ({ exercises: [] });
    sendLiveWorkoutPlan = async () => true;
    render = () => {};
    showToast = () => {};
    const first = sendWorkoutDraftLiveInvite();
    const busyBeforeRelease = workoutDraftLiveSendInProgress;
    const second = await sendWorkoutDraftLiveInvite();
    releaseRefresh(true);
    const firstResult = await first;
    return { busyBeforeRelease, second, firstResult, busyAfter: workoutDraftLiveSendInProgress };
  })()`, sandbox));

  assert.deepEqual(repeat, {
    busyBeforeRelease: true,
    second: false,
    firstResult: true,
    busyAfter: false
  });

  const changed = plain(await vm.runInContext(`(async () => {
    const recipient = {
      profileId: "p_0123456789abcdef0123456789abcdef",
      friendshipId: "f_0123456789abcdef0123456789abcdef",
      friendshipRevision: 7
    };
    workoutDraft = { startedAt: Date.now(), note: "sent snapshot", blocks: [] };
    workoutDraftLiveRecipient = { ...recipient };
    socialState.dashboard = { friends: [{ ...recipient, displayName: "Friend" }] };
    boundWorkoutDraftLiveRecipient = () => workoutDraftLiveRecipient ? ({ ...workoutDraftLiveRecipient }) : null;
    refreshSocialData = async () => true;
    sharedWorkoutPlanFromDraft = draft => ({ note: draft.note, exercises: [] });
    window.GymLiveWorkout = { patterns: { ROOM_ID: /^lr_[0-9a-f]{32}$/ } };
    sendLiveWorkoutPlan = async () => {
      workoutDraft.note = "newer edit";
      modal = { type: "live-invitation-sent", roomId: "lr_0123456789abcdef0123456789abcdef" };
      return true;
    };
    let clears = 0;
    clearWorkoutDraft = () => { clears += 1; workoutDraft = null; workoutDraftLiveRecipient = null; };
    let persists = 0;
    persistWorkoutDraft = () => { persists += 1; return true; };
    const sent = await sendWorkoutDraftLiveInvite();
    return {
      sent,
      clears,
      persists,
      note: workoutDraft?.note,
      recipient: workoutDraftLiveRecipient,
      busy: workoutDraftLiveSendInProgress
    };
  })()`, sandbox));

  assert.deepEqual(changed, {
    sent: true,
    clears: 0,
    persists: 1,
    note: "newer edit",
    recipient: null,
    busy: false
  });
  assert.match(appSource, /current\.name === "add" && workoutDraftLiveSendInProgress[\s\S]{0,80}inert aria-busy="true"/);
  assert.match(appSource, /if \(workoutDraftLiveSendInProgress && route\(\)\.name === "add"\) return false/);
});

test("fmtShortDate matches the iOS short date in EN, UK, and RU", () => {
  const sandbox = context();
  const now = new Date(2026, 8, 29, 12).getTime();
  const cases = [
    ["en", new Date(2026, 8, 26, 12).getTime(), "Sat, Sep 26"],
    ["en", new Date(2025, 7, 14, 12).getTime(), "Thu, Aug 14, 2025"],
    ["uk", new Date(2026, 8, 26, 12).getTime(), "сб, 26 вер."],
    ["uk", new Date(2025, 7, 14, 12).getTime(), "чт, 14 серп. 2025 р."],
    ["ru", new Date(2026, 8, 26, 12).getTime(), "Сб, 26 сент."],
    ["ru", new Date(2025, 7, 14, 12).getTime(), "Чт, 14 авг. 2025 г."]
  ];
  for (const [language, timestamp, expected] of cases) {
    sandbox.language = language;
    sandbox.timestamp = timestamp;
    sandbox.now = now;
    const actual = vm.runInContext(`(() => { state.language = language; return fmtShortDate(timestamp, now); })()`, sandbox);
    assert.equal(actual, expected, `${language} ${expected}`);
  }
});

test("fmtCompactDuration reproduces the iOS abbreviated hour/minute duration", () => {
  const sandbox = context();
  const cases = [
    ["en", 16271, "4h 31m"], ["en", 3600, "1h"], ["en", 2700, "45m"], ["en", 7260, "2h 1m"],
    ["en", 30, "0m"], ["en", 86400, "24h"], ["en", 3660, "1h 1m"],
    ["uk", 16271, "4\u202fг 31\u202fхв"], ["uk", 3600, "1\u202fг"], ["uk", 2700, "45\u202fхв"], ["uk", 7260, "2\u202fг 1\u202fхв"],
    ["ru", 16271, "4 ч 31 мин"], ["ru", 3600, "1 ч"], ["ru", 2700, "45 мин"], ["ru", 7260, "2 ч 1 мин"],
    ["en", 0, ""], ["en", null, ""], ["ru", undefined, ""], ["uk", -5, ""]
  ];
  for (const [language, seconds, expected] of cases) {
    sandbox.language = language;
    sandbox.seconds = seconds;
    const actual = vm.runInContext(`(() => { state.language = language; return fmtCompactDuration(seconds); })()`, sandbox);
    assert.equal(actual, expected, `${language} ${seconds}`);
  }
});

test("post-workout summary shows the iOS hero, records, badges, and actions", () => {
  const sandbox = context();
  const out = JSON.parse(vm.runInContext(`JSON.stringify((() => {
    const at = new Date(2026, 0, 5, 12).getTime();
    const later = new Date(2026, 0, 6, 12).getTime();
    const make = (id, startedAt, sets, durationSeconds) => ({
      id, startedAt, note: "", durationSeconds,
      exerciseNames: [...new Set(sets.map(set => set[0]))],
      sets: sets.map(([exerciseName, weight, reps], index) => ({ id: id * 10 + index, exerciseName, weight, reps, orderIndex: index }))
    });
    const first = make(1, at, [["Bench Press", 50, 8], ["Squat", 0, 10], ["Row", 40, 10]], 3600);
    const second = make(2, later, [["Bench Press", 60, 8], ["Squat", 0, 12], ["Row", 40, 10], ["Curl", 10, 10]], 16271);
    state = { ...defaultAppState(), language: "en", sessions: [first, second] };
    const screen = summaryScreen(2);
    const firstScreen = summaryScreen(1);
    state.language = "ru";
    const ruScreen = summaryScreen(2);
    return { screen, firstScreen, ruScreen, records: summaryPersonalRecords(second).map(item => ({ name: item.name, weight: item.weight, est: item.estimatedOneRepMax })) };
  })())`, sandbox));
  const { screen } = out;
  assert.match(screen, /Workout complete/);
  assert.match(screen, /Tue, Jan 6 · 4h 31m/);
  assert.match(screen, /\+\d+ XP<\/strong><span>Session XP/);
  assert.match(screen, /Level \d+ · [^<]+<\/strong><div class="progress"/);
  assert.match(screen, /\d+ XP to level \d+/);
  assert.doesNotMatch(screen, /metric-grid|summary-metrics|Level progress|Week streak|Most loaded|Previous best/);
  assert.match(screen, />Easy<[\s\S]*>Just right<[\s\S]*>Hard</);
  // Only Bench Press is a record: Row ties, Squat is 0 kg, Curl is a first session.
  assert.deepEqual(out.records.map(item => item.name), ["Bench Press"]);
  assert.match(screen, /New records/);
  assert.match(screen, /60 kg · Est\. 1RM 76 kg/);
  assert.doesNotMatch(screen, /<strong>Squat<|<strong>Row<|<strong>Curl</);
  assert.doesNotMatch(out.firstScreen, /New records/);
  assert.match(out.firstScreen, /New badges/);
  assert.match(out.firstScreen, /class="achievement-tile[^"]* static"/);
  assert.doesNotMatch(out.firstScreen, /data-action="open-achievement"/);
  assert.doesNotMatch(screen, /New badges/);
  assert.match(screen, /data-action="summary-done">Done<\/button>/);
  assert.match(screen, /data-action="summary-view"[^>]*>Workout details</);
  assert.match(out.ruScreen, /Тренировка завершена/);
  assert.match(out.ruScreen, /Как было\?/);
  assert.match(out.ruScreen, /В самый раз/);
  assert.match(out.ruScreen, /Новые рекорды/);
  assert.match(out.ruScreen, /60 кг · 1ПМ 76 кг/);
  assert.match(out.ruScreen, /Детали тренировки/);
});

test("summary feedback chips stay one row of three equal columns and stack only on very narrow screens", () => {
  const rule = selector => stylesSource.match(new RegExp(`${selector.replace(/[.[\]]/g, "\\$&")}\\s*\\{([^}]*)\\}`))?.[1] || "";
  assert.match(rule(".segmented.workout-feedback-options"), /grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)/);
  const button = rule(".segmented.workout-feedback-options button");
  assert.match(button, /min-height:\s*44px/);
  assert.match(button, /border:\s*1px solid/);
  assert.match(button, /white-space:\s*nowrap/);
  assert.match(rule(".segmented.workout-feedback-options button.selected"), /background:\s*var\(--primary\)/);
  assert.match(stylesSource, /@media \(max-width: 340px\) \{\s*\.segmented\.workout-feedback-options \{ grid-template-columns: 1fr; \}/);
});

test("fmtDateRange matches the iOS weekly-review range in EN, UK, and RU", () => {
  const sandbox = context();
  const now = new Date(2026, 8, 29, 12).getTime();
  const range = (fromYear, fromMonth, fromDay, toYear, toMonth, toDay) => [
    new Date(fromYear, fromMonth, fromDay, 12).getTime(),
    new Date(toYear, toMonth, toDay, 12).getTime()
  ];
  const cases = [
    ["en", range(2026, 8, 21, 2026, 8, 27), "Sep 21\u2009\u2013\u200927"],
    ["en", range(2026, 8, 28, 2026, 9, 4), "Sep 28\u2009\u2013\u2009Oct 4"],
    ["en", range(2025, 8, 22, 2025, 8, 28), "Sep 22\u2009\u2013\u200928, 2025"],
    ["en", range(2025, 11, 29, 2026, 0, 4), "Dec 29, 2025\u2009\u2013\u2009Jan 4, 2026"],
    ["uk", range(2026, 8, 21, 2026, 8, 27), "21\u201327 вер."],
    ["uk", range(2026, 8, 28, 2026, 9, 4), "28 вер. \u2013 4 жовт."],
    ["uk", range(2025, 8, 22, 2025, 8, 28), "22\u201328 вер. 2025\u202fр."],
    ["uk", range(2025, 11, 29, 2026, 0, 4), "29 груд. 2025 \u2013 4 січ. 2026\u202fрр."],
    ["ru", range(2026, 8, 21, 2026, 8, 27), "21\u201427 сент."],
    ["ru", range(2026, 8, 28, 2026, 9, 4), "28 сент. \u2014 4 окт."],
    ["ru", range(2025, 8, 22, 2025, 8, 28), "22\u201428 сент. 2025\u202fг."],
    ["ru", range(2025, 11, 29, 2026, 0, 4), "29 дек. 2025 \u2014 4 янв. 2026\u202fг."]
  ];
  for (const [language, [start, end], expected] of cases) {
    sandbox.language = language;
    sandbox.start = start;
    sandbox.end = end;
    sandbox.now = now;
    const actual = vm.runInContext(`(() => { state.language = language; return fmtDateRange(start, end, now); })()`, sandbox);
    assert.equal(actual, expected, `${language} ${expected}`);
  }
  assert.equal(vm.runInContext("fmtDateRange(NaN, 0, now)", sandbox), "");
});

test("Progress overview uses the shared inline navigator, compact hero, and lifetime card", () => {
  const sandbox = context();
  const run = (language, code) => {
    sandbox.language = language;
    return vm.runInContext(`(() => { state.language = language; ${code} })()`, sandbox);
  };
  for (const [language, completed, target, expected] of [
    ["en", 1, 1, "1 of 1 workout"], ["en", 2, 4, "2 of 4 workouts"], ["uk", 2, 1, "2 з 1 тренування"],
    ["uk", 2, 4, "2 з 4 тренувань"], ["ru", 2, 1, "2 из 1 тренировки"], ["ru", 2, 5, "2 из 5 тренировок"]
  ]) {
    assert.equal(run(language, `return weeklyReviewTitle(${completed}, ${target});`), expected);
  }
  const review = run("en", "return trainingWeeklyReviewMarkup();");
  assert.match(review, /Comparison with previous weeks appears after a couple of weeks of training\./);
  assert.match(review, /class="training-settings-link" data-action="open-training-settings">Training settings · edit</);
  assert.doesNotMatch(review, /training days|Not enough comparable/);
  assert.match(run("ru", "return trainingWeeklyReviewMarkup();"), /Настройки тренировок · изменить/);

  const nav = run("ru", "return monthNavigatorInline();");
  assert.match(nav, /data-action="month-prev"[\s\S]*data-action="month-current"[\s\S]*data-action="month-next"/);
  assert.match(nav, /aria-label="Текущий месяц, [^"]+"/);
  assert.match(nav, /<span class="month-nav-badge">Текущий месяц<\/span>/);
  assert.doesNotMatch(nav, /heat-cell|month-switcher/);
  assert.match(stylesSource, /\.month-navigator-inline \.month-nav-chevron \{[^}]*width: 44px;[^}]*height: 44px;/);

  const hero = run("en", "return soloProgressHero();");
  assert.match(hero, /Solo progress/);
  assert.match(hero, /class="pill hero-pill">Level 1</);
  assert.match(hero, /class="solo-xp-compact"[^>]*>0 XP<\/span><span class="solo-xp-earned"[^>]*>0 XP earned</);
  assert.match(hero, /<span>Month XP<\/span>[\s\S]*<span>Next title<\/span>/);
  assert.match(hero, /data-action="open-ranks"/);
  assert.doesNotMatch(hero, /TOTAL XP|hero-split|Week streak/);
  assert.match(run("uk", "return soloProgressHero();"), /Наступний титул[\s\S]*Переглянути ранги/);
  assert.match(stylesSource, /\.solo-progress-hero \{[^}]*linear-gradient\(145deg, var\(--brand-fill\)/);

  const lifetime = run("ru", "return lifetimeProgressCard();");
  assert.match(lifetime, /Прогресс за всё время[\s\S]*Тренировки[\s\S]*Серия недель[\s\S]*Объём/);

  const heatmap = run("en", "return activityHeatmapCard();");
  assert.match(heatmap, /<h2>Activity Heatmap<\/h2><div class="month-navigator-inline">/);
  assert.doesNotMatch(heatmap, /Sessions|metric-grid/);
  const muscle = run("en", "return muscleMapCard();");
  assert.doesNotMatch(muscle.split('<div class="period-tabs">')[0], /class="pill"/);
  assert.match(muscle, /metric-grid three tile-emphasized/);
  const overview = appSource.slice(appSource.indexOf("function progressScreen()"), appSource.indexOf("function exerciseProgressPanel()"));
  assert.doesNotMatch(overview.slice(overview.indexOf("} else {\n    content")), /monthSwitcher\(\)/);
});

test("training history states the weekly goal, shows volume with its unit, and uses short row dates", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    state.profile = { split: "Upper / Lower", days: 2, goal: "Strength", calories: "Maintenance" };
    const startedAt = Date.now();
    const make = (id, weight, extra = {}) => ({
      id, startedAt: startedAt - id, note: "", exerciseNames: ["Leg Press"],
      sets: [{ id: id * 100, exerciseName: "Leg Press", weight, reps: 10, orderIndex: 0 }], ...extra
    });
    state.sessions = [make(1, 50)];
    workoutHistoryPeriod = "week";
    const out = {};
    for (const language of ["en", "uk", "ru"]) {
      state.language = language;
      out[language] = { partial: trainingHistoryMarkup(), shortDate: fmtShortDate(startedAt - 1) };
    }
    state.language = "en";
    out.activityOnly = trainingHistoryWorkoutRow({
      id: 9, startedAt, note: "", exerciseNames: [], sets: [], durationSeconds: 1800
    });
    const monday = localMondayStart(Date.now() - 7 * 86400000);
    state.sessions = [make(1, 50, { startedAt: monday + 12 * 3600000 }), make(2, 60, { startedAt: monday + 36 * 3600000 })];
    workoutWeekOffset = -1;
    out.metWeek = trainingHistoryMarkup();
    workoutWeekOffset = 0;
    workoutHistoryPeriod = "month";
    out.month = trainingHistoryMarkup();
    workoutHistoryPeriod = "week";
    return out;
  })()`, sandbox));
  const goals = {
    en: ["Goal: 1 of 2", "Weekly goal: 1 of 2"],
    uk: ["Ціль: 1 з 2", "Ціль тижня: 1 з 2"],
    ru: ["Цель: 1 из 2", "Цель недели: 1 из 2"]
  };
  for (const [language, [visible, label]] of Object.entries(goals)) {
    const markup = result[language].partial;
    assert.match(markup, new RegExp(`<span role="group" aria-label="${label}"><svg[^>]*>.*?</svg>${visible}</span>`));
    assert.doesNotMatch(markup, /1 \/ 2 (days|днів|дней)/);
    assert.match(markup, new RegExp(`<strong>${result[language].shortDate}</strong>`));
    assert.match(markup, language === "en" ? /<b>[^<]+ kg<\/b>/ : /<b>[^<]+ кг<\/b>/);
  }
  assert.match(result.en.partial, /M12 2C6\.48|M20\.57 14\.86/);
  assert.doesNotMatch(result.en.partial, /M12 2C6\.48 2 2 6\.48/);
  assert.match(result.metWeek, /Goal: 2 of 2/);
  assert.match(result.metWeek, /<span role="group"[^>]*><svg[^>]*><path d="M12 2C6\.48/);
  assert.match(result.activityOnly, /<b>[^<]*30[^<]*<\/b>/);
  assert.doesNotMatch(result.activityOnly, / kg<\/b>/);
  assert.doesNotMatch(result.month, /Goal:|Weekly goal/);
  assert.match(stylesSource, /\.training-history-head > span \{[^}]*display: inline-flex[^}]*gap:/);
  assert.doesNotMatch(stylesSource.match(/\.training-history-row > b \{[^}]*\}/)[0], /background|border-radius/);
});

test("active workout Today card leads with the current exercise and set progress", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeWorkout = { blocks: [
      { exerciseName: "Bench Press", sets: [{ completed: true }, { completed: true }] },
      { exerciseName: "Squat", sets: [{ completed: true }, { completed: false }, { completed: false }] }
    ] };
    const out = {};
    for (const language of ["en", "uk", "ru"]) {
      state.language = language;
      out[language] = { markup: focusLensCard([]), name: exerciseDisplayName(activeWorkout.blocks[1], language) };
    }
    state.language = "ru";
    activeWorkout = { blocks: [{ exerciseName: "Squat", sets: [{ completed: true }] }] };
    out.done = focusLensCard([]);
    return out;
  })()`, sandbox));
  const subtitle = {
    en: "Set 2 · 3 / 5 completed", uk: "Підхід 2 · виконано 3 / 5", ru: "Подход 2 · выполнено 3 / 5"
  };
  const discard = { en: "Discard workout", uk: "Відкинути тренування", ru: "Удалить тренировку" };
  for (const language of ["en", "uk", "ru"]) {
    const { markup, name } = result[language];
    assert.match(markup, new RegExp(`<h2 id="focus-lens-title">${name}</h2>`));
    assert.match(markup, new RegExp(`<p>${subtitle[language]}</p>`));
    assert.match(markup, new RegExp(`data-action="discard-active-workout">${discard[language]}</button>`));
    assert.doesNotMatch(markup, /focus-lens-eyebrow|focus-lens-metrics|Continue where you stopped|WORKOUT IN PROGRESS/);
    assert.match(markup, /data-action="continue-active-workout"/);
    assert.match(markup, /focus-lens-details/);
  }
  assert.match(result.done, /<h2 id="focus-lens-title">Следующее упражнение<\/h2>/);
  assert.match(result.done, /Подход 1 · выполнено 1 \/ 1/);
});
