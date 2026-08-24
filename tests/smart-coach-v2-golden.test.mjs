import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");
const stateContractSource = await readFile("pwa/state-contract.js", "utf8");
const progressionRulesSource = await readFile("pwa/progression-rules.js", "utf8");
const fixture = JSON.parse(await readFile("shared/smart-coach-v2-golden.json", "utf8"));

function loadPwaEngine() {
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
    URLSearchParams,
    localStorage,
    navigator: {},
    document: {
      querySelector: () => ({
        innerHTML: "",
        querySelectorAll: () => [],
        querySelector: () => null
      })
    },
    requestAnimationFrame: callback => callback(),
    clearTimeout,
    setTimeout,
    clearInterval,
    setInterval,
    fetch: () => Promise.reject(new Error("network disabled in tests")),
    window: {
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {}
    }
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
  vm.runInContext(appSource, context);
  return context;
}

test("shared golden vectors execute the real PWA Smart Coach v2 policy", () => {
  assert.equal(fixture.contractVersion, 2);
  const context = loadPwaEngine();
  for (const vector of fixture.vectors) {
    const input = JSON.stringify(vector.input);
    const actual = vm.runInContext(`resolveSmartCoachV2(${input})`, context);
    assert.deepEqual(JSON.parse(JSON.stringify(actual)), vector.expected, vector.name);
  }
});

test("PWA Smart Coach v2 rejects unbounded context before plan generation", () => {
  const context = loadPwaEngine();
  assert.equal(vm.runInContext("normalizeSmartCoachContextV2({ availableMinutes: 29 })", context), null);
  assert.equal(vm.runInContext("normalizeSmartCoachContextV2({ availableEquipment: [] })", context), null);
  assert.equal(vm.runInContext("normalizeSmartCoachContextV2({ musclesToAvoid: ['unknown'] })", context), null);
});

test("PWA plan engine wires v2 context, exercise feedback, and core rest", () => {
  const context = loadPwaEngine();
  const exercises = [
    "Bench Press", "Shoulder Press", "Lateral Raise", "Cable Row", "Pull Up",
    "Biceps Curl", "Squat", "Leg Press", "Romanian Deadlift", "Calf Raise",
    "Weighted Crunch", "Hyperextension"
  ].map((name, index) => ({ id: index + 1, name }));
  const payload = JSON.stringify({
    exercises,
    sessions: [],
    profile: { split: "Full Body", days: 2, goal: "Muscle Gain", calories: "Surplus" }
  });
  const plan = vm.runInContext(`
    state = normalizeImportedState(${payload}, defaultAppState());
    normalizedSmartWorkoutPlan(
      buildSmartWorkoutPlan("Auto", { readiness: "low", availableMinutes: 45 })
    );
  `, context);
  const normalizedPlan = JSON.parse(JSON.stringify(plan));
  assert.equal(normalizedPlan.contractVersion, 2);
  assert.equal(normalizedPlan.freshForSeconds, 21_600);
  assert.equal(normalizedPlan.appliedEffort, "Recovery");
  assert.equal(normalizedPlan.setBudget, 15);
  assert.ok(normalizedPlan.exercises.reduce(
    (sum, item) => sum + item.recommendation.sets.length,
    0
  ) <= 15);
  assert.ok(normalizedPlan.adaptationReasons.includes("readinessRecovery"));
  assert.ok(normalizedPlan.adaptationReasons.includes("timeCapped"));
  assert.ok(Number.isInteger(normalizedPlan.estimatedMinutes));

  const baseline = vm.runInContext("smartRecommendation('Bench Press')", context);
  const protectedTarget = vm.runInContext(`smartRecommendation('Bench Press', {
    exerciseFeedback: [{ actualRir: 1, outcome: "tooHard", ageDays: 1 }]
  })`, context);
  assert.deepEqual(
    JSON.parse(JSON.stringify(protectedTarget.sets.map(item => item.reps))),
    JSON.parse(JSON.stringify(baseline.sets.map(item => Math.max(1, item.reps - 1))))
  );
  assert.ok(protectedTarget.adaptationReasonIds.includes("exerciseFeedbackTooHard"));
  assert.deepEqual(JSON.parse(JSON.stringify(protectedTarget.targetRir)), [3, 4]);
  assert.equal(vm.runInContext("smartRecommendation('Weighted Crunch').restSeconds", context), 60);
});
