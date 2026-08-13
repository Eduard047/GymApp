import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260813111115_start_live_on_accept_and_add_friend_workout_pages.sql";
const activationGuardMigrationPath =
  "supabase/migrations/20260813112014_allow_waiting_live_room_activation.sql";
const activationGuardRuntimePath =
  "supabase/tests/live_workout_waiting_activation_guard.sql";
const [migration, activationGuardMigration, activationGuardRuntime, androidFriend, androidFriendsViewModel, iosFriends] = await Promise.all([
  readFile(migrationPath, "utf8"),
  readFile(activationGuardMigrationPath, "utf8"),
  readFile(activationGuardRuntimePath, "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/FriendDetailScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/FriendsViewModel.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/LeaderboardView.swift", "utf8")
]);

test("forward guard migration permits only invariant-safe waiting-to-active activation", () => {
  assert.match(activationGuardMigration, /create or replace function gymapp_private\.guard_live_workout_room\(\)/i);
  assert.match(activationGuardMigration, /old\.status = 'waiting'[\s\S]{0,120}new\.status = 'active'/i);
  assert.match(activationGuardMigration, /new\.started_at is not null/i);
  assert.match(activationGuardMigration, /new\.active_expires_at = new\.started_at \+ interval '24 hours'/i);
  assert.match(activationGuardMigration, /new\.ended_at is null[\s\S]{0,80}new\.close_reason is null/i);
  assert.match(activationGuardMigration, /Live workout room identity is immutable/i);
  assert.match(activationGuardMigration, /Live workout plan is immutable/i);
  assert.match(activationGuardMigration, /revision must advance exactly once/i);
  assert.match(activationGuardMigration, /time cannot move backwards/i);
  assert.match(activationGuardMigration, /revoke all on function gymapp_private\.guard_live_workout_room\(\)[\s\S]*from public, anon, authenticated, service_role/i);
  assert.match(activationGuardRuntime, /^begin;/i);
  assert.match(activationGuardRuntime, /select lives_ok\([\s\S]*status = 'active'/i);
  assert.match(activationGuardRuntime, /select throws_ok\([\s\S]*active_expires_at = '2026-08-14 10:02:00\+00'/i);
  assert.match(activationGuardRuntime, /select \* from finish\(\);[\s\S]*rollback;/i);
});

function sqlFunction(name) {
  const marker = `function ${name}`;
  const start = migration.indexOf(marker);
  assert.notEqual(start, -1, `Missing SQL function ${name}`);
  const end = migration.indexOf("$function$;", start);
  assert.notEqual(end, -1, `Unterminated SQL function ${name}`);
  return migration.slice(start, end + "$function$;".length);
}

test("detail consent is independent, default-deny, CAS-bound, and least-privilege", () => {
  assert.match(
    migration,
    /add column if not exists share_workout_details boolean not null default false/
  );
  const update = sqlFunction("public.social_update_workout_detail_privacy");
  assert.match(update, /for update/);
  assert.match(update, /revision <> p_expected_revision/);
  assert.match(update, /revision = settings\.revision \+ 1/);
  assert.match(migration, /revoke all on function public\.social_update_workout_detail_privacy/);
  assert.match(
    migration,
    /grant execute on function public\.social_update_workout_detail_privacy\(boolean, bigint\)[\s\S]*?to authenticated/
  );
  assert.doesNotMatch(
    migration,
    /grant execute on function public\.social_update_workout_detail_privacy\(boolean, bigint\)[\s\S]*?to anon/
  );
});

test("friend capability and detail page fail closed at the database boundary", () => {
  const capability = sqlFunction("public.social_friend_workout_detail_capability");
  const page = sqlFunction("public.social_friend_workout_page");

  for (const source of [capability, page]) {
    assert.match(source, /social_require_caller\('friend_details'\)/);
    assert.match(source, /social_pair_is_accepted/);
    assert.match(source, /message = 'Social resource unavailable\.'/);
    assert.match(source, /set search_path = ''/);
  }
  assert.match(capability, /share_recent_workouts and settings\.share_workout_details/);
  assert.match(page, /not target_settings\.share_recent_workouts/);
  assert.match(page, /not target_settings\.share_workout_details/);
  assert.match(page, /p_limit is distinct from 5/);
  assert.match(page, /p_cursor is not null/);
  assert.match(page, /projection\.source_revision = state\.updated_at/);
  assert.match(page, /quarantine\.user_id is null/);
  assert.match(page, /p_expected_activity_revision is distinct from activity_revision/);
  assert.match(page, /workout_set_position <= 100/);
  assert.match(page, /exercise_set_position <= 20/);
  assert.match(page, /exercise_position <= 20/);
  assert.match(page, /'nextCursor', next_cursor/);
  assert.match(page, /null::text/);
});

test("friend history excludes only future sessions and pseudonymous IDs omit raw state", () => {
  const strictProjection = sqlFunction(
    "gymapp_private.social_friend_activity_from_state"
  );
  const details = sqlFunction("public.social_friend_details");
  const page = sqlFunction("public.social_friend_workout_page");

  assert.match(strictProjection, /clock_timestamp\(\)/);
  assert.match(strictProjection, /jsonb_agg\(session\.value order by session\.ordinality\)/);
  assert.doesNotMatch(strictProjection, /interval '24 hours'/);
  assert.match(details, /if has_future_session then/);
  assert.match(details, /social_friend_activity_from_state\(state_value\)/);
  assert.match(page, /target_profile\.public_id/);
  assert.match(page, /activity_revision::text/);
  assert.match(page, /session\.workout_millis::text/);
  assert.match(page, /session\.session_number::text/);
  assert.doesNotMatch(page, /session_value::text/);
  assert.doesNotMatch(page, /'note'|'rawState'|'state'/);
});

test("privacy and relationship revocation send only opaque account-bound invalidations", () => {
  const settings = sqlFunction("gymapp_private.broadcast_social_settings_change");
  const relationship = sqlFunction(
    "gymapp_private.broadcast_social_relationship_change"
  );
  for (const broadcast of [settings, relationship]) {
    assert.match(broadcast, /'version', 1/);
    assert.match(broadcast, /'kind', 'privacy_changed'/);
    assert.match(broadcast, /'gymapp_social_changed'/);
    assert.match(broadcast, /'gymapp:user:' \|\| recipient_user_id::text/);
    assert.doesNotMatch(
      broadcast,
      /settingsRevision|share_workout_details|share_recent_workouts|profileId/
    );
  }
  assert.match(
    migration,
    /create trigger friendships_broadcast_social_change[\s\S]*?after update of status/
  );
  assert.match(
    migration,
    /when \(old\.status is distinct from new\.status\)/
  );
});

test("invite acceptance atomically starts exactly two progress lanes and replays by receipt", () => {
  const accept = sqlFunction("public.social_respond_live_workout_invite");
  const grants = migration.slice(
    migration.indexOf(
      "revoke all on function public.social_respond_live_workout_invite",
      migration.indexOf("create or replace function public.social_respond_live_workout_invite")
    ),
    migration.indexOf("-- The direct waiting -> active transition")
  );
  assert.match(accept, /live_gateway_require_session/);
  assert.match(accept, /social_pair_is_accepted/);
  assert.match(accept, /live_workout_receipt_replay/);
  assert.match(accept, /where progress\.room_id = p_room_id/);
  assert.match(accept, /member\.user_id in \(p_caller_user_id, peer_user_id\)/);
  assert.match(accept, /member\.room_id <> p_room_id/);
  assert.match(accept, /set status = 'active'/);
  assert.match(accept, /insert into gymapp_private\.live_workout_progress/);
  assert.match(accept, /get diagnostics inserted_progress_count = row_count/);
  assert.match(accept, /inserted_progress_count <> 2/);
  assert.match(accept, /live_workout_store_receipt/);
  assert.match(
    grants,
    /grant execute on function public\.social_respond_live_workout_invite\([\s\S]*?to service_role/
  );
  assert.doesNotMatch(
    grants,
    /grant execute on function public\.social_respond_live_workout_invite\([\s\S]*?to authenticated/
  );
});

test("friend exact workouts stay ephemeral and expose no owner mutation actions", () => {
  const androidDetail = androidFriend.slice(
    androidFriend.indexOf("private fun FriendWorkoutDetail"),
    androidFriend.indexOf("internal sealed interface FriendRecordMetric")
  );
  const iosDetail = iosFriends.slice(
    iosFriends.indexOf("private struct FriendWorkoutReadOnlyDetailView"),
    iosFriends.indexOf("private struct FriendWorkoutPickerSheet")
  );

  for (const detail of [androidDetail, iosDetail]) {
    assert.doesNotMatch(detail, /deleteWorkout|saveWorkout|insertWorkout|shareWorkout/);
    assert.match(detail, /read.only|Read only|read_only/i);
  }
  assert.match(androidDetail, /editable = false/);
  assert.match(iosDetail, /editable: false/);
});

test("optional exact-detail failures keep authorized summaries visible", () => {
  assert.match(androidFriendsViewModel, /friendSummaryFallbackState/);
  assert.match(androidFriendsViewModel, /selectedFriendDetails = details/);
  assert.match(androidFriendsViewModel, /catch \(_: Throwable\)[\s\S]*?friendSummaryFallbackState/);

  const iosLoad = iosFriends.slice(
    iosFriends.indexOf("private func load() async"),
    iosFriends.indexOf("private func removeFriend() async")
  );
  assert.ok(
    iosLoad.indexOf("details = loaded") <
      iosLoad.indexOf("socialFriendWorkoutDetailCapability"),
    "iOS must publish summaries before requesting optional exact detail"
  );
  assert.match(iosLoad, /Exact-set availability is optional/);
  assert.match(iosLoad, /friendWorkoutDetailsAvailable = false/);
});
