import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile(
  "supabase/migrations/20260824120000_sync_activity_only_workouts.sql",
  "utf8"
);
const databaseTest = await readFile(
  "supabase/tests/activity_only_workout_sidecar.sql",
  "utf8"
);

function sqlFunction(source, name) {
  const marker = `function ${name}`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `Missing SQL function ${name}`);
  const end = source.indexOf("$function$;", start);
  assert.notEqual(end, -1, `Unterminated SQL function ${name}`);
  return source.slice(start, end + "$function$;".length);
}

test("activity-only storage is private, account-cascading, and defense-in-depth RLS protected", () => {
  assert.match(migration, /create table gymapp_private\.activity_only_workout_sync_states/);
  assert.match(migration, /create table gymapp_private\.activity_only_workouts/);
  assert.match(migration, /primary key \(user_id, workout_started_at_millis\)/);
  assert.match(migration, /references auth\.users\(id\) on delete cascade/);
  assert.match(migration, /references\s+gymapp_private\.activity_only_workout_sync_states\(user_id\)\s+on delete cascade/);
  assert.match(migration, /activity_only_workouts[\s\S]*enable row level security/);
  assert.match(migration, /activity_only_workouts[\s\S]*force row level security/);
  assert.match(migration, /revoke all on table gymapp_private\.activity_only_workouts[\s\S]*authenticated/);
  assert.match(migration, /revoke all on table gymapp_private\.activity_only_workout_sync_states[\s\S]*authenticated/);
  assert.doesNotMatch(migration, /create policy[\s\S]*activity_only_workout/i);
});

test("activity-only wire fields and resource limits are exact and bounded", () => {
  const sync = sqlFunction(migration, "public.garmin_sync_activity_only_workouts");
  assert.match(sync, /payload_bytes > 1048576\s+or item_count > 5000/);
  assert.match(sync, /'workoutStartedAt', 'durationSeconds', 'gymCalories'/);
  for (const field of [
    "garminCalories",
    "averageHeartRate",
    "maximumHeartRate",
    "endingHeartRateZone",
    "note"
  ]) {
    assert.match(sync, new RegExp(`'${field}'`));
  }
  assert.match(sync, /duration_value < 1 or duration_value > 604800/);
  assert.match(sync, /gym_calories_value < 0 or gym_calories_value > 100000/);
  assert.match(sync, /gym_calories_value \* 1000[\s\S]*trunc\(gym_calories_value \* 1000\)/);
  assert.match(sync, /average_heart_rate_value > maximum_heart_rate_value/);
  assert.match(sync, /optional_numeric_value < 0 or optional_numeric_value > 5/);
  assert.match(sync, /char_length\(item_value->>'note'\) > 512/);
  assert.match(sync, /convert_to\(item_value->>'note', 'UTF8'\)[\s\S]*> 2048/);
  assert.match(sync, /started_at_value <= previous_started_at_value/);
  assert.match(sync, /exists \([\s\S]*jsonb_object_keys\(item_value\)[\s\S]*<> all/);
});

test("activity-only synchronization is live-session-bound CAS with exact request replay", () => {
  const sync = sqlFunction(migration, "public.garmin_sync_activity_only_workouts");
  assert.match(sync, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(sync, /current_auth_session_is_live\(\)/);
  assert.match(sync, /pg_advisory_xact_lock/);
  assert.match(sync, /for update/);
  assert.match(sync, /extensions\.digest\([\s\S]*'sha256'/);
  assert.match(sync, /last_request_id = p_request_id/);
  assert.match(sync, /last_expected_revision = p_expected_revision[\s\S]*last_payload_digest = payload_digest/);
  assert.match(sync, /'status', 'request_conflict'/);
  assert.match(sync, /p_expected_revision <> current_revision/);
  assert.match(sync, /'status', 'conflict'/);
  assert.match(sync, /delete from gymapp_private\.activity_only_workouts/);
  assert.match(sync, /on conflict \(user_id, workout_started_at_millis\) do update/);
  assert.match(sync, /where \([\s\S]*\) is distinct from \(/);
  assert.match(sync, /next_revision := current_revision \+ case when changed_count > 0 then 1 else 0 end/);
  assert.match(sync, /consume_workout_duration_sync_budget/);
  assert.ok(
    sync.indexOf("consume_workout_duration_sync_budget") < sync.indexOf("for item_value in"),
    "the durable owner budget must be consumed before per-item expansion"
  );
  assert.ok(
    sync.indexOf("consume_workout_duration_sync_budget") < sync.indexOf("payload_bytes > 1048576"),
    "oversized authenticated requests must consume the durable owner budget"
  );
  assert.match(sync, /set statement_timeout = '8s'/);
  assert.match(sync, /set lock_timeout = '2s'/);
});

test("activity-only reads return only the live owner deterministic snapshot", () => {
  const read = sqlFunction(migration, "public.garmin_read_activity_only_workouts");
  assert.match(read, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(read, /current_auth_session_is_live\(\)/);
  assert.match(read, /select caller_user_id as user_id/);
  assert.match(read, /on state\.user_id = caller\.user_id/);
  assert.match(read, /on workout\.user_id = caller\.user_id/);
  assert.match(read, /into current_revision, result_items/);
  assert.match(read, /order by workout\.workout_started_at_millis/);
  assert.match(read, /jsonb_strip_nulls/);
  assert.match(read, /'version', 1[\s\S]*'revision', current_revision[\s\S]*'items', result_items/);
  assert.match(migration, /grant execute on function public\.garmin_read_activity_only_workouts\(\)[\s\S]*to authenticated/);
  assert.match(migration, /grant execute on function public\.garmin_sync_activity_only_workouts\([\s\S]*to authenticated/);
  assert.doesNotMatch(migration, /grant execute on function public\.garmin_(read|sync)_activity_only_workouts[\s\S]*to anon/);
});

test("mixed-version database coverage proves old duration sync cannot erase the new sidecar", () => {
  assert.doesNotMatch(
    migration,
    /create(?: or replace)? function public\.social_sync_workout_durations/i
  );
  assert.match(migration, /old_duration_definition like '%activity_only_workout%'/);
  assert.match(databaseTest, /select plan\(54\)/);
  assert.equal(
    (databaseTest.match(
      /^select (?:has_table|has_function|ok|is|throws_ok|lives_ok)\(/gm
    ) || []).length,
    54,
    "the pgTAP plan must match its assertion count"
  );
  assert.match(databaseTest, /request_conflict/);
  assert.match(databaseTest, /a stale device snapshot fails its CAS/);
  assert.match(databaseTest, /unknown item keys fail closed/);
  assert.match(databaseTest, /another owner cannot read the first owner snapshot/);
  assert.match(databaseTest, /an expired exact Auth session cannot read the sidecar/);
  assert.match(databaseTest, /public\.social_sync_workout_durations\('\[\]'::jsonb\)/);
  assert.match(databaseTest, /an old-client duration snapshot cannot erase activity-only rows/);
  assert.match(databaseTest, /account deletion cascades through activity-only rows/);
});
