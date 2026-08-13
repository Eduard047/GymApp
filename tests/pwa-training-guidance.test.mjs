import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource, progressionSource, russianSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/progression-rules.js", "utf8"),
  readFile("pwa/russian-text.js", "utf8")
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

test("missing or corrupt profiles use the shared defaults while valid stored profiles survive", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    const fallback = defaultAppState();
    const missing = GymStateContract.validateAndNormalize({
      schemaVersion: 2,
      language: "en",
      exercises: [], sessions: [], mappings: {}, profile: {}
    }, { fallback }).state.profile;
    const corrupt = GymStateContract.validateAndNormalize({
      schemaVersion: 2,
      language: "en",
      exercises: [], sessions: [], mappings: {},
      profile: { split: "<script>", days: 99, goal: "owner", calories: "admin" }
    }, { fallback }).state.profile;
    const valid = GymStateContract.validateAndNormalize({
      schemaVersion: 2,
      language: "en",
      exercises: [], sessions: [], mappings: {},
      profile: { split: "Full Body", days: 2, goal: "Strength", calories: "Maintenance" }
    }, { fallback }).state.profile;
    return { defaults: fallback.profile, missing, corrupt, valid };
  })()`, sandbox));

  const defaults = { split: "Upper / Lower", days: 4, goal: "Aesthetic Cut", calories: "Deficit" };
  assert.deepEqual(result.defaults, defaults);
  assert.deepEqual(result.missing, defaults);
  assert.deepEqual(result.corrupt, defaults);
  assert.deepEqual(result.valid, {
    split: "Full Body", days: 2, goal: "Strength", calories: "Maintenance"
  });
});

test("first-workout activation derives the exact profile matrix and skip stays account-local", () => {
  const sandbox = context();
  const matrix = plain(vm.runInContext(`(() => {
    const rows = [];
    for (const days of [2, 3, 4, 5, 6]) {
      for (const goal of ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"]) {
        rows.push({ days, goal, result: profileFromActivation({ days, goal, effort: "Standard" }) });
      }
    }
    return rows;
  })()`, sandbox));
  for (const { days, goal, result } of matrix) {
    assert.equal(result.profile.split, days <= 3 ? "Full Body" : days === 4 ? "Upper / Lower" : "Push Pull Legs");
    assert.equal(result.profile.calories, goal === "Aesthetic Cut" ? "Deficit" : goal === "Muscle Gain" ? "Surplus" : "Maintenance");
    assert.equal(result.effort, "Standard");
  }
  const canonicalDraft = plain(vm.runInContext(`(() => {
    state.profile = { split: "Push Pull Legs", days: 5, goal: "Strength", calories: "Maintenance" };
    return defaultActivationDraft();
  })()`, sandbox));
  assert.deepEqual(canonicalDraft, { goal: "Aesthetic Cut", days: 4, effort: "Standard" });

  const skipped = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    state.profile = { split: "Custom", days: 2, goal: "Balanced", calories: "Maintenance" };
    state.sessions = [];
    activeWorkout = null;
    nav = [{ name: "workouts" }];
    render = () => {};
    replaceNavigationHistory = () => {};
    let pushedNavigation = 0;
    pushNavigationHistory = () => { pushedNavigation += 1; };
    queueRemoteSave = () => {};
    activationDraft = { owner: "local:alpha", goal: "Strength", days: 5, effort: "Hard" };
    const completed = completeFirstWorkoutActivation(true);
    const firstAccount = {
      completed,
      dismissed: activationWasDismissed(),
      profile: state.profile,
      persistedState: localStorage.getItem(activeStorageKey()),
      route: route().name,
      blocks: workoutDraft.blocks,
      pushedNavigation
    };
    activeAccount = { id: "beta", name: "Beta" };
    state = defaultAppState();
    state.sessions = [];
    nav = [{ name: "workouts" }];
    return {
      firstAccount,
      secondDismissed: activationWasDismissed(),
      secondMarkup: workoutsScreen()
    };
  })()`, sandbox));

  assert.equal(skipped.firstAccount.completed, true);
  assert.equal(skipped.firstAccount.dismissed, true);
  assert.equal(skipped.firstAccount.route, "add");
  assert.equal(skipped.firstAccount.pushedNavigation, 1);
  assert.deepEqual(skipped.firstAccount.profile, {
    split: "Custom", days: 2, goal: "Balanced", calories: "Maintenance"
  });
  assert.equal(skipped.firstAccount.persistedState, null);
  assert.deepEqual(skipped.firstAccount.blocks, [{ exerciseName: "", sets: [{ weight: "", reps: "" }] }]);
  assert.equal(skipped.secondDismissed, false);
  assert.match(skipped.secondMarkup, /Goal/);
});

test("activation guidance failure leaves the profile, local state, and remote queue untouched", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    state.profile = { split: "Custom", days: 2, goal: "Balanced", calories: "Maintenance" };
    state.sessions = [];
    activeWorkout = null;
    workoutDraft = null;
    nav = [{ name: "workouts" }];
    render = () => {};
    replaceNavigationHistory = () => {};
    let remoteQueueCount = 0;
    queueRemoteSave = () => { remoteQueueCount += 1; };
    activationDraft = { owner: "local:alpha", goal: "Strength", days: 5, effort: "Hard" };
    writeTrainingGuidance = () => false;
    const completed = completeFirstWorkoutActivation(false);
    return {
      completed,
      remoteQueueCount,
      profile: state.profile,
      stateStorage: localStorage.getItem(activeStorageKey()),
      guidanceStorage: localStorage.getItem(trainingGuidanceAccountDescriptor().storageKey),
      route: route().name,
      hasDraft: workoutDraft !== null,
      dismissed: activationWasDismissed()
    };
  })()`, sandbox));

  assert.deepEqual(result, {
    completed: false,
    remoteQueueCount: 0,
    profile: { split: "Custom", days: 2, goal: "Balanced", calories: "Maintenance" },
    stateStorage: null,
    guidanceStorage: null,
    route: "workouts",
    hasDraft: false,
    dismissed: false
  });
});

test("feedback sidecar is exact, idempotent, pruned to 128, neutral on malformed data, and account-bound", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    const now = Date.now();
    state.sessions = Array.from({ length: 130 }, (_, index) => ({
      id: index + 1,
      startedAt: now - index * 3600000,
      note: "",
      exerciseNames: ["Bench Press"],
      sets: [{ id: 10000 + index, exerciseName: "Bench Press", weight: 40, reps: 8, orderIndex: 0 }]
    }));
    const descriptor = trainingGuidanceAccountDescriptor();
    const oversized = {
      version: 1,
      owner: descriptor.owner,
      activationDismissed: false,
      feedback: state.sessions.map(session => ({
        sessionId: session.id, startedAt: session.startedAt, value: "normal"
      })).reverse()
    };
    const wrote = writeTrainingGuidance(oversized);
    saveWorkoutFeedback(1, "easy");
    saveWorkoutFeedback(1, "easy");
    const bounded = readTrainingGuidance();
    const accountAKey = descriptor.storageKey;
    const accountAValue = workoutFeedbackValue(1);
    activeAccount = { id: "beta", name: "Beta" };
    const accountBKey = trainingGuidanceAccountDescriptor().storageKey;
    const accountBValue = workoutFeedbackValue(1);
    activeAccount = { id: "alpha", name: "Alpha" };
    localStorage.setItem(accountAKey, JSON.stringify({
      version: 1,
      owner: "local:alpha",
      activationDismissed: true,
      feedback: [{ sessionId: 1, startedAt: state.sessions[0].startedAt, value: "<img src=x onerror=alert(1)>" }]
    }));
    const malformed = readTrainingGuidance();
    const markup = workoutFeedbackPanel(state.sessions[0]);
    return {
      wrote,
      boundedCount: bounded.feedback.length,
      newest: bounded.feedback[0].sessionId,
      oldestKept: bounded.feedback.at(-1).sessionId,
      duplicateCount: bounded.feedback.filter(entry => entry.sessionId === 1).length,
      accountAKey, accountBKey, accountAValue, accountBValue,
      malformed,
      markup
    };
  })()`, sandbox));

  assert.equal(result.wrote, true);
  assert.equal(result.boundedCount, 128);
  assert.equal(result.newest, 1);
  assert.equal(result.oldestKept, 128);
  assert.equal(result.duplicateCount, 1);
  assert.notEqual(result.accountAKey, result.accountBKey);
  assert.equal(result.accountAValue, "easy");
  assert.equal(result.accountBValue, null);
  assert.deepEqual(result.malformed, {
    version: 1, owner: "local:alpha", activationDismissed: false, feedback: []
  });
  assert.doesNotMatch(result.markup, /onerror|<img|alert\(/i);
});

test("latest feedback is bounded to the newest completed local-day session", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    const now = new Date(2026, 7, 12, 18).getTime();
    const makeSession = (id, days) => ({
      id,
      startedAt: new Date(2026, 7, 12 - days, 12).getTime(),
      note: "", exerciseNames: ["Leg Press"],
      sets: [{ id: id * 100, exerciseName: "Leg Press", weight: 50, reps: 8, orderIndex: 0 }]
    });
    state.sessions = [makeSession(1, 2), makeSession(2, 1)];
    saveWorkoutFeedback(1, "hard");
    saveWorkoutFeedback(2, "normal");
    const newestWins = latestWorkoutFeedback(now);
    state.sessions = [makeSession(3, 8)];
    saveWorkoutFeedback(3, "hard");
    const stale = latestWorkoutFeedback(now);
    state.sessions = [{ ...makeSession(4, 0), startedAt: now + 1 }];
    saveWorkoutFeedback(4, "hard");
    const future = latestWorkoutFeedback(now);
    return { newestWins, stale, future };
  })()`, sandbox));

  assert.equal(result.newestWins.sessionId, 2);
  assert.equal(result.newestWins.value, "normal");
  assert.equal(result.stale, null);
  assert.equal(result.future, null);
});

test("Auto feedback effect is bounded: hard recovers, normal is neutral, easy adds at most one unchanged set", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    state.profile = { split: "Push Pull Legs", days: 5, goal: "Balanced", calories: "Maintenance" };
    const startedAt = new Date();
    startedAt.setHours(12, 0, 0, 0);
    startedAt.setDate(startedAt.getDate() - 2);
    state.sessions = [{
      id: 1, startedAt: startedAt.getTime(), note: "", exerciseNames: ["Leg Press", "Leg Extension"],
      sets: [
        { id: 101, exerciseName: "Leg Press", weight: 80, reps: 8, orderIndex: 0 },
        { id: 102, exerciseName: "Leg Extension", weight: 40, reps: 10, orderIndex: 0 }
      ]
    }];
    removeTrainingGuidanceStorage();
    const baseline = buildSmartWorkoutPlan("Auto");
    saveWorkoutFeedback(1, "normal");
    const normal = buildSmartWorkoutPlan("Auto");
    saveWorkoutFeedback(1, "easy");
    const easy = buildSmartWorkoutPlan("Auto");
    const originalRecommendation = smartRecommendation;
    let recommendationIndex = 0;
    smartRecommendation = (...args) => {
      const recommendation = originalRecommendation(...args);
      if (recommendationIndex++ === 0) recommendation.kindId = "Deload";
      return recommendation;
    };
    const mixedProtective = buildSmartWorkoutPlan("Auto");
    smartRecommendation = originalRecommendation;
    saveWorkoutFeedback(1, "hard");
    const hard = buildSmartWorkoutPlan("Auto");
    const explicit = buildSmartWorkoutPlan("Standard");
    return { baseline, normal, easy, mixedProtective, hard, explicit };
  })()`, sandbox));

  assert.deepEqual(result.normal, result.baseline);
  const total = plan => plan.exercises.reduce((sum, exercise) => sum + exercise.recommendation.sets.length, 0);
  assert.equal(result.easy.feedbackBonusSets, 1);
  assert.equal(result.easy.adjustment, "One safe set was added after your latest feedback.");
  assert.equal(total(result.easy), total(result.baseline) + 1);
  assert.ok(result.easy.exercises.length <= 8);
  assert.ok(result.easy.exercises.every(exercise => exercise.recommendation.sets.length <= 4));
  assert.ok(total(result.easy) <= 24 && total(result.easy) <= result.easy.setBudget);
  const changed = result.easy.exercises.filter((exercise, index) =>
    exercise.recommendation.sets.length !== result.baseline.exercises[index].recommendation.sets.length
  );
  assert.equal(changed.length, 1);
  const extraExercise = changed[0];
  const beforeExercise = result.baseline.exercises.find(exercise => exercise.name === extraExercise.name);
  assert.deepEqual(extraExercise.recommendation.sets.at(-1), beforeExercise.recommendation.sets.at(-1));
  assert.equal(result.mixedProtective.feedbackBonusSets, 0);
  assert.ok(result.mixedProtective.exercises.some(exercise => exercise.recommendation.kindId === "Deload"));
  assert.equal(result.hard.appliedEffort, "Recovery");
  assert.equal(result.hard.feedbackBonusSets, 0);
  assert.notEqual(result.hard.appliedEffort, "Hard");
  assert.equal(result.explicit.appliedEffort, "Standard");
  assert.equal(result.explicit.feedbackBonusSets, 0);
});

test("easy feedback never raises Smart-plan metadata beyond the 24-set contract", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    state.profile = { split: "Full Body", days: 2, goal: "Muscle Gain", calories: "Surplus" };
    state.exercises = state.exercises.slice(0, 2);
    const startedAt = new Date();
    startedAt.setHours(12, 0, 0, 0);
    startedAt.setDate(startedAt.getDate() - 2);
    const exerciseName = state.exercises[0].name;
    state.sessions = [{
      id: 1, startedAt: startedAt.getTime(), note: "", exerciseNames: [exerciseName],
      sets: [{ id: 101, exerciseName, weight: 20, reps: 8, orderIndex: 0 }]
    }];
    removeTrainingGuidanceStorage();
    saveWorkoutFeedback(1, "easy");
    const originalRecommendation = smartRecommendation;
    smartRecommendation = (...args) => {
      const recommendation = originalRecommendation(...args);
      recommendation.sets = recommendation.sets.slice(0, 3);
      return recommendation;
    };
    const plan = buildSmartWorkoutPlan("Auto");
    smartRecommendation = originalRecommendation;
    return plan;
  })()`, sandbox));

  assert.equal(result.feedbackBonusSets, 1);
  assert.equal(result.setBudget, 24);
  assert.ok(result.exercises.reduce((sum, exercise) =>
    sum + exercise.recommendation.sets.length, 0) <= result.setBudget);
});

test("prepared Smart launch opens the exact bounded plan without recomputation and rejects stale state", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    state.profile = { split: "Upper / Lower", days: 4, goal: "Aesthetic Cut", calories: "Deficit" };
    activeWorkout = null;
    render = () => {};
    replaceNavigationHistory = () => {};
    let pushedNavigation = 0;
    pushNavigationHistory = () => { pushedNavigation += 1; };
    const launch = prepareSmartWorkoutLaunch("Standard", "dashboard");
    const expected = launch.plan.exercises.map(exercise => ({
      exerciseName: exercise.name,
      catalogKey: exercise.catalogKey || null,
      sets: exercise.recommendation.sets.map(set => ({ weight: set.weight ?? "", reps: set.reps }))
    }));
    const originalBuilder = buildSmartWorkoutPlan;
    buildSmartWorkoutPlan = () => { throw new Error("must not recompute"); };
    const opened = launchPreparedSmartWorkout(launch);
    const replayOpened = launchPreparedSmartWorkout(launch);
    buildSmartWorkoutPlan = originalBuilder;
    const actual = workoutDraft.blocks.map(block => ({
      exerciseName: block.exerciseName,
      catalogKey: block.catalogKey || null,
      sets: block.sets.map(set => ({ weight: set.weight, reps: set.reps }))
    }));
    const caps = {
      exercises: launch.plan.exercises.length,
      totalSets: launch.plan.exercises.reduce((sum, exercise) => sum + exercise.recommendation.sets.length, 0),
      maxSets: Math.max(...launch.plan.exercises.map(exercise => exercise.recommendation.sets.length)),
      budget: launch.plan.setBudget
    };
    workoutDraft = null;
    const expired = { ...launch, createdAt: Date.now() - SMART_WORKOUT_LAUNCH_MAX_AGE_MS - 1 };
    const future = { ...launch, createdAt: Date.now() + SMART_WORKOUT_LAUNCH_FUTURE_SKEW_MS + 1 };
    const expiredOpened = launchPreparedSmartWorkout(expired);
    const futureOpened = launchPreparedSmartWorkout(future);
    const stale = prepareSmartWorkoutLaunch("Standard", "dashboard");
    state.profile = { ...state.profile, goal: "Strength", calories: "Maintenance" };
    const staleOpened = launchPreparedSmartWorkout(stale);
    const tooManySets = JSON.parse(JSON.stringify(launch.plan));
    while (tooManySets.exercises[0].recommendation.sets.length < 5) {
      tooManySets.exercises[0].recommendation.sets.push({ ...tooManySets.exercises[0].recommendation.sets[0] });
    }
    const overBudget = { ...launch.plan, setBudget: 25 };
    return {
      opened, replayOpened, expected, actual, caps, staleOpened, expiredOpened, futureOpened, pushedNavigation,
      tooManySetsAccepted: normalizedSmartWorkoutPlan(tooManySets) !== null,
      overBudgetAccepted: normalizedSmartWorkoutPlan(overBudget) !== null
    };
  })()`, sandbox));

  assert.equal(result.opened, true);
  assert.equal(result.replayOpened, false);
  assert.equal(result.pushedNavigation, 1);
  assert.deepEqual(result.actual, result.expected);
  assert.equal(result.expiredOpened, false);
  assert.equal(result.futureOpened, false);
  assert.ok(result.caps.exercises <= 8);
  assert.ok(result.caps.totalSets <= 24 && result.caps.totalSets <= result.caps.budget);
  assert.ok(result.caps.maxSets <= 4);
  assert.equal(result.staleOpened, false);
  assert.equal(result.tooManySetsAccepted, false);
  assert.equal(result.overBudgetAccepted, false);
});

test("Smart launch registry fails closed at 64 live IDs without making the oldest replayable", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    activeWorkout = null;
    render = () => {};
    pushNavigationHistory = () => {};
    const launches = [];
    for (let index = 0; index < 64; index += 1) {
      const launch = prepareSmartWorkoutLaunch("Standard", "dashboard");
      launches.push(launch);
      if (!launchPreparedSmartWorkout(launch)) throw new Error("launch rejected");
    }
    const overflow = prepareSmartWorkoutLaunch("Standard", "dashboard");
    return {
      size: consumedSmartWorkoutLaunchIds.size,
      overflowOpened: launchPreparedSmartWorkout(overflow),
      oldestReplayOpened: launchPreparedSmartWorkout(launches[0]),
      sizeAfter: consumedSmartWorkoutLaunchIds.size
    };
  })()`, sandbox));

  assert.deepEqual(result, {
    size: 64,
    overflowOpened: false,
    oldestReplayOpened: false,
    sizeAfter: 64
  });
});

test("weekly decision and compact screens preserve action-first ordering", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    activeAccount = { id: "alpha", name: "Alpha" };
    state = defaultAppState();
    state.language = "en";
    state.sessions = [];
    removeTrainingGuidanceStorage();
    activationDraft = null;
    activeWorkout = null;
    const empty = workoutsScreen();
    setActivationDismissed(true);
    const dismissed = workoutsScreen();
    setActivationDismissed(false);
    const now = new Date(2026, 7, 12, 18).getTime();
    const make = (id, day) => ({
      id, startedAt: new Date(2026, 7, day, 12).getTime(), note: "", exerciseNames: ["Leg Press"],
      sets: [{ id: id * 100, exerciseName: "Leg Press", weight: 50, reps: 8, orderIndex: 0 }]
    });
    state.profile.days = 2;
    state.sessions = [make(1, 10), make(2, 11)];
    const rest = smartWeeklyDecision(now);
    saveWorkoutFeedback(2, "hard");
    state.profile.days = 4;
    const recovery = smartWeeklyDecision(now);
    const populated = focusLensCard(state.sessions);
    const populatedScreen = workoutsScreen();
    const session = state.sessions[1];
    const feedback = workoutFeedbackPanel(session);
    smartPlanStale = false;
    smartGeneratedPlan = {
      focus: "Upper", requestedEffort: "Auto", appliedEffort: "Standard",
      adjustment: "This redundant explanation must stay hidden."
    };
    const standardCoach = smartCoachPanel();
    smartGeneratedPlan = { ...smartGeneratedPlan, appliedEffort: "Recovery" };
    const recoveryCoach = smartCoachPanel();
    return { empty, dismissed, rest, recovery, populated, populatedScreen, feedback, standardCoach, recoveryCoach };
  })()`, sandbox));

  const ordered = ["Today", "Goal", "Days / week", "Today’s effort", "Start plan", "Edit plan"];
  let cursor = -1;
  for (const label of ordered) {
    const next = result.empty.indexOf(label);
    assert.ok(next > cursor, label);
    cursor = next;
  }
  assert.doesNotMatch(result.empty, /Solo Progress|heatmap-grid|body-map-svg|Recommendations/);
  assert.match(result.dismissed, /Start plan/);
  assert.match(result.dismissed, /Weekly rhythm/);
  assert.equal(result.rest.kind, "rest");
  assert.equal(result.recovery.kind, "recovery");
  assert.match(result.populated, /Start plan|Train anyway/);
  assert.doesNotMatch(result.populatedScreen, /Tap a workout to open its details/);
  assert.equal((result.feedback.match(/data-action="workout-feedback"/g) || []).length, 3);
  assert.match(result.feedback, /How did it feel\?/);
  assert.match(result.feedback, /Too easy|Just right|Too hard/);
  assert.doesNotMatch(result.feedback, /helpful/i);
  assert.doesNotMatch(result.standardCoach, /smart-rir-guidance|redundant explanation/);
  assert.equal((result.recoveryCoach.match(/smart-rir-guidance/g) || []).length, 1);
});

test("future sessions cannot extend weekly-rhythm achievements", () => {
  const sandbox = context();
  const result = plain(vm.runInContext(`(() => {
    const at = (day, hour = 12) => new Date(2026, 7, day, hour).getTime();
    const now = at(12, 18);
    const sessions = [
      { id: 1, startedAt: at(3) },
      { id: 2, startedAt: at(4) },
      { id: 3, startedAt: at(5) },
      { id: 4, startedAt: at(17) },
      { id: 5, startedAt: at(18) },
      { id: 6, startedAt: at(19) }
    ];
    return {
      bounded: longestProfileWeeklyStreak(sessions, 3, now),
      futureOnly: longestProfileWeeklyStreak(sessions.slice(3), 3, now)
    };
  })()`, sandbox));

  assert.deepEqual(result, { bounded: 1, futureOnly: 0 });
});
