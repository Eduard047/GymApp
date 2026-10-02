import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const GARMIN_STORE_URL = "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f";
const GYMAPP_ANDROID_PACKAGE = "com.setforge.gymapp";
const GYMAPP_PLAY_URL = "https://play.google.com/store/apps/details?id=com.setforge.gymapp";
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

test("iOS Info.plist declares no background BLE mode and keeps foreground Bluetooth usage strings", async () => {
  const iosInfo = await readFile("ios/GymApp-iOS/GymApp/Resources/Info.plist", "utf8");
  const modes = iosInfo.match(/<key>UIBackgroundModes<\/key>\s*<array>([\s\S]*?)<\/array>/);

  assert.notEqual(modes, null, "UIBackgroundModes must remain declared for remote notifications");
  assert.equal(modes[1].includes("bluetooth-central"), false);
  assert.equal(modes[1].includes("<string>remote-notification</string>"), true);
  assert.equal(iosInfo.includes("<key>NSBluetoothAlwaysUsageDescription</key>"), true);
  assert.equal(iosInfo.includes("<key>NSBluetoothPeripheralUsageDescription</key>"), true);
});

test("iOS initializes the Connect IQ SDK without a Bluetooth state-restoration identifier", async () => {
  const service = await readFile("ios/GymApp-iOS/GymApp/Services/GarminPhoneSyncService.swift", "utf8");
  const iosInfo = await readFile("ios/GymApp-iOS/GymApp/Resources/Info.plist", "utf8");

  assert.equal(iosInfo.includes("bluetooth-central"), false);
  assert.equal(service.includes("stateRestorationIdentifier"), false);
  assert.equal(service.includes("restorationIdentifier"), false);
  assert.match(
    service,
    /connectIQ\.initialize\(\s*withUrlScheme: urlScheme,\s*uiOverrideDelegate: nil\s*\)/
  );
});

test("Android profile relies on the app bar and the two-section switcher", async () => {
  const androidScreen = await readFile(
    "app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt",
    "utf8"
  );

  assert.equal(androidScreen.includes("text = stringResource(R.string.title_profile)"), false);
  assert.equal(androidScreen.includes("ProfileSectionSwitcher("), true);
  assert.equal(androidScreen.includes("R.string.profile_section_training"), true);
  assert.equal(androidScreen.includes("R.string.profile_section_settings"), true);
});

test("Android profile groups Account, Language, Training settings, Backup and Help in one panel and owns the language menu", async () => {
  const androidScreen = await readFile(
    "app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt",
    "utf8"
  );
  const navGraph = await readFile(
    "app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt",
    "utf8"
  );

  assert.equal(androidScreen.includes("TutorialHelpCard"), false);
  assert.equal(androidScreen.includes("profile_up_to_date"), false);
  assert.equal(androidScreen.includes("BackupToolsSettingsRow("), true);
  assert.equal(androidScreen.includes("ProfileLanguageRow("), true);
  assert.equal(androidScreen.includes("R.string.profile_friends_live_requires_cloud"), true);
  assert.equal(androidScreen.includes("if (accountState.isCloudAccount) {\n            ProfileSectionSwitcher("), true);
  assert.equal(navGraph.includes("LanguageSelector("), false);
  assert.equal(navGraph.includes("onLanguageSelected = languageManager::setLanguage"), true);
});

test("PWA uses our Garmin listing and an Android intent with a Google Play fallback", async () => {
  const app = await readFile("pwa/app.js", "utf8");

  assert.equal(quotedValueFollowing(app, "GARMIN_STORE_APP_URL"), GARMIN_STORE_URL);
  assert.equal(quotedValueFollowing(app, "CONNECT_IQ_ANDROID_PACKAGE"), CONNECT_IQ_PACKAGE);
  assert.equal(app.includes("S.browser_fallback_url="), true);
  assert.equal(app.includes(OLD_QA_DOWNLOAD), false);
});

test("PWA exposes official Android and Garmin store links on the login and account surfaces", async () => {
  const [app, styles] = await Promise.all([
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/styles.css", "utf8")
  ]);

  assert.equal(quotedValueFollowing(app, "ANDROID_APP_PACKAGE"), GYMAPP_ANDROID_PACKAGE);
  assert.equal(app.includes("const GOOGLE_PLAY_APP_URL = `https://play.google.com/store/apps/details?id=${ANDROID_APP_PACKAGE}`"), true);
  assert.equal(app.includes(GYMAPP_PLAY_URL), false, "Keep the package ID as the single Google Play source of truth");
  assert.match(app, /function storeDownloadPanel\(\)/);
  assert.match(app, /\$\{storeDownloadPanel\(\)\}/);
  assert.match(app, /class="store-download-link" href="\$\{escapeAttr\(GOOGLE_PLAY_APP_URL\)\}" target="_blank" rel="noopener noreferrer"/);
  assert.match(app, /class="store-download-link" href="\$\{escapeAttr\(garminStoreAppLink\(\)\)\}" target="_blank" rel="noopener noreferrer"/);
  assert.match(app, /settingsRowMarkup\(\{[^\n]*href: GOOGLE_PLAY_APP_URL, trailing: external \}\)/);
  assert.match(app, /settingsRowMarkup\(\{[^\n]*href: garminStoreAppLink\(\), trailing: external \}\)/);
  assert.match(app, /<a class="\$\{classes\}" href="\$\{escapeAttr\(href\)\}" target="_blank" rel="noopener noreferrer"/);
  assert.match(styles, /\.auth-actions\s*\{[^}]*gap: 12px;[^}]*margin-top: 16px;/s);
  assert.match(styles, /:root\[data-theme="dark"\][\s\S]*?--on-accent: #071321;/);
  assert.match(styles, /\.button\s*\{[^}]*color: var\(--on-accent\);[^}]*background: var\(--sage\);/s);
});
