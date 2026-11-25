import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const contract = JSON.parse(readFileSync(new URL("../shared/watch-sync-v1.json", import.meta.url), "utf8"));

test("watch sync contract: transport and formats", () => {
  assert.equal(contract.schemaVersion, 1);
  assert.equal(contract.protocolVersion, 1);
  const t = contract.transport;
  assert.equal(t.envelopeKey, "gymappWatchSync");
  assert.equal(t.maximumEnvelopeBytes, 65536);
  assert.equal(t.context, "updateApplicationContext");
  for (const key of ["workout", "ack", "nack", "account-deleted"]) assert.equal(t[key], "transferUserInfo");
  const requestId = new RegExp(contract.formats.requestId);
  assert.ok(requestId.test("aw-0f8fad5b-d9cb-469f-a165-70867728950e"));
  assert.ok(!requestId.test("aw-0F8FAD5B-D9CB-469F-A165-70867728950E"));
  assert.ok(!requestId.test("garmin-123"));
  const hash = new RegExp(contract.formats.accountBinding);
  assert.ok(hash.test(contract.fixtures.activeAccount));
  assert.ok(hash.test(contract.fixtures.foreignAccount));
  assert.notEqual(contract.fixtures.activeAccount, contract.fixtures.foreignAccount);
  assert.deepEqual(contract.formats.languages, ["en", "uk", "ru"]);
});

test("watch sync contract: bounds are consistent", () => {
  const b = contract.bounds;
  assert.ok(b.maximumExerciseCharacters * 4 >= b.maximumExerciseBytes);
  assert.ok(b.maximumExerciseBytes < b.maximumTotalExerciseBytes);
  assert.ok(b.maximumTotalExerciseBytes < contract.transport.maximumEnvelopeBytes);
  assert.ok(b.maximumSetsPerExercise <= b.maximumPlanSets);
  assert.ok(b.maximumPlanExercises <= b.maximumPlanSets);
  for (const key of ["weight", "reps", "restSeconds", "planRevision", "durationSeconds", "heartRateBpm", "activeKilocalories"]) {
    assert.ok(b[key].minimum <= b[key].maximum, key);
  }
  assert.ok(b.restSeconds.default >= b.restSeconds.minimum && b.restSeconds.default <= b.restSeconds.maximum);
  assert.equal(b.planRevision.maximum, Number.MAX_SAFE_INTEGER);
  assert.ok(b.reps.minimum >= 1 && b.weight.minimum >= 0);
  assert.ok(b.maximumReceiptsPerHour <= b.maximumReceiptRecords);
  assert.ok(b.minimumStartedAtMillis > 0 && b.maximumFutureSkewMillis > 0);
});

test("watch sync contract: nack reasons fall in exactly one group", () => {
  const groups = contract.nackReasons;
  assert.deepEqual(Object.keys(groups).sort(), ["deterministic", "hold", "transient"]);
  const all = Object.values(groups).flat();
  assert.equal(new Set(all).size, all.length);
  assert.deepEqual(groups.transient, ["not-ready", "storage", "rate-limited"]);
  assert.deepEqual(groups.hold, ["foreign-account", "unsupported-version"]);
  assert.deepEqual(groups.deterministic, ["malformed", "conflict", "invalid"]);
});

test("watch sync contract: cases are unique and well-formed", () => {
  const ids = contract.cases.map((item) => item.id);
  assert.equal(new Set(ids).size, ids.length);
  const reasons = new Set(Object.values(contract.nackReasons).flat());
  const byId = new Map(contract.cases.map((item) => [item.id, item]));
  for (const item of contract.cases) {
    assert.ok(["phoneToWatch", "watchToPhone"].includes(item.direction), item.id);
    assert.ok(item.message || item.replayOf || item.envelopeBytes, item.id);
    if (item.replayOf) assert.ok(byId.get(item.replayOf)?.message, `${item.id}: replayOf`);
    if (item.envelopeBytes) assert.ok(item.envelopeBytes > contract.transport.maximumEnvelopeBytes, item.id);
    const e = item.expect;
    if (item.direction === "phoneToWatch") {
      assert.equal(typeof e.valid, "boolean", item.id);
      assert.ok(["context", "account-deleted"].includes(item.message.type), item.id);
      if (item.message.type === "account-deleted" && e.valid) {
        assert.deepEqual(Object.keys(item.message).sort(), [...contract.messages["account-deleted"].keys].sort(), item.id);
        assert.ok(new RegExp(contract.formats.accountBinding).test(item.message.accountBinding), item.id);
      }
    } else {
      assert.ok(["ack", "nack", "drop"].includes(e.result), item.id);
      if (e.result === "nack") assert.ok(reasons.has(e.reason), item.id);
      if (e.result === "ack") assert.ok(["committed", "duplicate"].includes(e.status), item.id);
    }
    const message = item.message ?? byId.get(item.replayOf)?.message;
    if (message?.type === "workout") {
      assert.ok(new RegExp(contract.formats.requestId).test(message.requestId), item.id);
      for (const key of Object.keys(message)) {
        assert.ok(
          contract.messages.workout.requiredKeys.includes(key) || contract.messages.workout.optionalKeys.includes(key),
          `${item.id}: ${key}`,
        );
      }
    }
  }
  // Old watches decode the unbound context by its exact key set: deletion must not add context keys.
  assert.deepEqual(contract.messages.context.requiredKeys, ["type", "protocolVersion", "state", "sentAtMillis"]);
  assert.ok(contract.cases.some((item) => item.message?.type === "account-deleted" && item.expect.valid === true));
  for (const reason of ["foreign-account", "not-ready", "unsupported-version", "malformed", "conflict"]) {
    assert.ok(contract.cases.some((item) => item.expect.reason === reason), `no case for ${reason}`);
  }
});

test("watch sync contract: restEndAlert is an optional bound-only boolean, absent = true", () => {
  const context = contract.messages.context;
  assert.ok(context.optionalKeys.includes("restEndAlert"));
  assert.ok(!context.requiredKeys.includes("restEndAlert"));
  assert.equal(typeof context.restEndAlert, "string");
  const boundKeys = [...context.requiredKeys, "accountBinding", "language", "planRevision", "plan", "exercises"];
  const contexts = contract.cases.filter((item) => item.message?.type === "context");
  for (const item of contexts) {
    if (!("restEndAlert" in item.expect)) continue;
    assert.equal(item.expect.valid, true, item.id);
    assert.equal(item.message.state, "bound", item.id);
    const expected = "restEndAlert" in item.message ? item.message.restEndAlert : true;
    assert.equal(item.expect.restEndAlert, expected, item.id);
  }
  // The default (on) context carries no restEndAlert, so its key set is unchanged for old watches.
  const absent = contexts.find((item) => item.expect.valid && item.message.state === "bound" && !("restEndAlert" in item.message));
  assert.ok(absent, "no bound context without restEndAlert");
  assert.deepEqual(Object.keys(absent.message).sort(), [...boundKeys].sort());
  assert.equal(absent.expect.restEndAlert, true);
  // Off is sent as a JSON boolean false; a non-boolean value is rejected.
  const off = contexts.find((item) => item.message.restEndAlert === false);
  assert.ok(off && off.expect.valid === true && off.expect.restEndAlert === false);
  const nonBoolean = contexts.filter((item) => "restEndAlert" in item.message && typeof item.message.restEndAlert !== "boolean");
  assert.ok(nonBoolean.length > 0);
  for (const item of nonBoolean) assert.equal(item.expect.valid, false, item.id);
  // The unbound context never carries it.
  const unbound = contexts.filter((item) => item.message.state === "unbound" && item.expect.valid);
  for (const item of unbound) assert.ok(!("restEndAlert" in item.message), item.id);
});
