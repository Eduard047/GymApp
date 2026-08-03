(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.GymSharedWorkout = api;
})(typeof globalThis !== "undefined" ? globalThis : window, function buildSharedWorkoutCodec() {
  "use strict";

  const VERSION = 1;
  const HASH_KEY = "workout";
  const LIMITS = Object.freeze({
    encodedLength: 12_000,
    decodedBytes: 9_000,
    exercises: 20,
    setsPerExercise: 12,
    totalSets: 120,
    exerciseNameCharacters: 120,
    exerciseNameBytes: 480,
    catalogKeyCharacters: 64,
    weightMax: 1_000_000,
    repsMax: 10_000
  });
  const CATALOG_KEY_PATTERN = /^[a-z0-9_]{1,64}$/;

  function fail(message) {
    throw new TypeError(message);
  }

  function utf8Bytes(value) {
    return new TextEncoder().encode(value);
  }

  function boundedName(value) {
    if (typeof value !== "string") fail("Exercise name must be a string.");
    const name = value.trim();
    if (!name || [...name].length > LIMITS.exerciseNameCharacters ||
        utf8Bytes(name).length > LIMITS.exerciseNameBytes || /[\u0000-\u001f\u007f]/u.test(name)) {
      fail("Exercise name is outside the supported bounds.");
    }
    return name;
  }

  function boundedCatalogKey(value) {
    if (value == null || value === "") return "";
    if (typeof value !== "string" || value.length > LIMITS.catalogKeyCharacters ||
        !CATALOG_KEY_PATTERN.test(value)) {
      fail("Exercise catalog key is invalid.");
    }
    return value;
  }

  function boundedSet(value) {
    const weight = Array.isArray(value) ? value[0] : value?.weight;
    const reps = Array.isArray(value) ? value[1] : value?.reps;
    if (typeof weight !== "number" || !Number.isFinite(weight) || weight < 0 || weight > LIMITS.weightMax) {
      fail("Set weight is invalid.");
    }
    if (!Number.isInteger(reps) || reps < 1 || reps > LIMITS.repsMax) {
      fail("Set repetitions are invalid.");
    }
    return Object.freeze({ weight, reps });
  }

  function normalize(input) {
    const rawExercises = input?.exercises;
    if (!Array.isArray(rawExercises) || !rawExercises.length || rawExercises.length > LIMITS.exercises) {
      fail("Shared workout exercise count is invalid.");
    }
    let totalSets = 0;
    const exercises = rawExercises.map(rawExercise => {
      const compact = Array.isArray(rawExercise);
      const catalogKey = boundedCatalogKey(compact ? rawExercise[0] : rawExercise?.catalogKey);
      const name = boundedName(compact ? rawExercise[1] : rawExercise?.name);
      const rawSets = compact ? rawExercise[2] : rawExercise?.sets;
      if (!Array.isArray(rawSets) || !rawSets.length || rawSets.length > LIMITS.setsPerExercise) {
        fail("Shared workout set count is invalid.");
      }
      totalSets += rawSets.length;
      if (totalSets > LIMITS.totalSets) fail("Shared workout contains too many sets.");
      return Object.freeze({
        ...(catalogKey ? { catalogKey } : {}),
        name,
        sets: Object.freeze(rawSets.map(boundedSet))
      });
    });
    return Object.freeze({ version: VERSION, exercises: Object.freeze(exercises) });
  }

  function compact(plan) {
    return {
      v: VERSION,
      e: plan.exercises.map(exercise => [
        exercise.catalogKey || "",
        exercise.name,
        exercise.sets.map(set => [set.weight, set.reps])
      ])
    };
  }

  function bytesToBase64(bytes) {
    let binary = "";
    for (let index = 0; index < bytes.length; index += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
    }
    if (typeof btoa === "function") return btoa(binary);
    if (typeof Buffer !== "undefined") return Buffer.from(bytes).toString("base64");
    fail("Base64 encoding is unavailable.");
  }

  function base64ToBytes(value) {
    if (!/^[A-Za-z0-9_-]+$/.test(value)) fail("Shared workout encoding is invalid.");
    const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
    let binary;
    try {
      binary = typeof atob === "function"
        ? atob(padded)
        : typeof Buffer !== "undefined"
          ? Buffer.from(padded, "base64").toString("binary")
          : fail("Base64 decoding is unavailable.");
    } catch {
      fail("Shared workout encoding is invalid.");
    }
    const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
    if (bytes.length > LIMITS.decodedBytes) fail("Shared workout is too large.");
    return bytes;
  }

  function encode(input) {
    const plan = normalize(input);
    const bytes = utf8Bytes(JSON.stringify(compact(plan)));
    if (bytes.length > LIMITS.decodedBytes) fail("Shared workout is too large.");
    const encoded = bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
    if (encoded.length > LIMITS.encodedLength) fail("Shared workout is too large.");
    return encoded;
  }

  function decode(encoded) {
    if (typeof encoded !== "string" || !encoded.length || encoded.length > LIMITS.encodedLength) {
      fail("Shared workout encoding is invalid.");
    }
    let parsed;
    try {
      parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(base64ToBytes(encoded)));
    } catch (error) {
      if (error instanceof TypeError && error.message.startsWith("Shared workout")) throw error;
      fail("Shared workout JSON is invalid.");
    }
    if (!parsed || parsed.v !== VERSION || !Array.isArray(parsed.e)) {
      fail("Shared workout version is unsupported.");
    }
    return normalize({ exercises: parsed.e });
  }

  function fromHash(hash) {
    const params = new URLSearchParams(String(hash || "").replace(/^#/, ""));
    const values = params.getAll(HASH_KEY);
    if (values.length !== 1) return null;
    return decode(values[0]);
  }

  function removeFromHash(hash) {
    const params = new URLSearchParams(String(hash || "").replace(/^#/, ""));
    params.delete(HASH_KEY);
    const rest = params.toString();
    return rest ? `#${rest}` : "";
  }

  function buildUrl(baseUrl, input) {
    const url = new URL(baseUrl);
    url.search = "";
    url.hash = `${HASH_KEY}=${encode(input)}`;
    return url.href;
  }

  return Object.freeze({ VERSION, HASH_KEY, LIMITS, normalize, encode, decode, fromHash, removeFromHash, buildUrl });
});
