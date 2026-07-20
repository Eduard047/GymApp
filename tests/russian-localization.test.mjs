import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const placeholderPattern = /%(?:\d+\$)?(?:[-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?)?[a-zA-Z@]/g;

function androidStrings(source) {
  return new Map([...source.matchAll(/<string\s+name="([^"]+)"[^>]*>(.*?)<\/string>/gs)]
    .map(([, name, value]) => [name, value]));
}

function placeholders(value) {
  return [...String(value).matchAll(placeholderPattern)].map(match => match[0]).sort();
}

test("Android Russian resources cover every English string with compatible placeholders", async () => {
  const [englishSource, russianSource, manager, navigation, dynamic, workoutDetail] = await Promise.all([
    readFile("app/src/main/res/values/strings.xml", "utf8"),
    readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/util/LanguageManager.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/util/RussianText.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/WorkoutDetailScreen.kt", "utf8")
  ]);
  const english = androidStrings(englishSource);
  const russian = androidStrings(russianSource);
  assert.deepEqual([...russian.keys()].sort(), [...english.keys()].sort());
  for (const [name, value] of english) {
    assert.deepEqual(placeholders(russian.get(name)), placeholders(value), name);
  }
  assert.doesNotMatch([...russian.values()].join("\n"), /[іїєґІЇЄҐ]/);
  assert.match(manager, /RU\("ru"\)/);
  assert.match(navigation, /onLanguageSelected\(AppLanguage\.RU\)/);
  assert.match(dynamic, /"Barbell Row" to "Тяга штанги в наклоне"/);
  assert.match(workoutDetail, /\^Garmin\(\?: Fenix 8\)\?\(\?: ·\|\$\)/);
  assert.equal(russian.get("action_add_set"), "Добавить подход");
});

test("iOS String Catalog has Russian values for every key and preserves format placeholders", async () => {
  const [catalogSource, languageSource, menuSource, projectSource] = await Promise.all([
    readFile("ios/GymApp-iOS/GymApp/Resources/Localizable.xcstrings", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/App/AppLanguage.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/UI/Components/AppLanguageMenu.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp.xcodeproj/project.pbxproj", "utf8")
  ]);
  const catalog = JSON.parse(catalogSource);
  assert.ok(Object.keys(catalog.strings).length >= 650);
  for (const [key, entry] of Object.entries(catalog.strings)) {
    const english = entry.localizations?.en?.stringUnit?.value ?? key;
    const russian = entry.localizations?.ru?.stringUnit?.value;
    assert.equal(typeof russian, "string", key);
    assert.deepEqual(placeholders(russian), placeholders(english), key);
    if (key !== "Українська") assert.doesNotMatch(russian, /[іїєґІЇЄҐ]/, key);
  }
  assert.match(languageSource, /case russian = "ru"/);
  assert.match(menuSource, /Label\("Русский"/);
  assert.match(projectSource, /knownRegions = \([\s\S]*\bru,/);
});

test("PWA accepts Russian state and renders Russian runtime text before app startup", async () => {
  const [contractSource, russianSource, appSource, indexSource, workerSource] = await Promise.all([
    readFile("pwa/state-contract.js", "utf8"),
    readFile("pwa/russian-text.js", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/sw.js", "utf8")
  ]);
  const window = {};
  vm.runInNewContext(russianSource, { Map, Object, RegExp, String, window });
  assert.equal(window.GymRussianText.translate("Add Set"), "Добавить подход");
  assert.equal(window.GymRussianText.translate("Barbell Row"), "Тяга штанги в наклоне");
  assert.equal(window.GymRussianText.translate("Deadlift"), "Становая тяга");
  assert.equal(window.GymRussianText.translate("4-workout week"), "4 тренировок за неделю");
  assert.match(contractSource, /\["en", "uk", "ru"\]\.includes/);
  assert.match(appSource, /data-language="ru">Русский/);
  assert.ok(indexSource.indexOf("russian-text.v48.js") < indexSource.indexOf("app.v48.js"));
  assert.match(workerSource, /"\.\/russian-text\.v48\.js"/);
});

test("Garmin accepts Russian language sync and uses direct touch hit targets", async () => {
  const [manifest, store, view, russianResources] = await Promise.all([
    readFile("garmin/manifest.xml", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/resources-rus/strings.xml", "utf8")
  ]);
  assert.match(manifest, /<iq:language>rus<\/iq:language>/);
  assert.match(store, /language\.equals\("ru"\)/);
  assert.match(store, /static function tr\(en, uk, ru\)/);
  assert.match(view, /evt\.getCoordinates\(\)/);
  assert.match(view, /function rowAt\(/);
  assert.match(view, /activate\(x < \(view\.screenWidth \/ 2\) \? -1 : 1\)/);
  assert.match(view, /pauseRow == 2 && view\.pauseSelected != 2/);
  assert.match(russianResources, /Облачный токен/);
});
