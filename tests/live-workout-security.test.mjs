import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const preparePath =
  "supabase/migrations/20260810075709_prepare_live_shared_workouts.sql";
const apiPath =
  "supabase/migrations/20260810075721_activate_live_shared_workout_api.sql";
const realtimePath =
  "supabase/migrations/20260810075729_activate_live_workout_realtime.sql";
const legacyPreparePath =
  "supabase/migrations/20260809202407_prepare_friend_social_graph.sql";
const legacyApiPath =
  "supabase/migrations/20260809202432_activate_friend_social_api.sql";

function functionBody(sql, functionName) {
  const start = sql.indexOf(`create or replace function ${functionName}`);
  assert.ok(start >= 0, `${functionName} must exist`);
  const end = sql.indexOf("\n$function$;", start);
  assert.ok(end > start, `${functionName} must use a bounded function body`);
  return sql.slice(start, end + "\n$function$;".length);
}

test("live workout storage is private, RPC-only, bounded, and max-two", async () => {
  const prepare = await readFile(preparePath, "utf8");
  const privateTables = [
    "live_workout_rooms",
    "live_workout_members",
    "live_workout_progress",
    "live_workout_operation_receipts",
  ];

  for (const table of privateTables) {
    assert.match(prepare, new RegExp(`create table gymapp_private\\.${table} \\(`));
    assert.match(
      prepare,
      new RegExp(`alter table gymapp_private\\.${table} enable row level security`),
    );
    assert.match(
      prepare,
      new RegExp(
        `revoke all on table gymapp_private\\.${table}\\s+from public, anon, authenticated, service_role`,
      ),
    );
  }
  assert.doesNotMatch(prepare, /create policy[\s\S]{0,120}gymapp_private\.live_/i);
  assert.match(
    prepare,
    /constraint live_workout_members_room_role_key unique \(room_id, role\)/,
  );
  assert.match(prepare, /primary key \(room_id, user_id\)/);
  assert.match(prepare, /role text not null check \(role in \('owner', 'participant'\)\)/);
  assert.match(prepare, /jsonb_array_length\(p_progress->'completedSets'\) > 120/);
  assert.match(prepare, /pg_column_size\(p_operation\)|pg_column_size\(request\) <= 8192/);
  assert.doesNotMatch(
    prepare,
    /pg_catalog\.(?:coalesce|greatest|least|nullif)\s*\(/i,
  );
});

test("the plan is frozen and server assigns deterministic exercise and set ids", async () => {
  const prepare = await readFile(preparePath, "utf8");
  const validator = functionBody(
    prepare,
    "gymapp_private.validate_live_workout_plan",
  );
  const roomGuard = functionBody(
    prepare,
    "gymapp_private.guard_live_workout_room",
  );

  assert.match(validator, /validate_social_workout\(p_workout\)/);
  assert.match(validator, /'exerciseId', 'e_' \|\| pg_catalog\.lpad/);
  assert.match(validator, /'setId', 's_' \|\| pg_catalog\.lpad/);
  assert.match(roomGuard, /Live workout plan is immutable/);
  assert.match(roomGuard, /new\.plan is distinct from old\.plan/);
  assert.match(roomGuard, /new\.payload_purged_at is not null/);
  assert.match(
    roomGuard,
    /old\.status = 'waiting' and new\.status in \('ready', 'cancelled', 'expired'\)/,
  );
  assert.match(
    roomGuard,
    /old\.status = 'ready' and new\.status in \('active', 'cancelled', 'expired'\)/,
  );
  assert.doesNotMatch(prepare, /update gymapp_private\.live_workout_rooms[\s\S]{0,120}set plan = (?!null)/i);
});

test("all live RPCs are service-gateway-only and bind verified user plus session", async () => {
  const api = await readFile(apiPath, "utf8");
  const signatures = [
    "social_live_workout_inbox\\(uuid, uuid\\)",
    "social_send_live_workout_invite\\(uuid, uuid, text, uuid, jsonb\\)",
    "social_respond_live_workout_invite\\(uuid, uuid, text, text, bigint, uuid\\)",
    "social_start_live_workout\\(uuid, uuid, text, bigint, uuid\\)",
    "social_live_workout_snapshot\\(uuid, uuid, text\\)",
    "social_apply_live_workout_operation\\(uuid, uuid, text, uuid, bigint, jsonb\\)",
    "social_finish_live_workout\\(uuid, uuid, text, uuid, bigint\\)",
    "social_leave_live_workout\\(uuid, uuid, text, uuid, bigint\\)",
    "social_cancel_live_workout\\(uuid, uuid, text, uuid, bigint\\)",
  ];
  const sessionGuard = functionBody(
    api,
    "gymapp_private.live_gateway_require_session",
  );

  assert.match(sessionGuard, /from auth\.sessions as session/);
  assert.match(sessionGuard, /session\.id = p_session_id/);
  assert.match(sessionGuard, /session\.user_id = p_caller_user_id/);
  assert.doesNotMatch(sessionGuard, /auth\.(?:uid|jwt)\(/);

  for (const signature of signatures) {
    assert.match(
      api,
      new RegExp(
        `revoke all on function public\\.${signature}\\s+from public, anon, authenticated, service_role`,
      ),
    );
    assert.match(
      api,
      new RegExp(`grant execute on function public\\.${signature}\\s+to service_role`),
    );
  }
  assert.doesNotMatch(
    api,
    /grant execute on function public\.social_(?:live|send_live|respond_live|start_live|apply_live|finish_live|leave_live|cancel_live)[^;]+to authenticated/i,
  );
  assert.equal(
    (api.match(/live_gateway_require_session\(p_caller_user_id, p_session_id\)/g) || [])
      .length,
    9,
  );
});

test("join is ready-only and owner explicitly starts both progress rows", async () => {
  const api = await readFile(apiPath, "utf8");
  const respond = functionBody(
    api,
    "public.social_respond_live_workout_invite",
  );
  const start = functionBody(api, "public.social_start_live_workout");

  assert.match(respond, /p_decision not in \('accept', 'decline'\)/);
  assert.match(respond, /set state = 'joined'/);
  assert.match(respond, /set status = 'ready'/);
  assert.doesNotMatch(respond, /set status = 'active'/);
  assert.doesNotMatch(respond, /insert into gymapp_private\.live_workout_progress/);

  assert.match(start, /caller_member\.role <> 'owner'/);
  assert.match(start, /room_row\.status <> 'ready'/);
  assert.match(start, /member\.state <> 'joined'/);
  assert.match(start, /set status = 'active'/);
  assert.match(start, /active_expires_at = mutation_time \+ interval '24 hours'/);
  assert.match(start, /insert into gymapp_private\.live_workout_progress/);
  assert.ok(
    start.indexOf("set status = 'active'") <
      start.indexOf("insert into gymapp_private.live_workout_progress"),
    "room must be active before the progress guard sees inserts",
  );
});

test("concurrent accepts and starts serialize per user and reject another open room", async () => {
  const [api, legacyPrepare] = await Promise.all([
    readFile(apiPath, "utf8"),
    readFile(legacyPreparePath, "utf8"),
  ]);
  const lockPair = functionBody(
    api,
    "gymapp_private.live_workout_lock_pair_for_room",
  );
  const canonicalAccountLocks = functionBody(
    legacyPrepare,
    "gymapp_private.social_lock_pair",
  );
  const respond = functionBody(
    api,
    "public.social_respond_live_workout_invite",
  );
  const start = functionBody(api, "public.social_start_live_workout");

  assert.match(lockPair, /social_lock_pair\(p_caller_user_id, peer_user_id\)/);
  assert.match(canonicalAccountLocks, /gymapp-social-user:' \|\| low_user_id::text/);
  assert.match(canonicalAccountLocks, /gymapp-social-user:' \|\| high_user_id::text/);
  assert.ok(
    canonicalAccountLocks.indexOf("gymapp-social-user:' || low_user_id::text") <
      canonicalAccountLocks.indexOf("gymapp-social-user:' || high_user_id::text"),
    "two accepts sharing either account must serialize in canonical UUID order",
  );
  assert.ok(
    respond.indexOf("live_workout_lock_pair_for_room") <
      respond.indexOf("for update;"),
    "accept must acquire canonical per-account locks before room rows",
  );
  assert.match(respond, /member\.room_id <> p_room_id/);
  assert.match(respond, /open_room\.status in \('waiting', 'ready', 'active'\)/);
  assert.match(respond, /User already has an open live workout/);
  assert.ok(
    start.indexOf("live_workout_lock_pair_for_room") < start.indexOf("for update;"),
    "start races must use the same account-before-row lock order",
  );
  assert.match(start, /member\.user_id in \(p_caller_user_id, peer_user_id\)/);
  assert.match(start, /A participant already has another open live workout/);
  assert.match(start, /room_row\.revision <> p_expected_room_revision/);
});

test("set operations are caller-owned, CAS-protected, bounded, and exactly idempotent", async () => {
  const api = await readFile(apiPath, "utf8");
  const apply = functionBody(
    api,
    "public.social_apply_live_workout_operation",
  );
  const replay = functionBody(
    api,
    "gymapp_private.live_workout_receipt_replay",
  );

  assert.match(apply, /operation_kind not in \('complete_set', 'undo_set'\)/);
  assert.match(apply, /pg_catalog\.pg_column_size\(p_operation\) > 4096/);
  assert.match(apply, /weight_value not between 0 and 1000000/);
  assert.match(apply, /reps_value not between 1 and 10000/);
  assert.match(apply, /progress\.user_id = p_caller_user_id/);
  assert.doesNotMatch(apply, /progress\.user_id = peer_user_id/);
  assert.match(apply, /progress_row\.revision <> p_expected_progress_revision/);
  assert.match(apply, /Only the latest own set can be undone/);
  assert.match(apply, /live_workout_store_receipt/);

  assert.match(replay, /receipt_row\.request is distinct from p_request/);
  assert.match(replay, /Client operation id was reused with a different request/);
  assert.match(replay, /return receipt_row\.result/);
});

test("durable operation receipts replay before lifecycle and CAS rejection", async () => {
  const api = await readFile(apiPath, "utf8");
  const cases = [
    ["public.social_respond_live_workout_invite", "if room_row.status = 'waiting'"],
    ["public.social_start_live_workout", "if room_row.status = 'ready'"],
    ["public.social_apply_live_workout_operation", "if room_row.status = 'active'"],
    ["public.social_finish_live_workout", "if room_row.status = 'active'"],
    ["public.social_leave_live_workout", "if room_row.status not in ('ready', 'active')"],
    [
      "public.social_cancel_live_workout",
      "if room_row.status not in ('waiting', 'ready', 'active')",
    ],
  ];

  for (const [name, firstLifecycleCheck] of cases) {
    const body = functionBody(api, name);
    const replay = body.indexOf("if replayed_result is not null then");
    const lifecycle = body.indexOf(firstLifecycleCheck);
    assert.ok(replay >= 0 && lifecycle >= 0 && replay < lifecycle, `${name} must replay first`);
  }
});

test("finish respects storage guard order and completes only after both members finish", async () => {
  const api = await readFile(apiPath, "utf8");
  const finish = functionBody(api, "public.social_finish_live_workout");
  const progressUpdate = finish.indexOf(
    "update gymapp_private.live_workout_progress as progress",
  );
  const memberUpdate = finish.indexOf(
    "update gymapp_private.live_workout_members as member",
    progressUpdate,
  );
  const roomUpdate = finish.indexOf(
    "update gymapp_private.live_workout_rooms as room",
    memberUpdate,
  );

  assert.ok(progressUpdate >= 0 && progressUpdate < memberUpdate && memberUpdate < roomUpdate);
  assert.match(finish, /pg_catalog\.bool_and\(member\.state = 'finished'\)/);
  assert.match(finish, /case when all_finished then 'completed' else room\.status end/);
  assert.match(finish, /close_reason = case when all_finished then 'completed' else null end/);
});

test("a guest who finished first can still leave without erasing finish history", async () => {
  const [prepare, api] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(apiPath, "utf8"),
  ]);
  const memberGuard = functionBody(
    prepare,
    "gymapp_private.guard_live_workout_member",
  );
  const leave = functionBody(api, "public.social_leave_live_workout");

  assert.match(
    prepare,
    /state = 'left'[\s\S]{0,120}joined_at is not null[\s\S]{0,120}departed_at is not null/,
  );
  assert.match(
    prepare,
    /state = 'revoked'[\s\S]{0,120}finished_at is null[\s\S]{0,120}departed_at is not null/,
  );
  assert.match(memberGuard, /old\.state = 'finished' and new\.state = 'left'/);
  assert.doesNotMatch(memberGuard, /old\.state = 'finished' and new\.state = 'revoked'/);
  assert.match(leave, /caller_member\.state not in \('joined', 'finished'\)/);
  assert.match(
    leave,
    /set state = 'left'[\s\S]*member\.user_id = p_caller_user_id[\s\S]*member\.state in \('joined', 'finished'\)/,
  );
  assert.match(
    leave,
    /set state = 'revoked'[\s\S]*member\.user_id <> p_caller_user_id[\s\S]*member\.state in \('invited', 'joined'\)/,
  );
  assert.doesNotMatch(leave, /set finished_at = null/);
});

test("remove, block, account deletion, expiry, purge, and cron close durable rooms", async () => {
  const api = await readFile(apiPath, "utf8");
  const closePair = functionBody(
    api,
    "gymapp_private.close_live_workout_rooms_for_pair",
  );
  const cleanup = functionBody(api, "gymapp_private.cleanup_live_workouts");
  const deleteTrigger = functionBody(
    api,
    "gymapp_private.auth_user_close_live_workouts",
  );

  assert.match(closePair, /room\.status in \('waiting', 'ready', 'active'\)/);
  assert.match(closePair, /set status = 'cancelled'/);
  assert.match(closePair, /member\.state in \('invited', 'joined'\)/);
  assert.match(api, /after update of status on gymapp_private\.friendships/);
  assert.match(api, /after insert on gymapp_private\.friend_blocks/);
  assert.match(api, /before delete on auth\.users/);
  assert.match(deleteTrigger, /'account_deleted'/);

  assert.match(cleanup, /for update of room skip locked/);
  assert.match(cleanup, /limit p_limit/);
  assert.match(cleanup, /interval '24 hours'/);
  assert.match(cleanup, /interval '30 days'/);
  assert.match(cleanup, /interval '31 days'/);
  assert.ok(
    cleanup.indexOf("delete from gymapp_private.live_workout_operation_receipts") <
      cleanup.indexOf("set plan = null"),
    "terminal operation payloads must be deleted with the plan/progress retention boundary",
  );
  assert.match(api, /create extension if not exists pg_cron with schema pg_catalog/);
  assert.match(api, /gymapp-live-workout-cleanup-v1/);
  assert.match(api, /cleanup_live_workouts\(100\)/);
});

test("Realtime is private personal read-only invalidation, never shared state transport", async () => {
  const realtime = await readFile(realtimePath, "utf8");
  const broadcaster = functionBody(
    realtime,
    "gymapp_private.broadcast_live_workout_room",
  );

  assert.match(realtime, /on realtime\.messages\s+for select\s+to authenticated/);
  assert.match(realtime, /realtime\.messages\.extension = 'broadcast'/);
  assert.match(realtime, /create or replace function gymapp_private\.realtime_has_current_auth_session\(\)/);
  assert.match(realtime, /gymapp_private\.has_current_auth_session\(\(select auth\.uid\(\)\)\)/);
  assert.match(realtime, /and \(select gymapp_private\.realtime_has_current_auth_session\(\)\)/);
  assert.match(realtime, /grant execute on function gymapp_private\.realtime_has_current_auth_session\(\)[\s\S]*to authenticated/);
  assert.match(realtime, /has_function_privilege\([\s\S]*'anon',[\s\S]*'gymapp_private\.realtime_has_current_auth_session\(\)'/);
  assert.match(realtime, /'gymapp:user:' \|\| \(select auth\.uid\(\)\)::text/);
  assert.doesNotMatch(realtime, /create policy[\s\S]{0,120}for insert/i);
  assert.match(realtime, /Competing authenticated Realtime SELECT policies must be removed/);
  assert.match(realtime, /personal Realtime read policy is not the sole authenticated SELECT boundary/);
  assert.doesNotMatch(realtime, /(?:create|alter|drop)\s+(?:table|function|trigger)[\s\S]{0,80}realtime\./i);
  assert.match(broadcaster, /'gymapp_live_changed'/);
  assert.match(broadcaster, /'roomRevision', room_revision/);
  assert.match(broadcaster, /'gymapp:user:' \|\| recipient\.user_id::text/);
  assert.match(broadcaster, /true\s*\n\s*\)/);
  assert.doesNotMatch(broadcaster, /plan|completedSets|weight|reps|displayName|email/i);
  assert.match(
    realtime,
    /'invite', 'joined', 'started', 'progress',[\s\S]*'participant_finished', 'room_closed'/,
  );
});

test("v3.0.4 static-copy invite API remains separate and unchanged", async () => {
  const [legacyPrepare, legacyApi, api] = await Promise.all([
    readFile(legacyPreparePath, "utf8"),
    readFile(legacyApiPath, "utf8"),
    readFile(apiPath, "utf8"),
  ]);

  assert.match(legacyPrepare, /Static bounded shared-workout v1 invitations/);
  assert.match(legacyPrepare, /not a live workout synchronization channel/);
  assert.match(legacyApi, /public\.social_workout_inbox\(\)/);
  assert.match(legacyApi, /public\.social_send_workout_invite\(text, uuid, jsonb\)/);
  assert.doesNotMatch(api, /create or replace function public\.social_workout_inbox\(\)/);
  assert.doesNotMatch(api, /create or replace function public\.social_send_workout_invite\(/);
});
