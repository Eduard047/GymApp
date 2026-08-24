import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const migrationsDirectory = "supabase/migrations";
const migrationNamePattern = /^(\d{14})_([a-z0-9_]+)\.sql$/;

const productionFirstRecordedVersion = "20260629115900";
const productionLastRecordedVersion = "20260824180727";
const productionMigrationCount = 57;
const reviewedForwardMigrations = [];

function migrationVersion(fileName) {
  const match = migrationNamePattern.exec(fileName);
  assert.ok(match, `${fileName} must match <14-digit UTC timestamp>_<name>.sql`);
  return match[1];
}

function assertValidUtcTimestamp(version, fileName) {
  const year = Number(version.slice(0, 4));
  const month = Number(version.slice(4, 6));
  const day = Number(version.slice(6, 8));
  const hour = Number(version.slice(8, 10));
  const minute = Number(version.slice(10, 12));
  const second = Number(version.slice(12, 14));
  const parsed = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  const roundTripped = parsed.toISOString().replace(/\D/g, "").slice(0, 14);

  assert.equal(
    roundTripped,
    version,
    `${fileName} must contain a real UTC calendar timestamp`
  );
}

async function orderedMigrationFiles() {
  const files = await readdir(migrationsDirectory);
  return files.filter((fileName) => fileName.endsWith(".sql")).sort();
}

test("Supabase migration versions are valid, unique, and strictly ordered", async () => {
  const files = await orderedMigrationFiles();
  const versions = files.map((fileName) => {
    const version = migrationVersion(fileName);
    assertValidUtcTimestamp(version, fileName);
    return version;
  });

  assert.equal(new Set(versions).size, versions.length, "migration versions must be unique");
  for (let index = 1; index < versions.length; index += 1) {
    assert.ok(
      versions[index - 1] < versions[index],
      `${files[index - 1]} must sort before ${files[index]}`
    );
  }

  const guardIndex = files.indexOf(
    "20260722005900_fail_closed_public_rls_guard.sql"
  );
  assert.ok(
    guardIndex > files.indexOf("20260721201016_add_hip_abduction_to_exercise_catalog.sql")
  );
  assert.ok(
    guardIndex < files.indexOf("20260722010000_require_live_session_for_account_deletion.sql")
  );
});

test("local Supabase uses the PostgreSQL major required by the migration chain", async () => {
  const [config, projectionMigration] = await Promise.all([
    readFile("supabase/config.toml", "utf8"),
    readFile(
      "supabase/migrations/20260722013000_prepare_bounded_user_state_projection.sql",
      "utf8"
    ),
  ]);
  const databaseSection = /\[db\]([\s\S]*?)(?=\n\[|$)/.exec(config)?.[1];

  assert.ok(databaseSection, "Supabase config must pin the local database major");
  assert.match(databaseSection, /major_version\s*=\s*17/);
  assert.match(
    projectionMigration,
    /current_setting\('server_version_num'\)::integer < 170000/
  );
});

test("verified production history is followed only by reviewed forward migrations", async () => {
  const files = await orderedMigrationFiles();
  const versions = files.map(migrationVersion);
  const preHistory = files.filter(
    (fileName) => migrationVersion(fileName) < productionFirstRecordedVersion
  );
  const forwardDrift = files.filter(
    (fileName) => migrationVersion(fileName) > productionLastRecordedVersion
  );

  assert.equal(files.length, productionMigrationCount + reviewedForwardMigrations.length);
  assert.equal(versions[0], productionFirstRecordedVersion);
  assert.equal(versions[productionMigrationCount - 1], productionLastRecordedVersion);
  assert.deepEqual(preHistory, []);
  assert.deepEqual(forwardDrift, reviewedForwardMigrations);
});
