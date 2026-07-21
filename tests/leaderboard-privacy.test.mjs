import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("clients use the authenticated owner-only leaderboard compatibility view", async () => {
  const [android, ios, pwa] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/Services/CloudSyncService.swift", "utf8"),
    readFile("pwa/app.js", "utf8")
  ]);

  assert.match(
    android,
    /\/rest\/v1\/leaderboard_public\?select=profile_id,display_name,xp,level,workouts,is_current_user/
  );
  assert.match(android, /profileId = row\.optString\("profile_id"\)/);
  assert.match(android, /isCurrentUser = row\.optBoolean\("is_current_user"\)/);
  assert.match(android, /\.filter\(LeaderboardRow::isCurrentUser\)/);
  assert.doesNotMatch(
    android,
    /\/rest\/v1\/profiles\?select=user_id,display_name,xp,level,workouts,updated_at/
  );

  assert.match(
    ios,
    /\/rest\/v1\/leaderboard_public\?select=profile_id,display_name,xp,level,workouts,is_current_user/
  );
  assert.match(ios, /guard isCurrentUser else \{ return nil \}/);
  assert.match(ios, /userID: session\.userID/);

  assert.match(
    pwa,
    /\/rest\/v1\/leaderboard_public\?select=profile_id,display_name,xp,level,workouts,is_current_user/
  );
  assert.match(pwa, /\{ session, signal: leaderboardRequestController\.signal/);
  assert.match(pwa, /\.filter\(row => Boolean\(row\?\.is_current_user\)\)/);
  assert.match(pwa, /\.map\(row => \(\{ \.\.\.row, isCurrent: true \}\)\)/);
  assert.match(pwa, /if \(!cloudMode\)/);
  assert.doesNotMatch(
    pwa,
    /\/rest\/v1\/profiles\?select=user_id,display_name,xp,level,workouts,updated_at/
  );
  assert.doesNotMatch(pwa, /state: payload, updated_at:/);
});

test("legacy schema entrypoint fails closed and hardened migrations are ordered", async () => {
  const [stub, leaderboard, hardening, revisionFix] = await Promise.all([
    readFile("supabase-schema.sql", "utf8"),
    readFile("supabase/migrations/20260711084556_create_leaderboard_public.sql", "utf8"),
    readFile("supabase/migrations/20260711084559_harden_gymapp_production_access.sql", "utf8"),
    readFile("supabase/migrations/20260711090358_fix_user_state_revision_trigger.sql", "utf8")
  ]);

  assert.match(stub, /is retired; apply the ordered supabase\/migrations files instead/);
  assert.doesNotMatch(stub, /create policy "Leaderboard is public"/);
  assert.match(leaderboard, /create or replace view public\.leaderboard_public/);
  assert.match(hardening, /drop policy if exists "Leaderboard is public"/);
  assert.match(hardening, /revoke all privileges on table/);
  assert.match(revisionFix, /current_revision timestamp with time zone/);
});

test("cross-account ranking stays disabled while workout history is client-authored", async () => {
  const migration = await readFile(
    "supabase/migrations/20260721143038_restrict_leaderboard_to_owner_until_verified_ingestion.sql",
    "utf8"
  );

  assert.match(migration, /create or replace function public\.leaderboard_public_rows\(\)/);
  assert.match(migration, /do \$preflight\$/);
  assert.match(migration, /security definer\s+set search_path = ''/);
  assert.match(migration, /profile\.user_id = \(select auth\.uid\(\)\)/);
  assert.match(migration, /gymapp_private\.user_state_quarantine/);
  assert.match(migration, /revoke all on function public\.leaderboard_public_rows\(\)[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.leaderboard_public_rows\(\)[\s\S]*to authenticated, service_role/);
  assert.match(migration, /do \$verify\$[\s\S]*has_function_privilege\('anon'/);
  assert.match(migration, /notify pgrst, 'reload schema'/);
  assert.doesNotMatch(migration, /from public\.user_states as state[\s\S]*cross join lateral/);
  assert.doesNotMatch(migration, /insert into|update public\.user_states|delete from public\.user_states/i);
});
