import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const kotlin = "app/src/main/java/com/example/gymapp";
const read = (path) => readFile(path, "utf8");
const [profile, watches, card, graph, state] = await Promise.all([
  read(`${kotlin}/ui/screens/ProfileScreen.kt`),
  read(`${kotlin}/ui/screens/WatchesScreen.kt`),
  read(`${kotlin}/ui/screens/HealthDataCard.kt`),
  read(`${kotlin}/navigation/GymNavGraph.kt`),
  read(`${kotlin}/ui/viewmodel/WatchesState.kt`)
]);
const locales = { en: "values", uk: "values-uk", ru: "values-ru" };
const strings = Object.fromEntries(
  await Promise.all(
    Object.entries(locales).map(async ([lang, dir]) => [lang, await read(`app/src/main/res/${dir}/strings.xml`)])
  )
);

const expected = {
  watches_title: { en: "Watches", uk: "Годинники", ru: "Часы" },
  watches_garmin_capability: {
    en: "Plan on the watch, sets and heart rate",
    uk: "План на годиннику, підходи й пульс",
    ru: "План на часах, подходы и пульс"
  },
  watches_health_capability: {
    en: "Imports workouts and heart rate",
    uk: "Імпортує тренування й пульс",
    ru: "Импортирует тренировки и пульс"
  },
  watches_status_none: { en: "Not connected", uk: "Не підключено", ru: "Не подключено" },
  watches_source_garmin: { en: "Garmin", uk: "Garmin", ru: "Garmin" },
  health_data_title: { en: "Health data", uk: "Дані здоров’я", ru: "Данные здоровья" }
};

test("Watches is a pushed Profile screen and Profile has the single Watches row", () => {
  assert.match(profile, /private enum class ProfileDestination \{[^}]*\bWatches\b/);
  assert.match(profile, /ProfileDestination\.Watches -> \{[\s\S]*?WatchesScreen\(/);
  assert.match(profile, /onOpenWatches = \{ destination = ProfileDestination\.Watches \}/);
  assert.equal((profile.match(/R\.string\.watches_title/g) ?? []).length, 2, "header + row");
  // Neither watch card is hosted inline in Profile any more.
  assert.equal(profile.includes("GarminDeviceCard("), false);
  assert.equal(profile.includes("HealthDataCard("), false);
  assert.match(profile, /onBack = \{ destination = ProfileDestination\.Root \}/);
});

test("the Profile row shows the connected sources through the pure status helpers", () => {
  assert.match(profile, /connectedWatchSources\(garminDeviceState, healthDataState, wearWatchState\)/);
  assert.match(profile, /watchesStatusLine\(/);
  assert.match(profile, /R\.string\.watches_status_none/);
  assert.match(profile, /WatchSource\.GARMIN to stringResource\(R\.string\.watches_source_garmin\)/);
  assert.match(profile, /WatchSource\.WEAR_OS to stringResource\(R\.string\.watches_wear_title\)/);
  assert.match(profile, /WatchSource\.HEALTH_DATA to stringResource\(R\.string\.health_data_title\)/);
  assert.match(state, /enum class WatchSource \{ GARMIN, WEAR_OS, HEALTH_DATA \}/);
  assert.match(state, /joinToString\(" · "\)/);
});

test("Watches order is Garmin, Wear OS, then Health data", () => {
  const garmin = watches.indexOf("GarminDeviceCard(\n                state = garminDeviceState");
  const wear = watches.indexOf("WearWatchCard(\n                    state = wearWatchState");
  const health = watches.indexOf("HealthDataCard(\n                    state = healthDataState");
  assert.ok(garmin > 0, "Garmin card call");
  assert.ok(wear > garmin, "Wear OS card after Garmin");
  assert.ok(health > wear, "Health data after the Wear OS card");
});

test("every Garmin and Health flow stays wired from the Watches screen", () => {
  for (const callback of [
    "onOpenGarminApp = { openGymWorkoutTrackerInGarminStore(context) }",
    "onResetGarminPairing = { showGarminResetConfirmation = true }",
    "onPairGarminDevice = onPairGarminDevice",
    "onPermissionRequestFinished = onHealthPermissionRequestFinished",
    "onImportNow = onHealthImportNow",
    "onDisconnect = onHealthDisconnect"
  ]) {
    assert.equal(watches.includes(callback), true, callback);
  }
  assert.match(watches, /onResetGarminPairing\(\)[\s\S]*garmin_reset_pairing_confirm/);
  assert.match(watches, /LaunchedEffect\(Unit\) \{ onOpened\(\) \}/);
  assert.match(
    profile,
    /onOpened = \{\s*onRefreshGarminDevices\(\)\s*onRefreshWearWatch\(\)\s*onRefreshHealthData\(\)\s*\}/
  );
  // Foreground auto-import is owned by the navigation graph, independent of the open screen.
  assert.match(graph, /healthDataViewModel\?\.importOnForeground\(\)/);
  assert.match(graph, /onRefreshHealthData = \{ healthDataViewModel\?\.refresh\(\) \}/);
});

test("capability lines sit under the card titles", () => {
  assert.match(watches, /supporting = stringResource\(R\.string\.watches_garmin_capability\)/);
  assert.match(card, /supporting = stringResource\(R\.string\.watches_health_capability\)/);
  assert.match(card, /R\.string\.health_data_caption/, "brand caption kept");
});

test("Watches strings exist in en, uk and ru with the agreed copy", () => {
  for (const [key, copy] of Object.entries(expected)) {
    for (const lang of Object.keys(locales)) {
      assert.match(strings[lang], new RegExp(`<string name="${key}">${copy[lang]}</string>`), `${lang}/${key}`);
    }
  }
});

test("flat style: no gradients on the Watches screen", () => {
  assert.doesNotMatch(watches, /Brush\.(linear|radial|vertical|horizontal)Gradient/);
});

test("Garmin card is titled Garmin and navigation hints point to Profile → Watches", () => {
  const hints = {
    en: "Profile → Watches before syncing",
    uk: "Профілі → Годинники перед",
    ru: "Профиле → Часы перед"
  };
  for (const lang of Object.keys(locales)) {
    assert.match(strings[lang], /<string name="garmin_profile_title">Garmin<\/string>/, lang);
    assert.ok(strings[lang].includes(hints[lang]), lang);
    assert.doesNotMatch(strings[lang], /Your watch<|Профіль → Годинник Garmin|Часы Garmin перед/, lang);
  }
});
