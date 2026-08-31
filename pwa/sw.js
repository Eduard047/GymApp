"use strict";

const CACHE_PREFIX = "gym-pwa-";
const CACHE_VERSION = "v145";
// v145 loads the finished LIVE room lifecycle fixes.
// Stable media remains isolated from the immutable application shell.
const CACHE_NAME = `${CACHE_PREFIX}${CACHE_VERSION}`;
const MEDIA_CACHE_VERSION = "v1-a93d1c50c244";
// Exercise demonstrations and install icons are content-versioned separately
// from the application shell. A shell-only release can therefore reuse the
// already verified public media cache instead of downloading every image again.
const MEDIA_CACHE_NAME = `${CACHE_PREFIX}media-${MEDIA_CACHE_VERSION}`;
const UPDATE_REFRESH_QUERY_KEY = "gymapp_sw_refresh";
const LEGACY_GITHUB_ORIGIN = "https://eduard047.github.io";
const LEGACY_GITHUB_SCOPE = `${LEGACY_GITHUB_ORIGIN}/GymApp/`;
const LEGACY_GITHUB_SCOPE_URL = new URL(LEGACY_GITHUB_SCOPE);
const IS_LEGACY_GITHUB_ORIGIN = self.location.origin === LEGACY_GITHUB_ORIGIN &&
  self.registration.scope === LEGACY_GITHUB_SCOPE;
const LEGACY_CLEANUP_URL = new URL("./legacy-origin-cleanup-v62.html", self.registration.scope);
const LEGACY_CONFIRMATION_URL = new URL("./confirmed.html", self.registration.scope);
const PUSH_BINDING_DB_NAME = "gymapp-push-binding-v1";
const PUSH_BINDING_DB_VERSION = 1;
const PUSH_BINDING_STORE_NAME = "current-bindings";
const PUSH_BINDING_RECORD_KEY = "current";
const PUSH_BINDING_TRANSITION_KEY = "transition";
const PUSH_BINDING_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const EXERCISE_MEDIA_KEYS = [
  "bench_press", "dumbbell_bench_press", "incline_dumbbell_press", "incline_bench_press",
  "chest_fly_machine", "push_up", "dips", "pull_up", "assisted_pull_up", "assisted_dip", "band_assisted_pull_up",
  "lat_pulldown", "straight_arm_pulldown", "barbell_row", "seated_cable_row", "plate_loaded_row", "face_pull",
  "squat", "leg_press", "romanian_deadlift", "deadlift", "hip_thrust", "bulgarian_split_squat", "lunge", "leg_extension",
  "lying_leg_curl", "seated_leg_curl", "hip_adduction", "hip_abduction", "calf_raise",
  "shoulder_press", "lateral_raise", "machine_lateral_raise", "rear_delt_fly", "upright_row", "biceps_curl",
  "barbell_curl", "seated_dumbbell_curl", "hammer_curl", "cable_curl", "preacher_curl",
  "triceps_pushdown", "v_bar_pushdown", "overhead_dumbbell_triceps_extension",
  "french_press", "hyperextension", "side_hyperextension", "plank", "weighted_crunch",
  "hanging_leg_raise", "plate_twist", "weighted_side_bend", "warm_up"
];
const SHELL_ASSETS = [
  "./",
  "./index.html",
  "./confirmed.html",
  "./confirmed.v56.css",
  "./confirmed.v57.js",
  "./frame-guard.v56.js",
  "./theme.v56.js",
  "./styles.v79.css",
  "./muscle-regions.v56.js",
  "./supabase-config.v58.js",
  "./state-contract.v72.js",
  "./garmin-cloud-sync.v57.js",
  "./progression-rules.v57.js",
  "./shared-workout.v66.js",
  "./shared-workout-flow.v71.js",
  "./supabase-realtime.v1.js",
  "./live-workout.v3.js",
  "./live-workout-state.v1.js",
  "./russian-text.v86.js",
  "./exercise-search-vocabulary.v1.js",
  "./app.v104.js",
  "./workout/index.html",
  "./workout/landing.v2.css",
  "./workout/landing.v4.js",
  "./manifest.webmanifest"
];
const MEDIA_ASSETS = [
  ...EXERCISE_MEDIA_KEYS.flatMap(key => [
    `./exercise-media/${key}_0.jpg`,
    `./exercise-media/${key}_1.jpg`
  ]),
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-192.png",
  "./icon-maskable-512.png",
  "./apple-touch-icon.png",
  "./favicon-32.png"
];
const ASSETS = [...SHELL_ASSETS, ...MEDIA_ASSETS];
const STATIC_URLS = new Set(
  ASSETS.map(asset => new URL(asset, self.registration.scope).href)
);
const MEDIA_URLS = new Set(
  MEDIA_ASSETS.map(asset => new URL(asset, self.registration.scope).href)
);
const ROOT_PATH = new URL("./", self.registration.scope).pathname;
const INDEX_PATH = new URL("./index.html", self.registration.scope).pathname;
const CONFIRMATION_PATH = new URL("./confirmed.html", self.registration.scope).pathname;
const WORKOUT_PATH = new URL("./workout/", self.registration.scope).pathname;
const WORKOUT_INDEX_PATH = new URL("./workout/index.html", self.registration.scope).pathname;
const DOCUMENT_PATHS = new Set([
  ROOT_PATH,
  INDEX_PATH,
  CONFIRMATION_PATH,
  WORKOUT_PATH,
  WORKOUT_INDEX_PATH
]);
const SENSITIVE_QUERY_KEYS = new Set([
  "access_token",
  "refresh_token",
  "token",
  "code",
  "apikey",
  "api_key"
]);
const INDEX_CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self' data:",
  "connect-src 'self' https://owrcbsrectdgaotndtxy.supabase.co wss://owrcbsrectdgaotndtxy.supabase.co",
  "worker-src 'self'",
  "manifest-src 'self'",
  "object-src 'none'",
  "frame-src 'none'",
  "frame-ancestors 'none'",
  "media-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "upgrade-insecure-requests"
].join("; ");
const CONFIRMATION_CSP = [
  "default-src 'none'",
  "style-src 'self'",
  "script-src 'self'",
  "img-src 'self' data:",
  "frame-ancestors 'none'",
  "base-uri 'none'",
  "form-action 'none'"
].join("; ");
const WORKOUT_CSP = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self'",
  "connect-src 'none'",
  "worker-src 'none'",
  "manifest-src 'self'",
  "object-src 'none'",
  "frame-src 'none'",
  "frame-ancestors 'none'",
  "media-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "upgrade-insecure-requests"
].join("; ");

function isSafeBaseRequest(request, url) {
  return request.method === "GET" &&
    url.origin === self.location.origin &&
    !url.username && !url.password &&
    !request.headers.has("authorization") &&
    !request.headers.has("apikey") &&
    !request.headers.has("range") &&
    !request.headers.has("if-range");
}

function documentPolicy(url) {
  if (url.pathname === CONFIRMATION_PATH) return CONFIRMATION_CSP;
  if (url.pathname === WORKOUT_PATH || url.pathname === WORKOUT_INDEX_PATH) return WORKOUT_CSP;
  if (url.pathname === ROOT_PATH || url.pathname === INDEX_PATH) return INDEX_CSP;
  return null;
}

function hasSensitiveQuery(url) {
  return [...url.searchParams.keys()].some(key => {
    const normalized = key.toLowerCase();
    return SENSITIVE_QUERY_KEYS.has(normalized) || normalized.includes("token");
  });
}

function isCacheableStaticRequest(request) {
  const url = new URL(request.url);
  if (!isSafeBaseRequest(request, url)) return false;
  // Documents must always revalidate against the network. Treating the app
  // shell as an immutable static asset lets an already controlled client stay
  // pinned to an old index and therefore to an internally consistent but stale
  // bundle set. The current cache remains the offline fallback below.
  if (documentPolicy(url) !== null) return false;
  if (hasSensitiveQuery(url)) return false;
  return STATIC_URLS.has(url.href);
}

function isHandledRequest(request) {
  const url = new URL(request.url);
  if (!isSafeBaseRequest(request, url)) return false;
  return documentPolicy(url) !== null || isCacheableStaticRequest(request);
}

function reloadRequests(assets) {
  return assets.map(asset => new Request(
    new URL(asset, self.registration.scope).href,
    { cache: "reload" }
  ));
}

async function ensureCompleteContentCache(cacheName, requests) {
  const cache = await caches.open(cacheName);
  const cachedUrls = new Set((await cache.keys()).map(request => request.url));
  const missing = requests.filter(request => !cachedUrls.has(request.url));
  if (missing.length) await cache.addAll(missing);
}

function staticCacheName(url) {
  return MEDIA_URLS.has(url.href) ? MEDIA_CACHE_NAME : CACHE_NAME;
}

function withDocumentSecurityHeaders(response, url, { noStore = false } = {}) {
  const policy = documentPolicy(url);
  if (!policy) return response;
  const headers = new Headers(response.headers);
  if (noStore) headers.set("Cache-Control", "no-store");
  headers.set("Content-Security-Policy", policy);
  headers.set("Cross-Origin-Opener-Policy", "same-origin");
  headers.set("Origin-Agent-Cluster", "?1");
  headers.set("Permissions-Policy", "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Frame-Options", "DENY");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

async function cachedCanonicalDocument(url) {
  const canonical = new URL(url.href);
  if (canonical.pathname === WORKOUT_PATH) canonical.pathname = WORKOUT_INDEX_PATH;
  canonical.search = "";
  canonical.hash = "";
  const cache = await caches.open(CACHE_NAME);
  return cache.match(canonical.href);
}

function isWithinLegacyGithubScope(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return url.origin === LEGACY_GITHUB_SCOPE_URL.origin &&
      url.pathname.startsWith(LEGACY_GITHUB_SCOPE_URL.pathname);
  } catch {
    return false;
  }
}

async function deleteLegacyGithubScopeCacheEntries() {
  const names = (await caches.keys()).filter(name => name.startsWith(CACHE_PREFIX));
  await Promise.all(names.map(async name => {
    const cache = await caches.open(name);
    const requests = await cache.keys();
    const results = await Promise.all(
      requests
        .filter(request => isWithinLegacyGithubScope(request.url))
        .map(request => cache.delete(request))
    );
    if (!results.every(result => result === true)) {
      throw new Error("Legacy GymApp cache cleanup was incomplete.");
    }
  }));
}

const PUSH_LIVE_KINDS = new Set([
  "invite", "joined", "started", "participant_finished", "room_closed"
]);
const PUSH_SOCIAL_TYPES = new Set([
  "friend_request_received", "friend_request_accepted",
  "workout_invite_received", "workout_invite_accepted"
]);
const PUSH_ROOM_PATTERN = /^lr_[0-9a-f]{32}$/;
const PUSH_FRIENDSHIP_PATTERN = /^f_[0-9a-f]{32}$/;
const PUSH_WORKOUT_INVITE_PATTERN = /^wi_[0-9a-f]{32}$/;

function pushBindingRecord(value) {
  const row = pushExactObject(value, ["version", "bindingId", "ownerId"]);
  if (row.version !== 1 || !PUSH_BINDING_UUID_PATTERN.test(row.bindingId || "") ||
      !PUSH_BINDING_UUID_PATTERN.test(row.ownerId || "")) {
    throw new TypeError("Push binding is invalid.");
  }
  return row;
}

function openPushBindingDatabase() {
  return new Promise((resolve, reject) => {
    if (!self.indexedDB) {
      reject(new Error("Push binding storage is unavailable."));
      return;
    }
    const request = self.indexedDB.open(PUSH_BINDING_DB_NAME, PUSH_BINDING_DB_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(PUSH_BINDING_STORE_NAME)) {
        database.createObjectStore(PUSH_BINDING_STORE_NAME);
      }
    };
    request.onerror = () => reject(request.error || new Error("Push binding storage failed."));
    request.onblocked = () => reject(new Error("Push binding storage is blocked."));
    request.onsuccess = () => resolve(request.result);
  });
}

async function storedPushBinding() {
  const database = await openPushBindingDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(PUSH_BINDING_STORE_NAME, "readonly");
      const store = transaction.objectStore(PUSH_BINDING_STORE_NAME);
      const request = store.get(PUSH_BINDING_RECORD_KEY);
      const transitionRequest = store.get(PUSH_BINDING_TRANSITION_KEY);
      let value = null;
      let transitionBlocked = false;
      request.onsuccess = () => {
        try {
          value = request.result === undefined ? null : pushBindingRecord(request.result);
        } catch {
          value = null;
        }
      };
      transitionRequest.onsuccess = () => {
        transitionBlocked = transitionRequest.result !== undefined;
      };
      request.onerror = () => reject(request.error || new Error("Push binding read failed."));
      transitionRequest.onerror = () => reject(
        transitionRequest.error || new Error("Push transition read failed.")
      );
      transaction.onabort = () => reject(transaction.error || new Error("Push binding read aborted."));
      transaction.onerror = () => {};
      transaction.oncomplete = () => resolve(transitionBlocked ? null : value);
    });
  } finally {
    database.close();
  }
}

async function pushBindingMatches(bindingId) {
  if (!PUSH_BINDING_UUID_PATTERN.test(bindingId || "")) return false;
  try {
    const stored = await storedPushBinding();
    return stored?.bindingId === bindingId;
  } catch {
    return false;
  }
}

function pushExactObject(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).sort().join(",") !== [...keys].sort().join(",")) {
    throw new TypeError("Push payload fields are invalid.");
  }
  return value;
}

function pushBoundedInteger(value, min = 0) {
  if (!Number.isSafeInteger(value) || value < min || value > 2147483647) {
    throw new TypeError("Push revision is invalid.");
  }
  return value;
}

function pushData(value) {
  if (Object.hasOwn(value || {}, "kind")) {
    const row = pushExactObject(value, [
      "version", "bindingId", "kind", "roomId", "roomRevision"
    ]);
    if (row.version !== 1 || !PUSH_LIVE_KINDS.has(row.kind) ||
        !PUSH_BINDING_UUID_PATTERN.test(row.bindingId || "") ||
        !PUSH_ROOM_PATTERN.test(row.roomId || "")) {
      throw new TypeError("Push live data is invalid.");
    }
    return {
      version: 1,
      bindingId: row.bindingId,
      kind: row.kind,
      roomId: row.roomId,
      roomRevision: pushBoundedInteger(row.roomRevision, 1)
    };
  }
  const row = pushExactObject(value, [
    "version", "bindingId", "type", "objectId", "objectRevision"
  ]);
  const pattern = String(row.type || "").startsWith("workout_invite_")
    ? PUSH_WORKOUT_INVITE_PATTERN
    : PUSH_FRIENDSHIP_PATTERN;
  if (row.version !== 1 || !PUSH_BINDING_UUID_PATTERN.test(row.bindingId || "") ||
      !PUSH_SOCIAL_TYPES.has(row.type) ||
      !pattern.test(row.objectId || "")) {
    throw new TypeError("Push social data is invalid.");
  }
  return {
    version: 1,
    bindingId: row.bindingId,
    type: row.type,
    objectId: row.objectId,
    objectRevision: pushBoundedInteger(row.objectRevision)
  };
}

function pushText(value, maxLength) {
  if (typeof value !== "string" || value.length < 1 || value.length > maxLength ||
      /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/u.test(value)) {
    throw new TypeError("Push notification copy is invalid.");
  }
  return value;
}

function pushEnvelope(value) {
  const root = pushExactObject(value, ["version", "notification", "data"]);
  const notification = pushExactObject(root.notification, ["title", "body", "tag"]);
  if (root.version !== 1 || typeof notification.tag !== "string" ||
      !/^[A-Za-z0-9_-]{1,32}$/.test(notification.tag)) {
    throw new TypeError("Push notification is invalid.");
  }
  return {
    version: 1,
    notification: {
      title: pushText(notification.title, 120),
      body: pushText(notification.body, 240),
      tag: notification.tag
    },
    data: pushData(root.data)
  };
}

function pushNavigationUrl(data) {
  const target = new URL("./", self.registration.scope);
  target.searchParams.set("notification", data.roomId ? "live" : "social");
  target.searchParams.set("binding", data.bindingId);
  if (data.roomId) target.searchParams.set("room", data.roomId);
  else {
    target.searchParams.set("social_type", data.type);
    target.searchParams.set("object", data.objectId);
    target.searchParams.set("revision", String(data.objectRevision));
  }
  return target;
}

async function openPushTarget(data) {
  const parsed = pushData(data);
  const target = pushNavigationUrl(parsed);
  const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  const scope = new URL(self.registration.scope);
  const existing = windows.find(client => {
    try {
      const url = new URL(client.url);
      return url.origin === scope.origin && url.pathname.startsWith(scope.pathname);
    } catch {
      return false;
    }
  });
  if (existing) {
    existing.postMessage({
      version: 1,
      type: "gymapp_notification_click",
      target: parsed.roomId ? "live" : "social",
      bindingId: parsed.bindingId,
      ...(parsed.roomId
        ? { roomId: parsed.roomId }
        : {
            socialType: parsed.type,
            objectId: parsed.objectId,
            objectRevision: parsed.objectRevision
          })
    });
    await existing.focus();
    return;
  }
  await self.clients.openWindow(target.href);
}

if (IS_LEGACY_GITHUB_ORIGIN) {
  self.addEventListener("install", event => {
    event.waitUntil(Promise.resolve(self.skipWaiting()));
  });

  self.addEventListener("activate", event => {
    event.waitUntil(
      deleteLegacyGithubScopeCacheEntries()
        .then(() => Promise.resolve(self.clients.claim()))
        .then(() => self.clients.matchAll({ type: "window", includeUncontrolled: true }))
        .then(clients => Promise.all(clients.map(client => {
          const clientUrl = new URL(client.url);
          if (!isWithinLegacyGithubScope(clientUrl.href) ||
              clientUrl.pathname === LEGACY_CONFIRMATION_URL.pathname ||
              clientUrl.pathname === LEGACY_CLEANUP_URL.pathname) return null;
          return client.navigate(LEGACY_CLEANUP_URL.href).catch(() => null);
        })))
    );
  });

  self.addEventListener("fetch", event => {
    const url = new URL(event.request.url);
    if (event.request.method !== "GET" || event.request.mode !== "navigate" ||
        url.origin !== self.location.origin || url.pathname === LEGACY_CLEANUP_URL.pathname ||
        url.pathname === LEGACY_CONFIRMATION_URL.pathname) return;
    event.respondWith(Promise.resolve(Response.redirect(LEGACY_CLEANUP_URL.href, 302)));
  });
} else {
  self.addEventListener("push", event => {
    let envelope;
    try {
      envelope = pushEnvelope(event.data?.json());
    } catch {
      return;
    }
    event.waitUntil((async () => {
      if (!await pushBindingMatches(envelope.data.bindingId)) return;
      await self.registration.showNotification(envelope.notification.title, {
        body: envelope.notification.body,
        tag: envelope.notification.tag,
        icon: new URL("./icon-192.png", self.registration.scope).href,
        badge: new URL("./icon-192.png", self.registration.scope).href,
        data: envelope.data,
        renotify: false,
        requireInteraction: false
      });
    })());
  });

  self.addEventListener("notificationclick", event => {
    let data;
    try {
      data = pushData(event.notification?.data);
    } catch {
      event.notification?.close?.();
      return;
    }
    event.notification.close();
    event.waitUntil((async () => {
      if (!await pushBindingMatches(data.bindingId)) return;
      await openPushTarget(data);
    })());
  });

  self.addEventListener("install", event => {
    const shellRequests = reloadRequests(SHELL_ASSETS);
    const mediaRequests = reloadRequests(MEDIA_ASSETS);
    event.waitUntil(
      Promise.all([
        caches.open(CACHE_NAME).then(cache => cache.addAll(shellRequests)),
        ensureCompleteContentCache(MEDIA_CACHE_NAME, mediaRequests)
      ])
        .then(() => Promise.resolve(self.skipWaiting()))
    );
  });

  self.addEventListener("activate", event => {
    event.waitUntil((async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter(key => key.startsWith(CACHE_PREFIX) &&
            key !== CACHE_NAME && key !== MEDIA_CACHE_NAME)
          .map(key => caches.delete(key))
      );
      await self.clients.claim();
      const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      clients.slice(0, 32).forEach(client => {
        try {
          const url = new URL(client.url);
          const isRootDocument = url.origin === self.location.origin &&
            (url.pathname === ROOT_PATH || url.pathname === INDEX_PATH);
          if (!isRootDocument || hasSensitiveQuery(url)) return;
          const refreshUrl = new URL(url.href);
          refreshUrl.searchParams.set(UPDATE_REFRESH_QUERY_KEY, CACHE_VERSION);
          // WindowClient.navigate() resolves only after the replacement
          // navigation completes. That navigation can wait for this worker to
          // finish activating before its fetch event is dispatched, so it must
          // never extend the activate event lifetime.
          void Promise.resolve(client.navigate(refreshUrl.href)).catch(() => null);
        } catch {
          // Ignore stale or malformed client records.
        }
      });
    })());
  });

  self.addEventListener("fetch", event => {
    if (!isHandledRequest(event.request)) return;
    const url = new URL(event.request.url);

    if (!isCacheableStaticRequest(event.request)) {
      let response = fetch(event.request, { cache: "no-store" })
        .then(networkResponse => withDocumentSecurityHeaders(networkResponse, url, { noStore: true }));
      if (!hasSensitiveQuery(url)) {
        response = response.catch(async error => {
          const cached = await cachedCanonicalDocument(url);
          if (!cached) throw error;
          return withDocumentSecurityHeaders(cached, url, { noStore: true });
        });
      }
      event.respondWith(response);
      return;
    }

    event.respondWith(
      caches.open(staticCacheName(url)).then(cache =>
        cache.match(event.request)
          .then(cached => cached || fetch(event.request))
          .then(response => withDocumentSecurityHeaders(response, url))
      )
    );
  });
}
