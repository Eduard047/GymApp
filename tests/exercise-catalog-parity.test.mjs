import assert from "node:assert/strict";
import test from "node:test";
import {
  parseAndroidCatalog,
  parseAndroidExactMuscleMap,
  parseAndroidProgramming,
  parseIosCatalog,
  parseIosExactMuscleMap,
  parseIosProgramming
} from "./helpers/exercise-sources.mjs";

const android = parseAndroidCatalog();
const ios = parseIosCatalog();

test("both catalogs expose the same non-trivial key set", () => {
  assert.ok(Object.keys(android).length >= 40, "Android catalog parsed too few entries");
  assert.deepEqual(Object.keys(ios).sort(), Object.keys(android).sort());
});

test("catalog entries match per key: names, muscle order, aliases, seed version", () => {
  for (const key of Object.keys(android)) {
    const a = android[key];
    const i = ios[key];
    assert.ok(i, `${key} missing on iOS`);
    assert.equal(i.nameEn, a.nameEn, `${key} nameEn`);
    assert.equal(i.nameUk, a.nameUk, `${key} nameUk`);
    assert.deepEqual(i.muscleIds, a.muscleIds, `${key} muscle ids (ordered)`);
    assert.deepEqual([...i.aliases].sort(), [...a.aliases].sort(), `${key} legacy aliases`);
    assert.equal(i.introducedInSeedVersion, a.introducedInSeedVersion, `${key} introducedInSeedVersion`);
  }
});

test("programming metadata matches per key on both platforms", () => {
  const androidProgramming = parseAndroidProgramming();
  const iosProgramming = parseIosProgramming();
  assert.deepEqual(Object.keys(iosProgramming).sort(), Object.keys(androidProgramming).sort());
  for (const key of Object.keys(androidProgramming)) {
    assert.deepEqual(iosProgramming[key], androidProgramming[key], `${key} programming`);
  }
  for (const key of Object.keys(android)) {
    assert.ok(androidProgramming[key], `${key} has no programming metadata`);
  }
});

test("exact muscle maps have the same keys and weights", () => {
  const androidMap = parseAndroidExactMuscleMap();
  const iosMap = parseIosExactMuscleMap();
  assert.ok(Object.keys(androidMap).length >= 70, "Android exact map parsed too few entries");
  assert.deepEqual(Object.keys(iosMap).sort(), Object.keys(androidMap).sort());
  for (const name of Object.keys(androidMap)) {
    assert.deepEqual(iosMap[name], androidMap[name], `${name} weights`);
    assert.deepEqual(Object.keys(iosMap[name]), Object.keys(androidMap[name]), `${name} muscle order`);
  }
});
