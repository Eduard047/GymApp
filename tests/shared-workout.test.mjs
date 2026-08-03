import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import test from "node:test";

const require = createRequire(import.meta.url);
const codec = require("../pwa/shared-workout.js");
const appSource = readFileSync(new URL("../pwa/app.js", import.meta.url), "utf8");
const indexSource = readFileSync(new URL("../pwa/index.html", import.meta.url), "utf8");
const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");

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
  const url = new URL(codec.buildUrl("https://gymapptracker.com/?tracking=remove", sample));
  assert.equal(url.origin, "https://gymapptracker.com");
  assert.equal(url.pathname, "/");
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

test("PWA opens a validated share as an editable draft without auto-saving", () => {
  assert.match(indexSource, /shared-workout\.v64\.js/);
  assert.match(workerSource, /shared-workout\.v64\.js/);
  assert.match(appSource, /activatePendingSharedWorkout\(\)/);
  assert.match(appSource, /workoutDraft = \{/);
  assert.match(appSource, /nav = \[\{ name: "workouts" \}, \{ name: "add" \}\]/);
  const activation = appSource.slice(
    appSource.indexOf("function activatePendingSharedWorkout"),
    appSource.indexOf("function sharedWorkoutPlanFromDraft")
  );
  assert.doesNotMatch(activation, /saveState|state\.sessions\.push|queueRemoteSave/);
});
