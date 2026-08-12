"use strict";

const CACHE_PREFIX = "gym-pwa-";
const ROOT_URL = new URL("./", self.registration.scope);
const INDEX_URL = new URL("./index.html", self.registration.scope);
const CONFIRMATION_URL = new URL("./confirmed.html", self.registration.scope);
const WORKOUT_URL = new URL("./workout/", self.registration.scope);
const WORKOUT_INDEX_URL = new URL("./workout/index.html", self.registration.scope);
const ROOT_PATHS = new Set([ROOT_URL.pathname, INDEX_URL.pathname]);
const PRESERVED_PATHS = new Set([
  CONFIRMATION_URL.pathname,
  WORKOUT_URL.pathname,
  WORKOUT_INDEX_URL.pathname
]);
const LANDING_SECURITY_HEADERS = Object.freeze({
  "Cache-Control": "no-store",
  "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'none'; worker-src 'none'; manifest-src 'none'; object-src 'none'; frame-src 'none'; frame-ancestors 'none'; media-src 'none'; font-src 'none'; base-uri 'none'; form-action 'none'",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Origin-Agent-Cluster": "?1",
  "Permissions-Policy": "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY"
});

function sameScopeUrl(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return url.origin === ROOT_URL.origin && url.pathname.startsWith(ROOT_URL.pathname) &&
      !url.username && !url.password;
  } catch {
    return false;
  }
}

function isRootUrl(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return sameScopeUrl(url.href) && ROOT_PATHS.has(url.pathname);
  } catch {
    return false;
  }
}

function isPreservedUrl(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return sameScopeUrl(url.href) && PRESERVED_PATHS.has(url.pathname);
  } catch {
    return false;
  }
}

async function deleteKnownStaticCaches() {
  const names = await caches.keys();
  const known = names.filter(name => typeof name === "string" && name.startsWith(CACHE_PREFIX));
  return Promise.allSettled(known.map(name => caches.delete(name)));
}

async function navigateRootClients() {
  const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  await Promise.allSettled(windows.map(client => {
    if (!isRootUrl(client.url) || isPreservedUrl(client.url) || typeof client.navigate !== "function") {
      return Promise.resolve();
    }
    return client.navigate(ROOT_URL.href);
  }));
}

function securedLandingResponse(response) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(LANDING_SECURITY_HEADERS)) headers.set(name, value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

function offlineLandingResponse() {
  const headers = new Headers({
    "Content-Type": "text/html; charset=utf-8",
    ...LANDING_SECURITY_HEADERS
  });
  return new Response(
    "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>GymApp</title><main><h1>GymApp</h1><p>GymApp workouts are available in the mobile apps.</p></main></html>",
    { status: 503, statusText: "Offline", headers }
  );
}

async function fetchLanding() {
  try {
    const response = await fetch(new Request(ROOT_URL.href, {
      method: "GET",
      credentials: "same-origin",
      redirect: "follow",
      cache: "reload",
      headers: { Accept: "text/html" }
    }));
    const contentType = response.headers.get("Content-Type") || "";
    if (!response.ok || response.type === "opaque" ||
        (response.url && !isRootUrl(response.url)) ||
        !/^text\/html(?:;|$)/i.test(contentType)) {
      throw new Error("Landing is unavailable.");
    }
    return securedLandingResponse(response);
  } catch {
    return offlineLandingResponse();
  }
}

self.addEventListener("install", event => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    await deleteKnownStaticCaches().catch(() => []);
    await self.clients.claim();
    await navigateRootClients();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET" || request.mode !== "navigate" ||
      request.headers.has("authorization") || request.headers.has("apikey") ||
      !isRootUrl(request.url)) {
    return;
  }
  event.respondWith(fetchLanding());
});
