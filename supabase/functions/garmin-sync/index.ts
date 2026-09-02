import { createClient } from "@supabase/supabase-js";
import {
  createGarminCapability,
  deriveGarminAccountBinding,
  verifyGarminCapability,
} from "../_shared/garmin-capability.ts";
import { validateGarminPlan } from "../_shared/garmin-plan-contract.ts";
import { scheduleBestEffortGarminTelemetry } from "../_shared/garmin-telemetry.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Expose-Headers": "X-GymApp-Garmin-Capability-Version",
};

const responseSecurityHeaders = {
  "Cache-Control": "no-store",
  "Pragma": "no-cache",
  "X-Content-Type-Options": "nosniff",
};

const REQUEST_BODY_BYTES = 8 * 1024;
const REQUEST_BODY_CHUNKS = 128;
const MAX_PLAN_REVISION = 2_147_483_647;
const MAX_TOKEN_REVISION = 2_147_483_647;
const MAX_EXPECTED_TOKEN_REVISION = MAX_TOKEN_REVISION - 1;
const DEVICE_NONCE_PATTERN = /^[a-f0-9]{64}$/;
const CAPABILITY_HMAC_SECRET_PATTERN = /^[a-f0-9]{64}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UUID_V4_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
// Control characters are intentionally rejected from user-visible device names.
// deno-lint-ignore no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f]/;
const RFC3339_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

type RequestBody = {
  action?: unknown;
  capabilityVersion?: unknown;
  deviceToken?: unknown;
  deviceId?: unknown;
  replacementNonce?: unknown;
  expectedTokenRevision?: unknown;
  requestId?: unknown;
  deviceNonce?: unknown;
  displayName?: unknown;
  planId?: unknown;
  planRevision?: unknown;
};

type GarminCapabilityContext = {
  version: 3;
  nonce: string;
  accountBinding?: string;
  deviceId?: string;
};

function json(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...responseSecurityHeaders,
      ...extraHeaders,
    },
  });
}

function rateLimitedResponse(
  value: unknown,
  extraHeaders: Record<string, string> = {},
): Response | null {
  if (!isObject(value) || value.status !== "rate_limited") return null;
  if (
    !Number.isInteger(value.retryAfter) || Number(value.retryAfter) < 1 ||
    Number(value.retryAfter) > 3600
  ) {
    return json({ error: "Invalid rate-limit response" }, 500, extraHeaders);
  }
  const retryAfter = Number(value.retryAfter);
  return json(
    { error: "Rate limit exceeded", retryAfter },
    429,
    { "Retry-After": String(retryAfter), ...extraHeaders },
  );
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function requestedCapabilityVersion(value: unknown): 2 | 3 | null {
  // Missing or explicit v2 identifies a retired client and is rejected before
  // authentication or database access. Only signed v3 pairing can proceed.
  if (value === undefined || value === 2) return 2;
  if (value === 3) return 3;
  return null;
}

function capabilityVersionHeaders(version: 2 | 3): Record<string, string> {
  return { "X-GymApp-Garmin-Capability-Version": String(version) };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validDisplayName(value: unknown): value is string {
  return typeof value === "string" && value === value.trim() &&
    value.length > 0 &&
    value.length <= 80 && !CONTROL_CHARACTER_PATTERN.test(value) &&
    new TextEncoder().encode(value).byteLength <= 320;
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && value.length <= 40 &&
    RFC3339_PATTERN.test(value) && Number.isFinite(Date.parse(value));
}

type SafeDevice = {
  id: string;
  display_name: string;
  created_at: string;
  last_seen_at: string | null;
  binding_version: 2;
  token_revision: number;
  device_token?: string;
};

function safeDevice(
  value: unknown,
  options: { requireToken?: boolean; expectedId?: string } = {},
): SafeDevice | null {
  if (
    !isObject(value) || typeof value.id !== "string" ||
    !UUID_PATTERN.test(value.id) || !validDisplayName(value.display_name) ||
    !validTimestamp(value.created_at) || value.binding_version !== 2 ||
    !Number.isInteger(value.token_revision) ||
    Number(value.token_revision) < 1 ||
    Number(value.token_revision) > MAX_TOKEN_REVISION
  ) {
    return null;
  }

  const id = value.id.toLowerCase();
  if (options.expectedId && id !== options.expectedId) return null;
  const lastSeenAt = value.last_seen_at === undefined
    ? null
    : value.last_seen_at;
  if (lastSeenAt !== null && !validTimestamp(lastSeenAt)) return null;
  if (!options.requireToken && "device_token" in value) return null;
  if (
    options.requireToken &&
    (typeof value.device_token !== "string" ||
      !DEVICE_NONCE_PATTERN.test(value.device_token))
  ) {
    return null;
  }

  return {
    id,
    display_name: value.display_name,
    created_at: value.created_at,
    last_seen_at: lastSeenAt,
    binding_version: 2,
    token_revision: Number(value.token_revision),
    ...(options.requireToken
      ? { device_token: value.device_token as string }
      : {}),
  };
}

async function readBody(request: Request): Promise<RequestBody | null> {
  const declaredLength = request.headers.get("content-length");
  if (
    declaredLength !== null && /^\d+$/.test(declaredLength.trim()) &&
    Number(declaredLength) > REQUEST_BODY_BYTES
  ) {
    return null;
  }
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteLength += value.byteLength;
      if (
        byteLength > REQUEST_BODY_BYTES ||
        chunks.length >= REQUEST_BODY_CHUNKS
      ) {
        await reader.cancel().catch(() => undefined);
        return null;
      }
      chunks.push(value);
    }
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
  const encoded = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    encoded.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const raw = new TextDecoder("utf-8", { fatal: true }).decode(encoded);
    const parsed = JSON.parse(raw);
    return isObject(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function authenticatedClient(
  request: Request,
  supabaseUrl: string,
  anonKey: string,
) {
  const authHeader = request.headers.get("Authorization") || "";
  if (!/^Bearer [^\s]{16,4096}$/.test(authHeader)) return null;
  return createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function capabilityClient(
  supabaseUrl: string,
  databaseSecretKey: string,
) {
  return createClient(supabaseUrl, databaseSecretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function capabilityRpc(
  supabaseUrl: string,
  databaseSecretKey: string,
  anonKey: string,
  functionName: string,
  args: Record<string, unknown>,
) {
  const primary = await capabilityClient(supabaseUrl, databaseSecretKey).rpc(
    functionName,
    args,
  );
  if (!primary.error || primary.error.code !== "42501") return primary;

  // Deployment compatibility only: before the ACL migration, the established
  // wrapper is anon-only. This fallback is reachable only after an HMAC-valid
  // v3 envelope and disappears when that migration revokes anon execution.
  const transitionalClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return transitionalClient.rpc(functionName, args);
}

async function resolveGarminCapability(
  value: unknown,
  hmacSecret: string,
): Promise<GarminCapabilityContext | null> {
  const signed = await verifyGarminCapability(value, hmacSecret);
  if (signed) {
    return {
      version: 3,
      nonce: signed.nonce,
      accountBinding: signed.accountBinding,
      deviceId: signed.deviceId,
    };
  }
  return null;
}

function scheduleCapabilityUse(
  supabaseUrl: string,
  databaseSecretKey: string,
  capability: GarminCapabilityContext,
): void {
  // The telemetry RPC is deployed by the ACL migration after this Edge bundle.
  // It is operational evidence for retirement, never an authorization input.
  scheduleBestEffortGarminTelemetry(
    () =>
      capabilityClient(supabaseUrl, databaseSecretKey).rpc(
        "garmin_record_capability_use",
        {
          p_device_token: capability.nonce,
          p_capability_version: capability.version,
        },
      ),
    (task) => {
      const runtime = (globalThis as typeof globalThis & {
        EdgeRuntime?: { waitUntil(value: Promise<unknown>): void };
      }).EdgeRuntime;
      if (!runtime) throw new Error("Edge background scheduler unavailable");
      runtime.waitUntil(task);
    },
  );
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: { ...corsHeaders, ...responseSecurityHeaders },
    });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let supabaseUrl: string;
  let anonKey: string;
  let databaseSecretKey: string;
  let capabilityHmacSecret: string;
  try {
    supabaseUrl = requiredEnv("SUPABASE_URL");
    anonKey = requiredEnv("SUPABASE_ANON_KEY");
    databaseSecretKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    capabilityHmacSecret = requiredEnv("GARMIN_CAPABILITY_HMAC_SECRET");
    if (!CAPABILITY_HMAC_SECRET_PATTERN.test(capabilityHmacSecret)) {
      throw new Error("Invalid Garmin capability configuration");
    }
  } catch {
    return json({ error: "Server configuration error" }, 500);
  }

  const body = await readBody(request);
  if (!body) return json({ error: "Invalid or oversized request body" }, 400);

  if (body.action === "createDeviceIdempotent") {
    const capabilityVersion = requestedCapabilityVersion(
      body.capabilityVersion,
    );
    if (!capabilityVersion) {
      return json({ error: "Unsupported Garmin capability version" }, 400);
    }
    if (capabilityVersion === 2) {
      return json({ error: "Garmin client upgrade required" }, 426);
    }
    const userClient = authenticatedClient(request, supabaseUrl, anonKey);
    if (!userClient) return json({ error: "Unauthorized" }, 401);
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
    }
    if (!await deriveGarminAccountBinding(userData.user.id)) {
      return json({ error: "Invalid account identity" }, 500);
    }

    const requestId = typeof body.requestId === "string"
      ? body.requestId.trim().toLowerCase()
      : "";
    const deviceId = typeof body.deviceId === "string"
      ? body.deviceId.trim().toLowerCase()
      : "";
    const deviceNonce = typeof body.deviceNonce === "string"
      ? body.deviceNonce
      : "";
    const displayName = typeof body.displayName === "string"
      ? body.displayName.trim()
      : "Garmin watch";
    if (
      !UUID_V4_PATTERN.test(requestId) ||
      !UUID_V4_PATTERN.test(deviceId) ||
      !DEVICE_NONCE_PATTERN.test(deviceNonce) ||
      !validDisplayName(displayName)
    ) {
      return json({ error: "Invalid device creation request" }, 400);
    }

    const { data, error } = await userClient.rpc(
      "garmin_create_device_idempotent",
      {
        p_request_id: requestId,
        p_device_id: deviceId,
        p_device_token: deviceNonce,
        p_display_name: displayName,
      },
    );
    if (error?.code === "PGRST202") {
      // Safe mixed-version rollout: this action has not called the legacy
      // creator, so a new client may explicitly fall back exactly once.
      return json({ error: "Idempotent device creation unavailable" }, 501);
    }
    if (data?.error === "Device creation limit reached") {
      return json({ error: data.error }, 429);
    }
    if (data?.error === "Unauthorized") {
      return json({ error: data.error }, 401);
    }
    if (
      data?.error === "Invalid device creation request" ||
      data?.error === "Invalid display name"
    ) {
      return json({ error: data.error }, 400);
    }
    if (data?.status === "conflict") {
      return json({ error: "Device creation conflict" }, 409);
    }
    const device = safeDevice(data?.device, {
      requireToken: true,
      expectedId: deviceId,
    });
    if (
      error || data?.error || !device ||
      !["created", "already_created"].includes(data?.status) ||
      device.device_token !== deviceNonce || device.token_revision !== 1
    ) {
      return json({ error: "Device creation failed" }, 500);
    }
    const deviceToken = await createGarminCapability({
      userId: userData.user.id,
      deviceId: device.id,
      nonce: device.device_token,
      secretHex: capabilityHmacSecret,
    });
    if (!deviceToken) {
      // The retry key still owns the row. Do not revoke an exact replay or
      // create an outcome-dependent second identity; the caller can retry.
      return json({ error: "Device capability creation failed" }, 500);
    }
    return json(
      {
        status: data.status,
        requestId,
        device: { ...device, device_token: deviceToken },
        capabilityVersion,
      },
      200,
      capabilityVersionHeaders(capabilityVersion),
    );
  }

  if (body.action === "createDevice") {
    const capabilityVersion = requestedCapabilityVersion(
      body.capabilityVersion,
    );
    if (!capabilityVersion) {
      return json({ error: "Unsupported Garmin capability version" }, 400);
    }
    if (capabilityVersion === 2) {
      return json({ error: "Garmin client upgrade required" }, 426);
    }
    const userClient = authenticatedClient(request, supabaseUrl, anonKey);
    if (!userClient) return json({ error: "Unauthorized" }, 401);
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
    }
    if (!await deriveGarminAccountBinding(userData.user.id)) {
      return json({ error: "Invalid account identity" }, 500);
    }
    const displayName = typeof body.displayName === "string"
      ? body.displayName.trim()
      : "Garmin watch";
    if (!validDisplayName(displayName)) {
      return json({ error: "Invalid displayName" }, 400);
    }

    const { data, error } = await userClient.rpc("garmin_create_device", {
      p_display_name: displayName,
    });

    if (data?.error === "Device creation limit reached") {
      return json({ error: data.error }, 429);
    }
    if (data?.error === "Unauthorized") {
      return json({ error: data.error }, 401);
    }
    if (data?.error === "Invalid display name") {
      return json({ error: data.error }, 400);
    }
    const device = safeDevice(data?.device, { requireToken: true });
    if (error || data?.error || !device) {
      return json({ error: "Device creation failed" }, 500);
    }
    const deviceToken = await createGarminCapability({
      userId: userData.user.id,
      deviceId: device.id,
      nonce: device.device_token,
      secretHex: capabilityHmacSecret,
    });
    if (!deviceToken) {
      await userClient.rpc("garmin_revoke_device", { p_device_id: device.id });
      return json({ error: "Device capability creation failed" }, 500);
    }
    return json(
      {
        device: { ...device, device_token: deviceToken },
        capabilityVersion,
      },
      200,
      capabilityVersionHeaders(capabilityVersion),
    );
  }

  if (body.action === "listDevices") {
    const userClient = authenticatedClient(request, supabaseUrl, anonKey);
    if (!userClient) return json({ error: "Unauthorized" }, 401);
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
    }
    const { data, error } = await userClient.rpc("garmin_list_devices");
    if (isObject(data) && data.error === "Unauthorized") {
      return json({ error: data.error }, 401);
    }
    if (
      error || !isObject(data) || !Array.isArray(data.devices) ||
      data.devices.length > 5
    ) {
      return json({ error: "Device list failed" }, 500);
    }
    const devices = data.devices.map((device: unknown) => safeDevice(device));
    if (
      devices.some((device) => device === null) ||
      new Set(devices.map((device) => device?.id)).size !== devices.length
    ) {
      return json({ error: "Device list failed" }, 500);
    }
    return json({ devices });
  }

  if (body.action === "rotateDeviceToken") {
    const capabilityVersion = requestedCapabilityVersion(
      body.capabilityVersion,
    );
    if (!capabilityVersion) {
      return json({ error: "Unsupported Garmin capability version" }, 400);
    }
    if (capabilityVersion === 2) {
      return json({ error: "Garmin client upgrade required" }, 426);
    }
    const userClient = authenticatedClient(request, supabaseUrl, anonKey);
    if (!userClient) return json({ error: "Unauthorized" }, 401);
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
    }
    const deviceId = typeof body.deviceId === "string"
      ? body.deviceId.trim().toLowerCase()
      : "";
    const replacementNonce = typeof body.replacementNonce === "string"
      ? body.replacementNonce
      : "";
    const expectedTokenRevision = body.expectedTokenRevision;
    if (
      !UUID_PATTERN.test(deviceId) ||
      !DEVICE_NONCE_PATTERN.test(replacementNonce) ||
      !Number.isInteger(expectedTokenRevision) ||
      Number(expectedTokenRevision) < 1 ||
      Number(expectedTokenRevision) > MAX_EXPECTED_TOKEN_REVISION
    ) {
      return json({ error: "Invalid token rotation request" }, 400);
    }
    const { data, error } = await userClient.rpc(
      "garmin_rotate_device_token",
      {
        p_device_id: deviceId,
        p_replacement_token: replacementNonce,
        p_expected_token_revision: expectedTokenRevision,
      },
    );
    if (error) return json({ error: "Device token rotation failed" }, 500);
    const rateLimited = rateLimitedResponse(data);
    if (rateLimited) return rateLimited;
    if (isObject(data) && data.error === "Unauthorized") {
      return json({ error: data.error }, 401);
    }
    if (
      isObject(data) &&
      ["Invalid rotation request", "Replacement token unchanged"].includes(
        String(data.error),
      )
    ) {
      return json({ error: data.error }, 400);
    }
    if (isObject(data) && data.error === "Device not found") {
      return json({ error: data.error }, 403);
    }
    if (isObject(data) && data.status === "conflict") {
      if (
        !Number.isInteger(data.tokenRevision) ||
        Number(data.tokenRevision) < 1 ||
        Number(data.tokenRevision) > MAX_TOKEN_REVISION
      ) {
        return json({ error: "Invalid token rotation response" }, 500);
      }
      return json({
        error: "Device token rotation conflict",
        status: "conflict",
        tokenRevision: data.tokenRevision,
      }, 409);
    }
    if (
      !isObject(data) ||
      !["rotated", "already_rotated"].includes(String(data.status))
    ) {
      return json({ error: "Invalid token rotation response" }, 500);
    }
    const device = safeDevice(data.device, { expectedId: deviceId });
    if (
      !device || device.token_revision !== Number(expectedTokenRevision) + 1
    ) {
      return json({ error: "Invalid token rotation response" }, 500);
    }
    const deviceToken = await createGarminCapability({
      userId: userData.user.id,
      deviceId: device.id,
      nonce: replacementNonce,
      secretHex: capabilityHmacSecret,
    });
    if (!deviceToken) {
      return json({ error: "Device capability rotation failed" }, 500);
    }
    return json(
      {
        status: data.status,
        device: { ...device, device_token: deviceToken },
        capabilityVersion,
      },
      200,
      capabilityVersionHeaders(capabilityVersion),
    );
  }

  if (body.action === "revokeDevice") {
    const userClient = authenticatedClient(request, supabaseUrl, anonKey);
    if (!userClient) return json({ error: "Unauthorized" }, 401);
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
    }
    const deviceId = typeof body.deviceId === "string"
      ? body.deviceId.trim().toLowerCase()
      : "";
    if (!UUID_PATTERN.test(deviceId)) {
      return json({ error: "Invalid deviceId" }, 400);
    }
    const { data, error } = await userClient.rpc("garmin_revoke_device", {
      p_device_id: deviceId,
    });
    if (error) return json({ error: "Device revocation failed" }, 500);
    if (data?.error === "Unauthorized") {
      return json({ error: data.error }, 401);
    }
    if (data?.error) return json({ error: data.error }, 403);
    return json(data || { status: "revoked" });
  }

  if (body.action === "fetchPlan") {
    const deviceToken = typeof body.deviceToken === "string"
      ? body.deviceToken
      : "";
    if (DEVICE_NONCE_PATTERN.test(deviceToken)) {
      return json(
        { error: "Garmin client upgrade required" },
        426,
        capabilityVersionHeaders(2),
      );
    }
    const capability = await resolveGarminCapability(
      deviceToken,
      capabilityHmacSecret,
    );
    if (!capability) {
      return json({ error: "Invalid deviceToken" }, 400);
    }

    const { data: candidate, error: fetchError } = await capabilityRpc(
      supabaseUrl,
      databaseSecretKey,
      anonKey,
      "garmin_fetch_pending_plan",
      {
        p_device_token: capability.nonce,
      },
    );
    if (fetchError) return json({ error: "Plan fetch failed" }, 500);
    const versionHeaders = capabilityVersionHeaders(capability.version);
    if (candidate?.error !== "Invalid device") {
      scheduleCapabilityUse(
        supabaseUrl,
        databaseSecretKey,
        capability,
      );
    }
    const rateLimited = rateLimitedResponse(candidate, versionHeaders);
    if (rateLimited) return rateLimited;
    if (candidate?.error) {
      return json({ error: candidate.error }, 401, versionHeaders);
    }
    if (!candidate || candidate.status === "empty") {
      return json(
        { status: "empty", capabilityVersion: capability.version },
        200,
        versionHeaders,
      );
    }
    if (candidate.status === "invalid") {
      return json(
        {
          error: "Pending plan was quarantined",
          planId: candidate.planId,
          capabilityVersion: capability.version,
        },
        422,
        versionHeaders,
      );
    }
    if (
      candidate.status !== "candidate" ||
      typeof candidate.planId !== "string" ||
      !UUID_PATTERN.test(candidate.planId) ||
      candidate.bindingVersion !== 2 ||
      typeof candidate.accountBinding !== "string" ||
      !/^[a-f0-9]{64}$/.test(candidate.accountBinding) ||
      typeof candidate.deviceBinding !== "string" ||
      !UUID_PATTERN.test(candidate.deviceBinding) ||
      (capability.version === 3 &&
        (candidate.accountBinding !== capability.accountBinding ||
          candidate.deviceBinding.toLowerCase() !== capability.deviceId)) ||
      !Number.isInteger(candidate.planRevision) ||
      candidate.planRevision < 1 ||
      candidate.planRevision > MAX_PLAN_REVISION
    ) {
      return json({ error: "Invalid plan candidate" }, 500, versionHeaders);
    }

    const validation = validateGarminPlan(candidate.plan);
    if (!validation.ok) {
      const { data: quarantine, error: quarantineError } = await capabilityRpc(
        supabaseUrl,
        databaseSecretKey,
        anonKey,
        "garmin_quarantine_pending_plan",
        {
          p_device_token: capability.nonce,
          p_plan_id: candidate.planId,
          p_plan_revision: candidate.planRevision,
          p_reason: validation.error.slice(0, 200),
        },
      );
      if (quarantineError) {
        return json({ error: "Plan quarantine failed" }, 500, versionHeaders);
      }
      const quarantineRateLimited = rateLimitedResponse(
        quarantine,
        versionHeaders,
      );
      if (quarantineRateLimited) return quarantineRateLimited;
      if (quarantine?.error === "Invalid device") {
        return json({ error: quarantine.error }, 401, versionHeaders);
      }
      if (quarantine?.status === "conflict") {
        return json({ error: "Plan quarantine conflict" }, 409, versionHeaders);
      }
      if (quarantine?.status !== "quarantined") {
        return json(
          { error: "Invalid plan quarantine response" },
          500,
          versionHeaders,
        );
      }
      return json(
        {
          error: "Pending plan failed validation",
          planId: candidate.planId,
          capabilityVersion: capability.version,
        },
        422,
        versionHeaders,
      );
    }

    return json(
      {
        status: "ok",
        bindingVersion: 2,
        accountBinding: candidate.accountBinding,
        deviceBinding: candidate.deviceBinding,
        planId: candidate.planId,
        planRevision: candidate.planRevision,
        plan: validation.plan,
        capabilityVersion: capability.version,
      },
      200,
      versionHeaders,
    );
  }

  if (body.action === "ackPlan") {
    const deviceToken = typeof body.deviceToken === "string"
      ? body.deviceToken
      : "";
    const planId = typeof body.planId === "string" ? body.planId.trim() : "";
    if (
      !UUID_PATTERN.test(planId) ||
      !Number.isInteger(body.planRevision) ||
      Number(body.planRevision) < 1 ||
      Number(body.planRevision) > MAX_PLAN_REVISION
    ) {
      return json({ error: "Invalid plan acknowledgement" }, 400);
    }
    if (DEVICE_NONCE_PATTERN.test(deviceToken)) {
      return json(
        { error: "Garmin client upgrade required" },
        426,
        capabilityVersionHeaders(2),
      );
    }
    const capability = await resolveGarminCapability(
      deviceToken,
      capabilityHmacSecret,
    );
    if (!capability) {
      return json({ error: "Invalid plan acknowledgement" }, 400);
    }
    const { data: acknowledged, error: ackError } = await capabilityRpc(
      supabaseUrl,
      databaseSecretKey,
      anonKey,
      "garmin_ack_plan",
      {
        p_device_token: capability.nonce,
        p_plan_id: planId,
        p_plan_revision: body.planRevision,
      },
    );
    if (ackError) return json({ error: "Plan acknowledgement failed" }, 500);
    const versionHeaders = capabilityVersionHeaders(capability.version);
    if (acknowledged?.error !== "Invalid device") {
      scheduleCapabilityUse(
        supabaseUrl,
        databaseSecretKey,
        capability,
      );
    }
    const rateLimited = rateLimitedResponse(acknowledged, versionHeaders);
    if (rateLimited) return rateLimited;
    if (acknowledged?.error === "Invalid device") {
      return json({ error: acknowledged.error }, 401, versionHeaders);
    }
    if (acknowledged?.status === "invalid") {
      return json(
        { error: "Plan failed acknowledgement validation" },
        422,
        versionHeaders,
      );
    }
    if (
      !["acknowledged", "already_acknowledged"].includes(acknowledged?.status)
    ) {
      return json(
        {
          error: "Plan acknowledgement conflict",
          status: acknowledged?.status || "conflict",
          capabilityVersion: capability.version,
        },
        409,
        versionHeaders,
      );
    }
    return json(
      {
        status: acknowledged.status,
        planId,
        planRevision: body.planRevision,
        capabilityVersion: capability.version,
      },
      200,
      versionHeaders,
    );
  }

  return json({ error: "Unknown action" }, 400);
});
