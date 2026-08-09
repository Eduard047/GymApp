import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("current clients use bounded account-bound social RPCs and never query the legacy leaderboard", async () => {
  const [android, androidContract, ios, iosContract, pwa] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/auth/CloudAuthManager.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/auth/SocialContract.kt", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/Services/CloudSyncService.swift", "utf8"),
    readFile("ios/GymApp-iOS/GymApp/Services/SocialModels.swift", "utf8"),
    readFile("pwa/app.js", "utf8")
  ]);

  for (const client of [android, ios, pwa]) {
    assert.doesNotMatch(client, /\/rest\/v1\/leaderboard_public/);
    assert.match(client, /social_dashboard/);
    assert.match(client, /social_friend_details/);
    assert.match(client, /social_workout_inbox/);
  }

  assert.match(android, /val freshSession = freshCloudSession\(session\)/);
  assert.match(android, /requireActiveCloudSession\(freshSession\)\s*\n\s*parser\(response\)/);
  assert.match(android, /MAX_CLOUD_RESPONSE_BYTES = 256 \* 1_024/);
  assert.match(androidContract, /requireExactKeys/);
  assert.match(androidContract, /SOCIAL_MAX_FRIENDS = 200/);

  assert.match(ios, /let expectedOperation = operationRevision/);
  assert.match(ios, /auth\.validCloudSession\(expectedUserID: expectedUserID\)/);
  assert.match(ios, /guard operationRevision == expectedOperation/);
  assert.match(iosContract, /maximumResponseBytes = 256 \* 1_024/);
  assert.match(iosContract, /object\(try json\(from: data\), keys:/);

  assert.match(pwa, /const MAX_SOCIAL_RESPONSE_BYTES = 256 \* 1024/);
  assert.match(pwa, /const SOCIAL_RPC_NAMES = new Set/);
  assert.match(pwa, /socialIdentityIsCurrent\(requestEpoch, expectedUserId\)/);
  assert.match(pwa, /socialRequestController\?\.abort\(\)/);
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
