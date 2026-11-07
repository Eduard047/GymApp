import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const fixture = JSON.parse(readFileSync("shared/live-social-names-v1.json", "utf8"));

// Mirror of gymapp_private.social_name_is_safe (supabase/migrations/20261029202651_*): fixed code-point list.
const rejectedPoints = new Set([
  173, 1564, 1757, 1807, 2192, 2193, 2274, 6158, 8203, 8204, 8205, 8206, 8207, 8232, 8233,
  8234, 8235, 8236, 8237, 8238, 8288, 8289, 8290, 8291, 8292, 8294, 8295, 8296, 8297, 8298,
  8299, 8300, 8301, 8302, 8303, 65279, 65529, 65530, 65531, 69821, 69837, 113824, 113825,
  113826, 113827, 119155, 119156, 119157, 119158, 119159, 119160, 119161, 119162, 917505
]);
const rejectedRanges = [[0, 31], [127, 159], [1536, 1541], [6068, 6069], [8288, 8303], [78896, 78943], [917536, 917631]];

function serverAccepts(text, limits) {
  const points = [...text].map(char => char.codePointAt(0));
  if (text !== text.replace(/^ +| +$/g, "")) return false;
  if (points.length < 1 || points.length > limits.maxCodePoints) return false;
  if (Buffer.byteLength(text, "utf8") > limits.maxUtf8Bytes) return false;
  return !points.some(point =>
    rejectedPoints.has(point) || rejectedRanges.some(([low, high]) => point >= low && point <= high));
}

function build(vector) {
  const repeat = vector.repeat;
  if (!repeat) return vector.text;
  return (repeat.prefix ?? "") + repeat.unit.repeat(repeat.count) + (repeat.suffix ?? "");
}

test("live/social names fixture is well formed", () => {
  assert.equal(fixture.version, 1);
  const ids = new Set(fixture.vectors.map(vector => vector.id));
  assert.equal(ids.size, fixture.vectors.length, "duplicate vector ids");
  assert.ok(fixture.vectors.some(vector => vector.valid) && fixture.vectors.some(vector => !vector.valid));
  for (const vector of fixture.vectors) {
    assert.ok(vector.kinds.length > 0 && vector.kinds.every(kind => kind in fixture.limits), vector.id);
    assert.ok(("text" in vector) !== ("repeat" in vector), `${vector.id} needs text xor repeat`);
  }
});

test("fixture verdicts equal what the server name rule accepts", () => {
  for (const vector of fixture.vectors) {
    for (const kind of vector.kinds) {
      assert.equal(
        serverAccepts(build(vector), fixture.limits[kind]),
        vector.valid,
        `${vector.id} as ${kind}`
      );
    }
  }
});
