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
    loadProfileWeights: 128,
    timestampMin: -62135769600000,
    timestampMax: 64092211200000,
    workoutDurationSeconds: 7 * 24 * 60 * 60,
    weightMax: 1000000,
    repsMax: 10000
  });

  const PROFILE_ENUMS = Object.freeze({
    split: Object.freeze(["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"]),
    goal: Object.freeze(["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"]),
    calories: Object.freeze(["Deficit", "Maintenance", "Surplus"])
  });
  const CATALOG_SEED_VERSION = 3;
  const UNSUPPORTED_EXERCISE_NAME_CONTROLS = /[\u0000-\u001f\u007f-\u009f]/u;
  const UNSUPPORTED_EXERCISE_NAME_CONTROLS_GLOBAL = /[\u0000-\u001f\u007f-\u009f]/gu;
  const LEGACY_EXERCISE_CONTROL_REPLACEMENT_BASE = 0xe000;

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

  function unicodeCodePointLengthAtMost(value, maximum) {
    const text = String(value);
    // UTF-16 uses one or two code units per Unicode code point. These cheap
    // bounds avoid walking ordinary short strings and obviously oversized input.
    if (text.length <= maximum) return true;
    if (text.length > maximum * 2) return false;
    let codePoints = 0;
    for (const _character of text) {
      codePoints += 1;
      if (codePoints > maximum) return false;
    }
    return true;
  }

  function portableExerciseNameKey(value) {
    return String(value ?? "")
      .normalize("NFC")
      .replace(/[\u02bc\u2019]/g, "'")
      .replace(/[\p{White_Space}\u001c-\u001f]+/gu, " ")
      .trim()
      .toLowerCase()
      .replace(/ё/g, "е");
  }

  function canonicalFiniteNumber(value) {
    return value === 0 ? 0 : value;
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

  function preflightJsonText(input) {
    let index = 0;
    let nodes = 0;

    function failSyntax() {
      fail("Backup is not valid JSON.", "invalid_json");
    }

    function skipWhitespace() {
      while (index < input.length && /[\u0009\u000a\u000d\u0020]/.test(input[index])) index += 1;
    }

    function scanString() {
      const start = index;
      if (input[index] !== "\"") failSyntax();
      index += 1;
      let decodedBytes = 0;
      while (index < input.length) {
        const code = input.charCodeAt(index);
        if (code === 0x22) {
          index += 1;
          if (decodedBytes > LIMITS.jsonStringBytes) {
            fail("Backup contains an oversized string.", "state_too_complex");
          }
          try {
            return JSON.parse(input.slice(start, index));
          } catch {
            failSyntax();
          }
        }
        if (code < 0x20) failSyntax();
        if (code === 0x5c) {
          index += 1;
          const escape = input[index];
          if (escape === "u") {
            const firstHex = input.slice(index + 1, index + 5);
            if (!/^[0-9a-fA-F]{4}$/.test(firstHex)) failSyntax();
            const firstUnit = Number.parseInt(firstHex, 16);
            const secondEscape = input.slice(index + 5, index + 11);
            if (firstUnit >= 0xd800 && firstUnit <= 0xdbff &&
                /^\\u[0-9a-fA-F]{4}$/.test(secondEscape)) {
              const secondUnit = Number.parseInt(secondEscape.slice(2), 16);
              if (secondUnit >= 0xdc00 && secondUnit <= 0xdfff) {
                decodedBytes += 4;
                index += 11;
              } else {
                decodedBytes += 3;
                index += 5;
              }
            } else {
              decodedBytes += firstUnit <= 0x7f ? 1 : firstUnit <= 0x7ff ? 2 : 3;
              index += 5;
            }
          } else if ('\"\\/bfnrt'.includes(escape || "")) {
            decodedBytes += 1;
            index += 1;
          } else {
            failSyntax();
          }
        } else {
          const nextCode = input.charCodeAt(index + 1);
          if (code >= 0xd800 && code <= 0xdbff && nextCode >= 0xdc00 && nextCode <= 0xdfff) {
            decodedBytes += 4;
            index += 2;
          } else {
            decodedBytes += code <= 0x7f ? 1 : code <= 0x7ff ? 2 : 3;
            index += 1;
          }
        }
        if (decodedBytes > LIMITS.jsonStringBytes) {
          fail("Backup contains an oversized string.", "state_too_complex");
        }
      }
      failSyntax();
    }

    function scanNumber() {
      const remainder = input.slice(index);
      const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(remainder);
      if (!match) failSyntax();
      index += match[0].length;
    }

    function countNode(depth) {
      nodes += 1;
      if (nodes > LIMITS.maxNodes) fail("Backup contains too many values.", "state_too_complex");
      if (depth > LIMITS.maxDepth) fail("Backup nesting is too deep.", "state_too_deep");
    }

    function scanValue(depth) {
      skipWhitespace();
      countNode(depth);
      const character = input[index];
      if (character === "{") {
        index += 1;
        skipWhitespace();
        const keys = new Set();
        if (input[index] === "}") {
          index += 1;
          return;
        }
        while (index < input.length) {
          skipWhitespace();
          const key = scanString();
          if (keys.has(key)) fail("Backup contains duplicate object keys.", "invalid_json");
          keys.add(key);
          skipWhitespace();
          if (input[index] !== ":") failSyntax();
          index += 1;
          scanValue(depth + 1);
          skipWhitespace();
          if (input[index] === "}") {
            index += 1;
            return;
          }
          if (input[index] !== ",") failSyntax();
          index += 1;
        }
        failSyntax();
      }
      if (character === "[") {
        index += 1;
        skipWhitespace();
        if (input[index] === "]") {
          index += 1;
          return;
        }
        while (index < input.length) {
          scanValue(depth + 1);
          skipWhitespace();
          if (input[index] === "]") {
            index += 1;
            return;
          }
          if (input[index] !== ",") failSyntax();
          index += 1;
        }
        failSyntax();
      }
      if (character === "\"") {
        scanString();
        return;
      }
      if (character === "-" || /[0-9]/.test(character || "")) {
        scanNumber();
        return;
      }
      for (const literal of ["true", "false", "null"]) {
        if (input.startsWith(literal, index)) {
          index += literal.length;
          return;
        }
      }
      failSyntax();
    }

    scanValue(0);
    skipWhitespace();
    if (index !== input.length) failSyntax();
  }

  function boundedString(value, path, maxLength, {
    optional = false,
    allowEmpty = false,
    maxBytes = null,
    unicodeCodePoints = false
  } = {}) {
    if (value == null && optional) return "";
    if (typeof value !== "string") fail(`${path} must be a string.`);
    const normalized = value.trim();
    const exceedsLength = unicodeCodePoints
      ? !unicodeCodePointLengthAtMost(normalized, maxLength)
      : normalized.length > maxLength;
    if ((!allowEmpty && !normalized) || exceedsLength ||
        (maxBytes !== null && utf8ByteLength(normalized) > maxBytes)) {
      fail(`${path} is outside the supported length.`);
    }
    return normalized;
  }

  function containsUnsupportedExerciseNameControls(value) {
    return typeof value === "string" && UNSUPPORTED_EXERCISE_NAME_CONTROLS.test(value);
  }

  function migrateLegacyExerciseNameControls(value) {
    if (!containsUnsupportedExerciseNameControls(value)) return value;
    return value.replace(UNSUPPORTED_EXERCISE_NAME_CONTROLS_GLOBAL, character =>
      String.fromCodePoint(LEGACY_EXERCISE_CONTROL_REPLACEMENT_BASE + character.codePointAt(0))
    );
  }

  function boundedExerciseName(value, path) {
    if (typeof value !== "string") fail(`${path} must be a string.`);
    if (containsUnsupportedExerciseNameControls(value)) {
      fail(`${path} contains unsupported control characters.`, "unsupported_exercise_name");
    }
    return boundedString(value, path, LIMITS.exerciseName, {
      maxBytes: LIMITS.exerciseNameBytes,
      unicodeCodePoints: true
    });
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
    if (typeof value === "string") return boundedExerciseName(value, path);
    const item = assertObject(value, path);
    if (isRecord(item.exercise)) {
      return boundedExerciseName(item.exercise.name ?? item.exercise.title, `${path}.exercise.name`);
    }
    return boundedExerciseName(item.name ?? item.exerciseName ?? item.title, `${path}.name`);
  }

  function stripCatalogIdentity(value) {
    if (!isRecord(value)) return;
    delete value.catalogKey;
    delete value.exerciseCatalogKey;
  }

  function migrateExerciseRecord(value, inheritedNameMigrated = false) {
    if (!isRecord(value)) return false;
    let migrated = false;
    const migrateField = (record, field) => {
      if (!Object.hasOwn(record, field) || typeof record[field] !== "string") return false;
      const next = migrateLegacyExerciseNameControls(record[field]);
      if (next === record[field]) return false;
      record[field] = next;
      stripCatalogIdentity(record);
      return true;
    };
    for (const field of ["name", "exerciseName", "title"]) {
      migrated = migrateField(value, field) || migrated;
    }
    if (isRecord(value.exercise)) {
      let nestedMigrated = false;
      for (const field of ["name", "exerciseName", "title"]) {
        nestedMigrated = migrateField(value.exercise, field) || nestedMigrated;
      }
      if (nestedMigrated) {
        stripCatalogIdentity(value);
        migrated = true;
      }
    }
    if (migrated || inheritedNameMigrated) stripCatalogIdentity(value);
    return migrated;
  }

  function migrateExerciseArray(values, migrateChildren = false) {
    if (!Array.isArray(values)) return false;
    let migrated = false;
    values.forEach((value, index) => {
      if (typeof value === "string") {
        const next = migrateLegacyExerciseNameControls(value);
        if (next !== value) {
          values[index] = next;
          migrated = true;
        }
        return;
      }
      if (!isRecord(value)) return;
      const exerciseMigrated = migrateExerciseRecord(value);
      migrated = exerciseMigrated || migrated;
      if (!migrateChildren) return;
      for (const field of ["sets", "setEntries", "entries", "history"]) {
        if (!Array.isArray(value[field])) continue;
        value[field].forEach(set => {
          if (!isRecord(set)) return;
          const setMigrated = migrateExerciseRecord(set, exerciseMigrated);
          migrated = setMigrated || migrated;
        });
      }
    });
    return migrated;
  }

  function migrateMappingKeys(value) {
    if (!isRecord(value)) return false;
    const entries = Object.entries(value);
    if (!entries.some(([name]) => containsUnsupportedExerciseNameControls(name))) return false;
    for (const key of Object.keys(value)) delete value[key];
    for (const [name, muscles] of entries) {
      const migratedName = migrateLegacyExerciseNameControls(name);
      if (!Object.hasOwn(value, migratedName)) {
        value[migratedName] = muscles;
        continue;
      }
      // The private-use replacement is one-to-one for legacy control code
      // points. This branch only handles a pre-existing replacement literal;
      // preserve all bounded muscle IDs instead of silently dropping either map.
      const previous = Array.isArray(value[migratedName]) ? value[migratedName] : [];
      const incoming = Array.isArray(muscles) ? muscles : [];
      value[migratedName] = [...new Set([...previous, ...incoming])].slice(0, LIMITS.mappingMuscles);
    }
    return true;
  }

  function migrateLegacyStoredExerciseNames(root) {
    if (!isRecord(root)) return false;
    let migrated = false;
    migrated = migrateExerciseArray(root.exercises) || migrated;
    migrated = migrateExerciseArray(root.exerciseCatalog) || migrated;
    if (Array.isArray(root.sessions)) {
      root.sessions.forEach(session => {
        if (!isRecord(session)) return;
        migrated = migrateExerciseArray(session.exerciseNames) || migrated;
        migrated = migrateExerciseArray(session.sets) || migrated;
        for (const field of ["exercises", "workoutExercises", "exerciseDetails", "items"]) {
          migrated = migrateExerciseArray(session[field], true) || migrated;
        }
      });
    }
    migrated = migrateMappingKeys(root.mappings) || migrated;
    if (isRecord(root.extensions) && isRecord(root.extensions.pwa)) {
      migrated = migrateMappingKeys(root.extensions.pwa.mappings) || migrated;
    }
    return migrated;
  }

  function normalizeLoadProfile(value, path) {
    const profile = assertObject(value, path);
    if (!['higherIsHarder', 'lowerIsHarder'].includes(profile.direction)) {
      fail(`${path}.direction is unsupported.`);
    }
    if (!Array.isArray(profile.allowedWeightsKg) ||
        profile.allowedWeightsKg.length < 1 ||
        profile.allowedWeightsKg.length > LIMITS.loadProfileWeights) {
      fail(`${path}.allowedWeightsKg must contain 1 to ${LIMITS.loadProfileWeights} values.`);
    }
    const allowedWeightsKg = profile.allowedWeightsKg.map((weight, weightIndex) =>
      canonicalFiniteNumber(
        finiteNumber(weight, `${path}.allowedWeightsKg[${weightIndex}]`, 0, LIMITS.weightMax)
      )
    );
    for (let index = 1; index < allowedWeightsKg.length; index += 1) {
      if (allowedWeightsKg[index] <= allowedWeightsKg[index - 1]) {
        fail(`${path}.allowedWeightsKg must be sorted with unique values.`);
      }
    }
    return { direction: profile.direction, allowedWeightsKg };
  }

  function normalizeCatalogItem(value, index, path) {
    const name = exerciseName(value, `${path}[${index}]`);
    const item = isRecord(value) ? value : {};
    const catalogKey = optionalCatalogKey(item.catalogKey ?? item.exerciseCatalogKey, `${path}[${index}].catalogKey`);
    const hasFavorite = Object.hasOwn(item, "favorite");
    const hasLegacyFavorite = Object.hasOwn(item, "isFavorite");
    if (hasFavorite && typeof item.favorite !== "boolean") {
      fail(`${path}[${index}].favorite must be a boolean.`);
    }
    if (hasLegacyFavorite && typeof item.isFavorite !== "boolean") {
      fail(`${path}[${index}].isFavorite must be a boolean.`);
    }
    if (hasFavorite && hasLegacyFavorite && item.favorite !== item.isFavorite) {
      fail(`${path}[${index}] has conflicting favorite values.`);
    }
    const favorite = hasFavorite ? item.favorite : item.isFavorite;
    const loadProfile = item.loadProfile == null
      ? null
      : normalizeLoadProfile(item.loadProfile, `${path}[${index}].loadProfile`);
    return {
      id: optionalId(item.id, index + 1, `${path}[${index}].id`),
      name,
      ...(catalogKey ? { catalogKey } : {}),
      ...(hasFavorite || hasLegacyFavorite ? { favorite } : {}),
      ...(loadProfile ? { loadProfile } : {})
    };
  }

  function normalizeSet(value, index, inheritedName, inheritedCatalogKey, path, idBase) {
    const item = assertObject(value, `${path}[${index}]`);
    const name = inheritedName || exerciseName(item, `${path}[${index}]`);
    const catalogKey = optionalCatalogKey(
      item.catalogKey ?? item.exerciseCatalogKey ?? inheritedCatalogKey,
      `${path}[${index}].catalogKey`
    );
    const weight = canonicalFiniteNumber(finiteNumber(
      item.weight ?? item.weightKg ?? item.kg,
      `${path}[${index}].weight`,
      0,
      LIMITS.weightMax
    ));
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
      const key = portableExerciseNameKey(normalized.exerciseName);
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
      const key = portableExerciseNameKey(name);
      if (!seenNames.has(key)) {
        seenNames.add(key);
        uniqueNames.push(name);
      }
    }
    if (uniqueNames.length > LIMITS.exercisesPerSession) {
      fail(`${path} exceeds ${LIMITS.exercisesPerSession} exercises.`, "too_many_exercises");
    }
    for (const name of uniqueNames) {
      counters.knownExerciseNames.add(portableExerciseNameKey(name));
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
    const durationSeconds = session.durationSeconds == null
      ? null
      : integer(
          session.durationSeconds,
          `${path}.durationSeconds`,
          0,
          LIMITS.workoutDurationSeconds
        );
    return {
      id: optionalId(session.id, counters.idBase + index, `${path}.id`),
      startedAt: timestamp(startedAtValue, `${path}.startedAt`),
      note,
      ...(durationSeconds === null ? {} : { durationSeconds }),
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
      split: enumValue("split", "Upper / Lower"),
      days,
      goal: enumValue("goal", "Aesthetic Cut"),
      calories: enumValue("calories", "Deficit")
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
        const name = boundedExerciseName(rawName, "state.mappings key");
        if (!Array.isArray(rawMuscles)) {
          if (trusted) continue;
          fail(`state.mappings.${name} must be an array.`);
        }
        if (rawMuscles.length > LIMITS.mappingMuscles) {
          fail(`state.mappings.${name} has too many muscle IDs.`);
        }
        merged[name] = [...new Set(rawMuscles.map((muscle, index) =>
          boundedString(muscle, `state.mappings.${name}[${index}]`, 64, { maxBytes: 256 })
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
    let pwaExtension = null;
    if (root.extensions != null) {
      const extensions = assertObject(root.extensions, "state.extensions");
      if (extensions.pwa != null) {
        pwaExtension = assertObject(extensions.pwa, "state.extensions.pwa");
        if (pwaExtension.version !== 1 || pwaExtension.language == null ||
            pwaExtension.mappings == null || pwaExtension.profile == null) {
          fail("state.extensions.pwa is incomplete or unsupported.");
        }
      }
    }
    const languageInput = root.language ?? pwaExtension?.language;
    if (languageInput != null && !["en", "uk", "ru"].includes(languageInput)) {
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
      normalizedExercises.map(exercise => portableExerciseNameKey(exercise.name))
    );
    const counters = { totalSets: 0, idBase: Date.now(), knownExerciseNames };
    const state = {
      language: ["uk", "ru"].includes(languageInput) ? languageInput : "en",
      catalogSeedVersion: root.catalogSeedVersion == null
        ? 0
        : integer(root.catalogSeedVersion, "state.catalogSeedVersion", 0, CATALOG_SEED_VERSION),
      exercises: normalizedExercises,
      sessions: sessionsInput.map((session, index) => normalizeSession(session, index, counters)),
      mappings: normalizeMappings(root.mappings ?? pwaExtension?.mappings, fallback.mappings),
      profile: safeProfile(root.profile ?? pwaExtension?.profile, fallback.profile)
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
      preflightJsonText(input);
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
    const migratedLegacyExerciseNameControls = options.migrateLegacyExerciseNameControls === true
      ? migrateLegacyStoredExerciseNames(root)
      : false;
    const normalized = normalizeRoot(root, options.fallback || {});
    return { ...normalized, migratedLegacyExerciseNameControls };
  }

  function normalizeState(input, options = {}) {
    return validateAndNormalize(input, options).state;
  }

  return Object.freeze({
    LIMITS,
    PROFILE_ENUMS,
    StateContractError,
    utf8ByteLength,
    unicodeCodePointLengthAtMost,
    containsUnsupportedExerciseNameControls,
    migrateLegacyExerciseNameControls,
    portableExerciseNameKey,
    validateAndNormalize,
    normalizeState
  });
});
