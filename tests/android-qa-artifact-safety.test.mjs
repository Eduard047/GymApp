import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [
  phoneBuild,
  mainManifest,
  debugManifest,
  mainActivity,
  cloudAuth,
  phoneReleaseScript,
  playReleaseScript,
  gradleProperties,
  securityWorkflow,
] = await Promise.all([
  readFile("app/build.gradle.kts", "utf8"),
  readFile("app/src/main/AndroidManifest.xml", "utf8"),
  readFile("app/src/debug/AndroidManifest.xml", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/MainActivity.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
  readFile("scripts/build-phone-release-apk.ps1", "utf8"),
  readFile("scripts/build-play-release-aab.ps1", "utf8"),
  readFile("gradle.properties", "utf8"),
  readFile(".github/workflows/security.yml", "utf8"),
]);

function qaBlock(build) {
  const match = build.match(/create\("qa"\)\s*\{([\s\S]*?)\n\s{8}\}/);
  assert.ok(match, "qa build type must exist");
  return match[1];
}

test("public QA variants inherit release behavior and stay outside production", () => {
  const qa = qaBlock(phoneBuild);
  assert.match(qa, /initWith\(getByName\("release"\)\)/, "phone QA must inherit release");
  assert.match(qa, /applicationIdSuffix\s*=\s*"\.dev"/, "phone QA must not use production ID");
  assert.match(qa, /versionNameSuffix\s*=\s*"-qa"/, "phone QA must be visibly labelled");
  assert.match(qa, /isDebuggable\s*=\s*false/, "phone QA must be non-debuggable");
  assert.match(
    qa,
    /signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)/,
    "phone QA must use only the non-production test certificate"
  );
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

test("Phone production releases require external environment-only signing material", () => {
  assert.match(phoneBuild, /environmentVariable\("GYMAPP_RELEASE_KEYSTORE_PATH"\)/);
  assert.match(phoneBuild, /environmentVariable\("GYMAPP_RELEASE_STORE_PASSWORD"\)/);
  assert.match(phoneBuild, /release keystore must be stored outside the repository/i);
  assert.doesNotMatch(phoneBuild, /keystore\.properties/);
  assert.match(phoneBuild, /create\("release"\)[\s\S]*?storeFile/);
  assert.match(
    phoneBuild,
    /release\s*\{[\s\S]*?if \(releaseSigningConfigured\)[\s\S]*?signingConfig/
  );
  for (const script of [phoneReleaseScript, playReleaseScript]) {
    assert.match(script, /GYMAPP_RELEASE_KEYSTORE_PATH/);
    assert.match(script, /release keystore must be stored outside the repository/i);
    assert.doesNotMatch(script, /keystore\.properties/);
  }
});

test("production Android scripts default to the declared release version", () => {
  const versionName = gradleProperties.match(/^appVersionName=(.+)$/m)?.[1]?.trim();
  const versionCode = gradleProperties.match(/^appVersionCode=(\d+)$/m)?.[1];
  assert.ok(versionName, "appVersionName must be declared");
  assert.ok(versionCode, "appVersionCode must be declared");

  for (const [label, script] of [
    ["phone APK", phoneReleaseScript],
    ["Play AAB", playReleaseScript],
  ]) {
    assert.match(script, /Get-Content \$gradlePropertiesPath/,
      `${label} must read the checked-in version defaults`);
    assert.match(script, /releaseProperties\['appVersionCode'\]/,
      `${label} must use appVersionCode`);
    assert.match(script, /releaseProperties\['appVersionName'\]/,
      `${label} must use appVersionName`);
    assert.doesNotMatch(script, /Get-Date|TotalMinutes|versionBase/,
      `${label} must not silently replace the release version with a timestamp`);
    assert.match(script, /VersionCode -le 0 -or \$VersionCode -gt 2100000000/,
      `${label} must reject invalid Android version codes`);
    assert.match(script, /VersionName\.Length -gt 64/,
      `${label} must bound the version name`);
    assert.match(script, /\\x00-\\x1F\\x7F/,
      `${label} must reject control characters in the version name`);
    assert.match(script, /-PappVersionCode=\$VersionCode/);
    assert.match(script, /-PappVersionName=\$VersionName/);
  }
});

test("production APK is verified before it is copied for publication", () => {
  const verificationIndex = phoneReleaseScript.indexOf("Assert-ZipArchiveEntries $phoneApkSource");
  const copyIndex = phoneReleaseScript.indexOf("Copy-Item -Path $phoneApkSource");

  assert.ok(verificationIndex >= 0, "phone APK ZIP verification must run");
  assert.ok(copyIndex > verificationIndex, "phone APK must be verified before it is copied");
  assert.match(phoneReleaseScript, /expectedPackageId\s*=\s*"com\.setforge\.gymapp"/);
  assert.match(phoneReleaseScript, /Assert-ReleaseOutputMetadata @metadataArguments/);
  assert.match(phoneReleaseScript, /aapt2[\s\S]*?dump badging/i);
  assert.match(phoneReleaseScript, /application-debuggable/);
  assert.match(phoneReleaseScript, /application-testOnly/);
  assert.match(phoneReleaseScript, /apksigner[\s\S]*?verify --verbose --print-certs/i);
  assert.match(phoneReleaseScript, /APK Signature Scheme v2/);
  assert.match(
    phoneReleaseScript,
    /Signer #\[0-9\]\+\|V\[0-9\.\]\+ Signer:/,
    "production APK verification must accept legacy and modern apksigner signer labels"
  );
  assert.match(
    securityWorkflow,
    /Signer #\[0-9\]\+\|V\[0-9\.\]\+ Signer:/,
    "CI APK verification must accept legacy and modern apksigner signer labels"
  );
  assert.match(phoneReleaseScript, /signer does not match the configured release keystore/i);
});

test("production AAB is verified before it is copied for publication", () => {
  const verificationIndex = playReleaseScript.indexOf("Assert-ZipArchiveEntries @bundleZipArguments");
  const copyIndex = playReleaseScript.indexOf("Copy-Item -Path $bundleSource");

  assert.ok(verificationIndex >= 0, "Play AAB ZIP verification must run");
  assert.ok(copyIndex > verificationIndex, "Play AAB must be verified before it is copied");
  assert.match(playReleaseScript, /BundleConfig\.pb/);
  assert.match(playReleaseScript, /base\/manifest\/AndroidManifest\.xml/);
  assert.match(playReleaseScript, /linked-resources-for-bundle-proto-format\.ap_/);
  assert.match(playReleaseScript, /bundleManifestSha256\s+-cne\s+\$generatedManifestSha256/);
  assert.match(playReleaseScript, /Assert-ReleaseManifestMetadata @manifestMetadataArguments/);
  assert.match(playReleaseScript, /application-debuggable/);
  assert.match(playReleaseScript, /application-testOnly/);
  assert.match(playReleaseScript, /'-verify',[\s\S]*?'-strict',[\s\S]*?'-verbose',[\s\S]*?'-certs'/);
  assert.match(playReleaseScript, /jar verified\\\.\\s\*\$/);
  assert.match(playReleaseScript, /signer does not match the configured release keystore/i);
});

test("release signer checks keep keystore passwords out of command lines and output", () => {
  for (const [label, script] of [
    ["phone APK", phoneReleaseScript],
    ["Play AAB", playReleaseScript],
  ]) {
    assert.match(script, /-storepass:env/,
      `${label} must pass the password to Java through a scoped environment variable`);
    assert.match(script, /SetEnvironmentVariable\([\s\S]*?StorePassword/,
      `${label} must scope the keystore password in process memory`);
    assert.doesNotMatch(script, /Write-(?:Host|Output|Warning)[^\r\n]*(?:storePassword|StorePassword)/i,
      `${label} must not print the keystore password`);
    assert.doesNotMatch(script, /'-storepass'\s*,\s*\$StorePassword/i,
      `${label} must not put the keystore password on the command line`);
    assert.match(script, /Read\(\$buffer, 0, \$buffer\.Length\)/,
      `${label} must read every ZIP entry to detect corrupt compressed data`);
  }
});
