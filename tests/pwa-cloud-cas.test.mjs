import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource, garminCloudSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8"),
  readFile("pwa/garmin-cloud-sync.js", "utf8")
]);
const ACTIVE_USER_ID = "00000000-0000-4000-8000-000000000001";
const UUID_V4_PATTERN_FOR_TEST = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function unsignedJwtFor(userId, exp = 4102444800) {
  const header = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ sub: userId, exp })).toString("base64url");
  return `${header}.${payload}.test-signature`;
}

function validGarminPlan(createdAt = "2026-07-14T00:00:00.000Z") {
  return {
    source: "pwa",
    version: 1,
    title: "Idempotent plan",
    createdAt,
    startedAt: "2026-07-14T00:00:00.000Z",
    note: "",
    exercises: [{ name: "Squat", sets: [{ weight: 100, reps: 5, orderIndex: 0 }] }]
  };
}

function loadContext(fetchImpl, { randomSeed = 1, sharedValues = null, lockManager = null } = {}) {
  const values = sharedValues || new Map();
  const sessionValues = new Map();
  let randomCall = 0;
  const appNode = {
    innerHTML: "",
    querySelectorAll: () => [],
    querySelector: () => null
  };
  const context = {
    AbortController,
    atob,
    clearInterval,
    clearTimeout,
    console,
    Date,
    Map,
    Promise,
    requestAnimationFrame: callback => callback(),
    Response,
    Set,
    setInterval,
    setTimeout,
    TextDecoder,
    TextEncoder,
    URL,
    URLSearchParams,
    crypto: {
      getRandomValues(target) {
        for (let index = 0; index < target.length; index += 1) {
          target[index] = (randomSeed + randomCall * 37 + index) & 0xff;
        }
        randomCall += 1;
        return target;
      }
    },
    fetch: fetchImpl,
    history: { replaceState() {}, pushState() {}, state: null },
    document: {
      documentElement: { lang: "en" },
      querySelector: selector => selector === "#app" ? appNode : null
    },
    navigator: {
      locks: lockManager || {
        async request(name, options, callback) {
          return callback({ name, mode: options?.mode || "exclusive" });
        }
      }
    },
    localStorage: {
      getItem: key => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, String(value)),
      removeItem: key => values.delete(key)
    },
    sessionStorage: {
      getItem: key => sessionValues.get(key) ?? null,
      setItem: (key, value) => sessionValues.set(key, String(value)),
      removeItem: key => sessionValues.delete(key)
    },
    window: {
      GYM_SUPABASE: { url: "https://project.example", anonKey: "publishable-test" },
      GymProgressionRules: {
        MAX_SUPPORTED_XP: 2147483647,
        sessionXP: () => 0,
        requirementForLevel: () => 200,
        cumulativeXPForLevel: () => 0,
        levelProgress: () => ({ level: 1, currentLevelXp: 0, xpForNextLevel: 200, progressFraction: 0 })
      },
      location: { search: "?access_token=test", hash: "", replace() {} },
      addEventListener() {}
    }
  };
  context.window.document = context.document;
  context.window.navigator = context.navigator;
  context.window.localStorage = context.localStorage;
  context.window.sessionStorage = context.sessionStorage;
  context.window.crypto = context.crypto;
  context.window.history = context.history;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  vm.runInContext(garminCloudSource, context);
  context.window.GymStateContract = context.GymStateContract;
  context.window.GymGarminCloud = context.GymGarminCloud;
  vm.runInContext(appSource, context);
  vm.runInContext(`
    activeAccount = {
      id: "remote-${ACTIVE_USER_ID}",
      name: "Owner",
      userId: ${JSON.stringify(ACTIVE_USER_ID)},
      remote: "supabase"
    };
    sessionStorage.setItem(REMOTE_SESSION_KEY, JSON.stringify({
      access_token: ${JSON.stringify(unsignedJwtFor(ACTIVE_USER_ID))},
      refresh_token: "opaque-refresh-token",
      user: { id: activeAccount.userId }
    }));
    state = defaultAppState();
    accountEpoch = 7;
  `, context);
  return context;
}

test("cloud update uses the prior server revision and zero changed rows fail closed", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    return new Response(JSON.stringify([]), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  vm.runInContext(`remoteStateSync = {
    userId: activeAccount.userId,
    exists: true,
    revision: "2026-07-13T20:00:00.000000+00:00"
  };`, context);

  await assert.rejects(vm.runInContext("saveRemoteState()", context), /changed on another client/);
  assert.equal(requests.length, 1, "a failed CAS must not publish a profile update");
  assert.equal(requests[0].options.method, "PATCH");
  assert.match(requests[0].url, /user_states\?user_id=eq\.00000000-0000-4000-8000-000000000001&updated_at=eq\./);
  assert.equal(requests[0].options.headers.Prefer, "return=representation");
});

test("successful cloud CAS adopts only the trigger-owned revision before updating the profile", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/user_states")) {
      return new Response(JSON.stringify([{ updated_at: "2026-07-13T20:00:00.000001+00:00" }]), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  });
  vm.runInContext(`remoteStateSync = {
    userId: activeAccount.userId,
    exists: true,
    revision: "2026-07-13T20:00:00.000000+00:00"
  };`, context);

  await vm.runInContext("saveRemoteState()", context);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].options.method, "PATCH");
  assert.match(requests[1].url, /\/rest\/v1\/profiles\?on_conflict=user_id$/);
  assert.equal(
    vm.runInContext("remoteStateSync.revision", context),
    "2026-07-13T20:00:00.000001+00:00"
  );
});

test("first cloud save inserts only when the loaded state was absent", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/user_states")) {
      return new Response(JSON.stringify([{ updated_at: "2026-07-13T20:00:00.000001+00:00" }]), {
        status: 201,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  });
  vm.runInContext(`remoteStateSync = {
    userId: activeAccount.userId,
    exists: false,
    revision: null
  };`, context);

  await vm.runInContext("saveRemoteState()", context);
  assert.equal(requests[0].options.method, "POST");
  assert.match(requests[0].url, /\/rest\/v1\/user_states\?select=updated_at$/);
  assert.doesNotMatch(requests[0].url, /on_conflict/);
});

test("cloud responses are byte-bounded before JSON parsing", async () => {
  const context = loadContext(async () => new Response(JSON.stringify({ payload: "x".repeat(64) }), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  }));

  await assert.rejects(
    vm.runInContext('supabaseRequest("/rest/v1/user_states", { maxResponseBytes: 32 })', context),
    /Cloud response exceeds 32 bytes/
  );
});

test("cloud decoding is strict and auth refresh cannot switch account identity", async () => {
  const invalidUtf8 = loadContext(async () => new Response(Uint8Array.from([0xff]), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  }));
  await assert.rejects(
    vm.runInContext('supabaseRequest("/rest/v1/user_states")', invalidUtf8)
  );

  const switched = loadContext(async () => new Response(JSON.stringify({
    access_token: unsignedJwtFor("00000000-0000-4000-8000-000000000099"),
    refresh_token: "replacement-refresh-token",
    user: { id: "00000000-0000-4000-8000-000000000099" }
  }), { status: 200, headers: { "Content-Type": "application/json" } }));
  await assert.rejects(
    vm.runInContext("refreshRemoteSession(loadRemoteSession())", switched),
    /invalid account response/
  );

  assert.doesNotMatch(appSource, /response\.(?:text|json)\(\)/);
  assert.match(appSource, /new TextDecoder\("utf-8", \{ fatal: true \}\)/);
  assert.match(appSource, /chunks\.length >= MAX_REMOTE_RESPONSE_CHUNKS/);
});

test("cloud credentials use transient storage and migrate the legacy persistent value once", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  const key = "gym-pwa-supabase-session-v1";
  const encoded = context.sessionStorage.getItem(key);

  assert.notEqual(encoded, null);
  assert.equal(context.localStorage.getItem(key), null);
  assert.equal(vm.runInContext("clearRemoteSession()", context), true);
  context.localStorage.setItem(key, encoded);

  assert.equal(vm.runInContext("loadRemoteSession().user.id", context), ACTIVE_USER_ID);
  assert.equal(context.localStorage.getItem(key), null);
  assert.equal(context.sessionStorage.getItem(key), encoded);
  assert.doesNotMatch(appSource, /localStorage\.setItem\(REMOTE_SESSION_KEY/);
});

test("remote logout stays fail-closed when transient credentials cannot be erased", async () => {
  const context = loadContext(async () => new Response(null, { status: 204 }));
  const authKey = "gym-pwa-active-account-v1";
  const sessionKey = "gym-pwa-supabase-session-v1";
  vm.runInContext("localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));", context);
  const markerBefore = context.localStorage.getItem(authKey);
  const sessionBefore = context.sessionStorage.getItem(sessionKey);
  const removeItem = context.sessionStorage.removeItem;
  context.sessionStorage.removeItem = key => {
    if (key === sessionKey) throw new Error("session storage removal denied");
    return removeItem(key);
  };

  await vm.runInContext("logoutAccount()", context);

  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(context.localStorage.getItem(authKey), markerBefore);
  assert.equal(context.sessionStorage.getItem(sessionKey), sessionBefore);
  assert.equal(vm.runInContext("loadActiveAccount().userId", context), ACTIVE_USER_ID);

  context.sessionStorage.removeItem = removeItem;
  await vm.runInContext("logoutAccount()", context);

  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.sessionStorage.getItem(sessionKey), null);
  assert.equal(context.localStorage.getItem(authKey), markerBefore);
  assert.equal(vm.runInContext("loadActiveAccount()", context), null);
});

test("remote logout detects a persistent legacy credential that storage refuses to remove", async () => {
  const context = loadContext(async () => new Response(null, { status: 204 }));
  const authKey = "gym-pwa-active-account-v1";
  const sessionKey = "gym-pwa-supabase-session-v1";
  const encodedSession = context.sessionStorage.getItem(sessionKey);
  assert.equal(vm.runInContext("clearRemoteSession()", context), true);
  context.localStorage.setItem(sessionKey, encodedSession);
  vm.runInContext("localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));", context);
  const markerBefore = context.localStorage.getItem(authKey);
  const removeItem = context.localStorage.removeItem;
  context.localStorage.removeItem = key => {
    if (key === sessionKey) return;
    return removeItem(key);
  };

  await vm.runInContext("logoutAccount()", context);

  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(context.localStorage.getItem(authKey), markerBefore);
  assert.equal(context.localStorage.getItem(sessionKey), encodedSession);
  assert.equal(vm.runInContext("loadActiveAccount().userId", context), ACTIVE_USER_ID);

  context.localStorage.removeItem = removeItem;
  await vm.runInContext("logoutAccount()", context);

  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem(sessionKey), null);
  assert.equal(context.sessionStorage.getItem(sessionKey), null);
  assert.equal(context.localStorage.getItem(authKey), markerBefore);
  assert.equal(vm.runInContext("loadActiveAccount()", context), null);
});

test("local logout keeps the account active until its owned marker is verifiably removed", async () => {
  const context = loadContext(async () => {
    throw new Error("network is not used for a local account");
  });
  const authKey = "gym-pwa-active-account-v1";
  vm.runInContext(`
    activeAccount = null;
    clearRemoteSession();
    loginAccount("Local Owner");
  `, context);
  const markerBefore = context.localStorage.getItem(authKey);
  const localAccountId = vm.runInContext("activeAccount.id", context);
  const removeItem = context.localStorage.removeItem;
  context.localStorage.removeItem = key => {
    if (key === authKey) return;
    return removeItem(key);
  };

  await vm.runInContext("logoutAccount()", context);

  assert.equal(vm.runInContext("activeAccount.id", context), localAccountId);
  assert.equal(context.localStorage.getItem(authKey), markerBefore);

  context.localStorage.removeItem = removeItem;
  await vm.runInContext("logoutAccount()", context);

  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem(authKey), null);
});

test("an independent tab without a session cannot sign out an authenticated tab", () => {
  const sharedValues = new Map();
  const fetchImpl = async () => {
    throw new Error("network is not used");
  };
  const firstTab = loadContext(fetchImpl, { sharedValues });
  firstTab.localStorage.setItem("gym-pwa-active-account-v1", JSON.stringify({
    id: `remote-${ACTIVE_USER_ID}`,
    name: "Owner",
    userId: ACTIVE_USER_ID,
    remote: "supabase"
  }));
  const markerBefore = firstTab.localStorage.getItem("gym-pwa-active-account-v1");
  const firstSessionBefore = firstTab.sessionStorage.getItem("gym-pwa-supabase-session-v1");

  const secondTab = loadContext(fetchImpl, { sharedValues });
  secondTab.sessionStorage.removeItem("gym-pwa-supabase-session-v1");
  assert.equal(vm.runInContext("loadActiveAccount()", secondTab), null);

  assert.equal(firstTab.localStorage.getItem("gym-pwa-active-account-v1"), markerBefore);
  assert.equal(firstTab.sessionStorage.getItem("gym-pwa-supabase-session-v1"), firstSessionBefore);
  assert.equal(vm.runInContext("loadActiveAccount().userId", firstTab), ACTIVE_USER_ID);
});

test("logging out one tab never deletes another account's shared marker", async () => {
  const otherUserId = "00000000-0000-4000-8000-000000000002";
  const sharedValues = new Map();
  const fetchImpl = async () => new Response(null, { status: 204 });
  const firstTab = loadContext(fetchImpl, { sharedValues });
  firstTab.localStorage.setItem("gym-pwa-active-account-v1", JSON.stringify({
    id: `remote-${ACTIVE_USER_ID}`,
    name: "First owner",
    userId: ACTIVE_USER_ID,
    remote: "supabase"
  }));

  const secondTab = loadContext(fetchImpl, { sharedValues });
  vm.runInContext(`
    activeAccount = {
      id: "remote-${otherUserId}",
      name: "Second owner",
      userId: ${JSON.stringify(otherUserId)},
      remote: "supabase"
    };
    saveRemoteSession({
      access_token: ${JSON.stringify(unsignedJwtFor(otherUserId))},
      refresh_token: "second-tab-refresh-token",
      user: { id: activeAccount.userId }
    });
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
  `, secondTab);
  const secondMarker = secondTab.localStorage.getItem("gym-pwa-active-account-v1");
  const secondSession = secondTab.sessionStorage.getItem("gym-pwa-supabase-session-v1");

  await vm.runInContext("logoutAccount()", firstTab);

  assert.equal(firstTab.localStorage.getItem("gym-pwa-active-account-v1"), secondMarker);
  assert.equal(secondTab.sessionStorage.getItem("gym-pwa-supabase-session-v1"), secondSession);
  assert.equal(vm.runInContext("loadActiveAccount().userId", secondTab), otherUserId);
});

test("logging out one remote tab preserves the same account in another tab", async () => {
  const sharedValues = new Map();
  const fetchImpl = async () => new Response(null, { status: 204 });
  const firstTab = loadContext(fetchImpl, { sharedValues });
  const secondTab = loadContext(fetchImpl, { sharedValues });
  const marker = JSON.stringify({
    id: `remote-${ACTIVE_USER_ID}`,
    name: "Owner",
    userId: ACTIVE_USER_ID,
    remote: "supabase"
  });
  firstTab.localStorage.setItem("gym-pwa-active-account-v1", marker);
  const secondSession = secondTab.sessionStorage.getItem("gym-pwa-supabase-session-v1");

  await vm.runInContext("logoutAccount()", firstTab);

  assert.equal(firstTab.localStorage.getItem("gym-pwa-active-account-v1"), marker);
  assert.equal(vm.runInContext("loadActiveAccount()", firstTab), null);
  assert.equal(secondTab.sessionStorage.getItem("gym-pwa-supabase-session-v1"), secondSession);
  assert.equal(vm.runInContext("loadActiveAccount().userId", secondTab), ACTIVE_USER_ID);
});

test("oversized account marker clears both the marker and legacy persistent session", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  const encodedSession = context.sessionStorage.getItem("gym-pwa-supabase-session-v1");
  vm.runInContext("clearRemoteSession()", context);
  context.localStorage.setItem("gym-pwa-supabase-session-v1", encodedSession);
  vm.runInContext('localStorage.setItem(AUTH_KEY, "x".repeat(MAX_LOCAL_ACCOUNT_STORAGE_BYTES + 1));', context);

  assert.equal(vm.runInContext("loadActiveAccount()", context), null);
  assert.equal(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
  assert.equal(context.localStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
});

test("account transitions clear timers while durable Garmin revocation stays explicit", () => {
  assert.match(appSource, /clearTimeout\(remoteSaveTimer\);[\s\S]*remoteStateSync = \{ userId: null, exists: false, revision: null \}/);
  const logoutSource = appSource.slice(appSource.indexOf("async function logoutAccount"), appSource.indexOf("async function unpairGarmin"));
  const unpairSource = appSource.slice(appSource.indexOf("async function unpairGarmin"), appSource.indexOf("function accountPanel"));
  assert.doesNotMatch(logoutSource, /revokeGarminBinding/);
  assert.match(logoutSource, /pendingGarminRevocations[\s\S]*revokeGarminDeviceById/);
  assert.match(unpairSource, /window\.confirm\(warning\)[\s\S]*await revokeGarminBinding\(session\)/);
  assert.match(logoutSource, /clearRemoteSession\(\)/);
  assert.match(
    logoutSource,
    /const localMarkerCleared[\s\S]*const remoteSessionCleared[\s\S]*if \(!localMarkerCleared \|\| !remoteSessionCleared\)/
  );
  assert.match(appSource, /LEGACY_GARMIN_DEVICE_TOKEN_KEY/);
  assert.doesNotMatch(appSource, /const current = localStorage\.getItem\(LEGACY_GARMIN_DEVICE_TOKEN_KEY\);/);
  assert.match(appSource, /storageNeedsRewrite \|\|= Boolean\([\s\S]*Object\.hasOwn\(value, "deviceToken"\)\)/);
  assert.doesNotMatch(appSource, /bindings\[binding\.userId\] = binding/);
  assert.doesNotMatch(appSource, /navigator\.clipboard\?\.writeText\(device\.device_token\)/);
  assert.match(appSource, /window\.confirm\(pairingWarning\)/);
  assert.match(appSource, /window\.prompt\(tokenPrompt, device\.device_token\)/);
  assert.match(appSource, /await revokeGarminDeviceById\(session, device\.id\)/);
});

test("ordinary sign-out preserves a working Garmin device identity for the next login", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    return new Response(null, { status: 204 });
  });
  const deviceId = "00000000-0000-4000-8000-000000000077";
  let confirmations = 0;
  context.window.confirm = () => {
    confirmations += 1;
    return false;
  };
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveGarminBinding({ version: 2, userId: activeAccount.userId, deviceId: ${JSON.stringify(deviceId)} });
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(confirmations, 0);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, context), deviceId);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(context.localStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(requests.length, 1);
  assert.match(requests[0].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.equal(requests[0].options.method, "POST");

  vm.runInContext(`
    activeAccount = {
      id: "remote-${ACTIVE_USER_ID}",
      name: "Owner",
      userId: ${JSON.stringify(ACTIVE_USER_ID)},
      remote: "supabase"
    };
    saveRemoteSession({
      access_token: ${JSON.stringify(unsignedJwtFor(ACTIVE_USER_ID))},
      refresh_token: "opaque-refresh-token",
      user: { id: activeAccount.userId }
    });
  `, context);
  const reused = await vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context);
  assert.equal(reused.binding.deviceId, deviceId);
  assert.equal(reused.created, false);
  assert.equal(requests.length, 1, "durable binding reuse must not create or rotate a device");
});

test("remote sign-out without a Garmin binding does not require a cloud request", async () => {
  const context = loadContext(async () => {
    throw new Error("network must not be used during ordinary sign-out");
  });
  let confirmations = 0;
  context.window.confirm = () => {
    confirmations += 1;
    return false;
  };
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    clearRemoteSession();
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(confirmations, 0);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.notEqual(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
  assert.equal(vm.runInContext("loadActiveAccount()", context), null);
});

test("failed server-side session revocation cannot prevent local sign-out", async () => {
  let requests = 0;
  const context = loadContext(async () => {
    requests += 1;
    throw new Error("offline");
  });
  vm.runInContext("localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));", context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(requests, 1);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.notEqual(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
  assert.equal(vm.runInContext("loadActiveAccount()", context), null);
});

test("logout refreshes an expired access JWT before revoking the local server session", async () => {
  const requests = [];
  const freshAccessToken = unsignedJwtFor(ACTIVE_USER_ID);
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/auth/v1/token?grant_type=refresh_token")) {
      return new Response(JSON.stringify({
        access_token: freshAccessToken,
        refresh_token: "rotated-refresh-token",
        user: { id: ACTIVE_USER_ID }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    return new Response(null, { status: 204 });
  });
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveRemoteSession({
      access_token: ${JSON.stringify(unsignedJwtFor(ACTIVE_USER_ID, 1))},
      refresh_token: "expired-access-refresh-token",
      user: { id: activeAccount.userId }
    });
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(requests.length, 2);
  assert.match(requests[0].url, /\/auth\/v1\/token\?grant_type=refresh_token$/);
  assert.match(requests[1].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.equal(requests[1].options.headers.Authorization, `Bearer ${freshAccessToken}`);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
});

test("logout retries one 401 with a refreshed session before local cleanup", async () => {
  const requests = [];
  const freshAccessToken = unsignedJwtFor(ACTIVE_USER_ID, 4102444700);
  let logoutCalls = 0;
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/auth/v1/token?grant_type=refresh_token")) {
      return new Response(JSON.stringify({
        access_token: freshAccessToken,
        refresh_token: "fallback-rotated-refresh",
        user: { id: ACTIVE_USER_ID }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    logoutCalls += 1;
    if (logoutCalls === 1) {
      return new Response(JSON.stringify({ error: "expired access" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  });
  vm.runInContext("localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));", context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(requests.length, 3);
  assert.match(requests[0].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.match(requests[1].url, /\/auth\/v1\/token\?grant_type=refresh_token$/);
  assert.match(requests[2].url, /\/auth\/v1\/logout\?scope=local$/);
  assert.equal(requests[2].options.headers.Authorization, `Bearer ${freshAccessToken}`);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
});

test("explicit Garmin unpair revokes the server device but keeps the cloud login", async () => {
  const actions = [];
  const context = loadContext(async (_url, options) => {
    actions.push(JSON.parse(options.body).action);
    return new Response(JSON.stringify({ status: "revoked" }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  });
  const deviceId = "00000000-0000-4000-8000-000000000078";
  context.window.confirm = () => true;
  vm.runInContext(`
    saveGarminBinding({ version: 2, userId: activeAccount.userId, deviceId: ${JSON.stringify(deviceId)} });
  `, context);

  await vm.runInContext("unpairGarmin()", context);

  assert.deepEqual(actions, ["revokeDevice"]);
  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext("loadRemoteSession().user.id", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)})`, context), null);
});

test("failed or cancelled explicit Garmin unpair preserves the working binding", async () => {
  const context = loadContext(async () => {
    throw new Error("network unavailable");
  });
  const deviceId = "00000000-0000-4000-8000-000000000079";
  vm.runInContext(`
    saveGarminBinding({ version: 2, userId: activeAccount.userId, deviceId: ${JSON.stringify(deviceId)} });
  `, context);

  context.window.confirm = () => false;
  await vm.runInContext("unpairGarmin()", context);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, context), deviceId);

  context.window.confirm = () => true;
  await vm.runInContext("unpairGarmin()", context);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, context), deviceId);
  assert.equal(vm.runInContext("loadRemoteSession().user.id", context), ACTIVE_USER_ID);
});

test("cloud saves require a previously validated revision and publish portable owner metadata", async () => {
  const context = loadContext(async () => {
    throw new Error("a fail-closed save must not reach fetch");
  });
  vm.runInContext(`remoteStateSync = { userId: null, exists: false, revision: null };`, context);
  await assert.rejects(
    vm.runInContext("saveRemoteState()", context),
    /must be loaded and validated/
  );

  const payload = vm.runInContext("remoteStatePayload(activeAccount.userId)", context);
  assert.equal(payload.schemaVersion, 2);
  assert.equal(payload.app, "GymApp");
  assert.equal("catalogSeedVersion" in payload, false);
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 1);
  assert.deepEqual(JSON.parse(JSON.stringify(payload.owner)), {
    accountId: "00000000-0000-4000-8000-000000000001",
    userId: "00000000-0000-4000-8000-000000000001",
    remote: true
  });
});

test("cloud revisions must be bounded RFC3339 timestamps", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  assert.equal(vm.runInContext('validRemoteStateRevision("2026-07-13T20:00:00.000001+00:00")', context), true);
  assert.equal(vm.runInContext('validRemoteStateRevision("not-a-revision")', context), false);
  assert.equal(vm.runInContext(`validRemoteStateRevision("${"1".repeat(65)}")`, context), false);
  assert.throws(
    () => vm.runInContext(`bindRemoteStateRevision({ userId: activeAccount.userId, exists: true, revision: "bad" })`, context),
    /Cloud revision is invalid/
  );
});

test("new local account IDs are random and do not collide for lossy legacy names", async () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  vm.runInContext(`
    activeAccount = null;
    localStorage.removeItem(AUTH_KEY);
    clearRemoteSession();
    localStorage.removeItem(ACCOUNT_LIST_KEY);
    state = defaultAppState();
  `, context);

  vm.runInContext('loginAccount("a b")', context);
  const firstId = vm.runInContext("activeAccount.id", context);
  await vm.runInContext("logoutAccount()", context);
  vm.runInContext('loginAccount("a-b")', context);
  const secondId = vm.runInContext("activeAccount.id", context);

  assert.match(firstId, /^local-v2-[a-f0-9]{32}$/);
  assert.match(secondId, /^local-v2-[a-f0-9]{32}$/);
  assert.notEqual(firstId, secondId);
  assert.notEqual(context.localStorage.getItem(`gym-pwa-account:${firstId}`), null);
  assert.notEqual(context.localStorage.getItem(`gym-pwa-account:${secondId}`), null);
});

test("Unicode and formerly truncated local names retain separate stable storage IDs", async () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  }, { randomSeed: 91 });
  vm.runInContext(`
    activeAccount = null;
    localStorage.removeItem(AUTH_KEY);
    clearRemoteSession();
    localStorage.removeItem(ACCOUNT_LIST_KEY);
    state = defaultAppState();
  `, context);
  const names = [
    "用户 Атлет",
    `${"x".repeat(63)}a`,
    `${"x".repeat(63)}b`
  ];
  const ids = [];
  for (const name of names) {
    vm.runInContext(`loginAccount(${JSON.stringify(name)})`, context);
    ids.push(vm.runInContext("activeAccount.id", context));
    await vm.runInContext("logoutAccount()", context);
  }

  assert.equal(new Set(ids).size, names.length);
  assert.deepEqual(
    JSON.parse(context.localStorage.getItem("gym-pwa-account-list-v1")).map(account => account.name),
    names
  );
});

test("legacy account keys remain stable while ambiguous collisions fail closed", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  const legacyState = vm.runInContext("defaultAppState()", context);
  legacyState.language = "uk";
  context.localStorage.setItem("gym-pwa-account:legacy-key", JSON.stringify(legacyState));
  context.localStorage.setItem("gym-pwa-account-list-v1", JSON.stringify([
    { id: "legacy-key", name: "Legacy Owner" }
  ]));
  vm.runInContext(`activeAccount = null; localStorage.removeItem(AUTH_KEY); state = defaultAppState();`, context);

  vm.runInContext('loginAccount("Legacy Owner")', context);
  assert.equal(vm.runInContext("activeAccount.id", context), "legacy-key");
  assert.equal(vm.runInContext("state.language", context), "uk");

  vm.runInContext(`
    activeAccount = null;
    localStorage.removeItem(AUTH_KEY);
    localStorage.setItem(ACCOUNT_LIST_KEY, JSON.stringify([
      { id: "shared-legacy-key", name: "a b" },
      { id: "shared-legacy-key", name: "a-b" }
    ]));
    localStorage.setItem(ACCOUNT_PREFIX + "shared-legacy-key", JSON.stringify(defaultAppState()));
  `, context);
  vm.runInContext('loginAccount("a-b")', context);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
});

test("account-scoped state never merges sessions from the global legacy key", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  vm.runInContext(`
    activeAccount = { id: "local-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name: "Owner", localIdVersion: 2 };
    const scoped = defaultAppState();
    scoped.sessions = [{ id: 1, startedAt: 1760000000000, note: "", exerciseNames: [], sets: [] }];
    const legacy = defaultAppState();
    legacy.sessions = [{
      id: 2,
      startedAt: 1760000000001,
      note: "previous user's private note",
      exerciseNames: ["Bench Press"],
      sets: [{ id: 3, exerciseName: "Bench Press", weight: 100, reps: 5, orderIndex: 0 }]
    }];
    localStorage.setItem(activeStorageKey(), JSON.stringify(scoped));
    localStorage.setItem(LEGACY_KEY, JSON.stringify(legacy));
    state = loadState();
  `, context);

  assert.equal(vm.runInContext("state.sessions.length", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].id", context), 1);
  assert.equal(vm.runInContext("state.sessions[0].sets.length", context), 0);
  assert.doesNotMatch(JSON.stringify(vm.runInContext("state", context)), /previous user's private note/);
});

test("invalid authenticated cloud state enters bounded recovery mode without hydration", async () => {
  const rawState = { schemaVersion: 2, sessions: [{}], privateLegacyField: "preserve me" };
  const context = loadContext(async () => new Response(JSON.stringify([{
    state: rawState,
    updated_at: "2026-07-13T20:00:00.000001+00:00"
  }]), { status: 200, headers: { "Content-Type": "application/json" } }));

  const updated = await vm.runInContext("pullRemoteState()", context);

  assert.equal(updated, true);
  assert.equal(vm.runInContext("cloudStateRecovery.userId", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext("cloudStateRecovery.rawState.privateLegacyField", context), "preserve me");
  assert.equal(vm.runInContext("state.sessions.length", context), 0);
  assert.equal(vm.runInContext("remoteStateSync.revision", context), "2026-07-13T20:00:00.000001+00:00");
  assert.match(vm.runInContext("cloudRecoveryScreen()", context), /export-cloud-recovery/);
  assert.match(vm.runInContext("cloudRecoveryScreen()", context), /reset-cloud-recovery/);
});

test("cloud recovery reset is explicit and uses the quarantined row revision as a CAS", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/user_states")) {
      return new Response(JSON.stringify([{ updated_at: "2026-07-13T20:00:00.000002+00:00" }]), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  });
  let confirmations = 0;
  context.window.confirm = () => {
    confirmations += 1;
    return true;
  };
  vm.runInContext(`
    state = defaultAppState();
    remoteStateSync = {
      userId: activeAccount.userId,
      exists: true,
      revision: "2026-07-13T20:00:00.000001+00:00"
    };
    cloudStateRecovery = {
      userId: activeAccount.userId,
      revision: remoteStateSync.revision,
      rawState: { sessions: [{}], privateLegacyField: "preserve me" }
    };
  `, context);

  await vm.runInContext("resetCloudRecovery()", context);

  assert.equal(confirmations, 1);
  assert.equal(requests.length, 2);
  assert.match(requests[0].url, /user_states\?user_id=eq\.[^&]+&updated_at=eq\.2026-07-13T20%3A00%3A00\.000001%2B00%3A00/);
  assert.equal(requests[0].options.method, "PATCH");
  const replacementPayload = JSON.parse(requests[0].options.body).state;
  assert.equal(replacementPayload.sessions.length, 0);
  assert.equal(replacementPayload.owner.userId, ACTIVE_USER_ID);
  assert.equal(vm.runInContext("cloudStateRecovery", context), null);
  assert.equal(vm.runInContext("remoteStateSync.revision", context), "2026-07-13T20:00:00.000002+00:00");
});

test("Garmin binding is persisted before the one-time token is shown", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000081";
  const token = "a".repeat(64);
  const context = loadContext(async (_url, options) => {
    const action = JSON.parse(options.body).action;
    const payload = action === "listDevices"
      ? { devices: [] }
      : { device: { id: deviceId, device_token: token, binding_version: 2, token_revision: 1 } };
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  });
  let promptCalls = 0;
  context.window.confirm = () => true;
  context.window.prompt = (_message, shownToken) => {
    promptCalls += 1;
    assert.equal(shownToken, token);
    const bindings = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"));
    assert.equal(bindings[ACTIVE_USER_ID].deviceId, deviceId);
    assert.equal(bindings[ACTIVE_USER_ID].recoveryPending, true);
    assert.equal(Object.hasOwn(bindings[ACTIVE_USER_ID], "deviceToken"), false);
    return "saved";
  };

  const result = await vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context);

  assert.equal(promptCalls, 1);
  assert.equal(result.binding.deviceId, deviceId);
  assert.equal(
    Object.hasOwn(JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"))[ACTIVE_USER_ID], "recoveryPending"),
    false
  );
  assert.equal(vm.runInContext("pendingGarminRevocations.size", context), 0);
});

test("Garmin storage failure revokes the unseen token before any prompt", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000082";
  const token = "b".repeat(64);
  const actions = [];
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action);
    if (body.action === "listDevices") {
      return new Response(JSON.stringify({ devices: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (body.action === "createDevice") {
      return new Response(JSON.stringify({
        device: { id: deviceId, device_token: token, binding_version: 2, token_revision: 1 }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify({ status: "revoked" }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  });
  const originalSetItem = context.localStorage.setItem.bind(context.localStorage);
  context.localStorage.setItem = (key, value) => {
    if (key === "gym-pwa-garmin-device-bindings-v2") throw new Error("quota exceeded");
    originalSetItem(key, value);
  };
  let promptCalls = 0;
  context.window.confirm = () => true;
  context.window.prompt = () => {
    promptCalls += 1;
    return "saved";
  };

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /unseen token was revoked/
  );
  assert.deepEqual(actions, ["listDevices", "createDevice", "revokeDevice"]);
  assert.equal(promptCalls, 0);
  assert.equal(vm.runInContext("pendingGarminRevocations.size", context), 0);
});

test("cancelled Garmin token prompt stays recoverable when revocation fails", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000085";
  const token = "e".repeat(64);
  const actions = [];
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action);
    if (body.action === "listDevices") {
      return new Response(JSON.stringify({ devices: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (body.action === "createDevice") {
      return new Response(JSON.stringify({
        device: { id: deviceId, device_token: token, binding_version: 2, token_revision: 1 }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    throw new Error("revocation offline");
  });
  context.window.confirm = () => true;
  context.window.prompt = () => null;

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /Use Unpair Garmin/
  );

  assert.deepEqual(actions, ["listDevices", "createDevice", "revokeDevice"]);
  assert.equal(
    vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).recoveryPending`, context),
    true
  );
});

test("lost browser binding recovers an existing watch by rotating its token without changing UUID", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000083";
  const actions = [];
  let replacementToken = null;
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action);
    if (body.action === "listDevices") {
      return new Response(JSON.stringify({
        devices: [{
          id: deviceId,
          display_name: "Fenix 8",
          created_at: "2026-07-14T00:00:00+00:00",
          last_seen_at: null,
          binding_version: 2,
          token_revision: 7
        }]
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    assert.equal(body.deviceId, deviceId);
    assert.equal(body.expectedTokenRevision, 7);
    assert.match(body.replacementToken, /^[a-f0-9]{64}$/);
    replacementToken = body.replacementToken;
    return new Response(JSON.stringify({
      status: "rotated",
      device: {
        id: deviceId,
        device_token: body.replacementToken,
        display_name: "Fenix 8",
        created_at: "2026-07-14T00:00:00+00:00",
        last_seen_at: null,
        binding_version: 2,
        token_revision: 8
      }
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  context.window.confirm = () => true;
  context.window.prompt = (_message, shownToken) => {
    assert.equal(shownToken, replacementToken);
    const binding = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"));
    assert.equal(binding[ACTIVE_USER_ID].deviceId, deviceId, "stable UUID must be durable before token rotation is revealed");
    assert.equal(binding[ACTIVE_USER_ID].recoveryPending, true);
    assert.equal(JSON.stringify(binding).includes(replacementToken), false);
    return "saved";
  };

  const result = await vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context);

  assert.deepEqual(actions, ["listDevices", "rotateDeviceToken"]);
  assert.equal(result.binding.deviceId, deviceId);
  assert.equal(result.created, false);
  assert.equal(result.rotated, true);
  assert.equal(
    Object.hasOwn(JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"))[ACTIVE_USER_ID], "recoveryPending"),
    false
  );
  assert.equal(context.localStorage.getItem("gym-pwa-supabase-session-v1"), null);
});

test("lost Garmin rotation response remains retryable for the same UUID", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000084";
  const actions = [];
  const rotationBodies = [];
  let rotationAttempts = 0;
  let listAttempts = 0;
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action);
    if (body.action === "listDevices") {
      listAttempts += 1;
      return new Response(JSON.stringify({
        devices: [{
          id: deviceId,
          display_name: "Fenix retry",
          created_at: "2026-07-14T00:00:00+00:00",
          last_seen_at: null,
          binding_version: 2,
          token_revision: listAttempts === 1 ? 3 : 4
        }]
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    rotationAttempts += 1;
    rotationBodies.push(body);
    if (rotationAttempts <= 2) throw new Error("response lost");
    return new Response(JSON.stringify({
      status: "rotated",
      device: {
        id: deviceId,
        device_token: body.replacementToken,
        display_name: "Fenix retry",
        created_at: "2026-07-14T00:00:00+00:00",
        last_seen_at: null,
        binding_version: 2,
        token_revision: 5
      }
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  context.window.confirm = () => true;
  context.window.prompt = (_message, shownToken) => {
    assert.equal(shownToken, rotationBodies[2].replacementToken);
    return "saved";
  };

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /response lost/
  );
  assert.equal(
    vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).recoveryPending`, context),
    true
  );

  const result = await vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context);

  assert.deepEqual(actions, ["listDevices", "rotateDeviceToken", "rotateDeviceToken", "listDevices", "rotateDeviceToken"]);
  assert.deepEqual(rotationBodies[0], rotationBodies[1], "transport retry must replay the exact CAS request");
  assert.equal(rotationBodies[0].expectedTokenRevision, 3);
  assert.equal(rotationBodies[2].expectedTokenRevision, 4);
  assert.notEqual(rotationBodies[2].replacementToken, rotationBodies[0].replacementToken);
  assert.equal(result.binding.deviceId, deviceId);
  assert.equal(result.rotated, true);
  assert.equal(
    vm.runInContext(`Object.hasOwn(garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}), "recoveryPending")`, context),
    false
  );
});

test("outcome-unknown Garmin rotation accepts exact already_rotated replay", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000093";
  const rotationBodies = [];
  let rotateCalls = 0;
  let promptCalls = 0;
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    if (body.action === "listDevices") {
      return new Response(JSON.stringify({
        devices: [{
          id: deviceId,
          display_name: "Fenix replay",
          created_at: "2026-07-14T00:00:00+00:00",
          last_seen_at: null,
          binding_version: 2,
          token_revision: 20
        }]
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    rotationBodies.push(body);
    rotateCalls += 1;
    if (rotateCalls === 1) throw new Error("response lost after commit");
    return new Response(JSON.stringify({
      status: "already_rotated",
      device: {
        id: deviceId,
        device_token: body.replacementToken,
        display_name: "Fenix replay",
        created_at: "2026-07-14T00:00:00+00:00",
        last_seen_at: null,
        binding_version: 2,
        token_revision: 21
      }
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  context.window.confirm = () => true;
  context.window.prompt = (_message, shownToken) => {
    promptCalls += 1;
    assert.equal(shownToken, rotationBodies[0].replacementToken);
    return "saved";
  };

  const result = await vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context);

  assert.equal(result.binding.deviceId, deviceId);
  assert.deepEqual(rotationBodies[0], rotationBodies[1]);
  assert.equal(promptCalls, 1);
  assert.equal(
    vm.runInContext(`Object.hasOwn(garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}), "recoveryPending")`, context),
    false
  );
});

test("stale account transition never reveals a rotated Garmin token", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000086";
  let context;
  let promptCalls = 0;
  let replacementToken = null;
  context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    if (body.action === "listDevices") {
      return new Response(JSON.stringify({
        devices: [{
          id: deviceId,
          display_name: "Fenix stale",
          created_at: "2026-07-14T00:00:00+00:00",
          last_seen_at: null,
          binding_version: 2,
          token_revision: 12
        }]
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    replacementToken = body.replacementToken;
    vm.runInContext("accountEpoch += 1; activeAccount = null; clearRemoteSession();", context);
    return new Response(JSON.stringify({
      status: "rotated",
      device: {
        id: deviceId,
        device_token: body.replacementToken,
        display_name: "Fenix stale",
        created_at: "2026-07-14T00:00:00+00:00",
        last_seen_at: null,
        binding_version: 2,
        token_revision: 13
      }
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  context.window.confirm = () => true;
  context.window.prompt = () => {
    promptCalls += 1;
    return "saved";
  };

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /stale account session/
  );

  assert.equal(promptCalls, 0);
  const stored = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"));
  assert.equal(stored[ACTIVE_USER_ID].deviceId, deviceId);
  assert.equal(stored[ACTIVE_USER_ID].recoveryPending, true);
  assert.equal(JSON.stringify(stored).includes(replacementToken), false);
});

test("stale account after device listing cannot prompt, create, or rotate", async () => {
  const actions = [];
  let context;
  let promptCalls = 0;
  context = loadContext(async (_url, options) => {
    actions.push(JSON.parse(options.body).action);
    vm.runInContext("accountEpoch += 1; activeAccount = null; clearRemoteSession();", context);
    return new Response(JSON.stringify({ devices: [] }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  });
  context.window.confirm = () => {
    promptCalls += 1;
    return true;
  };
  context.window.prompt = () => {
    promptCalls += 1;
    return "saved";
  };

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /stale account session/
  );

  assert.deepEqual(actions, ["listDevices"]);
  assert.equal(promptCalls, 0);
});

test("Garmin token revision conflict refreshes metadata and fails closed", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000088";
  const actions = [];
  let listCalls = 0;
  let replacementToken = null;
  let promptCalls = 0;
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action);
    if (body.action === "listDevices") {
      listCalls += 1;
      return new Response(JSON.stringify({
        devices: [{
          id: deviceId,
          display_name: "Fenix conflict",
          created_at: "2026-07-14T00:00:00+00:00",
          last_seen_at: null,
          binding_version: 2,
          token_revision: listCalls === 1 ? 9 : 10
        }]
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    replacementToken = body.replacementToken;
    assert.equal(body.expectedTokenRevision, 9);
    return new Response(JSON.stringify({
      error: "Device token rotation conflict",
      status: "conflict",
      tokenRevision: 10
    }), { status: 409, headers: { "Content-Type": "application/json" } });
  });
  context.window.confirm = () => true;
  context.window.prompt = () => {
    promptCalls += 1;
    return "saved";
  };

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /conflicted with another request.*revision is 10/
  );

  assert.deepEqual(actions, ["listDevices", "rotateDeviceToken", "listDevices"]);
  assert.equal(promptCalls, 0);
  const stored = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"));
  assert.equal(stored[ACTIVE_USER_ID].recoveryPending, true);
  assert.equal(JSON.stringify(stored).includes(replacementToken), false);
});

test("concurrent Garmin sync clicks run one list-create-queue path", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000087";
  const token = "1".repeat(64);
  const actions = [];
  let releaseList;
  const listGate = new Promise(resolve => {
    releaseList = resolve;
  });
  const context = loadContext(async (url, options) => {
    if (url.includes("/garmin-sync")) {
      const body = JSON.parse(options.body);
      actions.push(body.action);
      if (body.action === "listDevices") {
        await listGate;
        return new Response(JSON.stringify({ devices: [] }), {
          status: 200,
          headers: { "Content-Type": "application/json" }
        });
      }
      return new Response(JSON.stringify({
        device: { id: deviceId, device_token: token, binding_version: 2, token_revision: 1 }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    actions.push("queuePlan");
    const body = JSON.parse(options.body);
    assert.equal(body.p_device_id, deviceId);
    assert.match(body.p_client_request_id, /^[0-9a-f-]{36}$/);
    assert.equal(body.p_plan.title, "Concurrency plan");
    assert.equal(Object.hasOwn(body, "user_id"), false);
    assert.equal(Object.hasOwn(body, "status"), false);
    return new Response(JSON.stringify({
      status: "queued",
      planId: "00000000-0000-4000-8000-000000000099",
      planRevision: 1,
      planStatus: "pending"
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  context.window.GymGarminCloud = {
    ...context.window.GymGarminCloud,
    draftToGarminPlan: () => ({
      source: "pwa",
      version: 1,
      title: "Concurrency plan",
      createdAt: "2026-07-14T00:00:00.000Z",
      startedAt: "2026-07-14T00:00:00.000Z",
      note: "",
      exercises: [{ name: "Squat", sets: [{ reps: 5, weight: 100, orderIndex: 0 }] }]
    })
  };
  context.window.confirm = () => true;
  context.window.prompt = () => "saved";
  vm.runInContext("workoutDraft = { blocks: [{ exerciseName: 'Squat', sets: [{ reps: 5, weight: 100 }] }] };", context);

  const first = vm.runInContext("queueGarminPlanFromDraft()", context);
  const second = vm.runInContext("queueGarminPlanFromDraft()", context);
  releaseList();
  await Promise.all([first, second]);

  assert.deepEqual(actions, ["listDevices", "createDevice", "queuePlan"]);
  assert.equal(vm.runInContext("garminSyncInProgress", context), false);
  assert.equal(
    vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, context),
    deviceId
  );
});

test("a shared Web Lock allows only one cross-tab Garmin create and enqueue path", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000086";
  const token = "2".repeat(64);
  const actions = [];
  const heldLocks = new Set();
  const lockManager = {
    request(name, options, callback) {
      if (options?.ifAvailable && heldLocks.has(name)) return Promise.resolve(callback(null));
      heldLocks.add(name);
      return Promise.resolve(callback({ name, mode: options?.mode || "exclusive" }))
        .finally(() => heldLocks.delete(name));
    }
  };
  let releaseList;
  const listGate = new Promise(resolve => {
    releaseList = resolve;
  });
  const fetchImpl = async (url, options) => {
    if (url.includes("/garmin-sync")) {
      const body = JSON.parse(options.body);
      actions.push(body.action);
      if (body.action === "listDevices") {
        await listGate;
        return new Response(JSON.stringify({ devices: [] }), {
          status: 200,
          headers: { "Content-Type": "application/json" }
        });
      }
      return new Response(JSON.stringify({
        device: { id: deviceId, device_token: token, binding_version: 2, token_revision: 1 }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    actions.push("queuePlan");
    return new Response(JSON.stringify({
      status: "queued",
      planId: "00000000-0000-4000-8000-000000000098",
      planRevision: 1,
      planStatus: "pending"
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  const sharedValues = new Map();
  const firstTab = loadContext(fetchImpl, { sharedValues, lockManager, randomSeed: 11 });
  const secondTab = loadContext(fetchImpl, { sharedValues, lockManager, randomSeed: 22 });
  for (const context of [firstTab, secondTab]) {
    context.window.GymGarminCloud = {
      ...context.window.GymGarminCloud,
      draftToGarminPlan: () => validGarminPlan()
    };
    context.window.confirm = () => true;
    context.window.prompt = () => "saved";
    vm.runInContext("workoutDraft = { blocks: [{ exerciseName: 'Squat', sets: [{ reps: 5, weight: 100 }] }] };", context);
  }

  const first = vm.runInContext("queueGarminPlanFromDraft()", firstTab);
  const second = vm.runInContext("queueGarminPlanFromDraft()", secondTab);
  await second;
  releaseList();
  await first;

  assert.deepEqual(actions, ["listDevices", "createDevice", "queuePlan"]);
  assert.equal(heldLocks.size, 0);
  assert.equal(
    vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, firstTab),
    deviceId
  );
  assert.equal(
    vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, secondTab),
    deviceId
  );
});

test("Garmin sync fails closed when cross-tab locking is unavailable", async () => {
  let requests = 0;
  const context = loadContext(async () => {
    requests += 1;
    throw new Error("network must not be used");
  });
  context.navigator.locks = null;
  context.window.GymGarminCloud = {
    ...context.window.GymGarminCloud,
    draftToGarminPlan: () => validGarminPlan()
  };
  vm.runInContext("workoutDraft = { blocks: [{ exerciseName: 'Squat', sets: [{ reps: 5, weight: 100 }] }] };", context);

  await vm.runInContext("queueGarminPlanFromDraft()", context);

  assert.equal(requests, 0);
  assert.equal(vm.runInContext("garminSyncInProgress", context), false);
});

test("Garmin enqueue persists one request ID and replays the exact body after unknown outcome", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000089";
  const planId = "00000000-0000-4000-8000-000000000090";
  const bodies = [];
  let attempts = 0;
  const context = loadContext(async (url, options) => {
    assert.match(url, /\/rest\/v1\/rpc\/garmin_enqueue_plan$/);
    bodies.push(options.body);
    attempts += 1;
    if (attempts <= 2) throw new Error("outcome unknown");
    return new Response(JSON.stringify({
      status: "already_queued",
      planId,
      planRevision: 4,
      planStatus: "downloaded"
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  const bindingExpression = `{ version: 2, userId: ${JSON.stringify(ACTIVE_USER_ID)}, deviceId: ${JSON.stringify(deviceId)} }`;

  await assert.rejects(
    vm.runInContext(`enqueueGarminPlan(loadRemoteSession(), ${bindingExpression}, ${JSON.stringify(validGarminPlan())})`, context),
    /outcome unknown/
  );
  const pending = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-enqueue-requests-v1"));
  assert.match(pending[ACTIVE_USER_ID].requestId, UUID_V4_PATTERN_FOR_TEST);

  const response = await vm.runInContext(
    `enqueueGarminPlan(loadRemoteSession(), ${bindingExpression}, ${JSON.stringify(validGarminPlan("2026-07-14T00:01:00.000Z"))})`,
    context
  );

  assert.equal(response.status, "already_queued");
  assert.equal(bodies.length, 3);
  assert.equal(bodies[0], bodies[1]);
  assert.equal(bodies[1], bodies[2], "retry after reload-style regeneration must reuse stored plan and request ID");
  const sent = JSON.parse(bodies[0]);
  assert.deepEqual(Object.keys(sent).sort(), ["p_client_request_id", "p_device_id", "p_plan"]);
  assert.equal(sent.p_device_id, deviceId);
  assert.equal(sent.p_plan.createdAt, "2026-07-14T00:00:00.000Z");
  assert.equal(context.localStorage.getItem("gym-pwa-garmin-enqueue-requests-v1"), null);
  assert.doesNotMatch(appSource, /\/rest\/v1\/garmin_plans/);
});

test("Garmin enqueue conflict requires explicit approval before minting a new request ID", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000091";
  const bodies = [];
  let returnConflict = true;
  const context = loadContext(async (_url, options) => {
    bodies.push(JSON.parse(options.body));
    if (returnConflict) {
      return new Response(JSON.stringify({ status: "conflict" }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(JSON.stringify({
      status: "queued",
      planId: "00000000-0000-4000-8000-000000000092",
      planRevision: 1,
      planStatus: "pending"
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  const expression = `enqueueGarminPlan(loadRemoteSession(), { version: 2, userId: ${JSON.stringify(ACTIVE_USER_ID)}, deviceId: ${JSON.stringify(deviceId)} }, ${JSON.stringify(validGarminPlan())})`;
  context.window.confirm = () => false;

  await assert.rejects(vm.runInContext(expression, context), /conflicted with different server content/);
  const conflicted = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-enqueue-requests-v1"));
  assert.equal(conflicted[ACTIVE_USER_ID].conflict, true);
  const conflictedRequestId = conflicted[ACTIVE_USER_ID].requestId;

  await assert.rejects(vm.runInContext(expression, context), /pending review/);
  assert.equal(bodies.length, 1, "conflict must not automatically send or mint another request");

  context.window.confirm = () => true;
  returnConflict = false;
  await vm.runInContext(expression, context);
  assert.equal(bodies.length, 2);
  assert.notEqual(bodies[1].p_client_request_id, conflictedRequestId);
  assert.equal(context.localStorage.getItem("gym-pwa-garmin-enqueue-requests-v1"), null);
});

test("invalid Garmin recovery metadata fails closed before create or rotation", async () => {
  const actions = [];
  const context = loadContext(async (_url, options) => {
    actions.push(JSON.parse(options.body).action);
    return new Response(JSON.stringify({
      devices: [{
        id: "not-a-uuid",
        display_name: "Spoofed watch",
        created_at: "not-a-timestamp",
        last_seen_at: null,
        binding_version: 2,
        token_revision: 1
      }]
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  context.window.confirm = () => true;

  await assert.rejects(
    vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context),
    /device list is invalid/
  );
  assert.deepEqual(actions, ["listDevices"]);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)})`, context), null);
});
