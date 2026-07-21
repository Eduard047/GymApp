import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [androidSource, iosSource, pwaSource, baseMigrationSource, hipAbductionMigrationSource] = await Promise.all([
  readFile("app/src/main/java/com/example/gymapp/data/catalog/BuiltInExerciseCatalog.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/BuiltInExerciseCatalog.swift", "utf8"),
  readFile("pwa/app.js", "utf8"),
  readFile("supabase/migrations/20260721143010_create_exercise_catalog.sql", "utf8"),
  readFile("supabase/migrations/20260721201016_add_hip_abduction_to_exercise_catalog.sql", "utf8")
]);
const migrationSource = `${baseMigrationSource}\n${hipAbductionMigrationSource}`;

const expectedCatalog = [...pwaSource.matchAll(
  /\{ key: "([a-z0-9_]+)", names: \{ en: "([^"]+)", uk: "([^"]+)" \}/g
)].map(match => match.slice(1));

test("Android, iOS, and PWA expose the same built-in exercise contract", () => {
  assert.equal(expectedCatalog.length, 52);
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
