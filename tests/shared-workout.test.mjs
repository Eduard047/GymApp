import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import test from "node:test";

const require = createRequire(import.meta.url);
const codec = require("../pwa/shared-workout.js");
const appSource = readFileSync(new URL("../pwa/app.js", import.meta.url), "utf8");
const indexSource = readFileSync(new URL("../pwa/index.html", import.meta.url), "utf8");
const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");

function rawPayload(json) {
  return Buffer.from(typeof json === "string" ? json : JSON.stringify(json)).toString("base64url");
}

function nonCanonicalVariant(canonical) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  const remainder = canonical.length % 4;
  assert.ok(remainder === 2 || remainder === 3);
  const last = alphabet.indexOf(canonical.at(-1));
  return `${canonical.slice(0, -1)}${alphabet[last ^ 1]}`;
}

const sample = {
  accountId: "must-not-leak",
  note: "private note",
  heartRate: [120, 140],
  calories: 321,
  exercises: [
    {
      catalogKey: "lat_pulldown",
      name: "Тяга верхнього блока",
      garminDeviceId: "must-not-leak",
      sets: [{ weight: 50, reps: 8 }, { weight: 52.5, reps: 8 }]
    },
    {
      name: "Custom movement",
      sets: [{ weight: 0, reps: 10 }]
    }
  ]
};

test("shared workout round-trips exercises and planned sets only", () => {
  const decoded = codec.decode(codec.encode(sample));
  assert.deepEqual(decoded, {
    version: 1,
    exercises: [
      {
        catalogKey: "lat_pulldown",
        name: "Тяга верхнього блока",
        sets: [{ weight: 50, reps: 8 }, { weight: 52.5, reps: 8 }]
      },
      {
        name: "Custom movement",
        sets: [{ weight: 0, reps: 10 }]
      }
    ]
  });
  const serialized = JSON.stringify(decoded);
  for (const secret of ["must-not-leak", "private note", "heartRate", "calories", "garminDeviceId"]) {
    assert.equal(serialized.includes(secret), false);
  }
});

test("shared workout URL keeps its payload in the fragment", () => {
  const url = new URL(codec.buildUrl("https://gymapptracker.com/workout/?tracking=remove", sample));
  assert.equal(url.origin, "https://gymapptracker.com");
  assert.equal(url.pathname, "/workout/");
  assert.equal(url.search, "");
  assert.match(url.hash, /^#workout=[A-Za-z0-9_-]+$/);
  assert.deepEqual(codec.fromHash(url.hash), codec.normalize(sample));
  assert.equal(codec.removeFromHash(`${url.hash}&theme=dark`), "#theme=dark");
});

test("shared workout decoder rejects malformed and unbounded input", () => {
  assert.throws(() => codec.decode("***"), /invalid/);
  assert.throws(() => codec.decode("a".repeat(codec.LIMITS.encodedLength + 1)), /invalid/);
  assert.throws(() => codec.normalize({ exercises: [] }), /exercise count/);
  assert.throws(() => codec.normalize({ exercises: Array.from({ length: codec.LIMITS.exercises + 1 }, () => sample.exercises[0]) }), /exercise count/);
  assert.throws(() => codec.normalize({ exercises: [{ name: "X", sets: [{ weight: Number.NaN, reps: 8 }] }] }), /weight/);
  assert.throws(() => codec.normalize({ exercises: [{ name: "X", sets: [{ weight: 10, reps: 8.5 }] }] }), /repetitions/);
  assert.throws(() => codec.normalize({ exercises: [{ name: "X\u0000Y", sets: [{ weight: 10, reps: 8 }] }] }), /name/);
  assert.throws(() => codec.normalize({ exercises: [{ catalogKey: "../bad", name: "X", sets: [{ weight: 10, reps: 8 }] }] }), /catalog key/);
});

test("shared workout rejects controls, formats, and line separators before encode or import", () => {
  const unsafeScalars = ["\u0080", "\u009f", "\u200b", "\u2060", "\ufeff", "\u2028", "\u2029"];
  for (const scalar of unsafeScalars) {
    const exercise = { name: `Visible${scalar}Name`, sets: [{ weight: 10, reps: 8 }] };
    assert.throws(() => codec.normalize({ exercises: [exercise] }), /supported bounds/);
    assert.throws(() => codec.encode({ exercises: [exercise] }), /supported bounds/);
    assert.throws(
      () => codec.decode(rawPayload({ v: 1, e: [["", exercise.name, [[10, 8]]]] })),
      /supported bounds/
    );
  }
});

test("shared workout decoder requires exact v1 JSON shapes and unique object keys", () => {
  const compactExercise = ["", "X", [[10, 8]]];
  assert.throws(
    () => codec.decode(rawPayload({ v: 1, e: [compactExercise], accountId: "private" })),
    /version|unsupported/
  );
  assert.throws(
    () => codec.decode(rawPayload({ v: 1, e: [["", "X", [[10, 8]], "extra"]] })),
    /exercise/
  );
  assert.throws(
    () => codec.decode(rawPayload({ v: 1, e: [["", "X", [[10, 8, 9]]]] })),
    /set/
  );
  assert.throws(
    () => codec.decode(rawPayload('{"v":1,"\\u0076":1,"e":[["","X",[[10,8]]]]}')),
    /JSON/
  );
});

test("shared workout decoder rejects non-canonical base64url and encoded hash syntax", () => {
  let canonical;
  for (let suffix = ""; suffix.length < 4; suffix += "x") {
    canonical = codec.encode({ exercises: [{ name: `X${suffix}`, sets: [{ weight: 10, reps: 8 }] }] });
    if (canonical.length % 4 !== 0) break;
  }
  const alternative = nonCanonicalVariant(canonical);
  assert.deepEqual(Buffer.from(alternative, "base64url"), Buffer.from(canonical, "base64url"));
  assert.throws(() => codec.decode(alternative), /encoding/);
  assert.throws(() => codec.fromHash(`#workout=%${canonical.charCodeAt(0).toString(16)}${canonical.slice(1)}`), /encoding/);
  assert.equal(codec.fromHash(`#workout=${canonical}&theme=dark`), null);
});

test("shared workout identities reject normalized and built-in duplicates", () => {
  const oneSet = [{ weight: 10, reps: 8 }];
  assert.throws(() => codec.normalize({ exercises: [
    { name: "Custom   Move", sets: oneSet },
    { name: " custom move ", sets: oneSet }
  ] }), /duplicate/);

  const aliases = new Map([
    [codec.portableNameKey("Bench Press"), "bench_press"],
    [codec.portableNameKey("Жим штанги лежачи"), "bench_press"]
  ]);
  const resolver = name => aliases.get(codec.portableNameKey(name)) || null;
  codec.configureBuiltInIdentityResolver(resolver);
  assert.throws(() => codec.normalize({ exercises: [
    { name: "Bench Press", sets: oneSet },
    { name: "Жим штанги лежачи", sets: oneSet }
  ] }), /duplicate/);
});

test("PWA previews a validated share and imports it only after explicit confirmation", () => {
  assert.match(indexSource, /shared-workout\.v65\.js/);
  assert.match(indexSource, /shared-workout-flow\.v71\.js/);
  assert.match(workerSource, /shared-workout\.v65\.js/);
  assert.match(workerSource, /shared-workout-flow\.v71\.js/);
  assert.match(appSource, /configureBuiltInIdentityResolver\?\.\(catalogKeyRecognizedFromName\)/);
  assert.match(appSource, /const SHARED_WORKOUT_URL = `\$\{PUBLIC_SITE_URL\}workout\/`/);
  assert.match(appSource, /function applyPendingSharedWorkout\(allowDraftReplacement = false\)/);
  assert.match(appSource, /status === "blocked-active"/);
  assert.match(appSource, /type: "confirm-shared-workout-replace"/);
  assert.doesNotMatch(appSource, /function activatePendingSharedWorkout/);
  assert.match(appSource, /nav = \[\{ name: "workouts" \}, \{ name: "add" \}\]/);
  const explicitImport = appSource.slice(
    appSource.indexOf("function applyPendingSharedWorkout"),
    appSource.indexOf("function sharedWorkoutPlanFromDraft")
  );
  assert.doesNotMatch(explicitImport, /saveState|state\.sessions\.push|queueRemoteSave/);

  const capture = appSource.slice(
    appSource.indexOf("function captureSharedWorkoutFromLocation"),
    appSource.indexOf("function sharedWorkoutPreviewMarkup")
  );
  const malformedBranch = capture.slice(capture.indexOf("} catch {"));
  assert.doesNotMatch(malformedBranch, /pendingSharedWorkout\s*=\s*null|clearStoredSharedWorkout\(\)/);
});
