import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const expected = Object.freeze({
  marketingVersion: "4.0.2",
  androidVersionCode: "2000320912",
  iosBuildNumber: "51",
  garminVersion: "4.0.2",
  pwaBundle: "app.v116.js",
  pwaStyleBundle: "styles.v88.css",
  pwaRussianBundle: "russian-text.v90.js",
  pwaLiveWorkoutBundle: "live-workout.v3.js",
  pwaCache: "gym-pwa-v159",
});

const [
  gradleProperties,
  xcodeProject,
  archiveScript,
  liveActivityInfoPlist,
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
  readFile("ios/GymApp-iOS/GymAppLiveActivity/Info.plist", "utf8"),
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

test("Android release metadata remains aligned with GymApp 4.0.2", () => {
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
  // Order of appearance in project.pbxproj: GymAppLiveActivity (Debug), GymApp
  // (Debug), GymApp (Release), GymAppTests (Debug), GymAppTests (Release),
  // GymAppLiveActivity (Release).
  assert.deepEqual(
    matches(xcodeProject, /^\s*MARKETING_VERSION = ([^;]+);$/gm),
    [
      expected.marketingVersion,
      expected.marketingVersion,
      expected.marketingVersion,
      "1.0",
      "1.0",
      expected.marketingVersion,
    ]
  );
  assert.deepEqual(
    matches(xcodeProject, /^\s*CURRENT_PROJECT_VERSION = ([^;]+);$/gm),
    [
      expected.iosBuildNumber,
      expected.iosBuildNumber,
      expected.iosBuildNumber,
      "1",
      "1",
      expected.iosBuildNumber,
    ]
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

test("GymAppLiveActivity extension matches the GymApp app target's version and build (App Store parity)", () => {
  assert.match(
    xcodeProject,
    /PRODUCT_BUNDLE_IDENTIFIER = com\.setforge\.gymapp\.ios\.LiveActivity;/,
    "GymAppLiveActivity target must exist in the Xcode project"
  );

  // Isolate each GymAppLiveActivity XCBuildConfiguration block (Debug and
  // Release) and assert its MARKETING_VERSION/CURRENT_PROJECT_VERSION match
  // the host app's, since an embedded extension's CFBundleShortVersionString
  // and CFBundleVersion must match the host app for App Store submission.
  const extensionConfigBlocks = [
    ...xcodeProject.matchAll(
      /buildSettings = \{[^}]*PRODUCT_BUNDLE_IDENTIFIER = com\.setforge\.gymapp\.ios\.LiveActivity;[^}]*\}/g
    ),
  ].map((match) => match[0]);
  assert.equal(
    extensionConfigBlocks.length,
    2,
    "expected exactly one Debug and one Release build configuration for GymAppLiveActivity"
  );
  for (const block of extensionConfigBlocks) {
    assert.match(
      block,
      new RegExp(`MARKETING_VERSION = ${expected.marketingVersion.replaceAll(".", "\\.")};`),
      "GymAppLiveActivity MARKETING_VERSION must match the GymApp app target"
    );
    assert.match(
      block,
      new RegExp(`CURRENT_PROJECT_VERSION = ${expected.iosBuildNumber};`),
      "GymAppLiveActivity CURRENT_PROJECT_VERSION must match the GymApp app target"
    );
  }

  assert.match(
    liveActivityInfoPlist,
    /<key>CFBundleShortVersionString<\/key>\s*<string>\$\(MARKETING_VERSION\)<\/string>/,
    "GymAppLiveActivity Info.plist must derive CFBundleShortVersionString from MARKETING_VERSION"
  );
  assert.match(
    liveActivityInfoPlist,
    /<key>CFBundleVersion<\/key>\s*<string>\$\(CURRENT_PROJECT_VERSION\)<\/string>/,
    "GymAppLiveActivity Info.plist must derive CFBundleVersion from CURRENT_PROJECT_VERSION"
  );
});

test("Garmin, iOS, Android, and PWA remain aligned for 4.0.2", () => {
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
