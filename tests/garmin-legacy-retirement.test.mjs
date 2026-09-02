import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test, { after, beforeEach } from "node:test";
import {
  createGarminCapability,
  deriveGarminAccountBinding,
  verifyGarminCapability,
} from "../supabase/functions/_shared/garmin-capability.ts";

// Run the unchanged Edge handler and crypto/validation helpers. Replace only
// the SDK transport; these tests do not claim to prove database authorization.
const transportUrl = `data:text/javascript,${encodeURIComponent(
  "export let createClient; export function setClient(value) { createClient = value; }",
)}`;
const transport = await import(transportUrl);
const userId = "00000000-0000-4000-8000-000000000001";
const deviceId = "00000000-0000-4000-8000-000000000002";
const planId = "00000000-0000-4000-8000-000000000003";
const nonce = "31".repeat(32);
const secret = "71".repeat(32);
const accountBinding = await deriveGarminAccountBinding(userId);
const token = await createGarminCapability({ userId, deviceId, nonce, secretHex: secret });
const device = {
  id: deviceId,
  display_name: "Test watch",
  created_at: "2026-08-31T00:00:00.000Z",
  last_seen_at: null,
  binding_version: 2,
  token_revision: 1,
};
const plan = {
  source: "gymapp", version: 1, title: "Test plan", note: "",
  createdAt: "2026-08-31T00:00:00.000Z", startedAt: "2026-08-31T00:00:00.000Z",
  exercises: [{ name: "Squat", sets: [{ weight: 20, reps: 5, orderIndex: 0 }] }],
};
let legacyMode;
let handler;
let clients;
let calls;
let rpcResult;
let background;
const savedGlobals = Object.fromEntries(["Deno", "EdgeRuntime"].map((name) => [
  name, Object.getOwnPropertyDescriptor(globalThis, name),
]));
globalThis.Deno = {
  env: { get: (name) => ({
    SUPABASE_URL: "https://project.example",
    SUPABASE_ANON_KEY: "test-public-key",
    SUPABASE_SERVICE_ROLE_KEY: "test-server-key",
    GARMIN_CAPABILITY_HMAC_SECRET: secret,
    GARMIN_LEGACY_CAPABILITY_MODE: legacyMode,
  })[name] },
  serve: (value) => { handler = value; },
};
globalThis.EdgeRuntime = { waitUntil: (task) => background.push(task) };
transport.setClient((_url, key, options) => {
  clients.push({ key, options });
  return {
    auth: { getUser: async () => ({ data: { user: { id: userId } }, error: null }) },
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (name === "garmin_record_capability_use") return { data: null, error: null };
      return { data: rpcResult(name, args), error: null };
    },
  };
});
const hooks = registerHooks({
  resolve(specifier, context, nextResolve) {
    return specifier === "@supabase/supabase-js"
      ? { url: transportUrl, shortCircuit: true }
      : nextResolve(specifier, context);
  },
});
try {
  await import("../supabase/functions/garmin-sync/index.ts");
} finally {
  hooks.deregister();
}
assert.equal(typeof handler, "function");
after(() => {
  for (const [name, descriptor] of Object.entries(savedGlobals)) {
    if (descriptor) Object.defineProperty(globalThis, name, descriptor);
    else delete globalThis[name];
  }
});
beforeEach(() => {
  legacyMode = "disabled";
  clients = []; calls = []; background = [];
  rpcResult = (name) => { throw new Error(`Unexpected database access: ${name}`); };
});
async function request(body, owner = false) {
  const response = await handler(new Request("https://project.example/functions/v1/garmin-sync", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(owner ? { Authorization: "Bearer test-owner-access-token" } : {}),
    },
    body: JSON.stringify(body),
  }));
  await Promise.all(background);
  assert.equal(response.headers.get("cache-control"), "no-store");
  return response;
}

test("retired legacy mode cannot be re-enabled to reach a database lookup", async () => {
  legacyMode = "enabled";
  assert.equal((await request({ action: "fetchPlan", deviceToken: nonce })).status, 426);
  assert.deepEqual(clients, []);
  assert.deepEqual(calls, []);
});

test("retired legacy fetch and ACK reject raw tokens before any SDK client or RPC", async () => {
  for (const deviceToken of [nonce, "42".repeat(32), "53".repeat(32)]) {
    for (const action of ["fetchPlan", "ackPlan"]) {
      const response = await request({ action, deviceToken, planId, planRevision: 1 });
      assert.equal(response.status, 426);
      assert.equal(response.headers.get("x-gymapp-garmin-capability-version"), "2");
    }
  }
  assert.deepEqual(clients, []);
  assert.deepEqual(calls, []);
});

test("retirement blocks explicit and implicit v2 pairing and rotation before Auth or RPC", async () => {
  for (const action of ["createDevice", "createDeviceIdempotent", "rotateDeviceToken"]) {
    for (const capabilityVersion of [undefined, 2]) {
      assert.equal((await request({ action, capabilityVersion }, true)).status, 426);
    }
  }
  assert.deepEqual(clients, []);
});

test("invalid signatures and malformed ACKs cannot reach a database", async () => {
  const forged = `${token.slice(0, -1)}${token.endsWith("0") ? "1" : "0"}`;
  for (const deviceToken of [forged, "g3.invalid", ` ${nonce}`, "AF".repeat(32)]) {
    assert.equal((await request({ action: "fetchPlan", deviceToken })).status, 400);
    assert.equal((await request({ action: "ackPlan", deviceToken, planId, planRevision: 1 })).status, 400);
  }
  assert.equal((await request({ action: "ackPlan", deviceToken: token, planId, planRevision: 0 })).status, 400);
  assert.deepEqual(clients, []);
});

test("signed v3 fetch keeps empty, pending-plan and owner/device binding behavior", async () => {
  rpcResult = () => ({ status: "empty" });
  assert.deepEqual(await (await request({ action: "fetchPlan", deviceToken: token })).json(), {
    status: "empty", capabilityVersion: 3,
  });
  const candidate = { status: "candidate", planId, planRevision: 1, bindingVersion: 2,
    accountBinding, deviceBinding: deviceId, plan };
  rpcResult = () => candidate;
  const response = await request({ action: "fetchPlan", deviceToken: token });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-gymapp-garmin-capability-version"), "3");
  assert.equal((await response.json()).plan.title, plan.title);
  for (const mismatch of [{ accountBinding: "f".repeat(64) }, { deviceBinding: planId }]) {
    rpcResult = () => ({ ...candidate, ...mismatch });
    assert.equal((await request({ action: "fetchPlan", deviceToken: token })).status, 500);
  }
  assert.ok(calls.every(({ args }) => args.p_device_token === nonce));
  assert.ok(calls.filter(({ name }) => name === "garmin_record_capability_use")
    .every(({ args }) => args.p_capability_version === 3));
  assert.ok(clients.every(({ key }) => key === "test-server-key"));
});

test("signed ACK preserves replay, conflict, revoked-device and per-device quota outcomes", async () => {
  for (const [data, status] of [
    [{ status: "acknowledged" }, 200], [{ status: "already_acknowledged" }, 200],
    [{ status: "conflict" }, 409], [{ error: "Invalid device" }, 401],
    [{ status: "rate_limited", retryAfter: 30 }, 429],
  ]) {
    calls = [];
    rpcResult = () => data;
    const response = await request({ action: "ackPlan", deviceToken: token, planId, planRevision: 1 });
    assert.equal(response.status, status);
    assert.deepEqual(calls[0], { name: "garmin_ack_plan", args: {
      p_device_token: nonce, p_plan_id: planId, p_plan_revision: 1,
    } });
    if (status === 401) assert.equal(calls.length, 1);
    if (status === 429) assert.equal(response.headers.get("retry-after"), "30");
  }
});

test("owner-authenticated v3 creation and recovery still return verifiable signed capabilities", async () => {
  rpcResult = (name) => {
    assert.equal(name, "garmin_create_device_idempotent");
    return { status: "created", device: { ...device, device_token: nonce } };
  };
  const created = await request({ action: "createDeviceIdempotent", capabilityVersion: 3,
    requestId: planId, deviceId, deviceNonce: nonce, displayName: device.display_name }, true);
  assert.equal(created.status, 200);
  assert.deepEqual(await verifyGarminCapability((await created.json()).device.device_token, secret), {
    accountBinding, deviceId, nonce,
  });
  const replacementNonce = "64".repeat(32);
  rpcResult = (name, args) => {
    assert.equal(name, "garmin_rotate_device_token");
    assert.equal(args.p_replacement_token, replacementNonce);
    return { status: "rotated", device: { ...device, token_revision: 2 } };
  };
  const rotated = await request({ action: "rotateDeviceToken", capabilityVersion: 3,
    deviceId, replacementNonce, expectedTokenRevision: 1 }, true);
  assert.equal(rotated.status, 200);
  assert.deepEqual(await verifyGarminCapability((await rotated.json()).device.device_token, secret), {
    accountBinding, deviceId, nonce: replacementNonce,
  });
  assert.ok(clients.every(({ key, options }) => key === "test-public-key" &&
    options.global.headers.Authorization === "Bearer test-owner-access-token"));
});
