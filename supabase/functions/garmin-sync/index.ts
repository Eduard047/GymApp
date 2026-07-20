import { createClient } from "@supabase/supabase-js";
import { validateGarminPlan } from "../_shared/garmin-plan-contract.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
const DEVICE_TOKEN_PATTERN = /^[a-f0-9]{64}$/i;
const REPLACEMENT_TOKEN_PATTERN = /^[a-f0-9]{64}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RFC3339_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

type RequestBody = {
  action?: unknown;
  deviceToken?: unknown;
  deviceId?: unknown;
  replacementToken?: unknown;
  expectedTokenRevision?: unknown;
  displayName?: unknown;
  planId?: unknown;
  planRevision?: unknown;
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

function rateLimitedResponse(value: unknown): Response | null {
  if (!isObject(value) || value.status !== "rate_limited") return null;
  if (
    !Number.isInteger(value.retryAfter) || Number(value.retryAfter) < 1 ||
    Number(value.retryAfter) > 3600
  ) {
    return json({ error: "Invalid rate-limit response" }, 500);
  }
  const retryAfter = Number(value.retryAfter);
  return json(
    { error: "Rate limit exceeded", retryAfter },
    429,
    { "Retry-After": String(retryAfter) },
  );
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validDisplayName(value: unknown): value is string {
  return typeof value === "string" && value === value.trim() &&
    value.length > 0 &&
    value.length <= 80 && !/[\u0000-\u001f\u007f]/.test(value) &&
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
      !REPLACEMENT_TOKEN_PATTERN.test(value.device_token))
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
  try {
    supabaseUrl = requiredEnv("SUPABASE_URL");
    anonKey = requiredEnv("SUPABASE_ANON_KEY");
  } catch {
    return json({ error: "Server configuration error" }, 500);
  }

  const body = await readBody(request);
  if (!body) return json({ error: "Invalid or oversized request body" }, 400);

  if (body.action === "createDevice") {
    const userClient = authenticatedClient(request, supabaseUrl, anonKey);
    if (!userClient) return json({ error: "Unauthorized" }, 401);
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    if (userError || !userData.user) {
      return json({ error: "Unauthorized" }, 401);
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
    return json({ device });
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
    const replacementToken = typeof body.replacementToken === "string"
      ? body.replacementToken
      : "";
    const expectedTokenRevision = body.expectedTokenRevision;
    if (
      !UUID_PATTERN.test(deviceId) ||
      !REPLACEMENT_TOKEN_PATTERN.test(replacementToken) ||
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
        p_replacement_token: replacementToken,
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
    return json({
      status: data.status,
      device: { ...device, device_token: replacementToken },
    });
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
      ? body.deviceToken.trim()
      : "";
    if (!DEVICE_TOKEN_PATTERN.test(deviceToken)) {
      return json({ error: "Invalid deviceToken" }, 400);
    }

    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: candidate, error: fetchError } = await client.rpc(
      "garmin_fetch_pending_plan",
      {
        p_device_token: deviceToken,
      },
    );
    if (fetchError) return json({ error: "Plan fetch failed" }, 500);
    const rateLimited = rateLimitedResponse(candidate);
    if (rateLimited) return rateLimited;
    if (candidate?.error) return json({ error: candidate.error }, 401);
    if (!candidate || candidate.status === "empty") {
      return json({ status: "empty" });
    }
    if (candidate.status === "invalid") {
      return json({
        error: "Pending plan was quarantined",
        planId: candidate.planId,
      }, 422);
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
      !Number.isInteger(candidate.planRevision) ||
      candidate.planRevision < 1 ||
      candidate.planRevision > MAX_PLAN_REVISION
    ) {
      return json({ error: "Invalid plan candidate" }, 500);
    }

    const validation = validateGarminPlan(candidate.plan);
    if (!validation.ok) {
      const { data: quarantine, error: quarantineError } = await client.rpc(
        "garmin_quarantine_pending_plan",
        {
          p_device_token: deviceToken,
          p_plan_id: candidate.planId,
          p_plan_revision: candidate.planRevision,
          p_reason: validation.error.slice(0, 200),
        },
      );
      if (quarantineError) {
        return json({ error: "Plan quarantine failed" }, 500);
      }
      const quarantineRateLimited = rateLimitedResponse(quarantine);
      if (quarantineRateLimited) return quarantineRateLimited;
      if (quarantine?.error === "Invalid device") {
        return json({ error: quarantine.error }, 401);
      }
      if (quarantine?.status === "conflict") {
        return json({ error: "Plan quarantine conflict" }, 409);
      }
      if (quarantine?.status !== "quarantined") {
        return json({ error: "Invalid plan quarantine response" }, 500);
      }
      return json({
        error: "Pending plan failed validation",
        planId: candidate.planId,
      }, 422);
    }

    return json({
      status: "ok",
      bindingVersion: 2,
      accountBinding: candidate.accountBinding,
      deviceBinding: candidate.deviceBinding,
      planId: candidate.planId,
      planRevision: candidate.planRevision,
      plan: validation.plan,
    });
  }

  if (body.action === "ackPlan") {
    const deviceToken = typeof body.deviceToken === "string"
      ? body.deviceToken.trim()
      : "";
    const planId = typeof body.planId === "string" ? body.planId.trim() : "";
    if (
      !DEVICE_TOKEN_PATTERN.test(deviceToken) || !UUID_PATTERN.test(planId) ||
      !Number.isInteger(body.planRevision) ||
      Number(body.planRevision) < 1 ||
      Number(body.planRevision) > MAX_PLAN_REVISION
    ) {
      return json({ error: "Invalid plan acknowledgement" }, 400);
    }
    const client = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: acknowledged, error: ackError } = await client.rpc(
      "garmin_ack_plan",
      {
        p_device_token: deviceToken,
        p_plan_id: planId,
        p_plan_revision: body.planRevision,
      },
    );
    if (ackError) return json({ error: "Plan acknowledgement failed" }, 500);
    const rateLimited = rateLimitedResponse(acknowledged);
    if (rateLimited) return rateLimited;
    if (acknowledged?.error === "Invalid device") {
      return json({ error: acknowledged.error }, 401);
    }
    if (acknowledged?.status === "invalid") {
      return json({ error: "Plan failed acknowledgement validation" }, 422);
    }
    if (
      !["acknowledged", "already_acknowledged"].includes(acknowledged?.status)
    ) {
      return json({
        error: "Plan acknowledgement conflict",
        status: acknowledged?.status || "conflict",
      }, 409);
    }
    return json({
      status: acknowledged.status,
      planId,
      planRevision: body.planRevision,
    });
  }

  return json({ error: "Unknown action" }, 400);
});
