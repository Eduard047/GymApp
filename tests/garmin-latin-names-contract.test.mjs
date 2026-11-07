import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import test from "node:test";

const fixture = JSON.parse(await readFile("shared/garmin-latin-names-v1.json", "utf8"));
const kotlinPath = "app/src/main/java/com/example/gymapp/garmin/GarminLatinNames.kt";
const kotlin = await readFile(kotlinPath, "utf8");
const isAscii = (value) => /^[\x20-\x7E]*$/.test(value);

function between(source, begin, end) {
  const start = source.indexOf(begin);
  const stop = source.indexOf(end);
  assert.ok(start >= 0 && stop > start, `${begin}/${end} markers are missing`);
  return source.slice(start + begin.length, stop);
}

test("fixture shape", () => {
  assert.equal(fixture.version, 1);
  assert.equal(fixture.maxNameLength, 160);
  assert.equal(fixture.fallbackName, "Exercise");
  assert.equal(fixture.watchLanguage, "en");
  assert.equal(Object.keys(fixture.transliteration).length, 35);
  for (const [cyrillic, latin] of Object.entries(fixture.transliteration)) {
    assert.equal([...cyrillic].length, 1, `${cyrillic} must be one character`);
    assert.ok(cyrillic === cyrillic.toLowerCase(), `${cyrillic} must be lowercase`);
    assert.match(latin, /^[a-z]+$/);
  }
  assert.ok(fixture.assignCases.length >= 10);
  assert.ok(fixture.invertCases.length >= 5);
  const ids = [...fixture.assignCases, ...fixture.invertCases].map((item) => item.id);
  assert.equal(new Set(ids).size, ids.length, "case ids must be unique");
  for (const item of fixture.assignCases) {
    const expected = Object.values(item.expected);
    for (const latin of expected) assert.ok(isAscii(latin) && latin.length >= 1 && latin.length <= 160, `${item.id}: ${latin}`);
    const lowered = expected.map((latin) => latin.toLowerCase());
    assert.equal(new Set(lowered).size, lowered.length, `${item.id}: latin names must be unique case-insensitively`);
    for (const raw of item.names) assert.ok(raw.trim() in item.expected, `${item.id}: ${raw} has no expectation`);
    for (const entry of item.newEntries) assert.equal(item.expected[entry.raw], entry.latin, `${item.id}: new entry mismatch`);
  }
  for (const item of fixture.invertCases) {
    assert.ok(item.expected === null || typeof item.expected === "string");
  }
});

test("the Kotlin transliteration table equals the fixture", () => {
  const table = new Map(
    [...between(kotlin, "// TABLE-BEGIN", "// TABLE-END").matchAll(/'(.)' to "([a-z]+)"/gu)].map((m) => [m[1], m[2]])
  );
  assert.deepEqual(Object.fromEntries(table), fixture.transliteration);
  const dropped = /DROPPED = "([^"]*)"/u.exec(between(kotlin, "// DROPPED-BEGIN", "// DROPPED-END"));
  assert.ok(dropped, "DROPPED constant is missing");
  assert.deepEqual([...dropped[1]].sort(), [...fixture.droppedCharacters].sort());
  assert.match(kotlin, /const val MAX_LENGTH = 160/);
  assert.match(kotlin, /const val FALLBACK_NAME = "Exercise"/);
  assert.match(kotlin, /GARMIN_WATCH_LANGUAGE_TAG = "en"/);
});

// TODO(T121 step 2): the Swift table lives in ios/GymApp-iOS/GymApp/Services/GarminLatinNames.swift
// (path chosen by step 2). Once the file exists this test compares its table with the fixture too;
// until then it is skipped so the Android-only step stays green.
const swiftPath = "ios/GymApp-iOS/GymApp/Services/GarminLatinNames.swift";
test("the Swift transliteration table equals the fixture", { skip: !existsSync(swiftPath) }, async () => {
  const swift = await readFile(swiftPath, "utf8");
  const table = new Map(
    [...between(swift, "// TABLE-BEGIN", "// TABLE-END").matchAll(/"(.)":\s*"([a-z]+)"/gu)].map((m) => [m[1], m[2]])
  );
  assert.deepEqual(Object.fromEntries(table), fixture.transliteration);
  const dropped = /dropped = "([^"]*)"/u.exec(between(swift, "// DROPPED-BEGIN", "// DROPPED-END"));
  assert.ok(dropped, "dropped constant is missing");
  assert.deepEqual([...dropped[1]].sort(), [...fixture.droppedCharacters].sort());
});
