import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = "app/src/main";
const read = (path) => readFile(`${root}/${path}`, "utf8");
const locales = { en: "values", uk: "values-uk", ru: "values-ru" };
const strings = Object.fromEntries(
  await Promise.all(Object.entries(locales).map(async ([lang, dir]) => [lang, await read(`res/${dir}/strings.xml`)]))
);
const kotlin = "java/com/example/gymapp";
const card = await read(`${kotlin}/ui/screens/HealthDataCard.kt`);
const profile = await read(`${kotlin}/ui/screens/ProfileScreen.kt`);
const watches = await read(`${kotlin}/ui/screens/WatchesScreen.kt`);
const graph = await read(`${kotlin}/navigation/GymNavGraph.kt`);
const viewModel = await read(`${kotlin}/ui/viewmodel/HealthDataViewModel.kt`);
const rationale = await read(`${kotlin}/health/HealthPermissionRationaleActivity.kt`);

const plainKeys = [
  "health_data_title", "health_data_unavailable", "health_data_install", "health_data_connect",
  "health_data_last_import", "health_data_import_now", "health_data_disconnect", "health_data_importing",
  "health_data_empty", "health_data_failed", "health_data_caption",
  "health_import_rationale_title", "health_import_rationale_body"
];

test("every Health data string exists in English, Ukrainian and Russian", () => {
  for (const [lang, xml] of Object.entries(strings)) {
    for (const key of plainKeys) {
      assert.match(xml, new RegExp(`<string name="${key}">[^<]+</string>`), `${lang}: ${key}`);
    }
    assert.match(xml, /<plurals name="health_data_summary">/, `${lang}: plural summary`);
  }
});

test("the summary plural carries a count and a time in every locale and category", () => {
  const categories = { en: ["one", "other"], uk: ["one", "few", "many", "other"], ru: ["one", "few", "many", "other"] };
  for (const [lang, xml] of Object.entries(strings)) {
    const block = xml.match(/<plurals name="health_data_summary">([\s\S]*?)<\/plurals>/)[1];
    for (const quantity of categories[lang]) {
      const item = block.match(new RegExp(`<item quantity="${quantity}">([^<]*)</item>`));
      assert.ok(item, `${lang}: ${quantity}`);
      assert.ok(item[1].includes("%1$d") && item[1].includes("%2$s"), `${lang}: ${quantity} placeholders`);
    }
  }
});

test("the shared copy matches the agreed wording", () => {
  assert.match(strings.en, />Health data</);
  assert.match(strings.uk, />Дані здоров’я</);
  assert.match(strings.ru, />Данные здоровья</);
  assert.match(strings.en, />Connect Health Connect</);
  assert.match(strings.uk, />Підключити Health Connect</);
  assert.match(strings.ru, />Подключить Health Connect</);
  assert.match(strings.en, />Samsung, Xiaomi, Huawei, Amazfit, Polar, Fitbit and other watches — through Health Connect\.</);
  assert.match(strings.uk, />Samsung, Xiaomi, Huawei, Amazfit, Polar, Fitbit та інші годинники — через Health Connect\.</);
  assert.match(strings.ru, />Samsung, Xiaomi, Huawei, Amazfit, Polar, Fitbit и другие часы — через Health Connect\.</);
});

test("the card sits directly after the Garmin card on the Watches screen, not inline in Profile", () => {
  const garmin = watches.indexOf("GarminDeviceCard(\n                state = garminDeviceState");
  const health = watches.indexOf("HealthDataCard(\n                    state = healthDataState");
  assert.ok(garmin > 0, "Garmin card call");
  assert.ok(health > garmin, "Health data card comes after the Garmin card");
  assert.ok(health - garmin < 900, "no other card in between");
  assert.equal(profile.includes("HealthDataCard("), false, "Profile no longer hosts the card");
});

test("the card is wired from the navigation graph and refreshes on resume", () => {
  assert.match(graph, /healthDataState = healthDataState/);
  assert.match(graph, /onHealthImportNow = \{ healthDataViewModel\?\.importNow\(\) \}/);
  assert.match(graph, /onHealthDisconnect = \{ healthDataViewModel\?\.disconnect\(\) \}/);
  assert.match(graph, /healthDataViewModel\?\.importOnForeground\(\)/);
  // Profile still refreshes on open (status line); the Watches screen refreshes again when it opens.
  assert.match(graph, /healthDataViewModel\?\.refresh\(\)/);
  assert.match(graph, /onRefreshHealthData = \{ healthDataViewModel\?\.refresh\(\) \}/);
});

test("permissions are requested only from the Connect button, never automatically", () => {
  // The only launch call is inside the button's onClick.
  const launches = card.match(/\.launch\(/g) ?? [];
  assert.equal(launches.length, 1);
  const click = card.match(/onClick = \{\s*permissionLauncher\?\.launch\(/);
  assert.ok(click, "launch happens inside onClick");
  for (const [name, source] of [["card", card], ["view model", viewModel], ["graph", graph]]) {
    assert.doesNotMatch(source, /LaunchedEffect[^\n]*\n[^\n]*permissionLauncher/, name);
    assert.doesNotMatch(source, /requestPermissions\(|createRequestPermissionResultContract/, name);
  }
  assert.match(viewModel, /fun importOnForeground\(\)/);
  assert.match(viewModel, /shouldRunAutoImport/);
});

test("formatted strings use the safe helpers", () => {
  assert.match(card, /formattedPluralStringResource\(R\.plurals\.health_data_summary/);
  assert.match(card, /formattedStringResource\(R\.string\.health_data_last_import/);
  assert.doesNotMatch(card, /(?<![A-Za-z])stringResource\(R\.(string|plurals)\.health_data_(summary|last_import)/);
});

test("the Install button opens the Play Store page with a web fallback", () => {
  assert.match(card, /com\.google\.android\.apps\.healthdata/);
  assert.match(card, /market:\/\/details\?id=/);
  assert.match(card, /https:\/\/play\.google\.com\/store\/apps\/details\?id=/);
});

test("the card is flat: no gradients", () => {
  assert.doesNotMatch(card, /Brush\.|gradient/i);
});

test("the rationale screen reads its text from resources", () => {
  assert.match(rationale, /R\.string\.health_import_rationale_title/);
  assert.match(rationale, /R\.string\.health_import_rationale_body/);
  assert.doesNotMatch(rationale, /getIdentifier/);
});

test("disconnect revokes permissions and stops the opt-in", () => {
  assert.match(viewModel, /revokeAllPermissions\(\)/);
  assert.match(viewModel, /setEnabled\(false\)/);
});
