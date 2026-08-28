import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  type ClaimedDelivery,
  type DeliveryResult,
  loadProviderConfig,
  type ProviderConfig,
  type PushProvider,
  sendDelivery,
  warmProviderCredentials,
} from "./providers.ts";

const JSON_CONTENT_TYPE = "application/json; charset=utf-8";
const MAX_REQUEST_BYTES = 1_024;
// Keep one dispatch within two global worker waves. This composes with the
// provider/RPC timeouts, the 240-second database lease, and the scheduler's
// shorter HTTP timeout even when a batch contains all three providers.
const MAX_BATCH_SIZE = 10;
const DEFAULT_BATCH_SIZE = 10;
const MAX_CONCURRENCY = 5;
const RPC_TIMEOUT_MS = 12_000;
const HIGH_ENTROPY_SECRET_PATTERN = /^[A-Za-z0-9_-]{43,256}$/;

type JsonRecord = Record<string, unknown>;
type RpcClient = Pick<SupabaseClient, "rpc">;
type ReadEnv = (name: string) => string | undefined;

function isRecord(value: unknown): value is JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value: JsonRecord, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index]);
}

function responseHeaders(extra: HeadersInit = {}): Headers {
  const headers = new Headers(extra);
  headers.set("Cache-Control", "no-store");
  headers.set("Content-Type", JSON_CONTENT_TYPE);
  headers.set("Pragma", "no-cache");
  headers.set("X-Content-Type-Options", "nosniff");
  return headers;
}

function jsonResponse(
  status: number,
  body: JsonRecord,
  extra: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(extra),
  });
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

function getServiceKey(readEnv: ReadEnv): string | null {
  return readEnv("SUPABASE_SECRET_KEY")?.trim() ||
    parseNamedKeySet(readEnv("SUPABASE_SECRET_KEYS")) ||
    readEnv("SUPABASE_SERVICE_ROLE_KEY")?.trim() || null;
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
    // Modern sb_secret keys are gateway API keys, not JWTs. supabase-js adds
    // its key as a Bearer token by default, which PostgREST rejects as an
    // invalid JWT. Legacy service-role JWT authorization remains unchanged.
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
    ) {
      return null;
    }
    return url.origin;
  } catch {
    return null;
  }
}

export function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let difference = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}

export function loadDispatchCredentials(
  readEnv: ReadEnv,
): { serviceKey: string; dispatchServerKey: string } | null {
  const serviceKey = getServiceKey(readEnv);
  const dispatchServerKey = readEnv("PUSH_DISPATCH_SERVER_KEY")?.trim() ?? "";
  if (
    !serviceKey || !HIGH_ENTROPY_SECRET_PATTERN.test(dispatchServerKey) ||
    constantTimeEqual(dispatchServerKey, serviceKey)
  ) {
    return null;
  }
  return { serviceKey, dispatchServerKey };
}

async function readRequestBody(req: Request): Promise<unknown> {
  const declared = req.headers.get("content-length");
  if (declared) {
    const parsed = Number(declared);
    if (
      !Number.isSafeInteger(parsed) || parsed < 0 || parsed > MAX_REQUEST_BYTES
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
      total += value.byteLength;
      if (total > MAX_REQUEST_BYTES || chunks.length >= 16) {
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

function parseBatchRequest(value: unknown): number {
  if (
    !isRecord(value) || !exactKeys(value, ["version", "batchSize"]) ||
    value.version !== 1 ||
    !Number.isInteger(value.batchSize) || Number(value.batchSize) < 1 ||
    Number(value.batchSize) > MAX_BATCH_SIZE
  ) {
    throw new TypeError("invalid_request");
  }
  return Number(value.batchSize);
}

async function markResult(
  client: RpcClient,
  delivery: ClaimedDelivery,
  result: DeliveryResult,
): Promise<boolean> {
  try {
    if (result.outcome === "delivered") {
      const marked = await client.rpc("push_mark_delivered", {
        p_delivery_id: delivery.delivery_id,
        p_lease_token: delivery.lease_token,
        p_provider_status: result.providerStatus,
      }).abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
      return !marked.error && marked.data === true;
    }
    const marked = await client.rpc("push_mark_retry", {
      p_delivery_id: delivery.delivery_id,
      p_lease_token: delivery.lease_token,
      p_error_code: result.errorCode,
      p_provider_status: result.providerStatus,
      p_retry_after_seconds: result.retryAfterSeconds ?? null,
      p_invalid_registration: result.outcome === "invalid",
      p_permanent_failure: result.outcome === "permanent",
    }).abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
    return !marked.error && marked.data === true;
  } catch {
    return false;
  }
}

async function deliveryStillCurrent(
  client: RpcClient,
  delivery: ClaimedDelivery,
): Promise<"current" | "stale" | "unavailable"> {
  try {
    const checked = await client.rpc("push_delivery_is_current", {
      p_delivery_id: delivery.delivery_id,
      p_lease_token: delivery.lease_token,
    }).abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
    if (checked.error || typeof checked.data !== "boolean") {
      return "unavailable";
    }
    return checked.data ? "current" : "stale";
  } catch {
    return "unavailable";
  }
}

type DispatchCounts = {
  claimed: number;
  delivered: number;
  retried: number;
  invalidated: number;
  permanentlyFailed: number;
  acknowledgementFailures: number;
};

async function dispatchBatch(
  client: RpcClient,
  deliveries: ClaimedDelivery[],
  providerConfigFor: (delivery: ClaimedDelivery) => ProviderConfig,
): Promise<DispatchCounts> {
  const counts: DispatchCounts = {
    claimed: deliveries.length,
    delivered: 0,
    retried: 0,
    invalidated: 0,
    permanentlyFailed: 0,
    acknowledgementFailures: 0,
  };
  let nextIndex = 0;
  async function worker(): Promise<void> {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= deliveries.length) return;
      const delivery = deliveries[index];
      const current = await deliveryStillCurrent(client, delivery);
      const result: DeliveryResult = current === "current"
        ? await sendDelivery(delivery, providerConfigFor(delivery))
        : current === "stale"
        ? {
          // A false current-check can also mean the outbox expired or was
          // closed after claim. Only provider responses may declare a raw
          // registration invalid; otherwise a valid address could be
          // revoked because of ordinary delivery lifecycle timing.
          outcome: "permanent",
          errorCode: "delivery_changed_before_send",
          providerStatus: null,
        }
        : {
          outcome: "retry",
          errorCode: "registration_check_unavailable",
          providerStatus: null,
          retryAfterSeconds: 60,
        };
      if (result.outcome === "delivered") counts.delivered += 1;
      else if (result.outcome === "retry") counts.retried += 1;
      else if (result.outcome === "invalid") counts.invalidated += 1;
      else counts.permanentlyFailed += 1;
      if (!await markResult(client, delivery, result)) {
        counts.acknowledgementFailures += 1;
      }
    }
  }
  await Promise.all(
    Array.from(
      { length: Math.min(MAX_CONCURRENCY, deliveries.length) },
      () => worker(),
    ),
  );
  return counts;
}

export async function handleRequest(req: Request): Promise<Response> {
  if (req.headers.has("origin")) {
    return jsonResponse(403, { error: "browser_requests_forbidden" });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" }, {
      Allow: "POST",
    });
  }
  const credentials = loadDispatchCredentials((name) => Deno.env.get(name));
  if (!credentials) {
    return jsonResponse(503, { error: "service_unavailable" });
  }
  const { serviceKey, dispatchServerKey } = credentials;
  const suppliedDispatchServerKey = req.headers.get("apikey") ?? "";
  if (
    suppliedDispatchServerKey.length > 512 ||
    !constantTimeEqual(suppliedDispatchServerKey, dispatchServerKey)
  ) {
    return jsonResponse(401, { error: "invalid_authorization" });
  }
  const configuredDispatchToken = Deno.env.get("PUSH_DISPATCH_TOKEN")?.trim() ??
    "";
  const suppliedDispatchToken =
    req.headers.get("x-gymapp-push-dispatch-token") ?? "";
  if (
    !HIGH_ENTROPY_SECRET_PATTERN.test(configuredDispatchToken) ||
    suppliedDispatchToken.length > 512 ||
    !constantTimeEqual(suppliedDispatchToken, configuredDispatchToken)
  ) {
    return jsonResponse(401, { error: "invalid_authorization" });
  }
  if (
    req.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !==
      "application/json"
  ) {
    return jsonResponse(415, {
      error: "content_type_must_be_application_json",
    });
  }

  let batchSize = DEFAULT_BATCH_SIZE;
  try {
    batchSize = parseBatchRequest(await readRequestBody(req));
  } catch (error) {
    return jsonResponse(
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
  if (!projectUrl) {
    return jsonResponse(503, { error: "service_unavailable" });
  }

  const client = createClient(projectUrl, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: serviceRoleFetch(serviceKey) },
  });
  const claim = await client.rpc("push_claim_deliveries", {
    p_worker_id: crypto.randomUUID(),
    p_limit: batchSize,
    p_lease_seconds: 240,
  }).abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS)).then(
    (result) => result,
    () => null,
  );
  if (
    !claim || claim.error || !Array.isArray(claim.data) ||
    claim.data.length > batchSize
  ) {
    return jsonResponse(503, { error: "service_unavailable" });
  }

  const deliveries = claim.data as ClaimedDelivery[];
  const groups = new Map<string, ClaimedDelivery[]>();
  for (const delivery of deliveries) {
    const provider = String(delivery?.provider ?? "invalid");
    groups.set(provider, [...(groups.get(provider) ?? []), delivery]);
  }
  const emptyProviderConfig = (): ProviderConfig => ({
    fcm: null,
    apns: null,
    webPush: null,
  });
  const providerConfigs = new Map<string, ProviderConfig>();
  await Promise.all([...groups.keys()].map(async (provider) => {
    let providerConfig = emptyProviderConfig();
    if (["fcm", "apns", "web_push"].includes(provider)) {
      try {
        providerConfig = await loadProviderConfig(
          (name) => Deno.env.get(name),
          [provider as PushProvider],
        );
        await warmProviderCredentials(providerConfig);
      } catch {
        // Only this provider's leased rows receive a bounded retry. Loading
        // credentials in parallel prevents an unavailable native provider
        // from delaying configured Web Push, while the single dispatch worker
        // pool below keeps total external concurrency capped at five.
      }
    }
    providerConfigs.set(provider, providerConfig);
  }));
  const counts = await dispatchBatch(
    client,
    deliveries,
    (delivery) =>
      providerConfigs.get(String(delivery.provider)) ?? {
        fcm: null,
        apns: null,
        webPush: null,
      },
  );
  return jsonResponse(counts.acknowledgementFailures > 0 ? 503 : 200, {
    version: 1,
    ...counts,
  });
}

if (import.meta.main) Deno.serve(handleRequest);
