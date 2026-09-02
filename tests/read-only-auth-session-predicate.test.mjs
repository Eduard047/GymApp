import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const migrationDirectory = "supabase/migrations";
const suffix = "_fix_read_only_auth_session_predicate.sql";
const matchingMigrations = (await readdir(migrationDirectory))
  .filter((fileName) => fileName.endsWith(suffix));

assert.deepEqual(
  matchingMigrations.length,
  1,
  `expected exactly one ${suffix} migration`,
);

const migration = await readFile(
  `${migrationDirectory}/${matchingMigrations[0]}`,
  "utf8",
);
const deepHardeningMigration = await readFile(
  `${migrationDirectory}/20260901215530_harden_deep_scan_boundaries.sql`,
  "utf8",
);

function functionBody(sql, signature) {
  const start = sql.indexOf(`create or replace function ${signature}`);
  assert.ok(start >= 0, `${signature} must exist`);
  const end = sql.indexOf("$function$;", start);
  assert.ok(end > start, `${signature} must have a bounded body`);
  return sql.slice(start, end + "$function$;".length);
}

test("read-only RLS checks avoid row locks while writes retain revocation ordering", () => {
  const body = functionBody(
    migration,
    "gymapp_private.current_auth_session_is_live()",
  );
  const readOnlyBranch = body.indexOf(
    "if pg_catalog.current_setting('transaction_read_only')::boolean then",
  );
  const readOnlyExists = body.indexOf("return exists (", readOnlyBranch);
  const readOnlyEnd = body.indexOf("end if;", readOnlyExists);
  const writeLock = body.indexOf("for key share;", readOnlyEnd);

  assert.ok(readOnlyBranch >= 0, "the access mode must come from PostgreSQL");
  assert.ok(readOnlyExists > readOnlyBranch, "read-only requests use an existence check");
  assert.ok(readOnlyEnd > readOnlyExists, "the read-only branch must end before locking");
  assert.ok(writeLock > readOnlyEnd, "only the read-write path takes the session lock");
  assert.doesNotMatch(body.slice(readOnlyBranch, readOnlyEnd), /for key share/i);
  assert.match(body.slice(readOnlyEnd), /for key share/i);
});

test("the hotfix preserves exact session ownership, expiry, and least privilege", () => {
  const body = functionBody(
    migration,
    "gymapp_private.current_auth_session_is_live()",
  );
  const ownerChecks = body.match(/session\.user_id = caller_user_id/g) ?? [];
  const idChecks = body.match(/session\.id = session_id_text::uuid/g) ?? [];
  const expiryChecks = body.match(
    /session\.not_after is null[\s\S]*?session\.not_after > pg_catalog\.clock_timestamp\(\)/g,
  ) ?? [];

  assert.match(body, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(body, /session_id_text text := auth\.jwt\(\) ->> 'session_id'/);
  assert.match(body, /session_id_text !~\* '\^\[0-9a-f\]/);
  assert.equal(idChecks.length, 2, "both paths bind the exact JWT session");
  assert.equal(ownerChecks.length, 2, "both paths bind the session owner");
  assert.equal(expiryChecks.length, 2, "both paths reject expired sessions");
  assert.match(body, /volatile\s+security definer\s+set search_path = ''/);
  assert.match(
    migration,
    /revoke all on function gymapp_private\.current_auth_session_is_live\(\)[\s\S]*from public, anon, authenticated, service_role;/,
  );
  assert.match(
    migration,
    /grant execute on function gymapp_private\.current_auth_session_is_live\(\)[\s\S]*to authenticated;/,
  );
});

test("the compatibility hotfix changes no table, policy, or client grant", () => {
  assert.doesNotMatch(migration, /\b(?:create|alter|drop)\s+table\b/i);
  assert.doesNotMatch(migration, /\b(?:create|alter|drop)\s+policy\b/i);
  assert.doesNotMatch(migration, /\bgrant\s+[^;]*\bon\s+table\b/i);
  assert.doesNotMatch(migration, /\b(?:insert|update|delete)\s+(?:into|from\s+)?auth\.sessions\b/i);
  assert.match(migration, /notify pgrst, 'reload schema';/);
});

test("the shared user/session predicate locks every read-write authorization through commit", () => {
  const body = functionBody(
    deepHardeningMigration,
    "gymapp_private.has_current_auth_session(\n  p_user_id uuid\n)",
  );
  const readOnlyBranch = body.indexOf(
    "if pg_catalog.current_setting('transaction_read_only')::boolean then",
  );
  const readOnlyEnd = body.indexOf("end if;", readOnlyBranch);
  const writeLock = body.indexOf("for key share;", readOnlyEnd);

  assert.ok(readOnlyBranch >= 0);
  assert.ok(readOnlyEnd > readOnlyBranch);
  assert.ok(writeLock > readOnlyEnd);
  assert.match(body.slice(readOnlyBranch, readOnlyEnd), /return exists \(/);
  assert.doesNotMatch(body.slice(readOnlyBranch, readOnlyEnd), /for key share/i);
  assert.match(body.slice(readOnlyEnd), /for key share/i);
  assert.equal(
    (body.match(/session\.id = session_id_text::uuid/g) ?? []).length,
    2,
  );
  assert.equal(
    (body.match(/session\.user_id = p_user_id/g) ?? []).length,
    2,
  );
  assert.equal(
    (body.match(/session\.not_after > pg_catalog\.clock_timestamp\(\)/g) ?? [])
      .length,
    2,
  );
  assert.match(body, /volatile\s+security definer\s+set search_path = ''/);
  assert.match(
    deepHardeningMigration,
    /revoke all on function gymapp_private\.has_current_auth_session\(uuid\)\s+from public, anon, authenticated, service_role;/,
  );
  for (const signature of [
    "public.garmin_list_devices()",
    "public.require_live_session_for_account_deletion()",
    "gymapp_private.realtime_has_current_auth_session()",
  ]) {
    assert.match(
      deepHardeningMigration,
      new RegExp(`alter function ${signature.replace(/[().]/g, "\\$&")} volatile;`),
      `${signature} must not suppress the write-side session lock`,
    );
  }
});
