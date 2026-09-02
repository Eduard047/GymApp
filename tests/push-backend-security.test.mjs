import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const pushMigrationPath = new URL(
  "../supabase/migrations/20260810075952_add_provider_neutral_push_backend.sql",
  import.meta.url,
);
const perimeterMigrationPath = new URL(
  "../supabase/migrations/20260810080005_add_social_live_gateway_perimeter.sql",
  import.meta.url,
);
const gatewayPath = new URL("../supabase/functions/social-live-gateway/index.ts", import.meta.url);
const gatewayDenoPath = new URL("../supabase/functions/social-live-gateway/deno.json", import.meta.url);
const dispatcherPath = new URL("../supabase/functions/push-dispatch/index.ts", import.meta.url);
const providersPath = new URL("../supabase/functions/push-dispatch/providers.ts", import.meta.url);
const dispatcherDenoPath = new URL("../supabase/functions/push-dispatch/deno.json", import.meta.url);
const dispatcherReadmePath = new URL("../supabase/functions/push-dispatch/README.md", import.meta.url);
const configPath = new URL("../supabase/config.toml", import.meta.url);
const schedulerMigrationPath = new URL(
  "../supabase/migrations/20260810080915_schedule_push_dispatch.sql",
  import.meta.url,
);
const schedulerFixMigrationPath = new URL(
  "../supabase/migrations/20260810092029_fix_push_dispatch_token_validation.sql",
  import.meta.url,
);
const deepHardeningMigrationPath = new URL(
  "../supabase/migrations/20260902084252_harden_deep_scan_boundaries.sql",
  import.meta.url,
);

const [pushSql, perimeterSql, schedulerBaseSql, schedulerFixSql, deepHardeningSql, gateway, gatewayDeno, dispatcher, providers, dispatcherDeno, dispatcherReadme, config] =
  await Promise.all([
    readFile(pushMigrationPath, "utf8"),
    readFile(perimeterMigrationPath, "utf8"),
    readFile(schedulerMigrationPath, "utf8"),
    readFile(schedulerFixMigrationPath, "utf8"),
    readFile(deepHardeningMigrationPath, "utf8"),
    readFile(gatewayPath, "utf8"),
    readFile(gatewayDenoPath, "utf8"),
    readFile(dispatcherPath, "utf8"),
    readFile(providersPath, "utf8"),
    readFile(dispatcherDenoPath, "utf8"),
    readFile(dispatcherReadmePath, "utf8"),
    readFile(configPath, "utf8"),
  ]);

const schedulerSql = `${schedulerBaseSql}\n${schedulerFixSql}\n${deepHardeningSql}`;
const newSocialSql = `${pushSql}\n${perimeterSql}\n${schedulerSql}`;

test("new social migrations avoid schema-qualified PostgreSQL special forms", () => {
  assert.doesNotMatch(
    newSocialSql,
    /pg_catalog\.(?:coalesce|extract|greatest|least|nullif|position|substring|trim|overlay)\s*\(/i,
    "PostgreSQL special forms cannot be schema-qualified as ordinary functions",
  );
});

function sqlFunction(source, qualifiedName) {
  const start = source.indexOf(`create or replace function ${qualifiedName}(`);
  assert.notEqual(start, -1, `${qualifiedName} must exist`);
  const end = source.indexOf("\n$function$;", start);
  assert.notEqual(end, -1, `${qualifiedName} must have a complete body`);
  return source.slice(start, end + "\n$function$;".length);
}

test("push storage is private, RLS-enabled, account-bound, and scrubs revoked addresses", () => {
  for (const table of [
    "notification_installations", "notification_rate_limits",
    "push_outbox", "push_outbox_deliveries"
  ]) {
    assert.match(pushSql, new RegExp(`alter table gymapp_private\\.${table} enable row level security;`));
    assert.match(pushSql, new RegExp(`revoke all on table gymapp_private\\.${table}`));
  }
  assert.match(pushSql, /references auth\.users\(id\) on delete cascade/);
  assert.match(pushSql, /unique \(user_id, installation_id\)/);
  assert.match(pushSql, /binding_id uuid not null default pg_catalog\.gen_random_uuid\(\)/);
  assert.match(pushSql, /provider_token = null,[\s\S]*web_push_p256dh = null,[\s\S]*web_push_auth = null,[\s\S]*binding_id = pg_catalog\.gen_random_uuid\(\),[\s\S]*revoked_at = request_time/);
  assert.match(pushSql, /address_changed := existing_row\.revoked_at is not null/);
  assert.match(pushSql, /then gymapp_private\.notification_installations\.revision[\s\S]*else gymapp_private\.notification_installations\.revision \+ 1/);
  assert.match(pushSql, /set installation_revision = stored_row\.revision,[\s\S]*delivery\.status = 'pending'[\s\S]*outbox\.recipient_user_id = caller_user_id/);
  assert.match(pushSql, /revoked_at < request_time - interval '7 days'[\s\S]*limit 32/);
  assert.match(pushSql, /consume_notification_rate_limit\(caller_user_id, 'register'\)/);
  assert.match(pushSql, /consume_notification_rate_limit\(caller_user_id, 'revoke'\)/);
  assert.match(pushSql, /capacity := 30;[\s\S]*capacity := 60;/);
  assert.match(pushSql, /if total_count >= 64 then/);
  assert.match(pushSql, /grant execute on function public\.notification_register_installation\([\s\S]*\) to authenticated;/);
  assert.match(pushSql, /grant execute on function public\.push_claim_deliveries\(uuid, integer, integer\)[\s\S]*to service_role;/);
  assert.doesNotMatch(pushSql, /grant (?:select|insert|update|delete|all) on (?:table )?gymapp_private\.(?:notification_installations|push_outbox|push_outbox_deliveries) to/i);
});

test("notification domain failures preserve the debit and legacy PostgREST error contract", () => {
  const helper = sqlFunction(pushSql, "gymapp_private.notification_domain_error_response");
  const register = sqlFunction(pushSql, "public.notification_register_installation");
  const revoke = sqlFunction(pushSql, "public.notification_revoke_installation");

  for (const rpc of [register, revoke]) {
    const authCheck = rpc.indexOf("has_current_auth_session(caller_user_id)");
    const debit = rpc.indexOf("consume_notification_rate_limit(caller_user_id");
    const businessSubtransaction = rpc.indexOf("\n  begin", debit);
    assert.ok(authCheck >= 0 && debit > authCheck && businessSubtransaction > debit);
    assert.doesNotMatch(rpc, /when\s+others/i);
    assert.doesNotMatch(rpc, /when[^\n]*(?:42501|23[0-9A-Z]{3}|P0001)/i);
    assert.match(rpc, /get stacked diagnostics[\s\S]*domain_error_code = returned_sqlstate/);
    assert.match(rpc, /then\s+raise;[\s\S]*notification_domain_error_response/);
  }

  assert.match(register, /when sqlstate '22023' or sqlstate '54000' then/);
  assert.match(register, /domain_error_code = '22023'[\s\S]*Notification registration is invalid\./);
  assert.match(register, /domain_error_code = '54000'[\s\S]*Notification registration cannot be updated\.[\s\S]*Notification installation limit exceeded\./);
  assert.match(revoke, /when sqlstate '22023' then/);
  assert.doesNotMatch(revoke, /sqlstate '54000'/);
  assert.match(revoke, /domain_error_code is distinct from '22023'[\s\S]*domain_error_message is distinct from 'Notification revocation is invalid\.'/);

  assert.match(helper, /case when p_code = '54000' then '500' else '400' end/);
  assert.match(helper, /jsonb_build_object\(\s*'code', p_code,\s*'details', nullif\(p_detail, ''\),\s*'hint', nullif\(p_hint, ''\),\s*'message', p_message/s);
  assert.match(pushSql, /revoke all on function gymapp_private\.notification_domain_error_response\([\s\S]*from public, anon, authenticated, service_role;/);

  assert.match(register, /'version', 1,[\s\S]*'bindingId', stored_row\.binding_id,[\s\S]*'registrationRevision', stored_row\.revision,[\s\S]*'registeredAt', stored_row\.updated_at/);
  assert.match(revoke, /'version', 1,[\s\S]*'installationId', p_installation_id,[\s\S]*'revoked', revoked_count = 1/);
});

test("durable push hooks cover lifecycle events but never enqueue set progress", () => {
  for (const event of [
    "live_invite_received",
    "live_invite_accepted",
    "live_room_started",
    "live_participant_finished",
    "live_room_closed",
  ]) assert.match(pushSql, new RegExp(`'${event}'`));
  assert.match(pushSql, /create trigger live_workout_members_enqueue_push/);
  assert.match(pushSql, /create trigger live_workout_rooms_enqueue_push/);
  assert.match(pushSql, /Per-set progress is Realtime-only/);
  assert.doesNotMatch(pushSql, /enqueue_push_notification\([\s\S]{0,180}'(?:live_)?progress'/);
  assert.match(pushSql, /push_outbox_recipient_dedupe_key unique/);
  assert.match(pushSql, /installation_revision bigint not null/);
  assert.match(pushSql, /installation\.revision = delivery\.installation_revision/);
  assert.match(pushSql, /create or replace function public\.push_delivery_is_current/);
  assert.match(pushSql, /delivery\.lease_token = p_lease_token[\s\S]*installation\.user_id = outbox\.recipient_user_id[\s\S]*installation\.revision = delivery\.installation_revision/);
  assert.match(dispatcher, /rpc\("push_delivery_is_current"/);
  assert.ok(dispatcher.indexOf('rpc("push_delivery_is_current"') < dispatcher.indexOf("sendDelivery(delivery"));
  assert.match(dispatcher, /current === "stale"[\s\S]*outcome: "permanent"[\s\S]*delivery_changed_before_send/);
  assert.doesNotMatch(dispatcher, /current === "stale"[\s\S]{0,240}outcome: "invalid"/);
  assert.match(pushSql, /installation\.revision = delivery_row\.installation_revision/);
  assert.match(pushSql, /for update of delivery skip locked/);
  assert.match(pushSql, /completed_at < request_time - interval '30 days'[\s\S]*limit 500/);
  assert.match(pushSql, /last_seen_at < request_time - interval '180 days'[\s\S]*limit 500/);
  assert.match(pushSql, /revoked_at < request_time - interval '30 days'[\s\S]*limit 500/);
  assert.match(pushSql, /lease_owner = p_worker_id/);
  assert.match(pushSql, /delivery\.lease_token = p_lease_token/);
  assert.match(pushSql, /delivery\.lease_expires_at > request_time/g);
  assert.match(pushSql, /p_limit is null[\s\S]*p_lease_seconds is null/);
  assert.match(pushSql, /p_lease_seconds not between 15 and 300/);
  assert.match(pushSql, /p_invalid_registration is null[\s\S]*p_permanent_failure is null/);

  const retry = sqlFunction(pushSql, "public.push_mark_retry");
  assert.match(retry, /order by \(delivery\.id = delivery_row\.id\) desc,[\s\S]*for update skip locked[\s\S]*limit 500/);
  assert.match(retry, /changed_deliveries as \([\s\S]*update gymapp_private\.push_outbox_deliveries[\s\S]*returning delivery\.outbox_id[\s\S]*select distinct changed\.outbox_id[\s\S]*from changed_deliveries as changed/);
  assert.doesNotMatch(retry, /select distinct delivery\.outbox_id[\s\S]*where delivery\.installation_id = delivery_row\.installation_id/);
});

test("gateway re-verifies Auth, commits the durable perimeter debit, then validates and routes", () => {
  const bodyDecode = gateway.indexOf("rawBody = await readJsonBody(req)");
  const getUser = gateway.indexOf("auth.getUser(token)");
  const perimeterDebit = gateway.indexOf(
    'rpc("social_gateway_perimeter_debit"',
  );
  const semanticValidation = gateway.indexOf(
    "parseGatewayRequest(rawBody)",
    perimeterDebit,
  );
  const actionDebit = gateway.indexOf(
    'rpc("social_live_gateway_debit"',
    semanticValidation,
  );
  const detailedArgs = gateway.indexOf("args = route.args", actionDebit);
  const domain = gateway.indexOf("domainClient.rpc", detailedArgs);
  assert.ok(
    getUser > 0 && perimeterDebit > getUser && bodyDecode > perimeterDebit &&
      semanticValidation > bodyDecode && actionDebit > semanticValidation &&
      detailedArgs > actionDebit && domain > detailedArgs,
  );
  assert.match(gateway, /rpc\("social_gateway_perimeter_debit"[\s\S]*p_user_id: userId,[\s\S]*p_session_id: sessionId/);
  assert.match(gateway, /p_user_id: userId,[\s\S]*p_session_id: sessionId,[\s\S]*p_action: parsed\.action/);
  assert.match(gateway, /route\.serviceOnly\s*\? serviceClient\s*: userClient/);
  assert.match(gateway, /status === 409\s*\? "conflict"/);
  assert.match(perimeterSql, /from auth\.sessions as session[\s\S]*session\.id = p_session_id[\s\S]*session\.user_id = p_user_id[\s\S]*for key share/);
  assert.match(perimeterSql, /grant execute on function public\.social_live_gateway_debit\(uuid, uuid, text\)[\s\S]*to service_role/);
  assert.match(config, /\[functions\.social-live-gateway\]\nverify_jwt = true/);
});

test("dispatcher is server-only, dependency-pinned, and keeps provider payload opaque", () => {
  assert.match(dispatcher, /PUSH_DISPATCH_SERVER_KEY/);
  assert.match(dispatcher, /PUSH_DISPATCH_TOKEN/);
  assert.match(dispatcher, /constantTimeEqual\(suppliedDispatchToken, dispatchToken\)/);
  assert.match(dispatcher, /constantTimeEqual\(suppliedDispatchServerKey, dispatchServerKey\)/);
  assert.match(dispatcher, /serviceCredentials\.credentials/);
  assert.match(dispatcher, /for \(const credential of serviceCredentials\.credentials\)/);
  assert.match(dispatcher, /constantTimeEqual\(dispatchServerKey, credential\)/);
  assert.match(dispatcher, /constantTimeEqual\(dispatchToken, credential\)/);
  assert.match(dispatcher, /constantTimeEqual\(dispatchToken, dispatchServerKey\)/);
  assert.doesNotMatch(dispatcher, /constantTimeEqual\(suppliedDispatchServerKey, serviceKey\)/);
  assert.doesNotMatch(dispatcher, /req\.headers\.get\("authorization"\)/i);
  assert.match(dispatcher, /global: \{ fetch: serviceRoleFetch\(serviceKey\) \}/);
  assert.doesNotMatch(dispatcher, /createClient\(projectUrl,\s*dispatchServerKey/);
  assert.doesNotMatch(dispatcher, /serviceRoleFetch\(dispatchServerKey\)/);
  assert.match(gateway, /global: \{ fetch: serviceRoleFetch\(serviceKey\) \}/);
  assert.match(`${dispatcher}\n${gateway}`, /serviceKey\.startsWith\("sb_secret_"\)/);
  assert.match(`${dispatcher}\n${gateway}`, /if \(secretKey\) headers\.delete\("Authorization"\)/);
  assert.match(dispatcher, /if \(req\.headers\.has\("origin"\)\)/);
  assert.match(dispatcher, /push_claim_deliveries/);
  assert.match(dispatcher, /push_mark_delivered/);
  assert.match(dispatcher, /push_mark_retry/);
  assert.match(dispatcher, /const MAX_BATCH_SIZE = 10;/);
  assert.match(dispatcher, /const DEFAULT_BATCH_SIZE = 10;/);
  assert.match(dispatcher, /const MAX_CONCURRENCY = 5;/);
  assert.match(dispatcher, /p_lease_seconds: 240/);
  assert.match(dispatcher, /await Promise\.all\(\[\.\.\.groups\.keys\(\)\]\.map/);
  assert.match(dispatcher, /Math\.min\(MAX_CONCURRENCY, deliveries\.length\)/);
  assert.equal((dispatcher.match(/dispatchBatch\(/g) || []).length, 2);
  assert.match(providers, /redirect: "error"/);
  assert.match(providers, /webPushEndpointAllowed/);
  assert.match(providers, /google\.firebase\.fcm\.v1\.FcmError/);
  assert.match(providers, /errorCode === "INVALID_ARGUMENT" && tokenSpecific/);
  assert.doesNotMatch(providers, /errorCode === "SENDER_ID_MISMATCH" \|\|/);
  assert.match(providers, /if \(status === 410 \|\| reason === "Unregistered"\)/);
  assert.doesNotMatch(providers, /reason === "DeviceTokenNotForTopic" \|\|/);
  assert.match(providers, /version: 1,[\s\S]*bindingId: delivery\.binding_id,[\s\S]*kind: liveKind,[\s\S]*roomId:[\s\S]*roomRevision:/);
  assert.match(pushSql, /environment text,[\s\S]*binding_id uuid,[\s\S]*provider_token text/);
  assert.match(pushSql, /installation\.environment,[\s\S]*installation\.binding_id,[\s\S]*installation\.provider_token/);
  assert.doesNotMatch(providers, /(?:displayName|email|weight|reps|access_token).*opaquePayload/);
  assert.match(config, /\[functions\.push-dispatch\]\nverify_jwt = false/);
  assert.deepEqual(JSON.parse(gatewayDeno).imports, {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@2.110.2",
  });
  assert.deepEqual(JSON.parse(dispatcherDeno).imports, {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@2.110.2",
    "web-push-neo": "npm:web-push-neo@0.1.2",
  });
  assert.equal(JSON.parse(dispatcherDeno).lock.frozen, true);
});

test("push dispatch has a dormant Vault-backed minute scheduler with no public execute path", () => {
  assert.match(schedulerSql, /create extension if not exists pg_net with schema extensions/);
  assert.match(schedulerSql, /create table gymapp_private\.push_dispatch_requests/);
  assert.match(schedulerSql, /alter table gymapp_private\.push_dispatch_requests enable row level security/);
  assert.match(schedulerSql, /revoke all on table gymapp_private\.push_dispatch_requests[\s\S]*from public, anon, authenticated, service_role/);
  assert.match(schedulerSql, /gymapp_push_dispatch_url/);
  assert.match(schedulerSql, /gymapp_push_dispatch_server_key/);
  assert.match(schedulerSql, /gymapp_push_dispatch_token/);
  assert.match(dispatcherReadme, /gymapp_push_dispatch_server_key[\s\S]*dedicated[\s\S]*PUSH_DISPATCH_SERVER_KEY/);
  assert.match(dispatcherReadme, /does not send an `Authorization` header/);
  assert.match(dispatcherReadme, /not any Supabase API key/);
  assert.match(schedulerSql, /return null;[\s\S]*net\.http_post/);
  assert.match(schedulerSql, /'apikey', server_key/);
  assert.match(schedulerSql, /'X-GymApp-Push-Dispatch-Token', dispatch_token/);
  assert.match(schedulerFixSql, /octet_length\(dispatch_token\) not between 43 and 256/);
  assert.match(schedulerFixSql, /dispatch_token !~ '\^\[A-Za-z0-9_-\]\+\$'/);
  assert.match(deepHardeningSql, /server_key = dispatch_token/);
  assert.doesNotMatch(
    sqlFunction(schedulerFixSql, "gymapp_private.dispatch_push_notifications"),
    /\{43,256\}/,
  );
  assert.match(schedulerSql, /jsonb_build_object\('version', 1, 'batchSize', 10\)/);
  assert.match(schedulerSql, /timeout_milliseconds := 120000/);
  assert.match(schedulerSql, /pg_advisory_xact_lock\([\s\S]*gymapp-push-dispatch-scheduler-v1/);
  assert.match(schedulerSql, /tracked\.outcome = 'pending'[\s\S]*tracked\.requested_at >=[\s\S]*interval '5 minutes'[\s\S]*return null/);
  assert.match(schedulerSql, /insert into gymapp_private\.push_dispatch_requests \(request_id\)/);
  assert.match(schedulerSql, /create or replace function gymapp_private\.monitor_push_dispatch_responses\(\)/);
  assert.match(schedulerSql, /join net\._http_response as response on response\.id = tracked\.request_id/);
  assert.match(schedulerSql, /with responses as materialized[\s\S]*limit 100[\s\S]*get diagnostics resolved_count/);
  assert.match(schedulerSql, /with missing as materialized[\s\S]*limit 100[\s\S]*outcome = 'missing'/);
  assert.match(schedulerSql, /with expired as materialized[\s\S]*tracked\.outcome <> 'pending'[\s\S]*interval '30 days'[\s\S]*limit 500/);
  assert.doesNotMatch(schedulerSql, /set[\s\S]{0,160}(?:error_msg|content|headers)\s*=/);
  assert.match(schedulerSql, /create or replace function gymapp_private\.cleanup_push_dispatch_history\(\)/);
  assert.match(schedulerSql, /interval '7 days'[\s\S]*limit 5000/);
  assert.match(schedulerSql, /gymapp-live-workout-cleanup-v1/);
  assert.match(schedulerSql, /job\.username = current_user[\s\S]*job\.database = current_database\(\)/);
  const alterJobCalls = schedulerSql.match(
    /perform cron\.alter_job\([\s\S]*?\n  \);/g,
  ) ?? [];
  assert.equal(alterJobCalls.length, 3);
  for (const alterJobCall of alterJobCalls) {
    assert.match(alterJobCall, /schedule :=/);
    assert.match(alterJobCall, /command :=/);
    assert.match(alterJobCall, /active := true/);
    assert.doesNotMatch(alterJobCall, /\b(?:database|username)\s*:=/);
  }
  assert.match(schedulerSql, /'\* \* \* \* \*'/);
  assert.match(schedulerSql, /revoke all on function gymapp_private\.dispatch_push_notifications\(\)[\s\S]*from public, anon, authenticated, service_role/);
  assert.match(schedulerSql, /revoke all on function gymapp_private\.monitor_push_dispatch_responses\(\)[\s\S]*from public, anon, authenticated, service_role/);
  assert.match(schedulerSql, /has_table_privilege\([\s\S]*'service_role', 'gymapp_private\.push_dispatch_requests', 'SELECT'/);
  assert.doesNotMatch(schedulerSql, /sb_secret_|service_role_key|Bearer /i);
});

test("all external provider credential names are server environment lookups only", () => {
  for (const name of [
    "FCM_PROJECT_ID", "FCM_CLIENT_EMAIL", "FCM_PRIVATE_KEY",
    "APNS_TEAM_ID", "APNS_KEY_ID", "APNS_PRIVATE_KEY", "APNS_BUNDLE_ID",
    "WEBPUSH_VAPID_PUBLIC_KEY", "WEBPUSH_VAPID_PRIVATE_KEY", "WEBPUSH_CONTACT",
  ]) assert.match(providers, new RegExp(`requiredEnv\\(readEnv, "${name}"\\)`));
  assert.doesNotMatch(`${gateway}\n${dispatcher}\n${providers}`, /console\.(?:log|debug|info|warn|error)/);
});
