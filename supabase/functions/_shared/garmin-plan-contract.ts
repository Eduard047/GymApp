export const GARMIN_PLAN_LIMITS = Object.freeze({
  encodedBytes: 64 * 1024,
  title: 120,
  note: 2000,
  exerciseName: 160,
  exerciseNameBytes: 640,
  totalExerciseNameBytes: 12_000,
  exercises: 60,
  totalSets: 60,
  timestamp: 40,
  weightMax: 1_000_000,
  repsMax: 10_000,
});

export type GarminPlan = {
  source: string;
  version: 1;
  title: string;
  createdAt: string;
  startedAt: string;
  note: string;
  exercises: Array<{
    name: string;
    sets: Array<{ weight: number; reps: number; orderIndex: number }>;
  }>;
};

export type GarminPlanValidation =
  | { ok: true; plan: GarminPlan }
  | { ok: false; error: string };

const RFC3339_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function boundedString(
  value: unknown,
  max: number,
  allowEmpty = false,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  if ((!allowEmpty && !normalized) || normalized.length > max) return null;
  return normalized;
}

function isoTimestamp(value: unknown): string | null {
  const text = boundedString(value, GARMIN_PLAN_LIMITS.timestamp);
  if (!text || !RFC3339_PATTERN.test(text)) return null;
  const millis = Date.parse(text);
  return Number.isFinite(millis) ? new Date(millis).toISOString() : null;
}

export function validateGarminPlan(value: unknown): GarminPlanValidation {
  if (!isObject(value)) return { ok: false, error: "Plan must be an object." };
  let encoded: string;
  try {
    encoded = JSON.stringify(value);
  } catch {
    return { ok: false, error: "Plan cannot be encoded as JSON." };
  }
  if (
    new TextEncoder().encode(encoded).byteLength >
      GARMIN_PLAN_LIMITS.encodedBytes
  ) {
    return { ok: false, error: "Plan exceeds the encoded byte limit." };
  }

  const source = boundedString(value.source, 32);
  const title = boundedString(value.title, GARMIN_PLAN_LIMITS.title);
  const note = boundedString(value.note ?? "", GARMIN_PLAN_LIMITS.note, true);
  const createdAt = isoTimestamp(value.createdAt);
  const startedAt = isoTimestamp(value.startedAt);
  if (
    !source || value.version !== 1 || !title || note === null || !createdAt ||
    !startedAt
  ) {
    return { ok: false, error: "Plan metadata is invalid." };
  }
  if (
    !Array.isArray(value.exercises) || value.exercises.length < 1 ||
    value.exercises.length > GARMIN_PLAN_LIMITS.exercises
  ) {
    return { ok: false, error: "Plan exercise count is invalid." };
  }

  let totalSets = 0;
  let totalExerciseNameBytes = 0;
  const exercises: GarminPlan["exercises"] = [];
  for (const rawExercise of value.exercises) {
    if (!isObject(rawExercise)) {
      return { ok: false, error: "Plan exercise must be an object." };
    }
    const name = boundedString(
      rawExercise.name,
      GARMIN_PLAN_LIMITS.exerciseName,
    );
    if (
      !name || new TextEncoder().encode(name).byteLength >
        GARMIN_PLAN_LIMITS.exerciseNameBytes ||
      !Array.isArray(rawExercise.sets) ||
      rawExercise.sets.length < 1 ||
      rawExercise.sets.length > GARMIN_PLAN_LIMITS.totalSets
    ) {
      return {
        ok: false,
        error: "Plan exercise name or set count is invalid.",
      };
    }
    totalSets += rawExercise.sets.length;
    if (totalSets > GARMIN_PLAN_LIMITS.totalSets) {
      return { ok: false, error: "Plan exceeds 60 total sets." };
    }
    totalExerciseNameBytes += new TextEncoder().encode(name).byteLength *
      rawExercise.sets.length;
    if (
      totalExerciseNameBytes > GARMIN_PLAN_LIMITS.totalExerciseNameBytes
    ) {
      return {
        ok: false,
        error: "Plan exercise names exceed the Garmin storage byte limit.",
      };
    }
    const sets: GarminPlan["exercises"][number]["sets"] = [];
    for (const [setIndex, rawSet] of rawExercise.sets.entries()) {
      if (!isObject(rawSet)) {
        return { ok: false, error: "Plan set must be an object." };
      }
      const weight = rawSet.weight;
      const reps = rawSet.reps;
      const orderIndex = rawSet.orderIndex ?? setIndex;
      if (
        typeof weight !== "number" || !Number.isFinite(weight) || weight < 0 ||
        weight > GARMIN_PLAN_LIMITS.weightMax
      ) {
        return { ok: false, error: "Plan weight is invalid." };
      }
      if (
        !Number.isInteger(reps) || (reps as number) < 1 ||
        (reps as number) > GARMIN_PLAN_LIMITS.repsMax
      ) {
        return { ok: false, error: "Plan reps are invalid." };
      }
      if (
        !Number.isInteger(orderIndex) || (orderIndex as number) !== setIndex
      ) {
        return { ok: false, error: "Plan set order is invalid." };
      }
      sets.push({
        weight,
        reps: reps as number,
        orderIndex: orderIndex as number,
      });
    }
    exercises.push({ name, sets });
  }

  return {
    ok: true,
    plan: { source, version: 1, title, createdAt, startedAt, note, exercises },
  };
}
