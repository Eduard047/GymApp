import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const manager = await readFile(
  "app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt",
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

test("Android rejects inbound Garmin workouts that carry no pairing generation", () => {
  const body = functionBody(manager, "private suspend fun createWorkout(");
  const start = body.indexOf("val rawGeneration");
  const end = body.indexOf("val binding = GarminBinding(");
  assert.ok(start !== -1 && end > start);
  const admission = body.slice(start, end);

  assert.doesNotMatch(admission, /LEGACY_GARMIN_FALLBACK_GENERATION/);
  assert.doesNotMatch(admission, /pairingGenerationSupported\(/);
  assert.doesNotMatch(admission, /\bnull\s*->/);
  assert.match(admission, /when \(rawGeneration\) \{\s*is String -> inboundPairingGeneration\(/);
  assert.match(admission, /else -> return@withLock null/);
});

test("the generationless fallback stays outbound-only", () => {
  const workoutPart = functionBody(manager, "private suspend fun receiveWorkoutPart(");

  assert.doesNotMatch(workoutPart, /LEGACY_GARMIN_FALLBACK_GENERATION/);
});
