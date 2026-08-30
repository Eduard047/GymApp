import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const repairName = "20260830171312_fix_live_snapshot_session_lock_mode.sql";
const migration = await readFile(`supabase/migrations/${repairName}`, "utf8");
const fixture = await readFile("supabase/tests/live_snapshot_session_lock.sql", "utf8");

test("runtime snapshot fixture checks volatility, locking, and denied access without user writes", () => {
  assert.match(fixture, /Another locked-session RPC declares read-only volatility/);
  assert.match(fixture, /Session revocation lock was removed/);
  for (const role of ["anon", "authenticated", "service_role"]) {
    assert.ok(fixture.includes(`set local role ${role};`));
  }
  assert.match(fixture, /Missing session was accepted/);
  assert.match(fixture, /Unknown session was accepted/);
  assert.match(fixture, /rollback;\s*$/);
  assert.doesNotMatch(fixture, /\b(?:insert into|update|delete from|create table)\s/i);
});

test("snapshot repair changes only volatility and preserves the locked session guard", () => {
  assert.match(migration, /alter function public\.social_live_workout_snapshot\(uuid, uuid, text\) volatile;/i);
  assert.match(migration, /pg_catalog\.to_jsonb\(p\) - 'provolatile'/);
  assert.match(migration, /current_contract is distinct from original_contract/);
  assert.match(migration, /pg_get_functiondef\(guard_function\) is distinct from guard_definition/);
  assert.match(migration, /for key share/);
  assert.match(migration, /p\.provolatile in \('s', 'v'\)/);
  assert.match(migration, /^begin;/);
  assert.match(migration, /lock_timeout = '5s'/);
  assert.match(migration, /statement_timeout = '30s'/);
  assert.match(migration, /notify pgrst, 'reload schema'/);
  assert.match(migration, /commit;\s*$/);
  assert.doesNotMatch(migration, /\b(?:insert into|delete from|create or replace|drop|grant|revoke)\s/i);
  for (const role of ["anon", "authenticated", "service_role"]) {
    for (const target of ["snapshot_function", "guard_function"]) {
      assert.ok(migration.includes(`has_function_privilege('${role}', ${target}, 'EXECUTE')`));
    }
  }
});

test("effective LIVE session-guard callers cannot declare read-only RPC volatility", async () => {
  const functions = new Map();
  for (const name of (await readdir("supabase/migrations")).filter(name => name.endsWith(".sql")).sort()) {
    const sql = await readFile(`supabase/migrations/${name}`, "utf8");
    for (const match of sql.matchAll(/create or replace function ((?:public|gymapp_private)\.\w+)\([\s\S]*?\$function\$;/gi)) {
      functions.set(match[1], match[0]);
    }
    if (name === repairName) {
      const key = "public.social_live_workout_snapshot";
      assert.ok(functions.has(key));
      functions.set(key, functions.get(key).replace(/\bstable\b/i, "volatile"));
    }
  }
  let checked = 0;
  for (const [name, definition] of functions) {
    if (!/perform gymapp_private\.live_gateway_require_session\(/i.test(definition)) continue;
    const header = definition.split(/as \$function\$/i)[0];
    assert.doesNotMatch(header, /\b(?:stable|immutable)\b/i, name);
    checked += 1;
  }
  assert.ok(checked > 0);
});
