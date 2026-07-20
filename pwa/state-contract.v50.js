(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymStateContract = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function buildStateContract() {
  "use strict";

  const LIMITS = Object.freeze({
    rawBytes: 8 * 1024 * 1024,
    jsonStringBytes: 64 * 1024,
    maxDepth: 8,
    maxNodes: 1000000,
    exercises: 2000,
    sessions: 5000,
    exercisesPerSession: 100,
    setsPerExercise: 100,
    totalSets: 100000,
    exerciseName: 160,
    exerciseNameBytes: 640,
    note: 4000,
    noteBytes: 16000,
    mappingEntries: 2000,
    mappingMuscles: 32,
    timestampMin: -62135769600000,
    timestampMax: 64092211200000,
    weightMax: 1000000,
    repsMax: 10000
  });

  const PROFILE_ENUMS = Object.freeze({
    split: Object.freeze(["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"]),
    goal: Object.freeze(["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"]),
    calories: Object.freeze(["Deficit", "Maintenance", "Surplus"])
  });
  const CATALOG_SEED_VERSION = 1;

  class StateContractError extends Error {
    constructor(message, code = "invalid_state") {
      super(message);
      this.name = "StateContractError";
      this.code = code;
    }
  }

  function fail(message, code) {
    throw new StateContractError(message, code);
  }

  function utf8ByteLength(value) {
    return new TextEncoder().encode(String(value)).byteLength;
  }

  function isRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function assertObject(value, path) {
    if (!isRecord(value)) fail(`${path} must be an object.`);
    return value;
  }

  function assertJsonBudget(value) {
    const stack = [{ value, depth: 0 }];
    let nodes = 0;
    while (stack.length) {
      const current = stack.pop();
      nodes += 1;
      if (nodes > LIMITS.maxNodes) fail("Backup contains too many values.", "state_too_complex");
      if (current.depth > LIMITS.maxDepth) fail("Backup nesting is too deep.", "state_too_deep");
      if (typeof current.value === "string" && utf8ByteLength(current.value) > LIMITS.jsonStringBytes) {
        fail("Backup contains an oversized string.", "state_too_complex");
      }
      if (current.value === null || typeof current.value !== "object") continue;
      if (Array.isArray(current.value)) {
        for (let index = current.value.length - 1; index >= 0; index -= 1) {
          stack.push({ value: current.value[index], depth: current.depth + 1 });
        }
        continue;
      }
      for (const [key, child] of Object.entries(current.value)) {
        if (key === "__proto__" || key === "prototype" || key === "constructor") {
          fail("Backup contains a forbidden object key.");
        }
        if (utf8ByteLength(key) > LIMITS.jsonStringBytes) {
          fail("Backup contains an oversized object key.", "state_too_complex");
        }
        stack.push({ value: child, depth: current.depth + 1 });
      }
    }
  }

  function boundedString(value, path, maxLength, { optional = false, allowEmpty = false, maxBytes = null } = {}) {
    if (value == null && optional) return "";
    if (typeof value !== "string") fail(`${path} must be a string.`);
    const normalized = value.trim();
    if ((!allowEmpty && !normalized) || normalized.length > maxLength ||
        (maxBytes !== null && utf8ByteLength(normalized) > maxBytes)) {
      fail(`${path} is outside the supported length.`);
    }
    return normalized;
  }

  function optionalCatalogKey(value, path) {
    if (value == null || value === "") return undefined;
    const key = boundedString(value, path, 80);
    if (!/^[a-z0-9_-]+$/i.test(key)) fail(`${path} contains unsupported characters.`);
    return key;
  }

  function finiteNumber(value, path, min, max) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
      fail(`${path} must be a finite number between ${min} and ${max}.`);
    }
    return value;
  }

  function integer(value, path, min, max) {
    if (!Number.isInteger(value) || value < min || value > max) {
      fail(`${path} must be an integer between ${min} and ${max}.`);
    }
    return value;
  }

  function timestamp(value, path) {
    return integer(value, path, LIMITS.timestampMin, LIMITS.timestampMax);
  }

  function optionalId(value, fallback, path) {
    if (value == null || value === "") return fallback;
    if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return value;
    if (typeof value === "string" && /^\d{1,15}$/.test(value)) {
      const parsed = Number(value);
      if (Number.isSafeInteger(parsed) && parsed > 0) return parsed;
    }
    fail(`${path} must be a positive safe integer.`);
  }

  function exerciseName(value, path) {
    const options = { maxBytes: LIMITS.exerciseNameBytes };
    if (typeof value === "string") return boundedString(value, path, LIMITS.exerciseName, options);
    const item = assertObject(value, path);
    if (isRecord(item.exercise)) {
      return boundedString(item.exercise.name ?? item.exercise.title, `${path}.exercise.name`, LIMITS.exerciseName, options);
    }
    return boundedString(item.name ?? item.exerciseName ?? item.title, `${path}.name`, LIMITS.exerciseName, options);
  }

  function normalizeCatalogItem(value, index, path) {
    const name = exerciseName(value, `${path}[${index}]`);
    const item = isRecord(value) ? value : {};
    const catalogKey = optionalCatalogKey(item.catalogKey ?? item.exerciseCatalogKey, `${path}[${index}].catalogKey`);
    return {
      id: optionalId(item.id, index + 1, `${path}[${index}].id`),
      name,
      ...(catalogKey ? { catalogKey } : {})
    };
  }

  function normalizeSet(value, index, inheritedName, inheritedCatalogKey, path, idBase) {
    const item = assertObject(value, `${path}[${index}]`);
    const name = inheritedName || exerciseName(item, `${path}[${index}]`);
    const catalogKey = optionalCatalogKey(
      item.catalogKey ?? item.exerciseCatalogKey ?? inheritedCatalogKey,
      `${path}[${index}].catalogKey`
    );
    const weight = finiteNumber(
      item.weight ?? item.weightKg ?? item.kg,
      `${path}[${index}].weight`,
      0,
      LIMITS.weightMax
    );
    const reps = integer(
      item.reps ?? item.repeatCount ?? item.count,
      `${path}[${index}].reps`,
      1,
      LIMITS.repsMax
    );
    const orderIndex = item.orderIndex == null && item.index == null
      ? index
      : integer(item.orderIndex ?? item.index, `${path}[${index}].orderIndex`, 0, 9999);
    return {
      id: optionalId(item.id, idBase + index, `${path}[${index}].id`),
      exerciseName: name,
      ...(catalogKey ? { catalogKey } : {}),
      weight,
      reps,
      orderIndex
    };
  }

  function arrayField(object, fields, path) {
    let selected = null;
    for (const field of fields) {
      if (!(field in object) || object[field] == null) continue;
      if (!Array.isArray(object[field])) fail(`${path}.${field} must be an array.`);
      if (selected === null) selected = object[field];
    }
    return selected || [];
  }

  function normalizeNestedExercises(session, sessionIndex, idBase, path) {
    const fields = ["exercises", "workoutExercises", "exerciseDetails", "items"];
    const exercises = arrayField(session, fields, path);
    if (exercises.length > LIMITS.exercisesPerSession) {
      fail(`${path}.exercises exceeds ${LIMITS.exercisesPerSession} items.`, "too_many_exercises");
    }
    const names = [];
    const sets = [];
    exercises.forEach((rawExercise, exerciseIndex) => {
      const exercise = assertObject(rawExercise, `${path}.exercises[${exerciseIndex}]`);
      const name = exerciseName(exercise, `${path}.exercises[${exerciseIndex}]`);
      const catalogKey = optionalCatalogKey(
        exercise.catalogKey ?? exercise.exerciseCatalogKey,
        `${path}.exercises[${exerciseIndex}].catalogKey`
      );
      const rawSets = arrayField(exercise, ["sets", "setEntries", "entries", "history"], `${path}.exercises[${exerciseIndex}]`);
      if (rawSets.length > LIMITS.setsPerExercise) {
        fail(`${path}.exercises[${exerciseIndex}].sets exceeds ${LIMITS.setsPerExercise} items.`, "too_many_sets");
      }
      names.push(name);
      rawSets.forEach((set, setIndex) => {
        sets.push(normalizeSet(
          set,
          setIndex,
          name,
          catalogKey,
          `${path}.exercises[${exerciseIndex}].sets`,
          idBase + exerciseIndex * LIMITS.setsPerExercise
        ));
      });
    });
    return { names, sets };
  }

  function normalizeFlatSets(session, sessionIndex, idBase, path) {
    if (!("sets" in session) || session.sets == null) return [];
    if (!Array.isArray(session.sets)) fail(`${path}.sets must be an array.`);
    if (session.sets.length > LIMITS.exercisesPerSession * LIMITS.setsPerExercise) {
      fail(`${path}.sets exceeds the per-workout set budget.`, "too_many_sets");
    }
    const counts = new Map();
    return session.sets.map((set, setIndex) => {
      const normalized = normalizeSet(set, setIndex, "", undefined, `${path}.sets`, idBase);
      const key = normalized.exerciseName.toLocaleLowerCase("en-US");
      const next = (counts.get(key) || 0) + 1;
      if (next > LIMITS.setsPerExercise) {
        fail(`${path}.sets contains more than ${LIMITS.setsPerExercise} sets for one exercise.`, "too_many_sets");
      }
      counts.set(key, next);
      return normalized;
    });
  }

  function normalizeSession(value, index, counters) {
    const path = `state.sessions[${index}]`;
    const session = assertObject(value, path);
    const idBase = counters.idBase + counters.totalSets + index * 10001;
    const nested = normalizeNestedExercises(session, index, idBase, path);
    const flat = normalizeFlatSets(session, index, idBase, path);
    const sets = flat.length ? flat : nested.sets;
    counters.totalSets += sets.length;
    if (counters.totalSets > LIMITS.totalSets) {
      fail(`Backup exceeds ${LIMITS.totalSets} total sets.`, "too_many_sets");
    }

    const explicitNames = arrayField(session, ["exerciseNames"], path);
    if (explicitNames.length > LIMITS.exercisesPerSession) {
      fail(`${path}.exerciseNames exceeds ${LIMITS.exercisesPerSession} items.`, "too_many_exercises");
    }
    const names = [
      ...explicitNames.map((name, nameIndex) => exerciseName(name, `${path}.exerciseNames[${nameIndex}]`)),
      ...nested.names,
      ...sets.map(set => set.exerciseName)
    ];
    const uniqueNames = [];
    const seenNames = new Set();
    for (const name of names) {
      const key = name.toLocaleLowerCase("en-US");
      if (!seenNames.has(key)) {
        seenNames.add(key);
        uniqueNames.push(name);
      }
    }
    if (uniqueNames.length > LIMITS.exercisesPerSession) {
      fail(`${path} exceeds ${LIMITS.exercisesPerSession} exercises.`, "too_many_exercises");
    }
    for (const name of uniqueNames) {
      counters.knownExerciseNames.add(name.toLocaleLowerCase("en-US"));
      if (counters.knownExerciseNames.size > LIMITS.exercises) {
        fail(`Backup exceeds ${LIMITS.exercises} distinct exercises.`, "too_many_exercises");
      }
    }

    const startedAtValue = session.startedAt ?? session.date;
    if (startedAtValue == null) fail(`${path}.startedAt is required.`);
    const note = session.note == null
      ? ""
      : boundedString(session.note, `${path}.note`, LIMITS.note, {
          allowEmpty: true,
          maxBytes: LIMITS.noteBytes
        });
    return {
      id: optionalId(session.id, counters.idBase + index, `${path}.id`),
      startedAt: timestamp(startedAtValue, `${path}.startedAt`),
      note,
      exerciseNames: uniqueNames,
      sets
    };
  }

  function safeProfile(input, fallback) {
    const source = input == null ? {} : assertObject(input, "state.profile");
    const defaults = isRecord(fallback) ? fallback : {};
    const enumValue = (key, hardDefault) => {
      const allowed = PROFILE_ENUMS[key];
      const fallbackValue = allowed.includes(defaults[key]) ? defaults[key] : hardDefault;
      return allowed.includes(source[key]) ? source[key] : fallbackValue;
    };
    const fallbackDays = Number.isInteger(defaults.days) && defaults.days >= 2 && defaults.days <= 6 ? defaults.days : 4;
    const days = Number.isInteger(source.days) && source.days >= 2 && source.days <= 6 ? source.days : fallbackDays;
    return {
      split: enumValue("split", "Push Pull Legs"),
      days,
      goal: enumValue("goal", "Balanced"),
      calories: enumValue("calories", "Maintenance")
    };
  }

  function normalizeMappings(input, fallback) {
    // Mapping names are user-controlled exercise labels. A null-prototype
    // dictionary keeps labels such as "__proto__" from mutating object state.
    const merged = Object.create(null);
    const append = (source, trusted) => {
      if (source == null) return;
      if (!isRecord(source)) {
        if (trusted) return;
        fail("state.mappings must be an object.");
      }
      const entries = Object.entries(source);
      if (!trusted && entries.length > LIMITS.mappingEntries) {
        fail(`state.mappings exceeds ${LIMITS.mappingEntries} entries.`, "too_many_mappings");
      }
      for (const [rawName, rawMuscles] of entries) {
        const name = boundedString(rawName, "state.mappings key", LIMITS.exerciseName, {
          maxBytes: LIMITS.exerciseNameBytes
        });
        if (!Array.isArray(rawMuscles)) {
          if (trusted) continue;
          fail(`state.mappings.${name} must be an array.`);
        }
        if (rawMuscles.length > LIMITS.mappingMuscles) {
          fail(`state.mappings.${name} has too many muscle IDs.`);
        }
        merged[name] = [...new Set(rawMuscles.map((muscle, index) =>
          boundedString(muscle, `state.mappings.${name}[${index}]`, 64)
        ))];
      }
    };
    append(fallback, true);
    append(input, false);
    if (Object.keys(merged).length > LIMITS.mappingEntries) {
      fail(`state.mappings exceeds ${LIMITS.mappingEntries} entries.`, "too_many_mappings");
    }
    return merged;
  }

  function normalizeOwner(value) {
    if (value == null) return null;
    const owner = assertObject(value, "owner");
    const optional = (key, max) => owner[key] == null
      ? null
      : boundedString(owner[key], `owner.${key}`, max, { allowEmpty: true }) || null;
    let remote = null;
    if (typeof owner.remote === "boolean") remote = owner.remote;
    else if (owner.remote === "supabase") remote = owner.remote;
    else if (owner.remote != null) fail("owner.remote is unsupported.");
    return {
      accountId: optional("accountId", 64),
      userId: optional("userId", 64),
      email: optional("email", 254),
      remote
    };
  }

  function normalizeRoot(root, fallback = {}) {
    assertObject(root, "state");
    if (root.schemaVersion != null && root.schemaVersion !== 2) {
      fail("Unsupported GymApp backup schema version.", "unsupported_schema");
    }
    if (root.exportedAt != null) timestamp(root.exportedAt, "state.exportedAt");
    for (const field of ["app", "source"]) {
      if (root[field] != null) boundedString(root[field], `state.${field}`, 128, { allowEmpty: true });
    }
    if (root.diagnostics != null && typeof root.diagnostics !== "boolean") {
      fail("state.diagnostics must be a boolean.");
    }
    if (root.language != null && !["en", "uk", "ru"].includes(root.language)) {
      fail("state.language is unsupported.");
    }
    if (root.exercises != null && !Array.isArray(root.exercises)) {
      fail("state.exercises must be an array.");
    }
    if (root.exerciseCatalog != null && !Array.isArray(root.exerciseCatalog)) {
      fail("state.exerciseCatalog must be an array.");
    }
    const fallbackExercises = Array.isArray(fallback.exercises) ? fallback.exercises : [];
    const exerciseInput = root.exercises ?? root.exerciseCatalog ?? fallbackExercises;
    if (exerciseInput.length > LIMITS.exercises) {
      fail(`Backup exceeds ${LIMITS.exercises} exercises.`, "too_many_exercises");
    }
    if (root.sessions != null && !Array.isArray(root.sessions)) fail("state.sessions must be an array.");
    const sessionsInput = root.sessions || [];
    if (sessionsInput.length > LIMITS.sessions) {
      fail(`Backup exceeds ${LIMITS.sessions} sessions.`, "too_many_sessions");
    }
    const normalizedExercises = exerciseInput.map((exercise, index) =>
      normalizeCatalogItem(exercise, index, "state.exercises")
    );
    const knownExerciseNames = new Set(
      normalizedExercises.map(exercise => exercise.name.toLocaleLowerCase("en-US"))
    );
    const counters = { totalSets: 0, idBase: Date.now(), knownExerciseNames };
    const state = {
      language: ["uk", "ru"].includes(root.language) ? root.language : "en",
      catalogSeedVersion: root.catalogSeedVersion == null
        ? 0
        : integer(root.catalogSeedVersion, "state.catalogSeedVersion", 0, CATALOG_SEED_VERSION),
      exercises: normalizedExercises,
      sessions: sessionsInput.map((session, index) => normalizeSession(session, index, counters)),
      mappings: normalizeMappings(root.mappings, fallback.mappings),
      profile: safeProfile(root.profile, fallback.profile)
    };
    if (root.progressExerciseId != null) {
      state.progressExerciseId = optionalId(root.progressExerciseId, 1, "state.progressExerciseId");
    }
    return {
      state,
      owner: normalizeOwner(root.owner),
      diagnostics: root.diagnostics === true
    };
  }

  function validateAndNormalize(input, options = {}) {
    let root = input;
    if (typeof input === "string") {
      if (utf8ByteLength(input) > LIMITS.rawBytes) {
        fail(`Backup exceeds ${LIMITS.rawBytes} UTF-8 bytes.`, "state_too_large");
      }
      try {
        root = JSON.parse(input);
      } catch {
        fail("Backup is not valid JSON.", "invalid_json");
      }
    }
    assertJsonBudget(root);
    if (typeof input !== "string") {
      let encoded;
      try {
        encoded = JSON.stringify(root);
      } catch {
        fail("Backup cannot be encoded as JSON.", "invalid_json");
      }
      if (utf8ByteLength(encoded) > LIMITS.rawBytes) {
        fail(`Backup exceeds ${LIMITS.rawBytes} UTF-8 bytes.`, "state_too_large");
      }
    }
    return normalizeRoot(root, options.fallback || {});
  }

  function normalizeState(input, options = {}) {
    return validateAndNormalize(input, options).state;
  }

  return Object.freeze({
    LIMITS,
    PROFILE_ENUMS,
    StateContractError,
    utf8ByteLength,
    validateAndNormalize,
    normalizeState
  });
});
