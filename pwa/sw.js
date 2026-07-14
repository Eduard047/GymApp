"use strict";

const CACHE_PREFIX = "gym-pwa-";
const CACHE_VERSION = "v45";
const CACHE_NAME = `${CACHE_PREFIX}${CACHE_VERSION}`;
const LEGACY_GITHUB_ORIGIN = "https://eduard047.github.io";
const IS_LEGACY_GITHUB_ORIGIN = self.location.origin === LEGACY_GITHUB_ORIGIN;
const LEGACY_CLEANUP_URL = new URL("./legacy-origin-cleanup.html", self.registration.scope);
const LEGACY_CONFIRMATION_URL = new URL("./confirmed.html", self.registration.scope);
const ASSETS = [
  "./",
  "./index.html",
  "./confirmed.html",
  "./confirmed.v45.css",
  "./confirmed.v45.js",
  "./frame-guard.v45.js",
  "./styles.v45.css",
  "./muscle-regions.v45.js",
  "./supabase-config.v45.js",
  "./state-contract.v45.js",
  "./garmin-cloud-sync.v45.js",
  "./progression-rules.v45.js",
  "./app.v45.js",
  "./manifest.webmanifest",
  "./icon.svg"
];
const STATIC_URLS = new Set(
  ASSETS.map(asset => new URL(asset, self.registration.scope).href)
);
const ROOT_PATH = new URL("./", self.registration.scope).pathname;
const INDEX_PATH = new URL("./index.html", self.registration.scope).pathname;
const CONFIRMATION_PATH = new URL("./confirmed.html", self.registration.scope).pathname;
const DOCUMENT_PATHS = new Set([ROOT_PATH, INDEX_PATH, CONFIRMATION_PATH]);
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

if (IS_LEGACY_GITHUB_ORIGIN) {
  self.addEventListener("install", event => {
    event.waitUntil(Promise.resolve(self.skipWaiting()));
  });

  self.addEventListener("activate", event => {
    event.waitUntil(
      caches.keys()
        .then(keys => Promise.all(keys.filter(key => key.startsWith(CACHE_PREFIX)).map(key => caches.delete(key))))
        .then(() => Promise.resolve(self.clients.claim()))
        .then(() => self.clients.matchAll({ type: "window", includeUncontrolled: true }))
        .then(clients => Promise.all(clients.map(client => {
          const clientUrl = new URL(client.url);
          if (clientUrl.pathname === LEGACY_CONFIRMATION_URL.pathname) return null;
          return client.navigate(LEGACY_CLEANUP_URL.href).catch(() => null);
        })))
    );
  });

  self.addEventListener("fetch", event => {
    const url = new URL(event.request.url);
    if (event.request.method !== "GET" || event.request.mode !== "navigate" ||
        url.origin !== self.location.origin || url.pathname === LEGACY_CLEANUP_URL.pathname ||
        url.pathname === LEGACY_CONFIRMATION_URL.pathname) return;
    event.respondWith(fetch(LEGACY_CLEANUP_URL.href, {
      cache: "no-store",
      credentials: "omit",
      redirect: "error",
      referrerPolicy: "no-referrer"
    }));
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
