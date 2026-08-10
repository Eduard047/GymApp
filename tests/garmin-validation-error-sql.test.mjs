import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260810135453_fix_garmin_validation_error_ambiguity.sql";
const fixturePath = "supabase/tests/garmin_validation_error_core.sql";
const [migration, fixture] = await Promise.all([
  readFile(migrationPath, "utf8"),
  readFile(fixturePath, "utf8"),
]);

const sliceBetween = (source, startText, endText) => {
  const start = source.indexOf(startText);
  const end = source.indexOf(endText, start + startText.length);
  assert.ok(start >= 0 && end > start, `missing source slice: ${startText}`);
  return source.slice(start, end);
};

test("new migration replaces only existing Garmin core signatures", () => {
  assert.match(migration, /^begin;/);
  assert.match(migration, /commit;\s*$/);
  assert.match(
    migration,
    /create or replace function public\.garmin_fetch_pending_plan_core\(\s*p_device_token text\s*\)/,
  );
  assert.match(
    migration,
    /create or replace function public\.garmin_ack_plan_core\(\s*p_device_token text,\s*p_plan_id uuid,\s*p_plan_revision bigint\s*\)/,
  );
  assert.doesNotMatch(
    migration,
    /create or replace function public\.garmin_fetch_pending_plan\(\s*p_device_token/,
  );
  assert.doesNotMatch(
    migration,
    /create or replace function public\.garmin_ack_plan\(\s*p_device_token/,
  );
  assert.doesNotMatch(migration, /drop function|alter function/i);
});

test("both invalid-plan paths use an unambiguous renamed variable", () => {
  const fetchCore = sliceBetween(
    migration,
    "create or replace function public.garmin_fetch_pending_plan_core",
    "create or replace function public.garmin_ack_plan_core",
  );
  const ackCore = sliceBetween(
    migration,
    "create or replace function public.garmin_ack_plan_core",
    "revoke all on function public.garmin_fetch_pending_plan_core",
  );
  for (const core of [fetchCore, ackCore]) {
    assert.match(core, /security definer\s+set search_path = ''/);
    assert.match(core, /plan_validation_message text/);
    assert.match(
      core,
      /plan_validation_message := gymapp_private\.garmin_plan_validation_error/,
    );
    assert.match(
      core,
      /validation_error = pg_catalog\.left\(plan_validation_message, 200\)/,
    );
    assert.doesNotMatch(core, /left\(validation_error, 200\)/);
    assert.match(core, /update public\.garmin_plans as target_plan/);
    assert.match(core, /where target_plan\.id = found_plan\.id/);
  }
});

test("migration preserves owners, fixed search paths, wrappers, and denied core grants", () => {
  assert.match(migration, /snapshot_core_owners/);
  assert.match(migration, /fetch_function\.proowner::text/);
  assert.match(migration, /ack_function\.proowner::text/);
  assert.match(migration, /fetch_function\.prosecdef/);
  assert.match(migration, /fetch_function\.proconfig/);
  assert.match(
    migration,
    /revoke all on function public\.garmin_fetch_pending_plan_core\(text\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /revoke all on function public\.garmin_ack_plan_core\(text, uuid, bigint\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.doesNotMatch(migration, /grant execute on function public\.garmin_.*_core/);
  assert.match(migration, /fetch_wrapper_source[\s\S]*garmin_rate_limit_for_token/);
  assert.match(migration, /fetch_wrapper_source[\s\S]*garmin_fetch_pending_plan_core/);
  assert.match(migration, /ack_wrapper_source[\s\S]*garmin_ack_plan_core/);
});

test("pgTAP fixture checks both repaired paths and API denial", () => {
  assert.match(fixture, /select plan\(16\)/);
  assert.match(fixture, /fetch invalid-plan path uses an unambiguous local variable/);
  assert.match(fixture, /acknowledgement invalid-plan path uses an unambiguous local variable/);
  assert.match(fixture, /anonymous clients cannot bypass the fetch rate-limit wrapper/);
  assert.match(fixture, /authenticated clients cannot bypass the acknowledgement rate-limit wrapper/);
  assert.match(fixture, /service role cannot invoke the ungranted acknowledgement core/);
  assert.match(fixture, /public fetch wrapper still rate-limits before its core/);
  assert.match(fixture, /select \* from finish\(\);\s*rollback;/);
});
