import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import plugin from "@markw65/prettier-plugin-monkeyc";
import { splitGarminStoreStatics } from "../scripts/lib/garmin-store-statics.mjs";

const source = await readFile("garmin/source/GymStore.mc", "utf8");
const names = new Set([
  "sameOptionalText", "sameOptionalBoolean", "sameTextArray", "sameNumericArray",
  "utf8Bytes", "isBoundedText", "counterToLong", "isValidWeight", "isValidReps",
  "isValidSetInterval", "isValidSetIntervalsList", "areSetIntervalsConsistent",
  "isValidPlannedSetCount", "isValidExactPlannedProgress", "isBoundedNumber",
  "isOptionalBoundedNumber", "isBoundedInteger", "isOptionalBoundedInteger",
  "isNumeric", "containsName"
]);
const members = plugin.parsers.monkeyc.parse(source).body.find(n => n.type === "ClassDeclaration").body.body.map(n => n.item);
const methods = members.filter(n => n.type === "FunctionDeclaration" && names.has(n.id.name))
  .map(n => source.slice(n.start, n.end)).join("\n");
const full = `using Toybox.Lang;
class GymStore {
${Array.from({ length: 234 }, (_, i) => `static var value${i} = 0;`).join("\n")}
static const maxWeight = 1000000.0;
static const maxReps = 10000;
static const maxPlanSets = 60;
static const maxWorkoutSets = 60;
${methods}
static function save(value) { return isBoundedInteger(value, 0, 60); }
}`;

async function fixture(store, consumer, run) {
  const root = await mkdtemp(path.join(os.tmpdir(), "gymapp-store-statics-"));
  try {
    const group = path.join(root, "group", "source");
    await mkdir(group, { recursive: true });
    await writeFile(path.join(group, "GymStore.mc"), store);
    await writeFile(path.join(group, "Consumer.mc"), consumer);
    await run(root, group);
  } finally { await rm(root, { recursive: true, force: true }); }
}

test("compact Garmin storage sources remain untouched", async () => {
  const compact = "class GymStore { static function save() { return true; } }";
  await fixture(compact, "", async (root, group) => {
    assert.equal(await splitGarminStoreStatics(root), 0);
    assert.equal(await readFile(path.join(group, "GymStore.mc"), "utf8"), compact);
    assert.equal((await readdir(group)).length, 2);
  });
});

test("oversized Garmin storage retains validation bodies and qualifies both callers", async () => {
  await fixture(full, "function check(v) { return GymStore.isBoundedInteger(v, 1, 60); }", async (root, group) => {
    assert.equal(await splitGarminStoreStatics(root), 1);
    const store = await readFile(path.join(group, "GymStore.mc"), "utf8");
    const values = await readFile(path.join(group, "GymStoreValues.mc"), "utf8");
    const consumer = await readFile(path.join(group, "Consumer.mc"), "utf8");
    assert.match(store, /static function save\(value\) \{ return GymStoreValues.isBoundedInteger\(value, 0, 60\); \}/);
    assert.match(consumer, /GymStoreValues.isBoundedInteger\(v, 1, 60\)/);
    assert.match(values, /value >= minimum && value <= maximum/);
    assert.match(values, /numeric == numeric && numeric >= 0\.0 && numeric <= GymStore.maxWeight/);
    assert.match(values, /zoneSeconds <= value\[1\] - value\[0\]/);
    assert.match(values, /interval\[1\] > durationSeconds/);
    assert.equal(plugin.parsers.monkeyc.parse(values).body.filter(n => n.type === "ModuleDeclaration").length, 1);
    for (const name of names) {
      assert.doesNotMatch(store, new RegExp(`function ${name}\\(`));
      assert.match(values, new RegExp(`function ${name}\\(`));
    }
    assert.equal(await splitGarminStoreStatics(root), 0);
  });
});

test("ambiguous and reflective Garmin check references fail before source writes", async () => {
  for (const consumer of [
    "function check(GymStore) { return GymStore.isNumeric(1); }",
    "function check() { return GymStore.method(:isNumeric); }",
    'function check() { return "isNumeric"; }'
  ]) await fixture(full, consumer, async (root, group) => {
    await assert.rejects(splitGarminStoreStatics(root), /cannot be relocated/);
    assert.equal(await readFile(path.join(group, "GymStore.mc"), "utf8"), full);
    assert.equal((await readdir(group)).length, 2);
  });
});
