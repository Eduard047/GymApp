import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  createGarminCapability,
  deriveGarminAccountBinding,
  parseGarminCapability,
  verifyGarminCapability,
} from "../supabase/functions/_shared/garmin-capability.ts";

const USER_ID = "00000000-0000-4000-8000-000000000001";
const DEVICE_ID = "00000000-0000-4000-8000-000000000002";
const NONCE = "3".repeat(64);
const SECRET = "a".repeat(64);
const OTHER_SECRET = "b".repeat(64);

test("Garmin v3 capabilities authenticate owner, device, and nonce", async () => {
  const accountBinding = await deriveGarminAccountBinding(USER_ID);
  const capability = await createGarminCapability({
    userId: USER_ID,
    deviceId: DEVICE_ID,
    nonce: NONCE,
    secretHex: SECRET,
  });

  assert.equal(typeof capability, "string");
  assert.equal(capability.length, 234);
  assert.deepEqual(parseGarminCapability(capability), {
    accountBinding,
    deviceId: DEVICE_ID,
    nonce: NONCE,
    tag: capability.slice(-64),
    signedPayload: capability.slice(0, 169),
  });
  assert.deepEqual(await verifyGarminCapability(capability, SECRET), {
    accountBinding,
    deviceId: DEVICE_ID,
    nonce: NONCE,
  });

  for (const invalid of [
    capability.replace(`.${accountBinding}.`, `.${"f".repeat(64)}.`),
    capability.replace(DEVICE_ID, "00000000-0000-4000-8000-000000000003"),
    capability.replace(`.${NONCE}.`, `.${"4".repeat(64)}.`),
    `${capability.slice(0, -1)}${capability.endsWith("0") ? "1" : "0"}`,
    NONCE,
    ` ${capability}`,
  ]) {
    assert.equal(await verifyGarminCapability(invalid, SECRET), null);
  }
  assert.equal(await verifyGarminCapability(capability, OTHER_SECRET), null);
});

test("invalid capability configuration and identifiers fail closed", async () => {
  assert.equal(await createGarminCapability({
    userId: "not-a-user",
    deviceId: DEVICE_ID,
    nonce: NONCE,
    secretHex: SECRET,
  }), null);
  assert.equal(await createGarminCapability({
    userId: USER_ID,
    deviceId: DEVICE_ID,
    nonce: NONCE,
    secretHex: "short",
  }), null);
  assert.equal(await verifyGarminCapability("g3.invalid", SECRET), null);
});

test("the Edge gateway fast-authenticates v3 and bounds the legacy transition", async () => {
  const edge = await readFile("supabase/functions/garmin-sync/index.ts", "utf8");
  const fetchStart = edge.indexOf('if (body.action === "fetchPlan")');
  const ackStart = edge.indexOf('if (body.action === "ackPlan")');
  const fetch = edge.slice(fetchStart, ackStart);
  const ack = edge.slice(ackStart);

  assert.ok(fetchStart > 0 && ackStart > fetchStart);
  assert.ok(fetch.indexOf("resolveGarminCapability") < fetch.indexOf("capabilityRpc"));
  assert.match(fetch, /p_device_token: capability\.nonce/);
  assert.match(fetch, /candidate\.accountBinding !== capability\.accountBinding/);
  assert.match(fetch, /candidate\.deviceBinding\.toLowerCase\(\) !== capability\.deviceId/);
  assert.ok(ack.indexOf("resolveGarminCapability") < ack.indexOf("capabilityRpc"));
  assert.match(ack, /p_device_token: capability\.nonce/);
  assert.match(edge, /requiredEnv\("GARMIN_CAPABILITY_HMAC_SECRET"\)/);
  assert.match(edge, /requiredEnv\("SUPABASE_SERVICE_ROLE_KEY"\)/);
  assert.match(edge, /requiredEnv\([\s\S]*"GARMIN_LEGACY_CAPABILITY_MODE"/);
  assert.match(edge, /if \(value === undefined \|\| value === 2\) return 2/);
  assert.match(edge, /legacyEnabled && typeof value === "string"/);
  assert.match(edge, /verifyGarminCapability\(value, hmacSecret\)/);
  assert.match(edge, /candidate\?\.error !== "Invalid device"[\s\S]*recordCapabilityUse/);
  assert.match(fetch, /!legacyCapabilitiesEnabled && DEVICE_NONCE_PATTERN\.test\(deviceToken\)[\s\S]*426/);
  assert.doesNotMatch(fetch, /p_device_token: deviceToken/);
  assert.doesNotMatch(ack, /p_device_token: deviceToken/);
});

test("database capability RPCs are private and shared pre-auth state is retired", async () => {
  const migration = await readFile(
    "supabase/migrations/20260722012000_secure_garmin_capability_gateway.sql",
    "utf8",
  );
  assert.match(migration, /begin;[\s\S]*set local lock_timeout = '5s';/);
  assert.match(migration, /set local statement_timeout = '30s';/);
  assert.match(migration, /revoke all on function public\.garmin_fetch_pending_plan\(text\)[\s\S]*from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function public\.garmin_fetch_pending_plan\(text\)[\s\S]*to service_role/);
  assert.match(migration, /grant execute on function public\.garmin_ack_plan\(text, uuid, bigint\)[\s\S]*to service_role/);
  assert.match(migration, /drop table if exists gymapp_private\.garmin_preauth_rate_limits/);
  assert.match(migration, /device\.device_token = gymapp_private\.garmin_device_token_hash/);
  assert.match(migration, /consume_garmin_device_rate_limit\([\s\S]*found_device_id/);
  assert.match(migration, /legacy_capability_last_seen_at/);
  assert.match(migration, /v3_capability_last_seen_at/);
  assert.match(migration, /grant execute on function public\.garmin_record_capability_use\(text, smallint\)[\s\S]*to service_role/);
  assert.match(migration, /observation_time - interval '1 hour'/);
  const limiter = migration.slice(
    migration.indexOf("create or replace function gymapp_private.garmin_rate_limit_for_token"),
    migration.indexOf("revoke all on function gymapp_private.garmin_rate_limit_for_token"),
  );
  assert.ok(limiter.indexOf("select device.id") < limiter.indexOf("consume_garmin_device_rate_limit"));
  assert.doesNotMatch(
    limiter,
    /garmin_preauth|insert into|on conflict/i,
  );
});

test("unowned released v2 tokens are cleared on every account transition", async () => {
  const comm = await readFile("garmin/source/GymComm.mc", "utf8");
  const reconcile = comm.match(
    /static function reconcileCloudDeviceToken\(nextAccountBinding\) \{[\s\S]*?\n    \}/,
  )?.[0] || "";

  assert.match(
    reconcile,
    /tokenVersion == 2 && tokenAccountBinding == null[\s\S]*currentAccountBinding[\s\S]*!currentAccountBinding\.toString\(\)\.equals\(nextAccountBinding\.toString\(\)\)[\s\S]*return clearCloudDeviceToken\(\)/,
  );
  assert.ok(
    reconcile.indexOf("tokenVersion == 2 && tokenAccountBinding == null") <
      reconcile.indexOf("nextAccountBinding.toString().equals(signedOutAccountBinding)"),
    "an unowned v2 token must be cleared before the signed-out transition can preserve a token",
  );
});

test("PWA preserves released watches while the future binary binds v3 to account and device", async () => {
  const [app, versionedApp, comm, store, properties, worker] = await Promise.all([
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/app.v52.js", "utf8"),
    readFile("garmin/source/GymComm.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/resources/settings/properties.xml", "utf8"),
    readFile("pwa/sw.js", "utf8"),
  ]);
  assert.equal(app, versionedApp);
  assert.match(app, /const GARMIN_CAPABILITY_VERSION = 2/);
  assert.match(app, /const capabilityMigration = value\?\.version !== GARMIN_CAPABILITY_VERSION/);
  assert.match(app, /version: GARMIN_CAPABILITY_VERSION/);
  assert.match(app, /GARMIN_CAPABILITY_VERSION === 3[\s\S]*replacementNonce/);
  assert.match(app, /GARMIN_CAPABILITY_VERSION === 2[\s\S]*GARMIN_LEGACY_CAPABILITY_PATTERN/);
  assert.match(app, /replacementNonce/);
  assert.match(app, /capabilityVersion: GARMIN_CAPABILITY_VERSION/);
  assert.match(app, /GARMIN_CAPABILITY_PATTERN\.exec\(token\)/);
  assert.match(worker, /CACHE_VERSION = "v69"/);

  assert.match(comm, /cloudCapabilityLength = 234/);
  assert.match(comm, /legacyCapabilityLength = 64/);
  assert.match(comm, /cloudTokenVersion/);
  assert.match(comm, /GymStore\.isValidAccountBinding\(value\)[\s\S]*return 2/);
  assert.match(comm, /cloudTokenAccountBinding/);
  assert.match(comm, /cloudTokenDeviceBinding/);
  assert.match(
    comm,
    /requestCloudPlan\(callback\)[\s\S]*if \(!GymStore\.hasAccountBinding\(\)\)[\s\S]*TOKEN OWNER/,
  );
  assert.match(comm, /responseAccountBinding[\s\S]*expectedAccountBinding/);
  assert.match(comm, /responseDeviceBinding[\s\S]*expectedDeviceBinding/);
  assert.match(comm, /reconcileCloudDeviceToken/);
  assert.match(comm, /Properties\.setValue\("CloudDeviceToken", ""\)/);
  assert.match(
    comm,
    /hasCloudDeviceToken\(\)[\s\S]*GymStore\.hasAccountBinding\(\)[\s\S]*GymStore\.accountBinding/,
  );
  assert.match(comm, /nextAccountBinding\.toString\(\)\.equals\(signedOutAccountBinding\)/);
  assert.match(comm, /rememberLegacyCloudTokenBinding/);
  assert.ok(
    comm.indexOf("rememberLegacyCloudTokenBinding(") <
      comm.indexOf("syncMessageFromCloudData(data)"),
  );
  assert.match(
    comm,
    /acknowledgeCloudPlan[\s\S]*legacyTokenAccountBinding\(\)[\s\S]*legacyTokenDeviceBinding\(\)[\s\S]*GymStore\.syncBindingsMatch/,
  );
  assert.match(properties, /CloudLegacyTokenOwner/);
  assert.match(properties, /CloudLegacyTokenDevice/);
  assert.match(store, /GymComm\.reconcileCloudDeviceToken\(nextAccountBinding\)/);
});
