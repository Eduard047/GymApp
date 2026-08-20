import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const expected = Object.freeze({
  marketingVersion: "3.1.1",
  androidVersionCode: "2000320895",
  iosBuildNumber: "31",
  garminVersion: "3.1.1",
  pwaBundle: "app.v95.js",
  pwaStyleBundle: "styles.v76.css",
  pwaRussianBundle: "russian-text.v83.js",
  pwaLiveWorkoutBundle: "live-workout.v3.js",
  pwaCache: "gym-pwa-v132",
});

const [
  gradleProperties,
  xcodeProject,
  archiveScript,
  garminManifest,
  pwaApp,
  pwaBundle,
  pwaStyle,
  pwaStyleBundle,
  pwaRussianText,
  pwaRussianBundle,
  pwaLiveWorkout,
  pwaLiveWorkoutBundle,
  pwaIndex,
  pwaServiceWorker,
] = await Promise.all([
  readFile("gradle.properties", "utf8"),
  readFile("ios/GymApp-iOS/GymApp.xcodeproj/project.pbxproj", "utf8"),
  readFile("ios/GymApp-iOS/Scripts/archive-app-store.sh", "utf8"),
  readFile("garmin/manifest.xml", "utf8"),
  readFile("pwa/app.js", "utf8"),
  readFile(`pwa/${expected.pwaBundle}`, "utf8"),
  readFile("pwa/styles.css", "utf8"),
  readFile(`pwa/${expected.pwaStyleBundle}`, "utf8"),
  readFile("pwa/russian-text.js", "utf8"),
  readFile(`pwa/${expected.pwaRussianBundle}`, "utf8"),
  readFile("pwa/live-workout.js", "utf8"),
  readFile(`pwa/${expected.pwaLiveWorkoutBundle}`, "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("pwa/sw.js", "utf8"),
]);

function matches(source, pattern) {
  return [...source.matchAll(pattern)].map((match) => match[1]);
}

test("Android release metadata remains aligned with GymApp 3.1.1", () => {
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

test("Garmin 3.1.1 joins the unchanged iOS and PWA release", () => {
  assert.match(
    garminManifest,
    new RegExp(`\\bversion="${expected.garminVersion.replaceAll(".", "\\.")}"`)
  );
  assert.match(
    pwaIndex,
    new RegExp(`src="\\./${expected.pwaBundle.replaceAll(".", "\\.")}"`)
  );
  assert.match(
    pwaIndex,
    new RegExp(`href="\\./${expected.pwaStyleBundle.replaceAll(".", "\\.")}"`)
  );
  assert.match(pwaIndex, new RegExp(`src="\\./${expected.pwaRussianBundle.replaceAll(".", "\\.")}"`));
  assert.match(pwaIndex, new RegExp(`src="\\./${expected.pwaLiveWorkoutBundle.replaceAll(".", "\\.")}"`));
  assert.match(pwaIndex, /rel="manifest"/);
  assert.match(pwaServiceWorker, /CACHE_PREFIX\s*=\s*"gym-pwa-"/);
  const cacheSuffix = expected.pwaCache.replace(/^gym-pwa-/, "");
  assert.match(pwaServiceWorker, new RegExp(`CACHE_VERSION\\s*=\\s*"${cacheSuffix}"`));
  assert.match(pwaServiceWorker, new RegExp(`"\\./${expected.pwaBundle.replaceAll(".", "\\.")}"`));
  assert.match(pwaServiceWorker, new RegExp(`"\\./${expected.pwaLiveWorkoutBundle.replaceAll(".", "\\.")}"`));
  assert.equal(pwaBundle, pwaApp, "the immutable PWA bundle must equal canonical app.js");
  assert.equal(pwaStyleBundle, pwaStyle, "the immutable PWA stylesheet must equal canonical styles.css");
  assert.equal(pwaRussianBundle, pwaRussianText, "the immutable Russian bundle must equal canonical russian-text.js");
  assert.equal(pwaLiveWorkoutBundle, pwaLiveWorkout, "the immutable live-workout bundle must equal canonical live-workout.js");
});
