import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath = new URL(
  "../supabase/migrations/20260810091350_bind_push_installations_to_auth_sessions.sql",
  import.meta.url,
);
const sql = await readFile(migrationPath, "utf8");

function sqlFunction(source, qualifiedName) {
  const start = source.indexOf(`create function ${qualifiedName}(`) >= 0
    ? source.indexOf(`create function ${qualifiedName}(`)
    : source.indexOf(`create or replace function ${qualifiedName}(`);
  assert.notEqual(start, -1, `${qualifiedName} must exist`);
  const end = source.indexOf("\n$function$;", start);
  assert.notEqual(end, -1, `${qualifiedName} must have a complete body`);
  return source.slice(start, end + "\n$function$;".length);
}

test("notification addresses carry an indexed exact Auth-session reference", () => {
  assert.match(sql, /add column auth_session_id uuid;/);
  assert.match(
    sql,
    /foreign key \(auth_session_id\)[\s\S]*references auth\.sessions\(id\)[\s\S]*on delete set null[\s\S]*not valid;/,
  );
  assert.match(sql, /validate constraint notification_installations_auth_session_fkey/);
  assert.match(
    sql,
    /notification_installations_auth_session_idx[\s\S]*\(auth_session_id, id\)[\s\S]*where auth_session_id is not null/,
  );
  assert.doesNotMatch(
    sql,
    /grant (?:select|insert|update|delete|all) on (?:table )?gymapp_private\.notification_installations/i,
  );
});

test("registration derives the session only from the signed JWT and rotates on rebind", () => {
  const requireSession = sqlFunction(
    sql,
    "gymapp_private.notification_require_current_auth_session_id",
  );
  const guard = sqlFunction(
    sql,
    "gymapp_private.notification_installation_session_guard",
  );
  const register = sqlFunction(sql, "public.notification_register_installation");

  assert.match(requireSession, /auth\.jwt\(\) ->> 'session_id'/);
  assert.match(requireSession, /session\.id = session_id_text::uuid/);
  assert.match(requireSession, /session\.user_id = p_user_id/);
  assert.match(requireSession, /session\.not_after is null[\s\S]*session\.not_after > pg_catalog\.clock_timestamp\(\)/);
  assert.match(requireSession, /for key share/);

  assert.match(register, /caller_session_id := gymapp_private\.notification_require_current_auth_session_id/);
  assert.match(register, /gymapp\.notification_registration_session_id/);
  assert.match(register, /notification_register_installation_storage_v1/);
  assert.doesNotMatch(
    register.slice(0, register.indexOf("returns jsonb")),
    /p_(?:auth_)?session_id/,
    "the public RPC must not accept a caller-selected session id",
  );

  assert.match(guard, /old\.auth_session_id is distinct from current_session_id/);
  assert.match(guard, /new\.binding_id := pg_catalog\.gen_random_uuid\(\)/);
  assert.match(guard, /new\.revision := old\.revision \+ 1/);
  assert.match(guard, /new\.auth_session_id := current_session_id/);
  assert.match(
    guard,
    /old\.auth_session_id is not null[\s\S]*new\.auth_session_id is null[\s\S]*new\.provider_token := null[\s\S]*new\.revoked_at := request_time/,
  );
  assert.match(sql, /legacy_unbound[\s\S]*for update skip locked[\s\S]*limit 500/);
});

test("claim and final pre-send check both fail closed on the exact session", () => {
  const current = sqlFunction(
    sql,
    "gymapp_private.push_delivery_session_is_current",
  );
  const claim = sqlFunction(sql, "public.push_claim_deliveries");
  const preSend = sqlFunction(sql, "public.push_delivery_is_current");

  assert.match(current, /join auth\.sessions as session/);
  assert.match(current, /session\.id = installation\.auth_session_id/);
  assert.match(current, /session\.user_id = installation\.user_id/);
  assert.match(current, /installation\.revision = delivery\.installation_revision/);
  assert.match(current, /session\.not_after is null[\s\S]*session\.not_after > pg_catalog\.clock_timestamp\(\)/);
  assert.match(current, /for key share of session/);

  const storageCall = claim.indexOf("push_claim_deliveries_storage_v1");
  const currentCheck = claim.indexOf("push_delivery_session_is_current", storageCall);
  const providerReturn = claim.indexOf("claimed_row.provider_token::text", currentCheck);
  assert.ok(storageCall >= 0 && currentCheck > storageCall && providerReturn > currentCheck);
  assert.match(claim, /registration_session_revoked/);
  assert.match(claim, /invalid_session_installations[\s\S]*for update of installation skip locked[\s\S]*limit 500/);
  assert.match(claim, /set provider_token = null,[\s\S]*binding_id = pg_catalog\.gen_random_uuid\(\)[\s\S]*revoked_at = request_time/);
  assert.match(claim, /set status = 'invalid',[\s\S]*lease_token = null/);
  assert.match(preSend, /gymapp_private\.push_delivery_session_is_current/);
});

test("public signatures and least-privilege grants remain compatible", () => {
  assert.match(
    sql,
    /create function public\.notification_register_installation\([\s\S]*p_web_push_p256dh text default null,[\s\S]*p_app_version text default null[\s\S]*\)\s*returns jsonb/,
  );
  assert.match(
    sql,
    /create function public\.push_claim_deliveries\([\s\S]*p_limit integer default 25,[\s\S]*p_lease_seconds integer default 45[\s\S]*\)\s*returns table/,
  );
  assert.match(
    sql,
    /grant execute on function public\.notification_register_installation\([\s\S]*\) to authenticated;/,
  );
  assert.match(
    sql,
    /grant execute on function public\.push_claim_deliveries\(uuid, integer, integer\)[\s\S]*to service_role;/,
  );
  assert.match(
    sql,
    /grant execute on function public\.push_delivery_is_current\(uuid, uuid\)[\s\S]*to service_role;/,
  );
  assert.match(
    sql,
    /revoke all on function gymapp_private\.notification_register_installation_storage_v1\([\s\S]*from public, anon, authenticated, service_role;/,
  );
  assert.match(
    sql,
    /revoke all on function gymapp_private\.push_claim_deliveries_storage_v1\([\s\S]*from public, anon, authenticated, service_role;/,
  );
});

test("migration avoids schema-qualifying PostgreSQL special forms", () => {
  assert.doesNotMatch(
    sql,
    /pg_catalog\.(?:coalesce|extract|greatest|least|nullif|position|substring|trim|overlay)\s*\(/i,
  );
});
