import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const CURRENT_BUNDLE_NAMES = ["app.js", "app.v80.js"];
const currentBundles = CURRENT_BUNDLE_NAMES.map(filename => ({
  filename,
  source: readFileSync(new URL(`../pwa/${filename}`, import.meta.url), "utf8")
}));

function uidSourceFrom(source) {
  const start = source.indexOf("function uid() {");
  const end = source.indexOf("\nfunction route() {", start);
  assert.ok(start >= 0 && end > start, "uid() must remain directly before route()");
  return source.slice(start, end);
}

function loadUid(source, crypto) {
  const context = { window: { crypto } };
  vm.runInNewContext(`${uidSourceFrom(source)}\nglobalThis.__uid = uid;`, context);
  return context.__uid;
}

test("current PWA bundles use one byte-identical secure numeric ID generator", () => {
  for (const bundle of currentBundles.slice(1)) {
    assert.equal(bundle.source, currentBundles[0].source, bundle.filename);
  }

  for (const { filename, source } of currentBundles) {
    const uidSource = uidSourceFrom(source);
    assert.match(uidSource, /crypto[\s\S]*getRandomValues/);
    assert.doesNotMatch(uidSource, /Math\.random|Date\.now/);

    const samples = [
      [0x001fffff, 0xffffffff],
      [0x00000000, 0x00000001]
    ];
    let callCount = 0;
    const uid = loadUid(source, {
      getRandomValues(words) {
        const [high, low] = samples[callCount];
        callCount += 1;
        words[0] = high;
        words[1] = low;
        return words;
      }
    });

    const values = [uid(), uid()];
    assert.deepEqual(values, [Number.MAX_SAFE_INTEGER, 1], filename);
    assert.equal(callCount, 2, filename);
    for (const value of values) {
      assert.equal(Number.isSafeInteger(value), true, filename);
      assert.ok(value > 0, filename);
      assert.ok(String(value).length <= 16, filename);
    }
  }
});

test("numeric ID generation fails closed without usable Web Crypto", () => {
  for (const { filename, source } of currentBundles) {
    for (const crypto of [undefined, {}, { getRandomValues: null }]) {
      const uid = loadUid(source, crypto);
      assert.throws(
        () => uid(),
        /Secure numeric ID generation is unavailable/,
        filename
      );
    }

    let callCount = 0;
    const zeroOnlyUid = loadUid(source, {
      getRandomValues(words) {
        callCount += 1;
        words.fill(0);
        return words;
      }
    });
    assert.throws(() => zeroOnlyUid(), /Secure numeric ID generation failed/, filename);
    assert.equal(callCount, 8, filename);
  }
});
