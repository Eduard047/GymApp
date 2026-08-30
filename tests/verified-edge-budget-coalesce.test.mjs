import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const [isolation, migration, fixture] = await Promise.all([
  readFile("supabase/migrations/20260825105114_isolate_verified_edge_rate_limits.sql", "utf8"),
  readFile("supabase/migrations/20260830164651_fix_verified_edge_budget_coalesce.sql", "utf8"),
  readFile("supabase/tests/verified_edge_budget_coalesce.sql", "utf8"),
]);
const body = isolation.match(/as \$function\$\s*([\s\S]*?)\$function\$;/)?.[1];
const replacement = migration.match(
  /pg_catalog\.replace\(\s*original_definition,\s*'([^']+)',\s*'([^']+)'\s*\)/,
);

test("forward repair removes exactly the two invalid conditional expressions", () => {
  assert.ok(body);
  assert.ok(replacement);
  assert.equal(body.split(replacement[1]).length - 1, 2);
  const repaired = body.replaceAll(replacement[1], replacement[2]);
  assert.doesNotMatch(repaired, /pg_catalog\.(?:coalesce|greatest|least|nullif)\s*\(/i);
  assert.equal((repaired.match(/coalesce\(source_allowed, false\)/g) ?? []).length, 2);
  assert.equal(repaired.replaceAll(replacement[2], replacement[1]), body);
  for (const limit of ["('social_live', 180)", "('delete_account', 12)", "('garmin_legacy', 90)"]) {
    assert.ok(repaired.includes(limit));
  }
  assert.doesNotMatch(repaired, /global_(?:hash|limit)/);
});

test("repair is transactional, bounded, narrowly guarded, and safe to reapply", () => {
  assert.match(migration, /^begin;/);
  assert.match(migration, /set local lock_timeout = '5s'/);
  assert.match(migration, /set local statement_timeout = '30s'/);
  assert.match(migration, /invalid_calls = 2/);
  assert.match(migration, /elsif invalid_calls = 0/);
  assert.match(migration, /Unexpected verified Edge budget definition/);
  assert.match(migration, /commit;\s*$/);
  assert.doesNotMatch(migration, /\b(?:insert into|update|delete from|drop|grant|revoke)\s/i);
});

test("later limiter redefinitions cannot reintroduce qualified conditional expressions", async () => {
  let latest;
  for (const name of (await readdir("supabase/migrations")).filter(name => name.endsWith(".sql")).sort()) {
    const source = await readFile(`supabase/migrations/${name}`, "utf8");
    const definition = source.match(
      /create or replace function gymapp_private\.edge_preauth_debit\([\s\S]*?as \$function\$\s*([\s\S]*?)\$function\$;/i,
    );
    if (definition) latest = { name, body: definition[1] };
  }
  assert.ok(latest);
  const effectiveBody = latest.name < "20260830164651_fix_verified_edge_budget_coalesce.sql"
    ? latest.body.replaceAll(replacement[1], replacement[2])
    : latest.body;
  assert.doesNotMatch(effectiveBody, /pg_catalog\.(?:coalesce|greatest|least|nullif)\s*\(/i);
});

test("repair checks owner, ACL, search path, security mode, and wrapper preservation", () => {
  assert.match(migration, /p\.proowner, p\.proacl, p\.proconfig, p\.prosecdef, p\.provolatile/);
  assert.match(migration, /current_security is distinct from original_security/);
  assert.match(migration, /pg_get_functiondef\(wrapper_function\)\s*is distinct from wrapper_definition/);
  for (const role of ["anon", "authenticated", "service_role"]) {
    assert.ok(migration.includes(`has_function_privilege('${role}', wrapper_function, 'EXECUTE')`));
    assert.ok(migration.includes(`has_function_privilege('${role}', target_function, 'EXECUTE')`));
  }
});

test("runtime regression covers allowed, exhausted, isolated, reset, invalid, and denied paths", () => {
  assert.match(fixture, /First request failed/);
  assert.match(fixture, /Last allowed request failed/);
  assert.match(fixture, /Exhausted request did not fail closed/);
  assert.match(fixture, /One identity consumed another identity budget/);
  assert.match(fixture, /Expired window did not reset/);
  assert.match(fixture, /exception when invalid_parameter_value then null/);
  for (const role of ["anon", "authenticated", "service_role"]) {
    assert.ok(fixture.includes(`set local role ${role};`));
  }
  assert.match(fixture, /Service role bypassed the public wrapper/);
  assert.match(fixture, /Service role obtained direct budget-table access/);
  assert.match(fixture, /pg_catalog\.gen_random_uuid\(\)/);
  assert.match(fixture, /hashtextextended\(test_source_hash, 0\), 128\) <> 0/);
  assert.match(fixture, /rollback;\s*$/);
  assert.doesNotMatch(fixture, /auth\.users|public\.profiles|user_state|live_workout_rooms/);
});
