import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const manager = await readFile(
  "app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt",
  "utf8",
);
const security = await readFile(
  "app/src/main/java/com/example/gymapp/garmin/GarminSyncSecurity.kt",
  "utf8",
);

function functionBody(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start !== -1, `${signature} must exist`);
  const next = source.indexOf("\n    private ", start + signature.length);
  return source
    .slice(start, next === -1 ? undefined : next)
    .split("\n")
    .filter(line => !line.trim().startsWith("//"))
    .join("\n");
}

const body = functionBody(manager, "private suspend fun createWorkout(");

test("no nack path exists before the trusted-device check", () => {
  const trusted = body.indexOf("trustedDeviceBinding(account) != sourceDeviceBinding");
  assert.ok(trusted !== -1);
  const lockStart = body.indexOf("pairingStateMutex.withLock {");
  assert.ok(lockStart !== -1 && lockStart < trusted);
  const beforeTrusted = body.slice(lockStart, trusted);
  assert.doesNotMatch(beforeTrusted, /reject\(/);
  assert.doesNotMatch(beforeTrusted, /nack/i);
  // The untrusted-device and no-account branches stay silent.
  const afterCheck = body.slice(trusted, body.indexOf("fun reject("));
  assert.match(afterCheck, /return@withLock null/);
  assert.doesNotMatch(afterCheck, /reject\(/);
});

test("generation-missing and generation-mismatch rejects send a fixed-reason nack", () => {
  assert.match(body, /\?: return@withLock reject\(GarminNackReason\.GENERATION_MISMATCH\)/);
  assert.match(body, /else -> return@withLock reject\(GarminNackReason\.GENERATION_MISSING\)/);
  assert.match(body, /reject\(GarminNackReason\.BINDING_MISMATCH,/);
  assert.match(body, /reject\(GarminNackReason\.INVALID,/);
  assert.match(body, /WorkoutPersistenceResult\.RateLimited ->\s*reject\(GarminNackReason\.RATE_LIMITED,/);
  assert.match(body, /reject\(GarminNackReason\.REJECTED,/);
  assert.match(body, /\} \?: run \{\s*sendWorkoutNack\(device, command, nackReason, nackBinding\)\s*return false/);
});

test("the nack is built from the fixed payload helper and bound like the ack", () => {
  const send = functionBody(manager, "private suspend fun sendWorkoutNack(");
  assert.match(send, /garminNackPayload\(command, reason\)/);
  assert.match(send, /boundGarminPayload\(/);
  assert.match(send, /sendAndWait\(/);
  assert.match(send, /if \(reason == null \|\| binding == null\) return/);

  assert.match(security, /const val GARMIN_NACK_TYPE = "nack"/);
  assert.match(security, /payload\["type"\] = GARMIN_NACK_TYPE/);
  assert.match(security, /payload\["reason"\] = reason/);
  for (const reason of [
    "generation_missing",
    "generation_mismatch",
    "binding_mismatch",
    "invalid",
    "rejected",
    "rate_limited",
    "reset_required",
  ]) {
    assert.match(security, new RegExp(`= "${reason}"`));
  }
});

test("the 24h rate limit maps to its own persistence result", () => {
  assert.match(
    manager,
    /GarminWorkoutApplyResult\.RateLimited -> \{[\s\S]*?WorkoutPersistenceResult\.RateLimited\s*\}/,
  );
});
