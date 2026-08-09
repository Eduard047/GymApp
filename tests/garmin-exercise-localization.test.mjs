import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [
  androidCatalogSource,
  androidRussianSource,
  garminStoreSource,
  garminResourcesSource,
  garminLabelsSource,
  androidSyncSource
] =
  await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/data/catalog/BuiltInExerciseCatalog.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/util/RussianText.kt", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/resources/strings.xml", "utf8"),
    readFile("garmin/resources/exercise-labels.json", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt", "utf8")
  ]);

const catalogEntries = [...androidCatalogSource.matchAll(
  /definition\(\s*"([a-z0-9_]+)",\s*"([^"]+)",\s*"([^"]+)"/g
)].map(([, key, en, uk]) => ({ key, en, uk }));

const russianByEnglish = new Map(
  [...androidRussianSource.matchAll(/^\s*"([^"]+)"\s+to\s+"([^"]*)",?$/gm)]
    .map(([, en, ru]) => [en, ru])
);

const localizedFunction = garminStoreSource.slice(
  garminStoreSource.indexOf("static function localizedExerciseName(value)"),
  garminStoreSource.indexOf("static function applyCurrentPlanSet()")
);
const garminLabels = JSON.parse(garminLabelsSource);
const declaredGarminNames = [...garminLabelsSource.matchAll(/^\s*"([^"]+)"\s*:/gm)]
  .map(([, name]) => name);
const garminEntries = Object.entries(garminLabels)
  .map(([en, [uk, ru]]) => ({ en, uk, ru }));
const garminByEnglish = new Map(garminEntries.map(entry => [entry.en, entry]));

function renderedExerciseName(name, language) {
  if (language === "en") return name;
  const entry = garminByEnglish.get(name);
  if (!entry) return name;
  return language === "uk" ? entry.uk : language === "ru" ? entry.ru : name;
}

test("Garmin localizes every canonical built-in exercise with Android parity", () => {
  assert.equal(catalogEntries.length, 53);
  assert.equal(new Set(catalogEntries.map(entry => entry.key)).size, catalogEntries.length);
  assert.equal(new Set(catalogEntries.map(entry => entry.en)).size, catalogEntries.length);
  assert.equal(declaredGarminNames.length, new Set(declaredGarminNames).size, "Garmin contains duplicate names");
  assert.deepEqual(
    new Set(Object.keys(garminLabels)),
    new Set([...catalogEntries.map(entry => entry.en), "Exercise", "Overhead Press", "Curl"])
  );
  for (const [name, labels] of Object.entries(garminLabels)) {
    assert.ok(Array.isArray(labels), `${name} labels must be an array`);
    assert.equal(labels.length, 2, `${name} must contain exactly Ukrainian and Russian labels`);
    assert.ok(labels.every(label => typeof label === "string" && label.length > 0));
  }

  for (const entry of catalogEntries) {
    const garmin = garminByEnglish.get(entry.en);
    assert.ok(garmin, `Garmin is missing canonical exercise: ${entry.en}`);
    assert.equal(garmin.uk, entry.uk, `Ukrainian label differs for ${entry.en}`);
    assert.equal(garmin.ru, russianByEnglish.get(entry.en), `Russian label differs for ${entry.en}`);
  }
});

test("Garmin render localization never replaces synchronized exercise identity", () => {
  assert.equal(renderedExerciseName("Lat Pulldown", "uk"), "Тяга верхнього блока");
  assert.equal(renderedExerciseName("Lat Pulldown", "ru"), "Тяга верхнего блока");
  assert.equal(renderedExerciseName("Lat Pulldown", "en"), "Lat Pulldown");

  const customName = "My custom carry";
  assert.equal(renderedExerciseName(customName, "uk"), customName);
  assert.equal(renderedExerciseName(customName, "ru"), customName);
  assert.match(garminResourcesSource, /<jsonData id="ExerciseLabels" filename="exercise-labels\.json"\/>/);
  assert.match(localizedFunction, /App\.loadResource\(Rez\.JsonData\.ExerciseLabels\)/);
  assert.match(localizedFunction, /var label = name;/);
  assert.match(localizedFunction, /exerciseLabelCacheName = name;/);
  assert.match(localizedFunction, /exerciseLabelCacheLanguage = language;/);
  assert.match(localizedFunction, /return label;\s*\}/);
  assert.doesNotMatch(localizedFunction, /return tr\(name,/);

  assert.match(
    garminStoreSource,
    /static function currentExerciseLabel\(\) \{\s*return localizedExerciseName\(currentExercise\(\)\);/
  );
  assert.match(
    garminStoreSource,
    /"exerciseName" => currentExercise\(\)/,
    "completed workouts must keep the raw synchronized identity"
  );
  assert.match(
    garminStoreSource,
    /var flatName = flatNames\[f\]\.toString\(\);[\s\S]*"exerciseName" => flatName/,
    "plans must retain their raw synchronized identity"
  );
  assert.match(androidSyncSource, /"planNames" to compactPlan\.map \{ it\.exerciseName \}/);
  assert.doesNotMatch(androidSyncSource, /"planNames"[^\n]*displayName/);
});

test("Garmin retains released aliases while unknown names pass through", () => {
  assert.deepEqual(garminByEnglish.get("Overhead Press"), {
    en: "Overhead Press",
    uk: "Жим над головою",
    ru: "Жим над головой"
  });
  assert.deepEqual(garminByEnglish.get("Curl"), {
    en: "Curl",
    uk: "Згинання рук",
    ru: "Сгибание рук"
  });
  assert.equal(renderedExerciseName("Imported custom exercise", "uk"), "Imported custom exercise");
});
