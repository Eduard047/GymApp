import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const manifest = await readFile("app/src/debug/AndroidManifest.xml", "utf8");

test("the debug-only Garmin receiver is never exported", () => {
  const receiver = manifest.match(
    /<receiver[\s\S]*?android:name="\.garmin\.GarminDebugReceiver"[\s\S]*?<\/receiver>/
  )?.[0];

  assert.ok(receiver, "GarminDebugReceiver declaration is missing");
  assert.match(receiver, /android:exported="false"/);
  assert.doesNotMatch(receiver, /android:exported="true"/);
});
