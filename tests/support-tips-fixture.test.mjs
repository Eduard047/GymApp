import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const fixture = JSON.parse(
  await readFile("shared/support-tips-v1.json", "utf8"),
);
const EXPECTED_KEYS = [
  "tip_1",
  "tip_2",
  "tip_3",
  "tip_5",
  "tip_10",
  "tip_20",
];
const IOS_PREFIX = "com.setforge.gymapp.ios.";

test("support tips fixture has the six tips in order", () => {
  assert.equal(fixture.version, 1);
  assert.equal(fixture.tips.length, 6);
  assert.deepEqual(
    fixture.tips.map((tip) => tip.key),
    EXPECTED_KEYS,
  );
});

test("support tips fixture ids are unique and well formed", () => {
  const android = fixture.tips.map((tip) => tip.android);
  const ios = fixture.tips.map((tip) => tip.ios);
  assert.equal(new Set(android).size, android.length);
  assert.equal(new Set(ios).size, ios.length);
  for (const id of android) {
    assert.match(id, /^[a-z0-9_.]+$/);
  }
  for (const id of ios) {
    assert.ok(id.startsWith(IOS_PREFIX), id);
    assert.match(id.slice(IOS_PREFIX.length), /^[a-z0-9]+$/);
  }
});

test("support tips fixture amounts are ascending USD prices", () => {
  const amounts = fixture.tips.map((tip) => {
    assert.match(tip.usd, /^\d+\.\d{2}$/);
    return Number(tip.usd);
  });
  assert.deepEqual(
    amounts,
    [...amounts].sort((a, b) => a - b),
  );
});

test("Android billing constants are in the shared fixture order", async () => {
  const source = await readFile(
    "app/src/main/java/com/example/gymapp/billing/SupportTipModel.kt",
    "utf8",
  );
  const ids = [...source.matchAll(/"(support_tip_[a-z0-9_]+)"/g)].map(
    (match) => match[1],
  );
  assert.deepEqual(
    ids,
    fixture.tips.map((tip) => tip.android),
  );
});
