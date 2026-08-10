import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  recordBestEffortGarminTelemetry,
  scheduleBestEffortGarminTelemetry,
} from "../supabase/functions/_shared/garmin-telemetry.ts";

test("successful and not-yet-deployed Garmin telemetry stay silent", async () => {
  const warnings = [];
  const warn = (...args) => warnings.push(args);

  await recordBestEffortGarminTelemetry(async () => ({ error: null }), warn);
  await recordBestEffortGarminTelemetry(
    async () => ({ error: { code: "PGRST202" } }),
    warn,
  );

  assert.deepEqual(warnings, []);
});

test("telemetry RPC and transport failures never reject the primary result", async () => {
  const warnings = [];
  const warn = (message, details) => warnings.push({ message, details });

  await assert.doesNotReject(() =>
    recordBestEffortGarminTelemetry(
      async () => ({ error: { code: "42501" } }),
      warn,
    )
  );
  await assert.doesNotReject(() =>
    recordBestEffortGarminTelemetry(
      async () => {
        throw new Error("synthetic token=do-not-log");
      },
      warn,
    )
  );
  await assert.doesNotReject(() =>
    recordBestEffortGarminTelemetry(
      async () => ({ error: { code: "secret\nraw-token" } }),
      warn,
    )
  );
  await assert.doesNotReject(() =>
    recordBestEffortGarminTelemetry(
      async () => ({ error: { code: "500" } }),
      () => {
        throw new Error("logger unavailable");
      },
    )
  );

  assert.deepEqual(warnings, [
    {
      message: "Garmin capability telemetry failed",
      details: { code: "42501" },
    },
    {
      message: "Garmin capability telemetry failed",
      details: { code: "transport_error" },
    },
    {
      message: "Garmin capability telemetry failed",
      details: { code: "unknown" },
    },
  ]);
  assert.doesNotMatch(JSON.stringify(warnings), /do-not-log|raw-token/);
});

test("fetch and acknowledgement record telemetry only after their state RPC", async () => {
  const edge = await readFile(
    "supabase/functions/garmin-sync/index.ts",
    "utf8",
  );
  const fetchStart = edge.indexOf('if (body.action === "fetchPlan")');
  const ackStart = edge.indexOf('if (body.action === "ackPlan")');
  const end = edge.indexOf('return json({ error: "Unknown action" }');
  const fetch = edge.slice(fetchStart, ackStart);
  const ack = edge.slice(ackStart, end);
  const recorder = edge.slice(
    edge.indexOf("function scheduleCapabilityUse"),
    edge.indexOf("Deno.serve"),
  );

  assert.ok(fetchStart > 0 && ackStart > fetchStart && end > ackStart);
  assert.ok(fetch.indexOf("capabilityRpc(") < fetch.indexOf("scheduleCapabilityUse("));
  assert.ok(ack.indexOf("capabilityRpc(") < ack.indexOf("scheduleCapabilityUse("));
  assert.match(fetch, /candidate\?\.error !== "Invalid device"[\s\S]*scheduleCapabilityUse/);
  assert.match(ack, /acknowledged\?\.error !== "Invalid device"[\s\S]*scheduleCapabilityUse/);
  assert.match(recorder, /scheduleBestEffortGarminTelemetry/);
  assert.match(recorder, /runtime\.waitUntil\(task\)/);
  assert.doesNotMatch(recorder, /await scheduleBestEffortGarminTelemetry/);
});

test("background scheduling returns before telemetry and scheduler errors stay isolated", async () => {
  let finishOperation;
  let scheduledTask;
  let completed = false;
  const operation = () => new Promise((resolve) => {
    finishOperation = () => {
      completed = true;
      resolve({ error: null });
    };
  });

  scheduleBestEffortGarminTelemetry(operation, (task) => {
    scheduledTask = task;
  });
  assert.equal(completed, false);
  assert.ok(scheduledTask instanceof Promise);
  finishOperation();
  await scheduledTask;
  assert.equal(completed, true);

  assert.doesNotThrow(() =>
    scheduleBestEffortGarminTelemetry(
      async () => {
        throw new Error("synthetic telemetry rejection");
      },
      () => {
        throw new Error("scheduler unavailable");
      },
      () => undefined,
    )
  );
  await Promise.resolve();
});
