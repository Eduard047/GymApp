import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { parseAndroidCatalog, parseIosCatalog } from "./helpers/exercise-sources.mjs";

const fixture = JSON.parse(readFileSync("shared/muscle-contributions-v1.json", "utf8"));
const names = new Set(fixture.cases.map(item => item.name));

test("muscle contribution fixture is well formed", () => {
  assert.equal(fixture.version, 1);
  assert.equal(names.size, fixture.cases.length, "duplicate case names");
  for (const item of fixture.cases) {
    for (const [muscle, weight] of Object.entries(item.contributions)) {
      assert.match(muscle, /^[a-zA-Z]+$/, `${item.name} muscle id`);
      assert.ok(weight > 0 && weight <= 1, `${item.name} ${muscle} weight`);
    }
  }
});

test("fixture covers every catalog name and legacy alias on both platforms", () => {
  for (const catalog of [parseAndroidCatalog(), parseIosCatalog()]) {
    for (const entry of Object.values(catalog)) {
      for (const name of [entry.nameEn, entry.nameUk, ...entry.aliases]) {
        assert.ok(names.has(name), `fixture is missing "${name}" (${entry.key})`);
        const contributions = fixture.cases.find(item => item.name === name).contributions;
        assert.ok(Object.keys(contributions).length > 0, `"${name}" has no contributions`);
      }
    }
  }
});

test("fixture keeps custom-name heuristic cases", () => {
  for (const name of ["Cable Fly", "Leg Curl", "Хаммер", "Russian Twist", "Sumo Deadlift", "Нахили вбік", "Assisted Dip"]) {
    assert.ok(names.has(name), `fixture is missing custom case "${name}"`);
  }
  assert.ok(fixture.cases.length >= 100);
});
