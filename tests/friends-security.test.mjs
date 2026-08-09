import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const preparePath =
  "supabase/migrations/20260809202407_prepare_friend_social_graph.sql";
const backfillPath =
  "supabase/migrations/20260809202422_backfill_friend_activity_projection.sql";
const activatePath =
  "supabase/migrations/20260809202432_activate_friend_social_api.sql";
const nfcRecoveryPath =
  "supabase/migrations/20260809210834_normalize_friend_exercise_names_nfc.sql";

function functionBody(sql, functionName) {
  const start = sql.indexOf(`create or replace function ${functionName}`);
  assert.ok(start >= 0, `${functionName} must exist`);
  const end = sql.indexOf("\n$function$;", start);
  assert.ok(end > start, `${functionName} must use a bounded function body`);
  return sql.slice(start, end + "\n$function$;".length);
}

test("social storage is private, RLS-enabled, RPC-only, and forward-only", async () => {
  const [prepare, backfill, activate] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(backfillPath, "utf8"),
    readFile(activatePath, "utf8"),
  ]);

  const privateTables = [
    "social_settings",
    "friendships",
    "friend_blocks",
    "social_activity_projection",
    "social_rate_limits",
    "social_workout_invites",
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
  assert.doesNotMatch(
    `${prepare}\n${backfill}\n${activate}`,
    /create policy[\s\S]{0,160}gymapp_private\.(?:social_|friend)/i,
  );
  assert.doesNotMatch(
    `${prepare}\n${backfill}\n${activate}`,
    /alter table gymapp_private\.(?:user_state_quarantine|user_state_progression)\s+(?:enable|force) row level security/i,
  );
  assert.doesNotMatch(
    `${prepare}\n${backfill}\n${activate}`,
    /\b(?:drop|truncate)\s+(?:table\s+)?(?:public\.(?:profiles|user_states)|gymapp_private\.user_state_)/i,
  );
  assert.doesNotMatch(
    `${prepare}\n${backfill}\n${activate}`,
    /pg_catalog\.(?:coalesce|greatest|least|nullif)\s*\(/i,
    "PostgreSQL special forms cannot be schema-qualified as ordinary functions",
  );
  assert.match(activate, /exists \([\s\S]*from pg_catalog\.pg_policy[\s\S]*Private social relation/);
});

test("activity projection is revision-bound, bounded, and excludes private raw state", async () => {
  const [prepare, backfill, activate] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(backfillPath, "utf8"),
    readFile(activatePath, "utf8"),
  ]);
  const projection = functionBody(
    prepare,
    "gymapp_private.social_activity_from_state",
  );
  const detail = functionBody(activate, "public.social_friend_details");

  assert.match(projection, /perform gymapp_private\.validate_user_state\(p_state\)/);
  assert.match(projection, /interval '24 hours'/);
  assert.match(projection, /limit 5/);
  assert.match(projection, /limit 100/);
  assert.match(projection, /identity_position <= 20/);
  assert.match(
    projection,
    /jsonb_typeof\(session\.session_value->'sets'\) is not distinct from 'array'/,
  );
  assert.match(projection, /'workoutDay'/);
  assert.match(projection, /'exerciseCount'/);
  assert.match(projection, /'setCount'/);
  assert.match(projection, /'bestWeightKg'/);
  assert.match(projection, /'bestReps'/);
  assert.match(projection, /'lastWorkoutDay'/);
  assert.doesNotMatch(projection, /->\s*'note'|->>\s*'note'/i);
  assert.doesNotMatch(projection, /->\s*'owner'|->>\s*'email'/i);
  assert.doesNotMatch(projection, /garmin|heart|health|diagnostic/i);

  const safeDisplayName = functionBody(
    prepare,
    "gymapp_private.social_safe_display_name",
  );
  assert.match(safeDisplayName, /public\.safe_leaderboard_display_name\(p_value\)/);
  assert.match(safeDisplayName, /social_name_is_safe\(safe_value\)/);
  assert.doesNotMatch(
    activate,
    /coalesce\(public\.safe_leaderboard_display_name/,
  );

  assert.match(prepare, /source_revision timestamptz not null/);
  assert.match(prepare, /user_states_refresh_social_activity/);
  assert.match(prepare, /old\.state is not distinct from new\.state/);
  assert.match(prepare, /set source_revision = new\.updated_at/);
  assert.match(backfill, /on conflict \(user_id\) do nothing/);
  assert.match(backfill, /activity\.source_revision = state\.updated_at/);
  assert.match(activate, /social activation refused a stale projection backfill/);

  assert.match(detail, /friendship\.status = 'accepted'|social_pair_is_accepted/);
  assert.match(detail, /social_pair_is_accepted\(caller_user_id, target_user_id\)/);
  assert.match(detail, /share_progress/);
  assert.match(detail, /share_recent_workouts/);
  assert.match(detail, /share_records/);
  assert.match(detail, /progression_row\.source_revision = state\.updated_at/);
  assert.match(detail, /activity_row\.source_revision = state\.updated_at/);
  assert.match(detail, /quarantine\.user_id is null/);
  assert.match(detail, /'integrity', 'self_reported'/);
  assert.doesNotMatch(detail, /state\.state|user_states\.state/);
  assert.match(activate, /coalesce\(settings\.share_progress, false\) as share_progress/);
});

test("exercise records keep weight and repetition maxima independent", async () => {
  const prepare = await readFile(preparePath, "utf8");
  const projection = functionBody(
    prepare,
    "gymapp_private.social_activity_from_state",
  );
  const fixture = [
    { weight: 140, reps: 2 },
    { weight: 60, reps: 18 },
  ];

  const expectedBestWeight = Math.max(...fixture.map((set) => set.weight));
  const expectedBestReps = Math.max(...fixture.map((set) => set.reps));
  assert.equal(expectedBestWeight, 140);
  assert.equal(expectedBestReps, 18);
  assert.notEqual(
    fixture.find((set) => set.weight === expectedBestWeight)?.reps,
    expectedBestReps,
    "the fixture must distinguish an independent repetition record",
  );
  assert.match(
    projection,
    /pg_catalog\.max\(set_row\.weight_value\) as best_weight/,
  );
  assert.match(
    projection,
    /pg_catalog\.max\(set_row\.reps_value\) as best_reps/,
  );
  assert.doesNotMatch(projection, /array_agg\([\s\S]*as best_(?:weight|reps)/);
});

test("recent workouts keep same-day sessions separate with deterministic order", async () => {
  const prepare = await readFile(preparePath, "utf8");
  const projection = functionBody(
    prepare,
    "gymapp_private.social_activity_from_state",
  );
  const fixture = [
    { sessionNumber: 1, workoutMillis: Date.UTC(2026, 7, 9, 8, 0, 0) },
    { sessionNumber: 2, workoutMillis: Date.UTC(2026, 7, 9, 18, 0, 0) },
  ];
  const days = fixture.map(({ workoutMillis }) =>
    new Date(workoutMillis).toISOString().slice(0, 10),
  );

  assert.deepEqual(days, ["2026-08-09", "2026-08-09"]);
  assert.match(
    projection,
    /order by workout_millis desc, session_number desc\s+limit 5/,
  );
  assert.match(
    projection,
    /order by summary\.workout_millis desc, summary\.session_number desc/,
  );
});

test("every public social RPC is live-session-bound with exact authenticated grants", async () => {
  const activate = await readFile(activatePath, "utf8");
  const rpcSignatures = [
    "social_dashboard\\(\\)",
    "social_friend_details\\(text\\)",
    "social_send_friend_request\\(text\\)",
    "social_respond_friend_request\\(text, text, bigint\\)",
    "social_cancel_friend_request\\(text, bigint\\)",
    "social_remove_friend\\(text, bigint\\)",
    "social_block_profile\\(text\\)",
    "social_unblock_profile\\(text\\)",
    "social_update_privacy\\(boolean, boolean, boolean, boolean, bigint\\)",
    "social_workout_inbox\\(\\)",
    "social_send_workout_invite\\(text, uuid, jsonb\\)",
    "social_respond_workout_invite\\(text, text, bigint\\)",
    "social_cancel_workout_invite\\(text, bigint\\)",
  ];

  const requireCaller = functionBody(
    activate,
    "gymapp_private.social_require_caller",
  );
  assert.match(requireCaller, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(requireCaller, /has_current_auth_session\(caller_user_id\)/);
  assert.match(requireCaller, /consume_social_rate_limit\(caller_user_id, p_action\)/);
  assert.doesNotMatch(
    requireCaller,
    /social_purge_expired_workout_payloads\(caller_user_id\)/,
  );

  const dashboard = functionBody(activate, "public.social_dashboard");
  const workoutInbox = functionBody(activate, "public.social_workout_inbox");
  assert.match(
    dashboard,
    /social_require_caller\('dashboard'\)[\s\S]*social_purge_expired_workout_payloads\(caller_user_id\)/,
  );
  assert.match(
    workoutInbox,
    /social_require_caller\('workout_inbox'\)[\s\S]*social_purge_expired_workout_payloads\(caller_user_id\)/,
  );
  assert.equal(
    (activate.match(/perform gymapp_private\.social_purge_expired_workout_payloads\(caller_user_id\)/g) || []).length,
    2,
  );

  for (const signature of rpcSignatures) {
    assert.match(
      activate,
      new RegExp(`revoke all on function public\\.${signature}\\s+from public, anon, authenticated, service_role`),
    );
    assert.match(
      activate,
      new RegExp(`grant execute on function public\\.${signature} to authenticated`),
    );
  }
  assert.match(activate, /security definer\s+set search_path = ''/g);
  assert.match(activate, /has_function_privilege\('anon', rpc_signature, 'EXECUTE'\)/);
  assert.match(activate, /has_function_privilege\('service_role', rpc_signature, 'EXECUTE'\)/);
  assert.doesNotMatch(
    activate,
    /grant execute on function public\.social_[^;]+ to (?:anon|service_role|public)/i,
  );
});

test("friend mutations use a canonical locked pair, caps, CAS, and immediate revocation", async () => {
  const [prepare, activate] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(activatePath, "utf8"),
  ]);
  const pairLock = functionBody(prepare, "gymapp_private.social_lock_pair");
  const send = functionBody(activate, "public.social_send_friend_request");
  const respond = functionBody(activate, "public.social_respond_friend_request");
  const remove = functionBody(activate, "public.social_remove_friend");
  const block = functionBody(activate, "public.social_block_profile");

  assert.match(prepare, /constraint friendships_pair_key unique \(user_low_id, user_high_id\)/);
  assert.match(prepare, /user_low_id::text < user_high_id::text/);
  assert.match(pairLock, /gymapp-social-user:/);
  assert.match(pairLock, /gymapp-social-pair:/);
  assert.equal((pairLock.match(/pg_advisory_xact_lock/g) || []).length, 3);

  assert.match(send, /'result', 'submitted_or_unavailable'/);
  assert.doesNotMatch(send, /not_found|unknown_profile|blocked_target/);
  assert.match(send, /friendship_row\.requester_user_id = target_user_id/);
  assert.match(send, /set status = 'accepted'/);
  assert.match(send, /caller_pending_count >= 25/);
  assert.match(send, /target_pending_count >= 100/);
  assert.match(send, /caller_accepted_count < 200/);
  assert.match(send, /target_accepted_count < 200/);

  assert.match(respond, /p_decision not in \('accept', 'decline'\)/);
  assert.match(respond, /friendship\.requester_user_id <> caller_user_id/);
  assert.match(respond, /for update/);
  assert.match(respond, /friendship_row\.revision = p_expected_revision \+ 1/);
  assert.match(respond, /friendship_row\.revision <> p_expected_revision/);
  assert.match(remove, /friendship_row\.status <> 'accepted'/);
  assert.match(remove, /social_cancel_pending_workout_invites/);
  assert.match(block, /insert into gymapp_private\.friend_blocks/);
  assert.match(block, /set status = 'removed'/);
  assert.match(block, /social_cancel_pending_workout_invites/);
});

test("all revisioned mutations reject null CAS and decision inputs", async () => {
  const activate = await readFile(activatePath, "utf8");
  const revisionedFunctions = [
    "public.social_respond_friend_request",
    "public.social_cancel_friend_request",
    "public.social_remove_friend",
    "public.social_update_privacy",
    "public.social_respond_workout_invite",
    "public.social_cancel_workout_invite",
  ];
  for (const functionName of revisionedFunctions) {
    assert.match(
      functionBody(activate, functionName),
      /p_expected_revision is null/,
      `${functionName} must not let SQL NULL bypass its CAS`,
    );
  }
  assert.match(
    functionBody(activate, "public.social_respond_friend_request"),
    /p_decision is null/,
  );
  assert.match(
    functionBody(activate, "public.social_respond_workout_invite"),
    /p_decision is null/,
  );
});

test("transactional rate-limit scope is explicit and generic send failures commit their charge", async () => {
  const [prepare, activate] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(activatePath, "utf8"),
  ]);
  const friendSend = functionBody(
    activate,
    "public.social_send_friend_request",
  );
  const workoutSend = functionBody(
    activate,
    "public.social_send_workout_invite",
  );

  assert.match(
    prepare,
    /token buckets for committed social RPC calls[\s\S]*rolls back a charge[\s\S]*perimeter rate limiting/,
  );
  assert.match(
    friendSend,
    /p_friend_code is null[\s\S]*return pg_catalog\.jsonb_build_object\('version', 1, 'result', 'submitted_or_unavailable'\)/,
  );
  assert.match(
    workoutSend,
    /when sqlstate '22023' or sqlstate '54000' then[\s\S]*return pg_catalog\.jsonb_build_object\('version', 1, 'result', 'submitted_or_unavailable'\)/,
  );
});

test("workout invitations admit only canonical bounded shared-workout v1 payloads", async () => {
  const [prepare, activate] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(activatePath, "utf8"),
  ]);
  const validator = functionBody(
    prepare,
    "gymapp_private.validate_social_workout",
  );
  const send = functionBody(activate, "public.social_send_workout_invite");

  assert.match(validator, /not \(p_workout \? 'version'\)/);
  assert.match(validator, /not \(p_workout \? 'exercises'\)/);
  assert.match(validator, /jsonb_object_keys\(exercise_value\)/);
  assert.match(validator, /not in \('catalogKey', 'name', 'sets'\)/);
  assert.match(validator, /jsonb_object_keys\(set_value\)/);
  assert.match(validator, /exercise_count not between 1 and 20/);
  assert.match(validator, /set_count not between 1 and 12/);
  assert.match(validator, /total_set_count > 120/);
  assert.match(validator, /exceeds 32 KiB/);
  assert.match(validator, /'\^\[a-z0-9_\]\{1,64\}\$'/);
  assert.match(validator, /weight_value not between 0 and 1000000/);
  assert.match(validator, /reps_value not between 1 and 10000/);
  assert.match(validator, /reps_value <> pg_catalog\.trunc\(reps_value\)/);
  assert.match(validator, /social_name_is_safe\(exercise_name\)/);
  assert.match(validator, /social_normalize_name\(exercise_name\)/);
  assert.match(validator, /duplicate exercise names/);
  assert.match(validator, /duplicate catalog keys/);
  assert.doesNotMatch(
    validator,
    /['"](?:note|date|owner|account|health|garmin|coach)['"]/i,
  );

  assert.match(send, /p_client_request_id::text !~ '\^\[0-9a-f\]\{8\}/);
  assert.match(send, /gymapp-social-workout-request:/);
  assert.match(send, /invite\.sender_user_id = caller_user_id/);
  assert.match(send, /invite\.client_request_id = p_client_request_id/);
  assert.match(send, /social_pair_is_accepted\(caller_user_id, target_user_id\)/);
  assert.match(send, /sender_pending_count >= 25/);
  assert.match(send, /recipient_pending_count >= 25/);
  assert.match(send, /request_time \+ interval '7 days'/);
  assert.match(send, /when sqlstate '22023' or sqlstate '54000'/);
  assert.match(prepare, /unique \(\s*sender_user_id, client_request_id\s*\)/);
});

test("server exercise identities use NFC and repair stale projections and invites", async () => {
  const recovery = await readFile(nfcRecoveryPath, "utf8");
  const normalizer = functionBody(
    recovery,
    "gymapp_private.social_normalize_name",
  );

  assert.match(normalizer, /pg_catalog\.normalize\(p_value\)/);
  assert.match(recovery, /composed_name text := 'Café'/);
  assert.match(recovery, /decomposed_name text := 'Cafe' \|\| pg_catalog\.chr\(769\)/);
  assert.match(recovery, /non_breaking_edge_name text := pg_catalog\.chr\(160\) \|\| 'Bench' \|\| pg_catalog\.chr\(160\)/);
  assert.match(recovery, /edge-whitespace-stable/);
  assert.match(recovery, /social_normalize_name\(p_value\) = ''/);
  assert.match(recovery, /Whitespace-only social exercise names remain valid/);
  assert.match(normalizer, /pg_catalog\.btrim\(\s*pg_catalog\.regexp_replace\(/);
  assert.match(recovery, /validate_social_workout[\s\S]*when sqlstate '22023'/);
  assert.match(recovery, /on conflict \(user_id\) do update[\s\S]*source_revision = excluded\.source_revision/);
  assert.match(recovery, /from public\.user_states as current_state[\s\S]*current_state\.updated_at = state_row\.updated_at/);
  assert.match(recovery, /current_quarantine\.user_id = current_state\.user_id/);
  assert.match(recovery, /where gymapp_private\.social_activity_projection\.source_revision = excluded\.source_revision/);
  assert.match(recovery, /for update[\s\S]*payload_purged_at = repair_time/);
  assert.doesNotMatch(recovery, /\b(?:drop|truncate)\s+(?:table\s+)?/i);
  assert.doesNotMatch(recovery, /grant\s+/i);
});

test("invite inbox and transitions preserve recipient ownership, replay safety, and payload secrecy", async () => {
  const activate = await readFile(activatePath, "utf8");
  const inbox = functionBody(activate, "public.social_workout_inbox");
  const respond = functionBody(
    activate,
    "public.social_respond_workout_invite",
  );
  const cancel = functionBody(
    activate,
    "public.social_cancel_workout_invite",
  );

  assert.match(inbox, /invite\.recipient_user_id = caller_user_id/);
  assert.match(inbox, /invite\.workout is not null/);
  assert.match(inbox, /invite\.status = 'accepted'/);
  assert.match(
    inbox,
    /invite\.status = 'pending' and invite\.expires_at > read_time/,
  );
  assert.match(
    inbox,
    /invite\.status = 'accepted'[\s\S]*invite\.responded_at > read_time - interval '30 days'/,
  );
  assert.match(
    inbox,
    /social_pair_is_accepted\(invite\.sender_user_id, caller_user_id\)/,
  );
  assert.match(inbox, /invite\.sender_user_id = caller_user_id/);
  assert.match(inbox, /invite\.summary is not null/);
  assert.match(
    inbox,
    /invite\.status in \('declined', 'cancelled', 'expired'\)[\s\S]*invite\.responded_at > read_time - interval '24 hours'/,
  );
  assert.match(inbox, /limit 25/g);
  assert.match(inbox, /'pendingIncomingCount'/);
  assert.match(inbox, /'workout', bounded\.workout/);
  const outgoingStart = inbox.indexOf("where invite.sender_user_id = caller_user_id");
  assert.ok(outgoingStart > 0);
  assert.doesNotMatch(inbox.slice(outgoingStart), /'workout', bounded\.workout/);

  assert.match(respond, /invite\.recipient_user_id = caller_user_id/);
  assert.match(respond, /p_decision not in \('accept', 'decline'\)/);
  assert.match(respond, /social_pair_is_accepted/);
  assert.match(respond, /invite_row\.expires_at <= mutation_time/);
  assert.match(respond, /invite_row\.revision = p_expected_revision \+ 1/);
  assert.match(respond, /invite_row\.revision <> p_expected_revision/);
  assert.match(
    respond,
    /invite_row\.status = 'accepted'[\s\S]*invite_row\.workout is null[\s\S]*interval '30 days'/,
  );
  assert.match(respond, /'workout', case when invite_row\.status = 'accepted'/);

  assert.match(cancel, /invite\.sender_user_id = caller_user_id/);
  assert.match(cancel, /invite_row\.status = 'cancelled'/);
  assert.match(cancel, /invite_row\.revision = p_expected_revision \+ 1/);
  assert.match(cancel, /invite_row\.revision <> p_expected_revision/);
  assert.match(cancel, /invite_row\.expires_at <= mutation_time/);
});

test("workout payload retention is bounded without losing idempotency tombstones", async () => {
  const [prepare, activate] = await Promise.all([
    readFile(preparePath, "utf8"),
    readFile(activatePath, "utf8"),
  ]);
  const purge = functionBody(
    activate,
    "gymapp_private.social_purge_expired_workout_payloads",
  );

  assert.match(prepare, /workout jsonb,/);
  assert.match(prepare, /summary jsonb,/);
  assert.match(prepare, /payload_purged_at timestamptz/);
  assert.match(prepare, /payload_purged_at is not null[\s\S]*status <> 'pending'[\s\S]*workout is null/);
  assert.match(prepare, /payload_purged_at is not null and summary is null/);
  assert.match(prepare, /payload_purged_at >= responded_at/);
  assert.match(prepare, /unique \(\s*sender_user_id, client_request_id\s*\)/);

  assert.match(purge, /auth\.uid\(\) is distinct from p_user_id/);
  assert.match(purge, /set status = 'expired'/);
  assert.match(purge, /invite\.expires_at <= cleanup_time/);
  assert.match(purge, /set workout = null,[\s\S]*summary = null,[\s\S]*payload_purged_at = cleanup_time/);
  assert.match(purge, /invite\.status = 'accepted'[\s\S]*interval '30 days'/);
  assert.match(purge, /invite\.status in \('declined', 'cancelled', 'expired'\)[\s\S]*interval '24 hours'/);
  assert.equal((purge.match(/limit 100/g) || []).length, 2);
  assert.equal((purge.match(/for update skip locked/g) || []).length, 2);
  assert.doesNotMatch(purge, /delete from gymapp_private\.social_workout_invites/);
  const cancelForPair = functionBody(
    activate,
    "gymapp_private.social_cancel_pending_workout_invites",
  );
  assert.match(cancelForPair, /when invite\.expires_at <= mutation_time then 'expired'/);
  assert.match(cancelForPair, /when invite\.expires_at <= mutation_time then invite\.expires_at/);
  assert.match(cancelForPair, /else 'cancelled'/);
  assert.match(
    activate,
    /has_function_privilege\('authenticated', 'gymapp_private\.social_purge_expired_workout_payloads\(uuid\)', 'EXECUTE'\)/,
  );
});

test("the owner-only legacy leaderboard remains available only for old clients", async () => {
  const activate = await readFile(activatePath, "utf8");
  assert.match(activate, /to_regprocedure\('public\.leaderboard_public_rows\(\)'\)/);
  assert.match(activate, /to_regclass\('public\.leaderboard_public'\)/);
  assert.doesNotMatch(activate, /create or replace (?:view|function) public\.leaderboard/i);
  assert.doesNotMatch(activate, /grant select on table public\.profiles/i);
});
