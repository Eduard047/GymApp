import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const GARMIN_STORE_URL = "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f";
const CONNECT_IQ_PACKAGE = "com.garmin.connectiq";
const CONNECT_IQ_PLAY_URL = "https://play.google.com/store/apps/details?id=com.garmin.connectiq";
const CONNECT_IQ_APP_STORE_URL = "https://apps.apple.com/app/connect-iq-store/id1317652970";
const OLD_QA_DOWNLOAD = "gymapp-garmin-connect-iq.iq";

function quotedValueFollowing(source, marker) {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `Missing source marker: ${marker}`);
  const nearbySource = source.slice(markerIndex + marker.length, markerIndex + marker.length + 256);
  const match = nearbySource.match(/["`]([^"`\r\n]+)["`]/);
  assert.notEqual(match, null, `Missing quoted value after: ${marker}`);
  return match[1];
}

test("native clients open our Garmin listing with platform store fallbacks", async () => {
  const [androidLauncher, androidScreen, iosSettings, iosInfo] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/garmin/GarminStoreLauncher.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/UI/Screens/AccountSettingsView.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/Resources/Info.plist", "utf8")
  ]);

  assert.equal(quotedValueFollowing(androidLauncher, "GARMIN_STORE_APP_URL"), GARMIN_STORE_URL);
  assert.equal(quotedValueFollowing(androidLauncher, "CONNECT_IQ_ANDROID_PACKAGE"), CONNECT_IQ_PACKAGE);
  assert.equal(
    quotedValueFollowing(androidLauncher, "CONNECT_IQ_MARKET_URL"),
    `market://details?id=${CONNECT_IQ_PACKAGE}`
  );
  assert.equal(quotedValueFollowing(androidLauncher, "CONNECT_IQ_GOOGLE_PLAY_URL"), CONNECT_IQ_PLAY_URL);
  assert.equal(androidScreen.includes("openGymWorkoutTrackerInGarminStore(context)"), true);

  assert.equal(quotedValueFollowing(iosSettings, "private let garminStoreURL"), GARMIN_STORE_URL);
  assert.equal(quotedValueFollowing(iosSettings, "private let connectIQAppStoreURL"), CONNECT_IQ_APP_STORE_URL);
  assert.equal(iosSettings.includes("application.canOpenURL(connectIQSchemeURL)"), true);
  assert.equal(iosInfo.includes("<string>connectiq</string>"), true);

  assert.equal(androidLauncher.includes(OLD_QA_DOWNLOAD), false);
  assert.equal(androidScreen.includes(OLD_QA_DOWNLOAD), false);
  assert.equal(iosSettings.includes(OLD_QA_DOWNLOAD), false);
});

test("PWA uses our Garmin listing and an Android intent with a Google Play fallback", async () => {
  const app = await readFile("pwa/app.js", "utf8");

  assert.equal(quotedValueFollowing(app, "GARMIN_STORE_APP_URL"), GARMIN_STORE_URL);
  assert.equal(quotedValueFollowing(app, "CONNECT_IQ_ANDROID_PACKAGE"), CONNECT_IQ_PACKAGE);
  assert.equal(app.includes("S.browser_fallback_url="), true);
  assert.equal(app.includes(OLD_QA_DOWNLOAD), false);
});
