import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260629115900_bootstrap_public_rls_guard.sql";
const hardeningPath =
  "supabase/migrations/20260722005900_fail_closed_public_rls_guard.sql";

test("clean Supabase rebuilds install the private RLS DDL guard first", async () => {
  const [migration, migrationFiles] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readdir("supabase/migrations")
  ]);
  const orderedSql = migrationFiles.filter((name) => name.endsWith(".sql")).sort();

  assert.equal(orderedSql[0], "20260629115900_bootstrap_public_rls_guard.sql");
  assert.match(migration, /if to_regprocedure\('public\.rls_auto_enable\(\)'\) is null/);
  assert.match(migration, /returns event_trigger[\s\S]*security definer[\s\S]*set search_path = 'pg_catalog'/);
  assert.match(migration, /command_record\.schema_name = 'public'/);
  assert.match(migration, /alter table if exists %s enable row level security/);
  assert.match(migration, /create event trigger ensure_rls[\s\S]*on ddl_command_end[\s\S]*'CREATE TABLE'[\s\S]*'CREATE TABLE AS'[\s\S]*'SELECT INTO'/);
  assert.match(migration, /revoke all on function public\.rls_auto_enable\(\)[\s\S]*from public, anon, authenticated/);
  assert.doesNotMatch(migration, /grant\s+execute[\s\S]*rls_auto_enable/i);
});

test("the deployed RLS guard fails closed and remains non-client-executable", async () => {
  const migration = await readFile(hardeningPath, "utf8");

  assert.match(migration, /create or replace function public\.rls_auto_enable\(\)/);
  assert.match(migration, /returns event_trigger[\s\S]*security definer[\s\S]*set search_path = 'pg_catalog'/);
  assert.match(migration, /alter table if exists %s enable row level security/);
  assert.doesNotMatch(migration, /when others|raise log/i);
  assert.match(migration, /revoke all on function public\.rls_auto_enable\(\)[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /into strict trigger_function, trigger_event, trigger_tags/);
  assert.match(migration, /has_function_privilege\('anon'[\s\S]*has_function_privilege\([\s\S]*'authenticated'/);
});
