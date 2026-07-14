import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [appBuild, wearBuild, appDebugManifest, releaseScript] = await Promise.all([
  readFile("app/build.gradle.kts", "utf8"),
  readFile("wear/build.gradle.kts", "utf8"),
  readFile("app/src/debug/AndroidManifest.xml", "utf8"),
  readFile("scripts/publish-debug-release.ps1", "utf8"),
]);

test("public debug builds do not package Compose tooling or test activities", () => {
  for (const [label, build] of [
    ["phone", appBuild],
    ["watch", wearBuild],
  ]) {
    assert.doesNotMatch(
      build,
      /debugImplementation\(libs\.androidx\.compose\.ui\.tooling\)/,
      `${label} debug build must not package PreviewActivity`
    );
    assert.doesNotMatch(
      build,
      /debugImplementation\(libs\.androidx\.compose\.ui\.test\.manifest\)/,
      `${label} debug build must not package the exported test ComponentActivity`
    );
    assert.match(
      build,
      /implementation\(libs\.androidx\.compose\.ui\.tooling\.preview\)/,
      `${label} may retain compile-time preview annotations`
    );
  }
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
