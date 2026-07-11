import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const { draftToGarminPlan, cloudPlanResponseToSyncMessage } = require("../pwa/garmin-cloud-sync.js");

test("PWA draft becomes a clean Garmin cloud plan", () => {
  const plan = draftToGarminPlan({
    startedAt: Date.UTC(2026, 5, 29, 10, 30, 0),
    note: "Push day",
    blocks: [
      {
        exerciseName: " Bench Press ",
        sets: [
          { weight: "80,5", reps: "8" },
          { weight: "-1", reps: "8" },
          { weight: "bad", reps: "8" },
          { weight: "82.5", reps: "0" }
        ]
      },
      {
        exerciseName: "Squat",
        sets: [
          { weight: "120", reps: 5 },
          { weight: "", reps: 3 }
        ]
      },
      { exerciseName: "   ", sets: [{ weight: 10, reps: 10 }] }
    ]
  }, {
    title: "Today plan",
    now: () => new Date("2026-06-29T12:00:00.000Z")
  });

  assert.deepEqual(plan, {
    source: "pwa",
    version: 1,
    title: "Today plan",
    createdAt: "2026-06-29T12:00:00.000Z",
    startedAt: "2026-06-29T10:30:00.000Z",
    note: "Push day",
    exercises: [
      { name: "Bench Press", sets: [{ weight: 80.5, reps: 8, orderIndex: 0 }] },
      {
        name: "Squat",
        sets: [
          { weight: 120, reps: 5, orderIndex: 0 },
          { weight: 0, reps: 3, orderIndex: 1 }
        ]
      }
    ]
  });
});

test("empty or invalid draft is rejected before Supabase queueing", () => {
  assert.equal(draftToGarminPlan(null), null);
  assert.equal(draftToGarminPlan({ blocks: [{ exerciseName: "", sets: [{ weight: 10, reps: 8 }] }] }), null);
  assert.equal(draftToGarminPlan({ blocks: [{ exerciseName: "Bench", sets: [{ weight: -10, reps: 8 }] }] }), null);
});

test("cloud response flattens to the sync payload Garmin applies", () => {
  const message = cloudPlanResponseToSyncMessage({
    status: "ok",
    planId: "plan-123",
    plan: {
      exercises: [
        { name: "Bench Press", sets: [{ weight: 80.5, reps: 8 }, { weight: 82.5, reps: 6 }] },
        { name: "Squat", sets: [{ weight: 120, reps: 5 }] }
      ]
    }
  });

  assert.deepEqual(message, {
    type: "sync",
    syncId: "plan-123",
    resetWorkout: false,
    planNames: ["Bench Press", "Bench Press", "Squat"],
    planWeights: [80.5, 82.5, 120],
    planReps: [8, 6, 5]
  });
});

test("non-plan cloud responses do not produce Garmin sync messages", () => {
  assert.equal(cloudPlanResponseToSyncMessage({ status: "empty" }), null);
  assert.equal(cloudPlanResponseToSyncMessage({ status: "ok", plan: { exercises: [] } }), null);
  assert.equal(cloudPlanResponseToSyncMessage({ status: "error", error: "Invalid device" }), null);
});

test("PWA, Supabase, and Garmin code are wired to the same cloud sync contract", async () => {
  const [appJs, indexHtml, swJs, edgeFunction, schema, rpcMigration, gymComm, workoutView, settingsXml, manifest, buildScript] = await Promise.all([
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/sw.js", "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
    readFile("supabase/migrations/20260629120000_garmin_cloud_sync.sql", "utf8"),
    readFile("supabase/migrations/20260630000100_garmin_fetch_pending_plan_rpc.sql", "utf8"),
    readFile("garmin/source/GymComm.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/resources/settings/settings.xml", "utf8"),
    readFile("garmin/manifest.xml", "utf8"),
    readFile("scripts/build-garmin.ps1", "utf8")
  ]);

  assert.match(indexHtml, /garmin-cloud-sync\.js\?v=1/);
  assert.match(swJs, /garmin-cloud-sync\.js/);
  assert.match(appJs, /\/functions\/v1\/garmin-sync/);
  assert.match(appJs, /\/rest\/v1\/garmin_plans/);
  assert.match(appJs, /action:\s*"createDevice"/);

  assert.match(schema, /create table if not exists public\.garmin_devices/);
  assert.match(schema, /create table if not exists public\.garmin_plans/);
  assert.match(schema, /alter table public\.garmin_devices enable row level security/);
  assert.match(schema, /alter table public\.garmin_plans enable row level security/);

  assert.match(edgeFunction, /action === "createDevice"/);
  assert.match(edgeFunction, /action === "fetchPlan"/);
  assert.match(edgeFunction, /SUPABASE_ANON_KEY/);
  assert.match(edgeFunction, /rpc\("garmin_fetch_pending_plan"/);
  assert.match(rpcMigration, /security definer/);
  assert.match(rpcMigration, /status = 'downloaded'/);
  assert.match(rpcMigration, /grant execute on function public\.garmin_fetch_pending_plan\(text\) to anon, authenticated/);

  assert.match(settingsXml, /@Properties\.CloudDeviceToken/);
  assert.match(gymComm, /CloudDeviceToken/);
  assert.match(gymComm, /Comm\.makeWebRequest/);
  assert.match(gymComm, /\/functions\/v1\/garmin-sync/);
  assert.match(workoutView, /requestCloudSyncNow/);
  assert.match(workoutView, /GymStore\.applySync\(message\)/);
  assert.match(workoutView, /function sx\(w, baseX\)/);
  assert.match(workoutView, /function sy\(h, baseY\)/);
  assert.match(workoutView, /function sr\(w, h, value\)/);
  assert.match(manifest, /<iq:product id="fenix8solar47mm" \/>/);
  assert.match(manifest, /<iq:product id="venu3" \/>/);
  assert.match(buildScript, /\[string\]\$Device = 'fenix8solar47mm'/);
  assert.match(buildScript, /Connect IQ device '\$Device' is not installed/);
});
