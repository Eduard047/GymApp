import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("Android and PWA use the authenticated sanitized leaderboard", async () => {
  const [android, pwa] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
    readFile("pwa/app.js", "utf8")
  ]);

  assert.match(
    android,
    /\/rest\/v1\/leaderboard_public\?select=profile_id,display_name,xp,level,workouts,is_current_user/
  );
  assert.match(android, /profileId = row\.optString\("profile_id"\)/);
  assert.match(android, /isCurrentUser = row\.optBoolean\("is_current_user"\)/);
  assert.doesNotMatch(
    android,
    /\/rest\/v1\/profiles\?select=user_id,display_name,xp,level,workouts,updated_at/
  );

  assert.match(
    pwa,
    /\/rest\/v1\/leaderboard_public\?select=profile_id,display_name,xp,level,workouts,is_current_user/
  );
  assert.match(pwa, /\{ session, signal: leaderboardRequestController\.signal/);
  assert.match(pwa, /isCurrent: Boolean\(row\.is_current_user\)/);
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
