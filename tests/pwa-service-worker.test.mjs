import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../pwa/manifest.webmanifest", import.meta.url), "utf8"));
const indexHtml = readFileSync(new URL("../pwa/index.html", import.meta.url), "utf8");
const confirmedHtml = readFileSync(new URL("../pwa/confirmed.html", import.meta.url), "utf8");
const VERSIONED_ASSET_PAIRS = [
  ["confirmed.css", "confirmed.v52.css"],
  ["confirmed.js", "confirmed.v52.js"],
  ["frame-guard.js", "frame-guard.v52.js"],
  ["theme.js", "theme.v52.js"],
  ["styles.css", "styles.v52.css"],
  ["muscle-regions.js", "muscle-regions.v52.js"],
  ["supabase-config.js", "supabase-config.v52.js"],
  ["state-contract.js", "state-contract.v52.js"],
  ["garmin-cloud-sync.js", "garmin-cloud-sync.v52.js"],
  ["progression-rules.js", "progression-rules.v52.js"],
  ["russian-text.js", "russian-text.v52.js"],
  ["app.js", "app.v52.js"]
];

function loadWorker(scope = "https://example.test/GymApp/", options = {}) {
  const listeners = new Map();
  const openedCaches = [];
  const deletedCaches = [];
  const deletedCacheEntries = [];
  const addedAssets = [];
  const matchedRequests = [];
  const fetchInits = [];
  const fetchRequests = [];
  let fetchCount = 0;
  let claimCount = 0;
  let matchAllCount = 0;
  let skipWaitingCount = 0;
  const cacheContents = new Map();
  const cacheFor = name => {
    if (!cacheContents.has(name)) {
      const entries = new Map((options.cacheEntries?.[name] || []).map(rawUrl => {
        const request = new Request(rawUrl);
        return [request.url, request];
      }));
      cacheContents.set(name, entries);
    }
    return cacheContents.get(name);
  };
  const self = {
    registration: { scope },
    location: new URL(scope),
    clients: {
      claim() {
        claimCount += 1;
        return Promise.resolve();
      },
      matchAll() {
        matchAllCount += 1;
        return Promise.resolve(options.clients || []);
      }
    },
    skipWaiting() {
      skipWaitingCount += 1;
      return Promise.resolve();
    },
    addEventListener(type, handler) {
      listeners.set(type, handler);
    }
  };
  const caches = {
    async keys() {
      return ["gym-pwa-v39", "gym-pwa-v44", "gym-pwa-v59", "gym-pwa-v60", "gym-pwa-v61", "gym-pwa-v62", "gym-pwa-v64", "gym-pwa-v65", "another-app-v4"];
    },
    async open(name) {
      openedCaches.push(name);
      const entries = cacheFor(name);
      return {
        async addAll(assets) { addedAssets.push(...assets); },
        async keys() { return [...entries.values()]; },
        async delete(request) {
          const url = typeof request === "string" ? request : request.url;
          deletedCacheEntries.push([name, url]);
          if (options.cacheEntryDeleteResult === false) return false;
          entries.delete(url);
          return true;
        },
        async match(request) {
          matchedRequests.push(typeof request === "string" ? request : request.url);
          if (options.cacheMatch) return options.cacheMatch(request);
          return new Response("cached", {
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" }
          });
        }
      };
    },
    async delete(name) {
      deletedCaches.push(name);
      return true;
    }
  };

  vm.runInNewContext(workerSource, {
    Headers,
    Promise,
    Request,
    Response,
    Set,
    URL,
    caches,
    fetch: async (request, init) => {
      fetchCount += 1;
      fetchRequests.push(typeof request === "string" ? request : request.url);
      fetchInits.push(init);
      if (options.fetchImpl) return options.fetchImpl(request, init);
      return new Response("network", {
        status: 200,
        headers: { "Content-Type": "text/html; charset=utf-8" }
      });
    },
    self
  });

  return {
    listeners,
    openedCaches,
    deletedCaches,
    deletedCacheEntries,
    remainingCacheEntries(name) { return [...cacheFor(name).keys()]; },
    addedAssets,
    matchedRequests,
    fetchInits,
    fetchRequests,
    fetchCount: () => fetchCount,
    claimCount: () => claimCount,
    matchAllCount: () => matchAllCount,
    skipWaitingCount: () => skipWaitingCount
  };
}

function makeRequest(url, options = {}) {
  const { modeOverride, ...requestOptions } = options;
  const request = new Request(url, requestOptions);
  if (!modeOverride) return request;
  return {
    url: request.url,
    method: request.method,
    headers: request.headers,
    mode: modeOverride
  };
}

function responsePromiseFor(handler, url, options = {}) {
  let responsePromise = null;
  handler({
    request: makeRequest(url, options),
    respondWith(value) {
      responsePromise = value;
    }
  });
  return responsePromise;
}

function isIntercepted(handler, url, options = {}) {
  return responsePromiseFor(handler, url, options) !== null;
}

test("service worker caches only exact immutable v52 same-origin assets", () => {
  for (const scope of ["https://example.test/", "https://example.test/GymApp/"]) {
    const handler = loadWorker(scope).listeners.get("fetch");

    assert.equal(isIntercepted(handler, new URL("./app.v52.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./state-contract.v52.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./frame-guard.v52.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./icon-maskable-512.png", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./favicon-32.png", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./app.js?v=51", scope)), false);
    assert.equal(isIntercepted(handler, new URL("./app.js", scope)), false);
    assert.equal(isIntercepted(handler, scope), true);
    assert.equal(isIntercepted(handler, new URL("./rest/v1/user_states", scope)), false);
    assert.equal(isIntercepted(handler, "https://project.supabase.co/rest/v1/user_states"), false);
  }
});

test("v52 pathname assets cannot be mistaken for predecessor assets", () => {
  const predecessorPaths = new Set([
    "confirmed.css", "confirmed.js", "frame-guard.js", "theme.js", "styles.css",
    "muscle-regions.js", "supabase-config.js", "state-contract.js",
    "garmin-cloud-sync.js", "progression-rules.js", "russian-text.js", "app.js"
  ]);
  const v52Paths = [
    "confirmed.v52.css", "confirmed.v52.js", "frame-guard.v52.js", "theme.v52.js", "styles.v52.css",
    "muscle-regions.v52.js", "supabase-config.v52.js", "state-contract.v52.js",
    "garmin-cloud-sync.v52.js", "progression-rules.v52.js", "russian-text.v52.js", "app.v52.js"
  ];

  for (const pathname of v52Paths) {
    assert.equal(predecessorPaths.has(pathname), false, pathname);
    assert.match(workerSource, new RegExp(`\\./${pathname.replaceAll(".", "\\.")}`));
  }
  assert.doesNotMatch(workerSource, /\.\/app\.js\?v=51/);
});

test("every deployed v52 asset exists and is byte-identical to its canonical source", () => {
  for (const [canonical, versioned] of VERSIONED_ASSET_PAIRS) {
    const canonicalBytes = readFileSync(new URL(`../pwa/${canonical}`, import.meta.url));
    const versionedBytes = readFileSync(new URL(`../pwa/${versioned}`, import.meta.url));
    assert.equal(versionedBytes.equals(canonicalBytes), true, `${versioned} diverged from ${canonical}`);
  }
});

test("install surfaces use dedicated any, maskable, favicon, and Apple icons", () => {
  assert.deepEqual(manifest.icons, [
    { src: "./icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
    { src: "./icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
    { src: "./icon-maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
    { src: "./icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
  ]);
  for (const html of [indexHtml, confirmedHtml]) {
    assert.match(html, /rel="icon" href="\.\/favicon-32\.png" type="image\/png" sizes="32x32"/);
    assert.match(html, /rel="apple-touch-icon" href="\.\/apple-touch-icon\.png" sizes="180x180"/);
  }
  for (const asset of [
    "icon-192.png",
    "icon-512.png",
    "icon-maskable-192.png",
    "icon-maskable-512.png",
    "apple-touch-icon.png",
    "favicon-32.png"
  ]) {
    assert.match(workerSource, new RegExp(`"\\./${asset.replaceAll(".", "\\.")}"`));
  }
});

test("service worker ignores credential-bearing, partial-content, and non-GET requests", () => {
  const handler = loadWorker().listeners.get("fetch");

  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v52.js", {
    headers: { Authorization: "Bearer test-token" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/index.html", {
    headers: { apikey: "test-key" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v52.js", {
    headers: { Range: "bytes=0-10" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/index.html", {
    headers: { "If-Range": "etag" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v52.js", { method: "POST" }), false);
});

test("searched auth callbacks are network-only but receive enforceable anti-framing headers", async () => {
  const state = "A".repeat(32);
  for (const scope of ["https://example.test/", "https://example.test/GymApp/"]) {
    const worker = loadWorker(scope);
    const handler = worker.listeners.get("fetch");
    const callback = new URL("./confirmed.html", scope);
    callback.search = `?platform=ios&state=${state}&purpose=recovery&code=pkce-code`;

    const response = await responsePromiseFor(handler, callback);

    assert.equal(await response.text(), "network");
    assert.equal(worker.fetchCount(), 1);
    assert.equal(worker.fetchInits[0]?.cache, "no-store");
    assert.deepEqual(worker.openedCaches, []);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.match(response.headers.get("Content-Security-Policy"), /frame-ancestors 'none'/);
    assert.equal(response.headers.get("X-Frame-Options"), "DENY");
    assert.equal(response.headers.get("Referrer-Policy"), "no-referrer");
    assert.equal(response.headers.get("X-Content-Type-Options"), "nosniff");
  }
});

test("benign queried documents fall back offline to the canonical cached document", async () => {
  const worker = loadWorker("https://example.test/GymApp/", {
    fetchImpl: async () => { throw new TypeError("offline"); }
  });
  const handler = worker.listeners.get("fetch");
  const response = await responsePromiseFor(
    handler,
    "https://example.test/GymApp/index.html?utm_source=installed"
  );

  assert.equal(await response.text(), "cached");
  assert.deepEqual(worker.matchedRequests, ["https://example.test/GymApp/index.html"]);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(response.headers.get("X-Frame-Options"), "DENY");
});

test("sensitive callback network failures never fall back to cached HTML", async () => {
  const worker = loadWorker("https://example.test/GymApp/", {
    fetchImpl: async () => { throw new TypeError("offline"); }
  });
  const handler = worker.listeners.get("fetch");
  const state = "W".repeat(32);
  const response = responsePromiseFor(
    handler,
    `https://example.test/GymApp/confirmed.html?platform=android&state=${state}&code=secret-code`
  );

  await assert.rejects(response, /offline/);
  assert.deepEqual(worker.openedCaches, []);
  assert.deepEqual(worker.matchedRequests, []);
});

test("token-like asset queries are neither intercepted nor cached", () => {
  const handler = loadWorker().listeners.get("fetch");
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v52.js?provider_token=secret"), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/icon-512.png?access_token=secret"), false);
});

test("cached documents receive the same anti-framing policy", async () => {
  const worker = loadWorker();
  const handler = worker.listeners.get("fetch");
  const response = await responsePromiseFor(handler, "https://example.test/GymApp/");

  assert.equal(await response.text(), "cached");
  assert.deepEqual(worker.openedCaches, ["gym-pwa-v71"]);
  assert.match(response.headers.get("Content-Security-Policy"), /style-src 'self'/);
  assert.match(response.headers.get("Content-Security-Policy"), /frame-ancestors 'none'/);
  assert.doesNotMatch(response.headers.get("Content-Security-Policy"), /unsafe-inline/);
  assert.equal(response.headers.get("Cross-Origin-Opener-Policy"), "same-origin");
  assert.equal(response.headers.get("X-Frame-Options"), "DENY");
});

test("install reloads one internally consistent version without taking over old clients", async () => {
  const worker = loadWorker();
  const handler = worker.listeners.get("install");
  let installPromise = null;

  handler({ waitUntil(value) { installPromise = value; } });
  await installPromise;

  assert.deepEqual(worker.openedCaches, ["gym-pwa-v71"]);
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/app.v52.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/theme.v52.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/styles.v52.css")));
  assert.equal(worker.addedAssets.every(asset => asset instanceof Request && asset.cache === "reload"), true);
  assert.equal(worker.skipWaitingCount(), 0);
});

test("activation deletes only stale GymApp caches and does not claim old clients", async () => {
  const worker = loadWorker();
  const handler = worker.listeners.get("activate");
  let activationPromise = null;

  handler({ waitUntil(value) { activationPromise = value; } });
  await activationPromise;

  assert.deepEqual(
    worker.deletedCaches,
    ["gym-pwa-v39", "gym-pwa-v44", "gym-pwa-v59", "gym-pwa-v60", "gym-pwa-v61", "gym-pwa-v62", "gym-pwa-v64", "gym-pwa-v65"]
  );
  assert.equal(worker.claimCount(), 0);
  assert.equal(worker.matchAllCount(), 0);
});

test("legacy-origin worker cleans only its exact scope without touching sibling tabs or cache entries", async () => {
  const navigated = [];
  const client = url => ({
    url,
    navigate(nextUrl) {
      navigated.push([url, nextUrl]);
      return Promise.resolve();
    }
  });
  const scope = "https://eduard047.github.io/GymApp/";
  const siblingScope = "https://eduard047.github.io/gymapptracker-site/";
  const legacyCachedAsset = `${scope}app.v52.js`;
  const siblingCachedAsset = `${siblingScope}app.v52.js`;
  const worker = loadWorker(scope, {
    clients: [
      client(`${scope}index.html`),
      client(`${scope}confirmed.html?platform=android&code=one-time`),
      client(`${scope}legacy-origin-cleanup-v61.html`),
      client(`${siblingScope}index.html`)
    ],
    cacheEntries: {
      "gym-pwa-v59": [legacyCachedAsset, siblingCachedAsset],
      "gym-pwa-v60": [`${scope}index.html`]
    }
  });

  let installPromise = null;
  worker.listeners.get("install")({ waitUntil(value) { installPromise = value; } });
  await installPromise;
  assert.equal(worker.skipWaitingCount(), 1);
  assert.deepEqual(worker.openedCaches, []);

  let activationPromise = null;
  worker.listeners.get("activate")({ waitUntil(value) { activationPromise = value; } });
  await activationPromise;
  assert.deepEqual(worker.deletedCaches, []);
  assert.deepEqual(worker.deletedCacheEntries, [
    ["gym-pwa-v59", legacyCachedAsset],
    ["gym-pwa-v60", `${scope}index.html`]
  ]);
  assert.deepEqual(worker.remainingCacheEntries("gym-pwa-v59"), [siblingCachedAsset]);
  assert.equal(worker.claimCount(), 1);
  assert.equal(worker.matchAllCount(), 1);
  assert.deepEqual(navigated, [[
    `${scope}index.html`,
    `${scope}legacy-origin-cleanup-v61.html`
  ]]);

  const fetchHandler = worker.listeners.get("fetch");
  assert.equal(isIntercepted(fetchHandler, `${scope}confirmed.html?platform=android&code=one-time`, {
    modeOverride: "navigate"
  }), false);
  assert.equal(isIntercepted(fetchHandler, `${scope}legacy-origin-cleanup-v61.html`, {
    modeOverride: "navigate"
  }), false);
  const response = await responsePromiseFor(fetchHandler, `${scope}index.html`, {
    modeOverride: "navigate"
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("Location"), `${scope}legacy-origin-cleanup-v61.html`);
  assert.deepEqual(worker.fetchRequests, []);
});

test("a sibling github.io project scope never enters GymApp legacy cleanup", async () => {
  const scope = "https://eduard047.github.io/gymapptracker-site/";
  const worker = loadWorker(scope);
  let installPromise = null;

  worker.listeners.get("install")({ waitUntil(value) { installPromise = value; } });
  await installPromise;

  assert.equal(worker.skipWaitingCount(), 0);
  assert.deepEqual(worker.openedCaches, ["gym-pwa-v71"]);
  assert.equal(worker.claimCount(), 0);
  assert.equal(isIntercepted(worker.listeners.get("fetch"), scope), true);
});
