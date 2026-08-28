import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { debitVerifiedIdentityBudget } from "../_shared/preauth-budget.ts";

const JSON_CONTENT_TYPE = "application/json; charset=utf-8";
const MAX_BODY_BYTES = 48 * 1024;
const MAX_BODY_CHUNKS = 256;
const RPC_TIMEOUT_MS = 12_000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROFILE_ID_PATTERN = /^p_[0-9a-f]{32}$/;
const FRIENDSHIP_ID_PATTERN = /^f_[0-9a-f]{32}$/;
const WORKOUT_INVITE_ID_PATTERN = /^wi_[0-9a-f]{32}$/;
const LIVE_ROOM_ID_PATTERN = /^lr_[0-9a-f]{32}$/;

type JsonRecord = Record<string, unknown>;
type RpcClient = Pick<SupabaseClient, "rpc">;

type GatewayContext = {
  userId: string;
  sessionId: string;
};

type Route = {
  rpc: string;
  serviceOnly: boolean;
  args: (payload: JsonRecord, context: GatewayContext) => JsonRecord;
};

function isRecord(value: unknown): value is JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value: JsonRecord, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index]);
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function isRevision(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) >= 1 &&
    Number(value) <= 2_147_483_647;
}

function isLiveRoomId(value: unknown): value is string {
  return typeof value === "string" && LIVE_ROOM_ID_PATTERN.test(value);
}

function validJsonComplexity(root: unknown): boolean {
  const stack: Array<{ value: unknown; depth: number }> = [
    { value: root, depth: 0 },
  ];
  let containers = 0;
  while (stack.length) {
    const current = stack.pop()!;
    if (current.depth > 16) return false;
    if (Array.isArray(current.value)) {
      containers += 1;
      if (containers > 1_024 || current.value.length > 256) return false;
      for (const child of current.value) {
        stack.push({ value: child, depth: current.depth + 1 });
      }
    } else if (isRecord(current.value)) {
      containers += 1;
      const entries = Object.entries(current.value);
      if (containers > 1_024 || entries.length > 128) return false;
      for (const [key, child] of entries) {
        if (key.length > 80) return false;
        stack.push({ value: child, depth: current.depth + 1 });
      }
    } else if (
      typeof current.value === "string" && current.value.length > 4_000
    ) {
      return false;
    }
  }
  return true;
}

function emptyPayload(payload: JsonRecord): boolean {
  return exactKeys(payload, []);
}

function socialRoute(
  rpc: string,
  expected: readonly string[],
  validate: (payload: JsonRecord) => boolean,
  map: (payload: JsonRecord) => JsonRecord,
): Route {
  return {
    rpc,
    serviceOnly: false,
    args: (payload) => {
      if (!exactKeys(payload, expected) || !validate(payload)) {
        throw new TypeError("invalid_payload");
      }
      return map(payload);
    },
  };
}

function liveRoute(
  rpc: string,
  expected: readonly string[],
  validate: (payload: JsonRecord) => boolean,
  map: (payload: JsonRecord) => JsonRecord,
): Route {
  return {
    rpc,
    serviceOnly: true,
    args: (payload, context) => {
      if (!exactKeys(payload, expected) || !validate(payload)) {
        throw new TypeError("invalid_payload");
      }
      return {
        p_caller_user_id: context.userId,
        p_session_id: context.sessionId,
        ...map(payload),
      };
    },
  };
}

export const ROUTES: Readonly<Record<string, Route>> = Object.freeze({
  social_dashboard: socialRoute(
    "social_dashboard",
    [],
    emptyPayload,
    () => ({}),
  ),
  social_friend_details: socialRoute(
    "social_friend_details",
    ["profileId"],
    (p) =>
      typeof p.profileId === "string" && PROFILE_ID_PATTERN.test(p.profileId),
    (p) => ({ p_profile_id: p.profileId }),
  ),
  social_send_friend_request: socialRoute(
    "social_send_friend_request",
    ["friendCode"],
    (p) =>
      typeof p.friendCode === "string" && PROFILE_ID_PATTERN.test(p.friendCode),
    (p) => ({ p_friend_code: p.friendCode }),
  ),
  social_respond_friend_request: socialRoute(
    "social_respond_friend_request",
    ["friendshipId", "decision", "expectedRevision"],
    (p) =>
      typeof p.friendshipId === "string" &&
      FRIENDSHIP_ID_PATTERN.test(p.friendshipId) &&
      (p.decision === "accept" || p.decision === "decline") &&
      isRevision(p.expectedRevision),
    (p) => ({
      p_friendship_id: p.friendshipId,
      p_decision: p.decision,
      p_expected_revision: p.expectedRevision,
    }),
  ),
  social_cancel_friend_request: socialRoute(
    "social_cancel_friend_request",
    ["friendshipId", "expectedRevision"],
    (p) =>
      typeof p.friendshipId === "string" &&
      FRIENDSHIP_ID_PATTERN.test(p.friendshipId) &&
      isRevision(p.expectedRevision),
    (p) => ({
      p_friendship_id: p.friendshipId,
      p_expected_revision: p.expectedRevision,
    }),
  ),
  social_remove_friend: socialRoute(
    "social_remove_friend",
    ["friendshipId", "expectedRevision"],
    (p) =>
      typeof p.friendshipId === "string" &&
      FRIENDSHIP_ID_PATTERN.test(p.friendshipId) &&
      isRevision(p.expectedRevision),
    (p) => ({
      p_friendship_id: p.friendshipId,
      p_expected_revision: p.expectedRevision,
    }),
  ),
  social_block_profile: socialRoute(
    "social_block_profile",
    ["profileId"],
    (p) =>
      typeof p.profileId === "string" && PROFILE_ID_PATTERN.test(p.profileId),
    (p) => ({ p_profile_id: p.profileId }),
  ),
  social_unblock_profile: socialRoute(
    "social_unblock_profile",
    ["profileId"],
    (p) =>
      typeof p.profileId === "string" && PROFILE_ID_PATTERN.test(p.profileId),
    (p) => ({ p_profile_id: p.profileId }),
  ),
  social_update_privacy: socialRoute(
    "social_update_privacy",
    [
      "allowRequests",
      "shareProgress",
      "shareRecentWorkouts",
      "shareRecords",
      "expectedRevision",
    ],
    (p) =>
      typeof p.allowRequests === "boolean" &&
      typeof p.shareProgress === "boolean" &&
      typeof p.shareRecentWorkouts === "boolean" &&
      typeof p.shareRecords === "boolean" &&
      isRevision(p.expectedRevision),
    (p) => ({
      p_allow_requests: p.allowRequests,
      p_share_progress: p.shareProgress,
      p_share_recent_workouts: p.shareRecentWorkouts,
      p_share_records: p.shareRecords,
      p_expected_revision: p.expectedRevision,
    }),
  ),
  social_workout_inbox: socialRoute(
    "social_workout_inbox",
    [],
    emptyPayload,
    () => ({}),
  ),
  social_send_workout_invite: socialRoute(
    "social_send_workout_invite",
    ["profileId", "clientRequestId", "workout"],
    (p) =>
      typeof p.profileId === "string" && PROFILE_ID_PATTERN.test(p.profileId) &&
      isUuid(p.clientRequestId) && isRecord(p.workout) &&
      validJsonComplexity(p.workout),
    (p) => ({
      p_profile_id: p.profileId,
      p_client_request_id: p.clientRequestId,
      p_workout: p.workout,
    }),
  ),
  social_respond_workout_invite: socialRoute(
    "social_respond_workout_invite",
    ["inviteId", "decision", "expectedRevision"],
    (p) =>
      typeof p.inviteId === "string" &&
      WORKOUT_INVITE_ID_PATTERN.test(p.inviteId) &&
      (p.decision === "accept" || p.decision === "decline") &&
      isRevision(p.expectedRevision),
    (p) => ({
      p_invite_id: p.inviteId,
      p_decision: p.decision,
      p_expected_revision: p.expectedRevision,
    }),
  ),
  social_cancel_workout_invite: socialRoute(
    "social_cancel_workout_invite",
    ["inviteId", "expectedRevision"],
    (p) =>
      typeof p.inviteId === "string" &&
      WORKOUT_INVITE_ID_PATTERN.test(p.inviteId) &&
      isRevision(p.expectedRevision),
    (p) => ({
      p_invite_id: p.inviteId,
      p_expected_revision: p.expectedRevision,
    }),
  ),
  live_inbox: liveRoute(
    "social_live_workout_inbox",
    [],
    emptyPayload,
    () => ({}),
  ),
  live_send_invite: liveRoute(
    "social_send_live_workout_invite",
    ["profileId", "clientRequestId", "workout"],
    (p) =>
      typeof p.profileId === "string" && PROFILE_ID_PATTERN.test(p.profileId) &&
      isUuid(p.clientRequestId) && isRecord(p.workout) &&
      validJsonComplexity(p.workout),
    (p) => ({
      p_profile_id: p.profileId,
      p_client_request_id: p.clientRequestId,
      p_workout: p.workout,
    }),
  ),
  live_respond_invite: liveRoute(
    "social_respond_live_workout_invite",
    ["roomId", "decision", "expectedRoomRevision", "clientOperationId"],
    (p) =>
      isLiveRoomId(p.roomId) &&
      (p.decision === "accept" || p.decision === "decline") &&
      isRevision(p.expectedRoomRevision) && isUuid(p.clientOperationId),
    (p) => ({
      p_room_id: p.roomId,
      p_decision: p.decision,
      p_expected_room_revision: p.expectedRoomRevision,
      p_client_operation_id: p.clientOperationId,
    }),
  ),
  live_start: liveRoute(
    "social_start_live_workout",
    ["roomId", "expectedRoomRevision", "clientOperationId"],
    (p) =>
      isLiveRoomId(p.roomId) && isRevision(p.expectedRoomRevision) &&
      isUuid(p.clientOperationId),
    (p) => ({
      p_room_id: p.roomId,
      p_expected_room_revision: p.expectedRoomRevision,
      p_client_operation_id: p.clientOperationId,
    }),
  ),
  live_snapshot: liveRoute(
    "social_live_workout_snapshot",
    ["roomId"],
    (p) => isLiveRoomId(p.roomId),
    (p) => ({ p_room_id: p.roomId }),
  ),
  live_apply: liveRoute(
    "social_apply_live_workout_operation",
    ["roomId", "clientOperationId", "expectedProgressRevision", "operation"],
    (p) =>
      isLiveRoomId(p.roomId) && isUuid(p.clientOperationId) &&
      isRevision(p.expectedProgressRevision) && isRecord(p.operation) &&
      validJsonComplexity(p.operation),
    (p) => ({
      p_room_id: p.roomId,
      p_client_operation_id: p.clientOperationId,
      p_expected_progress_revision: p.expectedProgressRevision,
      p_operation: p.operation,
    }),
  ),
  live_finish: liveRoute(
    "social_finish_live_workout",
    ["roomId", "clientOperationId", "expectedProgressRevision"],
    (p) =>
      isLiveRoomId(p.roomId) && isUuid(p.clientOperationId) &&
      isRevision(p.expectedProgressRevision),
    (p) => ({
      p_room_id: p.roomId,
      p_client_operation_id: p.clientOperationId,
      p_expected_progress_revision: p.expectedProgressRevision,
    }),
  ),
  live_leave: liveRoute(
    "social_leave_live_workout",
    ["roomId", "clientOperationId", "expectedMembershipRevision"],
    (p) =>
      isLiveRoomId(p.roomId) && isUuid(p.clientOperationId) &&
      isRevision(p.expectedMembershipRevision),
    (p) => ({
      p_room_id: p.roomId,
      p_client_operation_id: p.clientOperationId,
      p_expected_membership_revision: p.expectedMembershipRevision,
    }),
  ),
  live_cancel: liveRoute(
    "social_cancel_live_workout",
    ["roomId", "clientOperationId", "expectedRoomRevision"],
    (p) =>
      isLiveRoomId(p.roomId) && isUuid(p.clientOperationId) &&
      isRevision(p.expectedRoomRevision),
    (p) => ({
      p_room_id: p.roomId,
      p_client_operation_id: p.clientOperationId,
      p_expected_room_revision: p.expectedRoomRevision,
    }),
  ),
});

export type ParsedGatewayRequest = {
  action: string;
  payload: JsonRecord;
};

export function parseGatewayRequest(value: unknown): ParsedGatewayRequest {
  if (
    !isRecord(value) || !exactKeys(value, ["version", "action", "payload"]) ||
    value.version !== 1 || typeof value.action !== "string" ||
    !Object.hasOwn(ROUTES, value.action) || !isRecord(value.payload) ||
    !validJsonComplexity(value.payload)
  ) {
    throw new TypeError("invalid_request");
  }
  return { action: value.action, payload: value.payload };
}

function baseHeaders(extra: HeadersInit = {}): Headers {
  const headers = new Headers(extra);
  headers.set("Cache-Control", "no-store");
  headers.set("Content-Type", JSON_CONTENT_TYPE);
  headers.set("Pragma", "no-cache");
  headers.set("X-Content-Type-Options", "nosniff");
  return headers;
}

function allowedOrigin(req: Request): string | null {
  const requestOrigin = req.headers.get("origin");
  const configured = Deno.env.get("SOCIAL_LIVE_ALLOWED_ORIGIN")?.trim();
  return requestOrigin && configured && requestOrigin === configured
    ? configured
    : null;
}

function corsHeaders(req: Request): HeadersInit {
  const origin = allowedOrigin(req);
  return origin
    ? {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Max-Age": "600",
      Vary: "Origin",
    }
    : {};
}

function jsonResponse(
  req: Request,
  status: number,
  body: JsonRecord,
  extra: HeadersInit = {},
): Response {
  const headers = baseHeaders(corsHeaders(req));
  new Headers(extra).forEach((value, key) => headers.set(key, value));
  return new Response(JSON.stringify(body), { status, headers });
}

function parseNamedKeySet(raw: string | undefined): string | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!isRecord(parsed)) return null;
    if (typeof parsed.default === "string" && parsed.default.trim()) {
      return parsed.default.trim();
    }
    return Object.values(parsed).find((value): value is string =>
      typeof value === "string" && value.trim().length > 0
    )?.trim() ?? null;
  } catch {
    return null;
  }
}

function getPublishableKey(): string | null {
  return Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ||
    parseNamedKeySet(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")) ||
    Deno.env.get("SUPABASE_ANON_KEY")?.trim() || null;
}

function getServiceKey(): string | null {
  return Deno.env.get("SUPABASE_SECRET_KEY")?.trim() ||
    parseNamedKeySet(Deno.env.get("SUPABASE_SECRET_KEYS")) ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || null;
}

export function serviceRoleFetch(
  serviceKey: string,
  baseFetch: typeof fetch = fetch,
): typeof fetch {
  const secretKey = serviceKey.startsWith("sb_secret_");
  return (input, init) => {
    const headers = new Headers(
      input instanceof Request ? input.headers : undefined,
    );
    const initHeaders = init && "headers" in init ? init.headers : undefined;
    new Headers(initHeaders).forEach((value, name) => headers.set(name, value));
    headers.set("apikey", serviceKey);
    if (secretKey) headers.delete("Authorization");
    return baseFetch(input, { ...init, headers });
  };
}

function normalizeProjectUrl(raw: string): string | null {
  try {
    const url = new URL(raw);
    if (
      url.protocol !== "https:" && url.hostname !== "127.0.0.1" &&
      url.hostname !== "localhost"
    ) return null;
    return url.origin;
  } catch {
    return null;
  }
}

function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (!header || header.length > 8_192) return null;
  return /^Bearer ([^\s]+)$/.exec(header)?.[1] ?? null;
}

function decodeBase64Url(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return null;
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  try {
    return Uint8Array.from(
      atob(padded),
      (character) => character.charCodeAt(0),
    );
  } catch {
    return null;
  }
}

export function verifiedSessionIdFromJwt(token: string): string | null {
  if (token.length > 8_192) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const decoded = decodeBase64Url(parts[1]);
  if (!decoded || decoded.byteLength > 8_192) return null;
  try {
    const payload = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(decoded),
    ) as unknown;
    return isRecord(payload) && isUuid(payload.session_id)
      ? payload.session_id
      : null;
  } catch {
    return null;
  }
}

async function readJsonBody(req: Request): Promise<unknown> {
  const declared = req.headers.get("content-length");
  if (declared) {
    const length = Number(declared);
    if (
      !Number.isSafeInteger(length) || length < 0 || length > MAX_BODY_BYTES
    ) {
      throw new DOMException("request_too_large", "QuotaExceededError");
    }
  }
  if (!req.body) throw new TypeError("invalid_request");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (chunks.length >= MAX_BODY_CHUNKS) {
        throw new DOMException("request_too_large", "QuotaExceededError");
      }
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        throw new DOMException("request_too_large", "QuotaExceededError");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  ) as unknown;
}

function rpcErrorStatus(error: { code?: string } | null): number {
  if (error?.code === "42501") return 401;
  if (error?.code === "P0002") return 404;
  if (error?.code === "P0001") return 409;
  if (error?.code === "22023" || error?.code === "54000") return 400;
  return 502;
}

export async function handleRequest(req: Request): Promise<Response> {
  const requestOrigin = req.headers.get("origin");
  const configuredOrigin = Deno.env.get("SOCIAL_LIVE_ALLOWED_ORIGIN")?.trim();
  if (req.method === "OPTIONS") {
    if (!configuredOrigin || requestOrigin !== configuredOrigin) {
      return jsonResponse(req, 403, { error: "origin_not_allowed" });
    }
    return new Response(null, {
      status: 204,
      headers: baseHeaders(corsHeaders(req)),
    });
  }
  if (
    requestOrigin && (!configuredOrigin || requestOrigin !== configuredOrigin)
  ) {
    return jsonResponse(req, 403, { error: "origin_not_allowed" });
  }
  if (req.method !== "POST") {
    return jsonResponse(req, 405, { error: "method_not_allowed" }, {
      Allow: "POST, OPTIONS",
    });
  }
  if (
    req.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !==
      "application/json"
  ) {
    return jsonResponse(req, 415, {
      error: "content_type_must_be_application_json",
    });
  }
  const token = bearerToken(req);
  if (!token) return jsonResponse(req, 401, { error: "invalid_authorization" });

  let parsed: ParsedGatewayRequest;
  try {
    parsed = parseGatewayRequest(await readJsonBody(req));
  } catch (error) {
    return jsonResponse(
      req,
      error instanceof DOMException && error.name === "QuotaExceededError"
        ? 413
        : 400,
      {
        error: error instanceof DOMException
          ? "request_too_large"
          : "invalid_request",
      },
    );
  }

  const projectUrl = normalizeProjectUrl(
    Deno.env.get("SUPABASE_URL")?.trim() ?? "",
  );
  const publishableKey = getPublishableKey();
  const serviceKey = getServiceKey();
  if (!projectUrl || !publishableKey || !serviceKey) {
    return jsonResponse(req, 503, { error: "service_unavailable" });
  }

  const authorization = `Bearer ${token}`;
  const userClient = createClient(projectUrl, publishableKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { headers: { Authorization: authorization } },
  });
  const serviceClient = createClient(projectUrl, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: serviceRoleFetch(serviceKey) },
  });

  const authResult = await userClient.auth.getUser(token).catch(() => null);
  const userId = authResult?.data.user?.id;
  const sessionId = verifiedSessionIdFromJwt(token);
  if (authResult?.error || !isUuid(userId) || !sessionId) {
    return jsonResponse(req, 401, { error: "invalid_or_expired_token" });
  }

  const identityBudget = await debitVerifiedIdentityBudget(
    `session:${sessionId.toLowerCase()}`,
    "social_live",
    projectUrl,
    serviceKey,
  );
  if (identityBudget.status === "rate_limited") {
    return jsonResponse(req, 429, { error: "rate_limited" }, {
      "Retry-After": String(identityBudget.retryAfter),
    });
  }
  if (identityBudget.status !== "allowed") {
    return jsonResponse(req, 503, { error: "service_unavailable" });
  }

  const route = ROUTES[parsed.action];
  // This service-only RPC is intentionally awaited before the domain call.
  // PostgREST commits the bounded debit in a separate transaction, so a later
  // validation/domain failure cannot roll it back.
  const debit = await serviceClient.rpc("social_live_gateway_debit", {
    p_user_id: userId,
    p_session_id: sessionId,
    p_action: parsed.action,
  }).abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS)).then(
    (result) => result,
    () => null,
  );
  if (!debit) {
    return jsonResponse(req, 503, { error: "service_unavailable" });
  }
  if (debit.error) {
    return jsonResponse(req, debit.error.code === "42501" ? 401 : 503, {
      error: debit.error.code === "42501"
        ? "invalid_or_expired_token"
        : "service_unavailable",
    });
  }
  if (
    !isRecord(debit.data) || debit.data.version !== 1 ||
    typeof debit.data.allowed !== "boolean"
  ) {
    return jsonResponse(req, 503, { error: "service_unavailable" });
  }
  if (!debit.data.allowed) {
    const retryAfter = Number(debit.data.retryAfter);
    if (!Number.isInteger(retryAfter) || retryAfter < 1 || retryAfter > 3_600) {
      return jsonResponse(req, 503, { error: "service_unavailable" });
    }
    return jsonResponse(req, 429, { error: "rate_limited", retryAfter }, {
      "Retry-After": String(retryAfter),
    });
  }

  // A recognized action consumes its perimeter token even when its detailed
  // payload is malformed. This keeps body-validation spam bounded while the
  // top-level envelope remains cheap to reject before authentication work.
  let args: JsonRecord;
  try {
    args = route.args(parsed.payload, { userId, sessionId });
  } catch {
    return jsonResponse(req, 400, { error: "invalid_request" });
  }

  const domainClient: RpcClient = route.serviceOnly
    ? serviceClient
    : userClient;
  const result = await domainClient.rpc(route.rpc, args)
    .abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS)).then(
      (value) => value,
      () => null,
    );
  if (!result) {
    return jsonResponse(req, 502, { error: "service_unavailable" });
  }
  if (result.error) {
    const status = rpcErrorStatus(result.error);
    return jsonResponse(req, status, {
      error: status === 401
        ? "invalid_or_expired_token"
        : status === 404
        ? "resource_unavailable"
        : status === 409
        ? "conflict"
        : status === 400
        ? "request_rejected"
        : "service_unavailable",
    });
  }
  return jsonResponse(req, 200, { version: 1, result: result.data });
}

if (import.meta.main) Deno.serve(handleRequest);
