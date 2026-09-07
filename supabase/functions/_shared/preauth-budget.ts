const HMAC_SECRET_PATTERN = /^[0-9a-f]{64}$/i;
const VERIFIED_IDENTITY_PATTERN =
  /^(?:account|session):[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type VerifiedIdentityBudgetResult =
  | { status: "allowed" }
  | { status: "rate_limited"; retryAfter: number }
  | {
    status: "unavailable";
    reason: string;
  };

function unavailable(code: string): VerifiedIdentityBudgetResult {
  const safeCode = /^[a-z0-9_]{1,64}$/.test(code) ? code : "rpc_rejected";
  // A bounded code is operationally useful without logging the identity, its
  // HMAC, any credential, or a database response body.
  console.warn("Gateway verified-identity budget unavailable", {
    code: safeCode,
  });
  return { status: "unavailable", reason: safeCode };
}

function bytesFromHex(value: string): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(new ArrayBuffer(value.length / 2));
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

async function identityHash(
  verifiedIdentity: string,
  route: string,
): Promise<string | null> {
  const secret = Deno.env.get("GATEWAY_PREAUTH_HMAC_SECRET")?.trim() ?? "";
  if (!HMAC_SECRET_PATTERN.test(secret)) return null;
  const key = await crypto.subtle.importKey(
    "raw",
    bytesFromHex(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${route}\n${verifiedIdentity.toLowerCase()}`),
    ),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

export async function debitVerifiedIdentityBudget(
  verifiedIdentity: string,
  route: "delete_account" | "social_live",
  projectUrl: string,
  administrativeKey: string,
): Promise<VerifiedIdentityBudgetResult> {
  if (!VERIFIED_IDENTITY_PATTERN.test(verifiedIdentity)) {
    return unavailable("invalid_verified_identity");
  }
  const hash = await identityHash(verifiedIdentity, route);
  if (!hash) return unavailable("invalid_hmac_secret");
  const headers: Record<string, string> = {
    apikey: administrativeKey,
    "Content-Type": "application/json",
  };
  if (!administrativeKey.startsWith("sb_secret_")) {
    headers.Authorization = `Bearer ${administrativeKey}`;
  }
  try {
    const response = await fetch(
      `${projectUrl}/rest/v1/rpc/edge_preauth_debit`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({ p_route: route, p_source_hash: hash }),
        signal: AbortSignal.timeout(5_000),
      },
    );
    if (!response.ok) {
      const errorBody = await response.clone().json().catch(() => null) as
        | Record<string, unknown>
        | null;
      const responseCode = typeof errorBody?.code === "string" &&
          /^[A-Za-z0-9]{1,16}$/.test(errorBody.code)
        ? errorBody.code.toLowerCase()
        : "unknown";
      return unavailable(`rpc_${response.status}_${responseCode}`);
    }
    const result = await response.json() as Record<string, unknown>;
    if (result.allowed === true && result.retryAfter === 0) {
      return { status: "allowed" };
    }
    if (result.allowed === false && result.retryAfter === 60) {
      return { status: "rate_limited", retryAfter: 60 };
    }
    return unavailable("invalid_rpc_response");
  } catch {
    return unavailable("rpc_transport_error");
  }
}

export type GarminGatewayBudgetLane = "jwt" | "capability";

const GARMIN_GATEWAY_ACTIONS = new Set([
  "createDeviceIdempotent",
  "createDevice",
  "listDevices",
  "rotateDeviceToken",
  "revokeDevice",
  "fetchPlan",
  "ackPlan",
]);

function garminUnavailable(code: string): VerifiedIdentityBudgetResult {
  const safeCode = /^[a-z0-9_]{1,64}$/.test(code) ? code : "rpc_rejected";
  console.warn("Garmin gateway budget unavailable", { code: safeCode });
  return { status: "unavailable", reason: safeCode };
}

function garminGatewayShard(
  lane: GarminGatewayBudgetLane,
  action: string,
  sourceHint: string,
): number | null {
  if (
    !GARMIN_GATEWAY_ACTIONS.has(action) || sourceHint.length > 4_096 ||
    sourceHint.length === 0
  ) {
    return null;
  }
  // FNV-1a is deliberately only a cheap fixed-shard selector. No raw bearer
  // or capability crosses the database boundary, and the independent global
  // lane bounds total work even when an attacker deliberately spreads shards.
  let hash = 0x811c9dc5;
  const input = `${lane}\n${action}\n${sourceHint}`;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash % 64;
}

export async function debitGarminGatewayBudget(
  lane: GarminGatewayBudgetLane,
  action: string,
  sourceHint: string,
  projectUrl: string,
  administrativeKey: string,
): Promise<VerifiedIdentityBudgetResult> {
  const shard = garminGatewayShard(lane, action, sourceHint);
  if (shard === null) return garminUnavailable("invalid_source_hint");

  const headers: Record<string, string> = {
    apikey: administrativeKey,
    "Content-Type": "application/json",
  };
  if (!administrativeKey.startsWith("sb_secret_")) {
    headers.Authorization = `Bearer ${administrativeKey}`;
  }

  try {
    const response = await fetch(
      `${projectUrl}/rest/v1/rpc/garmin_gateway_preauth_debit`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({ p_lane: lane, p_shard: shard }),
        signal: AbortSignal.timeout(5_000),
      },
    );
    if (!response.ok) {
      const errorBody = await response.clone().json().catch(() => null) as
        | Record<string, unknown>
        | null;
      const responseCode = typeof errorBody?.code === "string" &&
          /^[A-Za-z0-9]{1,16}$/.test(errorBody.code)
        ? errorBody.code.toLowerCase()
        : "unknown";
      return garminUnavailable(`rpc_${response.status}_${responseCode}`);
    }

    const result = await response.json() as Record<string, unknown>;
    if (
      result.version === 1 && result.allowed === true &&
      result.retryAfter === 0
    ) {
      return { status: "allowed" };
    }
    if (
      result.version === 1 && result.allowed === false &&
      Number.isInteger(result.retryAfter) && Number(result.retryAfter) >= 1 &&
      Number(result.retryAfter) <= 60
    ) {
      return {
        status: "rate_limited",
        retryAfter: Number(result.retryAfter),
      };
    }
    return garminUnavailable("invalid_rpc_response");
  } catch {
    return garminUnavailable("rpc_transport_error");
  }
}
