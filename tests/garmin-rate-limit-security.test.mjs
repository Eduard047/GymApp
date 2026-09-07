import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260721142951_add_garmin_device_rate_limits.sql";
const preauthMigrationPath =
  "supabase/migrations/20260721143058_add_bounded_garmin_preauth_rate_limits.sql";
const capabilityGatewayMigrationPath =
  "supabase/migrations/20260722012000_secure_garmin_capability_gateway.sql";
const gatewayBudgetMigrationPath =
  "supabase/migrations/20260902162345_harden_garmin_public_gateway_budgets.sql";

test("the historical fixed pre-auth limiter is private and retired by the v3 gateway", async () => {
  const [sql, retirement, edge] = await Promise.all([
    readFile(preauthMigrationPath, "utf8"),
    readFile(capabilityGatewayMigrationPath, "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
  ]);

  const tableStart = sql.indexOf(
    "create table gymapp_private.garmin_preauth_rate_limits",
  );
  const consumerStart = sql.indexOf(
    "create or replace function gymapp_private.consume_garmin_preauth_rate_limit",
  );
  const resolverStart = sql.indexOf(
    "create or replace function gymapp_private.garmin_rate_limit_for_token",
  );
  const verifyStart = sql.indexOf("do $verify$");
  assert.ok(
    tableStart > 0 && tableStart < consumerStart &&
      consumerStart < resolverStart &&
      resolverStart < verifyStart,
    "the fixed table, pre-auth consumer, resolver, and verification must stay ordered",
  );

  const tableAndSeed = sql.slice(tableStart, consumerStart);
  const consumer = sql.slice(consumerStart, resolverStart);
  const resolver = sql.slice(resolverStart, verifyStart);

  assert.match(tableAndSeed, /primary key \(bucket_action, shard_id\)/);
  assert.match(
    tableAndSeed,
    /bucket_action in \('fetch_plan', 'ack_plan', 'quarantine_plan'\)/,
  );
  assert.match(tableAndSeed, /generate_series\(0, 63\)/);
  assert.match(tableAndSeed, /\('fetch_plan'::text, 32::numeric\)/);
  assert.match(tableAndSeed, /\('ack_plan'::text, 16::numeric\)/);
  assert.match(tableAndSeed, /\('quarantine_plan'::text, 4::numeric\)/);
  assert.doesNotMatch(tableAndSeed, /device_token|token_hash/);
  assert.match(
    sql,
    /count\(\*\) from gymapp_private\.garmin_preauth_rate_limits\) <> 192/,
  );
  assert.match(
    sql,
    /revoke all on table gymapp_private\.garmin_preauth_rate_limits[\s\S]*from public, anon, authenticated, service_role/,
  );

  assert.match(consumer, /p_token_hash !~ '\^\[a-f0-9\]\{64\}\$'/);
  assert.match(consumer, /get_byte\([\s\S]*decode\([\s\S]*% 64/);
  assert.match(consumer, /for update skip locked/);
  assert.match(consumer, /if not found then\s+return 1/);
  assert.match(consumer, /available_tokens := least\(/);
  assert.match(
    consumer,
    /return least\(greatest\(retry_after_seconds, 1\), 3600\)::integer/,
  );
  assert.doesNotMatch(consumer, /insert into|on conflict|upsert/i);

  assert.equal(
    (resolver.match(/garmin_device_token_hash\(p_device_token\)/g) || [])
      .length,
    1,
    "the raw capability must be hashed once before limiting and lookup",
  );
  assert.ok(
    resolver.indexOf("consume_garmin_preauth_rate_limit") <
      resolver.indexOf("from public.garmin_devices"),
    "the fixed pre-auth bucket must be consumed before device lookup",
  );
  assert.match(resolver, /device\.device_token = token_hash/);
  assert.match(
    resolver,
    /consume_garmin_device_rate_limit\([\s\S]*found_device_id/,
  );
  assert.doesNotMatch(resolver, /insert into|on conflict|upsert/i);

  assert.match(
    sql,
    /revoke all on function gymapp_private\.consume_garmin_preauth_rate_limit\(text, text\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(sql, /notify pgrst, 'reload schema'/);
  assert.match(
    retirement,
    /drop table if exists gymapp_private\.garmin_preauth_rate_limits/,
  );
  assert.match(
    retirement,
    /grant execute on function public\.garmin_fetch_pending_plan\(text\)[\s\S]*to service_role/,
  );
  assert.match(
    retirement,
    /has_function_privilege\([\s\S]*'anon'[\s\S]*garmin_fetch_pending_plan\(text\)/,
  );
  assert.match(edge, /value\.status !== "rate_limited"/);
  assert.match(edge, /"Retry-After": String\(retryAfter\)/);
});

test("public Garmin JWT and capability work is fenced by a fixed global-plus-lane budget", async () => {
  const [sql, edge, helper] = await Promise.all([
    readFile(gatewayBudgetMigrationPath, "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
    readFile("supabase/functions/_shared/preauth-budget.ts", "utf8"),
  ]);
  const consumerStart = sql.indexOf(
    "create or replace function gymapp_private.consume_garmin_gateway_preauth_budget",
  );
  const wrapperStart = sql.indexOf(
    "create or replace function public.garmin_gateway_preauth_debit",
  );
  const consumer = sql.slice(consumerStart, wrapperStart);

  assert.match(sql, /primary key \(bucket_lane, shard_id\)/);
  assert.match(sql, /bucket_lane in \('global', 'jwt', 'capability'\)/);
  assert.match(sql, /generate_series\(0, 63\)/);
  assert.match(sql, /\) <> 192/);
  assert.doesNotMatch(sql, /device_token|authorization_header|bearer_token/i);
  assert.match(consumer, /bucket\.bucket_lane = 'global'[\s\S]*for update/);
  assert.match(consumer, /bucket\.bucket_lane = p_lane[\s\S]*for update/);
  assert.doesNotMatch(consumer, /insert into|on conflict|delete from/i);
  assert.match(
    sql,
    /revoke all on table gymapp_private\.garmin_gateway_preauth_buckets[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    sql,
    /grant execute on function public\.garmin_gateway_preauth_debit\(text, integer\)[\s\S]*to service_role/,
  );

  assert.match(helper, /Math\.imul\(hash, 0x01000193\)/);
  assert.match(
    helper,
    /body: JSON\.stringify\(\{ p_lane: lane, p_shard: shard \}\)/,
  );
  assert.doesNotMatch(
    helper.slice(
      helper.indexOf("export async function debitGarminGatewayBudget"),
    ),
    /p_(?:token|bearer|capability|source_hint)/i,
  );
  assert.match(helper, /return garminUnavailable\("rpc_transport_error"\)/);

  for (
    const action of [
      "createDeviceIdempotent",
      "createDevice",
      "listDevices",
      "rotateDeviceToken",
      "revokeDevice",
    ]
  ) {
    const start = edge.indexOf(`if (body.action === "${action}")`);
    const end = edge.indexOf("\n  if (body.action ===", start + 1);
    const route = edge.slice(start, end < 0 ? edge.length : end);
    assert.ok(start >= 0, `${action} route must exist`);
    assert.ok(
      route.indexOf("requireGarminGatewayBudget") <
        route.indexOf("authenticatedClient"),
      `${action} must debit before Auth SDK construction`,
    );
  }
  for (const action of ["fetchPlan", "ackPlan"]) {
    const start = edge.indexOf(`if (body.action === "${action}")`);
    const end = edge.indexOf("\n  if (body.action ===", start + 1);
    const route = edge.slice(start, end < 0 ? edge.length : end);
    assert.ok(
      route.indexOf("requireGarminGatewayBudget") <
        route.indexOf("resolveGarminCapability"),
      `${action} must debit before capability HMAC verification`,
    );
  }
});

test("Garmin capability RPCs use durable atomic per-device token buckets", async () => {
  const [sql, edge] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
  ]);

  assert.match(sql, /create table gymapp_private\.garmin_device_rate_limits/);
  assert.match(sql, /primary key \(device_id, bucket_action\)/);
  assert.match(
    sql,
    /references public\.garmin_devices\(id\) on delete cascade/,
  );
  assert.match(
    sql,
    /alter table gymapp_private\.garmin_device_rate_limits enable row level security/,
  );
  assert.match(
    sql,
    /revoke all on table gymapp_private\.garmin_device_rate_limits[\s\S]*from public, anon, authenticated/,
  );
  assert.match(sql, /on conflict \(device_id, bucket_action\) do nothing/);
  assert.match(sql, /for update;/);
  assert.match(sql, /available_tokens := least\(/);
  assert.match(
    sql,
    /return least\(greatest\(retry_after_seconds, 1\), 3600\)::integer/,
  );
  assert.doesNotMatch(sql, /x-forwarded-for|cf-connecting-ip|true-client-ip/i);
  assert.doesNotMatch(sql, /p_device_id\s*text/i);

  const resolverStart = sql.indexOf(
    "create or replace function gymapp_private.garmin_rate_limit_for_token",
  );
  const cleanupStart = sql.indexOf(
    "create or replace function gymapp_private.guard_garmin_plan",
  );
  const resolver = sql.slice(resolverStart, cleanupStart);
  assert.match(
    resolver,
    /device\.device_token = gymapp_private\.garmin_device_token_hash\(p_device_token\)/,
  );
  assert.match(resolver, /device\.binding_version = 2/);
  assert.match(resolver, /device\.revoked_at is null/);
  assert.match(resolver, /for update;/);
  assert.match(
    resolver,
    /consume_garmin_device_rate_limit\(found_device_id, p_action\)/,
  );

  assert.match(
    sql,
    /after update of revoked_at[\s\S]*handle_garmin_device_revocation/,
  );
  assert.match(sql, /security definer\s+set search_path = ''/g);
  assert.match(sql, /rename to garmin_fetch_pending_plan_core/);
  assert.match(
    sql,
    /grant execute on function public\.garmin_fetch_pending_plan\(text\)\s+to anon/,
  );
  assert.match(
    sql,
    /grant execute on function public\.garmin_ack_plan\(text, uuid, bigint\)\s+to anon/,
  );
  assert.match(
    sql,
    /revoke all on function public\.garmin_fetch_pending_plan_core\(text\)[\s\S]*from public, anon, authenticated/,
  );

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
  assert.match(
    quarantine,
    /check \(status <> 'pending' or device_id is not null\)/,
  );
  assert.doesNotMatch(quarantine, /delete\s+from\s+public\.garmin_plans/i);
  assert.doesNotMatch(quarantine, /set\s+device_id\s*=/i);
});

test("device revocation retires queued work and token rotation preserves the stable binding", async () => {
  const [sql, edge] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile("supabase/functions/garmin-sync/index.ts", "utf8"),
  ]);

  assert.match(
    sql,
    /update public\.garmin_plans[\s\S]*status = 'invalid'[\s\S]*where device_id = new\.id[\s\S]*and user_id = new\.user_id[\s\S]*and status = 'pending'/,
  );
  assert.match(sql, /Garmin device was revoked before this plan was delivered/);
  assert.match(sql, /not is_revocation_cancellation/);
  assert.match(sql, /Revoked Garmin devices retain pending plans/);
  assert.match(
    sql,
    /Legacy pending plan has no active owner-matched Garmin device/,
  );
  assert.match(sql, /device\.user_id = plan\.user_id/);
  assert.match(sql, /Pending Garmin plan has no active owner-matched device/);
  const guardStart = sql.indexOf(
    "create or replace function gymapp_private.guard_garmin_plan",
  );
  const revocationStart = sql.indexOf(
    "create or replace function gymapp_private.handle_garmin_device_revocation",
  );
  const guard = sql.slice(guardStart, revocationStart);
  assert.match(
    guard,
    /from public\.garmin_devices as device[\s\S]*device\.revoked_at is null[\s\S]*for update;/,
  );
  assert.match(
    guard,
    /if not found then[\s\S]*Garmin plan device binding is invalid/,
  );

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
  assert.match(
    rotate,
    /consume_garmin_device_rate_limit\([\s\S]*'rotate_token'/,
  );
  assert.match(
    rotate,
    /replacement_token_hash := gymapp_private\.garmin_device_token_hash/,
  );
  assert.match(
    rotate,
    /found_device\.token_revision = p_expected_token_revision \+ 1/,
  );
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
  assert.match(
    sql,
    /grant execute on function public\.garmin_list_devices\(\)\s+to authenticated/,
  );
  assert.match(
    sql,
    /grant execute on function public\.garmin_rotate_device_token\(uuid, text, bigint\)\s+to authenticated/,
  );
  assert.match(
    sql,
    /has_function_privilege\('anon', 'public\.garmin_list_devices\(\)', 'EXECUTE'\)/,
  );

  assert.match(
    sql,
    /create or replace function gymapp_private\.has_current_auth_session/,
  );
  assert.match(sql, /from auth\.sessions as session/);
  assert.match(sql, /auth\.jwt\(\) ->> 'session_id'/);
  assert.match(sql, /rename to garmin_create_device_core/);
  assert.match(sql, /rename to garmin_revoke_device_core/);
  assert.match(sql, /An active authenticated session is required/);

  assert.match(edge, /action === "listDevices"/);
  assert.match(edge, /action === "rotateDeviceToken"/);
  assert.match(edge, /"garmin_list_devices"/);
  assert.match(edge, /"garmin_rotate_device_token"/);
  assert.match(edge, /p_replacement_token: replacementNonce/);
  assert.match(edge, /createGarminCapability/);
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
  assert.match(
    enqueue,
    /p_client_request_id::text !~ '\^\[0-9a-f\]\{8\}[\s\S]*-4\[0-9a-f\]\{3\}-\[89ab\]/,
  );
  assert.match(enqueue, /pg_advisory_xact_lock/);
  assert.match(enqueue, /plan\.client_request_id = p_client_request_id/);
  assert.match(
    enqueue,
    /found_plan\.device_id is not distinct from p_device_id/,
  );
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

  assert.match(
    sql,
    /grant execute on function public\.garmin_enqueue_plan\(uuid, jsonb, uuid\)\s+to authenticated/,
  );
  assert.match(
    sql,
    /revoke insert on table public\.garmin_plans from public, anon, authenticated/,
  );
  assert.match(
    sql,
    /grant insert \(user_id, device_id, status, plan\)\s+on table public\.garmin_plans to authenticated/,
  );
  assert.match(sql, /new\.client_request_id := \(/);
  assert.match(sql, /pg_catalog\.sha256/);
  assert.match(sql, /existing_legacy_plan\.plan = new\.plan[\s\S]*return null/);
  assert.match(sql, /Garmin legacy request key collision/);
  assert.match(
    sql,
    /has_column_privilege\('authenticated', 'public\.garmin_plans', 'client_request_id', 'INSERT'\)/,
  );
  assert.match(
    sql,
    /Authenticated Garmin legacy INSERT grant is not narrowly scoped/,
  );
  assert.match(
    sql,
    /new\.client_request_id is distinct from old\.client_request_id/,
  );
});
