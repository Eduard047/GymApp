import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const appSource = await readFile("pwa/app.js", "utf8");
const stateContractSource = await readFile("pwa/state-contract.js", "utf8");

function createStorage() {
  const values = new Map();
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
}

function loadPwaContext() {
  const context = {
    console,
    Date,
    Map,
    Set,
    TextEncoder,
    URLSearchParams,
    window: {
      location: {
        search: "?access_token=test",
        hash: "",
        replace() {}
      },
      addEventListener() {}
    },
    document: {
      querySelector() {
        return {
          innerHTML: "",
          querySelectorAll: () => [],
          querySelector: () => null
        };
      }
    },
    navigator: {},
    localStorage: createStorage(),
    requestAnimationFrame: callback => callback(),
    clearTimeout,
    setTimeout,
    clearInterval,
    setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests"))
  };
  context.window.document = context.document;
  context.window.navigator = context.navigator;
  context.window.localStorage = context.localStorage;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(appSource, context);
  return context;
}

function daysAgo(days) {
  const date = new Date();
  date.setHours(9, 0, 0, 0);
  date.setDate(date.getDate() - days);
  return date.getTime();
}

function session(id, days, names) {
  return {
    id,
    startedAt: daysAgo(days),
    note: "",
    exerciseNames: names,
    sets: names.flatMap((exerciseName, exerciseIndex) =>
      Array.from({ length: 3 }, (_, setIndex) => ({
        id: id * 100 + exerciseIndex * 10 + setIndex,
        exerciseName,
        weight: 50,
        reps: 10,
        orderIndex: setIndex
      }))
    )
  };
}

function exerciseSession(id, days, exerciseName, setSpecs) {
  return {
    id,
    startedAt: daysAgo(days),
    note: "",
    exerciseNames: [exerciseName],
    sets: setSpecs.map(([weight, reps], index) => ({
      id: id * 100 + index,
      exerciseName,
      weight,
      reps,
      orderIndex: index
    }))
  };
}

function recommendationFor(context, { profile, sessions, exercise = "Bench Press" }) {
  const exerciseRecord = typeof exercise === "string" ? { id: 1, name: exercise } : { id: 1, ...exercise };
  const payload = JSON.stringify({
    exercises: [exerciseRecord],
    sessions,
    profile
  });
  const requested = JSON.stringify(exercise);
  const result = vm.runInContext(`
    state = normalizeImportedState(${payload}, defaultAppState());
    smartRecommendation(${requested});
  `, context);
  return JSON.parse(JSON.stringify(result));
}

function planNamesFor(context, { profile, sessions }) {
  return planFor(context, { profile, sessions }).exercises.map(item => item.name);
}

function planFor(context, { profile, sessions }) {
  const exercises = [
    "Bench Press",
    "Shoulder Press",
    "Lateral Raise",
    "Cable Row",
    "Pull Up",
    "Biceps Curl",
    "Squat",
    "Leg Press",
    "Leg Extension",
    "Leg Curl",
    "Romanian Deadlift",
    "Calf Raise",
    "Weighted Crunch",
    "Hyperextension",
    "Side Hyperextension",
    "Overhead Dumbbell Extension",
    "Crane Pulldown",
    "Dumbbell Bench Press",
    "Incline Dumbbell Press",
    "Incline Bench Press",
    "Chest Fly Machine",
    "Push Up",
    "Dips",
    "Barbell Row",
    "Seated Cable Row",
    "Lat Pulldown",
    "Face Pull",
    "Hammer Curl",
    "Preacher Curl",
    "Deadlift",
    "Hip Thrust",
    "Bulgarian Split Squat",
    "Lunge",
    "Seated Leg Curl",
    "Hip Adduction",
    "Hip Abduction"
  ].map((name, index) => ({ id: index + 1, name }));
  const payload = JSON.stringify({ exercises, sessions, profile });
  return vm.runInContext(`
    state = normalizeImportedState(${payload}, defaultAppState());
    buildSmartWorkoutPlan();
  `, context);
}

test("PWA smart lower plan matches Android safeguards against upper or unknown filler", () => {
  const context = loadPwaContext();
  const names = planNamesFor(context, {
    profile: { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" },
    sessions: [
      session(1, 2, ["Leg Extension", "Leg Curl", "Weighted Crunch"]),
      session(2, 1, ["Bench Press", "Pull Up", "Cable Row"])
    ]
  });

  assert.ok(names.includes("Squat"));
  assert.ok(names.some(name => ["Romanian Deadlift", "Deadlift", "Hip Thrust"].includes(name)));
  assert.ok(names.every(name =>
    [
      "Squat", "Leg Press", "Leg Extension", "Leg Curl", "Romanian Deadlift", "Calf Raise",
      "Deadlift", "Hip Thrust", "Bulgarian Split Squat", "Lunge", "Seated Leg Curl",
      "Hip Adduction", "Hip Abduction", "Weighted Crunch", "Hyperextension", "Side Hyperextension"
    ].includes(name)
  ));
  assert.ok(!names.includes("Bench Press"));
  assert.ok(!names.includes("Overhead Dumbbell Extension"));
  assert.ok(!names.includes("Crane Pulldown"));
});

test("PWA full-body smart plan keeps push, pull, and legs represented", () => {
  const context = loadPwaContext();
  const names = planNamesFor(context, {
    profile: { split: "Full Body", days: 3, goal: "Balanced", calories: "Maintenance" },
    sessions: []
  });

  assert.ok(names.some(name => ["Bench Press", "Shoulder Press", "Lateral Raise"].includes(name)));
  assert.ok(names.some(name => [
    "Cable Row", "Pull Up", "Biceps Curl", "Crane Pulldown", "Barbell Row",
    "Seated Cable Row", "Lat Pulldown", "Face Pull", "Hammer Curl", "Preacher Curl"
  ].includes(name)));
  assert.ok(names.some(name => ["Squat", "Leg Press", "Romanian Deadlift", "Calf Raise"].includes(name)));
  assert.ok(names.some(name => ["Weighted Crunch", "Hyperextension", "Side Hyperextension"].includes(name)));
});

test("PWA push-pull-legs split rotates from the latest dominant session", () => {
  const context = loadPwaContext();
  const profile = { split: "Push Pull Legs", days: 5, goal: "Balanced", calories: "Maintenance" };

  assert.equal(planFor(context, { profile, sessions: [session(1, 1, ["Bench Press"])] }).focus, "Pull");
  assert.equal(planFor(context, { profile, sessions: [session(1, 1, ["Cable Row"])] }).focus, "Legs");
  assert.equal(planFor(context, { profile, sessions: [session(1, 1, ["Leg Press"])] }).focus, "Push");
});

test("PWA upper day keeps both a press and a pull without banning familiar primary lifts", () => {
  const context = loadPwaContext();
  const names = planNamesFor(context, {
    profile: { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" },
    sessions: [
      session(1, 1, ["Leg Press"]),
      session(2, 3, ["Bench Press"])
    ]
  });

  assert.equal(names.length, 8);
  assert.ok(names.some(name => ["Bench Press", "Shoulder Press"].includes(name)));
  assert.ok(names.some(name => ["Cable Row", "Pull Up"].includes(name)));
});

test("PWA Strength 5-rep work builds to six without a false deload and preserves per-set loads", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Strength", calories: "Maintenance" },
    sessions: [exerciseSession(1, 1, "Bench Press", [[80, 5], [82.5, 5], [85, 5]])]
  });

  assert.equal(recommendation.kindId, "HoldAndBuild");
  assert.deepEqual(recommendation.sets, [
    { weight: 80, reps: 6 },
    { weight: 82.5, reps: 6 },
    { weight: 85, reps: 6 },
    { weight: 85, reps: 6 }
  ]);
});

test("PWA double progression adds load after every Strength set reaches the top range twice", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Strength", calories: "Maintenance" },
    sessions: [
      exerciseSession(1, 3, "Bench Press", [[80, 6], [82.5, 6], [85, 6], [85, 6]]),
      exerciseSession(2, 1, "Bench Press", [[80, 6], [82.5, 6], [85, 6], [85, 6]])
    ]
  });

  assert.equal(recommendation.kindId, "ProgressiveOverload");
  assert.deepEqual(recommendation.sets, [
    { weight: 82.5, reps: 3 },
    { weight: 85, reps: 3 },
    { weight: 87.5, reps: 3 },
    { weight: 87.5, reps: 3 }
  ]);
});

test("PWA Muscle Gain uses its rep range and surplus/frequency-aware set budgets", () => {
  const context = loadPwaContext();
  const maintenance = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Muscle Gain", calories: "Maintenance" },
    sessions: [exerciseSession(1, 1, "Bench Press", [[40, 8], [42.5, 8], [45, 8]])]
  });
  const surplusTwoDays = recommendationFor(context, {
    profile: { split: "Full Body", days: 2, goal: "Muscle Gain", calories: "Surplus" },
    sessions: [exerciseSession(1, 1, "Bench Press", [[40, 8], [42.5, 8], [45, 8]])]
  });
  const surplusSixDays = recommendationFor(context, {
    profile: { split: "Full Body", days: 6, goal: "Muscle Gain", calories: "Surplus" },
    sessions: [exerciseSession(1, 1, "Bench Press", [[40, 8], [42.5, 8], [45, 8]])]
  });

  assert.equal(maintenance.kindId, "HoldAndBuild");
  assert.deepEqual(maintenance.sets.map(set => set.reps), [9, 9, 9, 9]);
  assert.deepEqual(maintenance.sets.map(set => set.weight), [40, 42.5, 45, 45]);
  assert.equal(surplusTwoDays.sets.length, 4);
  assert.equal(surplusSixDays.sets.length, 3);
});

test("PWA Cut plus Deficit keeps three quality sets and permits earned progression", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Upper / Lower", days: 4, goal: "Aesthetic Cut", calories: "Deficit" },
    sessions: [
      exerciseSession(1, 3, "Bench Press", [[50, 10], [55, 10], [60, 10]]),
      exerciseSession(2, 1, "Bench Press", [[50, 10], [55, 10], [60, 10]])
    ]
  });

  assert.equal(recommendation.kindId, "ProgressiveOverload");
  assert.equal(recommendation.sets.length, 3);
  assert.deepEqual(recommendation.sets.map(set => set.reps), [6, 6, 6]);
  assert.deepEqual(recommendation.sets.map(set => set.weight), [52.5, 57.5, 62.5]);
});

test("PWA double progression rejects incomplete sessions and a drop from ten to eight reps", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 4, goal: "Balanced", calories: "Maintenance" };
  const incomplete = recommendationFor(context, {
    profile,
    sessions: [
      exerciseSession(1, 3, "Bench Press", [[100, 8]]),
      exerciseSession(2, 1, "Bench Press", [[100, 8]])
    ]
  });
  const declined = recommendationFor(context, {
    profile,
    sessions: [
      exerciseSession(3, 3, "Bench Press", [[100, 10], [100, 10], [100, 10], [100, 10]]),
      exerciseSession(4, 1, "Bench Press", [[100, 8], [100, 8], [100, 8], [100, 8]])
    ]
  });

  assert.notEqual(incomplete.kindId, "ProgressiveOverload");
  assert.notEqual(declined.kindId, "ProgressiveOverload");
  assert.ok(declined.sets.every(set => set.weight === 100));
});

test("PWA assistance progression makes the gravitron harder and return makes it easier", () => {
  const context = loadPwaContext();
  const profile = { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" };
  const progression = recommendationFor(context, {
    profile,
    exercise: "Assisted Pull Up",
    sessions: [
      exerciseSession(1, 3, "Assisted Pull Up", [[50, 8], [50, 8], [50, 8]]),
      exerciseSession(2, 1, "Assisted Pull Up", [[50, 8], [50, 8], [50, 8]])
    ]
  });
  const comeback = recommendationFor(context, {
    profile,
    exercise: "Assisted Pull Up",
    sessions: [exerciseSession(3, 12, "Assisted Pull Up", [[50, 7], [50, 7], [50, 7]])]
  });

  assert.equal(progression.kindId, "ProgressiveOverload");
  assert.deepEqual(progression.sets.map(set => set.weight), [47.5, 47.5, 47.5]);
  assert.equal(comeback.kindId, "Comeback");
  assert.deepEqual(comeback.sets.map(set => set.weight), [52.5, 52.5, 52.5]);
});

test("PWA machine profiles snap to real stack values and respect assistance direction", () => {
  const context = loadPwaContext();
  const profile = { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" };
  const latPulldown = recommendationFor(context, {
    profile,
    exercise: {
      name: "Lat Pulldown",
      loadProfile: { direction: "higherIsHarder", allowedWeightsKg: [45, 50, 55, 59, 64, 69, 73] }
    },
    sessions: [
      exerciseSession(1, 3, "Lat Pulldown", [[69, 8], [69, 8], [69, 8]]),
      exerciseSession(2, 1, "Lat Pulldown", [[69, 8], [69, 8], [69, 8]])
    ]
  });
  const assistedDip = recommendationFor(context, {
    profile,
    exercise: {
      name: "Assisted Dip",
      loadProfile: { direction: "lowerIsHarder", allowedWeightsKg: [35, 40, 45, 50, 55] }
    },
    sessions: [
      exerciseSession(3, 3, "Assisted Dip", [[50, 8], [50, 8], [50, 8]]),
      exerciseSession(4, 1, "Assisted Dip", [[50, 8], [50, 8], [50, 8]])
    ]
  });

  assert.equal(latPulldown.kindId, "ProgressiveOverload");
  assert.deepEqual(latPulldown.sets.map(set => set.weight), [73, 73, 73]);
  assert.equal(assistedDip.kindId, "ProgressiveOverload");
  assert.deepEqual(assistedDip.sets.map(set => set.weight), [45, 45, 45]);
  assert.equal(assistedDip.estimatedVolume, 0);
});

test("PWA machine-weight input treats compact commas as separators", () => {
  const context = loadPwaContext();
  const parsed = vm.runInContext('parsedLoadProfileWeights("45,50,55,59,64,69,73")', context);

  assert.deepEqual(JSON.parse(JSON.stringify(parsed)), [45, 50, 55, 59, 64, 69, 73]);
  assert.equal(vm.runInContext('parsedLoadProfileWeights("45,5,50")', context).length, 3);
  assert.equal(vm.runInContext('parsedLoadProfileWeights("45.5; 50")', context)[0], 45.5);
});

test("PWA no-profile fallback snaps off-grid history to 2.5 kg values", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Balanced", calories: "Deficit" },
    sessions: [
      exerciseSession(1, 3, "Bench Press", [[48.5, 8], [48.5, 8], [48.5, 8]]),
      exerciseSession(2, 1, "Bench Press", [[48.5, 8], [48.5, 8], [48.5, 8]])
    ]
  });

  assert.ok(recommendation.sets.every(set => set.weight % 2.5 === 0));
  assert.ok(recommendation.sets.every(set => set.weight !== 51));
  assert.deepEqual(recommendation.sets.map(set => set.weight), [50, 50, 50]);
  assert.equal(vm.runInContext('smartAdjustedWeight(48.5, "harder", { loadMode: "Standard" }, null)', context), 50);
  assert.equal(vm.runInContext('smartAdjustedWeight(50, "harder", { loadMode: "Standard" }, null)', context), 52.5);
  assert.equal(vm.runInContext('smartAdjustedWeight(51, "harder", { loadMode: "Standard" }, null)', context), 52.5);
  assert.equal(vm.runInContext('smartAdjustedWeight(51, "hold", { loadMode: "Standard" }, null)', context), 50);
  assert.equal(vm.runInContext('smartAdjustedWeight(50, "harder", { loadMode: "Assistance" }, null)', context), 47.5);
});

test("PWA assistance treats 50 to 45 as improvement and repeated increases as decline", () => {
  const context = loadPwaContext();
  const profile = { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" };
  const exercise = {
    name: "Assisted Dip",
    loadProfile: { direction: "lowerIsHarder", allowedWeightsKg: [35, 40, 45, 50, 55] }
  };
  const improved = recommendationFor(context, {
    profile,
    exercise,
    sessions: [
      exerciseSession(1, 3, "Assisted Dip", [[50, 8], [50, 8], [50, 8]]),
      exerciseSession(2, 1, "Assisted Dip", [[45, 8], [45, 8], [45, 8]])
    ]
  });
  const declined = recommendationFor(context, {
    profile,
    exercise,
    sessions: [
      exerciseSession(3, 5, "Assisted Dip", [[40, 7], [40, 7], [40, 7]]),
      exerciseSession(4, 3, "Assisted Dip", [[45, 7], [45, 7], [45, 7]]),
      exerciseSession(5, 1, "Assisted Dip", [[50, 7], [50, 7], [50, 7]])
    ]
  });

  assert.equal(improved.kindId, "ProgressiveOverload");
  assert.deepEqual(improved.sets.map(set => set.weight), [40, 40, 40]);
  assert.equal(declined.kindId, "Deload");
  assert.deepEqual(declined.sets.map(set => set.weight), [55, 55, 55]);
});

test("PWA assistance does not treat less counterweight as a softer session", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" },
    exercise: {
      name: "Assisted Dip",
      loadProfile: { direction: "lowerIsHarder", allowedWeightsKg: [35, 40, 45, 50, 55] }
    },
    sessions: [
      exerciseSession(1, 3, "Assisted Dip", [[50, 7], [50, 7], [50, 7]]),
      exerciseSession(2, 1, "Assisted Dip", [[40, 7], [40, 7], [40, 7]])
    ]
  });

  assert.ok(!recommendation.reasons.some(reason => reason.includes("softer session") || reason.includes("слабше тренування")));
});

test("PWA configured stack holds at its hardest boundary", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" },
    exercise: {
      name: "Assisted Dip",
      loadProfile: { direction: "lowerIsHarder", allowedWeightsKg: [40, 45, 50] }
    },
    sessions: [
      exerciseSession(1, 3, "Assisted Dip", [[40, 8], [40, 8], [40, 8]]),
      exerciseSession(2, 1, "Assisted Dip", [[40, 8], [40, 8], [40, 8]])
    ]
  });

  assert.equal(recommendation.kindId, "HoldAndBuild");
  assert.deepEqual(recommendation.sets.map(set => set.weight), [40, 40, 40]);
});

test("PWA bodyweight work never claims a zero-load progression beyond ten reps", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Muscle Gain", calories: "Maintenance" },
    exercise: "Pull Up",
    sessions: [
      exerciseSession(1, 3, "Pull Up", [[0, 10], [0, 10], [0, 10]]),
      exerciseSession(2, 1, "Pull Up", [[0, 10], [0, 10], [0, 10]])
    ]
  });

  assert.equal(recommendation.kindId, "HoldAndBuild");
  assert.ok(recommendation.sets.every(set => set.weight === 0 && set.reps === 10));
  assert.ok(recommendation.reasons.some(reason => reason.includes("harder variation") || reason.includes("складніший варіант")));
});

test("PWA built-in programming metadata keeps isolation exercises out of compound slots", () => {
  const context = loadPwaContext();
  const profile = { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" };
  for (const exercise of [
    "Lateral Raise",
    "Machine Lateral Raise",
    "Rear Delt Fly",
    "Face Pull",
    "Overhead Dumbbell Triceps Extension",
    "French Press",
    "Hyperextension"
  ]) {
    const recommendation = recommendationFor(context, { profile, sessions: [], exercise });
    assert.equal(recommendation.sets.length, 3, exercise);
    assert.ok(recommendation.sets.every(set => set.reps === 10), exercise);
  }
  const pushUp = recommendationFor(context, { profile, sessions: [], exercise: "Push Up" });
  assert.equal(pushUp.sets.length, 3);
  assert.ok(pushUp.sets.every(set => set.reps === 8));
});

test("PWA programming metadata covers every built-in identity exactly once", () => {
  const context = loadPwaContext();
  const coverage = JSON.parse(JSON.stringify(vm.runInContext(`({
    catalog: builtInExerciseCatalog.map(item => item.key).sort(),
    programming: [...smartBuiltInProgramming.keys()].sort()
  })`, context)));

  assert.deepEqual(coverage.programming, coverage.catalog);
});

test("PWA two-day PPL safely becomes full body and high-frequency plans stay short", () => {
  const context = loadPwaContext();
  const twoDay = JSON.parse(JSON.stringify(planFor(context, {
    profile: { split: "Push Pull Legs", days: 2, goal: "Muscle Gain", calories: "Surplus" },
    sessions: []
  })));
  const sixDay = JSON.parse(JSON.stringify(planFor(context, {
    profile: { split: "Full Body", days: 6, goal: "Muscle Gain", calories: "Surplus" },
    sessions: []
  })));

  assert.equal(twoDay.focus, "FullBody");
  assert.equal(twoDay.exercises.length, 10);
  assert.equal(sixDay.exercises.length, 6);
  assert.equal(sixDay.exercises.reduce((sum, item) => sum + item.recommendation.sets.length, 0), 18);
});

test("PWA target exercise counts do not collapse for goal or calorie mode", () => {
  const context = loadPwaContext();
  for (const [days, split, expected] of [
    [2, "Full Body", 10],
    [3, "Full Body", 9],
    [4, "Full Body", 8],
    [5, "Push Pull Legs", 7],
    [6, "Push Pull Legs", 6],
    [6, "Full Body", 6]
  ]) {
    for (const [goal, calories] of [["Strength", "Deficit"], ["Muscle Gain", "Surplus"]]) {
      const plan = planFor(context, { profile: { split, days, goal, calories }, sessions: [] });
      assert.equal(plan.exercises.length, expected, `${days}d ${split} ${goal} ${calories}`);
    }
  }
});

test("PWA weekly muscle targets follow goal and calorie mode within safe bounds", () => {
  const context = loadPwaContext();
  const targets = JSON.parse(JSON.stringify(vm.runInContext(`(() => {
    const goals = ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"];
    const calories = ["Deficit", "Maintenance", "Surplus"];
    return Object.fromEntries(goals.flatMap(goal => calories.map(mode => [
      goal + ":" + mode,
      smartWeeklyMuscleTarget({ goal, calories: mode })
    ])));
  })()`, context)));

  assert.deepEqual(targets, {
    "Aesthetic Cut:Deficit": 6,
    "Aesthetic Cut:Maintenance": 8,
    "Aesthetic Cut:Surplus": 9,
    "Muscle Gain:Deficit": 8,
    "Muscle Gain:Maintenance": 10,
    "Muscle Gain:Surplus": 11,
    "Strength:Deficit": 6,
    "Strength:Maintenance": 8,
    "Strength:Surplus": 9,
    "Balanced:Deficit": 6,
    "Balanced:Maintenance": 8,
    "Balanced:Surplus": 9
  });
});

test("PWA weekly effective sets use an exact rolling window and fractional muscle credit", () => {
  const context = loadPwaContext();
  const result = JSON.parse(JSON.stringify(vm.runInContext(`(() => {
    state = defaultAppState();
    const now = 1800000000000;
    const week = 7 * 24 * 60 * 60 * 1000;
    const row = (id, startedAt, reps = 8) => ({
      id,
      exerciseName: "Жим штанги лежачи",
      weight: 50,
      reps,
      orderIndex: 0,
      session: { id, startedAt }
    });
    const effective = smartWeeklyEffectiveSets([
      row(1, now - week),
      row(2, now),
      row(3, now - week - 1),
      row(4, now + 1),
      row(5, now - 1, 0),
      { ...row(6, now - 1), session: { id: 6, startedAt: "bad" } }
    ], now);
    return Object.fromEntries(effective);
  })()`, context)));

  assert.equal(result.chest, 2);
  assert.equal(result.triceps, 1.2);
  assert.equal(result.shoulders, 1);
  assert.equal(result.quads, 0);
});

test("PWA weekly coverage favors neglected muscles and accounts for projected smart sets", () => {
  const context = loadPwaContext();
  const scores = JSON.parse(JSON.stringify(vm.runInContext(`(() => {
    state = defaultAppState();
    state.profile = { split: "Full Body", days: 3, goal: "Balanced", calories: "Maintenance" };
    const benchExercise = state.exercises.find(item => item.catalogKey === "bench_press");
    const curlExercise = state.exercises.find(item => item.catalogKey === "biceps_curl");
    const candidate = exercise => ({ exercise, analysis: analyzeSmartExercise(exercise), score: 0 });
    const bench = candidate(benchExercise);
    const curl = candidate(curlExercise);
    const completed = new Map(muscles.map(([id]) => [id, 8]));
    completed.set("chest", 0);
    completed.set("shoulders", 0);
    completed.set("triceps", 0);
    const empty = new Map(muscles.map(([id]) => [id, 0]));
    return {
      neglectedBench: smartWeeklyCoverageScore(bench, [], completed, 8),
      saturatedCurl: smartWeeklyCoverageScore(curl, [], completed, 8),
      firstBench: smartWeeklyCoverageScore(bench, [], empty, 6),
      thirdBench: smartWeeklyCoverageScore(bench, [bench, bench], empty, 6)
    };
  })()`, context)));

  assert.ok(scores.neglectedBench > scores.saturatedCurl);
  assert.ok(scores.firstBench > 0);
  assert.ok(scores.thirdBench < 0);
});

test("PWA rotates exactly one mandatory trunk slot in every workout", () => {
  const context = loadPwaContext();
  const profile = { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" };
  const afterCore = planNamesFor(context, {
    profile,
    sessions: [
      session(1, 2, ["Leg Press", "Weighted Crunch"]),
      session(2, 1, ["Bench Press"])
    ]
  });
  const afterHyper = planNamesFor(context, {
    profile,
    sessions: [
      session(3, 2, ["Leg Press", "Hyperextension"]),
      session(4, 1, ["Bench Press"])
    ]
  });
  const upperAfterRecentTrunk = planNamesFor(context, {
    profile,
    sessions: [session(5, 1, ["Leg Press", "Weighted Crunch"])]
  });
  const coreNames = new Set([
    "Plank", "Weighted Crunch", "Hanging Leg Raise", "Plate Twist", "Weighted Side Bend"
  ]);
  const hyperNames = new Set(["Hyperextension", "Side Hyperextension"]);
  const trunkNames = new Set([...coreNames, ...hyperNames]);

  assert.equal(afterCore.filter(name => trunkNames.has(name)).length, 1);
  assert.ok(afterCore.some(name => hyperNames.has(name)));
  assert.equal(afterHyper.filter(name => trunkNames.has(name)).length, 1);
  assert.ok(afterHyper.some(name => coreNames.has(name)));
  assert.equal(upperAfterRecentTrunk.filter(name => trunkNames.has(name)).length, 1);
  assert.ok(upperAfterRecentTrunk.some(name => hyperNames.has(name)));
});

test("PWA plan deduplicates localized aliases by stable catalog identity", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 3, goal: "Balanced", calories: "Maintenance" };
  const payload = JSON.stringify({
    exercises: [
      { id: 1, name: "Bench Press" },
      { id: 2, name: "Жим штанги лежачи" },
      { id: 3, name: "Shoulder Press" },
      { id: 4, name: "Pull Up" },
      { id: 5, name: "Barbell Row" },
      { id: 6, name: "Squat" },
      { id: 7, name: "Romanian Deadlift" },
      { id: 8, name: "Weighted Crunch" }
    ],
    sessions: [],
    profile
  });
  const plan = JSON.parse(JSON.stringify(vm.runInContext(`
    state = normalizeImportedState(${payload}, defaultAppState());
    buildSmartWorkoutPlan();
  `, context)));

  const benchAliases = plan.exercises.filter(item => ["Bench Press", "Жим штанги лежачи"].includes(item.name));
  assert.equal(benchAliases.length, 1);
});

test("PWA deload requires two consecutive comparable regressions", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 4, goal: "Balanced", calories: "Maintenance" };
  const repeated = recommendationFor(context, {
    profile,
    sessions: [
      exerciseSession(1, 5, "Bench Press", [[100, 10], [100, 10], [100, 10]]),
      exerciseSession(2, 3, "Bench Press", [[90, 8], [90, 8], [90, 8]]),
      exerciseSession(3, 1, "Bench Press", [[80, 6], [80, 6], [80, 6]])
    ]
  });
  const single = recommendationFor(context, {
    profile,
    sessions: [
      exerciseSession(1, 5, "Bench Press", [[90, 8], [90, 8], [90, 8]]),
      exerciseSession(2, 3, "Bench Press", [[90, 8], [90, 8], [90, 8]]),
      exerciseSession(3, 1, "Bench Press", [[80, 6], [80, 6], [80, 6]])
    ]
  });

  assert.equal(repeated.kindId, "Deload");
  assert.deepEqual(repeated.sets.map(set => set.weight), [72.5, 72.5, 72.5, 72.5]);
  assert.notEqual(single.kindId, "Deload");
});

test("PWA standard deload and comeback snap percentage targets downward", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 4, goal: "Balanced", calories: "Maintenance" };
  const comeback = recommendationFor(context, {
    profile,
    sessions: [exerciseSession(20, 12, "Bench Press", [[50, 7], [50, 7], [50, 7], [50, 7]])]
  });

  assert.equal(comeback.kindId, "Comeback");
  assert.deepEqual(comeback.sets.map(set => set.weight), [45, 45, 45, 45]);
  assert.equal(
    vm.runInContext('smartAdjustedWeight(80, "easier", { loadMode: "Standard" }, null, 73.6)', context),
    72.5
  );
});

test("PWA plateau detection ignores rising reps and reacts to a truly flat four-session trend", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 4, goal: "Balanced", calories: "Maintenance" };
  const rising = recommendationFor(context, {
    profile,
    sessions: [
      exerciseSession(1, 7, "Bench Press", [[50, 5], [50, 5], [50, 5]]),
      exerciseSession(2, 5, "Bench Press", [[50, 6], [50, 6], [50, 6]]),
      exerciseSession(3, 3, "Bench Press", [[50, 7], [50, 7], [50, 7]]),
      exerciseSession(4, 1, "Bench Press", [[50, 8], [50, 8], [50, 8]])
    ]
  });
  const flat = recommendationFor(context, {
    profile,
    sessions: [1, 2, 3, 4].map((id, index) =>
      exerciseSession(id, 7 - index * 2, "Bench Press", [[50, 7], [50, 7], [50, 7]])
    )
  });

  assert.notEqual(rising.kindId, "PlateauBreak");
  assert.equal(flat.kindId, "PlateauBreak");
});

test("PWA full-body history rotates deterministic A/B/C plans", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 3, goal: "Balanced", calories: "Maintenance" };
  const completed = [
    session(1, 5, ["Bench Press", "Cable Row", "Squat"]),
    session(2, 3, ["Shoulder Press", "Pull Up", "Romanian Deadlift"])
  ];
  const planA = JSON.parse(JSON.stringify(planFor(context, { profile, sessions: [] })));
  const planB = JSON.parse(JSON.stringify(planFor(context, { profile, sessions: completed.slice(0, 1) })));
  const planC = JSON.parse(JSON.stringify(planFor(context, { profile, sessions: completed })));
  const repeatedPlanC = JSON.parse(JSON.stringify(planFor(context, { profile, sessions: completed })));

  assert.equal(planA.variant, "A");
  assert.equal(planB.variant, "B");
  assert.equal(planC.variant, "C");
  assert.deepEqual(planC, repeatedPlanC);
  assert.notDeepEqual(planA.exercises.map(item => item.name), planB.exercises.map(item => item.name));
  assert.notDeepEqual(planB.exercises.map(item => item.name), planC.exercises.map(item => item.name));
});

test("PWA smart history matches built-in aliases through stable catalog identity", () => {
  const context = loadPwaContext();
  const recommendation = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Balanced", calories: "Maintenance" },
    sessions: [exerciseSession(1, 1, "Bench Press", [[60, 8], [62.5, 8], [65, 8]])],
    exercise: "Жим штанги лежачи"
  });

  assert.notEqual(recommendation.kindId, "NewExercise");
  assert.deepEqual(recommendation.sets.map(set => set.weight), [60, 62.5, 65, 65]);
});

test("PWA smart outputs remain finite and clamped at the state-contract load bound", () => {
  const context = loadPwaContext();
  const maximum = 1_000_000;
  const recommendation = recommendationFor(context, {
    profile: { split: "Full Body", days: 4, goal: "Balanced", calories: "Maintenance" },
    sessions: [
      exerciseSession(1, 3, "Bench Press", [[maximum, 8], [maximum, 8], [maximum, 8], [maximum, 8]]),
      exerciseSession(2, 1, "Bench Press", [[maximum, 8], [maximum, 8], [maximum, 8], [maximum, 8]])
    ]
  });

  assert.equal(recommendation.kindId, "HoldAndBuild");
  assert.ok(recommendation.sets.every(set => Number.isFinite(set.weight) && set.weight === maximum));
  assert.ok(recommendation.sets.every(set => Number.isInteger(set.reps) && set.reps >= 1 && set.reps <= 10));
  assert.ok(Number.isFinite(recommendation.estimatedVolume));
});

test("PWA smart coach ignores history beyond the allowed future clock skew", () => {
  const context = loadPwaContext();
  const profile = { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" };
  const recommendation = recommendationFor(context, {
    profile,
    sessions: [
      exerciseSession(1, 1, "Bench Press", [[50, 8], [50, 8], [50, 8]]),
      exerciseSession(2, -30, "Bench Press", [[100, 12], [100, 12], [100, 12]])
    ]
  });
  const plan = planFor(context, {
    profile,
    sessions: [
      session(3, 1, ["Leg Press"]),
      session(4, -30, ["Bench Press"])
    ]
  });

  assert.equal(recommendation.kindId, "HoldAndBuild");
  assert.deepEqual(recommendation.sets.map(set => set.weight), [50, 50, 50, 50]);
  assert.equal(plan.focus, "Upper");
});

test("PWA smart prescriptions stay within three to four sets and ten reps for every profile", () => {
  const context = loadPwaContext();
  const goals = ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"];
  const calories = ["Deficit", "Maintenance", "Surplus"];
  const days = [2, 3, 4, 5, 6];

  for (const goal of goals) {
    for (const calorieMode of calories) {
      for (const workoutsPerWeek of days) {
        const profile = {
          split: workoutsPerWeek <= 3 ? "Full Body" : workoutsPerWeek === 4 ? "Upper / Lower" : "Push Pull Legs",
          days: workoutsPerWeek,
          goal,
          calories: calorieMode
        };
        for (const exercise of ["Bench Press", "Biceps Curl"]) {
          const recommendation = recommendationFor(context, { profile, sessions: [], exercise });
          assert.ok(recommendation.sets.length >= 3 && recommendation.sets.length <= 4);
          assert.ok(recommendation.sets.every(set => set.reps >= 3 && set.reps <= 10));
        }
      }
    }
  }
});

test("PWA 1200-scenario plan matrix stays deterministic, balanced, and volume-bounded", () => {
  const context = loadPwaContext();
  const goals = ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"];
  const calories = ["Deficit", "Maintenance", "Surplus"];
  const splits = ["Full Body", "Upper / Lower", "Push Pull Legs", "Custom"];
  const histories = [
    [],
    [session(101, 1, ["Bench Press", "Shoulder Press"])],
    [session(102, 1, ["Cable Row", "Pull Up"])],
    [session(103, 1, ["Squat", "Romanian Deadlift"])],
    [session(104, 1, ["Bench Press", "Cable Row", "Squat"])]
  ];
  const trunkKeys = new Set([
    "hyperextension", "side_hyperextension", "plank", "weighted_crunch",
    "hanging_leg_raise", "plate_twist", "weighted_side_bend"
  ]);

  let scenarioCount = 0;
  for (const goal of goals) {
    for (const calorieMode of calories) {
      for (let days = 2; days <= 6; days += 1) {
        for (const split of splits) {
          for (const sessions of histories) {
            const profile = { split, days, goal, calories: calorieMode };
            const plan = JSON.parse(JSON.stringify(planFor(context, { profile, sessions })));
            const repeated = JSON.parse(JSON.stringify(planFor(context, { profile, sessions })));
            const totalSets = plan.exercises.reduce((sum, item) => sum + item.recommendation.sets.length, 0);
            const names = plan.exercises.map(item => item.name);
            const trunkCount = plan.exercises.filter(item => trunkKeys.has(item.catalogKey)).length;
            const expectedExerciseCount = 12 - days;

            scenarioCount += 1;
            assert.deepEqual(repeated, plan);
            assert.equal(new Set(names).size, names.length);
            assert.equal(
              plan.exercises.length,
              expectedExerciseCount,
              `${days}d ${split} ${goal} ${calorieMode} ${plan.focus}`
            );
            assert.equal(trunkCount, 1, `${days}d ${split} ${goal} ${calorieMode} ${plan.focus}`);
            assert.ok(totalSets <= expectedExerciseCount * 4);
            assert.ok(plan.exercises.every(item => item.recommendation.sets.length >= 3 && item.recommendation.sets.length <= 4));
            assert.ok(plan.exercises.every(item => item.recommendation.sets.every(set => Number.isInteger(set.reps) && set.reps <= 10)));
            if (days <= 2) assert.equal(plan.focus, "FullBody");
            if (days >= 5) assert.ok(totalSets <= 21);
          }
        }
      }
    }
  }

  assert.equal(scenarioCount, 1200);
});

test("PWA smart plan never treats warm-up as a working exercise", () => {
  const context = loadPwaContext();
  const profile = { split: "Full Body", days: 3, goal: "Balanced", calories: "Maintenance" };
  const payload = JSON.stringify({
    exercises: [
      { id: 1, name: "Warm Up", catalogKey: "warm_up" },
      { id: 2, name: "Bench Press" },
      { id: 3, name: "Cable Row" },
      { id: 4, name: "Squat" },
      { id: 5, name: "Shoulder Press" },
      { id: 6, name: "Pull Up" },
      { id: 7, name: "Romanian Deadlift" }
    ],
    sessions: [],
    profile
  });
  const plan = vm.runInContext(`
    state = normalizeImportedState(${payload}, defaultAppState());
    buildSmartWorkoutPlan();
  `, context);

  assert.equal(JSON.parse(JSON.stringify(plan)).exercises.some(item => item.catalogKey === "warm_up"), false);
});

test("PWA achievement gallery exposes the canonical twelve stable milestones", () => {
  const context = loadPwaContext();
  const definitions = JSON.parse(JSON.stringify(vm.runInContext(`
    state = defaultAppState();
    achievementDefinitions().map(item => ({ id: item.id, target: item.target }));
  `, context)));

  assert.deepEqual(definitions, [
    { id: "first_workout", target: 1 },
    { id: "workout_5", target: 5 },
    { id: "workout_10", target: 10 },
    { id: "workout_25", target: 25 },
    { id: "workout_50", target: 50 },
    { id: "workout_100", target: 100 },
    { id: "streak_7", target: 7 },
    { id: "streak_14", target: 14 },
    { id: "streak_30", target: 30 },
    { id: "volume_10k", target: 10_000 },
    { id: "volume_50k", target: 50_000 },
    { id: "comeback", target: 7 }
  ]);
});
