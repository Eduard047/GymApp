import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");
const appSource = readFileSync(new URL("../pwa/app.js", import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../pwa/manifest.webmanifest", import.meta.url), "utf8"));
const indexHtml = readFileSync(new URL("../pwa/index.html", import.meta.url), "utf8");
const confirmedHtml = readFileSync(new URL("../pwa/confirmed.html", import.meta.url), "utf8");
const workoutHtml = readFileSync(new URL("../pwa/workout/index.html", import.meta.url), "utf8");
const VERSIONED_ASSET_PAIRS = [
  ["confirmed.css", "confirmed.v56.css"],
  ["confirmed.js", "confirmed.v57.js"],
  ["frame-guard.js", "frame-guard.v56.js"],
  ["theme.js", "theme.v56.js"],
  ["styles.css", "styles.v79.css"],
  ["muscle-regions.js", "muscle-regions.v56.js"],
  ["supabase-config.js", "supabase-config.v58.js"],
  ["state-contract.js", "state-contract.v72.js"],
  ["garmin-cloud-sync.js", "garmin-cloud-sync.v57.js"],
  ["progression-rules.js", "progression-rules.v57.js"],
  ["shared-workout.js", "shared-workout.v66.js"],
  ["shared-workout-flow.js", "shared-workout-flow.v71.js"],
  ["russian-text.js", "russian-text.v86.js"],
  ["exercise-search-vocabulary.js", "exercise-search-vocabulary.v1.js"],
  ["supabase-realtime.js", "supabase-realtime.v1.js"],
  ["live-workout.js", "live-workout.v3.js"],
  ["live-workout-state.js", "live-workout-state.v1.js"],
  ["app.js", "app.v103.js"],
  ["workout/landing.css", "workout/landing.v2.css"],
  ["workout/landing.js", "workout/landing.v4.js"]
];
const EXERCISE_MEDIA_KEYS = [
  ...workerSource.match(/const EXERCISE_MEDIA_KEYS = \[([\s\S]*?)\];/)?.[1]
    .matchAll(/"([a-z0-9_]+)"/g) || []
].map(match => match[1]);
const CURRENT_MEDIA_PATHS = [
  ...EXERCISE_MEDIA_KEYS.flatMap(key => [
    `exercise-media/${key}_0.jpg`,
    `exercise-media/${key}_1.jpg`
  ]),
  "icon-192.png",
  "icon-512.png",
  "icon-maskable-192.png",
  "icon-maskable-512.png",
  "apple-touch-icon.png",
  "favicon-32.png"
];
const CURRENT_MEDIA_DIGEST = (() => {
  const hash = createHash("sha256");
  for (const path of CURRENT_MEDIA_PATHS.toSorted()) {
    hash.update(path).update("\0").update(readFileSync(new URL(`../pwa/${path}`, import.meta.url))).update("\0");
  }
  return hash.digest("hex").slice(0, 12);
})();

function fakeIndexedDb(initialBinding = null) {
  const values = new Map(initialBinding ? [["current", initialBinding]] : []);
  let storeCreated = initialBinding !== null;
  const requestFor = (transaction, operation) => {
    const request = { result: undefined, error: null, onsuccess: null, onerror: null };
    transaction.pending += 1;
    queueMicrotask(() => {
      try {
        request.result = operation();
        request.onsuccess?.();
      } catch (error) {
        request.error = error;
        request.onerror?.();
        transaction.error = error;
        transaction.onerror?.();
        transaction.onabort?.();
      } finally {
        transaction.pending -= 1;
        if (transaction.pending === 0 && !transaction.error) {
          queueMicrotask(() => transaction.pending === 0 && transaction.oncomplete?.());
        }
      }
    });
    return request;
  };
  const database = {
    objectStoreNames: { contains: name => storeCreated && name === "current-bindings" },
    createObjectStore(name) {
      if (name !== "current-bindings" || storeCreated) throw new Error("invalid store");
      storeCreated = true;
    },
    transaction(name) {
      if (name !== "current-bindings" || !storeCreated) throw new Error("missing store");
      const transaction = {
        pending: 0,
        error: null,
        onabort: null,
        onerror: null,
        oncomplete: null,
        objectStore() {
          return {
            get: key => requestFor(transaction, () => values.get(key)),
            put: (value, key) => requestFor(transaction, () => values.set(key, value)),
            delete: key => requestFor(transaction, () => values.delete(key))
          };
        }
      };
      return transaction;
    },
    close() {}
  };
  return {
    open() {
      const request = {
        result: database,
        error: null,
        onupgradeneeded: null,
        onsuccess: null,
        onerror: null,
        onblocked: null
      };
      queueMicrotask(() => {
        if (!storeCreated) request.onupgradeneeded?.();
        request.onsuccess?.();
      });
      return request;
    },
    values
  };
}

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
  const notifications = [];
  const openedWindows = [];
  const cacheContents = new Map();
  const indexedDB = fakeIndexedDb(options.pushBinding ?? null);
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
    registration: {
      scope,
      showNotification(title, notificationOptions) {
        notifications.push({ title, options: notificationOptions });
        return Promise.resolve();
      }
    },
    indexedDB,
    location: new URL(scope),
    clients: {
      claim() {
        claimCount += 1;
        return Promise.resolve();
      },
      matchAll() {
        matchAllCount += 1;
        return Promise.resolve(options.clients || []);
      },
      openWindow(url) {
        openedWindows.push(url);
        return Promise.resolve({ url });
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
      return options.cacheKeys || ["gym-pwa-v39", "gym-pwa-v44", "gym-pwa-v59", "gym-pwa-v60", "gym-pwa-v61", "gym-pwa-v62", "gym-pwa-v64", "gym-pwa-v65", "gym-pwa-v74", "gym-pwa-v75", "gym-pwa-v76", "gym-pwa-v77", "gym-pwa-v78", "gym-pwa-v85", "gym-pwa-v86", "gym-pwa-v92", "gym-pwa-v97", "gym-pwa-v98", "gym-pwa-v101", "gym-pwa-v102", "gym-pwa-v107", "gym-pwa-v108", "gym-pwa-v109", "gym-pwa-v122", "gym-pwa-v123", "gym-pwa-v131", "gym-pwa-v138", "gym-pwa-v139", "gym-pwa-v141", "gym-pwa-v142", "gym-pwa-media-v1-a93d1c50c244", "another-app-v4"];
    },
    async open(name) {
      openedCaches.push(name);
      const entries = cacheFor(name);
      return {
        async addAll(assets) {
          addedAssets.push(...assets);
          if (!options.installFetchImpl) return;
          const responses = await Promise.all(assets.map(asset => options.installFetchImpl(asset)));
          if (responses.some(response => !response?.ok)) {
            throw new TypeError("Cache.addAll received a non-success response.");
          }
        },
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
          if (options.cacheMatch) return options.cacheMatch(request, name);
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
    skipWaitingCount: () => skipWaitingCount,
    notifications,
    openedWindows,
    pushBindingValues: indexedDB.values
  };
}

function strictServedPwaAsset(request, scope = "https://example.test/GymApp/") {
  const url = new URL(typeof request === "string" ? request : request.url);
  const scopeUrl = new URL(scope);
  if (url.origin !== scopeUrl.origin || !url.pathname.startsWith(scopeUrl.pathname)) {
    return new Response("not found", { status: 404 });
  }
  const relativePath = decodeURIComponent(url.pathname.slice(scopeUrl.pathname.length)) || "index.html";
  try {
    const file = new URL(`../pwa/${relativePath}`, import.meta.url);
    return new Response(readFileSync(file), { status: 200 });
  } catch {
    return new Response("not found", { status: 404 });
  }
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

test("strict PWA fixture reads a served asset directly and rejects a missing asset", async () => {
  const served = strictServedPwaAsset("https://example.test/GymApp/app.v103.js");
  const missing = strictServedPwaAsset("https://example.test/GymApp/missing.v100.js");

  assert.equal(served.status, 200);
  assert.ok((await served.text()).length > 0);
  assert.equal(missing.status, 404);
  assert.equal(await missing.text(), "not found");
});

test("service worker caches only exact immutable current same-origin assets", () => {
  for (const scope of ["https://example.test/", "https://example.test/GymApp/"]) {
    const handler = loadWorker(scope).listeners.get("fetch");

    assert.equal(isIntercepted(handler, new URL("./app.v103.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./shared-workout.v66.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./shared-workout-flow.v71.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./workout/", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./workout/landing.v4.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./state-contract.v72.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./frame-guard.v56.js", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./icon-maskable-512.png", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./favicon-32.png", scope)), true);
    assert.equal(isIntercepted(handler, new URL("./app.js?v=51", scope)), false);
    assert.equal(isIntercepted(handler, new URL("./app.js", scope)), false);
    assert.equal(isIntercepted(handler, scope), true);
    assert.equal(isIntercepted(handler, new URL("./rest/v1/user_states", scope)), false);
    assert.equal(isIntercepted(handler, "https://project.supabase.co/rest/v1/user_states"), false);
  }
});

test("static fetches use the shell or content-versioned media cache exactly", async () => {
  const scope = "https://example.test/GymApp/";
  const worker = loadWorker(scope, {
    cacheMatch(_request, cacheName) {
      return new Response(cacheName, { status: 200 });
    }
  });
  const handler = worker.listeners.get("fetch");

  assert.equal(await (await responsePromiseFor(handler, `${scope}app.v103.js`)).text(), "gym-pwa-v144");
  assert.equal(
    await (await responsePromiseFor(handler, `${scope}exercise-media/bench_press_0.jpg`)).text(),
    "gym-pwa-media-v1-a93d1c50c244"
  );
  assert.deepEqual(worker.openedCaches, ["gym-pwa-v144", "gym-pwa-media-v1-a93d1c50c244"]);
});

test("media cache version is coupled to the exact public content bytes", () => {
  assert.equal(CURRENT_MEDIA_DIGEST, "a93d1c50c244");
  assert.match(workerSource, /const MEDIA_CACHE_VERSION = "v1-a93d1c50c244";/);
});

test("push handler accepts only the minimal opaque notification contract", async () => {
  const bindingId = "55555555-5555-4555-8555-555555555555";
  const worker = loadWorker("https://gymapptracker.com/", {
    pushBinding: {
      version: 1,
      bindingId,
      ownerId: "11111111-1111-4111-8111-111111111111"
    }
  });
  const handler = worker.listeners.get("push");
  let wait = null;
  handler({
    data: {
      json: () => ({
        version: 1,
        notification: {
          title: "Live workout invitation",
          body: "Open GymApp to join the workout.",
          tag: "live_room"
        },
        data: {
          version: 1,
          bindingId,
          kind: "invite",
          roomId: `lr_${"a".repeat(32)}`,
          roomRevision: 3
        }
      })
    },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.equal(worker.notifications.length, 1);
  assert.equal(worker.notifications[0].title, "Live workout invitation");
  assert.deepEqual(JSON.parse(JSON.stringify(worker.notifications[0].options.data)), {
    version: 1,
    bindingId,
    kind: "invite",
    roomId: `lr_${"a".repeat(32)}`,
    roomRevision: 3
  });
  assert.equal(JSON.stringify(worker.notifications[0]).includes("weight"), false);

  worker.pushBindingValues.set("transition", {
    version: 1,
    nextOwnerId: "33333333-3333-4333-8333-333333333333"
  });
  let transitionWait = null;
  handler({
    data: {
      json: () => ({
        version: 1,
        notification: { title: "Old invite", body: "Open GymApp", tag: "live_room" },
        data: {
          version: 1,
          bindingId,
          kind: "invite",
          roomId: `lr_${"a".repeat(32)}`,
          roomRevision: 3
        }
      })
    },
    waitUntil(value) { transitionWait = value; }
  });
  await transitionWait;
  assert.equal(worker.notifications.length, 1);
  worker.pushBindingValues.delete("transition");

  let rejectedWait = null;
  handler({
    data: {
      json: () => ({
        version: 1,
        notification: { title: "Invite", body: "Open GymApp", tag: "live" },
        data: {
          version: 1,
          bindingId,
          kind: "invite",
          roomId: `lr_${"a".repeat(32)}`,
          roomRevision: 3,
          url: "https://evil.example/"
        }
      })
    },
    waitUntil(value) { rejectedWait = value; }
  });
  assert.equal(rejectedWait, null);
  assert.equal(worker.notifications.length, 1);
});

test("service worker drops a delivery and click from a superseded account binding", async () => {
  const oldBindingId = "55555555-5555-4555-8555-555555555555";
  const worker = loadWorker("https://gymapptracker.com/", {
    pushBinding: {
      version: 1,
      bindingId: "66666666-6666-4666-8666-666666666666",
      ownerId: "33333333-3333-4333-8333-333333333333"
    }
  });
  const data = {
    version: 1,
    bindingId: oldBindingId,
    kind: "invite",
    roomId: `lr_${"a".repeat(32)}`,
    roomRevision: 3
  };
  let wait = null;
  worker.listeners.get("push")({
    data: {
      json: () => ({
        version: 1,
        notification: { title: "Old invite", body: "Open GymApp", tag: "live_room" },
        data
      })
    },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.equal(worker.notifications.length, 0);

  let closed = 0;
  wait = null;
  worker.listeners.get("notificationclick")({
    notification: { data, close() { closed += 1; } },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.equal(closed, 1);
  assert.deepEqual(worker.openedWindows, []);
});

test("notification clicks focus an existing app or open only an allowlisted same-origin route", async () => {
  const bindingId = "55555555-5555-4555-8555-555555555555";
  const pushBinding = {
    version: 1,
    bindingId,
    ownerId: "11111111-1111-4111-8111-111111111111"
  };
  const messages = [];
  let focused = 0;
  const existingClient = {
    url: "https://gymapptracker.com/",
    postMessage(value) { messages.push(value); },
    focus() { focused += 1; return Promise.resolve(); }
  };
  const existingWorker = loadWorker("https://gymapptracker.com/", {
    clients: [existingClient], pushBinding
  });
  let wait = null;
  let closed = 0;
  const data = {
    version: 1,
    bindingId,
    kind: "started",
    roomId: `lr_${"b".repeat(32)}`,
    roomRevision: 8
  };
  existingWorker.listeners.get("notificationclick")({
    notification: { data, close() { closed += 1; } },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.equal(closed, 1);
  assert.equal(focused, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(messages)), [{
    version: 1,
    type: "gymapp_notification_click",
    target: "live",
    bindingId,
    roomId: `lr_${"b".repeat(32)}`
  }]);
  assert.deepEqual(existingWorker.openedWindows, []);

  const newWorker = loadWorker("https://gymapptracker.com/GymApp/", { pushBinding });
  wait = null;
  newWorker.listeners.get("notificationclick")({
    notification: { data, close() {} },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.equal(newWorker.openedWindows.length, 1);
  const opened = new URL(newWorker.openedWindows[0]);
  assert.equal(opened.origin, "https://gymapptracker.com");
  assert.equal(opened.pathname, "/GymApp/");
  assert.equal(opened.searchParams.get("notification"), "live");
  assert.equal(opened.searchParams.get("binding"), bindingId);
  assert.equal(opened.searchParams.get("room"), `lr_${"b".repeat(32)}`);

  const socialWorker = loadWorker("https://gymapptracker.com/GymApp/", { pushBinding });
  wait = null;
  socialWorker.listeners.get("notificationclick")({
    notification: {
      data: {
        version: 1,
        bindingId,
        type: "friend_request_received",
        objectId: `f_${"c".repeat(32)}`,
        objectRevision: 2
      },
      close() {}
    },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.equal(socialWorker.openedWindows.length, 1);
  const socialOpened = new URL(socialWorker.openedWindows[0]);
  assert.equal(socialOpened.searchParams.get("notification"), "social");
  assert.equal(socialOpened.searchParams.get("binding"), bindingId);
  assert.equal(socialOpened.searchParams.has("room"), false);
  assert.equal(socialOpened.searchParams.get("social_type"), "friend_request_received");
  assert.equal(socialOpened.searchParams.get("object"), `f_${"c".repeat(32)}`);
  assert.equal(socialOpened.searchParams.get("revision"), "2");

  const socialMessages = [];
  const existingSocialWorker = loadWorker("https://gymapptracker.com/GymApp/", {
    pushBinding,
    clients: [{
      url: "https://gymapptracker.com/GymApp/",
      postMessage(value) { socialMessages.push(value); },
      focus() { return Promise.resolve(); }
    }]
  });
  wait = null;
  existingSocialWorker.listeners.get("notificationclick")({
    notification: {
      data: {
        version: 1,
        bindingId,
        type: "workout_invite_accepted",
        objectId: `wi_${"d".repeat(32)}`,
        objectRevision: 9
      },
      close() {}
    },
    waitUntil(value) { wait = value; }
  });
  await wait;
  assert.deepEqual(JSON.parse(JSON.stringify(socialMessages)), [{
    version: 1,
    type: "gymapp_notification_click",
    target: "social",
    bindingId,
    socialType: "workout_invite_accepted",
    objectId: `wi_${"d".repeat(32)}`,
    objectRevision: 9
  }]);
});

test("current versioned pathname assets cannot be mistaken for predecessor assets", () => {
  const predecessorPaths = new Set([
    "confirmed.css", "confirmed.js", "frame-guard.js", "theme.js", "styles.css",
    "muscle-regions.js", "supabase-config.js", "state-contract.js",
    "garmin-cloud-sync.js", "progression-rules.js", "shared-workout.js", "shared-workout-flow.js",
    "russian-text.js", "app.js", "workout/landing.css", "workout/landing.js"
  ]);
  const currentPaths = [
    "confirmed.v56.css", "confirmed.v57.js", "frame-guard.v56.js", "theme.v56.js", "styles.v79.css",
    "muscle-regions.v56.js", "supabase-config.v58.js", "state-contract.v72.js",
    "garmin-cloud-sync.v57.js", "progression-rules.v57.js", "shared-workout.v66.js",
    "shared-workout-flow.v71.js", "supabase-realtime.v1.js", "live-workout.v3.js",
    "live-workout-state.v1.js", "russian-text.v86.js", "exercise-search-vocabulary.v1.js", "app.v103.js",
    "workout/landing.v2.css", "workout/landing.v4.js"
  ];

  for (const pathname of currentPaths) {
    assert.equal(predecessorPaths.has(pathname), false, pathname);
    assert.match(workerSource, new RegExp(`\\./${pathname.replaceAll(".", "\\.")}`));
  }
  assert.doesNotMatch(workerSource, /\.\/app\.js\?v=51/);
});

test("every deployed versioned asset exists and is byte-identical to its canonical source", () => {
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
  assert.match(workoutHtml, /rel="icon" href="\.\.\/favicon-32\.png" type="image\/png" sizes="32x32"/);
  assert.match(workoutHtml, /rel="apple-touch-icon" href="\.\.\/apple-touch-icon\.png" sizes="180x180"/);
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

  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v103.js", {
    headers: { Authorization: "Bearer test-token" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/index.html", {
    headers: { apikey: "test-key" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v103.js", {
    headers: { Range: "bytes=0-10" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/index.html", {
    headers: { "If-Range": "etag" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v103.js", { method: "POST" }), false);
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
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.v103.js?provider_token=secret"), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/icon-512.png?access_token=secret"), false);
});

test("app shell documents revalidate against the network instead of pinning a cached release", async () => {
  const worker = loadWorker();
  const handler = worker.listeners.get("fetch");
  const response = await responsePromiseFor(handler, "https://example.test/GymApp/");

  assert.equal(await response.text(), "network");
  assert.equal(worker.fetchCount(), 1);
  assert.equal(worker.fetchInits[0]?.cache, "no-store");
  assert.deepEqual(worker.openedCaches, []);
  assert.deepEqual(worker.matchedRequests, []);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.match(response.headers.get("Content-Security-Policy"), /style-src 'self'/);
  assert.match(response.headers.get("Content-Security-Policy"), /frame-ancestors 'none'/);
  assert.doesNotMatch(response.headers.get("Content-Security-Policy"), /unsafe-inline/);
  assert.equal(response.headers.get("Cross-Origin-Opener-Policy"), "same-origin");
  assert.equal(response.headers.get("X-Frame-Options"), "DENY");
});

test("offline cached documents retain their exact security policy", async () => {
  for (const pathname of ["workout/", "workout/index.html"]) {
    const worker = loadWorker("https://example.test/GymApp/", {
      fetchImpl: async () => { throw new TypeError("offline"); }
    });
    const handler = worker.listeners.get("fetch");
    const response = await responsePromiseFor(handler, `https://example.test/GymApp/${pathname}`);
    const policy = response.headers.get("Content-Security-Policy");

    assert.equal(await response.text(), "cached");
    assert.deepEqual(worker.openedCaches, ["gym-pwa-v144"]);
    assert.match(policy, /default-src 'none'/);
    assert.match(policy, /connect-src 'none'/);
    assert.match(policy, /worker-src 'none'/);
    assert.match(policy, /frame-ancestors 'none'/);
    assert.doesNotMatch(policy, /supabase|unsafe-inline|unsafe-eval/);
    assert.equal(response.headers.get("Referrer-Policy"), "no-referrer");
    assert.equal(response.headers.get("X-Frame-Options"), "DENY");
  }
});

test("install reloads one internally consistent fully served version before promptly replacing retirement", async () => {
  const worker = loadWorker("https://example.test/GymApp/", {
    installFetchImpl: request => strictServedPwaAsset(request)
  });
  const handler = worker.listeners.get("install");
  let installPromise = null;

  handler({ waitUntil(value) { installPromise = value; } });
  await installPromise;

  assert.deepEqual(worker.openedCaches, ["gym-pwa-v144", "gym-pwa-media-v1-a93d1c50c244"]);
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/exercise-search-vocabulary.v1.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/app.v103.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/shared-workout.v66.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/shared-workout-flow.v71.js")));
  assert.equal(worker.addedAssets.some(asset => asset.url.endsWith("/workout/")), false);
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/workout/index.html")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/workout/landing.v4.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/theme.v56.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/styles.v79.css")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/russian-text.v86.js")));
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/exercise-media/bench_press_0.jpg")));
  assert.equal(worker.addedAssets.some(asset => /retirement(?:\.v1)?\.(?:js|css)$/.test(asset.url)), false);
  assert.equal(worker.addedAssets.every(asset => asset instanceof Request && asset.cache === "reload"), true);
  assert.equal(worker.skipWaitingCount(), 1);
});

test("a shell update reuses the complete content-versioned media cache", async () => {
  const scope = "https://example.test/GymApp/";
  const worker = loadWorker(scope, {
    cacheKeys: ["gym-pwa-v142", "gym-pwa-media-v1-a93d1c50c244"],
    cacheEntries: {
      "gym-pwa-media-v1-a93d1c50c244": CURRENT_MEDIA_PATHS.map(path => new URL(path, scope).href)
    },
    installFetchImpl: request => strictServedPwaAsset(request, scope)
  });
  let installPromise = null;

  worker.listeners.get("install")({ waitUntil(value) { installPromise = value; } });
  await installPromise;

  assert.deepEqual(worker.openedCaches, ["gym-pwa-v144", "gym-pwa-media-v1-a93d1c50c244"]);
  assert.equal(
    worker.addedAssets.some(asset => /\/exercise-media\/|\/(?:icon|apple-touch-icon|favicon-32)/.test(asset.url)),
    false
  );
  assert.ok(worker.addedAssets.some(asset => asset.url.endsWith("/app.v103.js")));
  assert.equal(worker.skipWaitingCount(), 1);
});

test("a rejected install leaves the active predecessor cache untouched", async () => {
  const scope = "https://example.test/GymApp/";
  const oldEntry = `${scope}app.v86.js`;
  const worker = loadWorker(scope, {
    cacheKeys: ["gym-pwa-v86", "another-app-v4"],
    cacheEntries: { "gym-pwa-v86": [oldEntry] },
    installFetchImpl: request => new Response("asset", {
      status: new URL(request.url).pathname.endsWith("/app.v103.js") ? 404 : 200
    })
  });
  let installPromise = null;

  worker.listeners.get("install")({ waitUntil(value) { installPromise = value; } });

  await assert.rejects(installPromise, /non-success response/);
  assert.equal(worker.skipWaitingCount(), 0);
  assert.deepEqual(worker.deletedCaches, []);
  assert.deepEqual(worker.remainingCacheEntries("gym-pwa-v86"), [oldEntry]);
});

test("activation deletes the entire retirement cache, claims clients, and preserves browser data", async () => {
  const navigated = [];
  const binding = {
    version: 1,
    bindingId: "55555555-5555-4555-8555-555555555555",
    ownerId: "11111111-1111-4111-8111-111111111111"
  };
  const worker = loadWorker("https://example.test/GymApp/", {
    pushBinding: binding,
    clients: [{
      url: "https://example.test/GymApp/?restored=1",
      navigate(url) { navigated.push(url); return Promise.resolve(); }
    }, {
      url: "https://example.test/GymApp/workout/#workout=opaque",
      navigate() { throw new Error("workout handoff must not be navigated"); }
    }]
  });
  const handler = worker.listeners.get("activate");
  let activationPromise = null;

  handler({ waitUntil(value) { activationPromise = value; } });
  await activationPromise;

  assert.deepEqual(
    worker.deletedCaches,
    ["gym-pwa-v39", "gym-pwa-v44", "gym-pwa-v59", "gym-pwa-v60", "gym-pwa-v61", "gym-pwa-v62", "gym-pwa-v64", "gym-pwa-v65", "gym-pwa-v74", "gym-pwa-v75", "gym-pwa-v76", "gym-pwa-v77", "gym-pwa-v78", "gym-pwa-v85", "gym-pwa-v86", "gym-pwa-v92", "gym-pwa-v97", "gym-pwa-v98", "gym-pwa-v101", "gym-pwa-v102", "gym-pwa-v107", "gym-pwa-v108", "gym-pwa-v109", "gym-pwa-v122", "gym-pwa-v123", "gym-pwa-v131", "gym-pwa-v138", "gym-pwa-v139", "gym-pwa-v141", "gym-pwa-v142"]
  );
  assert.equal(worker.claimCount(), 1);
  assert.equal(worker.matchAllCount(), 1);
  assert.deepEqual(navigated, ["https://example.test/GymApp/?restored=1&gymapp_sw_refresh=v144"]);
  assert.deepEqual(worker.pushBindingValues.get("current"), binding);
  assert.doesNotMatch(workerSource, /localStorage\.(?:clear|removeItem|setItem)|indexedDB\.deleteDatabase/);
});

test("activation schedules at most 32 refresh navigations without waiting for them", async () => {
  let navigationCount = 0;
  const clients = Array.from({ length: 40 }, (_, index) => ({
    url: `https://example.test/GymApp/?client=${index}`,
    navigate() {
      navigationCount += 1;
      return new Promise(() => {});
    }
  }));
  const worker = loadWorker("https://example.test/GymApp/", {
    cacheKeys: ["gym-pwa-v86", "gym-pwa-v139"],
    clients
  });
  let activationPromise = null;

  worker.listeners.get("activate")({ waitUntil(value) { activationPromise = value; } });
  await Promise.race([
    activationPromise,
    new Promise((_, reject) => setTimeout(
      () => reject(new Error("activation waited for client navigation")),
      100
    ))
  ]);

  assert.equal(navigationCount, 32);
  assert.deepEqual(worker.deletedCaches, ["gym-pwa-v86", "gym-pwa-v139"]);
  assert.equal(worker.claimCount(), 1);
});

test("an old controlled client advances to one consistent v144 document and bundle set", async () => {
  const scope = "https://example.test/GymApp/";
  const oldIndex = '<script src="./russian-text.v78.js"></script><script src="./app.v86.js"></script>';
  const navigated = [];
  const worker = loadWorker(scope, {
    cacheKeys: ["gym-pwa-v86", "gym-pwa-v138", "gym-pwa-v139", "another-app-v4"],
    installFetchImpl: request => strictServedPwaAsset(request, scope),
    cacheEntries: {
      "gym-pwa-v86": [scope, `${scope}index.html`, `${scope}app.v86.js`]
    },
    clients: [{
      url: scope,
      navigate(url) {
        navigated.push(url);
        return Promise.resolve({ url });
      }
    }],
    fetchImpl: async request => {
      const url = new URL(typeof request === "string" ? request : request.url);
      if (url.pathname === "/GymApp/" || url.pathname === "/GymApp/index.html") {
        return new Response(indexHtml, {
          status: 200,
          headers: { "Content-Type": "text/html; charset=utf-8" }
        });
      }
      throw new Error(`unexpected network request: ${url.href}`);
    },
    cacheMatch(request, cacheName) {
      const url = new URL(typeof request === "string" ? request : request.url);
      if (cacheName === "gym-pwa-v86" &&
          (url.pathname === "/GymApp/" || url.pathname === "/GymApp/index.html")) {
        return new Response(oldIndex, { status: 200 });
      }
      if (cacheName === "gym-pwa-v144" && url.pathname === "/GymApp/app.v103.js") {
        return new Response("current-app-v103", {
          status: 200,
          headers: { "Content-Type": "text/javascript; charset=utf-8" }
        });
      }
      return null;
    }
  });

  let installPromise = null;
  worker.listeners.get("install")({ waitUntil(value) { installPromise = value; } });
  await installPromise;
  let activationPromise = null;
  worker.listeners.get("activate")({ waitUntil(value) { activationPromise = value; } });
  await activationPromise;

  assert.deepEqual(worker.deletedCaches, ["gym-pwa-v86", "gym-pwa-v138", "gym-pwa-v139"]);
  assert.deepEqual(navigated, [`${scope}?gymapp_sw_refresh=v144`]);

  const fetchHandler = worker.listeners.get("fetch");
  const documentResponse = await responsePromiseFor(fetchHandler, navigated[0], {
    modeOverride: "navigate"
  });
  const currentDocument = await documentResponse.text();
  assert.equal(currentDocument, indexHtml);
  assert.match(currentDocument, /src="\.\/russian-text\.v86\.js"/);
  assert.match(currentDocument, /src="\.\/app\.v103\.js"/);
  assert.doesNotMatch(currentDocument, /russian-text\.v78\.js|app\.v86\.js/);
  assert.equal(documentResponse.headers.get("Cache-Control"), "no-store");

  const appResponse = await responsePromiseFor(fetchHandler, `${scope}app.v103.js`);
  assert.equal(await appResponse.text(), "current-app-v103");
  assert.equal(worker.fetchCount(), 1, "the immutable current bundle must come from the new cache");
  assert.deepEqual(worker.fetchRequests, [navigated[0]]);
  assert.match(appSource, /scrubServiceWorkerRefreshParameter\(\)/);
  assert.match(appSource, /searchParams\.delete\("gymapp_sw_refresh"\)/);
});

test("the current app removes only the one-time service-worker refresh marker", () => {
  const start = appSource.indexOf("function scrubServiceWorkerRefreshParameter()");
  const end = appSource.indexOf("\nfunction showToast", start);
  assert.ok(start >= 0 && end > start);
  const functionSource = appSource.slice(start, end);
  const replacements = [];
  const context = {
    URL,
    window: {
      location: {
        href: "https://example.test/GymApp/?utm_source=installed&gymapp_sw_refresh=v144#today"
      }
    },
    history: {
      state: { route: "today" },
      replaceState(...args) { replacements.push(args); }
    }
  };
  vm.runInNewContext(`${functionSource}; scrubServiceWorkerRefreshParameter();`, context);
  assert.deepEqual(replacements, [[
    context.history.state,
    "",
    "/GymApp/?utm_source=installed#today"
  ]]);

  context.window.location.href =
    "https://example.test/GymApp/?gymapp_sw_refresh=v144&gymapp_sw_refresh=v142";
  vm.runInNewContext(`${functionSource}; scrubServiceWorkerRefreshParameter();`, context);
  assert.equal(replacements.length, 1, "ambiguous external markers must not rewrite the URL");
  assert.ok(
    appSource.indexOf("if (!handleEmailConfirmationRedirect())") <
      appSource.indexOf("scrubServiceWorkerRefreshParameter();"),
    "auth callbacks must be validated before the benign update marker is removed"
  );
});

test("the current app explicitly checks an existing registration for future worker updates", async () => {
  const start = appSource.indexOf("async function registerCurrentServiceWorker()");
  const end = appSource.indexOf("\nif (\"serviceWorker\" in navigator)", start);
  assert.ok(start >= 0 && end > start);
  const functionSource = appSource.slice(start, end);
  const calls = [];
  const registration = {
    active: { scriptURL: "https://example.test/GymApp/sw.js" },
    async update() { calls.push("update"); }
  };
  const context = {
    navigator: {
      serviceWorker: {
        async register(url, options) {
          calls.push([url, options]);
          return registration;
        }
      }
    }
  };

  await vm.runInNewContext(`${functionSource}; registerCurrentServiceWorker();`, context);

  assert.equal(calls.length, 2);
  assert.equal(calls[0][0], "./sw.js");
  assert.equal(calls[0][1].updateViaCache, "none");
  assert.equal(calls[1], "update");
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
  const legacyCachedAsset = `${scope}app.v59.js`;
  const siblingCachedAsset = `${siblingScope}app.v59.js`;
  const worker = loadWorker(scope, {
    clients: [
      client(`${scope}index.html`),
      client(`${scope}confirmed.html?platform=android&code=one-time`),
      client(`${scope}legacy-origin-cleanup-v62.html`),
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
    `${scope}legacy-origin-cleanup-v62.html`
  ]]);

  const fetchHandler = worker.listeners.get("fetch");
  assert.equal(isIntercepted(fetchHandler, `${scope}confirmed.html?platform=android&code=one-time`, {
    modeOverride: "navigate"
  }), false);
  assert.equal(isIntercepted(fetchHandler, `${scope}legacy-origin-cleanup-v62.html`, {
    modeOverride: "navigate"
  }), false);
  const response = await responsePromiseFor(fetchHandler, `${scope}index.html`, {
    modeOverride: "navigate"
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("Location"), `${scope}legacy-origin-cleanup-v62.html`);
  assert.deepEqual(worker.fetchRequests, []);
});

test("a sibling github.io project scope never enters GymApp legacy cleanup", async () => {
  const scope = "https://eduard047.github.io/gymapptracker-site/";
  const worker = loadWorker(scope);
  let installPromise = null;

  worker.listeners.get("install")({ waitUntil(value) { installPromise = value; } });
  await installPromise;

  assert.equal(worker.skipWaitingCount(), 1);
  assert.deepEqual(worker.openedCaches, ["gym-pwa-v144", "gym-pwa-media-v1-a93d1c50c244"]);
  assert.equal(worker.claimCount(), 0);
  assert.equal(isIntercepted(worker.listeners.get("fetch"), scope), true);
});
