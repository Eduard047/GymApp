import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [
  androidSource,
  iosSource,
  pwaSource,
  androidCloudStateSource,
  iosCloudStateSource,
  searchVocabularySource,
  baseMigrationSource,
  hipAbductionMigrationSource,
  assistedDipMigrationSource
] = await Promise.all([
  readFile("app/src/main/java/com/example/gymapp/data/catalog/BuiltInExerciseCatalog.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/BuiltInExerciseCatalog.swift", "utf8"),
  readFile("pwa/app.js", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/sync/CloudStateContract.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Data/WorkoutStore.swift", "utf8"),
  readFile("shared/exercise-search-vocabulary.json", "utf8"),
  readFile("supabase/migrations/20260721143010_create_exercise_catalog.sql", "utf8"),
  readFile("supabase/migrations/20260721201016_add_hip_abduction_to_exercise_catalog.sql", "utf8"),
  readFile("supabase/migrations/20260803090000_add_machine_load_profiles_and_assisted_dip.sql", "utf8")
]);
const migrationSource = `${baseMigrationSource}\n${hipAbductionMigrationSource}\n${assistedDipMigrationSource}`;
const searchVocabulary = JSON.parse(searchVocabularySource);

function sourceSection(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.notEqual(start, -1, `missing source marker: ${startMarker}`);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.notEqual(end, -1, `missing source marker: ${endMarker}`);
  return source.slice(start, end);
}

const expectedCatalog = [...pwaSource.matchAll(
  /\{ key: "([a-z0-9_]+)", names: \{ en: "([^"]+)", uk: "([^"]+)" \}/g
)].map(match => match.slice(1));

test("Android, iOS, and PWA expose the same built-in exercise contract", () => {
  assert.equal(expectedCatalog.length, 53);
  for (const [key, english, ukrainian] of expectedCatalog) {
    for (const [platform, source] of [
      ["Android", androidSource],
      ["iOS", iosSource],
      ["PWA", pwaSource]
    ]) {
      assert.ok(source.includes(`"${key}"`), `${platform} is missing ${key}`);
      assert.ok(source.includes(`"${english}"`), `${platform} is missing ${english}`);
      assert.ok(source.includes(`"${ukrainian}"`), `${platform} is missing ${ukrainian}`);
    }
    assert.ok(migrationSource.includes(`('${key}', '${english.replaceAll("'", "''")}', '${ukrainian.replaceAll("'", "''")}'`));
  }
});

test("Android, iOS, and PWA infer only absent built-in cloud catalog keys", () => {
  const androidPullEntryPoint = sourceSection(
    androidCloudStateSource,
    "internal fun prepareSharedCloudState(",
    "internal fun isSharedCloudStateCandidate("
  );
  const androidWriteEntryPoint = sourceSection(
    androidCloudStateSource,
    "internal fun attachSharedCloudExtensions(",
    "private fun prepareCanonicalV2("
  );
  const androidCanonicalReader = sourceSection(
    androidCloudStateSource,
    "private fun prepareCanonicalV2(",
    "private fun prepareLegacyPwaV2("
  );
  const androidCatalogKeyNormalizer = sourceSection(
    androidCloudStateSource,
    "private fun validateAndNormalizePortableCatalogKeys(",
    "private fun validateLegacyPortableCatalogKeys("
  );
  const iosNativeExerciseWire = sourceSection(
    iosCloudStateSource,
    "private static func canonicalNativeExerciseWire(",
    "private static func isCanonicalMachineLoadProfile("
  );
  const pwaNativeExerciseWire = sourceSection(
    pwaSource,
    "function nativeCloudExerciseWire(",
    "function nativeCloudCompareBytes("
  );

  assert.match(
    androidPullEntryPoint,
    /prepareCanonicalV2\(\s*root,\s*activeUserId,\s*allowMissingPortableCatalogKeys = true\s*\)/
  );
  assert.match(
    androidWriteEntryPoint,
    /prepareCanonicalV2\(\s*result,\s*userId,\s*allowMissingPortableCatalogKeys = false\s*\)/
  );
  assert.match(
    androidCanonicalReader,
    /validateAndNormalizePortableCatalogKeys\(\s*root = root,\s*backup = BackupImportValidator\.validate\(root\)/
  );
  assert.match(androidCatalogKeyNormalizer, /!rawExercise\.has\("catalogKey"\)/);
  assert.match(androidCatalogKeyNormalizer, /rawExercise\.isNull\("catalogKey"\)/);
  assert.match(
    androidCatalogKeyNormalizer,
    /rawCatalogKey == rawCatalogKey\.trim\(\) &&\s*rawCatalogKey == inferred/
  );
  assert.match(
    androidCatalogKeyNormalizer,
    /return exercise\.copy\(catalogKey = inferred\)/
  );

  assert.match(
    iosNativeExerciseWire,
    /!hasExplicitCatalogKey \|\| canonical\.catalogKey == rawCatalogKey/
  );
  assert.match(
    iosNativeExerciseWire,
    /backupExerciseIdentity\(name: canonical\.name, catalogKey: canonical\.catalogKey\)/
  );

  assert.match(
    pwaNativeExerciseWire,
    /hasExplicitCatalogKey && \(recognizedCatalogKey \|\| null\) !== catalogKey/
  );
  assert.match(pwaNativeExerciseWire, /catalogKey = recognizedCatalogKey \|\| null/);
});

test("Android, iOS, and PWA consume the shared search-only exercise vocabulary", () => {
  const sharedSearchAliases = searchVocabulary.aliasesByKey;
  assert.ok(Object.keys(sharedSearchAliases).length >= 50);
  assert.match(androidSource, /ExerciseSearchVocabulary\.aliasesByKey/);
  assert.match(iosSource, /ExerciseSearchVocabulary\.aliasesByKey/);
  assert.match(pwaSource, /globalThis\.GymExerciseSearchVocabulary/);

  for (const alias of [
    "махи в стороны с гантелями", "махи в сторони з гантелями", "pec deck",
    "гравитрон", "гравітрон", "OHP", "RDL", "BSS", "RFESS", "Scott curl"
  ]) {
    assert.ok(
      Object.values(sharedSearchAliases).some(aliases => aliases.includes(alias)),
      `missing reviewed search alias: ${alias}`
    );
  }
});

test("the imported database exercise names remain recognized aliases", () => {
  const importedNames = [
    "Журавель", "Нахили в сторони на гіперекстензії", "Присід зі штангою", "Розминка",
    "бокові нахили", "брусья", "біцепс в кросовері", "біцепс з гантелями сидячи",
    "вертикальна тяга", "гантеля над головою", "гантелі лежачи", "горизонтальна важільна тяга",
    "гіперекстензія", "жим лежачи", "жим ногами", "жим сидячи", "зведення ніг",
    "згибання ніг лежачи", "згибання ніг сидячі", "махи в сторони", "махи в сторони в тренажері",
    "махи в сторони з гантелями", "метелик в середину", "метелик в сторони",
    "прес з диском в сторони", "прес звичайний з диском", "прес(підйом ніг)", "протяжка",
    "підйом на носки", "підтягування в гравітроні", "підтягування з резинкою", "розгинання ніг",
    "румунська тяга", "станова тяга", "тренажер скота(біцепс)", "трицепс трикутник",
    "французький жим", "фронтальна тяга", "штанга на біцепс"
  ];
  for (const name of importedNames) {
    assert.ok(pwaSource.toLocaleLowerCase("uk").includes(name.toLocaleLowerCase("uk")), `missing backup alias: ${name}`);
  }
});

test("the shared exercise catalog is read-only through Supabase RLS", () => {
  assert.match(migrationSource, /alter table public\.exercise_catalog enable row level security;/i);
  assert.match(migrationSource, /revoke all on table public\.exercise_catalog from anon, authenticated;/i);
  assert.match(migrationSource, /grant select on table public\.exercise_catalog to anon, authenticated;/i);
  assert.match(migrationSource, /for select\s+to anon, authenticated\s+using \(true\);/i);
  assert.doesNotMatch(migrationSource, /grant\s+(?:insert|update|delete|all)/i);
  assert.doesNotMatch(migrationSource, /for\s+(?:insert|update|delete|all)/i);
});
