"use strict";

const CACHE_PREFIX = "gym-pwa-";
const CACHE_VERSION = "v116";
const CACHE_NAME = `${CACHE_PREFIX}${CACHE_VERSION}`;
const LEGACY_GITHUB_ORIGIN = "https://eduard047.github.io";
const LEGACY_GITHUB_SCOPE = `${LEGACY_GITHUB_ORIGIN}/GymApp/`;
const LEGACY_GITHUB_SCOPE_URL = new URL(LEGACY_GITHUB_SCOPE);
const IS_LEGACY_GITHUB_ORIGIN = self.location.origin === LEGACY_GITHUB_ORIGIN &&
  self.registration.scope === LEGACY_GITHUB_SCOPE;
const LEGACY_CLEANUP_URL = new URL("./legacy-origin-cleanup-v62.html", self.registration.scope);
const LEGACY_CONFIRMATION_URL = new URL("./confirmed.html", self.registration.scope);
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
const ASSETS = [
  "./",
  "./index.html",
  "./confirmed.html",
  "./confirmed.v56.css",
  "./confirmed.v56.js",
  "./frame-guard.v56.js",
  "./theme.v56.js",
  "./styles.v68.css",
  "./muscle-regions.v56.js",
  "./supabase-config.v56.js",
  "./state-contract.v69.js",
  "./garmin-cloud-sync.v57.js",
  "./progression-rules.v56.js",
  "./shared-workout.v65.js",
  "./shared-workout-flow.v71.js",
  "./russian-text.v74.js",
  "./exercise-search-vocabulary.v1.js",
  "./app.v81.js",
  "./workout/",
  "./workout/index.html",
  "./workout/landing.v1.css",
  "./workout/landing.v2.js",
  ...EXERCISE_MEDIA_KEYS.flatMap(key => [
    `./exercise-media/${key}_0.jpg`,
    `./exercise-media/${key}_1.jpg`
  ]),
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-192.png",
  "./icon-maskable-512.png",
  "./apple-touch-icon.png",
  "./favicon-32.png"
];
const STATIC_URLS = new Set(
  ASSETS.map(asset => new URL(asset, self.registration.scope).href)
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
  "connect-src 'self' https://owrcbsrectdgaotndtxy.supabase.co",
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
  if (url.search && DOCUMENT_PATHS.has(url.pathname)) return false;
  if (hasSensitiveQuery(url)) return false;
  return STATIC_URLS.has(url.href);
}

function isHandledRequest(request) {
  const url = new URL(request.url);
  if (!isSafeBaseRequest(request, url)) return false;
  return documentPolicy(url) !== null || isCacheableStaticRequest(request);
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
  self.addEventListener("install", event => {
    const requests = ASSETS.map(asset => new Request(
      new URL(asset, self.registration.scope).href,
      { cache: "reload" }
    ));
    event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(requests)));
  });

  self.addEventListener("activate", event => {
    event.waitUntil(
      caches.keys().then(keys =>
        Promise.all(
          keys
            .filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
            .map(key => caches.delete(key))
        )
      )
    );
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
      caches.open(CACHE_NAME).then(cache =>
        cache.match(event.request)
          .then(cached => cached || fetch(event.request))
          .then(response => withDocumentSecurityHeaders(response, url))
      )
    );
  });
}
