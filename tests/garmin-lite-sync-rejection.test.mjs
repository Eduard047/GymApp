import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const liteDevices = ["instinct2", "instinct2s", "instinct2x", "instinctcrossover", "descentg1"];

function annotatedBody(source, annotation, signature) {
  let at = source.indexOf(signature);
  while (at !== -1) {
    const open = source.lastIndexOf("(:", at);
    const close = source.indexOf(")", open);
    if (open !== -1 && /^\s*$/.test(source.slice(close + 1, at)) &&
        source.slice(open + 2, close).split(",").map((v) => v.trim().replace(/^:/, "")).includes(annotation)) {
      const start = source.indexOf("{", at);
      let depth = 0;
      for (let i = start; i < source.length; i += 1) {
        if (source[i] === "{") depth += 1;
        if (source[i] === "}" && --depth === 0) return source.slice(start, i + 1);
      }
    }
    at = source.indexOf(signature, at + signature.length);
  }
  assert.fail(`Missing :${annotation} ${signature}`);
}

test("96 KiB sync applies pairing fields only and drops the plan before validation", async () => {
  const app = await readFile("garmin/source/GymApp.mc", "utf8");
  const liteHandler = annotatedBody(app, "compactWorkoutMode96", "function handleSyncMessage(");
  // Plan columns and catalog are replaced before any validation or copy.
  assert.match(liteHandler, /message\.put\("planNames", \[\]\)/);
  assert.match(liteHandler, /message\.put\("planWeights", \[\]\)/);
  assert.match(liteHandler, /message\.put\("planReps", \[\]\)/);
  assert.match(liteHandler, /message\.remove\("exercises"\)/);
  assert.ok(liteHandler.indexOf('"planNames"') < liteHandler.indexOf("applyPhoneSync"));
  // The same validated apply path as the other profiles.
  assert.match(liteHandler, /GymStore\.applyPhoneSync\(message\)/);
  assert.match(liteHandler, /sendSyncAck\(message, applied\)/);

  const liteAck = annotatedBody(app, "compactWorkoutMode96", "function sendSyncAck(");
  assert.doesNotMatch(liteAck, /get\("(plan|exercises|sets)/);
  assert.doesNotMatch(liteAck, /planCount|exerciseCount/);
  assert.match(liteAck, /"type" => "sync_ack"/);
  assert.match(liteAck, /"applied" => applied/);
  assert.match(liteAck, /"lite" => 1/);
  assert.match(liteAck, /GymStore\.bindingsMatch\(message\)[\s\S]*message = null/);
  assert.match(liteAck, /method\(:onSyncAckSent\)/, "queued workouts are sent after the ack");

  const richHandler = annotatedBody(app, "richWorkoutMode", "function handleSyncMessage(");
  assert.match(richHandler, /GymStore\.applyPhoneSync\(message\)/);
  assert.doesNotMatch(richHandler, /planNames|"lite"/);

  const dispatch = annotatedBodyFree(app, "function handlePhonePayload(");
  assert.match(dispatch, /equals\("sync"\)\) \{\s*handleSyncMessage\(message\);/);
  assert.doesNotMatch(dispatch, /applyPhoneSync/);
});

test("96 KiB keeps the shared sync validation and drops only plan application", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const apply = annotatedBody(store, "compactLegacyState", "static function applySyncFromSource(");
  for (const check of ["isValidSyncMessage", "syncRevisionStatus", "BAD_BIND", "PAIR_OLD", "stageSync",
    "rememberSyncRequest", "rememberSyncRevision", "applyValidatedLanguage"]) {
    assert.ok(apply.includes(check), `${check} still runs on the 96 KiB build`);
  }
  assert.doesNotMatch(annotatedBody(store, "compactWorkoutMode96", "static function applyValidatedSync("),
    /plan\s*=|planNames|Storage/);
  assert.match(annotatedBody(store, "compactWorkoutMode96", "static function applyValidatedSync("), /SYNC_OK/);
  assert.match(annotatedBody(store, "compactWorkoutMode96", "static function syncPlanMatchesCurrentState("), /return true;/);
  assert.match(annotatedBody(store, "compactWorkoutMode96", "static function applyDeferredSyncIfIdle("), /return;/);
  // Rich-only plan apply code stays out of the lite build.
  for (const name of ["applyValidatedSync", "syncPlanMatchesCurrentState"]) {
    assert.match(store, new RegExp(`\\(:richWorkoutMode\\)\\s*static function ${name}\\(`));
  }
});

function annotatedBodyFree(source, signature) {
  const at = source.indexOf(signature);
  assert.notEqual(at, -1);
  const start = source.indexOf("{", at);
  let depth = 0;
  for (let i = start; i < source.length; i += 1) {
    if (source[i] === "{") depth += 1;
    if (source[i] === "}" && --depth === 0) return source.slice(start, i + 1);
  }
  return assert.fail("unterminated body");
}

test("lite variants are selected only on the 96 KiB profiles", async () => {
  const jungle = await readFile("garmin/monkey.jungle", "utf8");
  const exclusions = new Map();
  for (const line of jungle.split("\n")) {
    const match = line.match(/^(\S+)\.excludeAnnotations\s*=\s*(.*)$/);
    if (match) exclusions.set(match[1], match[2].split(";"));
  }
  for (const device of liteDevices) {
    const list = exclusions.get(device);
    assert.ok(list, device);
    assert.ok(list.includes("richWorkoutMode"), `${device} drops the rich variant`);
    assert.ok(!list.includes("compactWorkoutMode96"), `${device} keeps the lite variant`);
  }
  const base = jungle.match(/^base\.excludeAnnotations\s*=\s*(.*)$/m)[1].split(";");
  assert.ok(base.includes("compactWorkoutMode96") && !base.includes("richWorkoutMode"));
  for (const [device, list] of exclusions) {
    if (device === "base" || liteDevices.includes(device)) continue;
    assert.ok(list.includes("compactWorkoutMode96"), `${device} must not get the lite variant`);
    assert.ok(!list.includes("richWorkoutMode"), `${device} keeps the rich variant`);
  }
});

test("lite capability marker rides existing fields and is documented", async () => {
  const comm = await readFile("garmin/source/GymComm.mc", "utf8");
  const lite = comm.match(/\(:compactWorkoutMode96\)\s*static var watchVersion = "([^"]+)"/);
  const rich = comm.match(/\(:richWorkoutMode\)\s*static var watchVersion = "([^"]+)"/);
  assert.ok(lite && rich);
  assert.equal(lite[1], `${rich[1]}-lite`);
  assert.ok(Buffer.byteLength(lite[1]) <= 64, "released iOS parsers cap watchVersion at 64 bytes");
  const request = comm.slice(comm.indexOf('"type" => "request_sync"'), comm.indexOf("send(request, callback)"));
  assert.doesNotMatch(request, /"lite"/, "released iOS parsers reject unknown request_sync keys");

  const contract = JSON.parse(await readFile("shared/garmin-lite-mode-v1.json", "utf8"));
  assert.equal(contract.marker.sync_ack.field, "lite");
  assert.equal(contract.marker.sync_ack.value, 1);
  assert.deepEqual(contract.unsupported.slice(0, 1), ["plan_sync"]);
  assert.ok(contract.capabilities.includes("pairing") && contract.capabilities.includes("free_workout"));
  assert.match(contract.sync.phoneBehavior, /binding-only/);
  assert.deepEqual(contract.sync.response.echoes.includes("pairingGeneration"), true);
  assert.match(contract.marker.request_sync.rule, /-lite/);
  const readme = await readFile("garmin/README.md", "utf8");
  assert.match(readme, /## Lite mode \(96 KiB watches\)/);
});
