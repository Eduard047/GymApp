const SOURCE_PATTERN = /^[0-9a-f:.]{1,64}$/i;
const HMAC_SECRET_PATTERN = /^[0-9a-f]{64}$/i;

export type PreauthBudgetResult =
  | { status: "allowed" }
  | { status: "rate_limited"; retryAfter: number }
  | {
    status: "unavailable";
    reason: string;
  };

function unavailable(code: string): PreauthBudgetResult {
  const safeCode = /^[a-z0-9_]{1,64}$/.test(code) ? code : "rpc_rejected";
  // A bounded code is operationally useful without logging the source address,
  // its HMAC, any credential, or a database response body.
  console.warn("Gateway pre-authentication budget unavailable", {
    code: safeCode,
  });
  return { status: "unavailable", reason: safeCode };
}

function sourceAddress(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",", 1)[0]
    ?.trim();
  const candidate = request.headers.get("cf-connecting-ip")?.trim() ||
    request.headers.get("x-real-ip")?.trim() || forwarded || "unknown";
  return SOURCE_PATTERN.test(candidate) ? candidate.toLowerCase() : "unknown";
}

function bytesFromHex(value: string): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(new ArrayBuffer(value.length / 2));
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

async function sourceHash(request: Request, route: string): Promise<string | null> {
  const secret = Deno.env.get("GATEWAY_PREAUTH_HMAC_SECRET")?.trim() ?? "";
  if (!HMAC_SECRET_PATTERN.test(secret)) return null;
  const key = await crypto.subtle.importKey(
    "raw",
    bytesFromHex(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${route}\n${sourceAddress(request)}`),
  ));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function debitPreauthBudget(
  request: Request,
  route: "delete_account" | "social_live" | "garmin_legacy",
  projectUrl: string,
  administrativeKey: string,
): Promise<PreauthBudgetResult> {
  const hash = await sourceHash(request, route);
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
