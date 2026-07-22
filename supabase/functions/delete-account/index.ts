const JSON_CONTENT_TYPE = "application/json; charset=utf-8";
const MAX_BODY_BYTES = 1_024;
const REQUEST_TIMEOUT_MS = 10_000;

type JsonRecord = Record<string, unknown>;

function baseHeaders(extra: HeadersInit = {}): Headers {
  const headers = new Headers(extra);
  headers.set("Cache-Control", "no-store");
  headers.set("Content-Type", JSON_CONTENT_TYPE);
  headers.set("X-Content-Type-Options", "nosniff");
  return headers;
}

function corsHeaders(req: Request): HeadersInit {
  const configuredOrigin = Deno.env.get("DELETE_ACCOUNT_ALLOWED_ORIGIN")
    ?.trim();
  const requestOrigin = req.headers.get("origin");

  if (
    !configuredOrigin || !requestOrigin || requestOrigin !== configuredOrigin
  ) {
    return {};
  }

  return {
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Origin": configuredOrigin,
    "Access-Control-Max-Age": "600",
    Vary: "Origin",
  };
}

function jsonResponse(
  req: Request,
  status: number,
  body: JsonRecord,
  extraHeaders: HeadersInit = {},
): Response {
  const headers = baseHeaders(corsHeaders(req));
  new Headers(extraHeaders).forEach((value, key) => headers.set(key, value));
  return new Response(JSON.stringify(body), { status, headers });
}

function parseNamedKeySet(raw: string | undefined): string | null {
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null;
    }

    const keys = parsed as Record<string, unknown>;
    if (typeof keys.default === "string" && keys.default.trim()) {
      return keys.default.trim();
    }

    const firstKey = Object.values(keys).find(
      (value): value is string =>
        typeof value === "string" && value.trim().length > 0,
    );
    return firstKey?.trim() ?? null;
  } catch {
    return null;
  }
}

function getPublishableOrAnonKey(): string | null {
  return (
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ||
    parseNamedKeySet(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")) ||
    Deno.env.get("SUPABASE_ANON_KEY")?.trim() ||
    null
  );
}

function getSecretOrServiceRoleKey(): string | null {
  return (
    Deno.env.get("SUPABASE_SECRET_KEY")?.trim() ||
    parseNamedKeySet(Deno.env.get("SUPABASE_SECRET_KEYS")) ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ||
    null
  );
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

function bearerAuthorization(req: Request): string | null {
  const value = req.headers.get("authorization");
  if (!value || value.length > 8_192) return null;

  const match = /^Bearer ([^\s]+)$/.exec(value);
  return match ? `Bearer ${match[1]}` : null;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

async function readConfirmation(
  req: Request,
): Promise<"confirmed" | "invalid" | "too_large"> {
  const contentLength = req.headers.get("content-length");
  if (contentLength) {
    const declaredLength = Number(contentLength);
    if (
      !Number.isFinite(declaredLength) || declaredLength < 0 ||
      declaredLength > MAX_BODY_BYTES
    ) {
      return "too_large";
    }
  }

  if (!req.body) return "invalid";

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > MAX_BODY_BYTES) {
        await reader.cancel();
        return "too_large";
      }
      chunks.push(value);
    }
  } catch {
    return "invalid";
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return "invalid";
  }

  try {
    const parsed = JSON.parse(text) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return "invalid";
    }

    const body = parsed as JsonRecord;
    const keys = Object.keys(body);
    return keys.length === 1 && keys[0] === "confirmation" &&
        body.confirmation === "DELETE"
      ? "confirmed"
      : "invalid";
  } catch {
    return "invalid";
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestOrigin = req.headers.get("origin");
  const configuredOrigin = Deno.env.get("DELETE_ACCOUNT_ALLOWED_ORIGIN")
    ?.trim();

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

  const mediaType = req.headers.get("content-type")?.split(";", 1)[0].trim()
    .toLowerCase();
  if (mediaType !== "application/json") {
    return jsonResponse(req, 415, {
      error: "content_type_must_be_application_json",
    });
  }

  const authorization = bearerAuthorization(req);
  if (!authorization) {
    return jsonResponse(req, 401, { error: "invalid_authorization" });
  }

  const confirmation = await readConfirmation(req);
  if (confirmation === "too_large") {
    return jsonResponse(req, 413, { error: "request_too_large" });
  }
  if (confirmation !== "confirmed") {
    return jsonResponse(req, 400, {
      error: "confirmation_required",
      expected: { confirmation: "DELETE" },
    });
  }

  const projectUrl = normalizeProjectUrl(
    Deno.env.get("SUPABASE_URL")?.trim() ?? "",
  );
  const publishableOrAnonKey = getPublishableOrAnonKey();
  const administrativeKey = getSecretOrServiceRoleKey();

  if (!projectUrl || !publishableOrAnonKey || !administrativeKey) {
    return jsonResponse(req, 503, { error: "service_unavailable" });
  }

  try {
    const verifyResponse = await fetch(`${projectUrl}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: publishableOrAnonKey,
        Authorization: authorization,
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });

    if (!verifyResponse.ok) {
      return jsonResponse(req, 401, { error: "invalid_or_expired_token" });
    }

    const authenticatedUser = await verifyResponse.json() as JsonRecord;
    if (!isUuid(authenticatedUser.id)) {
      return jsonResponse(req, 401, { error: "invalid_or_expired_token" });
    }

    const liveSessionResponse = await fetch(
      `${projectUrl}/rest/v1/rpc/require_live_session_for_account_deletion`,
      {
        method: "POST",
        headers: {
          apikey: publishableOrAnonKey,
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: "{}",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    );

    if (!liveSessionResponse.ok) {
      return jsonResponse(req, 401, { error: "invalid_or_expired_token" });
    }

    const liveSessionUserId = await liveSessionResponse.json() as unknown;
    if (
      !isUuid(liveSessionUserId) ||
      liveSessionUserId.toLowerCase() !== authenticatedUser.id.toLowerCase()
    ) {
      return jsonResponse(req, 401, { error: "invalid_or_expired_token" });
    }

    const adminHeaders: Record<string, string> = {
      apikey: administrativeKey,
      "Content-Type": "application/json",
    };
    // New sb_secret keys are API-gateway credentials, not JWTs, and therefore
    // belong only in apikey. Legacy service_role keys remain JWT bearer tokens.
    if (!administrativeKey.startsWith("sb_secret_")) {
      adminHeaders.Authorization = `Bearer ${administrativeKey}`;
    }

    const deleteResponse = await fetch(
      `${projectUrl}/auth/v1/admin/users/${
        encodeURIComponent(authenticatedUser.id)
      }`,
      {
        method: "DELETE",
        headers: adminHeaders,
        body: JSON.stringify({ should_soft_delete: false }),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    );

    if (!deleteResponse.ok) {
      return jsonResponse(req, 502, { error: "account_deletion_failed" });
    }

    return jsonResponse(req, 200, { deleted: true });
  } catch {
    return jsonResponse(req, 502, { error: "account_deletion_failed" });
  }
});
