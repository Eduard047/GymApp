import {
  apnsBackgroundPayload,
  classifyApnsFailure,
  classifyFcmFailure,
  classifyWebPushFailure,
  fcmDataMessage,
  fcmFailureInfo,
  loadProviderConfig,
  notificationCopy,
  opaquePayload,
  parseRetryAfter,
  vapidAuthorization,
  webPushEndpointAllowed,
} from "./providers.ts";
import {
  constantTimeEqual,
  loadDispatchCredentials,
  serviceRoleFetch,
} from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
    );
  }
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/u,
    "",
  );
}

function pem(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const encoded = btoa(binary).match(/.{1,64}/gu)?.join("\n") ?? "";
  const privateKeyLabel = ["PRIVATE", "KEY"].join(" ");
  return `-----BEGIN ${privateKeyLabel}-----\n${encoded}\n-----END ${privateKeyLabel}-----`;
}

function decodeBase64Url(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

Deno.test("provider payload contains only opaque bounded invalidation fields", () => {
  const bindingId = "55555555-5555-4555-8555-555555555555";
  const live = opaquePayload({
    event_type: "live_room_started",
    object_id: `lr_${"a".repeat(32)}`,
    object_revision: 9,
    binding_id: bindingId,
  });
  assertEquals(live, {
    version: 1,
    bindingId,
    kind: "started",
    roomId: `lr_${"a".repeat(32)}`,
    roomRevision: 9,
  }, "live payload");
  const social = opaquePayload({
    event_type: "friend_request_received",
    object_id: `f_${"b".repeat(32)}`,
    object_revision: 2,
    binding_id: bindingId,
  });
  assertEquals(social, {
    version: 1,
    bindingId,
    type: "friend_request_received",
    objectId: `f_${"b".repeat(32)}`,
    objectRevision: 2,
  }, "social payload");
  const authUserId = "77777777-7777-4777-8777-777777777777";
  const privateClaimLike = {
    event_type: "workout_invite_received",
    object_id: `wi_${"c".repeat(32)}`,
    object_revision: 3,
    binding_id: bindingId,
    user_id: authUserId,
    access_token: "synthetic-access-token",
    workout: { weight: 120, reps: 8 },
  };
  const workoutInvite = opaquePayload(privateClaimLike);
  assertEquals(workoutInvite, {
    version: 1,
    bindingId,
    type: "workout_invite_received",
    objectId: `wi_${"c".repeat(32)}`,
    objectRevision: 3,
  }, "workout invitation payload");
  const encodedPayloads = JSON.stringify({ live, social, workoutInvite });
  assert(
    !encodedPayloads.includes("user") && !encodedPayloads.includes(authUserId),
    "payload must not contain user identifiers",
  );
  assert(
    !/(?:access[_-]?token|refresh[_-]?token|provider[_-]?token|weight|reps|email)/iu
      .test(encodedPayloads),
    "payload must not contain auth material or private workout data",
  );
});

Deno.test("localized copies are static and do not interpolate private data", () => {
  assertEquals(
    notificationCopy("live_invite_received", "ru-RU").title,
    "Приглашение на совместную тренировку",
    "Russian title",
  );
  assertEquals(
    notificationCopy("live_invite_received", "uk-UA").title,
    "Запрошення на спільне тренування",
    "Ukrainian title",
  );
  assertEquals(
    notificationCopy("live_invite_received", "de-DE").title,
    "Live workout invitation",
    "English fallback",
  );
});

Deno.test("native payloads are data-only until the bound app validates them", () => {
  const delivery = {
    delivery_id: "11111111-1111-4111-8111-111111111111",
    lease_token: "22222222-2222-4222-8222-222222222222",
    outbox_id: "33333333-3333-4333-8333-333333333333",
    event_type: "live_room_started",
    object_id: `lr_${"a".repeat(32)}`,
    object_revision: 4,
    collapse_key: "live_room_started",
    priority: "high" as const,
    expires_at: "2026-08-11T00:00:00Z",
    provider: "fcm" as const,
    environment: "production" as const,
    binding_id: "44444444-4444-4444-8444-444444444444",
    provider_token: "fcm_token_abcdefghijklmnopqrstuvwxyz0123456789",
    web_push_p256dh: null,
    web_push_auth: null,
    locale: "ru-RU",
    attempt_count: 1,
  };
  const fcm = fcmDataMessage(delivery);
  const apns = apnsBackgroundPayload({ ...delivery, provider: "apns" });
  const nativePayloads = JSON.stringify({ fcm, apns });
  assert(!nativePayloads.includes("notification"), "FCM must not auto-render");
  assert(!nativePayloads.includes("alert"), "APNs must not auto-render");
  assert(
    !nativePayloads.includes("sound"),
    "APNs must not play before validation",
  );
  assertEquals(apns.aps, { "content-available": 1 }, "background APNs aps");
  assertEquals(fcm.message.data.bindingId, delivery.binding_id, "FCM binding");
});

Deno.test("Web Push endpoints are HTTPS allowlisted and SSRF lookalikes fail closed", () => {
  for (
    const endpoint of [
      "https://fcm.googleapis.com/fcm/send/abcdefghijklmnopqrstuvwxyz0123456789",
      "https://updates.push.services.mozilla.com/wpush/v2/abcdefghijklmnopqrstuvwxyz",
      "https://web.push.apple.com/QHabcdefghijklmnopqrstuvwxyz0123456789",
      "https://db5.notify.windows.com/w/?token=abcdefghijklmnopqrstuvwxyz",
    ]
  ) assert(webPushEndpointAllowed(endpoint), `allowed endpoint ${endpoint}`);
  for (
    const endpoint of [
      undefined,
      null,
      // nosemgrep: gymapp-hardcoded-cleartext-url -- Intentional denied cleartext fixture.
      "http://fcm.googleapis.com/fcm/send/abcdefghijklmnopqrstuvwxyz0123456789",
      "https://fcm.googleapis.com.evil.example/fcm/send/abcdefghijklmnopqrstuvwxyz",
      "https://user@fcm.googleapis.com/fcm/send/abcdefghijklmnopqrstuvwxyz",
      "https://fcm.googleapis.com:444/fcm/send/abcdefghijklmnopqrstuvwxyz",
      "https://127.0.0.1/fcm/send/abcdefghijklmnopqrstuvwxyz0123456789",
    ]
  ) assert(!webPushEndpointAllowed(endpoint), `denied endpoint ${endpoint}`);
});

Deno.test("provider response classification revokes only dead registrations and bounds retry", () => {
  assertEquals(classifyFcmFailure(404, "UNREGISTERED"), {
    outcome: "invalid",
    errorCode: "fcm_unregistered",
    providerStatus: 404,
  }, "FCM invalid");
  assertEquals(classifyFcmFailure(400, "INVALID_ARGUMENT"), {
    outcome: "permanent",
    errorCode: "fcm_rejected",
    providerStatus: 400,
  }, "generic FCM invalid argument must not revoke a valid token");
  assertEquals(classifyFcmFailure(400, "INVALID_ARGUMENT", undefined, true), {
    outcome: "invalid",
    errorCode: "fcm_invalid_argument",
    providerStatus: 400,
  }, "token-specific FCM invalid argument may revoke the dead token");
  assertEquals(classifyFcmFailure(403, "SENDER_ID_MISMATCH"), {
    outcome: "retry",
    errorCode: "fcm_auth",
    providerStatus: 403,
    retryAfterSeconds: 3_600,
  }, "sender configuration mismatch must not revoke registrations");
  assertEquals(classifyApnsFailure(410, "Unregistered"), {
    outcome: "invalid",
    errorCode: "apns_unregistered",
    providerStatus: 410,
  }, "APNs invalid");
  assertEquals(classifyApnsFailure(400, "DeviceTokenNotForTopic"), {
    outcome: "permanent",
    errorCode: "apns_rejected",
    providerStatus: 400,
  }, "APNs topic configuration must not revoke a valid token");
  assertEquals(classifyApnsFailure(400, "BadDeviceToken"), {
    outcome: "permanent",
    errorCode: "apns_rejected",
    providerStatus: 400,
  }, "APNs environment mismatch must not revoke a registration");
  assertEquals(classifyWebPushFailure(410), {
    outcome: "invalid",
    errorCode: "web_push_unregistered",
    providerStatus: 410,
  }, "Web Push invalid");
  assertEquals(classifyWebPushFailure(503, 120), {
    outcome: "retry",
    errorCode: "web_push_transient",
    providerStatus: 503,
    retryAfterSeconds: 120,
  }, "Web Push retry");
  assertEquals(classifyFcmFailure(403, "PERMISSION_DENIED"), {
    outcome: "retry",
    errorCode: "fcm_auth",
    providerStatus: 403,
    retryAfterSeconds: 3_600,
  }, "FCM credential repair remains retryable");
  assertEquals(classifyApnsFailure(403, "InvalidProviderToken"), {
    outcome: "retry",
    errorCode: "apns_auth",
    providerStatus: 403,
    retryAfterSeconds: 3_600,
  }, "APNs credential repair remains retryable");
  assertEquals(parseRetryAfter("999999"), 3_600, "numeric retry bound");
});

Deno.test("FCM error details distinguish bad payloads from dead tokens", () => {
  assertEquals(
    fcmFailureInfo({
      error: {
        status: "INVALID_ARGUMENT",
        details: [{
          "@type": "type.googleapis.com/google.rpc.BadRequest",
          fieldViolations: [{ field: "message.data", description: "invalid" }],
        }],
      },
    }),
    { code: "INVALID_ARGUMENT", tokenSpecific: false },
    "bad payload",
  );
  assertEquals(
    fcmFailureInfo({
      error: {
        status: "INVALID_ARGUMENT",
        details: [{
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "INVALID_ARGUMENT",
        }],
      },
    }),
    { code: "INVALID_ARGUMENT", tokenSpecific: true },
    "dead token detail",
  );
});

Deno.test("dispatcher secret comparison handles equal, unequal, and different-length values", () => {
  assert(constantTimeEqual("a".repeat(43), "a".repeat(43)), "equal token");
  assert(
    !constantTimeEqual("a".repeat(43), `${"a".repeat(42)}b`),
    "unequal token",
  );
  assert(
    !constantTimeEqual("a".repeat(43), "a".repeat(44)),
    "different length",
  );
});

Deno.test("dispatcher ingress key stays separate from the Supabase service key", () => {
  const serviceKey = `sb_secret_${"s".repeat(48)}`;
  const dispatchServerKey = "d".repeat(43);
  const env = new Map<string, string>([
    ["SUPABASE_SECRET_KEYS", JSON.stringify({ default: serviceKey })],
    ["PUSH_DISPATCH_SERVER_KEY", dispatchServerKey],
  ]);
  assertEquals(
    loadDispatchCredentials((name) => env.get(name)),
    { serviceKey, dispatchServerKey },
    "dedicated ingress and internal service credentials",
  );

  env.set("PUSH_DISPATCH_SERVER_KEY", serviceKey);
  assertEquals(
    loadDispatchCredentials((name) => env.get(name)),
    null,
    "service key reuse must fail closed",
  );

  env.delete("PUSH_DISPATCH_SERVER_KEY");
  assertEquals(
    loadDispatchCredentials((name) => env.get(name)),
    null,
    "missing dedicated ingress key must fail closed",
  );
});

Deno.test("modern Supabase secret keys never enter the JWT Authorization header", async () => {
  const captures: Headers[] = [];
  const baseFetch: typeof fetch = (_input, init) => {
    captures.push(new Headers(init?.headers));
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const modern = `sb_secret_${"a".repeat(48)}`;
  await serviceRoleFetch(modern, baseFetch)(
    "https://example.test/rest/v1/rpc/test",
    {
      headers: { Authorization: `Bearer ${modern}` },
    },
  );
  assertEquals(captures.at(-1)?.get("apikey"), modern, "modern secret apikey");
  assertEquals(
    captures.at(-1)?.get("Authorization"),
    null,
    "modern secret is not a JWT",
  );

  const legacy = `${"a".repeat(20)}.${"b".repeat(20)}.${"c".repeat(20)}`;
  await serviceRoleFetch(legacy, baseFetch)(
    "https://example.test/rest/v1/rpc/test",
    {
      headers: { Authorization: `Bearer ${legacy}` },
    },
  );
  assertEquals(captures.at(-1)?.get("apikey"), legacy, "legacy apikey");
  assertEquals(
    captures.at(-1)?.get("Authorization"),
    `Bearer ${legacy}`,
    "legacy JWT stays authorized",
  );
});

Deno.test("provider configuration accepts pinned production key formats", async () => {
  const rsa = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const ec = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const rsaPkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", rsa.privateKey),
  );
  const ecPkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", ec.privateKey),
  );
  const ecRaw = new Uint8Array(
    await crypto.subtle.exportKey("raw", ec.publicKey),
  );
  const ecJwk = await crypto.subtle.exportKey("jwk", ec.privateKey);
  assert(typeof ecJwk.d === "string", "private JWK d");
  const env: Record<string, string> = {
    FCM_PROJECT_ID: "gymapp-test",
    FCM_CLIENT_EMAIL:
      "firebase-adminsdk-test@gymapp-test.iam.gserviceaccount.com",
    FCM_PRIVATE_KEY: pem(rsaPkcs8),
    APNS_TEAM_ID: "A1B2C3D4E5",
    APNS_KEY_ID: "F6G7H8J9K0",
    APNS_PRIVATE_KEY: pem(ecPkcs8),
    APNS_BUNDLE_ID: "com.setforge.gymapp.ios",
    WEBPUSH_VAPID_PUBLIC_KEY: base64Url(ecRaw),
    WEBPUSH_VAPID_PRIVATE_KEY: ecJwk.d,
    WEBPUSH_CONTACT: "mailto:push@example.test",
  };
  const config = await loadProviderConfig((name) => env[name]);
  assert(config.fcm !== null, "FCM configuration");
  assert(config.apns !== null, "APNs configuration");
  assert(config.webPush !== null, "Web Push configuration");
  assertEquals(config.fcm.projectId, env.FCM_PROJECT_ID, "FCM project");
  assertEquals(config.apns.bundleId, env.APNS_BUNDLE_ID, "APNs topic");
  assertEquals(
    config.webPush.publicKey,
    env.WEBPUSH_VAPID_PUBLIC_KEY,
    "VAPID public key",
  );
  const authorization = await vapidAuthorization(
    config,
    "https://fcm.googleapis.com/fcm/send/synthetic",
  );
  const match = /^vapid t=([^,]+), k=(.+)$/u.exec(authorization);
  assert(match, "VAPID authorization shape");
  assertEquals(match[2], env.WEBPUSH_VAPID_PUBLIC_KEY, "VAPID public header");
  const parts = match[1].split(".");
  assertEquals(parts.length, 3, "VAPID JWT segments");
  const claims = JSON.parse(
    new TextDecoder().decode(decodeBase64Url(parts[1])),
  );
  assertEquals(claims.aud, "https://fcm.googleapis.com", "VAPID audience");
  assertEquals(claims.sub, env.WEBPUSH_CONTACT, "VAPID contact");
  const now = Math.floor(Date.now() / 1_000);
  assert(
    Number.isInteger(claims.exp) && claims.exp > now + 11 * 60 * 60 &&
      claims.exp <= now + 12 * 60 * 60,
    "VAPID expiry must be at most 12 hours",
  );
  const signatureBytes = decodeBase64Url(parts[2]);
  const signature = new ArrayBuffer(signatureBytes.byteLength);
  new Uint8Array(signature).set(signatureBytes);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      ec.publicKey,
      signature,
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    ),
    "VAPID signature",
  );
});

Deno.test("Web Push configuration does not require unavailable native providers", async () => {
  const ec = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const ecRaw = new Uint8Array(
    await crypto.subtle.exportKey("raw", ec.publicKey),
  );
  const ecJwk = await crypto.subtle.exportKey("jwk", ec.privateKey);
  assert(typeof ecJwk.d === "string", "private JWK d");
  const env: Record<string, string> = {
    WEBPUSH_VAPID_PUBLIC_KEY: base64Url(ecRaw),
    WEBPUSH_VAPID_PRIVATE_KEY: ecJwk.d,
    WEBPUSH_CONTACT: "mailto:push@example.test",
  };
  const config = await loadProviderConfig((name) => env[name], ["web_push"]);
  assertEquals(config.fcm, null, "FCM remains unloaded");
  assertEquals(config.apns, null, "APNs remains unloaded");
  assert(config.webPush !== null, "Web Push configuration");
});
