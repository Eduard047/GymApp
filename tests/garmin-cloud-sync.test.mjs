import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const {
  PLAN_LIMITS,
  validateGarminPlan,
  draftToGarminPlan,
  cloudPlanResponseToSyncMessage
} = require("../pwa/garmin-cloud-sync.js");

test("PWA draft becomes a clean Garmin cloud plan", () => {
  const plan = draftToGarminPlan({
    startedAt: Date.UTC(2026, 5, 29, 10, 30, 0),
    note: "Push day",
    blocks: [
      {
        exerciseName: " Bench Press ",
        sets: [
          { weight: "80,5", reps: "8" }
        ]
      },
      {
        exerciseName: "Squat",
        sets: [
          { weight: "120", reps: 5 }
        ]
      }
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
        sets: [{ weight: 120, reps: 5, orderIndex: 0 }]
      }
    ]
  });
});

test("empty or invalid draft is rejected before Supabase queueing", () => {
  assert.equal(draftToGarminPlan(null), null);
  assert.equal(draftToGarminPlan({ blocks: [{ exerciseName: "", sets: [{ weight: 10, reps: 8 }] }] }), null);
  assert.equal(draftToGarminPlan({ blocks: [{ exerciseName: "Bench", sets: [{ weight: -10, reps: 8 }] }] }), null);
  assert.equal(draftToGarminPlan({ blocks: [{ exerciseName: "Bench", sets: [
    { weight: 10, reps: 8 },
    { weight: "bad", reps: 8 }
  ] }] }), null, "one invalid set rejects the whole plan instead of truncating it");
  assert.equal(draftToGarminPlan({ note: "x".repeat(2001), blocks: [
    { exerciseName: "Bench", sets: [{ weight: 10, reps: 8 }] }
  ] }), null);
  assert.equal(draftToGarminPlan({ blocks: [
    { exerciseName: "Bench", sets: Array.from({ length: 61 }, () => ({ weight: 10, reps: 8 })) }
  ] }), null);
});

test("repeated exercise names fit Garmin's per-value storage byte budget", () => {
  const plan = {
    source: "pwa",
    version: 1,
    title: "Unicode plan",
    createdAt: "2026-06-29T12:00:00.000Z",
    startedAt: "2026-06-29T12:00:00.000Z",
    note: "",
    exercises: [{
      name: "Ж".repeat(160),
      sets: Array.from({ length: 60 }, (_, orderIndex) => ({ weight: 10, reps: 8, orderIndex }))
    }]
  };

  assert.equal(PLAN_LIMITS.totalExerciseNameBytes, 12000);
  assert.deepEqual(validateGarminPlan(plan), {
    ok: false,
    error: "Plan exercise names exceed the Garmin storage byte limit."
  });
});

test("set order must match Garmin's direct parser position", () => {
  const plan = {
    source: "pwa",
    version: 1,
    title: "Order plan",
    createdAt: "2026-06-29T12:00:00.000Z",
    startedAt: "2026-06-29T12:00:00.000Z",
    note: "",
    exercises: [{ name: "Bench", sets: [{ weight: 10, reps: 8, orderIndex: 1 }] }]
  };
  assert.equal(validateGarminPlan(plan).ok, false);
});

test("Garmin plans require complete bounded RFC3339 timestamps", () => {
  const plan = {
    source: "pwa",
    version: 1,
    title: "Timestamp plan",
    createdAt: "2026-06-29T12:00:00.000Z",
    startedAt: "2026-06-29T12:00:00.000Z",
    note: "",
    exercises: [{ name: "Bench", sets: [{ weight: 10, reps: 8, orderIndex: 0 }] }]
  };

  for (const timestamp of [
    "2026-06-29T12:00:00",
    "2026-06-29T12:00:00.1234567Z",
    "2026-06-29 tomorrow",
    "2026-06-29T12:00:00Z trailing"
  ]) {
    assert.equal(validateGarminPlan({ ...plan, createdAt: timestamp }).ok, false);
  }
  assert.equal(validateGarminPlan({ ...plan, createdAt: "2026-06-29T12:00:00+03:00" }).ok, true);
});

test("cloud response flattens to the sync payload Garmin applies", () => {
  const message = cloudPlanResponseToSyncMessage({
    status: "ok",
    bindingVersion: 2,
    accountBinding: "a".repeat(64),
    deviceBinding: "00000000-0000-4000-8000-000000000001",
    planId: "00000000-0000-4000-8000-000000000002",
    planRevision: 42,
    plan: {
      source: "pwa",
      version: 1,
      title: "Today plan",
      createdAt: "2026-06-29T12:00:00.000Z",
      startedAt: "2026-06-29T10:30:00.000Z",
      note: "",
      exercises: [
        { name: "Bench Press", sets: [{ weight: 80.5, reps: 8, orderIndex: 0 }, { weight: 82.5, reps: 6, orderIndex: 1 }] },
        { name: "Squat", sets: [{ weight: 120, reps: 5, orderIndex: 0 }] }
      ]
    }
  });

  assert.deepEqual(message, {
    type: "sync",
    syncId: "00000000-0000-4000-8000-000000000002",
    bindingVersion: 2,
    accountBinding: "a".repeat(64),
    deviceBinding: "00000000-0000-4000-8000-000000000001",
    planRevision: 42,
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

test("cloud delivery revisions must be positive monotonic int32 counters", () => {
  const base = {
    status: "ok",
    bindingVersion: 2,
    accountBinding: "a".repeat(64),
    deviceBinding: "00000000-0000-4000-8000-000000000001",
    planId: "00000000-0000-4000-8000-000000000002",
    plan: {
      source: "pwa",
      version: 1,
      title: "Today plan",
      createdAt: "2026-06-29T12:00:00.000Z",
      startedAt: "2026-06-29T12:00:00.000Z",
      note: "",
      exercises: [{ name: "Bench", sets: [{ weight: 10, reps: 8, orderIndex: 0 }] }]
    }
  };
  for (const planRevision of [0, -1, 1.5, 2147483648, "2", null]) {
    assert.equal(cloudPlanResponseToSyncMessage({ ...base, planRevision }), null);
  }
  assert.equal(cloudPlanResponseToSyncMessage({ ...base, planRevision: 2147483647 })?.planRevision, 2147483647);
});

test("PWA, Supabase, and Garmin code are wired to the same cloud sync contract", async () => {
  const [appJs, indexHtml, swJs, edgeFunction, edgeConfig, schema, hardeningMigration, rateLimitMigration, denoConfig, denoLock, gymComm, workoutView, settingsXml, manifest, buildScript] = await Promise.all([
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/sw.js", "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
    readFile("supabase/config.toml", "utf8"),
    readFile("supabase/migrations/20260629120000_garmin_cloud_sync.sql", "utf8"),
    readFile("supabase/migrations/20260713210000_harden_garmin_pairing_and_plans.sql", "utf8"),
    readFile("supabase/migrations/20260714010000_add_garmin_device_rate_limits.sql", "utf8"),
    readFile("supabase/functions/garmin-sync/deno.json", "utf8"),
    readFile("supabase/functions/garmin-sync/deno.lock", "utf8"),
    readFile("garmin/source/GymComm.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/resources/settings/settings.xml", "utf8"),
    readFile("garmin/manifest.xml", "utf8"),
    readFile("scripts/build-garmin.ps1", "utf8")
  ]);

  assert.match(indexHtml, /garmin-cloud-sync\.v50\.js/);
  assert.match(swJs, /garmin-cloud-sync\.v50\.js/);
  assert.match(appJs, /\/functions\/v1\/garmin-sync/);
  assert.match(appJs, /\/rest\/v1\/rpc\/garmin_enqueue_plan/);
  assert.doesNotMatch(appJs, /supabaseRequest\("\/rest\/v1\/garmin_plans"/);
  assert.match(appJs, /p_client_request_id:\s*record\.requestId/);
  assert.match(appJs, /action:\s*"createDevice"/);
  assert.match(appJs, /action:\s*"revokeDevice"/);
  assert.doesNotMatch(appJs, /localStorage\.getItem\(GARMIN_DEVICE_TOKEN_KEY\)/);
  assert.doesNotMatch(appJs, /navigator\.clipboard\?\.writeText\(device\.device_token\)/);

  assert.match(schema, /create table if not exists public\.garmin_devices/);
  assert.match(schema, /create table if not exists public\.garmin_plans/);
  assert.match(schema, /alter table public\.garmin_devices enable row level security/);
  assert.match(schema, /alter table public\.garmin_plans enable row level security/);

  assert.match(edgeFunction, /action === "createDevice"/);
  assert.match(edgeFunction, /action === "fetchPlan"/);
  assert.match(edgeFunction, /action === "revokeDevice"/);
  assert.match(edgeFunction, /action === "listDevices"/);
  assert.match(edgeFunction, /action === "rotateDeviceToken"/);
  assert.match(edgeFunction, /SUPABASE_ANON_KEY/);
  assert.match(edgeFunction, /rpc\(\s*"garmin_fetch_pending_plan"/);
  assert.match(edgeFunction, /action === "ackPlan"/);
  assert.match(edgeFunction, /rpc\(\s*"garmin_ack_plan"/);
  assert.doesNotMatch(edgeFunction.slice(
    edgeFunction.indexOf('if (body.action === "fetchPlan")'),
    edgeFunction.indexOf('if (body.action === "ackPlan")')
  ), /garmin_ack_plan/);
  assert.match(edgeConfig, /\[functions\.garmin-sync\][\s\S]*verify_jwt = false/);
  assert.doesNotMatch(edgeFunction, /https:\/\/esm\.sh/);
  assert.match(edgeFunction, /"Cache-Control": "no-store"/);
  assert.match(denoConfig, /npm:@supabase\/supabase-js@2\.110\.2/);
  assert.match(denoConfig, /"frozen": true/);
  assert.match(denoLock, /"integrity": "sha512-/);
  assert.match(hardeningMigration, /security definer/);
  assert.match(hardeningMigration, /status = 'downloaded'/);
  assert.match(hardeningMigration, /status = 'invalid'/);
  assert.match(hardeningMigration, /status = 'superseded'/);
  assert.match(hardeningMigration, /for update skip locked/);
  assert.match(hardeningMigration, /grant execute on function public\.garmin_revoke_device\(uuid\) to authenticated/);
  assert.match(rateLimitMigration, /security definer/);
  assert.match(rateLimitMigration, /'status', 'rate_limited'/);
  assert.match(rateLimitMigration, /status = 'invalid'/);
  assert.match(rateLimitMigration, /for update;/);
  assert.match(rateLimitMigration, /rename to garmin_fetch_pending_plan_core/);
  assert.match(rateLimitMigration, /grant execute on function public\.garmin_fetch_pending_plan\(text\)\s+to anon/);
  assert.match(rateLimitMigration, /grant execute on function public\.garmin_ack_plan\(text, uuid, bigint\)\s+to anon/);

  assert.match(settingsXml, /@Properties\.CloudDeviceToken/);
  assert.match(gymComm, /CloudDeviceToken/);
  assert.match(gymComm, /Comm\.makeWebRequest/);
  assert.match(gymComm, /\/functions\/v1\/garmin-sync/);
  assert.match(workoutView, /requestCloudSyncNow/);
  assert.match(workoutView, /GymStore\.applyCloudSync\(message\)/);
  assert.match(workoutView, /function sx\(w, baseX\)/);
  assert.match(workoutView, /function sy\(h, baseY\)/);
  assert.match(workoutView, /function sr\(w, h, value\)/);
  assert.match(manifest, /<iq:product id="fenix8solar47mm" \/>/);
  assert.match(manifest, /<iq:product id="venu3" \/>/);
  assert.match(buildScript, /\[string\]\$Device = 'fenix8solar47mm'/);
  assert.match(buildScript, /Connect IQ device '\$Device' is not installed/);
});
