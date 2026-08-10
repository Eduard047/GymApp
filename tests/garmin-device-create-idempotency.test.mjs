import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const migrationPath =
  "supabase/migrations/20260810131353_add_idempotent_garmin_device_creation.sql";
const pgTapPath = "supabase/tests/idempotent_garmin_device_creation.sql";
const edgePath = "supabase/functions/garmin-sync/index.ts";
const pwaPath = "pwa/app.js";
const iosPath = "ios/GymApp-iOS/GymApp/Services/GarminCloudService.swift";
const iosTestsPath = "ios/GymApp-iOS/GymAppTests/CoreParityTests.swift";
const iosAppStatePath = "ios/GymApp-iOS/GymApp/App/AppState.swift";

const [migration, pgTap, edge, pwa, ios, iosTests, iosAppState] = await Promise.all([
  readFile(migrationPath, "utf8"),
  readFile(pgTapPath, "utf8"),
  readFile(edgePath, "utf8"),
  readFile(pwaPath, "utf8"),
  readFile(iosPath, "utf8"),
  readFile(iosTestsPath, "utf8"),
  readFile(iosAppStatePath, "utf8"),
]);

const sliceBetween = (source, startText, endText) => {
  const start = source.indexOf(startText);
  const end = source.indexOf(endText, start + startText.length);
  assert.ok(start >= 0 && end > start, `missing source slice: ${startText}`);
  return source.slice(start, end);
};

const functionSource = (source, name) => {
  const functionStart = source.indexOf(`function ${name}(`);
  assert.ok(functionStart >= 0, `missing function ${name}`);
  const start = source.slice(Math.max(0, functionStart - 6), functionStart) === "async "
    ? functionStart - 6
    : functionStart;
  const brace = source.indexOf("{", start);
  let depth = 0;
  let quote = null;
  let escaped = false;
  for (let index = brace; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'" || character === "`") {
      quote = character;
      continue;
    }
    if (character === "{") depth += 1;
    if (character === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(start, index + 1);
    }
  }
  throw new Error(`unterminated function ${name}`);
};

test("migration makes exact create replay owner-bound, atomic, private, and visible", () => {
  const creator = sliceBetween(
    migration,
    "create or replace function public.garmin_create_device_idempotent",
    "revoke all on function public.garmin_create_device_idempotent",
  );
  const sessionBoundary = sliceBetween(
    migration,
    "create or replace function gymapp_private.has_current_auth_session",
    "revoke all on function gymapp_private.has_current_auth_session",
  );

  assert.match(migration, /add column if not exists creation_request_id uuid/);
  assert.match(
    migration,
    /create unique index if not exists garmin_devices_creation_request_id_unique[\s\S]*where creation_request_id is not null/,
  );
  assert.match(sessionBoundary, /security definer\s+set search_path = ''/);
  assert.match(sessionBoundary, /session\.id = current_session_id/);
  assert.match(sessionBoundary, /session\.user_id = p_user_id/);
  assert.match(
    sessionBoundary,
    /session\.not_after is null[\s\S]*session\.not_after > pg_catalog\.clock_timestamp\(\)/,
  );
  assert.match(creator, /security definer\s+set search_path = ''/);
  assert.ok(
    creator.indexOf("has_current_auth_session") <
      creator.indexOf("garmin_device_token_hash"),
    "authorization must precede token work",
  );
  assert.ok(
    creator.indexOf("has_current_auth_session") <
      creator.indexOf("pg_advisory_xact_lock"),
    "authorization must precede serialization",
  );
  assert.match(creator, /p_request_id::text !~ '[^']*-4\[0-9a-f\]\{3\}-\[89ab\]/);
  assert.match(creator, /p_device_id::text !~ '[^']*-4\[0-9a-f\]\{3\}-\[89ab\]/);
  assert.match(creator, /p_device_token !~ '\^\[a-f0-9\]\{64\}\$'/);
  assert.match(creator, /octet_length\([\s\S]*convert_to\(clean_display_name, 'UTF8'\)[\s\S]*> 320/);
  assert.match(creator, /hashtextextended\(p_request_id::text, 719924\)/);
  assert.match(creator, /device\.creation_request_id = p_request_id/);
  assert.match(creator, /found_device\.user_id = caller_user_id/);
  assert.match(creator, /found_device\.id = p_device_id/);
  assert.match(creator, /found_device\.device_token = requested_token_hash/);
  assert.match(creator, /found_device\.display_name = clean_display_name/);
  assert.match(creator, /found_device\.token_revision = 1/);
  assert.match(creator, /found_device\.revoked_at is null/);
  assert.ok(
    creator.indexOf("'status', 'already_created'") <
      creator.indexOf("hashtextextended(caller_user_id::text, 719922)"),
    "exact replay must return before owner quotas",
  );
  assert.match(creator, /active_device_count >= 5 or recent_device_count >= 20/);
  assert.match(creator, /insert into public\.garmin_devices/);
  assert.match(creator, /requested_token_hash/);
  const insert = creator.slice(
    creator.indexOf("insert into public.garmin_devices"),
    creator.indexOf("on conflict do nothing"),
  );
  assert.match(insert, /values \([\s\S]*requested_token_hash/);
  assert.doesNotMatch(insert, /p_device_token/);
  assert.match(creator, /on conflict do nothing[\s\S]*'status', 'conflict'/);
  assert.doesNotMatch(creator, /update public\.garmin_devices/i);
  assert.match(
    migration,
    /revoke all on function public\.garmin_create_device_idempotent\([\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.garmin_create_device_idempotent\([\s\S]*to authenticated/,
  );
  assert.match(
    migration,
    /revoke all on table public\.garmin_devices\s+from public, anon, authenticated/,
  );
  assert.match(migration, /notify pgrst, 'reload schema';\s+commit;/);
});

test("pgTAP fixture covers success, replay, denial, revocation, quotas, and no side effects", () => {
  assert.match(pgTap, /select plan\(40\)/);
  assert.match(pgTap, /'created'[\s\S]*'already_created'/);
  assert.match(pgTap, /changed token is rejected/);
  assert.match(pgTap, /changed device ID is rejected/);
  assert.match(pgTap, /changed display payload is rejected/);
  assert.match(pgTap, /another owner cannot replay/);
  assert.match(pgTap, /revoked request cannot replay or resurrect/);
  assert.match(pgTap, /expired exact Auth session is rejected/);
  assert.match(pgTap, /anonymous invocation is rejected/);
  assert.match(pgTap, /five-active-device limit remains enforced/);
  assert.match(pgTap, /20-per-day creation limit remains enforced/);
  assert.match(pgTap, /malformed requests have no device-row side effects/);
  assert.match(pgTap, /duplicate and concurrent-equivalent calls converge/);
  assert.match(pgTap, /legacy-created rows remain compatible/);
  assert.match(pgTap, /select \* from finish\(\);\s+\nrollback;/);
});

test("Edge exposes a separately validated idempotent action without changing old clients", () => {
  const idempotentStart = edge.indexOf(
    'if (body.action === "createDeviceIdempotent")',
  );
  const legacyStart = edge.indexOf('if (body.action === "createDevice")');
  const creator = edge.slice(idempotentStart, legacyStart);
  assert.ok(idempotentStart > 0 && legacyStart > idempotentStart);
  assert.ok(creator.indexOf("getUser()") < creator.indexOf("userClient.rpc("));
  assert.match(creator, /UUID_V4_PATTERN\.test\(requestId\)/);
  assert.match(creator, /UUID_V4_PATTERN\.test\(deviceId\)/);
  assert.match(creator, /DEVICE_NONCE_PATTERN\.test\(deviceNonce\)/);
  assert.match(creator, /validDisplayName\(displayName\)/);
  assert.match(creator, /"garmin_create_device_idempotent"/);
  assert.match(creator, /p_request_id: requestId/);
  assert.match(creator, /p_device_id: deviceId/);
  assert.match(creator, /p_device_token: deviceNonce/);
  assert.match(creator, /error\?\.code === "PGRST202"[\s\S]*501/);
  assert.match(creator, /data\?\.status === "conflict"[\s\S]*409/);
  assert.match(creator, /\["created", "already_created"\]\.includes/);
  assert.match(creator, /device\.device_token !== deviceNonce/);
  assert.match(creator, /device\.token_revision !== 1/);
  assert.match(creator, /requestId,[\s\S]*device: \{ \.\.\.device/);
  assert.match(edge.slice(legacyStart), /userClient\.rpc\("garmin_create_device"/);
});

const runPwaCreate = async ({ record, replies }) => {
  let durable = structuredClone(record);
  const calls = [];
  const context = {
    GARMIN_CAPABILITY_VERSION: 2,
    JSON,
    Error,
    loadGarminCreateRequests: () => ({ [record.userId]: structuredClone(durable) }),
    saveGarminCreateRequests: (value) => {
      durable = structuredClone(value[record.userId]);
    },
    userVisibleError: (english) => new Error(english),
    supabaseRequest: async (_path, options) => {
      const body = JSON.parse(options.body);
      calls.push({ body, durable: structuredClone(durable) });
      const reply = replies.shift();
      if (reply instanceof Error || (reply && reply.throw)) {
        throw reply instanceof Error ? reply : reply.throw;
      }
      return reply;
    },
  };
  vm.createContext(context);
  vm.runInContext(functionSource(pwa, "exactGarminCreateFallback"), context);
  vm.runInContext(functionSource(pwa, "requestGarminDeviceCreation"), context);
  try {
    return {
      result: await context.requestGarminDeviceCreation(
        { user: { id: record.userId } },
        structuredClone(record),
      ),
      calls,
      durable,
    };
  } catch (error) {
    return { error, calls, durable };
  }
};

const browserRecord = (overrides = {}) => ({
  version: 1,
  userId: "00000000-0000-4000-8000-000000000001",
  requestId: "10000000-0000-4000-8000-000000000001",
  deviceId: "20000000-0000-4000-8000-000000000001",
  deviceNonce: "a".repeat(64),
  displayName: "Garmin watch",
  createdAt: 1_786_363_200_000,
  legacyFallbackAttempted: false,
  ...overrides,
});

const edgeError = (status, message) =>
  Object.assign(new Error(message), { status });

test("PWA falls back once only for an exact pre-mutation compatibility response", async () => {
  const unsupported = edgeError(
    501,
    JSON.stringify({ error: "Idempotent device creation unavailable" }),
  );
  const legacyResponse = { device: { id: "legacy" } };
  const outcome = await runPwaCreate({
    record: browserRecord(),
    replies: [{ throw: unsupported }, legacyResponse],
  });
  assert.deepEqual(outcome.calls.map((call) => call.body.action), [
    "createDeviceIdempotent",
    "createDevice",
  ]);
  assert.equal(outcome.calls[1].durable.legacyFallbackAttempted, true);
  assert.deepEqual(
    JSON.parse(JSON.stringify(outcome.result)),
    { response: legacyResponse, idempotent: false },
  );
  assert.equal(outcome.durable.legacyFallbackAttempted, true);

  const priorUnknown = await runPwaCreate({
    record: browserRecord({ legacyFallbackAttempted: true }),
    replies: [{ throw: unsupported }],
  });
  assert.equal(priorUnknown.calls.length, 1);
  assert.equal(priorUnknown.error instanceof Error, true);
  assert.match(priorUnknown.error.message, /may already have created/);
});

test("PWA never enters legacy create after a generic or outcome-unknown failure", async () => {
  const generic = edgeError(
    400,
    JSON.stringify({ error: "Unknown action", detail: "not exact" }),
  );
  const rejected = await runPwaCreate({
    record: browserRecord(),
    replies: [{ throw: generic }],
  });
  assert.equal(rejected.calls.length, 1);
  assert.equal(rejected.error, generic);
  assert.equal(rejected.durable.legacyFallbackAttempted, false);

  const unknown = edgeError(500, JSON.stringify({ error: "Temporary" }));
  const laterUnsupported = edgeError(
    501,
    JSON.stringify({ error: "Idempotent device creation unavailable" }),
  );
  const retried = await runPwaCreate({
    record: browserRecord(),
    replies: [{ throw: unknown }, { throw: laterUnsupported }],
  });
  assert.deepEqual(
    retried.calls.map((call) => call.body.action),
    ["createDeviceIdempotent", "createDeviceIdempotent"],
  );
  assert.equal(retried.error, laterUnsupported);
  assert.equal(retried.durable.legacyFallbackAttempted, false);
});

test("PWA and iOS persist bounded owner-bound retry material and clear it after recovery", () => {
  assert.match(pwa, /GARMIN_CREATE_REQUESTS_KEY/);
  assert.match(pwa, /MAX_GARMIN_CREATE_STORAGE_BYTES = 16 \* 1024/);
  assert.match(pwa, /MAX_GARMIN_CREATE_REQUESTS = 4/);
  assert.match(pwa, /GARMIN_CREATE_REQUEST_MAX_AGE_MS = 24 \* 60 \* 60 \* 1000/);
  assert.match(pwa, /value\.userId !== userId/);
  assert.match(pwa, /UUID_V4_PATTERN\.test\(value\.requestId/);
  assert.match(pwa, /legacyFallbackAttempted/);
  assert.match(pwa, /GARMIN_PENDING_REVOCATIONS_KEY/);
  assert.match(pwa, /cleanupKind/);
  assert.match(pwa, /promoteGarminCreateRequestToCleanup/);
  assert.match(pwa, /removeGarminCreateRequestForUser\(userId, creation\.requestId\)/);
  assert.match(pwa, /removeGarminCreateRequestForUser\(userId\)[\s\S]*chooseGarminDeviceForRecovery/);

  assert.match(ios, /pending-creation-v1\./);
  assert.match(ios, /maximumPendingCreationAge: TimeInterval = 24 \* 60 \* 60/);
  assert.match(ios, /canonicalVersion4UUIDString\(value\.requestID\)/);
  assert.match(ios, /isLowercaseHexToken\(value\.deviceToken\)/);
  assert.match(ios, /value\.userID == userID/);
  assert.match(ios, /legacyFallbackAttempted/);
  assert.match(ios, /retryExactDeviceCreation/);
  assert.match(ios, /clearPendingCreation/);
  assert.match(ios, /promotePendingCreationToCleanup/);
  assert.match(ios, /prepareForSessionEnd/);
  assert.match(ios, /legacyRecovery/);
  assert.match(ios, /recognizeUnavailableIdempotentCreation/);
  assert.match(ios, /decodedObject\.count == 1/);
  assert.match(iosTests, /testGarminCreateResumesExactKeychainRequestAfterRestart/);
  assert.match(iosTests, /testGarminCreateLegacyFallbackIsExactOnceAndRecoversLostOutcomeByList/);
  assert.match(iosTests, /testGarminLegacyEmptyOwnerListStartsFreshIdempotentRequestOnly/);
  assert.match(iosTests, /testGarminPendingCreationStoreRejectsMalformedExpiredAndWrongOwnerRecords/);
  assert.match(iosTests, /testGarminExpiredCreationBecomesRevokeOnlyAndRetriesBeforeRefresh/);
  assert.match(iosTests, /testGarminSessionEndStripsRawSecretAndKeepsFailedRevokeDurably/);
  assert.match(iosTests, /testGarminLegacyCleanupListsForExplicitRecoveryWithoutRevokingClientID/);
});

const pwaCleanupHarness = (initial = {}) => {
  const values = new Map(Object.entries(initial));
  const failures = { createDelete: false };
  const storageEvents = [];
  const localStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => {
      storageEvents.push({ operation: "set", key });
      values.set(key, String(value));
    },
    removeItem: (key) => {
      if (failures.createDelete && key === "gym-pwa-garmin-create-requests-v1") {
        throw new Error("synthetic create-record delete failure");
      }
      storageEvents.push({ operation: "remove", key });
      values.delete(key);
    },
  };
  const context = {
    JSON,
    Object,
    Set,
    Error,
    Date,
    TextEncoder,
    localStorage,
    GARMIN_PENDING_REVOCATIONS_KEY: "gym-pwa-garmin-pending-revocations-v1",
    GARMIN_CREATE_REQUESTS_KEY: "gym-pwa-garmin-create-requests-v1",
    MAX_GARMIN_PENDING_REVOCATION_STORAGE_BYTES: 8 * 1024,
    MAX_GARMIN_PENDING_REVOCATIONS: 4,
    MAX_GARMIN_CREATE_STORAGE_BYTES: 16 * 1024,
    MAX_GARMIN_CREATE_REQUESTS: 4,
    GARMIN_CREATE_REQUEST_MAX_AGE_MS: 24 * 60 * 60 * 1000,
    UUID_PATTERN: /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    UUID_V4_PATTERN: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    GARMIN_LEGACY_CAPABILITY_PATTERN: /^[a-f0-9]{64}$/,
    newUuidV4: (() => {
      const values = [
        "30000000-0000-4000-8000-000000000003",
        "40000000-0000-4000-8000-000000000004",
      ];
      return () => values.shift();
    })(),
    newGarminReplacementToken: () => "b".repeat(64),
  };
  vm.createContext(context);
  for (const name of [
    "validGarminDisplayName",
    "loadGarminPendingRevocations",
    "saveGarminPendingRevocations",
    "pendingGarminRevocationForUser",
    "rememberGarminPendingRevocation",
    "forgetGarminPendingRevocation",
    "saveGarminCreateRequests",
    "loadGarminCreateRequests",
    "removeGarminCreateRequestForUser",
    "removeGarminCreateRequestMatchingCleanup",
    "promoteGarminCreateRequestToCleanup",
    "prepareGarminCreateRequest",
  ]) {
    vm.runInContext(functionSource(pwa, name), context);
  }
  return { context, values, failures, storageEvents };
};

test("PWA expiry and logout promotion strip raw nonce only after durable cleanup", () => {
  const record = browserRecord({ createdAt: Date.now() - 24 * 60 * 60 * 1000 - 1 });
  const createKey = "gym-pwa-garmin-create-requests-v1";
  const cleanupKey = "gym-pwa-garmin-pending-revocations-v1";
  const expiredHarness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [record.userId]: record }),
  });
  const loaded = expiredHarness.context.loadGarminCreateRequests();
  assert.equal(Object.keys(loaded).length, 0);
  assert.equal(expiredHarness.values.has(createKey), false);
  const expiredCleanup = JSON.parse(expiredHarness.values.get(cleanupKey));
  assert.deepEqual(expiredCleanup[record.userId], {
    version: 1,
    userId: record.userId,
    deviceId: record.deviceId,
    cleanupKind: "revoke",
    createdAt: expiredCleanup[record.userId].createdAt,
    creationRequestId: record.requestId,
  });
  assert.doesNotMatch(expiredHarness.values.get(cleanupKey), /deviceNonce|a{64}/);

  const malformed = browserRecord({ userId: record.userId, deviceId: "not-a-uuid" });
  const malformedHarness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [record.userId]: malformed }),
  });
  assert.throws(
    () => malformedHarness.context.loadGarminCreateRequests(),
    /invalid/,
  );
  assert.equal(malformedHarness.values.has(createKey), false);
  assert.equal(malformedHarness.values.has(cleanupKey), false);
});

test("PWA partial storage failure retains marker until exact raw scrub succeeds", () => {
  const record = browserRecord({ createdAt: Date.now() });
  const createKey = "gym-pwa-garmin-create-requests-v1";
  const cleanupKey = "gym-pwa-garmin-pending-revocations-v1";
  const harness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [record.userId]: record }),
  });
  harness.failures.createDelete = true;
  assert.throws(
    () => harness.context.promoteGarminCreateRequestToCleanup(record.userId),
    /synthetic create-record delete failure/,
  );
  assert.equal(harness.values.has(createKey), true, "raw retry remains after failed scrub");
  assert.equal(harness.values.has(cleanupKey), true, "cleanup marker must already be durable");

  const cleanup = harness.context.pendingGarminRevocationForUser(record.userId);
  assert.equal(cleanup.creationRequestId, record.requestId);
  harness.failures.createDelete = false;
  harness.context.removeGarminCreateRequestMatchingCleanup(
    record.userId,
    cleanup.deviceId,
    cleanup.cleanupKind,
    cleanup.creationRequestId,
  );
  assert.equal(harness.values.has(createKey), false);
  assert.equal(harness.values.has(cleanupKey), true, "marker gates replay until raw is gone");
  harness.context.forgetGarminPendingRevocation(record.userId, cleanup.deviceId);
  assert.equal(harness.values.has(cleanupKey), false);

  const ensureBinding = functionSource(pwa, "ensureGarminDeviceBinding");
  const absence = sliceBetween(
    ensureBinding,
    "if (!pendingDevice)",
    "const retryWarning",
  );
  assert.ok(
    absence.indexOf("removeGarminCreateRequestMatchingCleanup") <
      absence.indexOf("forgetGarminPendingRevocation") &&
      absence.indexOf("forgetGarminPendingRevocation") <
      absence.indexOf("removeGarminBinding"),
    "recoveryPending authoritative absence must scrub raw, then marker, then binding",
  );
});

test("PWA pending cleanup accepts only exact legacy or request-correlated record shapes", () => {
  const record = browserRecord({ createdAt: Date.now() });
  const cleanupKey = "gym-pwa-garmin-pending-revocations-v1";
  const legacy = {
    version: 1,
    userId: record.userId,
    deviceId: record.deviceId,
    cleanupKind: "revoke",
    createdAt: Date.now(),
  };
  const legacyHarness = pwaCleanupHarness({
    [cleanupKey]: JSON.stringify({ [record.userId]: legacy }),
  });
  assert.deepEqual(
    JSON.parse(JSON.stringify(
      legacyHarness.context.pendingGarminRevocationForUser(record.userId),
    )),
    legacy,
  );

  const correlated = { ...legacy, creationRequestId: record.requestId.toUpperCase() };
  const correlatedHarness = pwaCleanupHarness({
    [cleanupKey]: JSON.stringify({ [record.userId]: correlated }),
  });
  assert.equal(
    correlatedHarness.context.pendingGarminRevocationForUser(record.userId)
      .creationRequestId,
    record.requestId,
  );

  for (const malformed of [
    { ...legacy, creationRequestId: "not-a-uuid" },
    { ...legacy, unexpected: true },
    { ...correlated, unexpected: true },
  ]) {
    const malformedHarness = pwaCleanupHarness({
      [cleanupKey]: JSON.stringify({ [record.userId]: malformed }),
    });
    assert.throws(
      () => malformedHarness.context.loadGarminPendingRevocations(),
      /invalid/,
    );
  }
});

test("PWA legacy response correlates server cleanup to raw request across delete failure and restart", async () => {
  const record = browserRecord({ createdAt: Date.now() });
  const serverDeviceId = "90000000-0000-4000-8000-000000000009";
  const createKey = "gym-pwa-garmin-create-requests-v1";
  const cleanupKey = "gym-pwa-garmin-pending-revocations-v1";
  const harness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [record.userId]: record }),
  });
  const { context } = harness;
  const session = { user: { id: record.userId } };
  let currentBinding = null;
  const revokedDeviceIds = [];
  const lifecycleEvents = [];
  Object.assign(context, {
    GARMIN_CAPABILITY_VERSION: 2,
    activeAccount: { userId: record.userId },
    accountEpoch: 7,
    loadRemoteSession: () => session,
    garminBindingForUser: () => currentBinding,
    removeGarminBinding: () => {
      lifecycleEvents.push("binding-removed");
      currentBinding = null;
    },
    listGarminDevices: async () => [],
    chooseGarminDeviceForRecovery: () => null,
    recoverGarminDeviceBinding: async () => {
      throw new Error("unexpected recovery");
    },
    normalizedGarminDevice: (device) => ({
      id: device.id,
      tokenRevision: 1,
      displayName: record.displayName,
      deviceToken: "legacy-response-token",
    }),
    saveGarminBinding: (binding) => {
      lifecycleEvents.push("binding-saved");
      currentBinding = structuredClone(binding);
    },
    tx: (english) => english,
    userVisibleError: (english) => new Error(english),
    window: { confirm: () => true, prompt: () => "confirmed" },
    requestGarminDeviceCreation: async (_session, creation) => {
      const requests = context.loadGarminCreateRequests();
      requests[record.userId] = {
        ...requests[record.userId],
        legacyFallbackAttempted: true,
      };
      context.saveGarminCreateRequests(requests);
      return {
        response: {
          device: {
            id: serverDeviceId,
            device_token: "legacy-response-token",
          },
        },
        idempotent: false,
      };
    },
    supabaseRequest: async (_path, options) => {
      const body = JSON.parse(options.body);
      revokedDeviceIds.push(body.deviceId);
      return { status: "already_revoked" };
    },
  });
  vm.runInContext(functionSource(pwa, "revokeGarminDeviceById"), context);
  vm.runInContext(functionSource(pwa, "ensureGarminDeviceBinding"), context);

  harness.failures.createDelete = true;
  await assert.rejects(
    context.ensureGarminDeviceBinding(session),
    /synthetic create-record delete failure/,
  );
  assert.deepEqual(revokedDeviceIds, [serverDeviceId]);
  assert.equal(currentBinding.deviceId, serverDeviceId);
  assert.equal(currentBinding.recoveryPending, true);
  const retainedRaw = JSON.parse(harness.values.get(createKey))[record.userId];
  assert.equal(retainedRaw.deviceId, record.deviceId);
  assert.equal(retainedRaw.legacyFallbackAttempted, true);
  const retainedMarker = JSON.parse(harness.values.get(cleanupKey))[record.userId];
  assert.equal(retainedMarker.deviceId, serverDeviceId);
  assert.equal(retainedMarker.cleanupKind, "revoke");
  assert.equal(retainedMarker.creationRequestId, record.requestId);

  harness.failures.createDelete = false;
  harness.storageEvents.length = 0;
  lifecycleEvents.length = 0;
  await assert.rejects(
    context.ensureGarminDeviceBinding(session),
    /no longer active/,
  );
  assert.deepEqual(revokedDeviceIds, [serverDeviceId, serverDeviceId]);
  assert.equal(harness.values.has(createKey), false);
  assert.equal(harness.values.has(cleanupKey), false);
  assert.equal(currentBinding, null);
  const rawRemovedAt = harness.storageEvents.findIndex(
    event => event.operation === "remove" && event.key === createKey,
  );
  const markerRemovedAt = harness.storageEvents.findIndex(
    event => event.operation === "remove" && event.key === cleanupKey,
  );
  assert.ok(rawRemovedAt >= 0 && markerRemovedAt > rawRemovedAt);
  assert.deepEqual(lifecycleEvents, ["binding-removed"]);
});

test("PWA request-correlated scrub rejects the wrong request while old markers remain compatible", () => {
  const record = browserRecord({
    createdAt: Date.now(),
    legacyFallbackAttempted: true,
  });
  const createKey = "gym-pwa-garmin-create-requests-v1";
  const cleanupKey = "gym-pwa-garmin-pending-revocations-v1";
  const serverDeviceId = "90000000-0000-4000-8000-000000000009";
  const wrongRequestId = "80000000-0000-4000-8000-000000000008";
  const correlatedHarness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [record.userId]: record }),
  });
  correlatedHarness.context.rememberGarminPendingRevocation(
    record.userId,
    serverDeviceId,
    "revoke",
    record.requestId,
  );
  assert.throws(
    () => correlatedHarness.context.removeGarminCreateRequestMatchingCleanup(
      record.userId,
      serverDeviceId,
      "revoke",
      wrongRequestId,
    ),
    /does not match the pending creation request/,
  );
  assert.equal(correlatedHarness.values.has(createKey), true);
  assert.equal(correlatedHarness.values.has(cleanupKey), true);
  correlatedHarness.context.removeGarminCreateRequestMatchingCleanup(
    record.userId,
    serverDeviceId,
    "revoke",
    record.requestId,
  );
  assert.equal(correlatedHarness.values.has(createKey), false);

  const oldMarkerRecord = browserRecord({
    createdAt: Date.now(),
    legacyFallbackAttempted: false,
  });
  const oldMarker = {
    version: 1,
    userId: oldMarkerRecord.userId,
    deviceId: oldMarkerRecord.deviceId,
    cleanupKind: "revoke",
    createdAt: Date.now(),
  };
  const oldHarness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [oldMarkerRecord.userId]: oldMarkerRecord }),
    [cleanupKey]: JSON.stringify({ [oldMarkerRecord.userId]: oldMarker }),
  });
  const loadedOld = oldHarness.context.pendingGarminRevocationForUser(
    oldMarkerRecord.userId,
  );
  assert.equal(loadedOld.creationRequestId, undefined);
  oldHarness.context.removeGarminCreateRequestMatchingCleanup(
    oldMarkerRecord.userId,
    loadedOld.deviceId,
    loadedOld.cleanupKind,
    loadedOld.creationRequestId ?? null,
  );
  assert.equal(oldHarness.values.has(createKey), false);
  assert.equal(oldHarness.values.has(cleanupKey), true);
});

test("PWA authoritative empty list discards only spent legacy retry before fresh create", () => {
  const record = browserRecord({
    createdAt: Date.now(),
    legacyFallbackAttempted: true,
  });
  const createKey = "gym-pwa-garmin-create-requests-v1";
  const harness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [record.userId]: record }),
  });
  const ensureBinding = functionSource(pwa, "ensureGarminDeviceBinding");
  const emptyListBranch = sliceBetween(
    ensureBinding,
    "const pendingCreationAfterEmptyList",
    "const pairingWarning",
  );
  assert.match(emptyListBranch, /pendingCreationAfterEmptyList\?\.legacyFallbackAttempted/);
  assert.match(
    emptyListBranch,
    /removeGarminCreateRequestMatchingCleanup\([\s\S]*"legacy-recovery"/,
  );

  harness.context.removeGarminCreateRequestMatchingCleanup(
    record.userId,
    record.deviceId,
    "legacy-recovery",
  );
  const fresh = harness.context.prepareGarminCreateRequest(record.userId, record.displayName);
  assert.notEqual(fresh.requestId, record.requestId);
  assert.notEqual(fresh.deviceId, record.deviceId);
  assert.equal(fresh.legacyFallbackAttempted, false);

  const nonLegacy = browserRecord({ createdAt: Date.now(), legacyFallbackAttempted: false });
  const retainedHarness = pwaCleanupHarness({
    [createKey]: JSON.stringify({ [nonLegacy.userId]: nonLegacy }),
  });
  assert.equal(
    retainedHarness.context.prepareGarminCreateRequest(
      nonLegacy.userId,
      nonLegacy.displayName,
    ).requestId,
    nonLegacy.requestId,
    "non-legacy idempotent retry material must survive an empty list",
  );
});

test("PWA and iOS logout hooks scrub Garmin retry secrets before auth teardown", () => {
  const logout = functionSource(pwa, "logoutAccount");
  assert.ok(
    logout.indexOf("promoteGarminCreateRequestToCleanup") <
      logout.indexOf("clearRemoteSession"),
  );
  assert.match(logout, /cleanupKind === "legacy-recovery"/);
  const signOut = sliceBetween(
    iosAppState,
    "func signOut() async -> Bool",
    "private func scheduleActivation",
  );
  assert.ok(
    signOut.indexOf("garminCloud.prepareForSessionEnd") <
      signOut.indexOf("auth.signOut()"),
  );
});

class IdempotentCreatorModel {
  constructor() {
    this.rowsByRequest = new Map();
    this.locks = new Map();
  }

  async create(owner, session, request) {
    const previous = this.locks.get(request.requestId) || Promise.resolve();
    let unlock;
    const current = new Promise((resolve) => { unlock = resolve; });
    this.locks.set(request.requestId, previous.then(() => current));
    await previous;
    try {
      if (!session?.current || session.owner !== owner) return { error: "Unauthorized" };
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(request.requestId) ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(request.deviceId) ||
          !/^[a-f0-9]{64}$/.test(request.token) ||
          typeof request.displayName !== "string" || request.displayName.length < 1 ||
          request.displayName.length > 80) return { error: "Invalid" };
      const existing = this.rowsByRequest.get(request.requestId);
      if (existing) {
        if (existing.owner === owner && existing.deviceId === request.deviceId &&
            existing.token === request.token && existing.displayName === request.displayName &&
            !existing.revoked && existing.revision === 1) {
          return { status: "already_created", device: structuredClone(existing) };
        }
        return { status: "conflict" };
      }
      const row = {
        owner,
        deviceId: request.deviceId,
        token: request.token,
        displayName: request.displayName,
        revision: 1,
        revoked: false,
      };
      this.rowsByRequest.set(request.requestId, row);
      return { status: "created", device: structuredClone(row) };
    } finally {
      unlock();
    }
  }
}

test("deterministic model covers duplicate/concurrent, wrong-owner, expired, malformed, and revoked replay", async () => {
  const creator = new IdempotentCreatorModel();
  const owner = "owner-a";
  const other = "owner-b";
  const request = {
    requestId: "10000000-0000-4000-8000-000000000001",
    deviceId: "20000000-0000-4000-8000-000000000001",
    token: "a".repeat(64),
    displayName: "Watch",
  };
  const current = { current: true, owner };

  assert.deepEqual(await creator.create(owner, null, request), { error: "Unauthorized" });
  assert.deepEqual(
    await creator.create(owner, { current: false, owner }, request),
    { error: "Unauthorized" },
  );
  assert.equal(creator.rowsByRequest.size, 0);
  assert.deepEqual(
    await creator.create(owner, current, { ...request, token: "BAD" }),
    { error: "Invalid" },
  );
  assert.equal(creator.rowsByRequest.size, 0);

  const concurrent = await Promise.all([
    creator.create(owner, current, request),
    creator.create(owner, current, request),
  ]);
  assert.deepEqual(concurrent.map((value) => value.status), ["created", "already_created"]);
  assert.deepEqual(concurrent[0].device, concurrent[1].device);
  assert.equal(creator.rowsByRequest.size, 1);

  assert.deepEqual(
    await creator.create(other, { current: true, owner: other }, request),
    { status: "conflict" },
  );
  assert.deepEqual(
    await creator.create(owner, current, { ...request, displayName: "Changed" }),
    { status: "conflict" },
  );
  assert.equal(creator.rowsByRequest.size, 1);

  creator.rowsByRequest.get(request.requestId).revoked = true;
  assert.deepEqual(
    await creator.create(owner, current, request),
    { status: "conflict" },
  );
  assert.equal(creator.rowsByRequest.get(request.requestId).revoked, true);
  assert.equal(creator.rowsByRequest.size, 1);
});
