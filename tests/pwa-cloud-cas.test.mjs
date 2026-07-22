import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
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

function garminTestCapability(_deviceId, nonce = "b".repeat(64)) {
  return nonce;
}

function garminTestCreatedDevice(deviceId, deviceToken) {
  return {
    id: deviceId,
    device_token: deviceToken,
    display_name: "Garmin watch",
    created_at: "2026-07-14T00:00:00+00:00",
    last_seen_at: null,
    binding_version: 2,
    token_revision: 1,
  };
}

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

function loadContext(fetchImpl, {
  randomSeed = 1,
  sharedValues = null,
  sharedSessionValues = null,
  lockManager = null,
  seedActiveSession = true,
  locationSearch = "?access_token=test"
} = {}) {
  const values = sharedValues || new Map();
  const sessionValues = sharedSessionValues || new Map();
  let randomCall = 0;
  const appNode = {
    innerHTML: "",
    querySelectorAll: () => [],
    querySelector: () => null
  };
  const runtimeNodes = new Map();
  const context = {
    AbortController,
    atob,
    btoa,
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
      subtle: webcrypto.subtle,
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
      querySelector: selector => selector === "#app" ? appNode : (runtimeNodes.get(selector) || null)
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
      location: { search: locationSearch, hash: "", pathname: "/", replace() {} },
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
  if (seedActiveSession) {
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
  }
  context.appNode = appNode;
  context.runtimeNodes = runtimeNodes;
  context.storageValues = values;
  context.sessionValues = sessionValues;
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

test("cloud fingerprints are stable across equivalent object key order", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  assert.equal(vm.runInContext(`(() => {
    const original = defaultAppState();
    const reordered = {
      profile: {
        calories: original.profile.calories,
        goal: original.profile.goal,
        days: original.profile.days,
        split: original.profile.split
      },
      mappings: Object.fromEntries(Object.entries(original.mappings).reverse()),
      sessions: original.sessions,
      exercises: original.exercises,
      catalogSeedVersion: original.catalogSeedVersion,
      language: original.language
    };
    return remoteStateFingerprint(original, activeAccount.userId) ===
      remoteStateFingerprint(reordered, activeAccount.userId);
  })()`, context), true);
});

test("a clean missing-cloud baseline accepts a later cloud creation", async () => {
  const requests = [];
  let remotePayload;
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    return new Response(JSON.stringify([{
      state: remotePayload,
      updated_at: "2026-07-20T10:00:00.000001+00:00"
    }]), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  vm.runInContext(`
    state = defaultAppState();
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveState({ queueRemote: false, markDirty: false });
    saveSyncBaseline({
      version: 1,
      userId: activeAccount.userId,
      remoteExists: false,
      revision: null,
      syncedFingerprint: null,
      localFingerprint: remoteStateFingerprint(state, activeAccount.userId),
      dirty: false,
      pending: null,
      updatedAt: Date.now()
    });
  `, context);
  remotePayload = JSON.parse(vm.runInContext(`JSON.stringify((() => {
    const remote = defaultAppState();
    remote.profile.goal = "Strength";
    return remoteStatePayload(activeAccount.userId, remote);
  })())`, context));

  await vm.runInContext("pullRemoteState()", context);

  assert.equal(requests.length, 1);
  assert.equal(vm.runInContext("state.profile.goal", context), "Strength");
  assert.equal(vm.runInContext("cloudSyncConflict", context), null);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", context), false);
});

test("an outcome-unknown write reconciles both applied and not-applied server outcomes", async () => {
  const runCase = async applied => {
    const requests = [];
    let basePayload;
    let attemptPayload;
    const context = loadContext(async (url, options) => {
      requests.push({ url, options });
      if ((options?.method || "GET") === "GET") {
        return new Response(JSON.stringify([{
          state: applied ? attemptPayload : basePayload,
          updated_at: applied
            ? "2026-07-20T11:00:00.000001+00:00"
            : "2026-07-20T11:00:00.000000+00:00"
        }]), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      if (options.method === "PATCH") {
        return new Response(JSON.stringify([{ updated_at: "2026-07-20T11:00:00.000002+00:00" }]), {
          status: 200,
          headers: { "Content-Type": "application/json" }
        });
      }
      return new Response(null, { status: 204 });
    });
    basePayload = JSON.parse(vm.runInContext(
      "JSON.stringify(remoteStatePayload(activeAccount.userId, defaultAppState()))",
      context
    ));
    attemptPayload = JSON.parse(vm.runInContext(`JSON.stringify((() => {
      const attempted = defaultAppState();
      attempted.profile.goal = "Strength";
      return remoteStatePayload(activeAccount.userId, attempted);
    })())`, context));
    context.__basePayload = basePayload;
    context.__attemptPayload = attemptPayload;
    vm.runInContext(`
      const baseStateForPending = normalizeImportedState(globalThis.__basePayload, defaultAppState());
      state = normalizeImportedState(globalThis.__attemptPayload, defaultAppState());
      localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
      saveState({ queueRemote: false, markDirty: false });
      bindRemoteStateRevision({
        userId: activeAccount.userId,
        exists: true,
        revision: "2026-07-20T11:00:00.000000+00:00"
      });
      saveSyncBaseline({
        version: 1,
        userId: activeAccount.userId,
        remoteExists: true,
        revision: remoteStateSync.revision,
        syncedFingerprint: remoteStateFingerprint(baseStateForPending, activeAccount.userId),
        localFingerprint: remoteStateFingerprint(state, activeAccount.userId),
        dirty: true,
        pending: {
          payloadFingerprint: remoteStateFingerprint(state, activeAccount.userId),
          baseExists: true,
          baseRevision: remoteStateSync.revision,
          baseFingerprint: remoteStateFingerprint(baseStateForPending, activeAccount.userId),
          startedAt: Date.now()
        },
        updatedAt: Date.now()
      });
    `, context);

    await vm.runInContext("startRemoteSave()", context);
    return { context, requests };
  };

  const applied = await runCase(true);
  assert.equal(applied.requests.filter(request => request.options?.method === "PATCH").length, 0);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).pending", applied.context), null);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", applied.context), false);

  const notApplied = await runCase(false);
  assert.equal(notApplied.requests.filter(request => request.options?.method === "PATCH").length, 1);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).pending", notApplied.context), null);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", notApplied.context), false);
});

test("a mutation during an in-flight cloud write remains durably dirty", async () => {
  const requests = [];
  let resolvePatch;
  const patchResponse = new Promise(resolve => { resolvePatch = resolve; });
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (options?.method === "PATCH") return patchResponse;
    return new Response(null, { status: 204 });
  });
  vm.runInContext(`
    state = defaultAppState();
    bindRemoteStateRevision({
      userId: activeAccount.userId,
      exists: true,
      revision: "2026-07-20T12:00:00.000000+00:00"
    });
    saveSyncBaseline(syncedBaseline(
      activeAccount.userId,
      remoteStateSync,
      remoteStateFingerprint(state, activeAccount.userId)
    ));
  `, context);

  const savePromise = vm.runInContext("saveRemoteState()", context);
  await new Promise(resolve => setImmediate(resolve));
  vm.runInContext(`
    state.profile.goal = "Strength";
    saveState({ queueRemote: false });
  `, context);
  resolvePatch(new Response(JSON.stringify([{ updated_at: "2026-07-20T12:00:00.000001+00:00" }]), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  }));
  await savePromise;

  assert.equal(requests.filter(request => request.options?.method === "PATCH").length, 1);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", context), true);
  assert.equal(vm.runInContext(`(() => {
    const baseline = loadSyncBaseline(activeAccount.userId);
    return baseline.syncedFingerprint !== baseline.localFingerprint;
  })()`, context), true);
});

test("browser and cloud edits since the confirmed baseline require an explicit choice", async () => {
  const requests = [];
  let remotePayload;
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    return new Response(JSON.stringify([{
      state: remotePayload,
      updated_at: "2026-07-20T13:00:00.000001+00:00"
    }]), { status: 200, headers: { "Content-Type": "application/json" } });
  });
  const basePayload = JSON.parse(vm.runInContext(
    "JSON.stringify(remoteStatePayload(activeAccount.userId, defaultAppState()))",
    context
  ));
  remotePayload = JSON.parse(vm.runInContext(`JSON.stringify((() => {
    const remote = defaultAppState();
    remote.profile.days = 6;
    return remoteStatePayload(activeAccount.userId, remote);
  })())`, context));
  context.__basePayload = basePayload;
  vm.runInContext(`
    const confirmed = normalizeImportedState(globalThis.__basePayload, defaultAppState());
    const confirmedFingerprint = remoteStateFingerprint(confirmed, activeAccount.userId);
    state = confirmed;
    state.profile.goal = "Strength";
    saveState({ queueRemote: false, markDirty: false });
    saveSyncBaseline({
      version: 1,
      userId: activeAccount.userId,
      remoteExists: true,
      revision: "2026-07-20T13:00:00.000000+00:00",
      syncedFingerprint: confirmedFingerprint,
      localFingerprint: remoteStateFingerprint(state, activeAccount.userId),
      dirty: true,
      pending: null,
      updatedAt: Date.now()
    });
  `, context);

  await vm.runInContext("pullRemoteState()", context);

  assert.equal(requests.length, 1, "conflict detection must not write either version");
  assert.equal(vm.runInContext("state.profile.goal", context), "Strength");
  assert.equal(vm.runInContext("cloudSyncConflict.userId", context), ACTIVE_USER_ID);
  assert.match(vm.runInContext("cloudSyncConflictScreen()", context), /Keep browser version/);
  assert.match(vm.runInContext("cloudSyncConflictScreen()", context), /Use cloud version/);
});

test("a dirty edit survives reload before debounce and uploads after reconciliation", async () => {
  const sharedValues = new Map();
  const sharedSessionValues = new Map();
  let basePayload;
  const first = loadContext(async () => {
    throw new Error("the first page must not sync before simulated reload");
  }, { sharedValues, sharedSessionValues });
  basePayload = JSON.parse(vm.runInContext(
    "JSON.stringify(remoteStatePayload(activeAccount.userId, defaultAppState()))",
    first
  ));
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    state = defaultAppState();
    saveState({ queueRemote: false, markDirty: false });
    bindRemoteStateRevision({
      userId: activeAccount.userId,
      exists: true,
      revision: "2026-07-20T14:00:00.000000+00:00"
    });
    saveSyncBaseline(syncedBaseline(
      activeAccount.userId,
      remoteStateSync,
      remoteStateFingerprint(state, activeAccount.userId)
    ));
    state.profile.goal = "Strength";
    saveState();
    clearTimeout(remoteSaveTimer);
    remoteSaveTimer = null;
  `, first);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", first), true);

  const requests = [];
  const second = loadContext(async (url, options) => {
    requests.push({ url, options });
    if ((options?.method || "GET") === "GET") {
      return new Response(JSON.stringify([{
        state: basePayload,
        updated_at: "2026-07-20T14:00:00.000000+00:00"
      }]), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (options.method === "PATCH") {
      return new Response(JSON.stringify([{ updated_at: "2026-07-20T14:00:00.000001+00:00" }]), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  }, {
    sharedValues,
    sharedSessionValues,
    seedActiveSession: false,
    locationSearch: ""
  });
  await new Promise(resolve => setTimeout(resolve, 100));

  assert.equal(requests.filter(request => request.options?.method === "PATCH").length, 1);
  assert.equal(vm.runInContext("state.profile.goal", second), "Strength");
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", second), false);
});

test("terminal reauthentication preserves a dirty baseline for the next login", async () => {
  const requests = [];
  let basePayload;
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if ((options?.method || "GET") === "GET") {
      return new Response(JSON.stringify([{
        state: basePayload,
        updated_at: "2026-07-20T15:00:00.000000+00:00"
      }]), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (options.method === "PATCH") {
      return new Response(JSON.stringify([{ updated_at: "2026-07-20T15:00:00.000001+00:00" }]), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  });
  basePayload = JSON.parse(vm.runInContext(
    "JSON.stringify(remoteStatePayload(activeAccount.userId, defaultAppState()))",
    context
  ));
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    state = defaultAppState();
    saveState({ queueRemote: false, markDirty: false });
    bindRemoteStateRevision({
      userId: activeAccount.userId,
      exists: true,
      revision: "2026-07-20T15:00:00.000000+00:00"
    });
    saveSyncBaseline(syncedBaseline(
      activeAccount.userId,
      remoteStateSync,
      remoteStateFingerprint(state, activeAccount.userId)
    ));
    state.profile.goal = "Strength";
    saveState({ queueRemote: false });
    const terminal = new Error("revoked");
    terminal.status = 401;
    terminal.terminalAuth = true;
    transitionToReauthentication(terminal);
  `, context);
  assert.equal(vm.runInContext(`loadSyncBaseline(${JSON.stringify(ACTIVE_USER_ID)}).dirty`, context), true);
  context.__reloginSession = {
    access_token: unsignedJwtFor(ACTIVE_USER_ID),
    refresh_token: "relogin-refresh-token",
    user: { id: ACTIVE_USER_ID, email: "owner@example.com" }
  };

  await vm.runInContext("activateRemoteSession(globalThis.__reloginSession)", context);

  assert.equal(requests.filter(request => request.options?.method === "PATCH").length, 1);
  assert.equal(vm.runInContext("state.profile.goal", context), "Strength");
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).dirty", context), false);
});

test("cloud sync baselines remain isolated by authenticated account", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  const otherUserId = "00000000-0000-4000-8000-000000000099";
  vm.runInContext(`
    state = defaultAppState();
    state.profile.goal = "Strength";
    markRemoteStateDirtyBeforeWrite(state);
  `, context);
  const firstKey = `gym-pwa-sync-baseline-v1:${ACTIVE_USER_ID}`;
  const firstBaseline = context.localStorage.getItem(firstKey);
  vm.runInContext(`
    activeAccount = {
      id: "remote-${otherUserId}",
      name: "Other",
      userId: ${JSON.stringify(otherUserId)},
      remote: "supabase"
    };
    saveRemoteSession({
      access_token: ${JSON.stringify(unsignedJwtFor(otherUserId))},
      refresh_token: "other-account-refresh-token",
      user: { id: activeAccount.userId }
    });
    state = defaultAppState();
    state.profile.days = 5;
    markRemoteStateDirtyBeforeWrite(state);
  `, context);

  assert.equal(context.localStorage.getItem(firstKey), firstBaseline);
  assert.notEqual(context.localStorage.getItem(`gym-pwa-sync-baseline-v1:${otherUserId}`), null);
  assert.equal(vm.runInContext("loadSyncBaseline(activeAccount.userId).userId", context), otherUserId);
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

test("production v2 Garmin bindings stay paired while embedded legacy secrets are stripped", () => {
  const context = loadContext(async () => {
    throw new Error("binding migration must not use the network");
  });
  const deviceId = "00000000-0000-4000-8000-000000000076";
  context.localStorage.setItem("gym-pwa-garmin-device-bindings-v2", JSON.stringify({
    [ACTIVE_USER_ID]: {
      version: 2,
      userId: ACTIVE_USER_ID,
      deviceId,
      deviceToken: "legacy-secret-must-not-survive",
    },
  }));

  const migrated = vm.runInContext(
    `garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)})`,
    context,
  );
  assert.equal(migrated.version, 2);
  assert.equal(migrated.deviceId, deviceId);
  assert.equal(Object.hasOwn(migrated, "recoveryPending"), false);
  const persisted = context.localStorage.getItem(
    "gym-pwa-garmin-device-bindings-v2",
  );
  assert.equal(persisted.includes("legacy-secret-must-not-survive"), false);
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

test("pending cloud activation can sign out without a cloud-state flush", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    return new Response(null, { status: 204 });
  });
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    const pendingSession = { ...loadRemoteSession(), activation_pending: "signup" };
    saveRemoteSession(pendingSession);
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(requests.some(request => request.url.includes("/rest/v1/user_states")), false);
  assert.equal(requests.filter(request => request.url.includes("/auth/v1/logout")).length, 1);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
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
  assert.equal(vm.runInContext("state.catalogSeedVersion", context), 2);
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
  const token = garminTestCapability(deviceId, "a".repeat(64));
  const context = loadContext(async (_url, options) => {
    const action = JSON.parse(options.body).action;
    const payload = action === "listDevices"
      ? { devices: [] }
      : { device: garminTestCreatedDevice(deviceId, token) };
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
  const token = garminTestCapability(deviceId, "b".repeat(64));
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
        device: garminTestCreatedDevice(deviceId, token)
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
  const token = garminTestCapability(deviceId, "e".repeat(64));
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
        device: garminTestCreatedDevice(deviceId, token)
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
    assert.equal(body.capabilityVersion, 2);
    assert.match(body.replacementToken, /^[a-f0-9]{64}$/);
    replacementToken = body.replacementToken;
    return new Response(JSON.stringify({
      status: "rotated",
      device: {
        id: deviceId,
        device_token: replacementToken,
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
    assert.equal(
      shownToken,
      rotationBodies[2].replacementToken,
    );
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
    assert.equal(
      shownToken,
      rotationBodies[0].replacementToken,
    );
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
  const token = garminTestCapability(deviceId, "1".repeat(64));
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
        device: garminTestCreatedDevice(deviceId, token)
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
  const token = garminTestCapability(deviceId, "2".repeat(64));
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
        device: garminTestCreatedDevice(deviceId, token)
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

test("remote recovery mode renders for the normalized Supabase account discriminator", () => {
  const context = loadContext(async () => {
    throw new Error("network is not used");
  });
  vm.runInContext(`
    cloudStateRecovery = {
      userId: activeAccount.userId,
      revision: "2026-07-13T20:00:00.000000+00:00",
      rawState: { schemaVersion: 1 }
    };
    render();
  `, context);

  assert.match(context.appNode.innerHTML, /Cloud data recovery/);
  assert.match(context.appNode.innerHTML, /Download original private JSON/);
});

test("logout flushes the debounced cloud state before revoking only the local Supabase session", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/rest/v1/user_states")) {
      return new Response(JSON.stringify([{ updated_at: "2026-07-13T20:00:00.000001+00:00" }]), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(null, { status: 204 });
  });
  vm.runInContext(`
    remoteStateSync = {
      userId: activeAccount.userId,
      exists: true,
      revision: "2026-07-13T20:00:00.000000+00:00"
    };
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    state.profile.goal = "strength";
    saveState();
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(requests.length, 3);
  assert.match(requests[0].url, /\/rest\/v1\/user_states/);
  assert.match(requests[1].url, /\/rest\/v1\/profiles/);
  const logoutUrl = new URL(requests[2].url);
  assert.equal(logoutUrl.pathname, "/auth/v1/logout");
  assert.equal(logoutUrl.searchParams.get("scope"), "local");
  assert.notEqual(logoutUrl.searchParams.get("scope"), "global");
  assert.equal(vm.runInContext("activeAccount", context), null);
});

test("a profile publication failure reports a partial result after the workout state commits", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/user_states")) {
      return new Response(JSON.stringify([{ updated_at: "2026-07-13T20:00:00.000001+00:00" }]), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(JSON.stringify({ message: "profile unavailable" }), {
      status: 503,
      headers: { "Content-Type": "application/json" }
    });
  });
  vm.runInContext(`remoteStateSync = {
    userId: activeAccount.userId,
    exists: true,
    revision: "2026-07-13T20:00:00.000000+00:00"
  };`, context);

  const result = await vm.runInContext("saveRemoteState()", context);
  assert.equal(result.stateSaved, true);
  assert.equal(result.profileUpdated, false);
  assert.equal(requests.length, 2);
  assert.equal(
    vm.runInContext("remoteStateSync.revision", context),
    "2026-07-13T20:00:00.000001+00:00"
  );
});

test("terminal refresh rejection clears the tab session and presents explicit reauthentication", async () => {
  const context = loadContext(async () => new Response(JSON.stringify({ error: "invalid_grant" }), {
    status: 401,
    headers: { "Content-Type": "application/json" }
  }));
  vm.runInContext("localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));", context);

  const error = await vm.runInContext("refreshRemoteSession(loadRemoteSession()).catch(error => error)", context);
  assert.equal(error.terminalAuth, true);
  assert.equal(error.status, 401);
  context.__terminalError = error;
  assert.equal(vm.runInContext("transitionToReauthentication(globalThis.__terminalError)", context), true);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.match(vm.runInContext("authNotice.text", context), /session expired or was revoked/i);
});

test("web signup and confirmation resend reuse the same PKCE transaction on the exact redirect", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/auth/v1/signup")) {
      return new Response(JSON.stringify({ user: { id: ACTIVE_USER_ID, email: "new-owner@example.com" } }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (url.includes("/auth/v1/resend")) {
      return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  vm.runInContext("activeAccount = null; clearRemoteSession(); state = defaultAppState();", context);
  context.runtimeNodes.set("#signup-name", { value: "New Owner" });
  context.runtimeNodes.set("#signup-email", { value: "new-owner@example.com" });
  context.runtimeNodes.set("#signup-email-confirm", { value: "new-owner@example.com" });
  context.runtimeNodes.set("#signup-password", { value: "StrongPass123!" });
  context.runtimeNodes.set("#signup-password-confirm", { value: "StrongPass123!" });

  await vm.runInContext("remoteLogin(true)", context);
  const signupUrl = new URL(requests[0].url);
  const signupBody = JSON.parse(requests[0].options.body);
  const initialTransaction = JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1"));
  assert.equal(signupUrl.pathname, "/auth/v1/signup");
  assert.equal(signupUrl.searchParams.get("redirect_to"), "https://gymapptracker.com/confirmed.html?platform=web");
  assert.equal(signupBody.code_challenge_method, "s256");
  assert.match(signupBody.code_challenge, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(Object.hasOwn(signupBody, "code_verifier"), false);
  assert.equal(initialTransaction.purpose, "signup");
  assert.equal(initialTransaction.email, "new-owner@example.com");

  await vm.runInContext("resendRemoteConfirmation()", context);
  const resendUrl = new URL(requests[1].url);
  const resendBody = JSON.parse(requests[1].options.body);
  const resentTransaction = JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1"));
  assert.equal(resendUrl.pathname, "/auth/v1/resend");
  assert.equal(resendUrl.searchParams.get("redirect_to"), "https://gymapptracker.com/confirmed.html?platform=web");
  assert.deepEqual(Object.keys(resendBody).sort(), ["code_challenge", "code_challenge_method", "email", "type"]);
  assert.equal(resendBody.type, "signup");
  assert.equal(resendBody.code_challenge_method, "s256");
  assert.match(resendBody.code_challenge, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(resentTransaction.purpose, "signup");
  assert.equal(resentTransaction.state, initialTransaction.state);
  assert.equal(resentTransaction.verifier, initialTransaction.verifier);
  assert.equal(resendBody.code_challenge, signupBody.code_challenge);
});

test("web signup callback exchanges its PKCE code and activates the confirmed cloud account", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/auth/v1/signup")) {
      return new Response(JSON.stringify({ user: { id: ACTIVE_USER_ID, email: "new-owner@example.com" } }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (url.includes("grant_type=pkce")) {
      return new Response(JSON.stringify({
        access_token: unsignedJwtFor(ACTIVE_USER_ID),
        refresh_token: "signup-replacement-refresh-token",
        user: { id: ACTIVE_USER_ID, email: "new-owner@example.com", user_metadata: { display_name: "New Owner" } }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (url.includes("/rest/v1/user_states")) {
      return new Response("[]", { status: 200, headers: { "Content-Type": "application/json" } });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  vm.runInContext("activeAccount = null; clearRemoteSession(); state = defaultAppState();", context);
  context.runtimeNodes.set("#signup-name", { value: "New Owner" });
  context.runtimeNodes.set("#signup-email", { value: "new-owner@example.com" });
  context.runtimeNodes.set("#signup-email-confirm", { value: "new-owner@example.com" });
  context.runtimeNodes.set("#signup-password", { value: "StrongPass123!" });
  context.runtimeNodes.set("#signup-password-confirm", { value: "StrongPass123!" });

  await vm.runInContext("remoteLogin(true)", context);
  const stored = JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1"));
  const code = "34e770dd-9ff9-416c-87fa-43b31d7ef225";
  await vm.runInContext(
    `completeAuthCallback(new URLSearchParams(${JSON.stringify(`platform=web&state=${stored.state}&purpose=signup&code=${code}`)}))`,
    context
  );

  const tokenRequest = requests.find(request => request.url.includes("grant_type=pkce"));
  assert.deepEqual(JSON.parse(tokenRequest.options.body), { auth_code: code, code_verifier: stored.verifier });
  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext("loadRemoteSession().password_update_required", context), undefined);
  assert.equal(context.localStorage.getItem("gym-pwa-auth-transaction-v1"), null);
  vm.runInContext("clearTimeout(remoteSaveTimer); remoteSaveTimer = null;", context);
});

test("a verified PKCE session survives a transient cloud-load failure and resumes after reload", async () => {
  const sharedValues = new Map();
  const sharedSessionValues = new Map();
  const firstRequests = [];
  const first = loadContext(async (url, options) => {
    firstRequests.push({ url, options });
    if (url.includes("grant_type=pkce")) {
      return new Response(JSON.stringify({
        access_token: unsignedJwtFor(ACTIVE_USER_ID),
        refresh_token: "durable-activation-refresh-token",
        user: { id: ACTIVE_USER_ID, email: "owner@example.com" }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify({ message: "temporarily unavailable" }), {
      status: 503,
      headers: { "Content-Type": "application/json" }
    });
  }, { sharedValues, sharedSessionValues });
  const transaction = {
    version: 1,
    purpose: "signup",
    state: "D".repeat(32),
    verifier: "v".repeat(43),
    email: "owner@example.com",
    createdAt: Date.now()
  };
  first.localStorage.setItem("gym-pwa-auth-transaction-v1", JSON.stringify(transaction));
  vm.runInContext("activeAccount = null; clearRemoteSession(); state = defaultAppState();", first);
  const remotePayload = JSON.parse(vm.runInContext(
    `JSON.stringify(remoteStatePayload(${JSON.stringify(ACTIVE_USER_ID)}, defaultAppState()))`,
    first
  ));
  const code = "24e770dd-9ff9-416c-87fa-43b31d7ef225";

  await vm.runInContext(
    `completeAuthCallback(new URLSearchParams(${JSON.stringify(`platform=web&state=${transaction.state}&purpose=signup&code=${code}`)}))`,
    first
  );
  assert.equal(first.localStorage.getItem("gym-pwa-auth-transaction-v1"), null);
  assert.equal(vm.runInContext("loadRemoteSession().activation_pending", first), "signup");
  assert.equal(vm.runInContext("activeAccount.userId", first), ACTIVE_USER_ID);

  const secondRequests = [];
  const second = loadContext(async (url, options) => {
    secondRequests.push({ url, options });
    return new Response(JSON.stringify([{
      state: remotePayload,
      updated_at: "2026-07-20T16:00:00.000000+00:00"
    }]), { status: 200, headers: { "Content-Type": "application/json" } });
  }, {
    sharedValues,
    sharedSessionValues,
    seedActiveSession: false,
    locationSearch: ""
  });
  await new Promise(resolve => setTimeout(resolve, 100));

  assert.equal(secondRequests.filter(request => request.url.includes("grant_type=pkce")).length, 0);
  assert.equal(vm.runInContext("loadRemoteSession().activation_pending", second), undefined);
  assert.equal(vm.runInContext("activeAccount.userId", second), ACTIVE_USER_ID);
});

test("web auth callback state mismatch does not exchange a code or erase the active transaction", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    throw new Error("mismatched callback must not use the network");
  });
  const stored = {
    version: 1,
    purpose: "signup",
    state: "S".repeat(32),
    verifier: "v".repeat(43),
    email: "owner@example.com",
    createdAt: Date.now()
  };
  context.localStorage.setItem("gym-pwa-auth-transaction-v1", JSON.stringify(stored));
  vm.runInContext("activeAccount = null; clearRemoteSession();", context);
  const code = "dd8af18b-ffb8-4f1e-8552-972ccf840d9f";
  await vm.runInContext(
    `completeAuthCallback(new URLSearchParams(${JSON.stringify(`platform=web&state=${"M".repeat(32)}&purpose=signup&code=${code}`)}))`,
    context
  );

  assert.equal(requests.length, 0);
  assert.deepEqual(JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1")), stored);
});

test("web auth callback purpose and error fields cannot clear or redirect the stored transaction", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    throw new Error("rejected callback must not use the network");
  });
  const stored = {
    version: 1,
    purpose: "recovery",
    state: "R".repeat(32),
    verifier: "v".repeat(43),
    email: "owner@example.com",
    createdAt: Date.now()
  };
  context.localStorage.setItem("gym-pwa-auth-transaction-v1", JSON.stringify(stored));
  vm.runInContext("activeAccount = null; clearRemoteSession();", context);

  await vm.runInContext(
    `completeAuthCallback(new URLSearchParams(${JSON.stringify(`platform=web&state=${stored.state}&purpose=signup&error=access_denied`)}))`,
    context
  );
  assert.equal(vm.runInContext("authMode", context), "forgot");
  assert.deepEqual(JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1")), stored);

  await vm.runInContext(
    `completeAuthCallback(new URLSearchParams(${JSON.stringify(`platform=web&state=${stored.state}&purpose=recovery&error=access_denied&error_description=Expired`)}))`,
    context
  );
  assert.equal(requests.length, 0);
  assert.deepEqual(JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1")), stored);
});

test("web password recovery keeps redirect_to on the exact production allowlist and exchanges PKCE locally", async () => {
  const requests = [];
  let recoveryState = "";
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("/auth/v1/recover")) {
      return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (url.includes("grant_type=pkce")) {
      return new Response(JSON.stringify({
        access_token: unsignedJwtFor(ACTIVE_USER_ID),
        refresh_token: "replacement-refresh-token",
        user: { id: ACTIVE_USER_ID, email: "owner@example.com" }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (url.includes("/rest/v1/user_states")) {
      return new Response("[]", { status: 200, headers: { "Content-Type": "application/json" } });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  vm.runInContext("activeAccount = null; clearRemoteSession(); state = defaultAppState();", context);

  await vm.runInContext('requestPasswordReset("owner@example.com")', context);
  const stored = JSON.parse(context.localStorage.getItem("gym-pwa-auth-transaction-v1"));
  recoveryState = stored.state;
  const recoverUrl = new URL(requests[0].url);
  assert.equal(
    recoverUrl.searchParams.get("redirect_to"),
    "https://gymapptracker.com/confirmed.html?platform=web"
  );
  assert.equal(recoverUrl.searchParams.get("redirect_to").includes("state="), false);
  const recoverBody = JSON.parse(requests[0].options.body);
  assert.equal(recoverBody.code_challenge_method, "s256");
  assert.match(recoverBody.code_challenge, /^[A-Za-z0-9_-]{43}$/);

  const code = "4be36bc9-5ee4-40f3-a674-5ebf01b53ac8";
  await vm.runInContext(
    `completeAuthCallback(new URLSearchParams(${JSON.stringify(`platform=web&state=${recoveryState}&purpose=recovery&code=${code}`)}))`,
    context
  );
  const tokenRequest = requests.find(request => request.url.includes("grant_type=pkce"));
  assert.ok(tokenRequest);
  const tokenBody = JSON.parse(tokenRequest.options.body);
  assert.equal(tokenBody.auth_code, code);
  assert.equal(tokenBody.code_verifier, stored.verifier);
  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext("loadRemoteSession().password_update_required", context), true);
  assert.equal(context.localStorage.getItem("gym-pwa-auth-transaction-v1"), null);
  vm.runInContext("clearTimeout(remoteSaveTimer); remoteSaveTimer = null;", context);
});

test("signed-in password change requires the current password while recovery does not", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith("/auth/v1/user")) {
      return new Response(JSON.stringify({ id: ACTIVE_USER_ID }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  context.runtimeNodes.set("#change-current-password", { value: "OldPassword123!" });
  context.runtimeNodes.set("#change-new-password", { value: "NewPassword123!" });
  context.runtimeNodes.set("#change-repeat-password", { value: "NewPassword123!" });
  vm.runInContext('modal = { type: "change-password" };', context);

  const markup = vm.runInContext("modalMarkup()", context);
  assert.match(markup, /id="change-current-password"/);
  assert.match(markup, /autocomplete="current-password"/);
  await vm.runInContext("updateRemotePassword()", context);

  assert.equal(requests.length, 1);
  assert.deepEqual(JSON.parse(requests[0].options.body), {
    password: "NewPassword123!",
    current_password: "OldPassword123!"
  });
});

test("password change refreshes an expired access token before the authenticated user request", async () => {
  const requests = [];
  const freshAccessToken = unsignedJwtFor(ACTIVE_USER_ID);
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.includes("grant_type=refresh_token")) {
      return new Response(JSON.stringify({
        access_token: freshAccessToken,
        refresh_token: "password-rotated-refresh-token",
        user: { id: ACTIVE_USER_ID }
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify({ id: ACTIVE_USER_ID }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  });
  vm.runInContext(`saveRemoteSession({
    access_token: ${JSON.stringify(unsignedJwtFor(ACTIVE_USER_ID, 1))},
    refresh_token: "password-expired-refresh-token",
    user: { id: activeAccount.userId }
  });`, context);
  context.runtimeNodes.set("#change-current-password", { value: "OldPassword123!" });
  context.runtimeNodes.set("#change-new-password", { value: "NewPassword123!" });
  context.runtimeNodes.set("#change-repeat-password", { value: "NewPassword123!" });
  vm.runInContext('modal = { type: "change-password" };', context);

  await vm.runInContext("updateRemotePassword()", context);

  assert.equal(requests.length, 2);
  assert.match(requests[0].url, /grant_type=refresh_token/);
  assert.match(requests[1].url, /\/auth\/v1\/user$/);
  assert.equal(requests[1].options.headers.Authorization, `Bearer ${freshAccessToken}`);
});

test("signed-in password change keeps the email nonce reauthentication fallback", async () => {
  const requests = [];
  let updateCount = 0;
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith("/auth/v1/user")) {
      updateCount += 1;
      if (updateCount === 1) {
        return new Response(JSON.stringify({ code: "reauthentication_needed" }), {
          status: 422,
          headers: { "Content-Type": "application/json" }
        });
      }
      return new Response(JSON.stringify({ id: ACTIVE_USER_ID }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (url.endsWith("/auth/v1/reauthenticate")) {
      return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  const fillPasswordFields = nonce => {
    context.runtimeNodes.set("#change-current-password", { value: "OldPassword123!" });
    context.runtimeNodes.set("#change-new-password", { value: "NewPassword123!" });
    context.runtimeNodes.set("#change-repeat-password", { value: "NewPassword123!" });
    context.runtimeNodes.set("#change-password-nonce", { value: nonce });
  };
  fillPasswordFields("");
  vm.runInContext('modal = { type: "change-password" };', context);

  await vm.runInContext("updateRemotePassword()", context);
  assert.equal(vm.runInContext("modal.reauthRequired", context), true);
  const reauthenticateRequests = requests.filter(request => request.url.endsWith("/auth/v1/reauthenticate"));
  assert.equal(reauthenticateRequests.length, 1);
  assert.equal(reauthenticateRequests[0].options.method, "GET");
  assert.equal(reauthenticateRequests[0].options.body, undefined);

  fillPasswordFields("123456");
  await vm.runInContext("updateRemotePassword()", context);
  const updateBodies = requests
    .filter(request => request.url.endsWith("/auth/v1/user"))
    .map(request => JSON.parse(request.options.body));
  assert.deepEqual(updateBodies, [
    { password: "NewPassword123!", current_password: "OldPassword123!" },
    { password: "NewPassword123!", current_password: "OldPassword123!", nonce: "123456" }
  ]);
});

test("mandatory password update and cloud deletion validate Supabase responses before cleanup", async () => {
  const requests = [];
  const context = loadContext(async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith("/auth/v1/user")) {
      return new Response(JSON.stringify({ id: ACTIVE_USER_ID }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (url.endsWith("/functions/v1/delete-account")) {
      return new Response(JSON.stringify({ deleted: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  vm.runInContext(`
    const pendingPasswordSession = { ...loadRemoteSession(), password_update_required: true };
    saveRemoteSession(pendingPasswordSession);
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveAccountList([activeAccount]);
    saveState({ queueRemote: false });
  `, context);
  context.runtimeNodes.set("#recovery-new-password", { value: "StrongPass123!" });
  context.runtimeNodes.set("#recovery-repeat-password", { value: "StrongPass123!" });

  await vm.runInContext("updateRemotePassword({ required: true })", context);
  assert.equal(vm.runInContext("loadRemoteSession().password_update_required", context), undefined);
  assert.deepEqual(JSON.parse(requests[0].options.body), { password: "StrongPass123!" });

  context.window.confirm = () => true;
  context.window.prompt = () => "DELETE";
  await vm.runInContext("deleteCloudAccount()", context);
  const deleteRequest = requests.find(request => request.url.endsWith("/functions/v1/delete-account"));
  assert.deepEqual(JSON.parse(deleteRequest.options.body), { confirmation: "DELETE" });
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(context.localStorage.getItem(`gym-pwa-account:remote-${ACTIVE_USER_ID}`), null);
  assert.equal(JSON.parse(context.localStorage.getItem("gym-pwa-account-list-v1")).length, 0);
});

test("cloud deletion rejects an expanded response contract before browser cleanup", async () => {
  const context = loadContext(async url => {
    if (url.endsWith("/functions/v1/delete-account")) {
      return new Response(JSON.stringify({ deleted: true, unexpected: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    throw new Error(`unexpected request: ${url}`);
  });
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveAccountList([activeAccount]);
    saveState({ queueRemote: false });
  `, context);
  const sessionBefore = context.sessionStorage.getItem("gym-pwa-supabase-session-v1");
  context.window.confirm = () => true;
  context.window.prompt = () => "DELETE";

  await vm.runInContext("deleteCloudAccount()", context);

  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(context.sessionStorage.getItem("gym-pwa-supabase-session-v1"), sessionBefore);
  assert.equal(JSON.parse(context.localStorage.getItem("gym-pwa-account-list-v1")).length, 1);
});

test("local account deletion removes only the confirmed local profile", () => {
  const context = loadContext(async () => {
    throw new Error("local deletion must not use the network");
  });
  vm.runInContext("activeAccount = null; clearRemoteSession(); loginAccount('Local Owner');", context);
  const localId = vm.runInContext("activeAccount.id", context);
  const localKey = `gym-pwa-account:${localId}`;
  context.window.confirm = () => true;
  context.window.prompt = () => "DELETE";

  vm.runInContext("deleteLocalAccount()", context);

  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem(localKey), null);
  assert.equal(JSON.parse(context.localStorage.getItem("gym-pwa-account-list-v1")).length, 0);
  assert.equal(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
});
