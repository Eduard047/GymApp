import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stateContractSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/state-contract.js", "utf8")
]);
const ACTIVE_USER_ID = "00000000-0000-4000-8000-000000000001";

function unsignedJwtFor(userId) {
  const header = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ sub: userId, exp: 4102444800 })).toString("base64url");
  return `${header}.${payload}.test-signature`;
}

function loadContext(fetchImpl, { randomSeed = 1 } = {}) {
  const values = new Map();
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
    navigator: {},
    localStorage: {
      getItem: key => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, String(value)),
      removeItem: key => values.delete(key)
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
  context.window.crypto = context.crypto;
  context.window.history = context.history;
  context.window.self = context.window;
  context.window.top = context.window;
  context.window.__GYMAPP_TOP_LEVEL__ = true;
  vm.createContext(context);
  vm.runInContext(stateContractSource, context);
  context.window.GymStateContract = context.GymStateContract;
  vm.runInContext(appSource, context);
  vm.runInContext(`
    activeAccount = {
      id: "remote-user-1",
      name: "Owner",
      userId: ${JSON.stringify(ACTIVE_USER_ID)},
      remote: "supabase"
    };
    localStorage.setItem(REMOTE_SESSION_KEY, JSON.stringify({
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

test("account transitions clear timers and revoke a bound Garmin device before session destruction", async () => {
  assert.match(appSource, /clearTimeout\(remoteSaveTimer\);[\s\S]*remoteStateSync = \{ userId: null, exists: false, revision: null \}/);
  assert.match(appSource, /await revokeGarminBinding\(session\);[\s\S]*localStorage\.removeItem\(REMOTE_SESSION_KEY\)/);
  assert.match(appSource, /LEGACY_GARMIN_DEVICE_TOKEN_KEY/);
  assert.doesNotMatch(appSource, /const current = localStorage\.getItem\(LEGACY_GARMIN_DEVICE_TOKEN_KEY\);/);
  assert.match(appSource, /storageNeedsRewrite \|\|= Boolean\([\s\S]*Object\.hasOwn\(value, "deviceToken"\)\)/);
  assert.doesNotMatch(appSource, /bindings\[binding\.userId\] = binding/);
  assert.doesNotMatch(appSource, /navigator\.clipboard\?\.writeText\(device\.device_token\)/);
  assert.match(appSource, /window\.confirm\(pairingWarning\)/);
  assert.match(appSource, /window\.prompt\(tokenPrompt, device\.device_token\)/);
  assert.match(appSource, /await revokeGarminDeviceById\(session, device\.id\)/);
});

test("failed Garmin revocation cancels sign-out by default and preserves retry state", async () => {
  const context = loadContext(async () => {
    throw new Error("network unavailable");
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

  assert.equal(confirmations, 1);
  assert.equal(vm.runInContext("activeAccount.userId", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext("loadRemoteSession().user.id", context), ACTIVE_USER_ID);
  assert.equal(vm.runInContext("garminBindingForUser(activeAccount.userId).deviceId", context), deviceId);
  assert.notEqual(context.localStorage.getItem("gym-pwa-supabase-session-v1"), null);
});

test("remote sign-out without a Garmin binding does not require a cloud session", async () => {
  const context = loadContext(async () => {
    throw new Error("network must not be used without a Garmin binding");
  });
  let confirmations = 0;
  context.window.confirm = () => {
    confirmations += 1;
    return false;
  };
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    localStorage.removeItem(REMOTE_SESSION_KEY);
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(confirmations, 0);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
});

test("explicit fallback sign-out clears local credentials but preserves failed Garmin revocation metadata", async () => {
  const context = loadContext(async () => {
    throw new Error("network unavailable");
  });
  const deviceId = "00000000-0000-4000-8000-000000000078";
  let confirmations = 0;
  context.window.confirm = () => {
    confirmations += 1;
    return true;
  };
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveGarminBinding({ version: 2, userId: activeAccount.userId, deviceId: ${JSON.stringify(deviceId)} });
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(confirmations, 1);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(context.localStorage.getItem("gym-pwa-active-account-v1"), null);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)}).deviceId`, context), deviceId);
});

test("successful Garmin revocation removes binding and credentials without a fallback prompt", async () => {
  const context = loadContext(async () => new Response(JSON.stringify({ status: "revoked" }), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  }));
  const deviceId = "00000000-0000-4000-8000-000000000079";
  let confirmations = 0;
  context.window.confirm = () => {
    confirmations += 1;
    return true;
  };
  vm.runInContext(`
    localStorage.setItem(AUTH_KEY, JSON.stringify(activeAccount));
    saveGarminBinding({ version: 2, userId: activeAccount.userId, deviceId: ${JSON.stringify(deviceId)} });
  `, context);

  await vm.runInContext("logoutAccount()", context);

  assert.equal(confirmations, 0);
  assert.equal(vm.runInContext("activeAccount", context), null);
  assert.equal(context.localStorage.getItem("gym-pwa-supabase-session-v1"), null);
  assert.equal(vm.runInContext(`garminBindingForUser(${JSON.stringify(ACTIVE_USER_ID)})`, context), null);
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
    localStorage.removeItem(REMOTE_SESSION_KEY);
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
    localStorage.removeItem(REMOTE_SESSION_KEY);
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
  const context = loadContext(async () => new Response(JSON.stringify({
    device: { id: deviceId, device_token: token, binding_version: 2 }
  }), { status: 200, headers: { "Content-Type": "application/json" } }));
  let promptCalls = 0;
  context.window.confirm = () => true;
  context.window.prompt = (_message, shownToken) => {
    promptCalls += 1;
    assert.equal(shownToken, token);
    const bindings = JSON.parse(context.localStorage.getItem("gym-pwa-garmin-device-bindings-v2"));
    assert.equal(bindings[ACTIVE_USER_ID].deviceId, deviceId);
    assert.equal(Object.hasOwn(bindings[ACTIVE_USER_ID], "deviceToken"), false);
    return "saved";
  };

  const result = await vm.runInContext("ensureGarminDeviceBinding(loadRemoteSession())", context);

  assert.equal(promptCalls, 1);
  assert.equal(result.binding.deviceId, deviceId);
  assert.equal(vm.runInContext("pendingGarminRevocations.size", context), 0);
});

test("Garmin storage failure revokes the unseen token before any prompt", async () => {
  const deviceId = "00000000-0000-4000-8000-000000000082";
  const token = "b".repeat(64);
  const actions = [];
  const context = loadContext(async (_url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action);
    if (body.action === "createDevice") {
      return new Response(JSON.stringify({
        device: { id: deviceId, device_token: token, binding_version: 2 }
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
  assert.deepEqual(actions, ["createDevice", "revokeDevice"]);
  assert.equal(promptCalls, 0);
  assert.equal(vm.runInContext("pendingGarminRevocations.size", context), 0);
});
