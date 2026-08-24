import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = await readFile(
  "supabase/migrations/20260824180727_harden_remaining_supabase_boundaries.sql",
  "utf8"
);
const databaseTest = await readFile(
  "supabase/tests/remaining_supabase_boundaries.sql",
  "utf8"
);

function sqlFunction(source, name) {
  const marker = `function ${name}`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `Missing SQL function ${name}`);
  const end = source.indexOf("$function$;", start);
  assert.notEqual(end, -1, `Unterminated SQL function ${name}`);
  return source.slice(start, end + "$function$;".length);
}

test("remaining-boundary migration fails closed on owner, policy, and default-ACL drift", () => {
  assert.match(migration, /current_user <> 'postgres'/);
  assert.match(migration, /GymApp boundary objects have an unexpected owner/);
  assert.match(migration, /Unexpected client policy exists on a private projection table/);
  assert.match(migration, /default_acl\.defaclnamespace = 0/);
  assert.match(migration, /Unexpected global postgres table or sequence defaults/);
  assert.match(migration, /Unexpected postgres-owned function schema/);
  assert.match(migration, /namespace_row\.nspname !~ '\^pg_'/);
  assert.match(migration, /set local lock_timeout = '5s'/);
  assert.match(migration, /set local statement_timeout = '2min'/);
});

test("server-owned progression tables have forced RLS, no policies, and no client grants", () => {
  for (const table of ["user_state_quarantine", "user_state_progression"]) {
    assert.match(
      migration,
      new RegExp(`alter table gymapp_private\\.${table}\\s+enable row level security`)
    );
    assert.match(
      migration,
      new RegExp(`alter table gymapp_private\\.${table}\\s+force row level security`)
    );
    assert.match(
      migration,
      new RegExp(
        `revoke all privileges on table gymapp_private\\.${table}` +
          `[\\s\\S]*?from public, anon, authenticated, service_role`
      )
    );
  }
  assert.doesNotMatch(migration, /create policy[\s\S]*user_state_(?:quarantine|progression)/i);
  assert.match(migration, /not class_row\.relforcerowsecurity/);
  assert.match(migration, /Private projection tables remain client-accessible/);
});

test("leaderboard compatibility projection requires the exact live Auth session", () => {
  const leaderboard = sqlFunction(migration, "public.leaderboard_public_rows");
  assert.match(leaderboard, /language sql\s+volatile\s+security definer/);
  assert.match(leaderboard, /set search_path = ''/);
  assert.match(
    leaderboard,
    /where \(select gymapp_private\.current_auth_session_is_live\(\)\)/
  );
  assert.match(leaderboard, /profile\.user_id = \(select auth\.uid\(\)\)/);
  assert.match(leaderboard, /gymapp_private\.user_state_quarantine/);
  assert.match(
    migration,
    /revoke all privileges on function public\.leaderboard_public_rows\(\)[\s\S]*?from public, anon, authenticated, service_role/
  );
  assert.match(
    migration,
    /grant execute on function public\.leaderboard_public_rows\(\)[\s\S]*?to authenticated, service_role/
  );
  assert.match(databaseTest, /a session owned by another account fails closed/);
  assert.match(databaseTest, /a JWT without session_id fails closed/);
  assert.match(databaseTest, /a malformed session_id fails closed/);
  assert.match(databaseTest, /an expired exact Auth session fails closed/);
  assert.match(databaseTest, /deleting the exact Auth session immediately revokes leaderboard reads/);
});

test("future postgres-owned GymApp objects are deny-by-default without changing platform owners", () => {
  for (const schema of ["public", "gymapp_private"]) {
    assert.match(
      migration,
      new RegExp(
        `alter default privileges for role postgres in schema ${schema}` +
          `[\\s\\S]*?revoke all privileges on tables` +
          `[\\s\\S]*?from public, anon, authenticated, service_role`
      )
    );
    assert.match(
      migration,
      new RegExp(
        `alter default privileges for role postgres in schema ${schema}` +
          `[\\s\\S]*?revoke all privileges on sequences` +
          `[\\s\\S]*?from public, anon, authenticated, service_role`
      )
    );
    assert.match(
      migration,
      new RegExp(
        `alter default privileges for role postgres in schema ${schema}` +
          `[\\s\\S]*?revoke all privileges on functions` +
          `[\\s\\S]*?from public, anon, authenticated, service_role`
      )
    );
  }
  assert.match(
    migration,
    /alter default privileges for role postgres\s+revoke all privileges on functions\s+from public, anon, authenticated, service_role/
  );
  assert.match(
    migration,
    /alter default privileges for role postgres in schema extensions\s+grant execute on functions to public/
  );
  assert.doesNotMatch(migration, /alter default privileges for role supabase_admin/i);
  assert.match(databaseTest, /future public functions are not executable by PUBLIC/);
  assert.match(databaseTest, /future private functions are not executable by PUBLIC/);
  assert.match(databaseTest, /future extension functions preserve the pre-hardening PUBLIC default/);
});

test("pgTAP coverage matches its plan and probes effective future privileges", () => {
  assert.match(databaseTest, /select plan\(56\)/);
  assert.equal(
    (databaseTest.match(
      /^select (?:has_table|has_function|ok|is|throws_ok|lives_ok)\(/gm
    ) || []).length,
    56,
    "the pgTAP plan must match its assertion count"
  );
  assert.match(databaseTest, /create table public\.gymapp_default_acl_table_probe/);
  assert.match(databaseTest, /create table gymapp_private\.gymapp_default_acl_table_probe/);
  assert.match(databaseTest, /create sequence public\.gymapp_default_acl_sequence_probe/);
  assert.match(databaseTest, /create sequence gymapp_private\.gymapp_default_acl_sequence_probe/);
  assert.match(databaseTest, /create function public\.gymapp_default_acl_function_probe/);
  assert.match(databaseTest, /create function gymapp_private\.gymapp_default_acl_function_probe/);
  assert.match(databaseTest, /create function extensions\.gymapp_default_acl_function_probe/);
  assert.match(databaseTest, /deny-by-default does not remove an explicit supported RPC grant/);
  assert.match(databaseTest, /rollback;/);
});
