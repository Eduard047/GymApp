import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import test from "node:test";

const require = createRequire(import.meta.url);
const retirement = require("../pwa/retirement.js");
const rootHtml = readFileSync(new URL("../pwa/index.html", import.meta.url), "utf8");
const retirementSource = readFileSync(new URL("../pwa/retirement.js", import.meta.url), "utf8");
const retirementBytes = readFileSync(new URL("../pwa/retirement.js", import.meta.url));
const versionedRetirementBytes = readFileSync(new URL("../pwa/retirement.v1.js", import.meta.url));
const retirementStyleBytes = readFileSync(new URL("../pwa/retirement.css", import.meta.url));
const versionedRetirementStyleBytes = readFileSync(new URL("../pwa/retirement.v1.css", import.meta.url));
const workerSource = readFileSync(new URL("../pwa/sw.js", import.meta.url), "utf8");
const workoutHtml = readFileSync(new URL("../pwa/workout/index.html", import.meta.url), "utf8");
const workoutSource = readFileSync(new URL("../pwa/workout/landing.js", import.meta.url), "utf8");
const contract = JSON.parse(readFileSync(new URL("../shared/browser-retirement-v1.json", import.meta.url), "utf8"));
const readme = readFileSync(new URL("../README.md", import.meta.url), "utf8");
const developmentGuide = readFileSync(new URL("../docs/DEVELOPMENT.md", import.meta.url), "utf8");
const operationsGuide = readFileSync(new URL("../docs/OPERATIONS.md", import.meta.url), "utf8");

const GOOGLE_PLAY = new URL("https://play.google.com/store/apps/details?id=com.setforge.gymapp");
const GARMIN_STORE = new URL("https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f");

function absoluteAnchorUrls(html) {
  return [...html.matchAll(/<a\b[^>]*\bhref="(https:[^"]+)"/g)].map(match => new URL(match[1]));
}

function fakeStorage(entries) {
  const values = new Map(entries);
  const reads = [];
  return {
    reads,
    writes: 0,
    removals: 0,
    get length() { return values.size; },
    key(index) { return [...values.keys()][index] ?? null; },
    getItem(key) {
      reads.push(key);
      return values.has(key) ? values.get(key) : null;
    },
    setItem() { this.writes += 1; },
    removeItem() { this.removals += 1; }
  };
}

function legacyFixture() {
  const accountId = "local-v2-0123456789abcdef0123456789abcdef";
  const owner = `local:${accountId}`;
  const state = {
    language: "ru",
    catalogSeedVersion: 3,
    owner: { accountId, userId: "private-user", email: "private@example.test" },
    diagnostics: true,
    refresh_token: "refresh-secret",
    exercises: [{
      id: 1,
      name: "Bench Press",
      catalogKey: "bench_press",
      favorite: true,
      customImageData: "data:image/jpeg;base64,private-image",
      access_token: "nested-secret"
    }],
    sessions: [{
      id: 2,
      startedAt: 1760000000000,
      note: "Strong session",
      exerciseNames: ["Bench Press"],
      sets: [{ id: 3, exerciseName: "Bench Press", catalogKey: "bench_press", weight: 80, reps: 8, orderIndex: 0 }],
      password: "session-secret"
    }],
    mappings: { "Bench Press": ["chest"] },
    profile: { split: "Upper / Lower", days: 4, goal: "Aesthetic Cut", calories: "Deficit", email: "hidden@example.test" }
  };
  const activeWorkout = {
    version: 1,
    owner,
    id: 10,
    startedAt: 1760000000000,
    createdAt: 1760000001000,
    updatedAt: 1760000002000,
    revision: 1,
    note: "In progress",
    blocks: [{
      id: 11,
      exerciseName: "Bench Press",
      catalogKey: "bench_press",
      sets: [{ id: 12, weight: 82.5, reps: 8, completed: false, completedAt: null }]
    }]
  };
  return { accountId, state, activeWorkout };
}

test("root is a non-installable first-party download and legal landing", () => {
  const scripts = [...rootHtml.matchAll(/<script[^>]+src="([^"]+)"/g)].map(match => match[1]);
  const links = absoluteAnchorUrls(rootHtml);
  assert.deepEqual(scripts, ["./frame-guard.v56.js", "./retirement.v1.js"]);
  assert.match(rootHtml, /\.\/retirement\.v1\.css/);
  assert.equal(links.some(link => (
    link.protocol === "https:"
      && link.hostname === "play.google.com"
      && link.pathname === "/store/apps/details"
      && link.searchParams.get("id") === "com.setforge.gymapp"
  )), true);
  assert.equal(links.some(link => (
    link.protocol === "https:"
      && link.hostname === "apps.garmin.com"
      && link.pathname === "/apps/fe82a300-4d9f-4588-8b10-365d75280b8f"
      && link.search === ""
  )), true);
  assert.equal(links.some(link => link.origin === "https://gymapptracker.com" && link.pathname === "/privacy-policy.html"), true);
  assert.equal(links.some(link => link.origin === "https://gymapptracker.com" && link.pathname === "/support.html"), true);
  assert.doesNotMatch(rootHtml, /rel="manifest"|apple-mobile-web-app-capable/i);
  assert.doesNotMatch(rootHtml, /apps\.apple\.com|App Store|Coming soon/i);
  assert.doesNotMatch(rootHtml, /app\.v\d+\.js|supabase|cloud-sync|live-workout|social|auth/i);
  assert.doesNotMatch(rootHtml, /[▶↗]|class="(?:orbit|ambient|store-symbol)/u);
  assert.match(rootHtml, /worker-src 'none'/);
  assert.match(rootHtml, /connect-src 'none'/);
});

test("public documentation describes the browser as distribution-only", () => {
  for (const source of [readme, developmentGuide, operationsGuide]) {
    assert.doesNotMatch(source, /Open Web App|Web \| Installable PWA|public website and installable PWA/i);
  }
  assert.match(readme, /Website &amp; Downloads/);
  assert.match(readme, /public root intentionally does not load[\s\S]*retired workout application/);
  assert.match(developmentGuide, /root intentionally has no workout or[\s\S]*authentication runtime/);
  assert.match(operationsGuide, /public root must not load the retained workout\/PWA runtime/);
});

test("retirement bundles are text, byte-identical, syntax-valid, and contain no NUL", () => {
  assert.equal(retirementBytes.equals(versionedRetirementBytes), true);
  assert.equal(retirementStyleBytes.equals(versionedRetirementStyleBytes), true);
  assert.equal(retirementBytes.includes(0), false);
  assert.equal(versionedRetirementBytes.includes(0), false);
  execFileSync(process.execPath, ["--check", new URL("../pwa/retirement.js", import.meta.url).pathname]);
  execFileSync(process.execPath, ["--check", new URL("../pwa/retirement.v1.js", import.meta.url).pathname]);
  execFileSync(process.execPath, ["--check", new URL("../pwa/sw.js", import.meta.url).pathname]);
});

test("legacy export is conditional, bounded, explicit, and omits account/auth/device material", () => {
  const { accountId, state, activeWorkout } = legacyFixture();
  const storage = fakeStorage([
    [`gym-pwa-account:${accountId}`, JSON.stringify(state)],
    [`gym-pwa-active-workout-v1:${accountId}`, JSON.stringify(activeWorkout)],
    ["gym-pwa-supabase-session-v1", JSON.stringify({ access_token: "access-secret", refresh_token: "refresh-secret" })],
    ["gym-pwa-active-account-v1", JSON.stringify({ id: accountId, email: "private@example.test" })],
    ["gym-pwa-auth-transaction-v1", JSON.stringify({ verifier: "pkce-secret" })],
    ["gym-pwa-web-push-installation-v1", JSON.stringify({ endpoint: "https://push.example/private" })],
    ["gym-pwa-garmin-device-bindings-v2", JSON.stringify({ deviceId: "private-device" })]
  ]);

  const snapshot = retirement.collectLegacyData(storage);
  assert.equal(snapshot.available, true);
  assert.equal(snapshot.profiles.length, 1);
  assert.equal(snapshot.profiles[0].state.language, "ru");
  assert.equal(snapshot.profiles[0].activeWorkout.blocks[0].sets[0].weight, 82.5);
  assert.deepEqual(storage.reads.sort(), [
    `gym-pwa-account:${accountId}`,
    `gym-pwa-active-workout-v1:${accountId}`
  ].sort());
  assert.equal(storage.writes, 0);
  assert.equal(storage.removals, 0);

  const exported = retirement.buildExport(snapshot, new Date("2026-08-12T12:00:00.000Z"));
  const encoded = JSON.stringify(exported);
  assert.equal(exported.credentialsIncluded, false);
  assert.match(encoded, /Strong session/);
  assert.doesNotMatch(encoded, /refresh-secret|access-secret|pkce-secret|private@example|private-user|private-device|private-image/);
  assert.doesNotMatch(encoded, new RegExp(accountId));
  assert.doesNotMatch(encoded, /refresh_token|access_token|password|endpoint|owner|diagnostics|customImageData/);
});

test("legacy download defers object URL revocation so Safari can start the save", () => {
  const { accountId, state } = legacyFixture();
  const snapshot = retirement.collectLegacyData(fakeStorage([
    [`gym-pwa-account:${accountId}`, JSON.stringify(state)]
  ]));
  const revoked = [];
  const scheduled = [];
  let clicked = 0;
  let appended = null;
  const link = {
    href: "",
    download: "",
    hidden: false,
    click() { clicked += 1; },
    remove() { appended = null; }
  };
  const document = {
    body: { append(node) { appended = node; } },
    createElement(tag) {
      assert.equal(tag, "a");
      return link;
    }
  };
  const urlApi = {
    createObjectURL(blob) {
      assert.equal(blob.type, "application/json");
      return "blob:synthetic-backup";
    },
    revokeObjectURL(url) { revoked.push(url); }
  };
  retirement.downloadExport(document, snapshot, {
    urlApi,
    schedule(callback, delay) { scheduled.push({ callback, delay }); }
  });
  assert.equal(clicked, 1);
  assert.equal(appended, null);
  assert.equal(link.href, "blob:synthetic-backup");
  assert.match(link.download, /^gymapp-browser-backup-\d{4}-\d{2}-\d{2}\.json$/);
  assert.deepEqual(revoked, []);
  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].delay, 1000);
  scheduled[0].callback();
  assert.deepEqual(revoked, ["blob:synthetic-backup"]);
});

test("empty storage hides migration while malformed or oversized candidate data fails closed without mutation", () => {
  assert.equal(retirement.collectLegacyData(fakeStorage([])).available, false);

  const malformed = fakeStorage([["gym-pwa-state-v2", "{bad"]]);
  assert.throws(() => retirement.collectLegacyData(malformed), retirement.LegacyExportError);
  assert.equal(malformed.writes, 0);
  assert.equal(malformed.removals, 0);

  const tooMany = fakeStorage(Array.from({ length: retirement.LIMITS.storageKeys + 1 }, (_, index) => [`other-${index}`, "x"]));
  assert.throws(() => retirement.collectLegacyData(tooMany), retirement.LegacyExportError);
  assert.equal(tooMany.reads.length, 0);
});

test("retirement only deletes allowlisted static caches and reloads at most once per tab", async () => {
  const deleted = [];
  const cacheStorage = {
    async keys() { return ["gym-pwa-v121", "gym-pwa-v122", "other-product-cache"]; },
    async delete(name) { deleted.push(name); return true; }
  };
  assert.deepEqual(await retirement.deleteKnownStaticCaches(cacheStorage), ["gym-pwa-v121", "gym-pwa-v122"]);
  assert.deepEqual(deleted, ["gym-pwa-v121", "gym-pwa-v122"]);

  const markers = new Map();
  const session = {
    getItem(key) { return markers.get(key) ?? null; },
    setItem(key, value) { markers.set(key, value); }
  };
  assert.equal(retirement.shouldReloadAfterRetirement(session, true), true);
  assert.equal(retirement.shouldReloadAfterRetirement(session, true), false);
  assert.equal(retirement.shouldReloadAfterRetirement(session, true), false);
  assert.equal(markers.get(retirement.RETIREMENT_RELOAD_KEY), "done");
});

test("landing revokes push only for the exact GymApp scope and deletes only its known push database", async () => {
  const calls = [];
  const exact = {
    scope: "https://gymapptracker.com/",
    pushManager: {
      async getSubscription() {
        calls.push("exact-get-subscription");
        return { async unsubscribe() { calls.push("exact-unsubscribe"); return true; } };
      }
    },
    async unregister() { calls.push("exact-unregister"); return true; }
  };
  const sibling = {
    scope: "https://gymapptracker.com/other/",
    pushManager: {
      async getSubscription() {
        calls.push("sibling-get-subscription");
        return { async unsubscribe() { calls.push("sibling-unsubscribe"); return true; } };
      }
    },
    async unregister() { calls.push("sibling-unregister"); return true; }
  };
  const deletedDatabases = [];
  const indexedDB = {
    deleteDatabase(name) {
      deletedDatabases.push(name);
      const request = {};
      queueMicrotask(() => request.onsuccess?.());
      return request;
    }
  };
  const markers = new Map();
  let reloads = 0;
  const didReload = await retirement.retireLegacyWorker({
    serviceWorker: {
      controller: { scriptURL: "https://gymapptracker.com/sw.js" },
      async getRegistrations() { return [exact, sibling]; }
    }
  }, {
    href: "https://gymapptracker.com/",
    reload() { reloads += 1; }
  }, {
    getItem(key) { return markers.get(key) ?? null; },
    setItem(key, value) { markers.set(key, value); }
  }, {
    async keys() { return []; },
    async delete() { throw new Error("unexpected"); }
  }, indexedDB);
  assert.equal(didReload, true);
  assert.equal(reloads, 1);
  assert.deepEqual(calls, ["exact-get-subscription", "exact-unsubscribe", "exact-unregister"]);
  assert.deepEqual(deletedDatabases, ["gymapp-push-binding-v1"]);
  assert.doesNotMatch(retirementSource, /serviceWorker\.register|pushManager\.subscribe|fetch\s*\(/);
  assert.doesNotMatch(retirementSource, /localStorage\.(?:setItem|removeItem|clear)/);
});

test("push unsubscribe failure cannot preserve the exact retired worker or touch another database", async () => {
  const calls = [];
  const exact = {
    scope: "https://gymapptracker.com/",
    pushManager: {
      async getSubscription() {
        calls.push("get-subscription");
        return { async unsubscribe() { calls.push("unsubscribe"); throw new Error("push unavailable"); } };
      }
    },
    async unregister() { calls.push("unregister"); return true; }
  };
  const deletedDatabases = [];
  const didReload = await retirement.retireLegacyWorker({
    serviceWorker: {
      controller: null,
      async getRegistrations() { return [exact]; }
    }
  }, {
    href: "https://gymapptracker.com/",
    reload() { calls.push("reload"); }
  }, {
    getItem() { return null; },
    setItem() {}
  }, {
    async keys() { return []; },
    async delete() { throw new Error("unexpected"); }
  }, {
    deleteDatabase(name) {
      deletedDatabases.push(name);
      const request = {};
      queueMicrotask(() => request.onblocked?.());
      return request;
    }
  });
  assert.equal(didReload, true);
  assert.deepEqual(calls, ["get-subscription", "unsubscribe", "unregister", "reload"]);
  assert.deepEqual(deletedDatabases, [retirement.PUSH_BINDING_DB_NAME]);
  assert.equal(retirement.PUSH_CLEANUP_TIMEOUT_MS, 1500);
  assert.doesNotMatch(retirementSource, /indexedDB\.(?:open|databases)|deleteDatabase\([^P]/);
});

test("retirement worker upgrades old shells without touching user storage or preserved routes", () => {
  assert.match(workerSource, /self\.skipWaiting\(\)/);
  assert.match(workerSource, /self\.clients\.claim\(\)/);
  assert.match(workerSource, /name\.startsWith\(CACHE_PREFIX\)/);
  assert.match(workerSource, /client\.navigate\(ROOT_URL\.href\)/);
  assert.match(workerSource, /\.\/confirmed\.html/);
  assert.match(workerSource, /\.\/workout\//);
  assert.doesNotMatch(workerSource, /caches\.open|indexedDB|localStorage|deleteDatabase|pushManager|registration\.unregister/);
  assert.doesNotMatch(workerSource, /app\.v\d+|supabase|manifest\.webmanifest|exercise-media/);
});

test("shared workout route previews safely and hands off only to native apps", () => {
  const links = absoluteAnchorUrls(workoutHtml);
  assert.doesNotMatch(workoutHtml, /continue-web|Continue on website|continue in (?:your )?browser/i);
  assert.doesNotMatch(workoutSource, /\bweb\s*:|continue-web|\.links\.web|\$\{CANONICAL_SITE\}#|localStorage|sessionStorage/);
  assert.equal(links.some(link => link.href === GOOGLE_PLAY.href), true);
  assert.equal(links.some(link => link.origin === "https://gymapptracker.com" && link.pathname === "/"), true);
  assert.match(workoutSource, /const ANDROID_SCHEME = "com\.setforge\.gymapp"/);
  assert.match(workoutSource, /const IOS_SCHEME = "com\.setforge\.gymapp\.ios"/);
  assert.doesNotMatch(workoutHtml, /apps\.apple\.com|App Store/i);
  assert.equal(
    readFileSync(new URL("../pwa/workout/landing.js", import.meta.url)).equals(
      readFileSync(new URL("../pwa/workout/landing.v2.js", import.meta.url))
    ),
    true
  );
});

test("shared retirement contract matches the implemented limits and destinations", () => {
  assert.equal(contract.status, "browser-workout-retired");
  assert.deepEqual(contract.root.allowedScripts, ["frame-guard.v56.js", "retirement.v1.js"]);
  assert.equal(contract.root.manifestLinked, false);
  assert.equal(contract.root.appStoreLinkVisible, false);
  assert.equal(contract.readyApps[0].url, GOOGLE_PLAY.href);
  assert.equal(contract.readyApps[1].url, GARMIN_STORE.href);
  assert.equal(contract.legacyExport.maxStorageKeysInspected, retirement.LIMITS.storageKeys);
  assert.equal(contract.legacyExport.maxCandidateBytes, retirement.LIMITS.candidateBytes);
  assert.equal(contract.legacyExport.maxRecordBytes, retirement.LIMITS.recordBytes);
  assert.equal(contract.legacyExport.maxProfiles, retirement.LIMITS.profiles);
  assert.equal(contract.legacyExport.maxExercisesPerProfile, retirement.LIMITS.exercises);
  assert.equal(contract.legacyExport.maxSessionsPerProfile, retirement.LIMITS.sessions);
  assert.equal(contract.legacyExport.maxJsonDepth, retirement.LIMITS.maxDepth);
  assert.equal(contract.legacyExport.maxJsonNodes, retirement.LIMITS.maxNodes);
  assert.equal(contract.legacyExport.maxStringBytes, retirement.LIMITS.maxStringBytes);
  assert.equal(
    contract.retirementWorker.exactScopePushSubscriptionRevocation,
    "bounded-best-effort-before-unregister"
  );
  assert.equal(contract.retirementWorker.workoutIndexedDbPreserved, true);
  assert.equal(contract.retirementWorker.knownPushBindingIndexedDbDeleted, retirement.PUSH_BINDING_DB_NAME);
  assert.equal(contract.retirementWorker.otherIndexedDbPreserved, true);
  assert.equal(contract.retirementWorker.pushCleanupMaximumWaitMilliseconds, retirement.PUSH_CLEANUP_TIMEOUT_MS);
  assert.equal(contract.retirementWorker.applicationBackendMutation, "none");
});
