const CACHE_PREFIX = "gym-pwa-";
const CACHE_NAME = `${CACHE_PREFIX}v36`;
const ASSETS = [
  "./",
  "./index.html",
  "./confirmed.html",
  "./confirmed.css",
  "./confirmed.js",
  "./styles.css",
  "./muscle-regions.js",
  "./supabase-config.js",
  "./garmin-cloud-sync.js",
  "./app.js",
  "./manifest.webmanifest",
  "./icon.svg"
];
const STATIC_PATHS = new Set(
  ASSETS.map(asset => new URL(asset, self.registration.scope).pathname)
);
const SENSITIVE_QUERY_KEYS = new Set([
  "access_token",
  "refresh_token",
  "token",
  "code",
  "apikey",
  "api_key"
]);

function isCacheableStaticRequest(request) {
  if (request.method !== "GET") return false;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return false;
  if (url.username || url.password) return false;
  if (request.headers.has("authorization") || request.headers.has("apikey")) return false;
  if ([...url.searchParams.keys()].some(key => SENSITIVE_QUERY_KEYS.has(key.toLowerCase()))) return false;

  return STATIC_PATHS.has(url.pathname);
}

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS)));
  self.skipWaiting();
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
  self.clients.claim();
});

self.addEventListener("fetch", event => {
  if (!isCacheableStaticRequest(event.request)) return;
  event.respondWith(
    caches.open(CACHE_NAME).then(cache =>
      cache.match(event.request, { ignoreSearch: true }).then(cached =>
        cached || fetch(event.request)
      )
    )
  );
});
