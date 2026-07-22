import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import test, { after } from "node:test";

const edgePath = "supabase/functions/delete-account/index.ts";
const migrationPath =
  "supabase/migrations/20260722010000_require_live_session_for_account_deletion.sql";
const sessionHelperMigrationPath =
  "supabase/migrations/20260721142951_add_garmin_device_rate_limits.sql";
const projectUrl = "https://project.example";
const publishableKey = "sb_publishable_delete_account_test";
const administrativeKey = "test-administrative-key";
const userId = "00000000-0000-4000-8000-000000000001";
const otherUserId = "00000000-0000-4000-8000-000000000002";
const accessToken = "test-user-access-token";

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
    body: JSON.stringify({ confirmation: "DELETE" }),
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
  const [edge, sql, sessionHelperSql] = await Promise.all([
    readFile(edgePath, "utf8"),
    readFile(migrationPath, "utf8"),
    readFile(sessionHelperMigrationPath, "utf8"),
  ]);

  const authUserCall = edge.indexOf("/auth/v1/user");
  const liveSessionCall = edge.indexOf(
    "/rest/v1/rpc/require_live_session_for_account_deletion",
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
    /create or replace function public\.require_live_session_for_account_deletion\(\)\s+returns uuid/,
  );
  assert.match(sql, /security definer\s+set search_path = ''/);
  assert.match(sql, /caller_user_id uuid := auth\.uid\(\)/);
  assert.match(
    sql,
    /not gymapp_private\.has_current_auth_session\(caller_user_id\)/,
  );
  assert.match(sql, /return caller_user_id/);
  const helperStart = sessionHelperSql.indexOf(
    "create or replace function gymapp_private.has_current_auth_session",
  );
  const helperEnd = sessionHelperSql.indexOf("$function$;", helperStart);
  const sessionHelper = sessionHelperSql.slice(helperStart, helperEnd);
  assert.ok(helperStart > 0 && helperEnd > helperStart);
  assert.match(sessionHelper, /auth\.jwt\(\) ->> 'session_id'/);
  assert.match(sessionHelper, /session\.id = current_session_id/);
  assert.match(sessionHelper, /session\.user_id = p_user_id/);
  assert.doesNotMatch(
    sql.slice(sql.indexOf("create or replace function"), sql.indexOf("$function$;", sql.indexOf("create or replace function"))),
    /p_user_id|p_session_id/,
  );
  assert.match(
    sql,
    /revoke all on function public\.require_live_session_for_account_deletion\(\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    sql,
    /grant execute on function public\.require_live_session_for_account_deletion\(\)[\s\S]*to authenticated/,
  );
  assert.match(
    sql,
    /has_function_privilege\([\s\S]*'anon'[\s\S]*require_live_session_for_account_deletion\(\)[\s\S]*'EXECUTE'/,
  );
  assert.match(
    sql,
    /has_function_privilege\([\s\S]*'service_role'[\s\S]*require_live_session_for_account_deletion\(\)[\s\S]*'EXECUTE'/,
  );
});

test("a revoked session is rejected even when the old user endpoint would still accept its JWT", async () => {
  const calls = [];
  const response = await withFetchMock(async (input, init = {}) => {
    const url = String(input);
    calls.push({ url, init });

    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/require_live_session_for_account_deletion")) {
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
  assert.deepEqual(await response.json(), { error: "invalid_or_expired_token" });
  assert.equal(calls.filter(({ url }) => url.endsWith("/auth/v1/user")).length, 1);
  assert.equal(calls.filter(({ url }) => url.includes("/auth/v1/admin/users/")).length, 0);

  const rpcCall = calls[1];
  assert.equal(
    rpcCall.url,
    `${projectUrl}/rest/v1/rpc/require_live_session_for_account_deletion`,
  );
  assert.equal(rpcCall.init.method, "POST");
  assert.equal(rpcCall.init.body, "{}");
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

    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/require_live_session_for_account_deletion")) {
      return Response.json(userId);
    }
    if (url === `${projectUrl}/auth/v1/admin/users/${userId}`) {
      return Response.json({});
    }
    throw new Error(`Unexpected request: ${url}`);
  }, () => edgeHandler(deleteRequest()));

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  assert.equal(calls.length, 3);

  const deleteCall = calls[2];
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
    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/require_live_session_for_account_deletion")) {
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
    if (url.endsWith("/auth/v1/user")) {
      return Response.json({ id: userId });
    }
    if (url.endsWith("/rest/v1/rpc/require_live_session_for_account_deletion")) {
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
