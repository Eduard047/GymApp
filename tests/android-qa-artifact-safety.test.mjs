import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [phoneBuild, wearBuild, mainManifest, debugManifest, mainActivity, cloudAuth] = await Promise.all([
  readFile("app/build.gradle.kts", "utf8"),
  readFile("wear/build.gradle.kts", "utf8"),
  readFile("app/src/main/AndroidManifest.xml", "utf8"),
  readFile("app/src/debug/AndroidManifest.xml", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/MainActivity.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
]);

function qaBlock(build) {
  const match = build.match(/create\("qa"\)\s*\{([\s\S]*?)\n\s{8}\}/);
  assert.ok(match, "qa build type must exist");
  return match[1];
}

test("public QA variants inherit release behavior and stay outside production", () => {
  for (const [label, build] of [
    ["phone", phoneBuild],
    ["watch", wearBuild],
  ]) {
    const qa = qaBlock(build);
    assert.match(qa, /initWith\(getByName\("release"\)\)/, `${label} QA must inherit release`);
    assert.match(qa, /applicationIdSuffix\s*=\s*"\.dev"/, `${label} QA must not use production ID`);
    assert.match(qa, /versionNameSuffix\s*=\s*"-qa"/, `${label} QA must be visibly labelled`);
    assert.match(qa, /isDebuggable\s*=\s*false/, `${label} QA must be non-debuggable`);
    assert.match(
      qa,
      /signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)/,
      `${label} QA must use only the non-production test certificate`
    );
  }
});

test("the QA source set does not inherit the phone debug receiver", () => {
  assert.match(debugManifest, /android:name="\.garmin\.GarminDebugReceiver"/);
  assert.doesNotMatch(phoneBuild, /sourceSets[\s\S]*?qa[\s\S]*?src\/debug/i);
});

test("QA authentication callbacks cannot be claimed by the production app", () => {
  const qa = qaBlock(phoneBuild);
  assert.match(mainManifest, /android:scheme="\$\{authCallbackScheme\}"/);
  assert.match(qa, /authCallbackScheme"\]\s*=\s*"com\.setforge\.gymapp\.dev"/);
  assert.match(qa, /AUTH_CALLBACK_SCHEME[\s\S]*?com\.setforge\.gymapp\.dev/);
  assert.match(qa, /AUTH_BRIDGE_VARIANT_QUERY[\s\S]*?variant=qa/);
  assert.match(mainActivity, /BuildConfig\.AUTH_CALLBACK_SCHEME/);
  assert.match(cloudAuth, /BuildConfig\.AUTH_BRIDGE_VARIANT_QUERY/);
});

test("Wear production releases use the same optional production signing contract as phone", () => {
  assert.match(wearBuild, /rootProject\.file\("keystore\.properties"\)/);
  assert.match(wearBuild, /create\("release"\)[\s\S]*?storeFile/);
  assert.match(
    wearBuild,
    /release\s*\{[\s\S]*?if \(keystorePropertiesFile\.exists\(\)\)[\s\S]*?signingConfig/
  );
});
