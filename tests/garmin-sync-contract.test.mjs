import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contract = JSON.parse(await readFile("shared/garmin-sync-v1.json", "utf8"));
const store = await readFile("garmin/source/GymStore.mc", "utf8");

function extractFunction(source, name, annotation) {
  const head = annotation
    ? new RegExp(`\\(:${annotation}[^)]*\\)\\s*static function ${name}\\(`)
    : new RegExp(`static function ${name}\\(`);
  const match = head.exec(source);
  assert.ok(match, `${name} (${annotation ?? "any"}) is missing from GymStore.mc`);
  let depth = 0;
  let started = false;
  for (let i = match.index; i < source.length; i += 1) {
    if (source[i] === "{") { depth += 1; started = true; }
    else if (source[i] === "}") {
      depth -= 1;
      if (started && depth === 0) return source.slice(match.index, i + 1);
    }
  }
  throw new Error(`${name} body is unterminated`);
}

// Keys the watch accepts from the phone ("phone" trusted source) in each build flavour.
const fullPhoneKeys = (() => {
  const body = extractFunction(store, "isAllowedSyncKey", "fullLegacyState");
  const common = new Set([...body.slice(0, body.indexOf('if (trustedSource.equals("cloud"))')).matchAll(/key\.equals\("(\w+)"\)/g)].map((m) => m[1]));
  const phoneTail = body.slice(body.lastIndexOf("return key.equals"));
  for (const m of phoneTail.matchAll(/key\.equals\("(\w+)"\)/g)) common.add(m[1]);
  return common;
})();
const compactPhoneKeys = new Set(
  [...extractFunction(store, "isAllowedSyncKey", "compactLegacyState").matchAll(/key\.equals\("(\w+)"\)/g)].map((m) => m[1])
);
const watchCap = Number(/message\.size\(\) > (\d+)/.exec(extractFunction(store, "hasOnlySyncKeys"))?.[1]);

test("the fixture watch cap matches hasOnlySyncKeys", () => {
  assert.equal(watchCap, contract.watchMaximumKeys);
  assert.ok(fullPhoneKeys.size >= 15, "allowlist parse should find the phone keys");
  assert.deepEqual([...compactPhoneKeys].sort(), [...fullPhoneKeys].sort());
});

for (const item of contract.cases) {
  for (const platform of ["android", "ios"]) {
    test(`${item.id} (${platform}) uses only watch-allowed keys within the cap`, () => {
      const payload = { ...item.expected, ...item.platformExtras[platform] };
      const keys = Object.keys(payload);
      assert.ok(keys.length <= watchCap, `${keys.length} keys exceed the watch cap ${watchCap}`);
      for (const key of keys) {
        assert.ok(fullPhoneKeys.has(key), `${platform} key ${key} is not in the full watch allowlist`);
        assert.ok(compactPhoneKeys.has(key), `${platform} key ${key} is not in the compact watch allowlist`);
      }
      assert.equal(payload.type, "sync");
      assert.equal(payload.planNames.length, payload.planWeights.length);
      assert.equal(payload.planNames.length, payload.planReps.length);
    });
  }
}

test("every key in any expected payload is watch-allowed", () => {
  const all = new Set(contract.cases.flatMap((c) => Object.keys(c.expected)));
  for (const key of all) assert.ok(fullPhoneKeys.has(key), `${key} missing from watch allowlist`);
});
