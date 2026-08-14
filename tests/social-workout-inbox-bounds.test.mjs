import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260814085251_bounded_social_workout_inbox.sql";
const cursorWindowMigrationPath =
  "supabase/migrations/20260814085312_extend_social_workout_inbox_cursor_window.sql";
const responseBudgetMigrationPath =
  "supabase/migrations/20260814125503_budget_social_workout_inbox_response.sql";

function functionBody(sql, functionName) {
  const start = sql.indexOf(`create or replace function ${functionName}`);
  assert.ok(start >= 0, `${functionName} must exist`);
  const end = sql.indexOf("\n$function$;", start);
  assert.ok(end > start, `${functionName} must use a bounded function body`);
  return sql.slice(start, end + "\n$function$;".length);
}

test("workout inbox pages metadata without repeating private plans", async () => {
  const migration = await readFile(migrationPath, "utf8");
  const page = functionBody(migration, "public.social_workout_inbox_page");

  assert.match(migration, /^--[\s\S]*\nbegin;/);
  assert.match(migration, /set local lock_timeout = '5s'/);
  assert.match(migration, /set local statement_timeout = '2min'/);
  assert.match(migration, /\ncommit;\s*$/);
  assert.match(page, /security definer[\s\S]*set search_path = ''/);
  assert.match(page, /social_require_caller\('workout_inbox'\)/);
  assert.match(page, /invite\.recipient_user_id = caller_user_id/);
  assert.match(page, /invite\.sender_user_id = caller_user_id/);
  assert.match(page, /social_pair_is_accepted/);
  assert.match(page, /p_limit not between 1 and 20/);
  assert.match(page, /limit effective_limit \+ 1/);
  assert.match(page, /limit effective_limit/);
  assert.match(page, /active_pending desc/);
  assert.match(page, /p_cursor_created_at/);
  assert.match(page, /p_cursor_invite_id/);
  assert.match(page, /p_cursor_pending/);
  assert.match(page, /'nextCursor'/);
  assert.match(page, /'pendingIncomingCount'/);
  assert.match(page, /'summary', page\.summary/);
  assert.doesNotMatch(page, /'workout'\s*,|invite\.workout/);
  assert.match(page, /> 262144/);
  assert.match(page, /raise exception using errcode = '54000'/);

  assert.match(
    migration,
    /revoke all on function public\.social_workout_inbox_page\([\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.social_workout_inbox_page\([\s\S]*to authenticated/,
  );
});

test("one-plan detail is exact-revision and recipient authorized", async () => {
  const migration = await readFile(migrationPath, "utf8");
  const detail = functionBody(migration, "public.social_workout_invite_plan");

  assert.match(detail, /security definer[\s\S]*set search_path = ''/);
  assert.match(detail, /social_require_caller\('workout_inbox'\)/);
  assert.match(detail, /p_invite_id !~ '\^wi_\[0-9a-f\]\{32\}\$'/);
  assert.match(detail, /p_expected_revision not between 1 and 2147483647/);
  assert.match(detail, /invite\.recipient_user_id = caller_user_id/);
  assert.match(detail, /invite\.revision = p_expected_revision/);
  assert.match(detail, /invite\.workout is not null/);
  assert.match(detail, /invite\.status = 'pending'/);
  assert.match(detail, /invite\.status = 'accepted'/);
  assert.match(detail, /interval '30 days'/);
  assert.match(detail, /social_pair_is_accepted/);
  assert.match(detail, /errcode = 'P0002'/);
  assert.match(detail, /message = 'Social resource unavailable\.'/);
  assert.match(detail, /'workout', invite_row\.workout/);
  assert.doesNotMatch(detail, /sender_user_id = caller_user_id/);

  assert.match(
    migration,
    /revoke all on function public\.social_workout_invite_plan\(text, bigint\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.social_workout_invite_plan\(text, bigint\)[\s\S]*to authenticated/,
  );
});

test("cursor validation covers the full accepted-invitation retention window", async () => {
  const migration = await readFile(cursorWindowMigrationPath, "utf8");
  const page = functionBody(migration, "public.social_workout_inbox_page");

  assert.match(migration, /^--[\s\S]*\nbegin;/);
  assert.match(migration, /\ncommit;\s*$/);
  assert.match(page, /p_cursor_created_at < read_time - interval '38 days'/);
  assert.doesNotMatch(page, /p_cursor_created_at < read_time - interval '31 days'/);
  assert.match(page, /invite\.responded_at > read_time - interval '30 days'/);
  assert.match(page, /security definer[\s\S]*set search_path = ''/);
  assert.match(
    migration,
    /revoke all on function public\.social_workout_inbox_page\([\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.social_workout_inbox_page\([\s\S]*to authenticated/,
  );
});

test("latest inbox page uses stable outgoing and exact full-response byte budgets", async () => {
  const migration = await readFile(responseBudgetMigrationPath, "utf8");
  const page = functionBody(migration, "public.social_workout_inbox_page");

  assert.match(migration, /^--[\s\S]*\nbegin;/);
  assert.match(migration, /set local lock_timeout = '5s'/);
  assert.match(migration, /set local statement_timeout = '2min'/);
  assert.match(migration, /\ncommit;\s*$/);
  assert.match(page, /security definer[\s\S]*set search_path = ''/);
  assert.match(page, /social_require_caller\('workout_inbox'\)/);
  assert.match(page, /invite\.recipient_user_id = caller_user_id/);
  assert.match(page, /invite\.sender_user_id = caller_user_id/);
  assert.match(page, /social_pair_is_accepted/);
  assert.match(page, /p_limit not between 1 and 20/);
  assert.match(page, /limit effective_limit \+ 1/);
  assert.match(page, /outgoing_array_byte_limit constant integer := 98304/);
  assert.match(page, /response_byte_limit constant integer := 258048/);
  assert.match(page, /Keep 4 KiB below the clients' 256 KiB transport ceiling/);
  assert.doesNotMatch(page, /single_row_responses|incoming_reserve_response/);
  assert.doesNotMatch(page, /outgoing_json := outgoing_json -/);
  assert.match(page, /message = 'Workout inbox row exceeds the response limit\.'/);
  assert.match(page, /candidate_array := outgoing_json \|\|[\s\S]*jsonb_build_array\(candidate_json\)/);
  assert.match(page, /candidate_array::text, 'UTF8'[\s\S]*> outgoing_array_byte_limit/);
  assert.match(page, /order by bounded\.created_at desc, bounded\.id desc[\s\S]*loop/);
  assert.match(page, /incoming_candidates->incoming_index/);
  assert.match(page, /candidate_array := incoming_json \|\|[\s\S]*jsonb_build_array\(candidate_json\)/);
  assert.match(page, /candidate_response::text, 'UTF8'[\s\S]*> response_byte_limit/);
  assert.match(page, /'createdAt', candidate_envelope->'createdAt'/);
  assert.match(page, /'inviteId', candidate_envelope->'inviteId'/);
  assert.match(page, /'pending', candidate_envelope->'pending'/);
  assert.match(page, /'nextCursor', case when has_more then last_cursor/);
  assert.match(page, /p_cursor_created_at < read_time - interval '38 days'/);
  assert.match(page, /'summary', eligible\.summary/);
  assert.doesNotMatch(page, /'workout'\s*,|invite\.workout/);

  assert.match(
    migration,
    /revoke all on function public\.social_workout_inbox_page\([\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.social_workout_inbox_page\([\s\S]*to authenticated/,
  );
});

test("released full-plan inbox remains available only as a compatibility fallback", async () => {
  const [migration, activation] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile(
      "supabase/migrations/20260809202432_activate_friend_social_api.sql",
      "utf8",
    ),
  ]);

  assert.doesNotMatch(migration, /drop function public\.social_workout_inbox/);
  assert.match(activation, /create or replace function public\.social_workout_inbox\(\)/);
  assert.match(activation, /'workout', bounded\.workout/);
});

test("database fixture covers paging, late acceptance, privacy, stale revision, and wrong owner", async () => {
  const fixture = await readFile(
    "supabase/tests/bounded_social_workout_inbox.sql",
    "utf8",
  );

  assert.match(fixture, /^begin;/);
  assert.match(fixture, /select plan\(34\)/);
  assert.match(fixture, /social_workout_inbox_page\(/);
  assert.match(fixture, /pending invites remain ahead/);
  assert.match(fixture, /stable cursor does not repeat/);
  assert.match(fixture, /late accepted invitations remain pageable beyond the old 31-day cursor window/);
  assert.match(fixture, /another account cannot page late accepted invitations/);
  assert.match(fixture, /response stays inside the shared client byte limit/);
  assert.match(fixture, /worst-case valid summaries reproduce the former aggregate overflow/);
  assert.match(fixture, /large-summary response stays inside the shared client byte limit/);
  assert.match(fixture, /outgoing byte budget keeps only a newest-first prefix/);
  assert.match(fixture, /outgoing snapshot is stable across incoming pages/);
  assert.match(fixture, /worst escaped valid single incoming row survives beside the maximum outgoing prefix/);
  assert.match(fixture, /worst escaped structurally valid summary passes canonical server validation/);
  assert.match(fixture, /byte-budgeted incoming cursor identifies the exact last emitted row/);
  assert.match(fixture, /anonymous clients cannot execute the metadata inbox/);
  assert.match(fixture, /stale plan revision fails without an existence oracle/);
  assert.match(fixture, /another account cannot read or distinguish the invite/);
  assert.match(fixture, /detail execution is granted only to authenticated clients/);
  assert.match(fixture, /\nrollback;\s*$/);
});
