import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const cleanupSource = await readFile("pwa/legacy-origin-cleanup.js", "utf8");
const SESSION_KEY = "gym-pwa-supabase-session-v1";
const ACCOUNT_KEY = "gym-pwa-active-account-v1";
const GARMIN_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";

function storage(initial = {}, { removeThrows = false } = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem(key) {
      if (removeThrows) throw new Error("storage removal denied");
      values.delete(key);
    }
  };
}

function loadCleanup({
  url = "https://eduard047.github.io/GymApp/legacy-origin-cleanup.html",
  fetchImpl,
  localInitial = {},
  sessionInitial = {},
  localRemoveThrows = false,
  cacheDeleteResult = true,
  cacheDeleteRejects = false,
  unregisterResult = true,
  unregisterRejects = false
} = {}) {
  const parsed = new URL(url);
  const status = { textContent: "Preparing secure cleanup…" };
  const localStorage = storage(localInitial, { removeThrows: localRemoveThrows });
  const sessionStorage = storage(sessionInitial);
  const deletedCaches = [];
  const unregisteredScopes = [];
  const registrations = [
    {
      scope: "https://eduard047.github.io/GymApp/",
      async unregister() {
        unregisteredScopes.push(this.scope);
        if (unregisterRejects) throw new Error("worker unregister denied");
        return unregisterResult;
      }
    },
    {
      scope: "https://eduard047.github.io/another-app/",
      async unregister() { unregisteredScopes.push(this.scope); return true; }
    }
  ];
  const window = {
    __GYMAPP_TOP_LEVEL__: true,
    GYM_SUPABASE: {
      url: "https://owrcbsrectdgaotndtxy.supabase.co",
      anonKey: "publishable-test-key"
    },
    location: {
      origin: parsed.origin,
      pathname: parsed.pathname,
      search: parsed.search,
      hash: parsed.hash
    }
  };
  window.self = window;
  window.top = window;
  const context = {
    AbortController,
    Promise,
    TextEncoder,
    URL,
    clearTimeout,
    document: { querySelector: selector => selector === "#cleanup-status" ? status : null },
    fetch: fetchImpl || (async () => new Response(null, { status: 204 })),
    localStorage,
    sessionStorage,
    setTimeout,
    caches: {
      async keys() { return ["gym-pwa-v44", "another-app-cache"]; },
      async delete(name) {
        deletedCaches.push(name);
        if (cacheDeleteRejects) throw new Error("cache deletion denied");
        return cacheDeleteResult;
      }
    },
    navigator: {
      serviceWorker: {
        async getRegistrations() { return registrations; }
      }
    },
    window
  };
  window.caches = context.caches;
  window.navigator = context.navigator;
  vm.createContext(context);
  vm.runInContext(cleanupSource, context);
  return { context, status, localStorage, sessionStorage, deletedCaches, unregisteredScopes };
}

async function settleCleanup(result) {
  for (let attempt = 0; attempt < 20 && result.status.textContent === "Preparing secure cleanup…"; attempt += 1) {
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.notEqual(result.status.textContent, "Preparing secure cleanup…");
}

test("legacy cleanup erases credentials before awaiting server revocation", async () => {
  let resolveFetch;
  const pendingFetch = new Promise(resolve => {
    resolveFetch = resolve;
  });
  const result = loadCleanup({
    fetchImpl: async () => pendingFetch,
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "legacy-access-token-long-enough",
        refresh_token: "legacy-refresh-token-long-enough"
      }),
      [ACCOUNT_KEY]: "account-marker",
      [GARMIN_TOKEN_KEY]: "legacy-garmin-token"
    },
    sessionInitial: {
      [SESSION_KEY]: "tab-session",
      [ACCOUNT_KEY]: "tab-account"
    }
  });

  for (const key of [SESSION_KEY, ACCOUNT_KEY, GARMIN_TOKEN_KEY]) {
    assert.equal(result.localStorage.getItem(key), null, key);
    assert.equal(result.sessionStorage.getItem(key), null, key);
  }

  resolveFetch(new Response(null, { status: 204 }));
  await settleCleanup(result);
  assert.match(result.status.textContent, /were removed/i);
});

test("legacy cleanup refreshes one 401 and unregisters only the exact GymApp scope", async () => {
  const requests = [];
  const result = loadCleanup({
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      if (url.includes("grant_type=refresh_token")) {
        return new Response(JSON.stringify({
          access_token: "refreshed-access-token-long-enough"
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      if (requests.filter(request => request.url.includes("/logout?scope=local")).length === 1) {
        return new Response(null, { status: 401 });
      }
      return new Response(null, { status: 204 });
    },
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "expired-access-token-long-enough",
        refresh_token: "valid-refresh-token-long-enough"
      })
    }
  });

  await settleCleanup(result);

  assert.equal(requests.length, 3);
  assert.match(requests[0].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.match(requests[1].url, /\/auth\/v1\/token\?grant_type=refresh_token$/);
  assert.match(requests[2].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.equal(requests[2].options.headers.Authorization, "Bearer refreshed-access-token-long-enough");
  assert.deepEqual(result.deletedCaches, ["gym-pwa-v44"]);
  assert.deepEqual(result.unregisteredScopes, ["https://eduard047.github.io/GymApp/"]);
  assert.match(result.status.textContent, /were removed/i);
});

test("legacy cleanup does not treat an unrecoverable 401 as confirmed revocation", async () => {
  const result = loadCleanup({
    fetchImpl: async url => url.includes("grant_type=refresh_token")
      ? new Response(null, { status: 401 })
      : new Response(null, { status: 401 }),
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "expired-access-token-long-enough",
        refresh_token: "expired-refresh-token-long-enough"
      })
    }
  });

  await settleCleanup(result);

  assert.match(result.status.textContent, /could not be confirmed/i);
});

test("legacy cleanup never reports success when credential removal cannot be verified", async () => {
  const result = loadCleanup({
    localInitial: { [ACCOUNT_KEY]: "persistent-marker" },
    localRemoveThrows: true
  });

  await settleCleanup(result);

  assert.equal(result.localStorage.getItem(ACCOUNT_KEY), "persistent-marker");
  assert.match(result.status.textContent, /could not be fully verified/i);
});

test("legacy cleanup never reports success when a cache deletion returns false", async () => {
  const result = loadCleanup({ cacheDeleteResult: false });

  await settleCleanup(result);

  assert.deepEqual(result.deletedCaches, ["gym-pwa-v44"]);
  assert.match(result.status.textContent, /could not be fully verified/i);
});

test("legacy cleanup never reports success when worker unregister fails", async () => {
  for (const options of [
    { unregisterResult: false },
    { unregisterRejects: true }
  ]) {
    const result = loadCleanup(options);
    await settleCleanup(result);
    assert.deepEqual(result.unregisteredScopes, ["https://eduard047.github.io/GymApp/"]);
    assert.match(result.status.textContent, /could not be fully verified/i);
  }
});

test("legacy cleanup refuses alternate paths and queried cleanup URLs", async () => {
  for (const url of [
    "https://eduard047.github.io/another-app/legacy-origin-cleanup.html",
    "https://gymapptracker.com/legacy-origin-cleanup.html",
    "https://eduard047.github.io/GymApp/legacy-origin-cleanup.html?token=unexpected"
  ]) {
    let fetchCalls = 0;
    const result = loadCleanup({
      url,
      fetchImpl: async () => {
        fetchCalls += 1;
        return new Response(null, { status: 204 });
      },
      localInitial: { [ACCOUNT_KEY]: "keep-me" }
    });
    await settleCleanup(result);
    assert.equal(fetchCalls, 0, url);
    assert.equal(result.localStorage.getItem(ACCOUNT_KEY), "keep-me", url);
    assert.deepEqual(result.deletedCaches, [], url);
    assert.deepEqual(result.unregisteredScopes, [], url);
    assert.match(result.status.textContent, /no legacy-origin cleanup/i);
  }
});
