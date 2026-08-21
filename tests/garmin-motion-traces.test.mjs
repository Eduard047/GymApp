import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const detector = ({ threshold = 130, minimum = 5, quiet = 4 } = {}) => ({
  threshold,
  minimum,
  quiet,
  burst: 0,
  rhythmic: 0,
  reversals: 0,
  startedAt: null,
  lastMotionAt: null,
  prompt: false
});

const applyWindow = (state, { second, score, reversals }) => {
  const strong = score >= state.threshold;
  const rhythmic = reversals >= 1 && reversals <= 8;
  if (!strong) {
    state.burst = 0;
    state.rhythmic = 0;
    state.reversals = 0;
    if (state.startedAt !== null && second - state.lastMotionAt >= state.quiet &&
        state.lastMotionAt - state.startedAt >= state.minimum) {
      state.prompt = true;
    }
    return state;
  }
  state.burst += 1;
  if (rhythmic) {
    state.rhythmic += 1;
    state.reversals = Math.min(8, state.reversals + reversals);
  }
  if (state.startedAt === null && state.burst >= 3 && state.rhythmic >= 2 &&
      state.reversals >= 4) {
    state.startedAt = second - 2;
  }
  if (state.startedAt !== null && rhythmic) state.lastMotionAt = second;
  return state;
};

test("labeled idle, handling, walking, and short-gesture traces do not start a set", () => {
  const traces = {
    idle: Array.from({ length: 12 }, (_, second) => ({ second, score: 8, reversals: 0 })),
    walking: Array.from({ length: 12 }, (_, second) => ({ second, score: 70, reversals: 4 })),
    plateLoading: [
      { second: 0, score: 210, reversals: 0 },
      { second: 1, score: 180, reversals: 0 },
      { second: 2, score: 30, reversals: 0 }
    ],
    shortGesture: [
      { second: 0, score: 240, reversals: 2 },
      { second: 1, score: 20, reversals: 0 },
      { second: 2, score: 15, reversals: 0 }
    ]
  };
  for (const [label, windows] of Object.entries(traces)) {
    const state = windows.reduce(applyWindow, detector());
    assert.equal(state.startedAt, null, `${label} must stay below the set boundary`);
    assert.equal(state.prompt, false, `${label} must never ask to save a set`);
  }
});

test("labeled slow and fast strength traces start, end, and ask before saving", () => {
  for (const windows of [
    [2, 2, 2, 2, 2, 2, 2],
    [4, 4, 4, 4, 4, 4, 4]
  ]) {
    const state = detector();
    windows.forEach((reversals, second) =>
      applyWindow(state, { second, score: 190, reversals }));
    for (let second = windows.length; second <= windows.length + 4; second += 1) {
      applyWindow(state, { second, score: 10, reversals: 0 });
    }
    assert.notEqual(state.startedAt, null);
    assert.equal(state.prompt, true);
  }
});

test("post-save rest requires deadband plus a new rhythmic cycle", () => {
  const canRestart = ({ age, burst, rhythmic, reversals, score }) =>
    age >= 8 && burst >= 3 && rhythmic >= 2 && reversals >= 4 && score >= 130;
  assert.equal(canRestart({ age: 3, burst: 4, rhythmic: 4, reversals: 8, score: 200 }), false);
  assert.equal(canRestart({ age: 12, burst: 3, rhythmic: 0, reversals: 0, score: 220 }), false);
  assert.equal(canRestart({ age: 12, burst: 3, rhythmic: 2, reversals: 4, score: 180 }), true);
});

test("full and compact Garmin tiers share bounded motion completion and explicit confirmation", async () => {
  const source = await readFile("garmin/source/GymSession.mc", "utf8");
  assert.match(source, /static function motionSampleRate\(\)[\s\S]*var sampleRate = 25/);
  assert.match(source, /motionReversalCount >= 4/);
  assert.match(source, /if \(dominantAxis != motionLastAxis\)[\s\S]*motionLastDirection = 0/);
  assert.equal((source.match(/static function updateMotionLifecycle\(\)/g) || []).length, 2);
  assert.equal((source.match(/static function endSetFromMotion\(\)/g) || []).length, 2);
  assert.doesNotMatch(source, /endSetFromMotion\(\)[\s\S]{0,500}GymStore\.addSet\(/);
  assert.match(source, /endSetFromMotion\(\)[\s\S]*autoLogPrompt = true/);
});
