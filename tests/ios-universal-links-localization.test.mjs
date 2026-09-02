import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = "ios/GymApp-iOS/GymApp";
const [
  aasaSource,
  entitlements,
  project,
  infoPlist,
  appSource,
  sharedLinkSource,
  englishInfo,
  ukrainianInfo,
  russianInfo
] = await Promise.all([
  readFile("pwa/.well-known/apple-app-site-association", "utf8"),
  readFile(`${root}/GymApp.entitlements`, "utf8"),
  readFile("ios/GymApp-iOS/GymApp.xcodeproj/project.pbxproj", "utf8"),
  readFile(`${root}/Resources/Info.plist`, "utf8"),
  readFile(`${root}/App/GymAppIOS.swift`, "utf8"),
  readFile(`${root}/Domain/SharedWorkoutLink.swift`, "utf8"),
  readFile(`${root}/Resources/en.lproj/InfoPlist.strings`, "utf8"),
  readFile(`${root}/Resources/uk.lproj/InfoPlist.strings`, "utf8"),
  readFile(`${root}/Resources/ru.lproj/InfoPlist.strings`, "utf8")
]);

function infoPlistStrings(source) {
  const entries = [...source.matchAll(/^"([^"]+)"\s*=\s*"([^"]*)";$/gmu)]
    .map(([, key, value]) => [key, value]);
  return Object.fromEntries(entries);
}

test("AASA binds exact workout and native-auth routes to the exact iOS app", async () => {
  const aasa = JSON.parse(aasaSource);
  assert.deepEqual(Object.keys(aasa), ["applinks"]);
  assert.deepEqual(Object.keys(aasa.applinks), ["details"]);
  assert.equal(aasa.applinks.details.length, 1);
  const detail = aasa.applinks.details[0];
  assert.deepEqual(detail.appIDs, ["XZ84SZH2PV.com.setforge.gymapp.ios"]);
  assert.deepEqual(detail.components.map(component => component["/"]), [
    "/workout/",
    "/workout/*",
    "/auth/ios-callback.html"
  ]);
  assert.equal(detail.components.some(component => ["/", "/confirmed.html", "/auth/*"].includes(component["/"])), false);

  assert.match(entitlements, /<key>com\.apple\.developer\.associated-domains<\/key>[\s\S]*?<string>applinks:gymapptracker\.com<\/string>/);
  assert.equal((entitlements.match(/applinks:gymapptracker\.com/g) || []).length, 1);
  assert.match(project, /com\.apple\.AssociatedDomains = \{\s*enabled = 1;\s*\};/);
  assert.match(project, /DEVELOPMENT_TEAM = XZ84SZH2PV;/);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER = com\.setforge\.gymapp\.ios;/);
  assert.match(appSource, /\.onContinueUserActivity\(NSUserActivityTypeBrowsingWeb\)/);
  assert.equal(
    (await readFile(`${root}/Services/AuthService.swift`, "utf8"))
      .includes("https://gymapptracker.com/auth/ios-callback.html"),
    true,
  );
  assert.match(sharedLinkSource, /percentEncodedPath == "\/workout\/"/);
  assert.match(sharedLinkSource, /com\.setforge\.gymapp\.ios:\/\/workout\/#workout=/);
  await access("pwa/.nojekyll");
});

test("Bluetooth permission copy has exact English fallback plus Ukrainian and Russian localizations", () => {
  const expectedKeys = [
    "NSBluetoothAlwaysUsageDescription",
    "NSBluetoothPeripheralUsageDescription"
  ];
  const locales = [
    ["en", infoPlistStrings(englishInfo)],
    ["uk", infoPlistStrings(ukrainianInfo)],
    ["ru", infoPlistStrings(russianInfo)]
  ];
  for (const [locale, values] of locales) {
    assert.deepEqual(Object.keys(values).sort(), expectedKeys, `${locale} must localize both Bluetooth prompts`);
    for (const value of Object.values(values)) {
      assert.ok(value.length >= 50 && value.length <= 220, `${locale} permission text must be bounded and explanatory`);
      assert.match(value, /GymApp/);
      assert.match(value, /Bluetooth/);
      assert.match(value, /Garmin/);
    }
  }
  for (const [key, value] of Object.entries(locales[0][1])) {
    assert.match(infoPlist, new RegExp(`<key>${key}<\\/key>\\s*<string>${value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}<\\/string>`));
  }
  assert.notDeepEqual(locales[1][1], locales[0][1]);
  assert.notDeepEqual(locales[2][1], locales[0][1]);
});
