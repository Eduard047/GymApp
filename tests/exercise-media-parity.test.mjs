import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const catalogSource = await readFile("pwa/app.js", "utf8");
const serviceWorkerSource = await readFile("pwa/sw.js", "utf8");
const indexSource = await readFile("pwa/index.html", "utf8");
const sourceRegistry = JSON.parse(await readFile("docs/exercise-media-sources.json", "utf8"));

function quotedValues(source) {
  return [...source.matchAll(/"([a-z0-9_]+)"/g)].map(match => match[1]);
}

function catalogKeys() {
  const block = catalogSource.match(/const builtInExerciseCatalog = \[([\s\S]*?)\n\];/);
  assert.ok(block, "PWA built-in exercise catalog was not found");
  return [...block[1].matchAll(/\{ key: "([a-z0-9_]+)"/g)].map(match => match[1]);
}

function pwaAppMediaKeys() {
  const block = catalogSource.match(/const bundledExerciseMediaKeys = new Set\(\[([\s\S]*?)\]\);/);
  assert.ok(block, "PWA bundled media allowlist was not found");
  return quotedValues(block[1]);
}

function serviceWorkerMediaKeys() {
  const block = serviceWorkerSource.match(/const EXERCISE_MEDIA_KEYS = \[([\s\S]*?)\];/);
  assert.ok(block, "service-worker media allowlist was not found");
  return quotedValues(block[1]);
}

function jpegDimensions(buffer) {
  assert.equal(buffer.readUInt16BE(0), 0xffd8, "asset must be a JPEG");
  const startOfFrameMarkers = new Set([
    0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
    0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf
  ]);
  let offset = 2;
  while (offset + 8 < buffer.length) {
    if (buffer[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = buffer[offset + 1];
    if (startOfFrameMarkers.has(marker)) {
      return {
        height: buffer.readUInt16BE(offset + 5),
        width: buffer.readUInt16BE(offset + 7)
      };
    }
    if (marker === 0xd8 || marker === 0xd9 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    const segmentLength = buffer.readUInt16BE(offset + 2);
    assert.ok(segmentLength >= 2, "invalid JPEG segment length");
    offset += 2 + segmentLength;
  }
  assert.fail("JPEG dimensions were not found");
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

test("every built-in exercise has two identical 480x320 assets on Android, iOS, and PWA", async () => {
  const keys = catalogKeys();
  assert.equal(keys.length, 53);
  assert.equal(new Set(keys).size, keys.length);

  const roots = [
    "app/src/main/assets/exercise-media",
    "ios/GymApp-iOS/GymApp/Resources/ExerciseMedia",
    "pwa/exercise-media"
  ];
  for (const key of keys) {
    for (const phase of [0, 1]) {
      const buffers = await Promise.all(
        roots.map(root => readFile(`${root}/${key}_${phase}.jpg`))
      );
      for (const buffer of buffers) {
        assert.deepEqual(jpegDimensions(buffer), { width: 480, height: 320 });
      }
      assert.equal(sha256(buffers[0]), sha256(buffers[1]), `${key}_${phase} differs on iOS`);
      assert.equal(sha256(buffers[0]), sha256(buffers[2]), `${key}_${phase} differs on PWA`);
    }
  }
});

test("media source registry and both PWA allowlists cover the exact catalog", () => {
  const expected = catalogKeys().toSorted();
  const publicSources = Object.keys(sourceRegistry.exercises);
  const generatedSources = Object.keys(sourceRegistry.generatedExercises);
  assert.deepEqual(publicSources.filter(key => generatedSources.includes(key)), []);
  assert.deepEqual([...publicSources, ...generatedSources].toSorted(), expected);
  assert.deepEqual(pwaAppMediaKeys().toSorted(), expected);
  assert.deepEqual(serviceWorkerMediaKeys().toSorted(), expected);
  assert.equal(sourceRegistry.exercises.hip_adduction, "Thigh_Adductor");
});

test("the active PWA bundle contains the reviewed coach and media code", async () => {
  const version = indexSource.match(/<script src="\.\/(app\.v\d+\.js)" defer><\/script>/)?.[1];
  assert.ok(version, "versioned PWA app bundle was not found in index.html");
  const activeBundle = await readFile(`pwa/${version}`);
  const sourceBundle = await readFile("pwa/app.js");
  assert.equal(sha256(activeBundle), sha256(sourceBundle));
  assert.match(serviceWorkerSource, new RegExp(`"\\./${version.replace(".", "\\.")}"`));
});
