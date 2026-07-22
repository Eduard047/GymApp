import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const cleanupSource = await readFile("pwa/legacy-origin-cleanup.js", "utf8");
const legacyEntrySource = await readFile("pwa/legacy-origin-index.html", "utf8");
const legacyAliasSource = await readFile("pwa/legacy-origin-cleanup.html", "utf8");
const legacyCleanupDocumentSource = await readFile("pwa/legacy-origin-cleanup-v61.html", "utf8");
const SESSION_KEY = "gym-pwa-supabase-session-v1";
const SESSION_REVOCATION_MARKER_KEY = "gym-pwa-legacy-session-revocation-pending-v1";
const ACCOUNT_KEY = "gym-pwa-active-account-v1";
const GARMIN_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";
const STATE_KEY = "gym-pwa-state-v2";
const GARMIN_BINDINGS_KEY = "gym-pwa-garmin-device-bindings-v2";
const GARMIN_ENQUEUE_REQUESTS_KEY = "gym-pwa-garmin-enqueue-requests-v1";
const LEGACY_CACHED_ASSET = "https://eduard047.github.io/GymApp/app.v52.js";
const SIBLING_CACHED_ASSET = "https://eduard047.github.io/another-app/app.js";

function storage(initial = {}, {
  getThrows = false,
  keyThrows = false,
  removeThrows = false,
  removeThrowsFor = []
} = {}) {
  const values = new Map(Object.entries(initial));
  const deniedRemovals = new Set(removeThrowsFor);
  return {
    get length() { return values.size; },
    key(index) {
      if (keyThrows) throw new Error("storage enumeration denied");
      return [...values.keys()][index] ?? null;
    },
    getItem(key) {
      if (getThrows) throw new Error("storage read denied");
      return values.get(key) ?? null;
    },
    setItem: (key, value) => values.set(key, String(value)),
    removeItem(key) {
      if (removeThrows || deniedRemovals.has(key)) throw new Error("storage removal denied");
      values.delete(key);
    }
  };
}

function loadCleanup({
  url = "https://eduard047.github.io/GymApp/legacy-origin-cleanup-v61.html",
  fetchImpl,
  localInitial = {},
  sessionInitial = {},
  localGetThrows = false,
  sessionGetThrows = false,
  localGetterThrows = false,
  sessionGetterThrows = false,
  localRemoveThrows = false,
  localRemoveThrowsFor = [],
  confirmResult = true,
  confirmImpl = null,
  cacheDeleteResult = true,
  cacheDeleteRejects = false,
  unregisterResult = true,
  unregisterRejects = false
} = {}) {
  const parsed = new URL(url);
  const status = { textContent: "Preparing secure cleanup…" };
  const dataSummary = { textContent: "", hidden: true };
  function actionButton() {
    let listener = null;
    return {
      hidden: true,
      disabled: false,
      lastEvent: null,
      addEventListener(type, nextListener) {
        if (type === "click") listener = nextListener;
      },
      click() {
        if (this.disabled) return undefined;
        this.lastEvent = {
          defaultPrevented: false,
          preventDefault() { this.defaultPrevented = true; }
        };
        return listener?.(this.lastEvent);
      }
    };
  }
  const continueLink = actionButton();
  const retryButton = actionButton();
  const backupButton = actionButton();
  const purgeButton = actionButton();
  const downloads = [];
  const objectUrls = new Map();
  let objectUrlSequence = 0;
  class RuntimeURL extends URL {
    static createObjectURL(blob) {
      const url = `blob:legacy-cleanup-${++objectUrlSequence}`;
      objectUrls.set(url, blob);
      return url;
    }

    static revokeObjectURL(url) {
      objectUrls.delete(url);
    }
  }
  const localStorage = storage(localInitial, {
    getThrows: localGetThrows,
    removeThrows: localRemoveThrows,
    removeThrowsFor: localRemoveThrowsFor
  });
  const sessionStorage = storage(sessionInitial, { getThrows: sessionGetThrows });
  const deletedCacheEntries = [];
  const cacheContents = new Map([
    ["gym-pwa-v44", new Map([
      [LEGACY_CACHED_ASSET, new Request(LEGACY_CACHED_ASSET)],
      [SIBLING_CACHED_ASSET, new Request(SIBLING_CACHED_ASSET)]
    ])],
    ["another-app-cache", new Map([
      [SIBLING_CACHED_ASSET, new Request(SIBLING_CACHED_ASSET)]
    ])]
  ]);
  const unregisteredScopes = [];
  const navigations = [];
  const windowListeners = new Map();
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
      hash: parsed.hash,
      assign(nextUrl) { navigations.push(nextUrl); }
    },
    addEventListener(type, listener) { windowListeners.set(type, listener); },
    confirm: message => typeof confirmImpl === "function"
      ? confirmImpl({ message, localStorage, sessionStorage })
      : confirmResult
  };
  if (localGetterThrows) {
    Object.defineProperty(window, "localStorage", {
      get() { throw new Error("localStorage getter denied"); }
    });
  } else {
    window.localStorage = localStorage;
  }
  if (sessionGetterThrows) {
    Object.defineProperty(window, "sessionStorage", {
      get() { throw new Error("sessionStorage getter denied"); }
    });
  } else {
    window.sessionStorage = sessionStorage;
  }
  window.self = window;
  window.top = window;
  const context = {
    AbortController,
    Blob,
    Promise,
    TextDecoder,
    TextEncoder,
    URL: RuntimeURL,
    clearTimeout,
    document: {
      createElement(tagName) {
        assert.equal(tagName, "a");
        return {
          href: "",
          download: "",
          click() {
            downloads.push({
              href: this.href,
              download: this.download,
              blob: objectUrls.get(this.href) || null
            });
          }
        };
      },
      querySelector(selector) {
        if (selector === "#cleanup-status") return status;
        if (selector === "#cleanup-data-summary") return dataSummary;
        if (selector === "#cleanup-continue") return continueLink;
        if (selector === "#cleanup-retry") return retryButton;
        if (selector === "#cleanup-backup") return backupButton;
        if (selector === "#cleanup-purge") return purgeButton;
        return null;
      }
    },
    fetch: fetchImpl || (async () => new Response(null, { status: 204 })),
    localStorage,
    sessionStorage,
    setTimeout,
    caches: {
      async keys() { return [...cacheContents.keys()]; },
      async open(name) {
        const entries = cacheContents.get(name) || new Map();
        cacheContents.set(name, entries);
        return {
          async keys() { return [...entries.values()]; },
          async delete(request) {
            const url = typeof request === "string" ? request : request.url;
            deletedCacheEntries.push([name, url]);
            if (cacheDeleteRejects) throw new Error("cache deletion denied");
            if (!cacheDeleteResult) return false;
            entries.delete(url);
            return true;
          }
        };
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
  return {
    context,
    status,
    dataSummary,
    continueLink,
    retryButton,
    backupButton,
    purgeButton,
    downloads,
    objectUrls,
    navigations,
    fireStorage(key) { windowListeners.get("storage")?.({ key }); },
    localStorage,
    sessionStorage,
    deletedCacheEntries,
    remainingCacheEntries(name) { return [...(cacheContents.get(name)?.keys() || [])]; },
    unregisteredScopes
  };
}

async function settleCleanup(result) {
  for (let attempt = 0; attempt < 20 && result.status.textContent === "Preparing secure cleanup…"; attempt += 1) {
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.notEqual(result.status.textContent, "Preparing secure cleanup…");
}

test("legacy entry navigates only to the exact same-origin cleanup document", () => {
  for (const source of [legacyEntrySource, legacyAliasSource]) {
    assert.match(
      source,
      /http-equiv="refresh" content="0; url=\.\/legacy-origin-cleanup-v61\.html"/
    );
    assert.match(source, /href="\.\/legacy-origin-cleanup-v61\.html"/);
    assert.match(source, /href="\.\/legacy-origin-cleanup\.css\?v=61"/);
    assert.doesNotMatch(source, /<script\b/i);
    assert.doesNotMatch(source, /https?:\/\//i);
  }
});

test("active legacy cleanup fingerprints every mutable cleanup asset", () => {
  assert.match(
    legacyCleanupDocumentSource,
    /href="\.\/legacy-origin-cleanup\.css\?v=61"/
  );
  assert.match(
    legacyCleanupDocumentSource,
    /src="\.\/legacy-origin-cleanup\.js\?v=61" defer/
  );
  assert.doesNotMatch(
    legacyCleanupDocumentSource,
    /(?:href|src)="\.\/legacy-origin-cleanup\.(?:css|js)"/
  );
});

test("legacy cleanup erases credentials before awaiting server revocation", async () => {
  let resolveFetch;
  const pendingFetch = new Promise(resolve => {
    resolveFetch = resolve;
  });
  const result = loadCleanup({
    fetchImpl: async url => url.includes("grant_type=refresh_token")
      ? new Response(null, { status: 401 })
      : pendingFetch,
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "legacy-access-token-long-enough",
        refresh_token: "legacy-refresh-token-long-enough"
      }),
      [ACCOUNT_KEY]: "account-marker",
      [GARMIN_TOKEN_KEY]: "legacy-garmin-token"
    },
    sessionInitial: {
      [ACCOUNT_KEY]: "tab-account"
    }
  });

  for (const key of [SESSION_KEY, GARMIN_TOKEN_KEY]) {
    assert.equal(result.localStorage.getItem(key), null, key);
    assert.equal(result.sessionStorage.getItem(key), null, key);
  }
  assert.equal(result.localStorage.getItem(ACCOUNT_KEY), "account-marker");
  assert.equal(result.sessionStorage.getItem(ACCOUNT_KEY), "tab-account");
  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.retryButton.hidden, true);

  resolveFetch(new Response(null, { status: 204 }));
  await settleCleanup(result);
  assert.match(result.status.textContent, /explicit private-data cleanup/i);
  assert.equal(result.backupButton.hidden, false);
  assert.equal(result.purgeButton.disabled, true);
  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.retryButton.hidden, true);
});

test("a session recreated during asynchronous cleanup is also erased and revoked", async () => {
  let resolveFetch;
  let requestCount = 0;
  const pendingFetch = new Promise(resolve => {
    resolveFetch = resolve;
  });
  const result = loadCleanup({
    fetchImpl: async () => {
      requestCount += 1;
      return pendingFetch;
    },
    localInitial: {
      [SESSION_KEY]: JSON.stringify({ access_token: "first-access-token-long-enough" })
    }
  });

  assert.equal(result.localStorage.getItem(SESSION_KEY), null);
  result.localStorage.setItem(
    SESSION_KEY,
    JSON.stringify({ access_token: "recreated-access-token-long-enough" })
  );
  resolveFetch(new Response(null, { status: 204 }));
  await settleCleanup(result);

  assert.equal(requestCount, 2);
  assert.equal(result.localStorage.getItem(SESSION_KEY), null);
  assert.equal(result.localStorage.getItem(SESSION_REVOCATION_MARKER_KEY), null);
  assert.equal(result.continueLink.hidden, false);
});

test("continuation performs a final runtime and storage check before navigation", async () => {
  const result = loadCleanup();
  await settleCleanup(result);
  assert.equal(result.continueLink.hidden, false);

  await result.continueLink.click();

  assert.equal(result.continueLink.lastEvent.defaultPrevented, true);
  assert.deepEqual(result.navigations, ["https://gymapptracker.com/"]);
  assert.deepEqual(result.deletedCacheEntries, [["gym-pwa-v44", LEGACY_CACHED_ASSET]]);
  assert.deepEqual(result.remainingCacheEntries("gym-pwa-v44"), [SIBLING_CACHED_ASSET]);
});

test("continuation is blocked when private data is recreated before the click", async () => {
  const result = loadCleanup();
  await settleCleanup(result);
  result.localStorage.setItem(STATE_KEY, JSON.stringify({ sessions: [{ id: 11 }] }));

  await result.continueLink.click();

  assert.deepEqual(result.navigations, []);
  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.backupButton.hidden, false);
  assert.notEqual(result.localStorage.getItem(STATE_KEY), null);
});

test("continuation restarts revocation when a credential is recreated before the click", async () => {
  let requestCount = 0;
  const result = loadCleanup({
    fetchImpl: async () => {
      requestCount += 1;
      return new Response(null, { status: 204 });
    }
  });
  await settleCleanup(result);
  result.localStorage.setItem(
    SESSION_KEY,
    JSON.stringify({ access_token: "late-access-token-long-enough" })
  );

  await result.continueLink.click();
  await settleCleanup(result);

  assert.deepEqual(result.navigations, []);
  assert.equal(requestCount, 1);
  assert.equal(result.localStorage.getItem(SESSION_KEY), null);
  assert.equal(result.continueLink.hidden, false);
});

test("legacy cleanup revokes a session stored only in sessionStorage", async () => {
  const requests = [];
  const result = loadCleanup({
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return new Response(null, { status: url.includes("grant_type=refresh_token") ? 401 : 204 });
    },
    sessionInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "tab-only-access-token-long-enough",
        refresh_token: "tab-only-refresh-token-long-enough"
      })
    }
  });

  await settleCleanup(result);

  assert.equal(requests.length, 2);
  assert.match(requests[0].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.equal(
    requests[0].options.headers.Authorization,
    "Bearer tab-only-access-token-long-enough"
  );
  assert.equal(result.sessionStorage.getItem(SESSION_KEY), null);
  assert.match(result.status.textContent, /were removed/i);
});

test("legacy cleanup revokes distinct bounded sessions from both stores", async () => {
  const authorizationHeaders = [];
  const result = loadCleanup({
    fetchImpl: async (url, options) => {
      if (options.headers.Authorization) authorizationHeaders.push(options.headers.Authorization);
      return new Response(null, { status: url.includes("grant_type=refresh_token") ? 401 : 204 });
    },
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "local-access-token-long-enough",
        refresh_token: "local-refresh-token-long-enough"
      })
    },
    sessionInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "tab-access-token-long-enough",
        refresh_token: "tab-refresh-token-long-enough"
      })
    }
  });

  await settleCleanup(result);

  assert.deepEqual(authorizationHeaders.sort(), [
    "Bearer local-access-token-long-enough",
    "Bearer tab-access-token-long-enough"
  ]);
  assert.equal(result.localStorage.getItem(SESSION_KEY), null);
  assert.equal(result.sessionStorage.getItem(SESSION_KEY), null);
  assert.match(result.status.textContent, /were removed/i);
});

test("legacy cleanup revokes a duplicated session only once", async () => {
  let requestCount = 0;
  const storedSession = JSON.stringify({
    access_token: "shared-access-token-long-enough",
    refresh_token: "shared-refresh-token-long-enough"
  });
  const result = loadCleanup({
    fetchImpl: async url => {
      requestCount += 1;
      return new Response(null, { status: url.includes("grant_type=refresh_token") ? 401 : 204 });
    },
    localInitial: { [SESSION_KEY]: storedSession },
    sessionInitial: { [SESSION_KEY]: storedSession }
  });

  await settleCleanup(result);

  assert.equal(requestCount, 2);
  assert.match(result.status.textContent, /were removed/i);
});

test("legacy cleanup revokes both sides of a mismatched access and refresh pair", async () => {
  const requests = [];
  const result = loadCleanup({
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      if (url.includes("grant_type=refresh_token")) {
        return new Response(JSON.stringify({
          access_token: "refreshed-mismatched-access-token"
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return new Response(null, { status: 204 });
    },
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "first-session-access-token",
        refresh_token: "different-session-refresh-token"
      })
    }
  });

  await settleCleanup(result);

  assert.equal(requests.length, 3);
  assert.equal(requests[0].options.headers.Authorization, "Bearer first-session-access-token");
  assert.match(requests[1].url, /grant_type=refresh_token/);
  assert.equal(requests[2].options.headers.Authorization, "Bearer refreshed-mismatched-access-token");
  assert.equal(result.continueLink.hidden, false);
});

test("oversized refresh responses fail closed before body parsing", async () => {
  const result = loadCleanup({
    fetchImpl: async url => url.includes("grant_type=refresh_token")
      ? new Response("{}", {
          status: 200,
          headers: { "Content-Length": String(64 * 1024 + 1) }
        })
      : new Response(null, { status: 204 }),
    localInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "bounded-access-token-long-enough",
        refresh_token: "bounded-refresh-token-long-enough"
      })
    }
  });

  await settleCleanup(result);

  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.localStorage.getItem(SESSION_REVOCATION_MARKER_KEY), "1");
  assert.match(result.status.textContent, /revocation could not be confirmed/i);
});

test("legacy cleanup fails closed for malformed or oversized stored sessions", async () => {
  for (const raw of [
    "not-json",
    JSON.stringify({ refresh_token: "short" }),
    "x".repeat(64 * 1024 + 1)
  ]) {
    const result = loadCleanup({ localInitial: { [SESSION_KEY]: raw } });
    await settleCleanup(result);

    assert.equal(result.localStorage.getItem(SESSION_KEY), null);
    assert.equal(result.continueLink.hidden, true);
    assert.equal(result.backupButton.hidden, true);
    assert.match(result.status.textContent, /revocation could not be confirmed/i);
  }
});

test("legacy cleanup handles storage read and getter failures without reporting success", async () => {
  for (const options of [
    { localGetThrows: true },
    { sessionGetThrows: true },
    { localGetterThrows: true },
    { sessionGetterThrows: true }
  ]) {
    const result = loadCleanup(options);
    await settleCleanup(result);

    assert.equal(result.continueLink.hidden, true);
    assert.equal(result.backupButton.hidden, true);
    assert.doesNotMatch(result.status.textContent, /^Preparing secure cleanup/);
    assert.match(result.status.textContent, /could not|revocation/i);
  }
});

test("an unavailable marker store does not prevent erasing and revoking an accessible tab session", async () => {
  let requestCount = 0;
  const result = loadCleanup({
    localGetterThrows: true,
    fetchImpl: async () => {
      requestCount += 1;
      return new Response(null, { status: 204 });
    },
    sessionInitial: {
      [SESSION_KEY]: JSON.stringify({ access_token: "tab-access-token-without-refresh" })
    }
  });
  await settleCleanup(result);

  assert.equal(requestCount, 1);
  assert.equal(result.sessionStorage.getItem(SESSION_KEY), null);
  assert.equal(result.continueLink.hidden, true);
  assert.match(result.status.textContent, /could not be fully verified|revocation/i);
});

test("private legacy data requires a bounded backup and confirmation before purge", async () => {
  const state = JSON.stringify({ language: "en", sessions: [{ id: 7, note: "private" }] });
  const pendingGarminPlan = JSON.stringify({
    pending: { planJson: JSON.stringify({ name: "Private pending watch plan" }) }
  });
  const result = loadCleanup({
    localInitial: {
      [ACCOUNT_KEY]: JSON.stringify({ id: "local-v2-test", name: "Private account" }),
      [STATE_KEY]: state,
      [GARMIN_BINDINGS_KEY]: JSON.stringify({ old: { version: 2, deviceToken: "do-not-back-up" } }),
      [GARMIN_ENQUEUE_REQUESTS_KEY]: pendingGarminPlan,
      "another-app-key": "preserve"
    }
  });
  await settleCleanup(result);

  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.backupButton.hidden, false);
  assert.equal(result.purgeButton.hidden, false);
  assert.equal(result.purgeButton.disabled, true);

  result.backupButton.click();
  assert.equal(result.downloads.length, 1);
  assert.match(result.downloads[0].download, /^gymapp-legacy-private-backup-/);
  assert.ok(result.downloads[0].blob instanceof Blob);
  const archive = JSON.parse(await result.downloads[0].blob.text());
  assert.equal(archive.source, "legacy-origin-browser-storage");
  assert.deepEqual(
    archive.entries.map(entry => entry.key).sort(),
    [ACCOUNT_KEY, STATE_KEY, GARMIN_ENQUEUE_REQUESTS_KEY].sort()
  );
  assert.doesNotMatch(JSON.stringify(archive.entries), /do-not-back-up/);
  assert.match(JSON.stringify(archive.entries), /Private pending watch plan/);
  assert.equal(archive.excluded.includes(GARMIN_ENQUEUE_REQUESTS_KEY), false);
  assert.equal(result.purgeButton.disabled, false);
  assert.equal(result.continueLink.hidden, true);

  result.purgeButton.click();
  assert.equal(result.localStorage.getItem(ACCOUNT_KEY), null);
  assert.equal(result.localStorage.getItem(STATE_KEY), null);
  assert.equal(result.localStorage.getItem(GARMIN_BINDINGS_KEY), null);
  assert.equal(result.localStorage.getItem(GARMIN_ENQUEUE_REQUESTS_KEY), null);
  assert.equal(result.localStorage.getItem("another-app-key"), "preserve");
  assert.equal(result.continueLink.hidden, false);
  assert.match(result.status.textContent, /access token expires/i);
});

test("private legacy data is preserved when purge confirmation is declined", async () => {
  const result = loadCleanup({
    confirmResult: false,
    localInitial: { [STATE_KEY]: JSON.stringify({ sessions: [] }) }
  });
  await settleCleanup(result);

  result.backupButton.click();
  result.purgeButton.click();

  assert.notEqual(result.localStorage.getItem(STATE_KEY), null);
  assert.equal(result.continueLink.hidden, true);
});

test("private legacy data changed after backup cannot be purged from a stale snapshot", async () => {
  const original = JSON.stringify({ sessions: [] });
  const changed = JSON.stringify({ sessions: [{ id: 9 }] });
  const result = loadCleanup({ localInitial: { [STATE_KEY]: original } });
  await settleCleanup(result);

  result.backupButton.click();
  result.localStorage.setItem(STATE_KEY, changed);
  result.purgeButton.click();

  assert.equal(result.localStorage.getItem(STATE_KEY), changed);
  assert.equal(result.purgeButton.disabled, true);
  assert.equal(result.continueLink.hidden, true);
  assert.match(result.status.textContent, /download a fresh backup/i);
});

test("private legacy data changed while confirmation is open is never purged", async () => {
  const original = JSON.stringify({ sessions: [] });
  const changed = JSON.stringify({ sessions: [{ id: 10 }] });
  const result = loadCleanup({
    localInitial: { [STATE_KEY]: original },
    confirmImpl: ({ localStorage }) => {
      localStorage.setItem(STATE_KEY, changed);
      return true;
    }
  });
  await settleCleanup(result);

  result.backupButton.click();
  result.purgeButton.click();

  assert.equal(result.localStorage.getItem(STATE_KEY), changed);
  assert.equal(result.purgeButton.disabled, true);
  assert.equal(result.continueLink.hidden, true);
  assert.match(result.status.textContent, /changed while confirmation was open/i);
});

test("metadata-only partial purge remains explicitly retryable", async () => {
  const result = loadCleanup({
    localInitial: { [GARMIN_BINDINGS_KEY]: "binding-metadata" },
    localRemoveThrowsFor: [GARMIN_BINDINGS_KEY]
  });
  await settleCleanup(result);

  assert.equal(result.backupButton.hidden, true);
  assert.equal(result.purgeButton.disabled, false);
  result.purgeButton.click();

  assert.equal(result.localStorage.getItem(GARMIN_BINDINGS_KEY), "binding-metadata");
  assert.equal(result.backupButton.hidden, true);
  assert.equal(result.purgeButton.hidden, false);
  assert.equal(result.purgeButton.disabled, false);
  assert.equal(result.continueLink.hidden, true);
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
  assert.deepEqual(result.deletedCacheEntries, [["gym-pwa-v44", LEGACY_CACHED_ASSET]]);
  assert.deepEqual(result.remainingCacheEntries("gym-pwa-v44"), [SIBLING_CACHED_ASSET]);
  assert.deepEqual(result.unregisteredScopes, ["https://eduard047.github.io/GymApp/"]);
  assert.match(result.status.textContent, /were removed/i);
});

test("invalid access and refresh credentials are treated as already unusable", async () => {
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

  assert.match(result.status.textContent, /were removed/i);
  assert.equal(result.localStorage.getItem(SESSION_REVOCATION_MARKER_KEY), null);
  assert.equal(result.continueLink.hidden, false);
  assert.equal(result.retryButton.hidden, true);
});

test("an interrupted revocation marker remains fail-closed after reload", async () => {
  const result = loadCleanup({
    localInitial: { [SESSION_REVOCATION_MARKER_KEY]: "1" }
  });
  await settleCleanup(result);

  assert.equal(result.localStorage.getItem(SESSION_REVOCATION_MARKER_KEY), "1");
  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.backupButton.hidden, true);
  assert.match(result.status.textContent, /revocation could not be confirmed/i);
});

test("failed server revocation remains retryable before continuation", async () => {
  let serverAvailable = false;
  let requestCount = 0;
  const result = loadCleanup({
    fetchImpl: async url => {
      requestCount += 1;
      if (serverAvailable && url.includes("grant_type=refresh_token")) {
        return new Response(null, { status: 401 });
      }
      return new Response(null, { status: serverAvailable ? 204 : 503 });
    },
    sessionInitial: {
      [SESSION_KEY]: JSON.stringify({
        access_token: "retry-access-token-long-enough",
        refresh_token: "retry-refresh-token-long-enough"
      })
    }
  });

  await settleCleanup(result);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(requestCount, 1);
  assert.equal(result.continueLink.hidden, true);
  assert.equal(result.retryButton.hidden, false);

  serverAvailable = true;
  result.retryButton.click();
  await settleCleanup(result);

  assert.equal(requestCount, 3);
  assert.equal(result.localStorage.getItem(SESSION_REVOCATION_MARKER_KEY), null);
  assert.equal(result.continueLink.hidden, false);
  assert.equal(result.retryButton.hidden, true);
  assert.match(result.status.textContent, /were removed/i);
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

  assert.deepEqual(result.deletedCacheEntries, [["gym-pwa-v44", LEGACY_CACHED_ASSET]]);
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
    "https://eduard047.github.io/GymApp/legacy-origin-cleanup.html",
    "https://eduard047.github.io/another-app/legacy-origin-cleanup-v61.html",
    "https://gymapptracker.com/legacy-origin-cleanup-v61.html",
    "https://eduard047.github.io/GymApp/legacy-origin-cleanup-v61.html?token=unexpected"
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
    assert.deepEqual(result.deletedCacheEntries, [], url);
    assert.deepEqual(result.unregisteredScopes, [], url);
    assert.match(result.status.textContent, /no legacy-origin cleanup/i);
  }
});
