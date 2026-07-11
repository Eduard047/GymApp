import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");

function loadWorker(scope = "https://example.test/GymApp/") {
  const listeners = new Map();
  const openedCaches = [];
  const deletedCaches = [];
  const self = {
    registration: { scope },
    location: new URL(scope),
    clients: { claim() {} },
    skipWaiting() {},
    addEventListener(type, handler) {
      listeners.set(type, handler);
    }
  };
  const caches = {
    async keys() { return ["gym-pwa-v35", "gym-pwa-v36", "another-app-v4"]; },
    async open(name) {
      openedCaches.push(name);
      return {
        addAll: async () => {},
        match: async () => new Response("cached", { status: 200 })
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
    fetch: async () => new Response("network", { status: 200 }),
    self
  });

  return { listeners, openedCaches, deletedCaches };
}

function isIntercepted(handler, url, options = {}) {
  let responsePromise = null;
  handler({
    request: new Request(url, options),
    respondWith(value) {
      responsePromise = value;
    }
  });
  return responsePromise !== null;
}

test("service worker intercepts only allowlisted same-origin static assets", () => {
  const handler = loadWorker().listeners.get("fetch");

  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.js?v=27"), true);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/"), true);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/rest/v1/user_states"), false);
  assert.equal(isIntercepted(handler, "https://project.supabase.co/rest/v1/user_states"), false);
});

test("service worker ignores credential-bearing and non-GET requests", () => {
  const handler = loadWorker().listeners.get("fetch");

  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.js", {
    headers: { Authorization: "Bearer test-token" }
  }), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/confirmed.html?access_token=test"), false);
  assert.equal(isIntercepted(handler, "https://example.test/GymApp/app.js", { method: "POST" }), false);
});

test("service worker reads only the current app cache", async () => {
  const worker = loadWorker();
  const handler = worker.listeners.get("fetch");
  let responsePromise = null;

  handler({
    request: new Request("https://example.test/GymApp/app.js?v=27"),
    respondWith(value) { responsePromise = value; }
  });

  assert.equal(await (await responsePromise).text(), "cached");
  assert.deepEqual(worker.openedCaches, ["gym-pwa-v36"]);
});

test("service worker activation deletes only its own stale caches", async () => {
  const worker = loadWorker();
  const handler = worker.listeners.get("activate");
  let activationPromise = null;

  handler({
    waitUntil(value) { activationPromise = value; }
  });
  await activationPromise;

  assert.deepEqual(worker.deletedCaches, ["gym-pwa-v35"]);
});
