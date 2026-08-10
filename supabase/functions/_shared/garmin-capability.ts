const ACCOUNT_BINDING_PATTERN = /^[a-f0-9]{64}$/;
const DEVICE_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const NONCE_PATTERN = /^[a-f0-9]{64}$/;
const TAG_PATTERN = /^[a-f0-9]{64}$/;
const SECRET_PATTERN = /^[a-f0-9]{64}$/;
const CAPABILITY_PATTERN =
  /^g3\.([a-f0-9]{64})\.([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.([a-f0-9]{64})\.([a-f0-9]{64})$/;

export type GarminCapability = {
  accountBinding: string;
  deviceId: string;
  nonce: string;
};

type ParsedGarminCapability = GarminCapability & {
  tag: string;
  signedPayload: string;
};

type CreateGarminCapabilityInput = {
  userId: unknown;
  deviceId: unknown;
  nonce: unknown;
  secretHex: unknown;
};

function hexToBytes(value: unknown): Uint8Array<ArrayBuffer> | null {
  if (typeof value !== "string" || value.length % 2 !== 0) return null;
  const bytes = new Uint8Array(new ArrayBuffer(value.length / 2));
  for (let index = 0; index < bytes.length; index += 1) {
    const byte = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
    if (!Number.isInteger(byte)) return null;
    bytes[index] = byte;
  }
  return bytes;
}

function bytesToHex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function importHmacKey(secretHex: unknown): Promise<CryptoKey | null> {
  if (typeof secretHex !== "string") return null;
  if (!SECRET_PATTERN.test(secretHex)) return null;
  const secret = hexToBytes(secretHex);
  if (!secret) return null;
  return await crypto.subtle.importKey(
    "raw",
    secret,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export function parseGarminCapability(
  value: unknown,
): ParsedGarminCapability | null {
  if (typeof value !== "string" || value.length !== 234) return null;
  const match = CAPABILITY_PATTERN.exec(value);
  if (!match) return null;
  return {
    accountBinding: match[1],
    deviceId: match[2],
    nonce: match[3],
    tag: match[4],
    signedPayload: value.slice(0, 169),
  };
}

export async function deriveGarminAccountBinding(
  userId: unknown,
): Promise<string | null> {
  if (typeof userId !== "string") return null;
  const normalized = userId.toLowerCase();
  if (!DEVICE_ID_PATTERN.test(normalized)) return null;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  return bytesToHex(digest);
}

export async function createGarminCapability({
  userId,
  deviceId,
  nonce,
  secretHex,
}: CreateGarminCapabilityInput): Promise<string | null> {
  const accountBinding = await deriveGarminAccountBinding(userId);
  const normalizedDeviceId = typeof deviceId === "string"
    ? deviceId.toLowerCase()
    : "";
  if (
    !accountBinding || !DEVICE_ID_PATTERN.test(normalizedDeviceId) ||
    typeof nonce !== "string" ||
    !NONCE_PATTERN.test(nonce)
  ) {
    return null;
  }
  const key = await importHmacKey(secretHex);
  if (!key) return null;
  const signedPayload = `g3.${accountBinding}.${normalizedDeviceId}.${nonce}`;
  const tag = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signedPayload),
  );
  return `${signedPayload}.${bytesToHex(tag)}`;
}

export async function verifyGarminCapability(
  value: unknown,
  secretHex: unknown,
): Promise<GarminCapability | null> {
  const parsed = parseGarminCapability(value);
  if (
    !parsed || !ACCOUNT_BINDING_PATTERN.test(parsed.accountBinding) ||
    !DEVICE_ID_PATTERN.test(parsed.deviceId) ||
    !NONCE_PATTERN.test(parsed.nonce) || !TAG_PATTERN.test(parsed.tag)
  ) {
    return null;
  }
  const key = await importHmacKey(secretHex);
  const tag = hexToBytes(parsed.tag);
  if (!key || !tag) return null;
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    tag,
    new TextEncoder().encode(parsed.signedPayload),
  );
  return valid
    ? {
      accountBinding: parsed.accountBinding,
      deviceId: parsed.deviceId,
      nonce: parsed.nonce,
    }
    : null;
}
