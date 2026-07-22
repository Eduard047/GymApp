import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const preparePath =
  "supabase/migrations/20260722013000_prepare_bounded_user_state_projection.sql";
const backfillPath =
  "supabase/migrations/20260722013100_backfill_user_state_projection.sql";
const activatePath =
  "supabase/migrations/20260722013200_activate_bounded_user_state_projection.sql";

test("user-state validation rejects structural exhaustion before recursive SQL expansion", async () => {
  const migration = await readFile(preparePath, "utf8");
  const globalBudget = migration.match(
    /create or replace function gymapp_private\.validate_user_state_global_budget\(p_state jsonb\)[\s\S]*?\$function\$;/
  )?.[0];

  assert.ok(globalBudget, "the native global budget helper must exist");
  assert.match(migration, /pg_catalog\.pg_column_size\(p_state\) > 33554432/);
  assert.match(migration, /canonical_state := p_state::text/);
  assert.ok(
    migration.indexOf("pg_catalog.pg_column_size(p_state)") <
      migration.indexOf("canonical_state := p_state::text"),
    "the cheap storage guard must run before canonicalization"
  );
  assert.doesNotMatch(globalBudget, /jsonb_path_query/);
  assert.match(migration, /structural_state := pg_catalog\.regexp_replace/);
  assert.match(migration, /\(2 \* container_count\) \+ comma_count > 1000000/);
  assert.match(migration, /jsonb_path_exists\(p_state, 'strict \$\.\*\*\{9\}'/);
  assert.match(migration, /@\.key == "__proto__" \|\| @\.key == "prototype" \|\| @\.key == "constructor"/);
  assert.match(migration, /like_regex "\^\(\.\{255\}\)\{32\}\.\{33\}" flag "s"/);
  assert.doesNotMatch(migration, /canonical_state ~ '"\(__proto__/);
  assert.match(migration, /validate_user_state_global_budget\(p_state\)/);
  assert.match(migration, /Recursive GymApp JSON walk remains after replacement/);

  const paddingValueCount = 999_998;
  const containerCount = 2; // root object plus padding array
  const commaCount = paddingValueCount - 1;
  assert.ok(
    2 * containerCount + commaCount > 1_000_000,
    "the previously accepted million-node padding state must fail the cheap structural budget"
  );
});

test("state writes maintain a private revision-bound projection without changing grants", async () => {
  const migration = await readFile(preparePath, "utf8");

  assert.match(migration, /create table if not exists gymapp_private\.user_state_progression/);
  assert.match(migration, /source_revision timestamptz not null/);
  assert.match(migration, /on conflict \(user_id\) do update/);
  assert.match(migration, /new\.user_id, new\.updated_at, progression\.xp/);
  assert.match(migration, /create trigger user_states_projection_revision_only/);
  assert.match(migration, /old\.state is not distinct from new\.state/);
  assert.match(migration, /set source_revision = new\.updated_at/);
  assert.match(migration, /revoke all on table gymapp_private\.user_state_progression[\s\S]*from public, anon, authenticated/);
  assert.doesNotMatch(migration, /grant (?:select|insert|update|delete)[\s\S]*user_state_progression[\s\S]*authenticated/i);
});

test("online backfill cannot overwrite a concurrently projected revision", async () => {
  const [prepareMigration, migration] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(backfillPath, "utf8"),
  ]);

  assert.match(migration, /from public\.user_states as state/);
  assert.match(migration, /user_state_quarantine/);
  assert.match(migration, /on conflict \(user_id\) do nothing/);
  assert.doesNotMatch(migration, /update public\.user_states|delete from public\.user_states/i);
  assert.match(prepareMigration, /foreign key \(user_id\)[\s\S]*references public\.user_states\(user_id\)[\s\S]*on delete cascade[\s\S]*not valid/);
  assert.match(prepareMigration, /validate constraint user_state_progression_user_id_fkey/);
  assert.match(migration, /An orphaned GymApp state projection remains after backfill/);
  assert.match(migration, /A valid GymApp state is missing its revision-bound projection/);
});

test("profile-only writes never read or revalidate user state", async () => {
  const migration = await readFile(activatePath, "utf8");
  const guardBody = migration.match(
    /create or replace function gymapp_private\.guard_profile_progression\(\)[\s\S]*?\$function\$;/
  )?.[0];

  assert.ok(guardBody, "the replacement profile guard must exist");
  assert.doesNotMatch(guardBody, /public\.user_states|progression_from_state/);
  assert.match(guardBody, /new\.xp := old\.xp/);
  assert.match(guardBody, /new\.level := old\.level/);
  assert.match(guardBody, /new\.workouts := old\.workouts/);
  assert.match(guardBody, /gymapp_private\.user_state_progression/);
  assert.match(guardBody, /pg_catalog\.pg_trigger_depth\(\) > 1/);
  assert.match(guardBody, /trusted_refresh_owner = new\.user_id::text/);
});

test("state refresh creates the profile row and restores its scoped marker on errors", async () => {
  const migration = await readFile(preparePath, "utf8");

  assert.match(migration, /insert into public\.profiles[\s\S]*on conflict \(user_id\) do update/);
  assert.match(migration, /set_config\('gymapp\.progression_refresh_user', new\.user_id::text, true\)/);
  assert.match(migration, /exception[\s\S]*when others then[\s\S]*coalesce\(previous_refresh_owner, ''\)[\s\S]*raise/);
});
