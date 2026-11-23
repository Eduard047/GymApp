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

test("iOS Watches screen order is Garmin card, Apple Watch slot, then Health data", async () => {
  const screen = screenBody(await readFile(profilePath, "utf8"));
  const body = screen.slice(screen.indexOf("var body: some View"), screen.indexOf("private var garminCard"));
  const garmin = body.indexOf("garminCard");
  const slot = body.indexOf("WATCHES-APPLE-WATCH-SLOT");
  const health = body.indexOf("HealthDataCard(service: healthImport)");
  assert.ok(garmin >= 0 && slot > garmin && health > slot, "Garmin -> Apple Watch slot -> Health data");
});

test("iOS Watches cards carry the capability lines and keep their flows", async () => {
  const profile = await readFile(profilePath, "utf8");
  const health = await readFile(`${ios}/Components/HealthDataCard.swift`, "utf8");
  assert.match(
    profile,
    /"Plan on the watch, sets and heart rate",\s*"План на годиннику, підходи й пульс",\s*"План на часах, подходы и пульс"/
  );
  assert.match(
    health,
    /"Imports workouts and heart rate",\s*"Імпортує тренування й пульс",\s*"Импортирует тренировки и пульс"/
  );
  // The brand caption stays on the Health data card.
  assert.match(health, /Samsung, Xiaomi, Huawei, Amazfit, Polar, Fitbit and other watches — through Apple Health\./);
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
  assert.match(profile, /WatchesStatus\.summary\(\s*garminPaired: garminPaired,\s*healthConnected: appState\.healthImport\.isConnected/);
});

test("WatchesStatus copy is complete in EN/UK/RU", async () => {
  const status = await readFile(`${ios}/Screens/WatchesStatus.swift`, "utf8");
  assert.match(status, /"Health data", "Дані здоров’я", "Данные здоровья"/);
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
  assert.ok(all.includes("Профіль → Годинники."));
  assert.ok(all.includes("Профиль → Часы."));
  assert.doesNotMatch(all, /Profile → Your watch|Профіль → Годинник Garmin|Профиль → Часы Garmin|Profile → Garmin watch/);
});
