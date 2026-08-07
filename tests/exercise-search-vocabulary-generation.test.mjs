import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import test from "node:test";
import vm from "node:vm";

const sourcePath = "shared/exercise-search-vocabulary.json";
const generatorPath = "scripts/generate-exercise-search-vocabulary.mjs";
const androidPath = "app/src/main/java/com/example/gymapp/data/catalog/ExerciseSearchVocabulary.generated.kt";
const iosPath = "ios/GymApp-iOS/GymApp/Domain/ExerciseSearchVocabulary.generated.swift";
const pwaPath = "pwa/exercise-search-vocabulary.js";
const versionedPwaPath = "pwa/exercise-search-vocabulary.v1.js";

const [
  vocabulary,
  androidSource,
  iosSource,
  pwaSource,
  versionedPwaSource
] = await Promise.all([
  readFile(sourcePath, "utf8").then(JSON.parse),
  readFile(androidPath, "utf8"),
  readFile(iosPath, "utf8"),
  readFile(pwaPath, "utf8"),
  readFile(versionedPwaPath, "utf8")
]);

test("exercise search vocabulary generated outputs are current", () => {
  const result = spawnSync(process.execPath, [generatorPath, "--check"], {
    cwd: process.cwd(),
    encoding: "utf8"
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /outputs are up to date/i);
});

test("the shared vocabulary covers all catalog exercises and uses bounded reviewed values", () => {
  assert.equal(vocabulary.schemaVersion, 1);
  assert.equal(Object.keys(vocabulary.aliasesByKey).length, 51);
  assert.equal(Object.keys(vocabulary.equipmentIdsByKey).length, 53);
  assert.ok(Object.keys(vocabulary.muscleTermsById).length >= 15);
  assert.ok(Object.keys(vocabulary.equipmentTermsById).length >= 7);

  const equipmentIds = new Set(Object.keys(vocabulary.equipmentTermsById));
  for (const [key, aliases] of Object.entries(vocabulary.aliasesByKey)) {
    assert.ok(vocabulary.equipmentIdsByKey[key], `missing equipment classification for ${key}`);
    assert.ok(aliases.length > 0 && aliases.length <= 64, `invalid alias count for ${key}`);
    assert.ok(aliases.every(alias => alias.length > 0 && alias.length <= 128));
  }
  for (const [key, assignedIds] of Object.entries(vocabulary.equipmentIdsByKey)) {
    assert.ok(assignedIds.length > 0 && assignedIds.length <= 8, `invalid equipment count for ${key}`);
    assert.ok(assignedIds.every(id => equipmentIds.has(id)), `unknown equipment ID for ${key}`);
  }
});

test("muscle and equipment vocabulary supports the reviewed compound searches", () => {
  assert.ok(vocabulary.muscleTermsById.triceps.includes("трицепс"));
  assert.ok(vocabulary.equipmentTermsById.dumbbell.includes("гантели"));
  assert.ok(vocabulary.equipmentIdsByKey.overhead_dumbbell_triceps_extension.includes("dumbbell"));

  const backTerms = ["lats", "upperBack", "lowerBack"].flatMap(id => vocabulary.muscleTermsById[id]);
  assert.ok(backTerms.includes("спина"));
  assert.ok(vocabulary.equipmentTermsById.cable.includes("блок"));
  assert.ok(vocabulary.equipmentIdsByKey.lat_pulldown.includes("cable"));
  assert.ok(vocabulary.equipmentIdsByKey.seated_cable_row.includes("cable"));
});

test("platform outputs expose one consistent generated API", () => {
  assert.match(androidSource, /object ExerciseSearchVocabulary/);
  assert.match(androidSource, /val aliasesByKey: Map<String, List<String>>/);
  assert.match(androidSource, /val equipmentIdsByKey: Map<String, Set<String>>/);
  assert.match(iosSource, /public enum ExerciseSearchVocabulary/);
  assert.match(iosSource, /public static let aliasesByKey: \[String: \[String\]\]/);
  assert.match(pwaSource, /globalThis\.GymExerciseSearchVocabulary = deepFreeze/);
  assert.equal(versionedPwaSource, pwaSource);

  for (const aliases of Object.values(vocabulary.aliasesByKey)) {
    for (const alias of aliases) {
      assert.ok(androidSource.includes(JSON.stringify(alias)), `Android output is missing ${alias}`);
      assert.ok(iosSource.includes(JSON.stringify(alias)), `iOS output is missing ${alias}`);
    }
  }

  const context = vm.createContext({});
  vm.runInContext(pwaSource, context);
  const generatedPwaVocabulary = JSON.parse(JSON.stringify(context.GymExerciseSearchVocabulary));
  assert.deepEqual(generatedPwaVocabulary, vocabulary);
  assert.equal(vm.runInContext("Object.isFrozen(GymExerciseSearchVocabulary.aliasesByKey.bench_press)", context), true);
});
