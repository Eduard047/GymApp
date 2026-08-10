import { generateRequestDetails } from "web-push-neo";

const MAX_PROVIDER_RESPONSE_BYTES = 64 * 1024;
const PROVIDER_TIMEOUT_MS = 10_000;
const MAX_TTL_SECONDS = 7 * 24 * 60 * 60;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BINDING_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FCM_PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const SERVICE_EMAIL_PATTERN =
  /^[^@\s]{1,128}@[^@\s]{1,128}\.iam\.gserviceaccount\.com$/;
const APNS_IDENTIFIER_PATTERN = /^[A-Z0-9]{10}$/;
const BUNDLE_ID_PATTERN = /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
const BASE64URL_PATTERN = /^[A-Za-z0-9_-]+$/;
const APNS_TOKEN_PATTERN = /^(?:[0-9a-f]{2}){16,100}$/;
const FCM_TOKEN_PATTERN = /^[A-Za-z0-9_:-]{32,4096}$/;
const LIVE_ROOM_PATTERN = /^lr_[0-9a-f]{32}$/;
const FRIENDSHIP_PATTERN = /^f_[0-9a-f]{32}$/;
const WORKOUT_INVITE_PATTERN = /^wi_[0-9a-f]{32}$/;
const OBJECT_ID_PATTERN = /^[A-Za-z0-9:_-]{1,128}$/;
const COLLAPSE_KEY_PATTERN = /^[A-Za-z0-9_-]{1,32}$/;

export const PUSH_EVENT_TYPES = Object.freeze(
  [
    "friend_request_received",
    "friend_request_accepted",
    "workout_invite_received",
    "workout_invite_accepted",
    "live_invite_received",
    "live_invite_accepted",
    "live_room_started",
    "live_participant_finished",
    "live_room_closed",
  ] as const,
);

export type PushEventType = typeof PUSH_EVENT_TYPES[number];
export type Fetcher = typeof fetch;

export type ClaimedDelivery = {
  delivery_id: string;
  lease_token: string;
  outbox_id: string;
  event_type: string;
  object_id: string;
  object_revision: number;
  collapse_key: string;
  priority: "normal" | "high";
  expires_at: string;
  provider: "fcm" | "apns" | "web_push";
  environment: "production" | "sandbox";
  binding_id: string;
  provider_token: string;
  web_push_p256dh: string | null;
  web_push_auth: string | null;
  locale: string | null;
  attempt_count: number;
};

export type DeliveryResult =
  | { outcome: "delivered"; providerStatus: number }
  | {
    outcome: "retry" | "invalid" | "permanent";
    errorCode: string;
    providerStatus: number | null;
    retryAfterSeconds?: number;
  };

export type PushProvider = "fcm" | "apns" | "web_push";

export type ProviderConfig = {
  fcm: {
    projectId: string;
    clientEmail: string;
    privateKey: CryptoKey;
  } | null;
  apns: {
    teamId: string;
    keyId: string;
    bundleId: string;
    privateKey: CryptoKey;
  } | null;
  webPush: {
    publicKey: string;
    privateKey: CryptoKey;
    contact: string;
  } | null;
};

type EnvReader = (name: string) => string | undefined;
type Copy = { title: string; body: string };

class ProviderConfigurationError extends Error {}

const COPY: Readonly<
  Record<"en" | "uk" | "ru", Readonly<Record<PushEventType, Copy>>>
> = {
  en: {
    friend_request_received: {
      title: "New friend request",
      body: "Open GymApp to respond.",
    },
    friend_request_accepted: {
      title: "Friend request accepted",
      body: "Your friend is now in GymApp.",
    },
    workout_invite_received: {
      title: "Workout invitation",
      body: "A friend shared a workout with you.",
    },
    workout_invite_accepted: {
      title: "Workout accepted",
      body: "Your friend accepted the workout.",
    },
    live_invite_received: {
      title: "Live workout invitation",
      body: "Open GymApp to join the workout.",
    },
    live_invite_accepted: {
      title: "Friend joined",
      body: "Your live workout is ready.",
    },
    live_room_started: {
      title: "Workout started",
      body: "Your shared live workout has started.",
    },
    live_participant_finished: {
      title: "Friend finished",
      body: "Your friend finished the live workout.",
    },
    live_room_closed: {
      title: "Live workout ended",
      body: "Open GymApp to view the latest state.",
    },
  },
  uk: {
    friend_request_received: {
      title: "Новий запит у друзі",
      body: "Відкрий GymApp, щоб відповісти.",
    },
    friend_request_accepted: {
      title: "Запит у друзі прийнято",
      body: "Друг тепер доступний у GymApp.",
    },
    workout_invite_received: {
      title: "Запрошення на тренування",
      body: "Друг поділився з тобою тренуванням.",
    },
    workout_invite_accepted: {
      title: "Тренування прийнято",
      body: "Друг прийняв твоє тренування.",
    },
    live_invite_received: {
      title: "Запрошення на спільне тренування",
      body: "Відкрий GymApp, щоб приєднатися.",
    },
    live_invite_accepted: {
      title: "Друг приєднався",
      body: "Спільне тренування готове до старту.",
    },
    live_room_started: {
      title: "Тренування почалося",
      body: "Спільне тренування вже розпочато.",
    },
    live_participant_finished: {
      title: "Друг завершив тренування",
      body: "Переглянь актуальний стан у GymApp.",
    },
    live_room_closed: {
      title: "Спільне тренування завершено",
      body: "Відкрий GymApp, щоб переглянути стан.",
    },
  },
  ru: {
    friend_request_received: {
      title: "Новая заявка в друзья",
      body: "Открой GymApp, чтобы ответить.",
    },
    friend_request_accepted: {
      title: "Заявка в друзья принята",
      body: "Друг теперь доступен в GymApp.",
    },
    workout_invite_received: {
      title: "Приглашение на тренировку",
      body: "Друг поделился с тобой тренировкой.",
    },
    workout_invite_accepted: {
      title: "Тренировка принята",
      body: "Друг принял твою тренировку.",
    },
    live_invite_received: {
      title: "Приглашение на совместную тренировку",
      body: "Открой GymApp, чтобы присоединиться.",
    },
    live_invite_accepted: {
      title: "Друг присоединился",
      body: "Совместная тренировка готова к старту.",
    },
    live_room_started: {
      title: "Тренировка началась",
      body: "Совместная тренировка уже началась.",
    },
    live_participant_finished: {
      title: "Друг закончил тренировку",
      body: "Посмотри актуальное состояние в GymApp.",
    },
    live_room_closed: {
      title: "Совместная тренировка завершена",
      body: "Открой GymApp, чтобы посмотреть состояние.",
    },
  },
};

const LIVE_KIND: Readonly<Partial<Record<PushEventType, string>>> = Object
  .freeze({
    live_invite_received: "invite",
    live_invite_accepted: "joined",
    live_room_started: "started",
    live_participant_finished: "participant_finished",
    live_room_closed: "room_closed",
  });

let fcmAccessTokenCache: {
  identity: string;
  token: string;
  refreshAfter: number;
} | null = null;
let apnsProviderTokenCache: {
  identity: string;
  token: string;
  refreshAfter: number;
} | null = null;

function requiredEnv(readEnv: EnvReader, name: string): string {
  const value = readEnv(name)?.trim();
  if (!value) throw new ProviderConfigurationError(`Missing ${name}`);
  return value;
}

function decodeBase64Url(value: string): Uint8Array {
  if (!BASE64URL_PATTERN.test(value)) {
    throw new ProviderConfigurationError("Invalid base64url value");
  }
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  try {
    return Uint8Array.from(
      atob(padded),
      (character) => character.charCodeAt(0),
    );
  } catch {
    throw new ProviderConfigurationError("Invalid base64url value");
  }
}

function encodeBase64Url(value: Uint8Array | string): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/u,
    "",
  );
}

function decodePkcs8Pem(value: string): Uint8Array<ArrayBuffer> {
  const normalized = value.includes("\\n")
    ? value.replaceAll("\\n", "\n")
    : value;
  const privateKeyLabel = ["PRIVATE", "KEY"].join(" ");
  const match = new RegExp(
    `^-----BEGIN ${privateKeyLabel}-----\\s+([A-Za-z0-9+/=\\s]+)\\s+-----END ${privateKeyLabel}-----$`,
    "u",
  ).exec(normalized.trim());
  if (!match) {
    throw new ProviderConfigurationError("Private key must be PKCS#8 PEM");
  }
  const base64 = match[1].replaceAll(/\s/gu, "");
  if (base64.length < 64 || base64.length > 16_384) {
    throw new ProviderConfigurationError("Private key length is invalid");
  }
  try {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    throw new ProviderConfigurationError("Private key is invalid");
  }
}

async function importRsaPrivateKey(pem: string): Promise<CryptoKey> {
  try {
    return await crypto.subtle.importKey(
      "pkcs8",
      decodePkcs8Pem(pem),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
  } catch (error) {
    if (error instanceof ProviderConfigurationError) throw error;
    throw new ProviderConfigurationError("FCM private key is invalid");
  }
}

async function importEcPkcs8PrivateKey(pem: string): Promise<CryptoKey> {
  try {
    return await crypto.subtle.importKey(
      "pkcs8",
      decodePkcs8Pem(pem),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
  } catch (error) {
    if (error instanceof ProviderConfigurationError) throw error;
    throw new ProviderConfigurationError("APNs private key is invalid");
  }
}

async function importVapidPrivateKey(
  publicValue: string,
  privateValue: string,
): Promise<CryptoKey> {
  const publicBytes = decodeBase64Url(publicValue);
  const privateBytes = decodeBase64Url(privateValue);
  if (
    publicBytes.length !== 65 || publicBytes[0] !== 4 ||
    privateBytes.length !== 32
  ) {
    throw new ProviderConfigurationError("VAPID key material is invalid");
  }
  try {
    return await crypto.subtle.importKey(
      "jwk",
      {
        kty: "EC",
        crv: "P-256",
        x: encodeBase64Url(publicBytes.slice(1, 33)),
        y: encodeBase64Url(publicBytes.slice(33, 65)),
        d: encodeBase64Url(privateBytes),
        ext: true,
      },
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
  } catch {
    throw new ProviderConfigurationError("VAPID private key is invalid");
  }
}

function validVapidContact(value: string): boolean {
  if (value.length > 256 || /[\u0000-\u0020\u007f]/u.test(value)) return false;
  if (/^mailto:[^@\s]+@[^@\s]+\.[^@\s]+$/u.test(value)) return true;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password &&
      !url.hash;
  } catch {
    return false;
  }
}

export async function loadProviderConfig(
  readEnv: EnvReader,
  requestedProviders: readonly PushProvider[] = ["fcm", "apns", "web_push"],
): Promise<ProviderConfig> {
  const requested = new Set<PushProvider>(requestedProviders);
  if (requested.size !== requestedProviders.length) {
    throw new ProviderConfigurationError("Provider selection is invalid");
  }
  let fcm: ProviderConfig["fcm"] = null;
  let apns: ProviderConfig["apns"] = null;
  let webPush: ProviderConfig["webPush"] = null;
  if (requested.has("fcm")) {
    const projectId = requiredEnv(readEnv, "FCM_PROJECT_ID");
    const clientEmail = requiredEnv(readEnv, "FCM_CLIENT_EMAIL");
    if (
      !FCM_PROJECT_PATTERN.test(projectId) ||
      !SERVICE_EMAIL_PATTERN.test(clientEmail)
    ) {
      throw new ProviderConfigurationError("FCM identity is invalid");
    }
    fcm = {
      projectId,
      clientEmail,
      privateKey: await importRsaPrivateKey(
        requiredEnv(readEnv, "FCM_PRIVATE_KEY"),
      ),
    };
  }
  if (requested.has("apns")) {
    const teamId = requiredEnv(readEnv, "APNS_TEAM_ID");
    const keyId = requiredEnv(readEnv, "APNS_KEY_ID");
    const bundleId = requiredEnv(readEnv, "APNS_BUNDLE_ID");
    if (
      !APNS_IDENTIFIER_PATTERN.test(teamId) ||
      !APNS_IDENTIFIER_PATTERN.test(keyId) ||
      bundleId.length > 255 || !BUNDLE_ID_PATTERN.test(bundleId)
    ) {
      throw new ProviderConfigurationError("APNs identity is invalid");
    }
    apns = {
      teamId,
      keyId,
      bundleId,
      privateKey: await importEcPkcs8PrivateKey(
        requiredEnv(readEnv, "APNS_PRIVATE_KEY"),
      ),
    };
  }
  if (requested.has("web_push")) {
    const publicKey = requiredEnv(readEnv, "WEBPUSH_VAPID_PUBLIC_KEY");
    const privateValue = requiredEnv(readEnv, "WEBPUSH_VAPID_PRIVATE_KEY");
    const contact = requiredEnv(readEnv, "WEBPUSH_CONTACT");
    if (!validVapidContact(contact)) {
      throw new ProviderConfigurationError("Web Push contact is invalid");
    }
    webPush = {
      publicKey,
      privateKey: await importVapidPrivateKey(publicKey, privateValue),
      contact,
    };
  }
  return { fcm, apns, webPush };
}

async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  privateKey: CryptoKey,
  algorithm: AlgorithmIdentifier | EcdsaParams,
): Promise<string> {
  const signingInput = `${encodeBase64Url(JSON.stringify(header))}.${
    encodeBase64Url(JSON.stringify(payload))
  }`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      algorithm,
      privateKey,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${encodeBase64Url(signature)}`;
}

async function readBoundedText(response: Response): Promise<string> {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let total = 0;
  let result = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_PROVIDER_RESPONSE_BYTES) {
        await reader.cancel();
        throw new Error("provider_response_too_large");
      }
      result += decoder.decode(value, { stream: true });
    }
    result += decoder.decode();
    return result;
  } finally {
    reader.releaseLock();
  }
}

function jsonRecord(value: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(value) as unknown;
    return parsed !== null && typeof parsed === "object" &&
        !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

export function parseRetryAfter(
  value: string | null,
  now = Date.now(),
): number | undefined {
  if (!value || value.length > 128) return undefined;
  if (/^\d{1,10}$/u.test(value)) {
    return Math.max(1, Math.min(3_600, Number(value)));
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) return undefined;
  return Math.max(1, Math.min(3_600, Math.ceil((parsed - now) / 1_000)));
}

function languageFor(locale: string | null): "en" | "uk" | "ru" {
  const language = locale?.toLowerCase().split("-", 1)[0];
  return language === "uk" || language === "ru" ? language : "en";
}

export function notificationCopy(
  eventType: PushEventType,
  locale: string | null,
): Copy {
  return COPY[languageFor(locale)][eventType];
}

export function opaquePayload(
  delivery: Pick<
    ClaimedDelivery,
    "event_type" | "object_id" | "object_revision" | "binding_id"
  >,
) {
  const eventType = delivery.event_type as PushEventType;
  const liveKind = LIVE_KIND[eventType];
  if (liveKind) {
    return {
      version: 1,
      bindingId: delivery.binding_id,
      kind: liveKind,
      roomId: delivery.object_id,
      roomRevision: delivery.object_revision,
    };
  }
  return {
    version: 1,
    bindingId: delivery.binding_id,
    type: eventType,
    objectId: delivery.object_id,
    objectRevision: delivery.object_revision,
  };
}

function validClaim(value: ClaimedDelivery): boolean {
  if (value === null || typeof value !== "object") return false;
  const eventType = value.event_type as PushEventType;
  return isPushEventType(eventType) && UUID_PATTERN.test(value.delivery_id) &&
    UUID_PATTERN.test(value.lease_token) &&
    UUID_PATTERN.test(value.outbox_id) &&
    OBJECT_ID_PATTERN.test(value.object_id) &&
    ((eventType.startsWith("live_") &&
      LIVE_ROOM_PATTERN.test(value.object_id)) ||
      (eventType.startsWith("friend_") &&
        FRIENDSHIP_PATTERN.test(value.object_id)) ||
      (eventType.startsWith("workout_") &&
        WORKOUT_INVITE_PATTERN.test(value.object_id))) &&
    Number.isInteger(value.object_revision) && value.object_revision >= 0 &&
    value.object_revision <= 2_147_483_647 &&
    COLLAPSE_KEY_PATTERN.test(value.collapse_key) &&
    BINDING_ID_PATTERN.test(value.binding_id) &&
    (value.priority === "normal" || value.priority === "high") &&
    Number.isInteger(value.attempt_count) && value.attempt_count >= 1 &&
    value.attempt_count <= 8 &&
    Number.isFinite(Date.parse(value.expires_at)) &&
    ((value.provider === "fcm" && value.environment === "production" &&
      FCM_TOKEN_PATTERN.test(value.provider_token) &&
      value.web_push_p256dh === null &&
      value.web_push_auth === null) ||
      (value.provider === "apns" &&
        (value.environment === "production" ||
          value.environment === "sandbox") &&
        APNS_TOKEN_PATTERN.test(value.provider_token) &&
        value.web_push_p256dh === null &&
        value.web_push_auth === null) ||
      (value.provider === "web_push" && value.environment === "production" &&
        webPushEndpointAllowed(value.provider_token) &&
        typeof value.web_push_p256dh === "string" &&
        typeof value.web_push_auth === "string"));
}

function isPushEventType(value: string): value is PushEventType {
  return (PUSH_EVENT_TYPES as readonly string[]).includes(value);
}

export function webPushEndpointAllowed(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    value.length < 32 || value.length > 2_048 ||
    /[\u0000-\u0020\u007f]/u.test(value)
  ) return false;
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" || url.username || url.password || url.port ||
      url.hash ||
      !url.pathname.startsWith("/")
    ) return false;
    const host = url.hostname.toLowerCase();
    return host === "fcm.googleapis.com" ||
      host === "updates.push.services.mozilla.com" ||
      host === "web.push.apple.com" ||
      /^[a-z0-9-]+\.notify\.windows\.com$/u.test(host);
  } catch {
    return false;
  }
}

function ttlFor(delivery: ClaimedDelivery): number {
  return Math.max(
    0,
    Math.min(
      MAX_TTL_SECONDS,
      Math.floor((Date.parse(delivery.expires_at) - Date.now()) / 1_000),
    ),
  );
}

async function getFcmAccessToken(
  config: ProviderConfig,
  fetcher: Fetcher,
  force = false,
): Promise<string> {
  const fcm = config.fcm;
  if (!fcm) throw new ProviderConfigurationError("FCM is not configured");
  const identity = `${fcm.projectId}:${fcm.clientEmail}`;
  if (
    !force && fcmAccessTokenCache?.identity === identity &&
    fcmAccessTokenCache.refreshAfter > Date.now()
  ) {
    return fcmAccessTokenCache.token;
  }
  const nowSeconds = Math.floor(Date.now() / 1_000);
  const assertion = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: fcm.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: nowSeconds,
      exp: nowSeconds + 3_600,
    },
    fcm.privateKey,
    "RSASSA-PKCS1-v1_5",
  );
  const form = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });
  const response = await fetcher("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
    redirect: "error",
    signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
  });
  const body = jsonRecord(await readBoundedText(response));
  const token = body?.access_token;
  const expiresIn = Number(body?.expires_in);
  if (
    !response.ok || typeof token !== "string" || token.length < 32 ||
    token.length > 4_096 ||
    !Number.isInteger(expiresIn) || expiresIn < 300 || expiresIn > 7_200
  ) {
    throw new Error("fcm_oauth_failed");
  }
  fcmAccessTokenCache = {
    identity,
    token,
    refreshAfter: Date.now() + Math.max(60, expiresIn - 300) * 1_000,
  };
  return token;
}

async function getApnsProviderToken(
  config: ProviderConfig,
  force = false,
): Promise<string> {
  const apns = config.apns;
  if (!apns) throw new ProviderConfigurationError("APNs is not configured");
  const identity = `${apns.teamId}:${apns.keyId}`;
  if (
    !force && apnsProviderTokenCache?.identity === identity &&
    apnsProviderTokenCache.refreshAfter > Date.now()
  ) {
    return apnsProviderTokenCache.token;
  }
  const token = await signJwt(
    { alg: "ES256", kid: apns.keyId },
    { iss: apns.teamId, iat: Math.floor(Date.now() / 1_000) },
    apns.privateKey,
    { name: "ECDSA", hash: "SHA-256" },
  );
  apnsProviderTokenCache = {
    identity,
    token,
    refreshAfter: Date.now() + 50 * 60 * 1_000,
  };
  return token;
}

export async function vapidAuthorization(
  config: ProviderConfig,
  endpoint: string,
): Promise<string> {
  const webPush = config.webPush;
  if (!webPush) {
    throw new ProviderConfigurationError("Web Push is not configured");
  }
  const url = new URL(endpoint);
  const nowSeconds = Math.floor(Date.now() / 1_000);
  const token = await signJwt(
    { typ: "JWT", alg: "ES256" },
    {
      aud: url.origin,
      exp: nowSeconds + 12 * 60 * 60,
      sub: webPush.contact,
    },
    webPush.privateKey,
    { name: "ECDSA", hash: "SHA-256" },
  );
  return `vapid t=${token}, k=${webPush.publicKey}`;
}

export async function warmProviderCredentials(
  config: ProviderConfig,
  fetcher: Fetcher = fetch,
): Promise<void> {
  const warmups: Promise<unknown>[] = [];
  if (config.fcm) warmups.push(getFcmAccessToken(config, fetcher));
  if (config.apns) warmups.push(getApnsProviderToken(config));
  await Promise.all(warmups);
}

export type FcmFailureInfo = {
  code: string;
  tokenSpecific: boolean;
};

export function fcmFailureInfo(
  body: Record<string, unknown> | null,
): FcmFailureInfo | null {
  const error = body?.error;
  if (!error || typeof error !== "object" || Array.isArray(error)) return null;
  const details = (error as Record<string, unknown>).details;
  let fallback: FcmFailureInfo | null = null;
  if (Array.isArray(details)) {
    for (const detail of details) {
      if (detail && typeof detail === "object" && !Array.isArray(detail)) {
        const record = detail as Record<string, unknown>;
        const code = record.errorCode;
        if (typeof code === "string" && /^[A-Z_]{1,64}$/u.test(code)) {
          const tokenSpecific = record["@type"] ===
            "type.googleapis.com/google.firebase.fcm.v1.FcmError";
          if (tokenSpecific) return { code, tokenSpecific: true };
          fallback ??= { code, tokenSpecific: false };
        }
      }
    }
  }
  const status = (error as Record<string, unknown>).status;
  return fallback ?? (
    typeof status === "string" && /^[A-Z_]{1,64}$/u.test(status)
      ? { code: status, tokenSpecific: false }
      : null
  );
}

export function classifyFcmFailure(
  status: number,
  errorCode: string | null,
  retryAfter?: number,
  tokenSpecific = false,
): DeliveryResult {
  if (
    errorCode === "UNREGISTERED" ||
    (errorCode === "INVALID_ARGUMENT" && tokenSpecific)
  ) {
    return {
      outcome: "invalid",
      errorCode: `fcm_${errorCode.toLowerCase()}`,
      providerStatus: status,
    };
  }
  if (
    status === 429 || status >= 500 || errorCode === "QUOTA_EXCEEDED" ||
    errorCode === "UNAVAILABLE" || errorCode === "INTERNAL"
  ) {
    return {
      outcome: "retry",
      errorCode: "fcm_transient",
      providerStatus: status,
      retryAfterSeconds: retryAfter,
    };
  }
  if (status === 401 || status === 403) {
    return {
      outcome: "retry",
      errorCode: "fcm_auth",
      providerStatus: status,
      retryAfterSeconds: retryAfter ?? 3_600,
    };
  }
  return {
    outcome: "permanent",
    errorCode: "fcm_rejected",
    providerStatus: status,
  };
}

async function sendFcm(
  delivery: ClaimedDelivery,
  config: ProviderConfig,
  fetcher: Fetcher,
): Promise<DeliveryResult> {
  const fcm = config.fcm;
  if (!fcm) throw new ProviderConfigurationError("FCM is not configured");
  const requestBody = JSON.stringify(fcmDataMessage(delivery));
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const accessToken = await getFcmAccessToken(config, fetcher, attempt === 1);
    const response = await fetcher(
      `https://fcm.googleapis.com/v1/projects/${
        encodeURIComponent(fcm.projectId)
      }/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json; charset=utf-8",
        },
        body: requestBody,
        redirect: "error",
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
      },
    );
    const bodyText = await readBoundedText(response);
    if (response.ok) {
      return { outcome: "delivered", providerStatus: response.status };
    }
    if (response.status === 401 && attempt === 0) {
      fcmAccessTokenCache = null;
      continue;
    }
    const failure = fcmFailureInfo(jsonRecord(bodyText));
    return classifyFcmFailure(
      response.status,
      failure?.code ?? null,
      parseRetryAfter(response.headers.get("retry-after")),
      failure?.tokenSpecific ?? false,
    );
  }
  return {
    outcome: "retry",
    errorCode: "fcm_auth_retry",
    providerStatus: 401,
    retryAfterSeconds: 60,
  };
}

export function fcmDataMessage(delivery: ClaimedDelivery) {
  const data = Object.fromEntries(
    Object.entries(opaquePayload(delivery)).map(([key, value]) => [
      key,
      String(value),
    ]),
  );
  return {
    message: {
      token: delivery.provider_token,
      data,
      android: {
        collapse_key: delivery.collapse_key,
        priority: delivery.priority === "high" ? "HIGH" : "NORMAL",
        ttl: `${ttlFor(delivery)}s`,
      },
    },
  };
}

function apnsReason(body: Record<string, unknown> | null): string | null {
  const value = body?.reason;
  return typeof value === "string" && /^[A-Za-z0-9]{1,64}$/u.test(value)
    ? value
    : null;
}

export function classifyApnsFailure(
  status: number,
  reason: string | null,
  retryAfter?: number,
): DeliveryResult {
  if (status === 410 || reason === "Unregistered") {
    return {
      outcome: "invalid",
      errorCode: "apns_unregistered",
      providerStatus: status,
    };
  }
  if (
    status === 429 || status >= 500 || reason === "TooManyRequests" ||
    reason === "InternalServerError" || reason === "ServiceUnavailable"
  ) {
    return {
      outcome: "retry",
      errorCode: "apns_transient",
      providerStatus: status,
      retryAfterSeconds: retryAfter,
    };
  }
  if (status === 403) {
    return {
      outcome: "retry",
      errorCode: "apns_auth",
      providerStatus: status,
      retryAfterSeconds: retryAfter ?? 3_600,
    };
  }
  return {
    outcome: "permanent",
    errorCode: "apns_rejected",
    providerStatus: status,
  };
}

async function sendApns(
  delivery: ClaimedDelivery,
  config: ProviderConfig,
  fetcher: Fetcher,
): Promise<DeliveryResult> {
  const apns = config.apns;
  if (!apns) throw new ProviderConfigurationError("APNs is not configured");
  const body = JSON.stringify(apnsBackgroundPayload(delivery));
  const host = delivery.environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const providerToken = await getApnsProviderToken(config, attempt === 1);
    const response = await fetcher(
      `https://${host}/3/device/${delivery.provider_token}`,
      {
        method: "POST",
        headers: {
          authorization: `bearer ${providerToken}`,
          "apns-topic": apns.bundleId,
          "apns-push-type": "background",
          "apns-priority": "5",
          "apns-expiration": String(
            Math.floor(Date.parse(delivery.expires_at) / 1_000),
          ),
          "apns-collapse-id": delivery.collapse_key,
          "apns-id": delivery.outbox_id,
          "content-type": "application/json; charset=utf-8",
        },
        body,
        redirect: "error",
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
      },
    );
    const responseBody = jsonRecord(await readBoundedText(response));
    if (response.ok) {
      return { outcome: "delivered", providerStatus: response.status };
    }
    const reason = apnsReason(responseBody);
    if (
      response.status === 403 && reason === "ExpiredProviderToken" &&
      attempt === 0
    ) {
      apnsProviderTokenCache = null;
      continue;
    }
    return classifyApnsFailure(
      response.status,
      reason,
      parseRetryAfter(response.headers.get("retry-after")),
    );
  }
  return {
    outcome: "retry",
    errorCode: "apns_auth_retry",
    providerStatus: 403,
    retryAfterSeconds: 60,
  };
}

export function apnsBackgroundPayload(delivery: ClaimedDelivery) {
  return {
    aps: {
      "content-available": 1,
    },
    gymapp: opaquePayload(delivery),
  };
}

export function classifyWebPushFailure(
  status: number,
  retryAfter?: number,
): DeliveryResult {
  if (status === 404 || status === 410) {
    return {
      outcome: "invalid",
      errorCode: "web_push_unregistered",
      providerStatus: status,
    };
  }
  if (status === 429 || status >= 500) {
    return {
      outcome: "retry",
      errorCode: "web_push_transient",
      providerStatus: status,
      retryAfterSeconds: retryAfter,
    };
  }
  if (status === 401 || status === 403) {
    return {
      outcome: "retry",
      errorCode: "web_push_auth",
      providerStatus: status,
      retryAfterSeconds: retryAfter ?? 3_600,
    };
  }
  return {
    outcome: "permanent",
    errorCode: "web_push_rejected",
    providerStatus: status,
  };
}

async function sendWebPush(
  delivery: ClaimedDelivery,
  config: ProviderConfig,
  fetcher: Fetcher,
): Promise<DeliveryResult> {
  if (
    !webPushEndpointAllowed(delivery.provider_token) ||
    !delivery.web_push_p256dh || !delivery.web_push_auth
  ) {
    return {
      outcome: "invalid",
      errorCode: "web_push_subscription_invalid",
      providerStatus: null,
    };
  }
  const payload = JSON.stringify({
    version: 1,
    notification: {
      ...notificationCopy(
        delivery.event_type as PushEventType,
        delivery.locale,
      ),
      tag: delivery.collapse_key,
    },
    data: opaquePayload(delivery),
  });
  let details;
  try {
    details = await generateRequestDetails(
      {
        endpoint: delivery.provider_token,
        keys: {
          p256dh: delivery.web_push_p256dh,
          auth: delivery.web_push_auth,
        },
      },
      payload,
      {
        TTL: ttlFor(delivery),
        urgency: delivery.priority === "high" ? "high" : "normal",
        topic: delivery.collapse_key,
      },
    );
  } catch {
    return {
      outcome: "invalid",
      errorCode: "web_push_subscription_invalid",
      providerStatus: null,
    };
  }
  details.headers.Authorization = await vapidAuthorization(
    config,
    details.endpoint,
  );
  const response = await fetcher(details.endpoint, {
    method: details.method,
    headers: details.headers,
    body: details.body,
    redirect: "error",
    signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
  });
  await readBoundedText(response);
  if (response.ok) {
    return { outcome: "delivered", providerStatus: response.status };
  }
  return classifyWebPushFailure(
    response.status,
    parseRetryAfter(response.headers.get("retry-after")),
  );
}

export async function sendDelivery(
  delivery: ClaimedDelivery,
  config: ProviderConfig,
  fetcher: Fetcher = fetch,
): Promise<DeliveryResult> {
  if (!validClaim(delivery)) {
    return {
      outcome: "permanent",
      errorCode: "invalid_claim",
      providerStatus: null,
    };
  }
  if (ttlFor(delivery) <= 0) {
    return {
      outcome: "permanent",
      errorCode: "notification_expired",
      providerStatus: null,
    };
  }
  try {
    if (delivery.provider === "fcm") {
      return await sendFcm(delivery, config, fetcher);
    }
    if (delivery.provider === "apns") {
      return await sendApns(delivery, config, fetcher);
    }
    return await sendWebPush(delivery, config, fetcher);
  } catch (error) {
    if (error instanceof ProviderConfigurationError) {
      return {
        outcome: "retry",
        errorCode: "provider_configuration",
        providerStatus: null,
        retryAfterSeconds: 3_600,
      };
    }
    return {
      outcome: "retry",
      errorCode: "provider_network",
      providerStatus: null,
    };
  }
}
