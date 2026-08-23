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
  const JSON_MAX_DEPTH = 8;
  let builtInIdentityResolver = null;

  function fail(message) {
    throw new TypeError(message);
  }

  function utf8Bytes(value) {
    return new TextEncoder().encode(value);
  }

  function portableNameKey(value) {
    return String(value ?? "")
      .normalize("NFC")
      .replace(/[\u02bc\u2019]/g, "'")
      .replace(/[\p{White_Space}\u001c-\u001f]+/gu, " ")
      .trim()
      .toLowerCase()
      .replace(/ё/g, "е");
  }

  function configureBuiltInIdentityResolver(resolver) {
    if (typeof resolver !== "function" ||
        (builtInIdentityResolver !== null && builtInIdentityResolver !== resolver)) {
      fail("Shared workout identity resolver is invalid.");
    }
    builtInIdentityResolver = resolver;
  }

  function builtInIdentityForName(name) {
    if (!builtInIdentityResolver) return "";
    const value = builtInIdentityResolver(name);
    if (value == null || value === "") return "";
    return boundedCatalogKey(value);
  }

  function boundedName(value) {
    if (typeof value !== "string") fail("Exercise name must be a string.");
    const name = value.trim();
    if (!name || [...name].length > LIMITS.exerciseNameCharacters ||
        utf8Bytes(name).length > LIMITS.exerciseNameBytes ||
        /[\p{Cc}\p{Cf}\u2028\u2029]/u.test(name)) {
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
    const normalizedNames = new Set();
    const catalogIdentities = new Set();
    const exercises = rawExercises.map(rawExercise => {
      const compact = Array.isArray(rawExercise);
      const catalogKey = boundedCatalogKey(compact ? rawExercise[0] : rawExercise?.catalogKey);
      const name = boundedName(compact ? rawExercise[1] : rawExercise?.name);
      const normalizedName = portableNameKey(name);
      const builtInIdentity = builtInIdentityForName(name);
      const catalogIdentity = builtInIdentity || catalogKey;
      if (normalizedNames.has(normalizedName) ||
          (catalogIdentity && catalogIdentities.has(catalogIdentity))) {
        fail("Shared workout contains duplicate exercises.");
      }
      normalizedNames.add(normalizedName);
      if (catalogIdentity) catalogIdentities.add(catalogIdentity);
      const rawSets = compact ? rawExercise[2] : rawExercise?.sets;
      if (!Array.isArray(rawSets) || !rawSets.length || rawSets.length > LIMITS.setsPerExercise) {
        fail("Shared workout set count is invalid.");
      }
      totalSets += rawSets.length;
      if (totalSets > LIMITS.totalSets) fail("Shared workout contains too many sets.");
      return Object.freeze({
        ...(builtInIdentity || catalogKey ? { catalogKey: builtInIdentity || catalogKey } : {}),
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

  function bytesToBase64Url(bytes) {
    return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
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
    if (bytesToBase64Url(bytes) !== value) fail("Shared workout encoding is invalid.");
    return bytes;
  }

  function validateStrictJson(text) {
    let index = 0;

    function skipWhitespace() {
      while (index < text.length && /[\u0009\u000a\u000d\u0020]/.test(text[index])) index += 1;
    }

    function scanString() {
      const start = index;
      if (text[index] !== "\"") fail("Shared workout JSON is invalid.");
      index += 1;
      while (index < text.length) {
        const character = text[index];
        if (character === "\"") {
          index += 1;
          try {
            return JSON.parse(text.slice(start, index));
          } catch {
            fail("Shared workout JSON is invalid.");
          }
        }
        if (character === "\\") {
          index += 1;
          if (text[index] === "u") index += 4;
        }
        index += 1;
      }
      fail("Shared workout JSON is invalid.");
    }

    function scanValue(depth) {
      if (depth > JSON_MAX_DEPTH) fail("Shared workout JSON is invalid.");
      skipWhitespace();
      const character = text[index];
      if (character === "{") {
        index += 1;
        skipWhitespace();
        const keys = new Set();
        if (text[index] === "}") {
          index += 1;
          return;
        }
        while (index < text.length) {
          skipWhitespace();
          const key = scanString();
          if (keys.has(key)) fail("Shared workout JSON is invalid.");
          keys.add(key);
          skipWhitespace();
          if (text[index] !== ":") fail("Shared workout JSON is invalid.");
          index += 1;
          scanValue(depth + 1);
          skipWhitespace();
          if (text[index] === "}") {
            index += 1;
            return;
          }
          if (text[index] !== ",") fail("Shared workout JSON is invalid.");
          index += 1;
        }
        fail("Shared workout JSON is invalid.");
      }
      if (character === "[") {
        index += 1;
        skipWhitespace();
        if (text[index] === "]") {
          index += 1;
          return;
        }
        while (index < text.length) {
          scanValue(depth + 1);
          skipWhitespace();
          if (text[index] === "]") {
            index += 1;
            return;
          }
          if (text[index] !== ",") fail("Shared workout JSON is invalid.");
          index += 1;
        }
        fail("Shared workout JSON is invalid.");
      }
      if (character === "\"") {
        scanString();
        return;
      }
      const primitive = text.slice(index).match(/^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/)?.[0];
      if (!primitive) fail("Shared workout JSON is invalid.");
      index += primitive.length;
    }

    scanValue(0);
    skipWhitespace();
    if (index !== text.length) fail("Shared workout JSON is invalid.");
  }

  function encode(input) {
    const plan = normalize(input);
    const bytes = utf8Bytes(JSON.stringify(compact(plan)));
    if (bytes.length > LIMITS.decodedBytes) fail("Shared workout is too large.");
    const encoded = bytesToBase64Url(bytes);
    if (encoded.length > LIMITS.encodedLength) fail("Shared workout is too large.");
    return encoded;
  }

  function decode(encoded) {
    if (typeof encoded !== "string" || !encoded.length || encoded.length > LIMITS.encodedLength) {
      fail("Shared workout encoding is invalid.");
    }
    let parsed;
    try {
      const text = new TextDecoder("utf-8", { fatal: true }).decode(base64ToBytes(encoded));
      validateStrictJson(text);
      parsed = JSON.parse(text);
    } catch (error) {
      if (error instanceof TypeError && error.message.startsWith("Shared workout")) throw error;
      fail("Shared workout JSON is invalid.");
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
        Object.keys(parsed).length !== 2 || !Object.hasOwn(parsed, "v") ||
        !Object.hasOwn(parsed, "e") || parsed.v !== VERSION || !Array.isArray(parsed.e)) {
      fail("Shared workout version is unsupported.");
    }
    for (const rawExercise of parsed.e) {
      if (!Array.isArray(rawExercise) || rawExercise.length !== 3 ||
          typeof rawExercise[0] !== "string" || typeof rawExercise[1] !== "string" ||
          !Array.isArray(rawExercise[2])) {
        fail("Shared workout exercise is invalid.");
      }
      for (const rawSet of rawExercise[2]) {
        if (!Array.isArray(rawSet) || rawSet.length !== 2 ||
            typeof rawSet[0] !== "number" || typeof rawSet[1] !== "number") {
          fail("Shared workout set is invalid.");
        }
      }
    }
    return normalize({ exercises: parsed.e });
  }

  function fromHash(hash) {
    const raw = String(hash || "").replace(/^#/, "");
    const prefix = `${HASH_KEY}=`;
    if (raw.length > prefix.length + LIMITS.encodedLength ||
        !raw.startsWith(prefix) || raw.includes("&")) return null;
    return decode(raw.slice(prefix.length));
  }

  function removeFromHash(hash) {
    const raw = String(hash || "").replace(/^#/, "");
    if (raw.length > 8192 || (raw && raw.split("&").length > 32)) return "";
    const params = new URLSearchParams(raw);
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

  return Object.freeze({
    VERSION,
    HASH_KEY,
    LIMITS,
    portableNameKey,
    configureBuiltInIdentityResolver,
    normalize,
    encode,
    decode,
    fromHash,
    removeFromHash,
    buildUrl
  });
});
