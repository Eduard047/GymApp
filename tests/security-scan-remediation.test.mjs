import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [sessionSql, durationSql, deletionSql, preauthSql, preauthWrapperFixSql, coalesceFixSql, pushSource, pwaSource, stateSource, androidStore] =
  await Promise.all([
    readFile("supabase/migrations/20260823160702_harden_live_sessions_and_push_ownership.sql", "utf8"),
    readFile("supabase/migrations/20260823160703_bound_workout_duration_sync.sql", "utf8"),
    readFile("supabase/migrations/20260823160705_require_one_time_account_deletion_grants.sql", "utf8"),
    readFile("supabase/migrations/20260823160706_add_edge_preauth_budgets.sql", "utf8"),
    readFile("supabase/migrations/20260823161839_fix_edge_preauth_service_wrapper.sql", "utf8"),
    readFile("supabase/migrations/20260823162119_fix_security_hardening_coalesce_calls.sql", "utf8"),
    readFile("supabase/functions/_shared/preauth-budget.ts", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/state-contract.js", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/auth/AndroidKeystoreAuthStore.kt", "utf8"),
  ]);

test("direct owner RLS and live gateway reject revoked or not-after sessions", () => {
  assert.match(sessionSql, /create or replace function gymapp_private\.current_auth_session_is_live\(\)/);
  assert.match(sessionSql, /session\.id = session_id_text::uuid/);
  assert.match(sessionSql, /session\.user_id = caller_user_id/);
  assert.match(sessionSql, /session\.not_after is null[\s\S]*session\.not_after > pg_catalog\.clock_timestamp\(\)/);
  assert.match(sessionSql, /for key share/);
  for (const policy of [
    "Users can read own profile", "Users can insert own profile", "Users can update own profile",
    "Users can read own state", "Users can insert own state", "Users can update own state",
    "Users can read own Garmin plans",
  ]) {
    const start = sessionSql.indexOf(`create policy "${policy}"`);
    assert.ok(start >= 0, `${policy} must be replaced`);
    assert.match(sessionSql.slice(start, start + 650), /current_auth_session_is_live/);
  }
  assert.match(sessionSql, /live_gateway_require_session[\s\S]*session\.not_after/);
});

test("duration synchronization is byte-bounded, budgeted, serialized, and differential", () => {
  const byteLimit = durationSql.indexOf("payload_bytes > 262144");
  const firstExpansion = durationSql.indexOf("jsonb_array_elements(p_items)");
  assert.ok(byteLimit >= 0 && byteLimit < firstExpansion);
  assert.match(durationSql, /consume_workout_duration_sync_budget/);
  assert.match(durationSql, /pg_advisory_xact_lock/);
  assert.match(durationSql, /statement_timeout = '8s'/);
  assert.match(durationSql, /on conflict \(user_id, workout_started_at_millis\) do update/);
  assert.match(durationSql, /is distinct from excluded\.duration_seconds/);
});

test("account deletion requires fresh password AMR and a single-use exact-session grant", () => {
  assert.match(deletionSql, /method\.value->>'method' = 'password'/);
  assert.match(deletionSql, /interval '5 minutes'/);
  assert.match(deletionSql, /grant_hash bytea primary key/);
  assert.match(deletionSql, /session_id uuid not null references auth\.sessions/);
  assert.match(deletionSql, /consumed_at is null[\s\S]*for update/);
  assert.match(deletionSql, /set consumed_at = pg_catalog\.clock_timestamp\(\)/);
});

test("public Edge pre-authentication work has service-only durable source and global budgets", () => {
  assert.match(preauthSql, /\('delete_account', 12, 1200\)/);
  assert.match(preauthSql, /\('social_live', 180, 6000\)/);
  assert.match(preauthSql, /\('garmin_legacy', 90, 3000\)/);
  assert.match(preauthSql, /grant execute on function public\.edge_preauth_debit\(text, text\)[\s\S]*to service_role/);
  assert.doesNotMatch(preauthSql, /grant execute on function public\.edge_preauth_debit\(text, text\)[\s\S]*to (?:anon|authenticated)/);
  assert.match(preauthWrapperFixSql, /alter function public\.edge_preauth_debit\(text, text\) security definer/);
  assert.match(preauthWrapperFixSql, /set search_path = ''/);
  assert.doesNotMatch(preauthWrapperFixSql, /grant usage on schema gymapp_private/);
  assert.match(coalesceFixSql, /social_sync_workout_durations\(jsonb\)/);
  assert.match(coalesceFixSql, /gymapp_private\.edge_preauth_debit\(text,text\)/);
  assert.match(coalesceFixSql, /regexp_count/);
  assert.match(coalesceFixSql, /'pg_catalog\.coalesce',[\s\S]*'coalesce'/);
  assert.match(pushSource, /GATEWAY_PREAUTH_HMAC_SECRET/);
  assert.match(pushSource, /crypto\.subtle\.sign/);
  assert.match(pushSource, /p_source_hash: hash/);
});

test("push installation ownership transfer requires exact provider-address possession", () => {
  assert.match(sessionSql, /pg_advisory_xact_lock/);
  assert.match(sessionSql, /installation\.user_id <> caller_user_id/);
  assert.match(sessionSql, /foreign_installation\.token_fingerprint is distinct from requested_fingerprint/);
  assert.match(sessionSql, /raise exception using errcode = '22023'/);
});

test("PWA rejects complex JSON, oversized routes, and image pixel bombs before expensive parsers", () => {
  assert.ok(stateSource.indexOf("preflightJsonText(input)") < stateSource.indexOf("JSON.parse(input)"));
  assert.match(stateSource, /Backup contains duplicate object keys/);
  assert.ok(pwaSource.indexOf("customExerciseImageHeaderDimensions(file)") < pwaSource.indexOf("createImageBitmap(file)"));
  assert.match(pwaSource, /boundedLocationParameters\(window\.location\.search, 8192\)/);
  assert.match(pwaSource, /rawHash\.length > window\.GymSharedWorkout\.LIMITS\.encodedLength/);
});

test("Android cloud credentials use non-exportable AES-GCM Android Keystore storage", () => {
  assert.match(androidStore, /KeyStore\.getInstance\("AndroidKeyStore"\)/);
  assert.match(androidStore, /PURPOSE_ENCRYPT or KeyProperties\.PURPOSE_DECRYPT/);
  assert.match(androidStore, /AES\/GCM\/NoPadding/);
  assert.match(androidStore, /setRandomizedEncryptionRequired\(true\)/);
  assert.match(androidStore, /cipher\.updateAAD/);
});
