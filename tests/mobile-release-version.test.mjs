import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const expected = Object.freeze({
  marketingVersion: "3.0.8",
  androidVersionCode: "2000320888",
  iosBuildNumber: "26",
  browserScript: "retirement.v1.js",
  browserStyle: "retirement.v1.css",
});

const [
  gradleProperties,
  xcodeProject,
  archiveScript,
  garminManifest,
  browserScript,
  browserScriptBundle,
  browserStyle,
  browserStyleBundle,
  pwaIndex,
  pwaServiceWorker,
  browserContract,
] = await Promise.all([
  readFile("gradle.properties", "utf8"),
  readFile("ios/GymApp-iOS/GymApp.xcodeproj/project.pbxproj", "utf8"),
  readFile("ios/GymApp-iOS/Scripts/archive-app-store.sh", "utf8"),
  readFile("garmin/manifest.xml", "utf8"),
  readFile("pwa/retirement.js", "utf8"),
  readFile(`pwa/${expected.browserScript}`, "utf8"),
  readFile("pwa/retirement.css", "utf8"),
  readFile(`pwa/${expected.browserStyle}`, "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("pwa/sw.js", "utf8"),
  readFile("shared/browser-retirement-v1.json", "utf8"),
]);

function matches(source, pattern) {
  return [...source.matchAll(pattern)].map((match) => match[1]);
}

test("Android release metadata declares GymApp 3.0.8 with the next versionCode", () => {
  assert.match(
    gradleProperties,
    new RegExp(`^appVersionName=${expected.marketingVersion.replaceAll(".", "\\.")}$`, "m")
  );
  assert.match(
    gradleProperties,
    new RegExp(`^appVersionCode=${expected.androidVersionCode}$`, "m")
  );
});

test("iOS app target and archive defaults agree on release version and build", () => {
  assert.deepEqual(
    matches(xcodeProject, /^\s*MARKETING_VERSION = ([^;]+);$/gm),
    [expected.marketingVersion, expected.marketingVersion, "1.0", "1.0"]
  );
  assert.deepEqual(
    matches(xcodeProject, /^\s*CURRENT_PROJECT_VERSION = ([^;]+);$/gm),
    [expected.iosBuildNumber, expected.iosBuildNumber, "1", "1"]
  );
  assert.match(
    archiveScript,
    new RegExp(`MARKETING_VERSION="\\$\\{MARKETING_VERSION:-${expected.marketingVersion.replaceAll(".", "\\.")}\\}"`)
  );
  assert.match(
    archiveScript,
    new RegExp(`BUILD_NUMBER="\\$\\{BUILD_NUMBER:-${expected.iosBuildNumber}\\}"`)
  );
});

test("Garmin and the immutable browser-retirement entrypoints agree with release 3.0.8", () => {
  assert.match(
    garminManifest,
    new RegExp(`\\bversion="${expected.marketingVersion.replaceAll(".", "\\.")}"`)
  );
  assert.match(
    pwaIndex,
    new RegExp(`src="\\./${expected.browserScript.replaceAll(".", "\\.")}"`)
  );
  assert.match(
    pwaIndex,
    new RegExp(`href="\\./${expected.browserStyle.replaceAll(".", "\\.")}"`)
  );
  assert.match(pwaServiceWorker, /CACHE_PREFIX\s*=\s*"gym-pwa-"/);
  assert.match(pwaServiceWorker, /self\.skipWaiting\(\)/);
  assert.doesNotMatch(pwaServiceWorker, /CACHE_VERSION|CACHE_NAME|app\.v86\.js|russian-text/);
  assert.doesNotMatch(pwaIndex, /app\.v86\.js|russian-text|rel="manifest"/);
  assert.equal(browserScriptBundle, browserScript, "immutable retirement JS must equal canonical source");
  assert.equal(browserStyleBundle, browserStyle, "immutable retirement CSS must equal canonical source");
  assert.equal(JSON.parse(browserContract).productVersion, expected.marketingVersion);
});
