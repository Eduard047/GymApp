(function (root, factory) {
  "use strict";

  const api = factory(root);
  root.GymBrowserRetirement = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;

  if (root.document) {
    const start = () => api.mount(root.document);
    if (root.document.readyState === "loading") {
      root.document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
      start();
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : window, function buildBrowserRetirement(root) {
  "use strict";

  const CACHE_PREFIX = "gym-pwa-";
  const PUSH_BINDING_DB_NAME = "gymapp-push-binding-v1";
  const PUSH_CLEANUP_TIMEOUT_MS = 1_500;
  const RETIREMENT_RELOAD_KEY = "gymapp-retirement-reload-v1";
  const STATE_KEY = "gym-pwa-state-v2";
  const LEGACY_STATE_KEY = "gym-pwa-state-v1";
  const ACCOUNT_STATE_PREFIX = "gym-pwa-account:";
  const ACTIVE_WORKOUT_PREFIX = "gym-pwa-active-workout-v1:";
  const FORBIDDEN_OBJECT_KEYS = new Set(["__proto__", "prototype", "constructor"]);
  const PROFILE_ENUMS = Object.freeze({
    split: Object.freeze(["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"]),
    goal: Object.freeze(["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"]),
    calories: Object.freeze(["Deficit", "Maintenance", "Surplus"])
  });
  const LIMITS = Object.freeze({
    storageKeys: 256,
    keyLength: 256,
    candidateBytes: 32 * 1024 * 1024,
    recordBytes: 8 * 1024 * 1024,
    maxDepth: 8,
    maxNodes: 250000,
    maxStringBytes: 64 * 1024,
    profiles: 24,
    exercises: 2000,
    sessions: 5000,
    exercisesPerSession: 100,
    setsPerExercise: 100,
    totalSets: 100000,
    mappingEntries: 2000,
    mappingMuscles: 32,
    exerciseNameLength: 160,
    exerciseNameBytes: 640,
    noteLength: 4000,
    noteBytes: 16000,
    loadProfileWeights: 128,
    weightMax: 1000000,
    repsMax: 10000,
    timestampMin: -62135769600000,
    timestampMax: 64092211200000
  });

  const COPY = Object.freeze({
    en: Object.freeze({
      title: "Train in GymApp",
      lead: "GymApp workouts are available in the mobile apps. Your existing browser data stays on this device.",
      downloadsTitle: "Get GymApp",
      availableOn: "Available on",
      legacyTitle: "Legacy browser data",
      legacyCopy: "Download a private backup before removing this site's data. Sign-in credentials and custom images are not included.",
      exportAction: "Download backup",
      exportSuccess: "Backup downloaded.",
      exportError: "The backup could not be created. Your data was not changed.",
      privacy: "Privacy",
      support: "Support",
      deletion: "Account & data deletion",
      footer: "Official downloads and help"
    }),
    uk: Object.freeze({
      title: "Тренуйся у GymApp",
      lead: "Тренування GymApp доступні в мобільних застосунках. Наявні дані браузера залишаються на цьому пристрої.",
      downloadsTitle: "Завантажити GymApp",
      availableOn: "Доступно в",
      legacyTitle: "Дані браузера",
      legacyCopy: "Завантаж приватну резервну копію перед видаленням даних сайту. Дані входу й власні зображення не додаються.",
      exportAction: "Завантажити копію",
      exportSuccess: "Резервну копію завантажено.",
      exportError: "Не вдалося створити копію. Твої дані не змінено.",
      privacy: "Конфіденційність",
      support: "Підтримка",
      deletion: "Видалення акаунта й даних",
      footer: "Офіційні завантаження та допомога"
    }),
    ru: Object.freeze({
      title: "Тренируйтесь в GymApp",
      lead: "Тренировки GymApp доступны в мобильных приложениях. Данные браузера остаются на этом устройстве.",
      downloadsTitle: "Скачать GymApp",
      availableOn: "Доступно в",
      legacyTitle: "Данные браузера",
      legacyCopy: "Скачайте личную резервную копию перед удалением данных сайта. Данные входа и свои изображения не включаются.",
      exportAction: "Скачать копию",
      exportSuccess: "Резервная копия скачана.",
      exportError: "Не удалось создать копию. Ваши данные не изменены.",
      privacy: "Конфиденциальность",
      support: "Поддержка",
      deletion: "Удаление аккаунта и данных",
      footer: "Официальные загрузки и помощь"
    })
  });

  class LegacyExportError extends Error {
    constructor(message) {
      super(message);
      this.name = "LegacyExportError";
    }
  }

  function fail(message) {
    throw new LegacyExportError(message);
  }

  function utf8Bytes(value) {
    return new TextEncoder().encode(String(value)).byteLength;
  }

  function isRecord(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function assertJsonBudget(value) {
    const stack = [{ value, depth: 0 }];
    let nodes = 0;
    while (stack.length) {
      const current = stack.pop();
      nodes += 1;
      if (nodes > LIMITS.maxNodes || current.depth > LIMITS.maxDepth) {
        fail("Legacy data is too complex.");
      }
      if (typeof current.value === "string" && utf8Bytes(current.value) > LIMITS.maxStringBytes) {
        fail("Legacy data contains an oversized string.");
      }
      if (current.value === null || typeof current.value !== "object") continue;
      if (Array.isArray(current.value)) {
        for (let index = current.value.length - 1; index >= 0; index -= 1) {
          stack.push({ value: current.value[index], depth: current.depth + 1 });
        }
        continue;
      }
      for (const [key, child] of Object.entries(current.value)) {
        if (FORBIDDEN_OBJECT_KEYS.has(key) || key.length > LIMITS.keyLength) {
          fail("Legacy data contains an unsupported object key.");
        }
        stack.push({ value: child, depth: current.depth + 1 });
      }
    }
  }

  function parseBoundedJson(raw) {
    if (typeof raw !== "string" || utf8Bytes(raw) > LIMITS.recordBytes) {
      fail("Legacy data record is oversized.");
    }
    let value;
    try {
      value = JSON.parse(raw);
    } catch {
      fail("Legacy data is not valid JSON.");
    }
    assertJsonBudget(value);
    return value;
  }

  function boundedString(value, maxLength, maxBytes, { empty = false, trim = false } = {}) {
    if (typeof value !== "string") fail("Legacy data contains an invalid string.");
    const result = trim ? value.trim() : value;
    if ((!empty && !result) || result.length > maxLength || utf8Bytes(result) > maxBytes) {
      fail("Legacy data string is outside the supported limit.");
    }
    return result;
  }

  function exerciseName(value) {
    const result = boundedString(value, LIMITS.exerciseNameLength, LIMITS.exerciseNameBytes, { trim: true });
    if (/[\u0000-\u001f\u007f-\u009f]/u.test(result)) {
      fail("Legacy exercise name contains unsupported controls.");
    }
    return result;
  }

  function optionalCatalogKey(value) {
    if (value == null || value === "") return null;
    const result = boundedString(value, 80, 320, { trim: true });
    if (!/^[a-z0-9_-]+$/i.test(result)) fail("Legacy catalog key is invalid.");
    return result;
  }

  function positiveId(value, fallback) {
    if (value == null || value === "") return fallback;
    const parsed = typeof value === "string" && /^\d{1,15}$/.test(value) ? Number(value) : value;
    if (!Number.isSafeInteger(parsed) || parsed <= 0) fail("Legacy ID is invalid.");
    return parsed;
  }

  function finiteNumber(value, minimum, maximum) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
      fail("Legacy number is invalid.");
    }
    return Object.is(value, -0) ? 0 : value;
  }

  function integer(value, minimum, maximum) {
    if (!Number.isInteger(value) || value < minimum || value > maximum) {
      fail("Legacy integer is invalid.");
    }
    return value;
  }

  function timestamp(value) {
    return integer(value, LIMITS.timestampMin, LIMITS.timestampMax);
  }

  function sanitizeLoadProfile(value) {
    if (!isRecord(value) || !["higherIsHarder", "lowerIsHarder"].includes(value.direction) ||
        !Array.isArray(value.allowedWeightsKg) || value.allowedWeightsKg.length < 1 ||
        value.allowedWeightsKg.length > LIMITS.loadProfileWeights) {
      fail("Legacy load profile is invalid.");
    }
    const allowedWeightsKg = value.allowedWeightsKg.map(weight => finiteNumber(weight, 0, LIMITS.weightMax));
    for (let index = 1; index < allowedWeightsKg.length; index += 1) {
      if (allowedWeightsKg[index] <= allowedWeightsKg[index - 1]) {
        fail("Legacy load profile is not ordered.");
      }
    }
    return { direction: value.direction, allowedWeightsKg };
  }

  function sanitizeExercise(value, index) {
    const item = typeof value === "string" ? { name: value } : value;
    if (!isRecord(item)) fail("Legacy exercise is invalid.");
    const name = exerciseName(item.name ?? item.exerciseName ?? item.title);
    const result = { id: positiveId(item.id, index + 1), name };
    const catalogKey = optionalCatalogKey(item.catalogKey ?? item.exerciseCatalogKey);
    if (catalogKey) result.catalogKey = catalogKey;
    if (Object.hasOwn(item, "favorite") || Object.hasOwn(item, "isFavorite")) {
      const favorite = Object.hasOwn(item, "favorite") ? item.favorite : item.isFavorite;
      if (typeof favorite !== "boolean") fail("Legacy favorite state is invalid.");
      result.favorite = favorite;
    }
    if (item.loadProfile != null) result.loadProfile = sanitizeLoadProfile(item.loadProfile);
    return result;
  }

  function sanitizeSet(value, index, inheritedName = "") {
    if (!isRecord(value)) fail("Legacy set is invalid.");
    const name = inheritedName || exerciseName(value.exerciseName ?? value.name ?? value.title);
    const result = {
      id: positiveId(value.id, index + 1),
      exerciseName: name,
      weight: finiteNumber(value.weight ?? value.weightKg ?? value.kg, 0, LIMITS.weightMax),
      reps: integer(value.reps ?? value.repeatCount ?? value.count, 1, LIMITS.repsMax),
      orderIndex: value.orderIndex == null && value.index == null
        ? index
        : integer(value.orderIndex ?? value.index, 0, 9999)
    };
    const catalogKey = optionalCatalogKey(value.catalogKey ?? value.exerciseCatalogKey);
    if (catalogKey) result.catalogKey = catalogKey;
    return result;
  }

  function sanitizeSession(value, index, counters) {
    if (!isRecord(value)) fail("Legacy session is invalid.");
    const explicitNames = value.exerciseNames == null ? [] : value.exerciseNames;
    if (!Array.isArray(explicitNames) || explicitNames.length > LIMITS.exercisesPerSession) {
      fail("Legacy session exercise list is invalid.");
    }
    const names = explicitNames.map(exerciseName);
    let sets = [];
    if (value.sets != null) {
      if (!Array.isArray(value.sets) || value.sets.length > LIMITS.exercisesPerSession * LIMITS.setsPerExercise) {
        fail("Legacy session set list is invalid.");
      }
      sets = value.sets.map((set, setIndex) => sanitizeSet(set, setIndex));
    } else if (Array.isArray(value.exercises)) {
      if (value.exercises.length > LIMITS.exercisesPerSession) fail("Legacy session exercise list is too large.");
      value.exercises.forEach((exercise, exerciseIndex) => {
        if (!isRecord(exercise) || !Array.isArray(exercise.sets) ||
            exercise.sets.length > LIMITS.setsPerExercise) {
          fail("Legacy nested exercise is invalid.");
        }
        const name = exerciseName(exercise.name ?? exercise.exerciseName ?? exercise.title);
        names.push(name);
        exercise.sets.forEach((set, setIndex) => {
          sets.push(sanitizeSet(set, exerciseIndex * LIMITS.setsPerExercise + setIndex, name));
        });
      });
    }
    counters.totalSets += sets.length;
    if (counters.totalSets > LIMITS.totalSets) fail("Legacy data contains too many sets.");
    const seen = new Set();
    const exerciseNames = [];
    for (const name of [...names, ...sets.map(set => set.exerciseName)]) {
      const key = name.normalize("NFC").toLocaleLowerCase("en-US");
      if (seen.has(key)) continue;
      seen.add(key);
      exerciseNames.push(name);
    }
    if (exerciseNames.length > LIMITS.exercisesPerSession) fail("Legacy session contains too many exercises.");
    return {
      id: positiveId(value.id, index + 1),
      startedAt: timestamp(value.startedAt ?? value.date),
      note: value.note == null
        ? ""
        : boundedString(value.note, LIMITS.noteLength, LIMITS.noteBytes, { empty: true }),
      exerciseNames,
      sets
    };
  }

  function sanitizeMappings(value) {
    if (value == null) return Object.create(null);
    if (!isRecord(value)) fail("Legacy mappings are invalid.");
    const entries = Object.entries(value);
    if (entries.length > LIMITS.mappingEntries) fail("Legacy mappings are too large.");
    const result = Object.create(null);
    for (const [rawName, rawMuscles] of entries) {
      const name = exerciseName(rawName);
      if (!Array.isArray(rawMuscles) || rawMuscles.length > LIMITS.mappingMuscles) {
        fail("Legacy muscle mapping is invalid.");
      }
      result[name] = [...new Set(rawMuscles.map(muscle =>
        boundedString(muscle, 64, 256, { trim: true })
      ))];
    }
    return result;
  }

  function sanitizeProfile(value) {
    const source = value == null ? {} : value;
    if (!isRecord(source)) fail("Legacy profile is invalid.");
    const split = PROFILE_ENUMS.split.includes(source.split) ? source.split : "Upper / Lower";
    const goal = PROFILE_ENUMS.goal.includes(source.goal) ? source.goal : "Aesthetic Cut";
    const calories = PROFILE_ENUMS.calories.includes(source.calories) ? source.calories : "Deficit";
    const days = source.days == null ? 4 : integer(source.days, 2, 6);
    return { split, days, goal, calories };
  }

  function sanitizeState(value) {
    if (!isRecord(value)) fail("Legacy profile state is invalid.");
    const exercises = value.exercises ?? value.exerciseCatalog ?? [];
    const sessions = value.sessions ?? [];
    if (!Array.isArray(exercises) || exercises.length > LIMITS.exercises ||
        !Array.isArray(sessions) || sessions.length > LIMITS.sessions) {
      fail("Legacy profile exceeds the export limits.");
    }
    const language = ["en", "uk", "ru"].includes(value.language) ? value.language : "en";
    const catalogSeedVersion = value.catalogSeedVersion == null
      ? 0
      : integer(value.catalogSeedVersion, 0, 3);
    const counters = { totalSets: 0 };
    const state = {
      schemaVersion: 2,
      language,
      catalogSeedVersion,
      exercises: exercises.map(sanitizeExercise),
      sessions: sessions.map((session, index) => sanitizeSession(session, index, counters)),
      mappings: sanitizeMappings(value.mappings ?? value.extensions?.pwa?.mappings),
      profile: sanitizeProfile(value.profile ?? value.extensions?.pwa?.profile)
    };
    if (value.progressExerciseId != null) {
      state.progressExerciseId = positiveId(value.progressExerciseId, 1);
    }
    return state;
  }

  function sanitizeActiveSet(value) {
    if (!isRecord(value)) fail("Legacy active set is invalid.");
    const completed = value.completed;
    if (typeof completed !== "boolean") fail("Legacy active set completion is invalid.");
    const completedAt = completed ? timestamp(value.completedAt) : null;
    if (!completed && value.completedAt !== null) fail("Legacy active set timestamp is invalid.");
    return {
      id: positiveId(value.id, 1),
      weight: finiteNumber(value.weight, 0, LIMITS.weightMax),
      reps: integer(value.reps, 1, LIMITS.repsMax),
      completed,
      completedAt
    };
  }

  function sanitizeActiveWorkout(value) {
    if (!isRecord(value) || value.version !== 1 || !Array.isArray(value.blocks) ||
        value.blocks.length < 1 || value.blocks.length > LIMITS.exercisesPerSession) {
      fail("Legacy active workout is invalid.");
    }
    const startedAt = timestamp(value.startedAt);
    const createdAt = timestamp(value.createdAt);
    const updatedAt = timestamp(value.updatedAt);
    if (startedAt > createdAt || updatedAt < createdAt) fail("Legacy active workout timestamps are invalid.");
    const note = boundedString(value.note, 2000, 8000, { empty: true });
    let totalSets = 0;
    const blocks = value.blocks.map((block, blockIndex) => {
      if (!isRecord(block) || !Array.isArray(block.sets) || block.sets.length < 1 ||
          block.sets.length > LIMITS.setsPerExercise) {
        fail("Legacy active workout block is invalid.");
      }
      totalSets += block.sets.length;
      if (totalSets > LIMITS.exercisesPerSession * LIMITS.setsPerExercise) {
        fail("Legacy active workout is too large.");
      }
      const result = {
        id: positiveId(block.id, blockIndex + 1),
        exerciseName: exerciseName(block.exerciseName),
        sets: block.sets.map(sanitizeActiveSet)
      };
      const catalogKey = optionalCatalogKey(block.catalogKey);
      if (catalogKey) result.catalogKey = catalogKey;
      return result;
    });
    return {
      version: 1,
      id: positiveId(value.id, 1),
      startedAt,
      createdAt,
      updatedAt,
      revision: integer(value.revision, 1, Number.MAX_SAFE_INTEGER),
      note,
      blocks
    };
  }

  function candidateDescriptor(key) {
    if (key === STATE_KEY) return { type: "state", association: "guest" };
    if (key === LEGACY_STATE_KEY) return { type: "state", association: "legacy" };
    if (key.startsWith(ACCOUNT_STATE_PREFIX)) {
      const suffix = key.slice(ACCOUNT_STATE_PREFIX.length);
      if (/^[a-z0-9:_-]{1,96}$/i.test(suffix)) return { type: "state", association: suffix };
    }
    if (key.startsWith(ACTIVE_WORKOUT_PREFIX)) {
      const suffix = key.slice(ACTIVE_WORKOUT_PREFIX.length);
      if (/^[a-z0-9:_-]{1,96}$/i.test(suffix)) return { type: "active", association: suffix };
    }
    return null;
  }

  function collectLegacyData(storage) {
    if (!storage || typeof storage.length !== "number" || typeof storage.key !== "function" ||
        typeof storage.getItem !== "function") {
      return Object.freeze({ available: false, profiles: Object.freeze([]), unassignedActiveWorkouts: Object.freeze([]) });
    }
    if (!Number.isInteger(storage.length) || storage.length < 0 || storage.length > LIMITS.storageKeys) {
      fail("Browser storage contains too many keys to inspect safely.");
    }
    const states = [];
    const activeByAssociation = new Map();
    let candidateBytes = 0;
    for (let index = 0; index < storage.length; index += 1) {
      const key = storage.key(index);
      if (typeof key !== "string" || key.length > LIMITS.keyLength) fail("Browser storage key is invalid.");
      const descriptor = candidateDescriptor(key);
      if (!descriptor) continue;
      const raw = storage.getItem(key);
      if (raw == null) continue;
      const bytes = utf8Bytes(raw);
      candidateBytes += bytes;
      if (bytes > LIMITS.recordBytes || candidateBytes > LIMITS.candidateBytes) {
        fail("Legacy browser data is too large to export safely.");
      }
      const parsed = parseBoundedJson(raw);
      if (descriptor.type === "state") {
        states.push({ association: descriptor.association, state: sanitizeState(parsed) });
      } else {
        activeByAssociation.set(descriptor.association, sanitizeActiveWorkout(parsed));
      }
    }
    if (states.length > LIMITS.profiles || activeByAssociation.size > LIMITS.profiles) {
      fail("Legacy browser data contains too many profiles.");
    }
    const uniqueStates = new Set();
    const profiles = [];
    for (const item of states) {
      const signature = JSON.stringify(item.state);
      if (uniqueStates.has(signature)) continue;
      uniqueStates.add(signature);
      const activeWorkout = activeByAssociation.get(item.association) || null;
      if (activeWorkout) activeByAssociation.delete(item.association);
      profiles.push(Object.freeze({
        label: `Profile ${profiles.length + 1}`,
        state: item.state,
        ...(activeWorkout ? { activeWorkout } : {})
      }));
    }
    const unassignedActiveWorkouts = [...activeByAssociation.values()];
    return Object.freeze({
      available: profiles.length > 0 || unassignedActiveWorkouts.length > 0,
      profiles: Object.freeze(profiles),
      unassignedActiveWorkouts: Object.freeze(unassignedActiveWorkouts)
    });
  }

  function buildExport(snapshot, now = new Date()) {
    if (!snapshot?.available || !Array.isArray(snapshot.profiles) ||
        !Array.isArray(snapshot.unassignedActiveWorkouts) || !(now instanceof Date) ||
        !Number.isFinite(now.getTime())) {
      fail("Legacy export snapshot is unavailable.");
    }
    return {
      schemaVersion: 1,
      app: "GymApp",
      source: "browser-retirement-export",
      exportedAt: now.toISOString(),
      credentialsIncluded: false,
      profiles: snapshot.profiles,
      unassignedActiveWorkouts: snapshot.unassignedActiveWorkouts
    };
  }

  function languageFor(navigatorLike) {
    const languages = Array.isArray(navigatorLike?.languages)
      ? navigatorLike.languages
      : [navigatorLike?.language];
    for (const candidate of languages) {
      const language = String(candidate || "").toLowerCase();
      if (language.startsWith("uk")) return "uk";
      if (language.startsWith("ru")) return "ru";
      if (language.startsWith("en")) return "en";
    }
    return "en";
  }

  function applyLanguage(document, language) {
    const selected = Object.hasOwn(COPY, language) ? language : "en";
    const copy = COPY[selected];
    document.documentElement.lang = selected;
    document.title = copy.title;
    document.querySelectorAll("[data-copy]").forEach(node => {
      const key = node.getAttribute("data-copy");
      if (Object.hasOwn(copy, key)) node.textContent = copy[key];
    });
    document.querySelectorAll("[data-language]").forEach(button => {
      button.setAttribute("aria-pressed", String(button.getAttribute("data-language") === selected));
    });
    return selected;
  }

  async function deleteKnownStaticCaches(cacheStorage) {
    if (!cacheStorage || typeof cacheStorage.keys !== "function" || typeof cacheStorage.delete !== "function") {
      return Object.freeze([]);
    }
    const names = await cacheStorage.keys();
    const known = names.filter(name => typeof name === "string" && name.startsWith(CACHE_PREFIX));
    const results = await Promise.allSettled(known.map(name => cacheStorage.delete(name)));
    return Object.freeze(known.filter((_, index) =>
      results[index].status === "fulfilled" && results[index].value === true
    ));
  }

  function deleteKnownPushBindingDatabase(indexedDbLike, {
    schedule = root.setTimeout,
    cancel = root.clearTimeout
  } = {}) {
    if (!indexedDbLike || typeof indexedDbLike.deleteDatabase !== "function") {
      return Promise.resolve(false);
    }
    return new Promise(resolve => {
      let settled = false;
      let timer = null;
      const finish = result => {
        if (settled) return;
        settled = true;
        if (timer !== null && typeof cancel === "function") cancel(timer);
        resolve(result);
      };
      if (typeof schedule === "function") {
        timer = schedule(() => finish(false), PUSH_CLEANUP_TIMEOUT_MS);
      }
      try {
        const request = indexedDbLike.deleteDatabase(PUSH_BINDING_DB_NAME);
        if (!request || typeof request !== "object") {
          finish(false);
          return;
        }
        request.onsuccess = () => finish(true);
        request.onerror = () => finish(false);
        request.onblocked = () => finish(false);
      } catch {
        finish(false);
      }
    });
  }

  function boundedPushStep(operation, timeoutMilliseconds) {
    return new Promise(resolve => {
      let settled = false;
      const finish = value => {
        if (settled) return;
        settled = true;
        root.clearTimeout(timer);
        resolve(value);
      };
      const timer = root.setTimeout(() => finish(false), timeoutMilliseconds);
      Promise.resolve()
        .then(operation)
        .then(value => finish(value), () => finish(false));
    });
  }

  async function retireExactScopeRegistration(registration) {
    const stepTimeout = Math.floor(PUSH_CLEANUP_TIMEOUT_MS / 2);
    await boundedPushStep(async () => {
      const subscription = await registration?.pushManager?.getSubscription?.();
      if (subscription && typeof subscription.unsubscribe === "function") {
        await subscription.unsubscribe();
      }
      return true;
    }, stepTimeout);
    // Unregistering the exact service-worker scope still deactivates its push
    // subscription. Never let a push-service failure keep the retired shell alive.
    return await boundedPushStep(
      () => registration.unregister(),
      PUSH_CLEANUP_TIMEOUT_MS - stepTimeout
    ) === true;
  }

  function shouldReloadAfterRetirement(sessionStorage, didRetire) {
    if (!didRetire || !sessionStorage || typeof sessionStorage.getItem !== "function" ||
        typeof sessionStorage.setItem !== "function") return false;
    try {
      const marker = sessionStorage.getItem(RETIREMENT_RELOAD_KEY);
      if (marker === "done") return false;
      if (marker === "reload") {
        sessionStorage.setItem(RETIREMENT_RELOAD_KEY, "done");
        return false;
      }
      sessionStorage.setItem(RETIREMENT_RELOAD_KEY, "reload");
      return true;
    } catch {
      return false;
    }
  }

  async function retireLegacyWorker(
    navigatorLike,
    locationLike,
    sessionStorage,
    cacheStorage,
    indexedDbLike = root.indexedDB
  ) {
    await deleteKnownStaticCaches(cacheStorage).catch(() => []);
    const pushBindingCleanup = deleteKnownPushBindingDatabase(indexedDbLike).catch(() => false);
    const serviceWorker = navigatorLike?.serviceWorker;
    if (!serviceWorker || typeof serviceWorker.getRegistrations !== "function") {
      await pushBindingCleanup;
      return false;
    }
    let scope;
    try {
      scope = new URL("./", locationLike.href).href;
    } catch {
      await pushBindingCleanup;
      return false;
    }
    const expectedWorker = new URL("sw.js", scope).href;
    let registrations;
    try {
      registrations = await serviceWorker.getRegistrations();
    } catch {
      await pushBindingCleanup;
      return false;
    }
    const matching = registrations.filter(registration => registration?.scope === scope);
    const controlledByGymApp = (() => {
      try {
        return serviceWorker.controller?.scriptURL === expectedWorker;
      } catch {
        return false;
      }
    })();
    const results = await Promise.allSettled(matching.map(retireExactScopeRegistration));
    await pushBindingCleanup;
    const didRetire = controlledByGymApp || matching.length > 0 ||
      results.some(result => result.status === "fulfilled" && result.value === true);
    if (shouldReloadAfterRetirement(sessionStorage, didRetire) &&
        typeof locationLike.reload === "function") {
      locationLike.reload();
      return true;
    }
    return false;
  }

  function downloadExport(document, snapshot, {
    urlApi = root.URL,
    schedule = root.setTimeout
  } = {}) {
    const payload = JSON.stringify(buildExport(snapshot), null, 2);
    if (utf8Bytes(payload) > LIMITS.candidateBytes) fail("Legacy export is too large.");
    const blob = new Blob([payload], { type: "application/json" });
    if (!urlApi || typeof urlApi.createObjectURL !== "function" ||
        typeof urlApi.revokeObjectURL !== "function") {
      fail("Legacy export download is unavailable.");
    }
    const url = urlApi.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `gymapp-browser-backup-${new Date().toISOString().slice(0, 10)}.json`;
    link.hidden = true;
    document.body.append(link);
    link.click();
    link.remove();
    const revoke = () => urlApi.revokeObjectURL(url);
    if (typeof schedule === "function") schedule(revoke, 1000);
    else revoke();
  }

  function mount(document) {
    let language = applyLanguage(document, languageFor(root.navigator));
    document.querySelectorAll("[data-language]").forEach(button => {
      button.addEventListener("click", () => {
        language = applyLanguage(document, button.getAttribute("data-language"));
      });
    });

    const panel = document.getElementById("legacy-export");
    const action = document.getElementById("export-legacy");
    const status = document.getElementById("export-status");
    let snapshot = null;
    try {
      snapshot = collectLegacyData(root.localStorage);
      if (snapshot.available) panel?.removeAttribute("hidden");
    } catch {
      snapshot = null;
    }
    action?.addEventListener("click", () => {
      if (!snapshot?.available) return;
      action.disabled = true;
      try {
        snapshot = collectLegacyData(root.localStorage);
        downloadExport(document, snapshot);
        if (status) status.textContent = COPY[language].exportSuccess;
      } catch {
        if (status) status.textContent = COPY[language].exportError;
      } finally {
        action.disabled = false;
      }
    });

    void retireLegacyWorker(
      root.navigator,
      root.location,
      root.sessionStorage,
      root.caches,
      root.indexedDB
    );
  }

  return Object.freeze({
    CACHE_PREFIX,
    PUSH_BINDING_DB_NAME,
    PUSH_CLEANUP_TIMEOUT_MS,
    RETIREMENT_RELOAD_KEY,
    LIMITS,
    COPY,
    LegacyExportError,
    languageFor,
    applyLanguage,
    collectLegacyData,
    buildExport,
    deleteKnownStaticCaches,
    deleteKnownPushBindingDatabase,
    shouldReloadAfterRetirement,
    retireLegacyWorker,
    downloadExport,
    mount
  });
});
