import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260714010000_add_garmin_device_rate_limits.sql";

test("Garmin capability RPCs use durable atomic per-device token buckets", async () => {
  const [sql, edge] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
  ]);

  assert.match(sql, /create table gymapp_private\.garmin_device_rate_limits/);
  assert.match(sql, /primary key \(device_id, bucket_action\)/);
  assert.match(sql, /references public\.garmin_devices\(id\) on delete cascade/);
  assert.match(sql, /alter table gymapp_private\.garmin_device_rate_limits enable row level security/);
  assert.match(sql, /revoke all on table gymapp_private\.garmin_device_rate_limits[\s\S]*from public, anon, authenticated/);
  assert.match(sql, /on conflict \(device_id, bucket_action\) do nothing/);
  assert.match(sql, /for update;/);
  assert.match(sql, /available_tokens := least\(/);
  assert.match(sql, /return least\(greatest\(retry_after_seconds, 1\), 3600\)::integer/);
  assert.doesNotMatch(sql, /x-forwarded-for|cf-connecting-ip|true-client-ip/i);
  assert.doesNotMatch(sql, /p_device_id\s*text/i);

  const resolverStart = sql.indexOf(
    "create or replace function gymapp_private.garmin_rate_limit_for_token",
  );
  const cleanupStart = sql.indexOf(
    "create or replace function gymapp_private.guard_garmin_plan",
  );
  const resolver = sql.slice(resolverStart, cleanupStart);
  assert.match(resolver, /device\.device_token = gymapp_private\.garmin_device_token_hash\(p_device_token\)/);
  assert.match(resolver, /device\.binding_version = 2/);
  assert.match(resolver, /device\.revoked_at is null/);
  assert.match(resolver, /for update;/);
  assert.match(resolver, /consume_garmin_device_rate_limit\(found_device_id, p_action\)/);

  assert.match(sql, /after update of revoked_at[\s\S]*handle_garmin_device_revocation/);
  assert.match(sql, /security definer\s+set search_path = ''/g);
  assert.match(sql, /rename to garmin_fetch_pending_plan_core/);
  assert.match(sql, /grant execute on function public\.garmin_fetch_pending_plan\(text\)\s+to anon/);
  assert.match(sql, /grant execute on function public\.garmin_ack_plan\(text, uuid, bigint\)\s+to anon/);
  assert.match(sql, /revoke all on function public\.garmin_fetch_pending_plan_core\(text\)[\s\S]*from public, anon, authenticated/);

  assert.match(edge, /"garmin_fetch_pending_plan"/);
  assert.match(edge, /"garmin_ack_plan"/);
  assert.match(edge, /"garmin_quarantine_pending_plan"/);
  assert.match(edge, /value\.status !== "rate_limited"/);
  assert.match(edge, /"Retry-After": String\(retryAfter\)/);
  assert.match(edge, /Rate limit exceeded/);
  assert.match(edge, /"X-Content-Type-Options": "nosniff"/);
  assert.match(edge, /const \{ data: quarantine, error: quarantineError \}/);
  assert.match(edge, /quarantine\?\.status !== "quarantined"/);
});

test("legacy unbound pending plans are quarantined without deletion or silent assignment", async () => {
  const sql = await readFile(migrationPath, "utf8");
  const quarantineEnd = sql.indexOf(
    "create table gymapp_private.garmin_device_rate_limits",
  );
  const quarantine = sql.slice(0, quarantineEnd);

  assert.match(quarantine, /update public\.garmin_plans/);
  assert.match(quarantine, /status = 'invalid'/);
  assert.match(quarantine, /where status = 'pending'\s+and device_id is null/);
  assert.match(quarantine, /check \(status <> 'pending' or device_id is not null\)/);
  assert.doesNotMatch(quarantine, /delete\s+from\s+public\.garmin_plans/i);
  assert.doesNotMatch(quarantine, /set\s+device_id\s*=/i);
});

test("device revocation retires queued work and token rotation preserves the stable binding", async () => {
  const [sql, edge] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
  ]);

  assert.match(sql, /update public\.garmin_plans[\s\S]*status = 'invalid'[\s\S]*where device_id = new\.id[\s\S]*and user_id = new\.user_id[\s\S]*and status = 'pending'/);
  assert.match(sql, /Garmin device was revoked before this plan was delivered/);
  assert.match(sql, /not is_revocation_cancellation/);
  assert.match(sql, /Revoked Garmin devices retain pending plans/);
  assert.match(sql, /Legacy pending plan has no active owner-matched Garmin device/);
  assert.match(sql, /device\.user_id = plan\.user_id/);
  assert.match(sql, /Pending Garmin plan has no active owner-matched device/);
  const guardStart = sql.indexOf(
    "create or replace function gymapp_private.guard_garmin_plan",
  );
  const revocationStart = sql.indexOf(
    "create or replace function gymapp_private.handle_garmin_device_revocation",
  );
  const guard = sql.slice(guardStart, revocationStart);
  assert.match(guard, /from public\.garmin_devices as device[\s\S]*device\.revoked_at is null[\s\S]*for update;/);
  assert.match(guard, /if not found then[\s\S]*Garmin plan device binding is invalid/);

  const rotateStart = sql.indexOf(
    "create or replace function public.garmin_rotate_device_token",
  );
  const grantsStart = sql.indexOf(
    "revoke all on function public.garmin_fetch_pending_plan_core(text)",
  );
  const rotate = sql.slice(rotateStart, grantsStart);
  assert.match(rotate, /p_replacement_token text/);
  assert.match(rotate, /p_expected_token_revision bigint/);
  assert.match(rotate, /device\.id = p_device_id/);
  assert.match(rotate, /device\.user_id = caller_user_id/);
  assert.match(rotate, /device\.revoked_at is null/);
  assert.match(rotate, /for update;/);
  assert.match(rotate, /consume_garmin_device_rate_limit\([\s\S]*'rotate_token'/);
  assert.match(rotate, /replacement_token_hash := gymapp_private\.garmin_device_token_hash/);
  assert.match(rotate, /found_device\.token_revision = p_expected_token_revision \+ 1/);
  assert.match(rotate, /found_device\.device_token = replacement_token_hash/);
  assert.match(rotate, /'status', 'already_rotated'/);
  assert.match(rotate, /'status', 'conflict'/);
  assert.match(rotate, /token_revision = next_token_revision/);
  assert.ok(
    rotate.indexOf("'status', 'already_rotated'") <
      rotate.indexOf("consume_garmin_device_rate_limit"),
    "exact CAS retries must not consume the rotation bucket",
  );
  assert.match(rotate, /'id', found_device\.id/);
  assert.doesNotMatch(rotate, /'device_token'/);
  assert.doesNotMatch(rotate, /set\s+id\s*=/i);

  const listStart = sql.indexOf(
    "create or replace function public.garmin_list_devices",
  );
  const list = sql.slice(listStart, rotateStart);
  assert.match(list, /device\.user_id = caller_user_id/);
  assert.match(list, /device\.binding_version = 2/);
  assert.match(list, /device\.revoked_at is null/);
  assert.doesNotMatch(list, /device_token/);
  assert.match(list, /'token_revision', device\.token_revision/);
  assert.match(sql, /grant execute on function public\.garmin_list_devices\(\)\s+to authenticated/);
  assert.match(sql, /grant execute on function public\.garmin_rotate_device_token\(uuid, text, bigint\)\s+to authenticated/);
  assert.match(sql, /has_function_privilege\('anon', 'public\.garmin_list_devices\(\)', 'EXECUTE'\)/);

  assert.match(sql, /create or replace function gymapp_private\.has_current_auth_session/);
  assert.match(sql, /from auth\.sessions as session/);
  assert.match(sql, /auth\.jwt\(\) ->> 'session_id'/);
  assert.match(sql, /rename to garmin_create_device_core/);
  assert.match(sql, /rename to garmin_revoke_device_core/);
  assert.match(sql, /An active authenticated session is required/);

  assert.match(edge, /action === "listDevices"/);
  assert.match(edge, /action === "rotateDeviceToken"/);
  assert.match(edge, /"garmin_list_devices"/);
  assert.match(edge, /"garmin_rotate_device_token"/);
  assert.match(edge, /p_replacement_token: replacementToken/);
  assert.match(edge, /p_expected_token_revision: expectedTokenRevision/);
  assert.match(edge, /Device token rotation conflict/);
  assert.match(edge, /\.trim\(\)\.toLowerCase\(\)/);
  assert.match(edge, /"Cache-Control": "no-store"/);
  assert.match(edge, /"Pragma": "no-cache"/);
});

test("plan enqueue retries are owner-scoped, session-bound, and idempotent", async () => {
  const sql = await readFile(migrationPath, "utf8");

  assert.match(sql, /add column client_request_id uuid/);
  assert.match(sql, /set client_request_id = id/);
  assert.match(sql, /unique \(user_id, client_request_id\)/);
  const enqueueStart = sql.indexOf(
    "create or replace function public.garmin_enqueue_plan",
  );
  const listStart = sql.indexOf(
    "create or replace function public.garmin_list_devices",
  );
  const enqueue = sql.slice(enqueueStart, listStart);
  assert.match(enqueue, /security definer\s+set search_path = ''/);
  assert.match(enqueue, /has_current_auth_session\(caller_user_id\)/);
  assert.match(enqueue, /p_client_request_id uuid/);
  assert.match(enqueue, /p_client_request_id::text !~ '\^\[0-9a-f\]\{8\}[\s\S]*-4\[0-9a-f\]\{3\}-\[89ab\]/);
  assert.match(enqueue, /pg_advisory_xact_lock/);
  assert.match(enqueue, /plan\.client_request_id = p_client_request_id/);
  assert.match(enqueue, /found_plan\.device_id is not distinct from p_device_id/);
  assert.match(enqueue, /found_plan\.plan = p_plan/);
  assert.match(enqueue, /'status', 'already_queued'/);
  assert.match(enqueue, /'status', 'conflict'/);
  assert.match(enqueue, /device\.user_id = caller_user_id/);
  assert.match(enqueue, /device\.revoked_at is null[\s\S]*for update;/);
  assert.match(enqueue, /insert into public\.garmin_plans/);
  assert.match(enqueue, /'status', 'queued'/);
  assert.doesNotMatch(enqueue, /p_user_id|p_status/);
  assert.ok(
    enqueue.indexOf("'status', 'already_queued'") <
      enqueue.indexOf("insert into public.garmin_plans"),
    "exact enqueue retries must return before quota/revision-consuming INSERT",
  );

  assert.match(sql, /grant execute on function public\.garmin_enqueue_plan\(uuid, jsonb, uuid\)\s+to authenticated/);
  assert.match(sql, /revoke insert on table public\.garmin_plans from public, anon, authenticated/);
  assert.match(sql, /grant insert \(user_id, device_id, status, plan\)\s+on table public\.garmin_plans to authenticated/);
  assert.match(sql, /new\.client_request_id := \(/);
  assert.match(sql, /pg_catalog\.sha256/);
  assert.match(sql, /existing_legacy_plan\.plan = new\.plan[\s\S]*return null/);
  assert.match(sql, /Garmin legacy request key collision/);
  assert.match(sql, /has_column_privilege\('authenticated', 'public\.garmin_plans', 'client_request_id', 'INSERT'\)/);
  assert.match(sql, /Authenticated Garmin legacy INSERT grant is not narrowly scoped/);
  assert.match(sql, /new\.client_request_id is distinct from old\.client_request_id/);
});
