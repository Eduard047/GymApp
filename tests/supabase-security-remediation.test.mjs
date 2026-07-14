import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const garminMigrationPath = "supabase/migrations/20260713210000_harden_garmin_pairing_and_plans.sql";
const progressionMigrationPath = "supabase/migrations/20260713211000_reconcile_canonical_progression.sql";

test("Garmin migration binds, validates, quarantines, and grants each RPC to the narrow role", async () => {
  const sql = await readFile(garminMigrationPath, "utf8");

  assert.match(sql, /add column if not exists binding_version smallint/);
  assert.match(sql, /update public\.garmin_devices[\s\S]*revoked_at = coalesce[\s\S]*sha256\(pg_catalog\.convert_to\(device_token, 'UTF8'\)\)[\s\S]*where binding_version is null/);
  assert.match(sql, /drop constraint if exists garmin_plans_status_check[\s\S]*status in \('pending', 'downloaded', 'completed', 'invalid', 'superseded'\)/);
  const planColumns = sql.indexOf("add column if not exists plan_revision");
  const legacyStatusQuarantine = sql.indexOf("Legacy unsupported status quarantined:");
  const statusValidation = sql.indexOf("alter table public.garmin_plans validate constraint garmin_plans_status_check");
  assert.ok(planColumns > 0 && planColumns < legacyStatusQuarantine && legacyStatusQuarantine < statusValidation);
  assert.match(sql, /update public\.garmin_plans[\s\S]*status = 'invalid',[\s\S]*pg_catalog\.quote_literal\(status\)[\s\S]*where status not in \('pending', 'downloaded', 'completed', 'invalid', 'superseded'\)/);
  assert.match(sql, /garmin_plan_validation_error\(p_plan jsonb\)/);
  assert.match(sql, /octet_length\([\s\S]*> 65536/);
  assert.match(sql, /jsonb_array_length\(exercises_value\) not between 1 and 60/);
  assert.match(sql, /total_sets := total_sets \+ pg_catalog\.jsonb_array_length\(sets_value\);[\s\S]*if total_sets > 60/);
  assert.match(sql, /total_exercise_name_bytes :=[\s\S]*octet_length\([\s\S]*jsonb_array_length\(sets_value\);[\s\S]*> 12000/);
  assert.match(sql, /weight_value > 1000000/);
  assert.match(sql, /reps_value > 10000/);
  assert.match(sql, /status = 'invalid',[\s\S]*validation_error/);
  assert.doesNotMatch(sql, /delete\s+from\s+public\.garmin_plans/i);

  for (const signature of [
    "public.garmin_create_device(text)",
    "public.garmin_revoke_device(uuid)",
    "public.garmin_fetch_pending_plan(text)",
    "public.garmin_ack_plan(text, uuid, bigint)",
    "public.garmin_quarantine_pending_plan(text, uuid, bigint, text)"
  ]) {
    assert.ok(
      sql.includes(`revoke all on function ${signature} from public, anon, authenticated;`),
      `Missing least-privilege revoke for ${signature}`
    );
  }
  assert.match(sql, /grant execute on function public\.garmin_revoke_device\(uuid\) to authenticated/);
  assert.match(sql, /grant execute on function public\.garmin_create_device\(text\) to authenticated/);
  assert.match(sql, /grant execute on function public\.garmin_fetch_pending_plan\(text\) to anon/);
  assert.match(sql, /revoke all on table public\.garmin_devices, public\.garmin_plans\s+from public, anon, authenticated/);
  assert.match(sql, /from information_schema\.column_privileges[\s\S]*table_name in \('garmin_devices', 'garmin_plans'\)[\s\S]*execute pg_catalog\.format\(/);
  assert.match(sql, /pg_catalog\.aclexplode\(attribute\.attacl\)/);
  assert.match(sql, /Legacy Garmin column grants remain/);
  assert.match(sql, /grant select on table public\.garmin_plans to authenticated/);
  assert.doesNotMatch(sql, /grant select on table public\.garmin_devices/);
  assert.match(sql, /grant insert on table public\.garmin_plans to authenticated/);
  assert.match(sql, /revoke update on table public\.garmin_devices, public\.garmin_plans from authenticated/);
  assert.match(sql, /has_table_privilege\('authenticated', 'public\.garmin_devices', 'INSERT'\)/);
  assert.match(sql, /new\.id := pg_catalog\.gen_random_uuid\(\)/);
  assert.match(sql, /new\.downloaded_at := null/);
  assert.match(sql, /if new\.device_id is null or not exists \(/);
  assert.match(sql, /coalesce\(pg_catalog\.max\(plan\.plan_revision\), 0\) \+ 1/);
  assert.match(sql, /new\.plan_revision := next_plan_revision/);
  assert.match(sql, /check \(plan_revision between 1 and 2147483647\)/);
  assert.match(sql, /recent_plan_count >= 10 or pending_plan_count >= 5/);
  assert.match(sql, /active_device_count >= 5 or recent_device_count >= 20/);
  assert.match(sql, /jsonb_typeof\(set_value->'weight'\) is distinct from 'number'/);
  assert.match(sql, /order_value <> set_index/);
  assert.match(sql, /garmin_device_token_hash\(generated_token\)/);
  assert.match(sql, /device\.device_token = gymapp_private\.garmin_device_token_hash\(p_device_token\)/g);
  assert.doesNotMatch(sql, /device\.device_token = p_device_token/);
  assert.match(sql, /security definer\s+set search_path = ''/g);
});

test("fetch and revoke serialize on the same device and acknowledgement is an idempotent revision CAS", async () => {
  const sql = await readFile(garminMigrationPath, "utf8");
  const fetchStart = sql.indexOf("create or replace function public.garmin_fetch_pending_plan");
  const markStart = sql.indexOf("create or replace function public.garmin_ack_plan");
  const quarantineStart = sql.indexOf("create or replace function public.garmin_quarantine_pending_plan");
  const revokeStart = sql.indexOf("create or replace function public.garmin_revoke_device");
  const fetchBlock = sql.slice(fetchStart, markStart);
  const markBlock = sql.slice(markStart, quarantineStart);
  const revokeBlock = sql.slice(revokeStart, fetchStart);

  assert.match(fetchBlock, /from public\.garmin_devices[\s\S]*for update;/);
  assert.match(revokeBlock, /from public\.garmin_devices[\s\S]*for update;/);
  assert.match(markBlock, /from public\.garmin_devices[\s\S]*for update;/);
  assert.match(markBlock, /plan\.plan_revision = p_plan_revision/);
  assert.match(markBlock, /plan\.status in \('pending', 'downloaded'\)/);
  assert.match(markBlock, /device\.revoked_at is null/);
  assert.match(markBlock, /plan\.device_id = found_device\.id/);
  assert.match(markBlock, /p_device_token !~ '\^\[A-Fa-f0-9\]\{64\}\$'/);
  assert.match(markBlock, /'status', 'already_acknowledged'/);
  assert.match(fetchBlock, /status = 'superseded'/);
  assert.match(fetchBlock, /order by plan\.plan_revision desc, plan\.created_at desc, plan\.id/);
  assert.match(fetchBlock, /older_plan\.plan_revision < found_plan\.plan_revision/);
  assert.match(fetchBlock, /pg_advisory_xact_lock\([\s\S]*found_device\.user_id/);
  assert.match(fetchBlock, /accountBinding/);
  assert.match(fetchBlock, /garmin_account_binding\(found_device\.user_id\)/);
  assert.doesNotMatch(fetchBlock, /'userId'/);
});

test("canonical progression checks legacy budgets before traversal and ignores empty sessions", async () => {
  const sql = await readFile(progressionMigrationPath, "utf8");
  const legacyLength = sql.indexOf("flat_set_count := pg_catalog.jsonb_array_length(sets_value);");
  const legacyTraversal = sql.indexOf("for set_value in", legacyLength);

  assert.ok(legacyLength > 0 && legacyLength < legacyTraversal);
  assert.match(sql.slice(legacyLength, legacyTraversal), /total_set_count \+ flat_set_count > 100000/);
  assert.match(sql, /if max_sets_for_one_exercise > 100/);
  assert.match(sql, /if session_set_count > 0 then[\s\S]*workout_count := workout_count \+ 1;[\s\S]*session_xp := least\(/);
  assert.match(sql, /total_xp > 2147483647/);
  assert.match(sql, /Closed-form cumulative XP with a bounded binary search/);
  assert.match(sql, /create trigger profiles_canonical_progression_guard/);
  assert.match(sql, /create trigger user_states_refresh_profile_progression/);
  assert.doesNotMatch(sql, /jsonb_object_length/);
  assert.match(sql, /known_exercise_name_count := known_exercise_name_count \+ 1/);
  assert.match(sql, /limit 2001[\s\S]*bounded_mapping_keys/);
  assert.match(sql, /create table if not exists gymapp_private\.user_state_quarantine/);
  assert.match(sql, /when sqlstate '22023' or sqlstate '22003' or sqlstate '54000'/);
  assert.match(sql, /not exists \([\s\S]*gymapp_private\.user_state_quarantine/);
  assert.match(sql, /select \* into strict progression[\s\S]*delete from gymapp_private\.user_state_quarantine/);
  assert.match(sql, /revoke all on function gymapp_private\.progression_from_state\(jsonb\)/);
  assert.match(sql, /octet_length\(pg_catalog\.convert_to\(p_state::text, 'UTF8'\)\) > 8388608/);
  assert.match(sql, /create or replace function gymapp_private\.validate_user_state\(p_state jsonb\)/);
  assert.match(sql, /json_node_count > 1000000/);
  assert.match(sql, /json_max_depth > 8/);
  assert.match(sql, /json_has_oversized_string/);
  assert.match(sql, /octet_length\(pg_catalog\.convert_to\(session_value->>'note', 'UTF8'\)\) > 16000/);
  assert.match(sql, /state_name_is_valid\(exercise_value->>'name'\)/);
  assert.match(sql, /nested and flat workout representations disagree/);
  assert.match(sql, /GymApp cloud state owner is immutable/);
  assert.match(sql, /owner_value->>'remote' = 'supabase'/);
  assert.match(sql, /\(p_state->>'schemaVersion'\)::numeric <> 2/);
  assert.doesNotMatch(sql, /daily workout limit|session_day_count/);
  assert.match(sql, /session_xp := least\([\s\S]*5000::bigint/);
  assert.match(sql, /floor\(session_volume \/ 80\.0::double precision \+ 0\.5\)/);
  assert.doesNotMatch(sql, /pg_catalog\.greatest/);
  assert.doesNotMatch(sql, /jsonb_typeof\([^\n]+\) <> '(?:object|array|string|number)'/);
  assert.doesNotMatch(sql, /delete\s+from\s+public\.user_states/i);
});

test("Edge dependency and response contracts are exact, integrity locked, and pseudonymous", async () => {
  const [edge, edgeConfig, planContract, denoConfig, denoLock] = await Promise.all([
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
    readFile("supabase/config.toml", "utf8"),
    readFile("supabase/functions/_shared/garmin-plan-contract.ts", "utf8"),
    readFile("supabase/functions/garmin-sync/deno.json", "utf8"),
    readFile("supabase/functions/garmin-sync/deno.lock", "utf8")
  ]);

  assert.match(denoConfig, /npm:@supabase\/supabase-js@2\.110\.2/);
  assert.match(denoConfig, /"frozen": true/);
  assert.match(denoLock, /"@supabase\/supabase-js@2\.110\.2"[\s\S]*"integrity": "sha512-/);
  assert.doesNotMatch(edge, /esm\.sh/);
  assert.match(edge, /bindingVersion: 2/);
  assert.match(edge, /accountBinding: candidate\.accountBinding/);
  assert.match(edge, /deviceBinding: candidate\.deviceBinding/);
  assert.match(edge, /planRevision: candidate\.planRevision/);
  assert.doesNotMatch(edge, /userId:\s*candidate/);
  assert.match(edge, /action === "ackPlan"/);
  assert.match(edge, /"garmin_ack_plan"/);
  assert.match(edge, /request\.body\.getReader\(\)/);
  assert.match(edge, /byteLength > REQUEST_BODY_BYTES[\s\S]*reader\.cancel\(\)/);
  assert.match(edge, /chunks\.length >= REQUEST_BODY_CHUNKS/);
  assert.match(edge, /new TextDecoder\("utf-8", \{ fatal: true \}\)/);
  assert.match(edge, /candidate\.planRevision > MAX_PLAN_REVISION/);
  assert.match(edge, /!UUID_PATTERN\.test\(candidate\.planId\)/);
  assert.doesNotMatch(edge, /request\.text\(\)/);
  assert.match(edgeConfig, /\[functions\.garmin-sync\][\s\S]*verify_jwt = false/);
  assert.match(planContract, /totalExerciseNameBytes: 12_000/);
  assert.match(planContract, /new TextEncoder\(\)\.encode\(name\)\.byteLength/);
  assert.match(planContract, /RFC3339_PATTERN\.test\(text\)/);
});
