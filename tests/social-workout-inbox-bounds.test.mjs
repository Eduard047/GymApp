import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260814085251_bounded_social_workout_inbox.sql";
const cursorWindowMigrationPath =
  "supabase/migrations/20260814085312_extend_social_workout_inbox_cursor_window.sql";

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
  assert.match(fixture, /select plan\(20\)/);
  assert.match(fixture, /social_workout_inbox_page\(/);
  assert.match(fixture, /pending invites remain ahead/);
  assert.match(fixture, /stable cursor does not repeat/);
  assert.match(fixture, /late accepted invitations remain pageable beyond the old 31-day cursor window/);
  assert.match(fixture, /another account cannot page late accepted invitations/);
  assert.match(fixture, /response stays inside the shared client byte limit/);
  assert.match(fixture, /stale plan revision fails without an existence oracle/);
  assert.match(fixture, /another account cannot read or distinguish the invite/);
  assert.match(fixture, /detail execution is granted only to authenticated clients/);
  assert.match(fixture, /\nrollback;\s*$/);
});
