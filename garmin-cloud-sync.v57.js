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
  const WORKOUT_NOTE_LIMITS = Object.freeze({
    characters: 4000,
    encodedBytes: 16000,
    sets: 60,
    durationSeconds: 7 * 24 * 60 * 60,
    activeSeconds: 7200,
    restSeconds: 86400,
    heartRate: 240,
    calories: 100000,
    garminCalories: 100000,
    confidence: 100
  });

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

  function parsedInteger(value, minimum, maximum) {
    const number = Number(value);
    return Number.isInteger(number) && number >= minimum && number <= maximum ? number : null;
  }

  function parsedFinite(value, minimum, maximum) {
    const number = Number(value);
    return Number.isFinite(number) && number >= minimum && number <= maximum ? number : null;
  }

  function firstCapture(note, regex) {
    return (regex.exec(note) || [])[1] || "";
  }

  function firstInteger(note, regex, maximum) {
    const raw = firstCapture(note, regex);
    return raw ? parsedInteger(raw, 0, maximum) : null;
  }

  function parsedDurationSeconds(value) {
    if (typeof value !== "string") return null;
    const parts = value.split(":");
    if (parts.length !== 2 && parts.length !== 3) return null;
    const numbers = parts.map(part => /^\d+$/.test(part) ? Number(part) : NaN);
    if (numbers.some(number => !Number.isSafeInteger(number) || number < 0)) return null;
    const [hours, minutes, seconds] = parts.length === 3
      ? numbers
      : [0, numbers[0], numbers[1]];
    if (seconds > 59 || (parts.length === 3 && minutes > 59)) return null;
    const total = hours * 3600 + minutes * 60 + seconds;
    return Number.isSafeInteger(total) && total <= WORKOUT_NOTE_LIMITS.durationSeconds
      ? total
      : null;
  }

  function parseGarminSetNote(segment) {
    const header = /^S([1-9]\d?)\s+(.+)$/.exec(segment);
    if (!header) return null;
    const index = parsedInteger(header[1], 1, WORKOUT_NOTE_LIMITS.sets);
    if (index === null) return null;
    const body = header[2];
    const result = { index };
    let recognized = false;

    const activeMatch = /^(\d{1,4})s(?:\s|$)/.exec(body);
    const restMatch = /(?:^|\s)R(\d{1,5})s(?:\s|$)/.exec(body);
    const heartRateMatch = /(?:^|\s)HR(\d{1,3}|-)\/(\d{1,3}|-)\/(\d{1,3}|-)(?:\s|$)/.exec(body);
    const recoveryMatch = /(?:^|\s)↓(\d{1,3})(?:\s|$)/.exec(body);
    const confidenceMatch = /(?:^|\s)C(\d{1,3})%(?:\s|$)/.exec(body);
    const statistics = {};
    if (activeMatch) {
      const value = parsedInteger(activeMatch[1], 0, WORKOUT_NOTE_LIMITS.activeSeconds);
      if (value === null) return null;
      statistics.activeSeconds = value;
      recognized = true;
    }
    if (restMatch) {
      const value = parsedInteger(restMatch[1], 0, WORKOUT_NOTE_LIMITS.restSeconds);
      if (value === null) return null;
      statistics.restBeforeSeconds = value;
      recognized = true;
    }
    if (heartRateMatch) {
      const values = heartRateMatch.slice(1).map(value => value === "-"
        ? null
        : parsedInteger(value, 0, WORKOUT_NOTE_LIMITS.heartRate));
      if (values.some((value, position) => heartRateMatch[position + 1] !== "-" && value === null) ||
          (values[0] !== null && values[1] !== null && values[0] > values[1]) ||
          (values[2] !== null && values[1] !== null && values[2] > values[1])) return null;
      [statistics.startHeartRate, statistics.peakHeartRate, statistics.endHeartRate] = values;
      recognized = true;
    }
    if (recoveryMatch) {
      const value = parsedInteger(recoveryMatch[1], 0, WORKOUT_NOTE_LIMITS.heartRate);
      if (value === null) return null;
      statistics.recoveryHeartRateDrop = value;
      recognized = true;
    }
    if (confidenceMatch) {
      const value = parsedInteger(confidenceMatch[1], 0, WORKOUT_NOTE_LIMITS.confidence);
      if (value === null) return null;
      statistics.detectionConfidence = value;
      recognized = true;
    }
    if (Object.keys(statistics).length) result.statistics = statistics;

    const intervalMatch = /(?:^|\s)I(\d{1,6})-(\d{1,6})s(?:\s|$)/.exec(body);
    const caloriesMatch = /(?:^|\s)K(\d+(?:\.\d{1,2})?)\/(-|\d{1,6})(?:\s|$)/.exec(body);
    const zonesMatch = /(?:^|\s)Z(\d{1,4})\/(\d{1,4})\/(\d{1,4})\/(\d{1,4})\/(\d{1,4})\/(\d{1,4})s(?:\s|$)/.exec(body);
    const hasIntervalToken = Boolean(intervalMatch || caloriesMatch || zonesMatch);
    if (hasIntervalToken) {
      if (!intervalMatch || !caloriesMatch || !zonesMatch) return null;
      const startSeconds = parsedInteger(intervalMatch[1], 0, WORKOUT_NOTE_LIMITS.durationSeconds);
      const endSeconds = parsedInteger(intervalMatch[2], 0, WORKOUT_NOTE_LIMITS.durationSeconds);
      const gymCalories = parsedFinite(caloriesMatch[1], 0, WORKOUT_NOTE_LIMITS.calories);
      const garminCalories = caloriesMatch[2] === "-"
        ? null
        : parsedInteger(caloriesMatch[2], 0, WORKOUT_NOTE_LIMITS.garminCalories);
      const zoneSeconds = zonesMatch.slice(1).map(value => parsedInteger(value, 0, WORKOUT_NOTE_LIMITS.activeSeconds));
      if (startSeconds === null || endSeconds === null || endSeconds < startSeconds ||
          endSeconds - startSeconds > WORKOUT_NOTE_LIMITS.activeSeconds ||
          gymCalories === null || (caloriesMatch[2] !== "-" && garminCalories === null) ||
          zoneSeconds.some(value => value === null) ||
          zoneSeconds.reduce((sum, value) => sum + value, 0) > endSeconds - startSeconds) return null;
      result.interval = { startSeconds, endSeconds, gymCalories, garminCalories, zoneSeconds };
      recognized = true;
    }
    return recognized ? result : null;
  }

  function parseGarminWorkoutMetrics(note) {
    if (typeof note !== "string" || note.length > WORKOUT_NOTE_LIMITS.characters ||
        byteLength(note) > WORKOUT_NOTE_LIMITS.encodedBytes) return null;
    const normalized = note.trim();
    if (!/^Garmin(?: Fenix 8)?(?: ·|$)/i.test(normalized)) return null;
    const completedMatch = /(?:Completed|Partial|Виконано|Частково|Выполнено|Частично)\s+(\d{1,2})\/(\d{1,2})(?:\s|$)/i.exec(normalized);
    let completion = null;
    if (completedMatch) {
      const completedSets = parsedInteger(completedMatch[1], 0, WORKOUT_NOTE_LIMITS.sets);
      const plannedSets = parsedInteger(completedMatch[2], 1, WORKOUT_NOTE_LIMITS.sets);
      if (completedSets === null || plannedSets === null || completedSets >= plannedSets) return null;
      completion = { completedSets, plannedSets };
    }
    const segments = normalized.split(" · ");
    const omittedSegments = segments.filter(segment => segment.startsWith("S+"));
    let omittedSetIntervalCount = null;
    if (omittedSegments.length > 0) {
      if (omittedSegments.length !== 1) return null;
      const omittedMatch = /^S\+(\d{1,2})$/.exec(omittedSegments[0]);
      omittedSetIntervalCount = omittedMatch
        ? parsedInteger(omittedMatch[1], 1, WORKOUT_NOTE_LIMITS.sets)
        : null;
      if (omittedSetIntervalCount === null) return null;
    }
    const sets = [];
    for (const segment of segments) {
      if (!/^S\d+(?:\s|$)/.test(segment)) continue;
      const parsedSet = parseGarminSetNote(segment);
      // A structured row that advertises a set index must be valid in full.
      // Silently dropping a malformed interval would make the surrounding
      // note look like a trusted Garmin receipt while hiding bad metrics.
      if (!parsedSet) return null;
      sets.push(parsedSet);
    }
    if (new Set(sets.map(set => set.index)).size !== sets.length) return null;
    if (omittedSetIntervalCount !== null &&
        sets.length + omittedSetIntervalCount > WORKOUT_NOTE_LIMITS.sets) return null;
    const duration = firstCapture(
      normalized,
      /(?:Duration|Тривалість|Длительность)\s+([0-9]+:[0-9]{2}(?::[0-9]{2})?)/i
    );
    const durationSeconds = duration ? parsedDurationSeconds(duration) : null;
    if (duration && durationSeconds === null) return null;
    const intervalSets = sets.filter(set => set.interval);
    for (let index = 0; index < intervalSets.length; index += 1) {
      const interval = intervalSets[index].interval;
      if ((index > 0 && interval.startSeconds < intervalSets[index - 1].interval.endSeconds) ||
          (durationSeconds !== null && interval.endSeconds > durationSeconds)) return null;
    }
    let averageHeartRate = firstInteger(
      normalized,
      /(?:Avg HR|Сер пульс|Средний пульс)\s+([0-9]+)/i,
      WORKOUT_NOTE_LIMITS.heartRate
    );
    let maximumHeartRate = firstInteger(
      normalized,
      /(?:Max HR|Макс\.? пульс)\s+([0-9]+)/i,
      WORKOUT_NOTE_LIMITS.heartRate
    );
    if (averageHeartRate !== null && maximumHeartRate !== null &&
        averageHeartRate > maximumHeartRate) {
      averageHeartRate = null;
      maximumHeartRate = null;
    }
    return {
      duration,
      gymCalories: firstInteger(normalized, /Gym\s+(?:kcal|ккал)\s+([0-9]+)/i, WORKOUT_NOTE_LIMITS.garminCalories),
      garminCalories: firstInteger(normalized, /Garmin\s+(?:kcal|ккал)\s+([0-9]+)/i, WORKOUT_NOTE_LIMITS.garminCalories),
      avgHeartRate: averageHeartRate,
      maxHeartRate: maximumHeartRate,
      heartRateZone: firstCapture(normalized, /(?:Ending HR zone|HR zone|Кінцева зона пульсу|Зона пульсу|Конечная зона пульса)\s+(Z[0-5])/i),
      completion,
      omittedSetIntervalCount,
      sets
    };
  }

  return Object.freeze({
    PLAN_LIMITS,
    WORKOUT_NOTE_LIMITS,
    validateGarminPlan,
    draftToGarminPlan,
    cloudPlanResponseToSyncMessage,
    parseGarminWorkoutMetrics
  });
});
