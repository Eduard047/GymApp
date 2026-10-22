import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const edge = await readFile("supabase/functions/garmin-sync/index.ts", "utf8");
const migration = await readFile(
  "supabase/migrations/20260722012000_secure_garmin_capability_gateway.sql",
  "utf8",
);

test("garmin-sync capability RPCs run only with the service credential", () => {
  const start = edge.indexOf("async function capabilityRpc(");
  const end = edge.indexOf("async function resolveGarminCapability(");
  assert.ok(start !== -1 && end > start);
  const body = edge.slice(start, end);

  assert.doesNotMatch(body, /anonKey|createClient\(supabaseUrl, anon/);
  assert.doesNotMatch(body, /42501/);
  assert.match(body, /capabilityClient\(supabaseUrl, databaseSecretKey\)/);
});

test("garmin-sync only answers cross-origin requests from the first-party site", () => {
  const cors = edge.match(/const corsHeaders = \{[\s\S]*?\};/);
  assert.ok(cors);
  assert.doesNotMatch(cors[0], /Allow-Origin": "\*"/);
  assert.match(
    cors[0],
    /"Access-Control-Allow-Origin": "https:\/\/gymapptracker\.com"/,
  );
});

test("watch wrapper RPCs stay revoked from anon and public", () => {
  for (const signature of [
    "garmin_fetch_pending_plan(text)",
    "garmin_ack_plan(text, uuid, bigint)",
    "garmin_quarantine_pending_plan(text, uuid, bigint, text)",
  ]) {
    const revoke = new RegExp(
      `revoke all on function public\\.${signature.replace(/[()]/g, "\\$&")}\\s+from public, anon, authenticated`,
    );
    const grant = new RegExp(
      `grant execute on function public\\.${signature.replace(/[()]/g, "\\$&")}\\s+to service_role`,
    );
    assert.match(migration, revoke, `${signature} must be revoked from anon`);
    assert.match(migration, grant, `${signature} must be granted to service_role only`);
  }
});
