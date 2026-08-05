import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const flow = require("../pwa/shared-workout-flow.js");

const plan = {
  version: 1,
  exercises: [
    {
      catalogKey: "bench_press",
      name: "Bench Press",
      sets: [{ weight: 60, reps: 8 }, { weight: 62.5, reps: 6 }]
    },
    {
      name: "Custom movement",
      sets: [{ weight: 0, reps: 12 }]
    }
  ]
};

test("a confirmed shared plan becomes a separate editable draft", () => {
  const original = structuredClone(plan);
  const result = flow.prepareImport(plan, { now: 1_700_000_000_000 });

  assert.equal(result.status, "ready");
  assert.deepEqual(result.draft, {
    startedAt: 1_700_000_000_000,
    note: "",
    blocks: [
      {
        exerciseName: "Bench Press",
        catalogKey: "bench_press",
        sets: [{ weight: 60, reps: 8 }, { weight: 62.5, reps: 6 }]
      },
      {
        exerciseName: "Custom movement",
        sets: [{ weight: 0, reps: 12 }]
      }
    ]
  });
  assert.deepEqual(plan, original);
  assert.notEqual(result.draft.blocks[0].sets, plan.exercises[0].sets);
});

test("an active workout blocks import even when draft replacement was allowed", () => {
  const result = flow.prepareImport(plan, {
    hasActiveWorkout: true,
    hasDraft: true,
    allowDraftReplacement: true,
    now: 1_700_000_000_000
  });

  assert.equal(result.status, "blocked-active");
  assert.equal("draft" in result, false);
  assert.deepEqual(result.plan, plan);
});

test("an existing draft requires a separate replacement confirmation", () => {
  const review = flow.prepareImport(plan, {
    hasDraft: true,
    now: 1_700_000_000_000
  });
  assert.equal(review.status, "confirm-replace");
  assert.equal("draft" in review, false);

  const confirmed = flow.prepareImport(plan, {
    hasDraft: true,
    allowDraftReplacement: true,
    now: 1_700_000_000_000
  });
  assert.equal(confirmed.status, "ready");
  assert.equal(confirmed.draft.blocks[0].exerciseName, "Bench Press");
});

test("malformed plans and invalid timestamps fail without producing a draft", () => {
  assert.throws(
    () => flow.prepareImport({ exercises: [] }, { now: 1_700_000_000_000 }),
    /exercise count/
  );
  assert.throws(() => flow.editableDraft(plan, Number.NaN), /timestamp/);
  assert.throws(() => flow.editableDraft(plan, 0), /timestamp/);
});

test("import rejects Unicode controls, formats, and line separators before creating a draft", () => {
  const unsafeScalars = ["\u0080", "\u009f", "\u200b", "\u2060", "\ufeff", "\u2028", "\u2029"];
  for (const scalar of unsafeScalars) {
    assert.throws(
      () => flow.prepareImport({
        exercises: [{ name: `Visible${scalar}Name`, sets: [{ weight: 10, reps: 8 }] }]
      }, { now: 1_700_000_000_000 }),
      /supported bounds/
    );
  }
});
