import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const contract = JSON.parse(
  readFileSync(new URL("../shared/display-name-v1.json", import.meta.url), "utf8")
);

const codePoints = (value) => [...value].length;

// JS mirror of the static rules in public.safe_leaderboard_display_name
// (supabase/migrations/20260711084556_create_leaderboard_public.sql). The dynamic
// leaderboard_blocked_terms table is intentionally not mirrored.
function serverAccepts(raw) {
  if (raw === null || /[\p{Cc}]/u.test(raw)) return false;
  if (/[​‌‍﻿]/u.test(raw)) return false;
  const cleaned = raw.trim().replace(/\s+/gu, " ");
  const length = codePoints(cleaned);
  if (length < 2 || length > 40) return false;
  if (!/[\p{L}\p{Nd}]/u.test(cleaned)) return false;
  if (cleaned.includes("@")) return false;
  if (
    /(https?:\/\/|www[.]|discord[.]gg|t[.]me\/|[\p{L}\p{Nd}_-]+[.](com|net|org|io|gg)(\/|$))/iu.test(
      cleaned
    )
  ) {
    return false;
  }
  if (cleaned.replace(/[^0-9]/g, "").length >= 7) return false;
  return true;
}

test("fixture is well formed", () => {
  assert.equal(contract.version, 1);
  assert.equal(contract.minCodePoints, 2);
  assert.equal(contract.maxCodePoints, 32);
  assert.ok(contract.cases.length >= 40);
  const ids = new Set(contract.cases.map((item) => item.id));
  assert.equal(ids.size, contract.cases.length);
  for (const item of contract.cases) {
    if (item.normalized === null) {
      assert.ok(["length", "characters", "server"].includes(item.reason), item.id);
    } else {
      assert.equal(item.reason, undefined, item.id);
    }
  }
});

test("every accepted name satisfies the server static rules", () => {
  for (const item of contract.cases.filter((entry) => entry.normalized !== null)) {
    const name = item.normalized;
    assert.equal(name, name.trim().replace(/\s+/gu, " "), `${item.id} is normalized`);
    const length = codePoints(name);
    assert.ok(length >= 2 && length <= contract.maxCodePoints, `${item.id} length`);
    assert.ok(serverAccepts(name), `${item.id} must pass the server rules`);
    assert.ok(serverAccepts(item.input), `${item.id} raw input must pass the server rules`);
  }
});

test("rejected names marked as server rules fail the server static rules", () => {
  for (const item of contract.cases.filter((entry) => entry.reason === "server")) {
    assert.equal(serverAccepts(item.input), false, `${item.id} must be rejected by the server`);
  }
});

test("accepted names are exactly the trimmed, collapsed input", () => {
  for (const item of contract.cases.filter((entry) => entry.normalized !== null)) {
    assert.equal(item.normalized, item.input.replace(/ /gu, " ").trim().replace(/\s+/gu, " "), item.id);
  }
});

test("draft outputs that survive validation also pass the server rules", () => {
  for (const item of contract.draftCases) {
    const name = item.draft.trim();
    if (codePoints(name) >= 2) {
      assert.ok(serverAccepts(name), `${item.id} draft output must pass the server rules`);
    }
  }
});
