import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contract = JSON.parse(await readFile("shared/garmin-memory-tiers-v1.json", "utf8"));
const store = await readFile("garmin/source/GymStore.mc", "utf8");
const app = await readFile("garmin/source/GymApp.mc", "utf8");
const comm = await readFile("garmin/source/GymComm.mc", "utf8");
const jungle = await readFile("garmin/monkey.jungle", "utf8");

// Annotation set required to select each tier's limit constants.
const tierAnnotations = {
  wide: ["mem128Wide"],
  fr55: ["mem128", "fr55Memory"],
};
const limitConsts = {
  planSets: "memPlanSets",
  planChars: "memPlanChars",
  catalogEntries: "memCatalogEntries",
  catalogChars: "memCatalogChars",
};

function sameSet(a, b) {
  return [...a].sort().join(",") === [...b].sort().join(",");
}

function constValue(annotations, name) {
  const re = /\(:([^)]*)\)\s*static\s+const\s+(\w+)\s*=\s*(\d+)\s*;/g;
  for (const match of store.matchAll(re)) {
    const found = match[1].split(",").map((v) => v.trim().replace(/^:/, ""));
    if (match[2] === name && sameSet(found, annotations)) return Number(match[3]);
  }
  assert.fail(`Missing const ${name} for (${annotations.join(", ")})`);
}

function jungleDevices(excludedAnnotation) {
  // Devices whose excludeAnnotations list names the annotation.
  const devices = [];
  for (const line of jungle.split(/\r?\n/)) {
    const match = line.match(/^\s*(\w+)\.excludeAnnotations\s*=\s*(.*)$/);
    if (!match || match[1] === "base") continue;
    if (match[2].split(";").map((v) => v.trim()).includes(excludedAnnotation)) devices.push(match[1]);
  }
  return devices;
}

test("contract names exactly two tiers with the expected shape", () => {
  assert.equal(contract.version, 1);
  assert.deepEqual(Object.keys(contract.tiers).sort(), ["fr55", "wide"]);
  for (const tier of Object.values(contract.tiers)) {
    assert.deepEqual(Object.keys(tier.limits).sort(), Object.keys(limitConsts).sort());
    assert.ok(tier.devices.length > 0);
  }
});

for (const [tier, annotations] of Object.entries(tierAnnotations)) {
  test(`${tier} limits in the contract equal the GymStore constants`, () => {
    for (const [key, name] of Object.entries(limitConsts)) {
      assert.equal(contract.tiers[tier].limits[key], constValue(annotations, name), `${tier}.${key}`);
    }
  });
}

test("jungle membership matches the contract device lists", () => {
  const all = Object.values(contract.tiers).flatMap((tier) => tier.devices);
  assert.equal(new Set(all).size, all.length, "a device appears in two tiers");
  // Devices built with the 128 KiB sync code are those that do not exclude it.
  assert.ok(sameSet(jungleDevices("noMem128"), all));
  // Wide devices are the 128 KiB devices that do not exclude mem128Wide.
  const wideExcluded = jungleDevices("mem128Wide");
  assert.ok(sameSet(jungleDevices("noMem128").filter((d) => !wideExcluded.includes(d)), contract.tiers.wide.devices));
  // The former tight group now builds the 96 KiB lite profile: no mem128 code.
  for (const device of ["enduro", "fenix6", "fenix6s", "fr245", "venusq"]) {
    assert.ok(jungleDevices("mem128").includes(device), `${device} must not compile mem128 code`);
    assert.ok(!jungleDevices("noMem128").includes(device));
  }
  // fr55 is the only 128 KiB device that takes the fr55 limits.
  const fr55Devices = jungleDevices("notFr55Memory");
  assert.ok(sameSet(fr55Devices, contract.tiers.fr55.devices));
  // The base profile excludes both annotations so lighter builds drop the code.
  const base = jungle.match(/^\s*base\.excludeAnnotations\s*=\s*(.*)$/m)[1].split(";").map((v) => v.trim());
  assert.ok(base.includes("mem128") && base.includes("mem128Wide"));
});

test("watchVersion suffixes match the contract and stay phone-parsable", () => {
  const suffixes = contract.marker.request_sync.suffixes;
  const found = (annotations) => {
    const re = /\(:([^)]*)\)\s*static\s+var\s+watchVersion\s*=\s*"([^"]*)"\s*;/g;
    for (const match of comm.matchAll(re)) {
      const names = match[1].split(",").map((v) => v.trim().replace(/^:/, ""));
      if (sameSet(names, annotations)) return match[2];
    }
    assert.fail(`Missing watchVersion for (${annotations.join(", ")})`);
  };
  const c128 = found(["mem128", "notFr55Memory"]);
  const fr55 = found(["mem128", "fr55Memory"]);
  assert.ok(c128.endsWith(suffixes.wide));
  assert.ok(fr55.endsWith(suffixes.fr55));
  assert.equal(suffixes.wide, "-c128");
  assert.equal(suffixes.fr55, "-fr55");
  for (const version of [c128, fr55]) {
    assert.ok(version.length <= 32, `${version} is longer than 32 characters`);
    assert.match(version, /^[A-Za-z0-9._+-]+$/);
  }
});

test("request_sync gains no new key", () => {
  const start = comm.indexOf('"watchVersion" =>');
  assert.notEqual(start, -1);
  const open = comm.lastIndexOf("{", start);
  const close = comm.indexOf("}", start);
  const keys = [...comm.slice(open, close).matchAll(/"(\w+)"\s*=>/g)].map((m) => m[1]);
  assert.ok(keys.includes("watchVersion"));
  assert.ok(!keys.includes("reason") && !keys.includes("tier") && !keys.includes("memory"));
  assert.ok(keys.length <= 8, `request_sync has ${keys.length} keys: ${keys.join(", ")}`);
});

test("the 128 KiB sync handler refuses oversized plans with the contract reason", () => {
  const reason = contract.marker.sync_ack.value;
  assert.equal(reason, "plan_too_large");
  const at = app.search(/\(:mem128\)\s*function\s+handleSyncMessage\s*\(/);
  assert.notEqual(at, -1);
  const handler = app.slice(at, app.indexOf("\n    }\n", at));
  assert.match(handler, /syncFitsMemory\s*\(\s*message\s*\)/);
  assert.match(handler, new RegExp(`reason\\s*=\\s*"${reason}"`));
  for (const key of ["planNames", "planWeights", "planReps", "exercises"]) {
    assert.match(handler, new RegExp(`message\\.put\\(\\s*"${key}"\\s*,\\s*\\[\\s*\\]\\s*\\)`));
  }
  assert.match(handler, /trimSyncCatalog\s*\(\s*message\s*\)/);
  assert.match(handler, /sendSyncAck\(\s*message\s*,\s*reason\s*==\s*null\s*&&\s*applied\s*,\s*reason\s*\)/);
  assert.ok(handler.indexOf("syncFitsMemory") < handler.indexOf("applyPhoneSync"));
  assert.match(app, /function\s+sendSyncAck\s*\(\s*message\s*,\s*applied\s*,\s*reason\s*\)/);
});

test("cold-start purge follows the contract", () => {
  const cold = contract.coldStart;
  assert.equal(cold.marker, "mem128SizedV1");
  const at = store.search(/function\s+purgeOversizedPlanState128\s*\(/);
  assert.notEqual(at, -1);
  const body = store.slice(at, store.indexOf("\n    }\n", at));
  assert.match(body, /Storage\.getValue\(\s*"mem128SizedV1"\s*\)/);
  assert.match(body, /Storage\.setValue\(\s*"mem128SizedV1"\s*,/);
  const deleted = [...body.matchAll(/Storage\.deleteValue\(\s*"(\w+)"\s*\)/g)].map((m) => m[1]);
  assert.deepEqual(deleted.sort(), [...cold.deletes].sort());
  assert.match(body, /activeWorkoutV1/);
  assert.match(body, /preparedWorkoutV1/);
  assert.ok(!/queue/i.test(body.replace(/\/\/.*$/gm, "")), "the purge must not touch queued workouts");
});

test("both phones honour the plan_too_large reason", async () => {
  const reason = contract.marker.sync_ack.value;
  const android = await readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncSecurity.kt", "utf8");
  const ios = await readFile("ios/GymApp-iOS/GymApp/Services/GarminPhoneSyncService.swift", "utf8");
  assert.match(android, new RegExp(`GARMIN_PLAN_TOO_LARGE_REASON\\s*=\\s*"${reason}"`));
  assert.match(android, new RegExp(`fun\\s+${contract.phones.android.function}\\b`));
  assert.match(android, /command\["applied"\]\s*!=\s*false/);
  assert.match(ios, new RegExp(`planTooLargeReason\\s*=\\s*"${reason}"`));
  assert.match(ios, new RegExp(`func\\s+${contract.phones.ios.function}\\b`));
  assert.match(ios, /reason\s*==\s*planTooLargeReason/);
  assert.match(ios, /boolean\(message\["applied"\]\)\s*==\s*false/);
  assert.ok(reason.length <= 32);
});
