import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile(
  "supabase/migrations/20260821200800_add_workout_duration_to_friend_details.sql",
  "utf8"
);
const enrichmentFix = await readFile(
  "supabase/migrations/20260822071247_fix_friend_workout_duration_enrichment.sql",
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

test("duration sidecar is private, owner-bound, bounded, and atomically replaced", () => {
  const sync = sqlFunction(migration, "public.social_sync_workout_durations");
  assert.match(migration, /create table if not exists gymapp_private\.workout_durations/);
  assert.match(migration, /primary key \(user_id, workout_started_at_millis\)/);
  assert.match(migration, /alter table gymapp_private\.workout_durations enable row level security/);
  assert.match(migration, /revoke all on table gymapp_private\.workout_durations[\s\S]*authenticated/);
  assert.match(sync, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(sync, /has_current_auth_session\(caller_user_id\)/);
  assert.match(sync, /jsonb_array_length\(p_items\)/);
  assert.match(sync, /item_count > 5000/);
  assert.match(sync, /duration_value > 604800/);
  assert.match(sync, /Workout duration payload contains duplicates/);
  assert.match(sync, /delete from gymapp_private\.workout_durations/);
  assert.match(sync, /insert into gymapp_private\.workout_durations/);
  assert.match(migration, /grant execute on function public\.social_sync_workout_durations\(jsonb\)[\s\S]*to authenticated/);
  assert.doesNotMatch(migration, /grant execute on function public\.social_sync_workout_durations\(jsonb\)[\s\S]*to anon/);
});

test("friend duration enrichment reuses the authorized detail projection", () => {
  const page = sqlFunction(migration, "public.social_friend_workout_page");
  assert.match(page, /social_friend_workout_page_base_v1/);
  assert.match(page, /left join gymapp_private\.workout_durations/);
  assert.match(page, /duration\.user_id = target_user_id/);
  assert.match(page, /'\{durationSeconds\}'/);
  assert.match(migration, /revoke all on function public\.social_friend_workout_page_base_v1/);
  assert.doesNotMatch(page, /note|rawState/);
});

test("friend duration enrichment uses executable PostgreSQL COALESCE syntax", () => {
  const page = sqlFunction(enrichmentFix, "public.social_friend_workout_page");
  assert.match(page, /social_friend_workout_page_base_v1/);
  assert.match(page, /left join gymapp_private\.workout_durations/);
  assert.match(page, /select coalesce\(/);
  assert.doesNotMatch(page, /pg_catalog\.coalesce\(/);
  assert.match(enrichmentFix, /revoke all on function public\.social_friend_workout_page/);
  assert.match(enrichmentFix, /grant execute on function public\.social_friend_workout_page[\s\S]*to authenticated/);
  assert.match(enrichmentFix, /social_friend_workout_page_base_v1[\s\S]*'EXECUTE'/);
});
