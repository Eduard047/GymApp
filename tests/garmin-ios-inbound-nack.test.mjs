import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const swift = await readFile(
  "ios/GymApp-iOS/GymApp/Services/GarminPhoneSyncService.swift",
  "utf8",
);
const security = await readFile(
  "app/src/main/java/com/example/gymapp/garmin/GarminSyncSecurity.kt",
  "utf8",
);

function stripComments(text) {
  return text
    .split("\n")
    .filter(line => !line.trim().startsWith("//"))
    .join("\n");
}

// Returns the source from `signature` through the matching closing brace of its body.
function functionBody(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start !== -1, `${signature} must exist`);
  const open = source.indexOf("{", start + signature.length);
  assert.ok(open !== -1, `${signature} must have a body`);
  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") {
      depth -= 1;
      if (depth === 0) return stripComments(source.slice(start, index + 1));
    }
  }
  assert.fail(`${signature} body is not closed`);
}

const NACK_REASONS = [
  "generation_missing",
  "generation_mismatch",
  "binding_mismatch",
  "invalid",
  "rejected",
  "rate_limited",
  "reset_required",
];

const body = functionBody(swift, "private func receiveWorkout(");
const lines = body.split("\n");

// The first guard resolves the device binding and the ready account store.
const firstGuardStart = body.indexOf("guard let binding = binding(for: app.device)");
assert.ok(firstGuardStart !== -1, "the binding/store guard must exist");
const firstGuardEnd = body.indexOf("return false", firstGuardStart);
assert.ok(firstGuardEnd !== -1);

test("no nack path exists before the binding and ready-account guard", () => {
  const beforeGuard = body.slice(0, firstGuardStart);
  assert.doesNotMatch(beforeGuard, /sendNack\(/);

  const guard = body.slice(firstGuardStart, firstGuardEnd + "return false".length);
  assert.match(guard, /readyWorkoutStore\(\)/);
  // Unknown device / no ready account stays silent.
  assert.doesNotMatch(guard, /sendNack\(/);
  assert.match(guard, /else \{[\s\S]*return false$/);
});

test("every rejecting path after the guard sends a nack with a fixed reason", () => {
  const afterGuard = body.slice(firstGuardEnd + "return false".length);

  // Parse failure: the reason is classified by the parser.
  assert.match(
    afterGuard,
    /\) else \{\s*publishStatus\([^)]*\)\s*sendNack\(\s*for: rawMessage,\s*reason: GarminPhoneWorkoutParser\.rejectReason\(/,
  );
  // Hourly limit.
  assert.match(
    afterGuard,
    /maximumReceiptsPerHour else \{[^}]*sendNack\(for: rawMessage, reason: \.rateLimited, binding: binding, to: app\)/,
  );
  // Conflicting replay, ledger save failures and the catch block.
  assert.match(
    afterGuard,
    /existing\.digest == command\.digest else \{[^}]*sendNack\(for: rawMessage, reason: \.rejected, binding: binding, to: app\)/,
  );
  assert.match(
    afterGuard,
    /\} catch \{[\s\S]*sendNack\(for: rawMessage, reason: \.rejected, binding: binding, to: app\)\s*return false\s*\}\s*\}$/,
  );
  const rejectedNacks = afterGuard.match(
    /sendNack\(for: rawMessage, reason: \.rejected, binding: binding, to: app\)/g,
  );
  // conflicting replay, two replay-ledger saves, new-receipt save, post-commit save, catch.
  assert.equal(rejectedNacks.length, 6);
  assert.equal(
    afterGuard.match(/reason: \.rateLimited/g).length,
    1,
  );

  // Every `return false` after the first guard is preceded by a sendNack( call
  // (the multi-line parse-failure call spans 9 lines, hence the 12-line window).
  const firstGuardEndLine = body.slice(0, firstGuardEnd).split("\n").length - 1;
  let returnsFalse = 0;
  lines.forEach((line, index) => {
    if (index <= firstGuardEndLine || !/\breturn false\b/.test(line)) return;
    returnsFalse += 1;
    const preceding = lines.slice(Math.max(0, index - 12), index).join("\n");
    assert.match(preceding, /sendNack\(/, `return false at body line ${index + 1} must follow a nack`);
  });
  assert.ok(returnsFalse > 0);
  // One nack per rejecting return: nothing is nacked twice or without returning.
  assert.equal(afterGuard.match(/sendNack\(/g).length, returnsFalse);
});

test("GarminPhoneNackReason has exactly the seven shared wire reasons", () => {
  const start = swift.indexOf("enum GarminPhoneNackReason: String");
  assert.ok(start !== -1);
  const open = swift.indexOf("{", start);
  const end = swift.indexOf("\n}", open);
  const enumBody = stripComments(swift.slice(open, end));
  const cases = [...enumBody.matchAll(/^\s*case\s+\w+\s*=\s*"([a-z_]+)"\s*$/gm)].map(m => m[1]);
  assert.equal(enumBody.match(/^\s*case /gm).length, 7);
  assert.deepEqual([...cases].sort(), [...NACK_REASONS].sort());
});

test("the nack payload is fixed-shape and the request id is sanitized", () => {
  const payload = functionBody(swift, "static func nackPayload(");
  assert.match(payload, /"type": "nack"/);
  assert.match(payload, /"reason": reason\.rawValue/);
  assert.match(payload, /"bindingVersion": bindingVersion/);
  assert.match(payload, /"accountBinding": binding\.account/);
  assert.match(payload, /"deviceBinding": binding\.device/);
  assert.match(payload, /"pairingGeneration": binding\.pairingGeneration/);
  // requestId is added only through the sanitizer.
  assert.equal(payload.match(/requestId/g).length, 2);
  assert.match(payload, /let requestID = nackRequestID\(message\["requestId"\]\)/);
  assert.match(payload, /payload\["requestId"\] = requestID/);

  const requestId = functionBody(swift, "static func nackRequestID(");
  assert.match(requestId, /maximumRequestIDBytes/);
  assert.match(requestId, /0x20 \.\.\. 0x7E/);
});

test("rejectReason classifies in generation, binding, invalid order", () => {
  const reject = functionBody(swift, "static func rejectReason(");
  const order = [".generationMissing", ".generationMismatch", ".bindingMismatch", ".invalid"].map(
    token => {
      const at = reject.indexOf(`return ${token}`);
      assert.ok(at !== -1, `rejectReason must return ${token}`);
      return at;
    },
  );
  // The first `.invalid` is the non-dictionary guard; the final fallback comes last.
  assert.ok(order[0] < order[1] && order[1] < order[2]);
  assert.ok(reject.lastIndexOf("return .invalid") > order[2]);
});

test("Android and iOS share the same nack reason strings", () => {
  const androidReasons = [...security.matchAll(/const val [A-Z_]+ = "([a-z_]+)"/g)]
    .map(m => m[1])
    .filter(value => NACK_REASONS.includes(value));
  assert.deepEqual([...androidReasons].sort(), [...NACK_REASONS].sort());
  for (const reason of NACK_REASONS) {
    assert.match(security, new RegExp(`= "${reason}"`));
    assert.match(swift, new RegExp(`= "${reason}"`));
  }
});

test("chunked workout parts and sync requests never send a nack", () => {
  assert.doesNotMatch(functionBody(swift, "private func receiveWorkoutPart("), /sendNack\(/);
  assert.doesNotMatch(functionBody(swift, "private func receiveSyncRequest("), /sendNack\(/);
});
