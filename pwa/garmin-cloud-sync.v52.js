(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymGarminCloud = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function () {
  "use strict";

  const PLAN_LIMITS = Object.freeze({
    encodedBytes: 64 * 1024,
    title: 120,
    note: 2000,
    exerciseName: 160,
    exerciseNameBytes: 640,
    totalExerciseNameBytes: 12000,
    exercises: 60,
    totalSets: 60,
    timestamp: 40,
    weightMax: 1000000,
    repsMax: 10000
  });
  const MAX_PLAN_REVISION = 2147483647;
  const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const RFC3339_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

  function byteLength(value) {
    return new TextEncoder().encode(String(value)).byteLength;
  }

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function boundedString(value, max, { allowEmpty = false } = {}) {
    if (typeof value !== "string") return null;
    const normalized = value.trim();
    if ((!allowEmpty && !normalized) || normalized.length > max) return null;
    return normalized;
  }

  function isoTimestamp(value) {
    const text = boundedString(value, PLAN_LIMITS.timestamp);
    if (!text || !RFC3339_PATTERN.test(text)) return null;
    const millis = Date.parse(text);
    return Number.isFinite(millis) ? new Date(millis).toISOString() : null;
  }

  function validateGarminPlan(value) {
    if (!isObject(value)) return { ok: false, error: "Plan must be an object." };
    let encoded;
    try {
      encoded = JSON.stringify(value);
    } catch {
      return { ok: false, error: "Plan cannot be encoded as JSON." };
    }
    if (byteLength(encoded) > PLAN_LIMITS.encodedBytes) {
      return { ok: false, error: "Plan exceeds the encoded byte limit." };
    }
    const source = boundedString(value.source, 32);
    const title = boundedString(value.title, PLAN_LIMITS.title);
    const note = boundedString(value.note ?? "", PLAN_LIMITS.note, { allowEmpty: true });
    const createdAt = isoTimestamp(value.createdAt);
    const startedAt = isoTimestamp(value.startedAt);
    if (!source || value.version !== 1 || !title || note === null || !createdAt || !startedAt) {
      return { ok: false, error: "Plan metadata is invalid." };
    }
    if (!Array.isArray(value.exercises) || value.exercises.length < 1 || value.exercises.length > PLAN_LIMITS.exercises) {
      return { ok: false, error: "Plan exercise count is invalid." };
    }

    let totalSets = 0;
    let totalExerciseNameBytes = 0;
    const exercises = [];
    for (const [exerciseIndex, rawExercise] of value.exercises.entries()) {
      if (!isObject(rawExercise)) return { ok: false, error: "Plan exercise must be an object." };
      const name = boundedString(rawExercise.name, PLAN_LIMITS.exerciseName);
      if (!name || byteLength(name) > PLAN_LIMITS.exerciseNameBytes ||
          !Array.isArray(rawExercise.sets) || rawExercise.sets.length < 1 || rawExercise.sets.length > PLAN_LIMITS.totalSets) {
        return { ok: false, error: "Plan exercise name or set count is invalid." };
      }
      totalSets += rawExercise.sets.length;
      if (totalSets > PLAN_LIMITS.totalSets) return { ok: false, error: "Plan exceeds 60 total sets." };
      totalExerciseNameBytes += byteLength(name) * rawExercise.sets.length;
      if (totalExerciseNameBytes > PLAN_LIMITS.totalExerciseNameBytes) {
        return { ok: false, error: "Plan exercise names exceed the Garmin storage byte limit." };
      }
      const sets = [];
      for (const [setIndex, rawSet] of rawExercise.sets.entries()) {
        if (!isObject(rawSet)) return { ok: false, error: "Plan set must be an object." };
        const weight = rawSet.weight;
        const reps = rawSet.reps;
        const orderIndex = rawSet.orderIndex ?? setIndex;
        if (typeof weight !== "number" || !Number.isFinite(weight) || weight < 0 || weight > PLAN_LIMITS.weightMax) {
          return { ok: false, error: "Plan weight is invalid." };
        }
        if (!Number.isInteger(reps) || reps < 1 || reps > PLAN_LIMITS.repsMax) {
          return { ok: false, error: "Plan reps are invalid." };
        }
        if (!Number.isInteger(orderIndex) || orderIndex !== setIndex) {
          return { ok: false, error: "Plan set order is invalid." };
        }
        sets.push({ weight, reps, orderIndex });
      }
      exercises.push({ name, sets });
      if (exerciseIndex + 1 > PLAN_LIMITS.exercises) return { ok: false, error: "Plan has too many exercises." };
    }

    return {
      ok: true,
      plan: { source, version: 1, title, createdAt, startedAt, note, exercises }
    };
  }

  function draftToGarminPlan(draft, options = {}) {
    if (!draft || !Array.isArray(draft.blocks) || draft.blocks.length < 1 || draft.blocks.length > PLAN_LIMITS.exercises) {
      return null;
    }
    const exercises = [];
    for (const block of draft.blocks) {
      if (!isObject(block)) return null;
      const name = boundedString(block.exerciseName, PLAN_LIMITS.exerciseName);
      if (!name) {
        if (Array.isArray(block.sets) && block.sets.length === 0) continue;
        return null;
      }
      if (!Array.isArray(block.sets) || block.sets.length < 1 || block.sets.length > PLAN_LIMITS.totalSets) return null;
      const sets = [];
      for (const [index, set] of block.sets.entries()) {
        if (!isObject(set)) return null;
        const weightText = typeof set.weight === "string" ? set.weight.replace(",", ".").trim() : set.weight;
        const repsText = typeof set.reps === "string" ? set.reps.trim() : set.reps;
        if (weightText === "" || repsText === "") return null;
        const weight = Number(weightText);
        const reps = Number(repsText);
        if (!Number.isFinite(weight) || weight < 0 || weight > PLAN_LIMITS.weightMax ||
            !Number.isInteger(reps) || reps < 1 || reps > PLAN_LIMITS.repsMax) return null;
        sets.push({ weight, reps, orderIndex: index });
      }
      exercises.push({ name, sets });
    }
    if (!exercises.length) return null;
    const now = options.now || (() => new Date());
    const createdAt = now();
    const startedAt = new Date(draft.startedAt ?? Date.now());
    if (!(createdAt instanceof Date) || !Number.isFinite(createdAt.getTime()) || !Number.isFinite(startedAt.getTime())) return null;
    const candidate = {
      source: "pwa",
      version: 1,
      title: options.title || "Workout plan",
      createdAt: createdAt.toISOString(),
      startedAt: startedAt.toISOString(),
      note: draft.note || "",
      exercises
    };
    const validation = validateGarminPlan(candidate);
    return validation.ok ? validation.plan : null;
  }

  function cloudPlanResponseToSyncMessage(response) {
    if (!response || response.status !== "ok" || response.bindingVersion !== 2 ||
        !/^[a-f0-9]{64}$/.test(String(response.accountBinding || "")) ||
        !UUID_PATTERN.test(String(response.deviceBinding || "")) ||
        !UUID_PATTERN.test(String(response.planId || "")) ||
        !Number.isInteger(response.planRevision) || response.planRevision < 1 ||
        response.planRevision > MAX_PLAN_REVISION) return null;
    const validation = validateGarminPlan(response.plan);
    if (!validation.ok) return null;
    const planNames = [];
    const planWeights = [];
    const planReps = [];
    validation.plan.exercises.forEach(exercise => {
      exercise.sets.forEach(set => {
        planNames.push(exercise.name);
        planWeights.push(set.weight);
        planReps.push(set.reps);
      });
    });
    return {
      type: "sync",
      syncId: response.planId,
      bindingVersion: 2,
      accountBinding: response.accountBinding,
      deviceBinding: response.deviceBinding,
      planRevision: response.planRevision,
      resetWorkout: false,
      planNames,
      planWeights,
      planReps
    };
  }

  return Object.freeze({ PLAN_LIMITS, validateGarminPlan, draftToGarminPlan, cloudPlanResponseToSyncMessage });
});
