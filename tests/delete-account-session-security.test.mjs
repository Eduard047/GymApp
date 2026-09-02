import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import test, { after } from "node:test";

const edgePath = "supabase/functions/delete-account/index.ts";
const migrationPath =
  "supabase/migrations/20260823160705_require_one_time_account_deletion_grants.sql";
const hardeningMigrationPath =
  "supabase/migrations/20260902084252_harden_deep_scan_boundaries.sql";
const projectUrl = "https://project.example";
const publishableKey = "sb_publishable_delete_account_test";
const administrativeKey = "test-administrative-key";
const userId = "00000000-0000-4000-8000-000000000001";
const otherUserId = "00000000-0000-4000-8000-000000000002";
const accessToken = "test-user-access-token";
const deletionGrant = "10000000-0000-4000-8000-000000000001";

const originalDeno = globalThis.Deno;
const hadDeno = Object.prototype.hasOwnProperty.call(globalThis, "Deno");
const originalFetch = globalThis.fetch;
let edgeHandler;

globalThis.Deno = {
  env: {
    get(name) {
      return {
        SUPABASE_URL: projectUrl,
        SUPABASE_PUBLISHABLE_KEY: publishableKey,
        SUPABASE_SECRET_KEY: administrativeKey,
        GATEWAY_PREAUTH_HMAC_SECRET: "11".repeat(32),
      }[name];
    },
  },
  serve(handler) {
    edgeHandler = handler;
  },
};

await import(`${pathToFileURL(resolve(edgePath)).href}?delete-account-session-test`);
assert.equal(typeof edgeHandler, "function", "the real Edge handler must register with Deno.serve");

after(() => {
  globalThis.fetch = originalFetch;
  if (hadDeno) globalThis.Deno = originalDeno;
  else delete globalThis.Deno;
});

function deleteRequest() {
  return new Request(`${projectUrl}/functions/v1/delete-account`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ action: "delete", confirmation: "DELETE", grant: deletionGrant }),
  });
}

function prepareRequest() {
  return new Request(`${projectUrl}/functions/v1/delete-account`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ action: "prepare" }),
  });
}

async function withFetchMock(mock, operation) {
  globalThis.fetch = mock;
  try {
    return await operation();
  } finally {
    globalThis.fetch = originalFetch;
  }
}

test("account deletion RPC derives and binds a current signed session with least privilege", async () => {
  const [edge, sql, hardeningSql] = await Promise.all([
    readFile(edgePath, "utf8"),
    readFile(migrationPath, "utf8"),
    readFile(hardeningMigrationPath, "utf8"),
  ]);

  const authUserCall = edge.indexOf("/auth/v1/user");
  const liveSessionCall = edge.indexOf(
    "/rest/v1/rpc/consume_account_deletion_grant",
  );
  const administrativeDelete = edge.indexOf("/auth/v1/admin/users/");
  assert.ok(
    authUserCall > 0 && authUserCall < liveSessionCall &&
      liveSessionCall < administrativeDelete,
    "Auth-user and live-session decisions must precede administrative deletion",
  );
  assert.match(edge, /Authorization: authorization/);
  assert.match(edge, /const liveSessionUserId = await liveSessionResponse\.json\(\) as unknown/);
  assert.match(edge, /!isUuid\(liveSessionUserId\)/);
  assert.match(
    edge,
    /liveSessionUserId\.toLowerCase\(\) !== authenticatedUser\.id\.toLowerCase\(\)/,
  );
  assert.match(edge, /encodeURIComponent\(authenticatedUser\.id\)/);

  assert.match(
    sql,
    /create or replace function public\.prepare_account_deletion\(\)\s+returns jsonb/,
  );
  assert.match(hardeningSql, /account_deletion_grants_one_owner_purpose_idx/);
  assert.match(hardeningSql, /delete from gymapp_private\.account_deletion_grants as deletion_grant[\s\S]*deletion_grant\.user_id = caller_user_id/);
  assert.match(hardeningSql, /edge_preauth_debit\([\s\S]*'delete_account'/);
  assert.match(hardeningSql, /limit 64[\s\S]*for update skip locked/);
  assert.match(sql, /security definer\s+set search_path = ''/);
  assert.match(sql, /current_password_auth_is_recent\(interval '5 minutes'\)/);
  assert.match(sql, /method\.value->>'method' = 'password'/);
  assert.match(sql, /session\.id = caller_session_id/);
  assert.match(sql, /session\.user_id = caller_user_id/);
  assert.match(sql, /for key share/);
  assert.match(sql, /consumed_at is null/);
  assert.match(sql, /return caller_user_id/);
  assert.match(
    sql,
    /revoke all on function public\.consume_account_deletion_grant\(text\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    sql,
    /grant execute on function public\.consume_account_deletion_grant\(text\)[\s\S]*to authenticated/,
  );
});

test("fresh preparation returns only a bounded one-time grant", async () => {
  const expiresAt = "2026-08-23T16:00:00.000Z";
  const response = await withFetchMock(async (input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/edge_preauth_debit")) {
      return Response.json({ allowed: true, retryAfter: 0 });
    }
    if (url.endsWith("/auth/v1/user")) return Response.json({ id: userId });
    if (url.endsWith("/rest/v1/rpc/prepare_account_deletion")) {
      return Response.json({ version: 1, grant: deletionGrant, expiresAt });
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(prepareRequest()));

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { grant: deletionGrant, expiresAt });
});

test("database-enforced preparation exhaustion is surfaced after Auth validation", async () => {
  let authAttempted = false;
  let preparationAttempted = false;
  const response = await withFetchMock(async (input) => {
    const url = String(input);
    if (url.endsWith("/auth/v1/user")) {
      authAttempted = true;
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/prepare_account_deletion")) {
      preparationAttempted = true;
      return Response.json({ version: 1, error: "rate_limited", retryAfter: 60 });
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(prepareRequest()));

  assert.equal(response.status, 429);
  assert.equal(response.headers.get("retry-after"), "60");
  assert.equal(authAttempted, true);
  assert.equal(preparationAttempted, true);
});

test("an invalid bearer cannot debit any verified account budget", async () => {
  let identityBudgetAttempted = false;
  const response = await withFetchMock(async (input) => {
    const url = String(input);
    if (url.endsWith("/auth/v1/user")) {
      return Response.json(
        { code: "bad_jwt" },
        { status: 401 },
      );
    }
    if (url.endsWith("/rest/v1/rpc/edge_preauth_debit")) {
      identityBudgetAttempted = true;
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(prepareRequest()));

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), {
    error: "invalid_or_expired_token",
  });
  assert.equal(identityBudgetAttempted, false);
});

test("a revoked session is rejected even when the old user endpoint would still accept its JWT", async () => {
  const calls = [];
  const response = await withFetchMock(async (input, init = {}) => {
    const url = String(input);
    calls.push({ url, init });

    if (url.endsWith("/rest/v1/rpc/edge_preauth_debit")) {
      return Response.json({ allowed: true, retryAfter: 0 });
    }

    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/consume_account_deletion_grant")) {
      return Response.json(
        { code: "42501", message: "A current authenticated session is required" },
        { status: 403 },
      );
    }
    if (url.includes("/auth/v1/admin/users/")) {
      return Response.json({});
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(deleteRequest()));

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "invalid_deletion_grant" });
  assert.equal(calls.filter(({ url }) => url.endsWith("/auth/v1/user")).length, 1);
  assert.equal(calls.filter(({ url }) => url.includes("/auth/v1/admin/users/")).length, 0);

  const rpcCall = calls[2];
  assert.equal(
    rpcCall.url,
    `${projectUrl}/rest/v1/rpc/consume_account_deletion_grant`,
  );
  assert.equal(rpcCall.init.method, "POST");
  assert.equal(rpcCall.init.body, JSON.stringify({ p_grant: deletionGrant }));
  const rpcHeaders = new Headers(rpcCall.init.headers);
  assert.equal(rpcHeaders.get("authorization"), `Bearer ${accessToken}`);
  assert.equal(rpcHeaders.get("apikey"), publishableKey);
  assert.notEqual(rpcHeaders.get("apikey"), administrativeKey);
});

test("a live session hard-deletes only the UUID returned by the bound RPC", async () => {
  const calls = [];
  const response = await withFetchMock(async (input, init = {}) => {
    const url = String(input);
    calls.push({ url, init });

    if (url.endsWith("/rest/v1/rpc/edge_preauth_debit")) {
      return Response.json({ allowed: true, retryAfter: 0 });
    }

    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/consume_account_deletion_grant")) {
      return Response.json(userId);
    }
    if (url === `${projectUrl}/auth/v1/admin/users/${userId}`) {
      return Response.json({});
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(deleteRequest()));

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  assert.equal(calls.length, 4);

  const deleteCall = calls[3];
  assert.equal(deleteCall.url, `${projectUrl}/auth/v1/admin/users/${userId}`);
  assert.equal(deleteCall.init.method, "DELETE");
  assert.equal(deleteCall.init.body, JSON.stringify({ should_soft_delete: false }));
  const adminHeaders = new Headers(deleteCall.init.headers);
  assert.equal(adminHeaders.get("apikey"), administrativeKey);
  assert.equal(adminHeaders.get("authorization"), `Bearer ${administrativeKey}`);
  assert.notEqual(adminHeaders.get("authorization"), `Bearer ${accessToken}`);
});

test("a malformed live-session response cannot select an administrative deletion target", async () => {
  let adminDeleteAttempted = false;
  const response = await withFetchMock(async (input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/edge_preauth_debit")) {
      return Response.json({ allowed: true, retryAfter: 0 });
    }
    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/consume_account_deletion_grant")) {
      return Response.json({ id: userId });
    }
    if (url.includes("/auth/v1/admin/users/")) {
      adminDeleteAttempted = true;
      return Response.json({});
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(deleteRequest()));

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "invalid_or_expired_token" });
  assert.equal(adminDeleteAttempted, false);
});

test("a live-session UUID mismatch cannot redirect the administrative delete", async () => {
  let adminDeleteAttempted = false;
  const response = await withFetchMock(async (input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/edge_preauth_debit")) {
      return Response.json({ allowed: true, retryAfter: 0 });
    }
    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/consume_account_deletion_grant")) {
      return Response.json(otherUserId);
    }
    if (url.includes("/auth/v1/admin/users/")) {
      adminDeleteAttempted = true;
      return Response.json({});
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(deleteRequest()));

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "invalid_or_expired_token" });
  assert.equal(adminDeleteAttempted, false);
});
