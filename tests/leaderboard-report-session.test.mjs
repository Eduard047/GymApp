import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile(
  "supabase/migrations/20260831093331_require_live_session_for_leaderboard_reports.sql", "utf8",
);
const previous = await readFile(
  "supabase/migrations/20260722011000_bound_leaderboard_reports.sql", "utf8",
);
const functionDefinition = source => source.match(
  /create or replace function public\.prepare_leaderboard_report\(\)[\s\S]*?\$function\$;/,
)?.[0];

test("report session repair preserves the complete prior admission contract", () => {
  const original = functionDefinition(previous);
  const changed = functionDefinition(migration);
  assert.ok(original && changed);
  assert.equal(changed.replace(
    "if caller_user_id is null\n     or not gymapp_private.current_auth_session_is_live() then",
    "if caller_user_id is null then",
  ), original);
  assert.ok(changed.indexOf("current_auth_session_is_live()") < changed.indexOf("from public.profiles"));
});

test("report INSERT policy preserves ownership and adds the shared live-session predicate", () => {
  assert.match(migration, /alter policy "authenticated users can submit leaderboard reports"[\s\S]*reporter_user_id = \(select auth\.uid\(\)\)[\s\S]*and \(select gymapp_private\.current_auth_session_is_live\(\)\)/);
  assert.match(migration, /revoke all on function public\.prepare_leaderboard_report\(\)\s+from public, anon, authenticated/);
  assert.doesNotMatch(migration, /\b(?:grant|drop|truncate|delete from|disable row level security)\b/i);
});

test("forward report repair is atomic and bounds lock and execution time", () => {
  assert.match(migration, /^begin;/);
  assert.match(migration, /set local lock_timeout = '5s'/);
  assert.match(migration, /set local statement_timeout = '30s'/);
  assert.match(migration, /Leaderboard report session prerequisites are missing/);
  assert.match(migration, /notify pgrst, 'reload schema'/);
  assert.match(migration, /commit;\s*$/);
});
