import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");

function client(url) {
  return {
    url,
    navigations: [],
    async navigate(destination) {
      this.navigations.push(destination);
      return this;
    }
  };
}

function createWorker({
  scope = "https://example.test/GymApp/",
  cacheNames = ["gym-pwa-v121", "gym-pwa-v122", "another-app-cache"],
  fetchImpl = async request => new Response("landing", {
    status: 200,
    headers: { "Content-Type": "text/html" }
  }),
  windows = []
} = {}) {
  const handlers = new Map();
  const deletedCaches = [];
  const fetchedRequests = [];
  let skipped = 0;
  let claimed = 0;
  const self = {
    registration: { scope },
    clients: {
      async claim() { claimed += 1; },
      async matchAll(options) {
        assert.equal(options.type, "window");
        assert.equal(options.includeUncontrolled, true);
        return windows;
      }
    },
    async skipWaiting() { skipped += 1; },
    addEventListener(type, handler) { handlers.set(type, handler); }
  };
  const context = vm.createContext({
    self,
    URL,
    Request,
    Response,
    Headers,
    Object,
    Set,
    Promise,
    Error,
    caches: {
      async keys() { return [...cacheNames]; },
      async delete(name) { deletedCaches.push(name); return true; }
    },
    async fetch(request) {
      fetchedRequests.push(request);
      return fetchImpl(request);
    }
  });
  vm.runInContext(workerSource, context, { filename: "sw.js" });
  return {
    handlers,
    deletedCaches,
    fetchedRequests,
    get skipped() { return skipped; },
    get claimed() { return claimed; }
  };
}

function navigationRequest(url, { method = "GET", headers = {}, mode = "navigate" } = {}) {
  return { url, method, mode, headers: new Headers(headers) };
}

async function dispatchLifecycle(handler) {
  let promise = null;
  handler({ waitUntil(value) { promise = Promise.resolve(value); } });
  assert.ok(promise, "lifecycle handler must extend the event lifetime");
  await promise;
}

function dispatchFetch(handler, request) {
  let responsePromise = null;
  handler({
    request,
    respondWith(value) { responsePromise = Promise.resolve(value); }
  });
  return responsePromise;
}

test("retirement worker installs immediately and claims clients", async () => {
  const worker = createWorker();
  await dispatchLifecycle(worker.handlers.get("install"));
  await dispatchLifecycle(worker.handlers.get("activate"));
  assert.equal(worker.skipped, 1);
  assert.equal(worker.claimed, 1);
});

test("activation deletes only GymApp static caches", async () => {
  const worker = createWorker();
  await dispatchLifecycle(worker.handlers.get("activate"));
  assert.deepEqual(worker.deletedCaches, ["gym-pwa-v121", "gym-pwa-v122"]);
  assert.equal(worker.deletedCaches.includes("another-app-cache"), false);
});

test("activation navigates only same-scope root clients and preserves callback/share routes", async () => {
  const scope = "https://example.test/GymApp/";
  const root = client(scope);
  const index = client(`${scope}index.html?utm_source=old-shell#stale`);
  const confirmed = client(`${scope}confirmed.html?platform=android&code=opaque`);
  const workout = client(`${scope}workout/#workout=opaque`);
  const workoutIndex = client(`${scope}workout/index.html#workout=opaque`);
  const sibling = client("https://example.test/OtherApp/");
  const nested = client(`${scope}support.html`);
  const worker = createWorker({ scope, windows: [root, index, confirmed, workout, workoutIndex, sibling, nested] });

  await dispatchLifecycle(worker.handlers.get("activate"));

  assert.deepEqual(root.navigations, [scope]);
  assert.deepEqual(index.navigations, [scope]);
  for (const preserved of [confirmed, workout, workoutIndex, sibling, nested]) {
    assert.deepEqual(preserved.navigations, [], preserved.url);
  }
});

test("root navigation always fetches the canonical landing without credential-bearing query or fragment", async () => {
  const scope = "https://example.test/GymApp/";
  const worker = createWorker({ scope });
  const request = navigationRequest(`${scope}index.html?access_token=do-not-forward#fragment`, {
    headers: { Accept: "text/html" }
  });
  const responsePromise = dispatchFetch(worker.handlers.get("fetch"), request);
  assert.ok(responsePromise);
  const response = await responsePromise;

  assert.equal(worker.fetchedRequests.length, 1);
  assert.equal(worker.fetchedRequests[0].url, scope);
  assert.equal(worker.fetchedRequests[0].cache, "reload");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.match(response.headers.get("content-security-policy"), /connect-src 'none'/);
  assert.equal(response.headers.get("x-frame-options"), "DENY");
});

test("authorization-bearing root requests and all preserved or static routes bypass interception", () => {
  const scope = "https://example.test/GymApp/";
  const worker = createWorker({ scope });
  const handler = worker.handlers.get("fetch");
  const requests = [
    navigationRequest(scope, { headers: { Authorization: "Bearer private" } }),
    navigationRequest(`${scope}confirmed.html?code=opaque`),
    navigationRequest(`${scope}workout/#workout=opaque`),
    navigationRequest(`${scope}retirement.v1.js`, { mode: "cors" }),
    navigationRequest(scope, { method: "POST", headers: { "Content-Type": "text/plain" } })
  ];
  for (const request of requests) assert.equal(dispatchFetch(handler, request), null, request.url);
});

test("network failure returns a minimal no-store landing instead of an old cached app shell", async () => {
  const scope = "https://example.test/GymApp/";
  const worker = createWorker({
    scope,
    fetchImpl: async () => { throw new Error("offline"); }
  });
  const response = await dispatchFetch(
    worker.handlers.get("fetch"),
    navigationRequest(scope)
  );
  assert.equal(response.status, 503);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.match(await response.text(), /GymApp workouts are available in the mobile apps/);
  assert.doesNotMatch(await Promise.resolve(workerSource), /caches\.match|caches\.open/);
});

test("retirement worker has no installability, push, auth, storage, or private-cache behavior", () => {
  assert.doesNotMatch(workerSource, /manifest\.webmanifest|app\.v\d+|supabase|exercise-media|notificationclick/);
  assert.doesNotMatch(workerSource, /pushManager|indexedDB|localStorage|sessionStorage|deleteDatabase/);
  assert.doesNotMatch(workerSource, /registration\.unregister|serviceWorker\.register/);
  assert.match(workerSource, /name\.startsWith\(CACHE_PREFIX\)/);
  assert.match(workerSource, /\.\/confirmed\.html/);
  assert.match(workerSource, /\.\/workout\//);
});
