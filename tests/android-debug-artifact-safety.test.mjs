import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [appBuild, appDebugManifest, releaseScript] = await Promise.all([
  readFile("app/build.gradle.kts", "utf8"),
  readFile("app/src/debug/AndroidManifest.xml", "utf8"),
  readFile("scripts/publish-debug-release.ps1", "utf8"),
]);

test("public debug builds do not expose Compose tooling or test activities", () => {
  assert.doesNotMatch(
    appBuild,
    /debugImplementation\(libs\.androidx\.compose\.ui\.tooling\)/,
    "phone debug build must not package PreviewActivity"
  );
  assert.doesNotMatch(
    appBuild,
    /debugImplementation\(libs\.androidx\.compose\.ui\.test\.manifest\)/,
    "phone debug build must not package the exported test ComponentActivity"
  );
  assert.match(
    appBuild,
    /implementation\(libs\.androidx\.compose\.ui\.tooling\.preview\)/,
    "phone may retain compile-time preview annotations"
  );
  assert.match(
    appDebugManifest,
    /android:name="androidx\.activity\.ComponentActivity"[\s\S]*?android:exported="false"/,
    "the in-process Compose host must remain unreachable outside the debug app"
  );
});

test("the remaining phone-only debug receiver is explicitly non-exported", () => {
  assert.match(
    appDebugManifest,
    /android:name="\.garmin\.GarminDebugReceiver"[\s\S]*?android:exported="false"/
  );
});

test("debug publication entry point is disabled before any artifact work", () => {
  assert.match(releaseScript, /publication is disabled by repository security policy/i);
  assert.doesNotMatch(releaseScript, /\bgh\s+release\s+(?:create|upload)\b/i);
  assert.doesNotMatch(releaseScript, /\bgit\s+(?:fetch|push|add|commit|switch)\b/i);
  assert.doesNotMatch(releaseScript, /build-update-apk|gradlew/i);
});
