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
    "Overhead Dumbbell Extension",
    "Crane Pulldown"
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
  assert.ok(names.includes("Romanian Deadlift"));
  assert.ok(names.every(name =>
    ["Squat", "Leg Press", "Leg Extension", "Leg Curl", "Romanian Deadlift", "Calf Raise", "Weighted Crunch"].includes(name)
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
  assert.ok(names.some(name => ["Cable Row", "Pull Up", "Biceps Curl", "Crane Pulldown"].includes(name)));
  assert.ok(names.some(name => ["Squat", "Leg Press", "Romanian Deadlift", "Calf Raise"].includes(name)));
});

test("PWA push-pull-legs split rotates from the latest dominant session", () => {
  const context = loadPwaContext();
  const profile = { split: "Push Pull Legs", days: 5, goal: "Balanced", calories: "Maintenance" };

  assert.equal(planFor(context, { profile, sessions: [session(1, 1, ["Bench Press"])] }).focus, "Pull");
  assert.equal(planFor(context, { profile, sessions: [session(1, 1, ["Cable Row"])] }).focus, "Legs");
  assert.equal(planFor(context, { profile, sessions: [session(1, 1, ["Leg Press"])] }).focus, "Push");
});

test("PWA second upper day rotates away from recent bench toward uncovered muscles", () => {
  const context = loadPwaContext();
  const names = planNamesFor(context, {
    profile: { split: "Upper / Lower", days: 4, goal: "Balanced", calories: "Maintenance" },
    sessions: [
      session(1, 1, ["Leg Press"]),
      session(2, 3, ["Bench Press"])
    ]
  });

  assert.ok(!names.includes("Bench Press"));
  assert.ok(names.some(name => ["Lateral Raise", "Shoulder Press"].includes(name)));
  assert.ok(names.some(name => ["Cable Row", "Pull Up"].includes(name)));
});
