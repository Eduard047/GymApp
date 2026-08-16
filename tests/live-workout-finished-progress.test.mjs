import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260816225557_canonical_finished_live_progress.sql";
const fixturePath = "supabase/tests/canonical_finished_live_progress.sql";

const [migration, fixture, android, androidTests, ios, pwa] = await Promise.all([
  readFile(migrationPath, "utf8"),
  readFile(fixturePath, "utf8"),
  readFile(
    "app/src/main/java/com/example/gymapp/auth/LiveWorkoutContract.kt",
    "utf8",
  ),
  readFile(
    "app/src/test/java/com/example/gymapp/auth/LiveWorkoutContractTest.kt",
    "utf8",
  ),
  readFile("ios/GymApp-iOS/GymApp/Services/LiveWorkoutModels.swift", "utf8"),
  readFile("pwa/live-workout.js", "utf8"),
]);

function functionBody(sql, functionName) {
  const start = sql.indexOf(`create or replace function ${functionName}`);
  assert.ok(start >= 0, `${functionName} must exist`);
  const end = sql.indexOf("\n$function$;", start);
  assert.ok(end > start, `${functionName} must have a bounded body`);
  return sql.slice(start, end + "\n$function$;".length);
}

test("forward migration normalizes legacy finished rows with a bounded atomic guard bypass", () => {
  assert.match(migration, /^begin;\n/);
  assert.match(migration, /set local lock_timeout = '5s';/);
  assert.match(migration, /set local statement_timeout = '30s';/);
  assert.match(
    migration,
    /lock table gymapp_private\.live_workout_progress in access exclusive mode;/,
  );
  assert.match(
    migration,
    /limit 10001[\s\S]*candidate_count > 10000[\s\S]*10000-row safety bound/,
  );
  assert.match(
    migration,
    /disable trigger live_workout_progress_guard;[\s\S]*update gymapp_private\.live_workout_progress[\s\S]*'\{undoableSetId\}'[\s\S]*'null'::jsonb[\s\S]*enable trigger live_workout_progress_guard;/,
  );
  assert.match(
    migration,
    /jsonb_typeof\(progress\.payload->'finishedAt'\) = 'string'[\s\S]*jsonb_typeof\(progress\.payload->'undoableSetId'\) = 'string'/,
  );
  assert.match(migration, /trigger_row\.tgenabled = 'O'/);
  assert.match(migration, /not gymapp_private\.live_workout_progress_is_valid\(progress\.payload\)/);
  assert.match(migration, /\ncommit;\s*$/);
});

test("database validator enforces the canonical finish and reconciliation invariants", () => {
  const validator = functionBody(
    migration,
    "gymapp_private.live_workout_progress_is_valid",
  );

  assert.match(validator, /immutable[\s\S]*security invoker[\s\S]*set search_path = ''/);
  assert.match(validator, /jsonb_array_length\(p_progress->'completedSets'\) > 120/);
  assert.match(validator, /pg_column_size\(p_progress\) > 65536/);
  assert.match(
    validator,
    /jsonb_typeof\(p_progress->'finishedAt'\) = 'string'[\s\S]*jsonb_typeof\(p_progress->'undoableSetId'\) <> 'null'[\s\S]*return false;/,
  );
  assert.match(
    validator,
    /jsonb_array_length\(p_progress->'completedSets'\) = 0[\s\S]*jsonb_typeof\(p_progress->'undoableSetId'\) = 'null'/,
  );
  assert.match(
    validator,
    /jsonb_typeof\(p_progress->'undoableSetId'\) = 'null'[\s\S]*return true;[\s\S]*p_progress->>'undoableSetId' = last_set_id/,
  );
  assert.match(
    migration,
    /revoke all on function gymapp_private\.live_workout_progress_is_valid\(jsonb\)[\s\S]*from public, anon, authenticated, service_role/,
  );
});

test("finish RPC seals progress atomically while retaining auth, ownership, replay, and CAS gates", () => {
  const finish = functionBody(migration, "public.social_finish_live_workout");

  assert.match(finish, /volatile[\s\S]*security definer[\s\S]*set search_path = ''/);
  assert.match(
    finish,
    /live_gateway_require_session\(p_caller_user_id, p_session_id\)/,
  );
  assert.match(finish, /live_workout_lock_pair_for_room\([\s\S]*p_caller_user_id/);
  assert.match(finish, /live_workout_rooms[\s\S]*for update;/);
  assert.match(finish, /live_workout_members[\s\S]*order by member\.user_id[\s\S]*for update;/);
  assert.match(finish, /live_workout_progress[\s\S]*for update;/);
  assert.match(finish, /not gymapp_private\.social_pair_is_accepted/);
  assert.match(finish, /live_workout_receipt_replay/);
  assert.ok(
    finish.indexOf("live_workout_receipt_replay") <
      finish.indexOf("if room_row.status = 'active'"),
    "idempotent replay must precede lifecycle rejection",
  );
  assert.match(finish, /progress_row\.revision <> p_expected_progress_revision/);
  assert.match(
    finish,
    /set payload = progress\.payload \|\| pg_catalog\.jsonb_build_object\([\s\S]*'undoableSetId', null,[\s\S]*'finishedAt', mutation_time[\s\S]*revision = progress\.revision \+ 1/,
  );
  const sealingStart = finish.indexOf("-- Progress must finish");
  const progressSeal = finish.indexOf(
    "update gymapp_private.live_workout_progress",
    sealingStart,
  );
  const membershipFinish = finish.indexOf("set state = 'finished'", progressSeal);
  assert.ok(
    sealingStart >= 0 && progressSeal > sealingStart && membershipFinish > progressSeal,
    "progress must seal before membership lifecycle advances",
  );
  assert.match(
    migration,
    /revoke all on function public\.social_finish_live_workout\(uuid, uuid, text, uuid, bigint\)[\s\S]*from public, anon, authenticated, service_role;[\s\S]*grant execute on function public\.social_finish_live_workout\(uuid, uuid, text, uuid, bigint\)[\s\S]*to service_role;/,
  );
  assert.match(migration, /finish_function\.proowner::text[\s\S]*live_finish_owner/);
  assert.match(migration, /finish_function\.proconfig @> array\['search_path=""'\]/);
});

test("Android, iOS, and PWA accept the same sealed and reconciled progress states", () => {
  assert.match(
    android,
    /setOf\("version", "revision", "completedSets", "undoableSetId", "finishedAt"\)/,
  );
  assert.match(android, /completedSets\.isNotEmpty\(\) \|\| undoableSetId == null/);
  assert.match(android, /finishedAt == null \|\| undoableSetId == null/);
  assert.doesNotMatch(
    android,
    /\(undoableSetId == null\) == completedSets\.isEmpty\(\)/,
  );

  assert.match(ios, /guard !\(finishedAt != nil && undoableSetID != nil\)/);
  assert.match(
    pwa,
    /finishedAt !== null && undoableSetId !== null[\s\S]*Live workout finish state is invalid/,
  );

  assert.match(
    androidTests,
    /snapshot parser accepts production finished progress without an undo marker/,
  );
  assert.match(
    androidTests,
    /snapshot parser accepts reconciled nonempty progress without an undo marker/,
  );
  assert.match(
    androidTests,
    /snapshot parser rejects finished progress that retains an undo marker/,
  );
  assert.match(
    androidTests,
    /snapshot parser rejects an undo marker when completed progress is empty/,
  );
});

test("pgTAP fixture covers canonical positive and negative vectors transactionally", () => {
  assert.match(fixture, /^begin;\n/);
  assert.match(fixture, /select plan\(6\);/);
  assert.match(fixture, /server-reconciled unfinished progress may have no undo marker/);
  assert.match(fixture, /finished progress is canonical when its undo marker is cleared/);
  assert.match(fixture, /finished progress rejects a retained undo marker/);
  assert.match(fixture, /select \* from finish\(\);\s*\n\s*rollback;\s*$/);
});
