import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import test, { after } from "node:test";

const originalDeno = globalThis.Deno;
const hadDeno = Object.prototype.hasOwnProperty.call(globalThis, "Deno");
const originalFetch = globalThis.fetch;

globalThis.Deno = {
  env: {
    get(name) {
      return name === "GATEWAY_PREAUTH_HMAC_SECRET" ? "22".repeat(32) : undefined;
    },
  },
};

const { debitVerifiedIdentityBudget } = await import(
  `${pathToFileURL(resolve("supabase/functions/_shared/preauth-budget.ts")).href}?verified-identity-budget-test`
);

after(() => {
  globalThis.fetch = originalFetch;
  if (hadDeno) globalThis.Deno = originalDeno;
  else delete globalThis.Deno;
});

const projectUrl = "https://project.example";
const administrativeKey = "test-administrative-key";
const firstAccount = "account:00000000-0000-4000-8000-000000000001";
const secondAccount = "account:00000000-0000-4000-8000-000000000002";

async function captureDebit(identity) {
  let body;
  globalThis.fetch = async (_input, init = {}) => {
    body = JSON.parse(String(init.body));
    return Response.json({ allowed: true, retryAfter: 0 });
  };
  const result = await debitVerifiedIdentityBudget(
    identity,
    "delete_account",
    projectUrl,
    administrativeKey,
  );
  assert.deepEqual(result, { status: "allowed" });
  return body;
}

test("the same verified account always debits the same pseudonymous bucket", async () => {
  const first = await captureDebit(firstAccount);
  const repeated = await captureDebit(firstAccount.toUpperCase());

  assert.equal(first.p_route, "delete_account");
  assert.match(first.p_source_hash, /^[0-9a-f]{64}$/);
  assert.equal(repeated.p_source_hash, first.p_source_hash);
});

test("different verified accounts cannot consume each other's bucket", async () => {
  const first = await captureDebit(firstAccount);
  const second = await captureDebit(secondAccount);

  assert.notEqual(first.p_source_hash, second.p_source_hash);
});

test("unverified or malformed identities fail closed without database work", async () => {
  let fetchAttempted = false;
  globalThis.fetch = async () => {
    fetchAttempted = true;
    return Response.json({ allowed: true, retryAfter: 0 });
  };

  const result = await debitVerifiedIdentityBudget(
    "account:not-a-uuid",
    "delete_account",
    projectUrl,
    administrativeKey,
  );

  assert.deepEqual(result, {
    status: "unavailable",
    reason: "invalid_verified_identity",
  });
  assert.equal(fetchAttempted, false);
});
