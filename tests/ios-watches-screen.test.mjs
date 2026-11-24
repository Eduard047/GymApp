import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const ios = "ios/GymApp-iOS/GymApp/UI";
const profilePath = `${ios}/Screens/ProfileView.swift`;

function screenBody(profile) {
  const start = profile.indexOf("private struct WatchesScreen: View");
  assert.ok(start >= 0, "WatchesScreen exists");
  return profile.slice(start);
}

test("iOS Watches screen replaces the Garmin-only screen", async () => {
  const profile = await readFile(profilePath, "utf8");
  assert.equal(profile.includes("GarminWatchScreen"), false);
  assert.match(profile, /private struct WatchesScreen: View/);
  const screen = screenBody(profile);
  assert.match(
    screen,
    /\.navigationTitle\(gymText\("Watches", "Годинники", "Часы", languageCode: languageCode\)\)/
  );
});

test("iOS Watches screen order is Garmin card, Apple Watch card, then Health data", async () => {
  const screen = screenBody(await readFile(profilePath, "utf8"));
  const body = screen.slice(screen.indexOf("var body: some View"), screen.indexOf("private var garminCard"));
  const garmin = body.indexOf("garminCard");
  const apple = body.indexOf("appleWatchCard");
  const health = body.indexOf("HealthDataCard(service: healthImport)");
  assert.ok(garmin >= 0 && apple > garmin && health > apple, "Garmin -> Apple Watch -> Health data");
  assert.equal(screen.includes("WATCHES-APPLE-WATCH-SLOT"), false, "the placeholder is gone");
  // Hidden without a paired Apple Watch, like Wear OS on Android without the Wearable API.
  assert.match(body, /if appleWatch\.isPaired \{\s*appleWatchCard\s*\}/);
});

test("iOS Apple Watch card mirrors the Android Wear OS card without an unlink action", async () => {
  const screen = screenBody(await readFile(profilePath, "utf8"));
  const card = screen.slice(screen.indexOf("private var appleWatchCard"), screen.indexOf("private var garminLinkedToAnotherAccountTitle"));
  assert.ok(card.length > 0, "appleWatchCard exists");
  assert.match(card, /title: "Apple Watch"/);
  assert.match(card, /appleWatchLinked\(appleWatch\)/);
  assert.match(
    card,
    /"Install GymApp on your Apple Watch from the Watch app\.",\s*"Встановіть GymApp на Apple Watch у застосунку Watch\.",\s*"Установите GymApp на Apple Watch в приложении Watch\."/
  );
  assert.match(card, /gymText\("Paired", "Прив’язано", "Привязано", languageCode: languageCode\)/);
  assert.match(
    card,
    /"Plan on the watch, sets and heart rate",\s*"План на годиннику, підходи й пульс",\s*"План на часах, подходы и пульс"/
  );
  // The system owns Apple Watch pairing: no unlink/unpair action and no destructive button.
  assert.doesNotMatch(card, /[Uu]nlink|[Uu]npair|role: \.destructive/);
  assert.doesNotMatch(card, /Gradient/);
  const profile = await readFile(profilePath, "utf8");
  assert.match(profile, /func appleWatchLinked\(_ appleWatch: WatchConnectivityService\) -> Bool \{\s*appleWatch\.isPaired && appleWatch\.isWatchAppInstalled/);
});

test("iOS Garmin card polish: centered two-line store button, no repeated model line", async () => {
  const screen = screenBody(await readFile(profilePath, "utf8"));
  assert.match(
    screen,
    /"Открыть Gym Workout Tracker в Garmin",\s*languageCode: languageCode\s*\)\)\s*\.multilineTextAlignment\(\.center\)/
  );
  const row = screen.slice(screen.indexOf("private func garminDeviceRow"));
  assert.match(row, /\.caseInsensitiveCompare\(name\.trimmingCharacters\(in: \.whitespaces\)\) != \.orderedSame/);
});

test("iOS HealthApp row opens an in-app sheet: chevron and a details label", async () => {
  const profile = await readFile(profilePath, "utf8");
  const row = profile.slice(profile.indexOf("private var healthAppRow"), profile.indexOf("private var helpRow"));
  assert.ok(row.length > 0, "healthAppRow exists");
  assert.equal(row.includes("arrow.up.right"), false);
  assert.equal(row.includes("in the App Store"), false);
  assert.match(row, /"HealthApp, details",\s*"HealthApp, докладніше",\s*"HealthApp, подробнее"/);
});

test("iOS Watches cards carry the capability lines and keep their flows", async () => {
  const profile = await readFile(profilePath, "utf8");
  const health = await readFile(`${ios}/Components/HealthDataCard.swift`, "utf8");
  assert.match(
    profile,
    /"Plan on the watch, sets and heart rate",\s*"План на годиннику, підходи й пульс",\s*"План на часах, подходы и пульс"/
  );
  // No card subtitle: it repeated the source caption below.
  assert.doesNotMatch(health, /"Imports workouts and heart rate"/);
  // The source caption names Apple Watch and Apple Health, not the Android brand list.
  assert.match(
    health,
    /"Imports gym workouts and heart rate from Apple Watch and other watches that save to Apple Health\."/
  );
  assert.doesNotMatch(health, /Samsung|Fitbit/);
  assert.match(health, /"Health data", "Дані про здоров’я", "Данные о здоровье"/);
  // The Settings path is the real iOS one.
  assert.match(health, /Settings › Apps › Health › Data Access & Devices\./);
  assert.match(health, /Параметри › Програми › Здоров’я › Доступ до даних і пристрої\./);
  assert.match(health, /Настройки › Приложения › Здоровье › Доступ к данным и устройства\./);
  assert.doesNotMatch(health, /Налаштуваннях|Настройках/);
  // Existing Garmin and Health flows are untouched.
  assert.match(profile, /garminPhoneSync\.selectDevices\(\)/);
  assert.match(profile, /Open Gym Workout Tracker in Garmin/);
  assert.match(health, /service\.connect\(\)/);
  assert.match(health, /service\.importNow\(\)/);
  assert.match(health, /service\.disconnect\(\)/);
});

test("iOS Profile has one Watches row for every profile, with a status line", async () => {
  const profile = await readFile(profilePath, "utf8");
  assert.equal(profile.includes("garminRow"), false);
  assert.match(profile, /title: gymText\("Watches", "Годинники", "Часы", languageCode: languageCode\)/);
  const devices = profile.match(/ProfileGroup\(title: gymText\("Devices"[\s\S]*?\n            \}/)?.[0];
  assert.ok(devices, "Devices group exists");
  // Not behind the cloud-account condition: local/offline profiles see it too.
  assert.match(devices, /watchesRow/);
  assert.doesNotMatch(devices, /isCloudAccount/);
  assert.match(
    profile,
    /WatchesStatus\.summary\(\s*garminPaired: garminPaired,\s*appleWatchLinked: appleWatchLinked\(appleWatch\),\s*healthConnected: healthImport\.isConnected/
  );
  assert.match(profile, /WatchesRowLabel\(\s*garminPaired: garminPaired,\s*appleWatch: appState\.watchSync,\s*healthImport: appState\.healthImport/);
});

test("WatchesStatus copy is complete in EN/UK/RU", async () => {
  const status = await readFile(`${ios}/Screens/WatchesStatus.swift`, "utf8");
  assert.match(status, /"Health data", "Дані про здоров’я", "Данные о здоровье"/);
  // Android order: Garmin · Wear OS (Apple Watch here) · Health data.
  const garmin = status.indexOf('sources.append("Garmin")');
  const apple = status.indexOf('sources.append("Apple Watch")');
  const health = status.indexOf('sources.append(gymText("Health data"');
  assert.ok(garmin >= 0 && apple > garmin && health > apple, "Garmin -> Apple Watch -> Health data");
  assert.match(status, /"Not connected", "Не підключено", "Не подключено"/);
  assert.match(status, /static let separator = " · "/);
  assert.match(status, /sources\.append\("Garmin"\)/);
});

test("iOS Garmin card is titled Garmin and navigation hints point to Profile → Watches", async () => {
  const profile = await readFile(profilePath, "utf8");
  assert.ok(screenBody(profile).includes('title: gymText("Garmin", "Garmin", "Garmin", languageCode: languageCode)'));
  assert.equal(profile.includes('gymText("Your watch"'), false);
  const sources = await Promise.all(
    [
      `${ios}/Screens/AddWorkoutView.swift`,
      `${ios}/Components/GarminPlanDeliveryPanel.swift`,
      `${ios}/Screens/AccountSettingsView.swift`,
      "ios/GymApp-iOS/GymApp/Services/GarminCloudService.swift",
      "ios/GymApp-iOS/GymApp/Resources/Localizable.xcstrings"
    ].map((path) => readFile(path, "utf8"))
  );
  const all = sources.join("\n");
  assert.ok(all.includes("Profile → Watches before syncing a plan."));
  // The plan-sync hint names Garmin and matches the Android wording.
  for (const path of [0, 1]) {
    assert.ok(sources[path].includes("Підключіть годинник Garmin у Профілі → Годинники перед синхронізацією плану."));
    assert.ok(sources[path].includes("Подключите часы Garmin в Профиле → Часы перед синхронизацией плана."));
    assert.equal(sources[path].includes("Перед синхронизацией плана подключите часы"), false);
  }
  assert.doesNotMatch(sources[2], /cloud token|хмарний токен|облачный токен/);
  assert.ok(all.includes("Профіль → Годинники."));
  assert.ok(all.includes("Профиль → Часы."));
  assert.doesNotMatch(all, /Profile → Your watch|Профіль → Годинник Garmin|Профиль → Часы Garmin|Profile → Garmin watch/);
});
