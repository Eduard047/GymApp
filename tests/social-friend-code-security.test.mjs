import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260811223504_add_private_social_friend_codes.sql";
const legacyActivationPath =
  "supabase/migrations/20260809202432_activate_friend_social_api.sql";

function functionBody(sql, functionName) {
  const start = sql.indexOf(`create or replace function ${functionName}`);
  assert.ok(start >= 0, `${functionName} must exist`);
  const end = sql.indexOf("\n$function$;", start);
  assert.ok(end > start, `${functionName} must use a bounded function body`);
  return sql.slice(start, end + "\n$function$;".length);
}

test("private friend codes are lazy, 48-bit, collision-bounded, and RPC-only", async () => {
  const sql = await readFile(migrationPath, "utf8");
  const ensureCode = functionBody(
    sql,
    "gymapp_private.social_ensure_friend_code",
  );

  assert.match(sql, /create table gymapp_private\.social_friend_codes \(/);
  assert.match(sql, /user_id uuid primary key[\s\S]*references auth\.users\(id\) on delete cascade/);
  assert.match(sql, /constraint social_friend_codes_code_key unique \(friend_code\)/);
  assert.match(sql, /check \(friend_code ~ '\^g_\[0-9a-f\]\{12\}\$'\)/);
  assert.match(sql, /alter table gymapp_private\.social_friend_codes enable row level security/);
  assert.match(sql, /alter table gymapp_private\.social_friend_codes force row level security/);
  assert.match(
    sql,
    /revoke all on table gymapp_private\.social_friend_codes\s+from public, anon, authenticated, service_role/,
  );
  assert.doesNotMatch(
    sql,
    /create policy[\s\S]{0,160}gymapp_private\.social_friend_codes/i,
  );
  assert.doesNotMatch(
    sql,
    /insert into gymapp_private\.social_friend_codes[^;]*\)\s*select\b/i,
  );

  assert.match(ensureCode, /auth\.uid\(\) is distinct from p_user_id/);
  assert.match(ensureCode, /has_current_auth_session\(p_user_id\)/);
  assert.match(ensureCode, /gymapp-social-friend-code:/);
  assert.match(ensureCode, /for generation_attempt in 1\.\.16 loop/);
  assert.match(ensureCode, /pg_catalog\.gen_random_uuid\(\)/);
  assert.match(ensureCode, /pg_catalog\.left\([\s\S]*12\s*\)/);
  assert.match(ensureCode, /on conflict do nothing/);
  assert.match(ensureCode, /Friend-code generation is temporarily unavailable/);
  assert.equal((ensureCode.match(/insert into gymapp_private\.social_friend_codes/g) || []).length, 1);
});

test("own friend-code RPC is exact v1 and fails closed for anon or a different session owner", async () => {
  const sql = await readFile(migrationPath, "utf8");
  const ownCode = functionBody(sql, "public.social_my_friend_code");

  assert.match(ownCode, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(ownCode, /session_id_text text := auth\.jwt\(\) ->> 'session_id'/);
  assert.match(ownCode, /caller_user_id is null/);
  assert.match(ownCode, /session\.id = current_session_id/);
  assert.match(ownCode, /session\.user_id = caller_user_id/);
  assert.match(ownCode, /session\.not_after is null[\s\S]*session\.not_after > pg_catalog\.clock_timestamp\(\)/);
  assert.match(ownCode, /for key share/);
  assert.ok(
    ownCode.indexOf("from auth.sessions as session") <
      ownCode.indexOf("gymapp_private.social_ensure_friend_code(caller_user_id)"),
    "the live session must be locked before lazy code creation",
  );
  assert.match(
    ownCode,
    /return pg_catalog\.jsonb_build_object\(\s*'version', 1,\s*'friendCode', caller_friend_code\s*\)/,
  );
  assert.doesNotMatch(ownCode, /'userId'|'profileId'|'email'|'sessionId'/);

  assert.match(
    sql,
    /revoke all on function public\.social_my_friend_code\(\)\s+from public, anon, authenticated, service_role/,
  );
  assert.match(
    sql,
    /grant execute on function public\.social_my_friend_code\(\)\s+to authenticated/,
  );
  assert.doesNotMatch(
    sql,
    /grant execute on function public\.social_my_friend_code\(\)\s+to (?:public|anon|service_role)/i,
  );
});

test("friend request keeps one generic response and read-only p_ or g_ resolution", async () => {
  const [sql, legacyActivation] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile(legacyActivationPath, "utf8"),
  ]);
  const send = functionBody(sql, "public.social_send_friend_request");
  const legacySend = functionBody(
    legacyActivation,
    "public.social_send_friend_request",
  );
  const lookupStart = send.indexOf("if p_friend_code is null then");
  const mutationBoundary = send.indexOf(
    "perform gymapp_private.social_lock_pair(caller_user_id, target_user_id)",
  );
  const lookup = send.slice(lookupStart, mutationBoundary);
  const genericResponse =
    "return pg_catalog.jsonb_build_object('version', 1, 'result', 'submitted_or_unavailable');";

  assert.match(send, /social_require_caller\('send_friend'\)/);
  assert.match(send, /pg_catalog\.octet_length\(p_friend_code\) = 34/);
  assert.match(send, /pg_catalog\.octet_length\(p_friend_code\) = 14/);
  assert.match(send, /p_friend_code ~ '\^p_\[0-9a-f\]\{32\}\$'/);
  assert.match(send, /p_friend_code ~ '\^g_\[0-9a-f\]\{12\}\$'/);
  assert.match(lookup, /from public\.profiles as profile[\s\S]*profile\.public_id = p_friend_code/);
  assert.match(lookup, /from gymapp_private\.social_friend_codes as code[\s\S]*code\.friend_code = p_friend_code/);
  assert.doesNotMatch(lookup, /\b(?:insert|update|delete)\b/i);
  assert.doesNotMatch(send, /insert into gymapp_private\.social_friend_codes/i);
  const legacyMutationBoundary = legacySend.indexOf(
    "perform gymapp_private.social_lock_pair(caller_user_id, target_user_id)",
  );
  assert.equal(
    send.slice(mutationBoundary),
    legacySend.slice(legacyMutationBoundary),
    "pair locking, blocking, privacy, caps, auto-accept, and mutation semantics must stay byte-identical",
  );

  const returns = send
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("return pg_catalog.jsonb_build_object"));
  assert.ok(returns.length >= 8, "every outcome must remain generic");
  assert.deepEqual(new Set(returns), new Set([genericResponse]));
  assert.match(send, /social_pair_is_blocked\(caller_user_id, target_user_id\)/);
  assert.match(send, /not target_allows_requests/);
  assert.match(send, /caller_pending_count >= 25 or target_pending_count >= 100/);
  assert.match(send, /caller_accepted_count < 200/);
  assert.match(send, /target_accepted_count < 200/);
});

test("friend-code migration verifies grants, forced RLS, no policies, and empty search paths", async () => {
  const sql = await readFile(migrationPath, "utf8");

  assert.match(sql, /relation\.relrowsecurity[\s\S]*relation\.relforcerowsecurity/);
  assert.match(sql, /from pg_catalog\.pg_policy[\s\S]*social_friend_codes/);
  for (const role of ["anon", "authenticated", "service_role"]) {
    assert.match(
      sql,
      new RegExp(`has_table_privilege\\('${role}', 'gymapp_private\\.social_friend_codes'`),
    );
  }
  assert.match(sql, /security definer\s+set search_path = ''/g);
  assert.match(sql, /procedure\.proconfig @> array\['search_path=""'\]/);
  assert.match(
    sql,
    /join pg_catalog\.pg_roles as owner_role[\s\S]*owner_role\.oid = procedure\.proowner[\s\S]*owner_role\.rolsuper or owner_role\.rolbypassrls/,
  );
  for (const signature of [
    "gymapp_private.social_ensure_friend_code(uuid)",
    "public.social_my_friend_code()",
    "public.social_send_friend_request(text)",
  ]) {
    assert.match(sql, new RegExp(signature.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
  assert.match(sql, /notify pgrst, 'reload schema'/);
  assert.doesNotMatch(sql, /\b(?:drop|truncate)\s+(?:table\s+)?/i);
});
