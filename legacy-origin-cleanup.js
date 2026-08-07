"use strict";

(() => {
  const LEGACY_ORIGIN = "https://eduard047.github.io";
  const LEGACY_PATH_PREFIX = "/GymApp/";
  const LEGACY_CLEANUP_PATHS = new Set([
    `${LEGACY_PATH_PREFIX}legacy-origin-cleanup-v61.html`,
    `${LEGACY_PATH_PREFIX}legacy-origin-cleanup-v62.html`
  ]);
  const LEGACY_SERVICE_WORKER_SCOPE = `${LEGACY_ORIGIN}${LEGACY_PATH_PREFIX}`;
  const LEGACY_SCOPE_URL = new URL(LEGACY_SERVICE_WORKER_SCOPE);
  const PUBLIC_SITE_URL = "https://gymapptracker.com/";
  const REMOTE_SESSION_KEY = "gym-pwa-supabase-session-v1";
  const SESSION_REVOCATION_MARKER_KEY = "gym-pwa-legacy-session-revocation-pending-v1";
  const AUTH_KEY = "gym-pwa-active-account-v1";
  const LEGACY_GARMIN_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";
  const GARMIN_DEVICE_BINDINGS_KEY = "gym-pwa-garmin-device-bindings-v2";
  const GARMIN_ENQUEUE_REQUESTS_KEY = "gym-pwa-garmin-enqueue-requests-v1";
  const BACKUP_DATA_KEYS = new Set([
    "gym-pwa-state-v1",
    "gym-pwa-state-v2",
    AUTH_KEY,
    "gym-pwa-account-list-v1",
    GARMIN_ENQUEUE_REQUESTS_KEY
  ]);
  const ACCOUNT_STATE_PREFIX = "gym-pwa-account:";
  const OWNED_STORAGE_PREFIX = "gym-pwa-";
  const CREDENTIAL_KEYS = [REMOTE_SESSION_KEY, LEGACY_GARMIN_TOKEN_KEY];
  const MAX_SESSION_BYTES = 64 * 1024;
  const MAX_RESPONSE_CHUNKS = 128;
  const MAX_STORAGE_KEYS = 1024;
  const MAX_OWNED_ENTRIES = 128;
  const MAX_STORAGE_KEY_LENGTH = 256;
  const MAX_OWNED_VALUE_BYTES = 8 * 1024 * 1024;
  const MAX_ARCHIVE_BYTES = 16 * 1024 * 1024;
  const MAX_RUNTIME_ITEMS = 256;
  const status = document.querySelector("#cleanup-status");
  const dataSummary = document.querySelector("#cleanup-data-summary");
  const continueLink = document.querySelector("#cleanup-continue");
  const retryButton = document.querySelector("#cleanup-retry");
  const backupButton = document.querySelector("#cleanup-backup");
  const purgeButton = document.querySelector("#cleanup-purge");
  const storageAccesses = [acquireStorage("sessionStorage"), acquireStorage("localStorage")];
  let pendingSessions = null;
  let sessionReadComplete = false;
  let privateSnapshot = null;
  let backupDownloaded = false;
  let coreCleanupComplete = false;
  let cleanupRunning = false;
  let continuationRunning = false;

  const setStatus = message => {
    if (status) status.textContent = message;
  };

  const setActions = ({ canContinue = false, canRetry = false } = {}) => {
    if (continueLink) continueLink.hidden = !canContinue;
    if (retryButton) retryButton.hidden = !canRetry;
  };

  const hideDataActions = () => {
    if (dataSummary) dataSummary.hidden = true;
    if (backupButton) backupButton.hidden = true;
    if (purgeButton) {
      purgeButton.hidden = true;
      purgeButton.disabled = true;
    }
  };

  function acquireStorage(name) {
    try {
      const storage = window[name];
      if (!storage || typeof storage.getItem !== "function" ||
          typeof storage.removeItem !== "function" || typeof storage.key !== "function") {
        return { name, storage: null, available: false };
      }
      return { name, storage, available: true };
    } catch {
      return { name, storage: null, available: false };
    }
  }

  function isBoundedAccessToken(value) {
    return typeof value === "string" && value.length >= 16 && value.length <= 16384;
  }

  function isBoundedRefreshToken(value) {
    // Supabase refresh tokens are opaque. Their security does not depend on a
    // client-enforced minimum length, so accept every non-empty bounded value
    // that the current PWA session contract accepts.
    return typeof value === "string" && value.length > 0 && value.length <= 8192;
  }

  function isWithinLegacyScope(rawUrl) {
    try {
      const url = new URL(rawUrl);
      return url.origin === LEGACY_SCOPE_URL.origin &&
        url.pathname.startsWith(LEGACY_SCOPE_URL.pathname);
    } catch {
      return false;
    }
  }

  function readLegacySession(access, { ignoreMarker = false } = {}) {
    if (!access.available) return { complete: false, session: null };
    try {
      const pendingMarker = access.storage.getItem(SESSION_REVOCATION_MARKER_KEY);
      const raw = access.storage.getItem(REMOTE_SESSION_KEY);
      const markerClear = ignoreMarker || pendingMarker === null;
      if (raw === null) return { complete: markerClear, session: null };
      if (!raw || new TextEncoder().encode(raw).byteLength > MAX_SESSION_BYTES) {
        return { complete: false, session: null };
      }
      const parsed = JSON.parse(raw);
      const accessToken = isBoundedAccessToken(parsed?.access_token) ? parsed.access_token : null;
      const refreshToken = isBoundedRefreshToken(parsed?.refresh_token) ? parsed.refresh_token : null;
      if (!accessToken && !refreshToken) return { complete: false, session: null };
      return {
        complete: markerClear,
        session: { accessToken, refreshToken }
      };
    } catch {
      return { complete: false, session: null };
    }
  }

  function readLegacySessions(options = {}) {
    const sessions = [];
    let complete = true;
    for (const access of storageAccesses) {
      const result = readLegacySession(access, options);
      complete &&= result.complete;
      const session = result.session;
      if (!session || sessions.some(existing =>
        existing.accessToken === session.accessToken && existing.refreshToken === session.refreshToken
      )) continue;
      sessions.push(session);
    }
    return { sessions, complete };
  }

  async function authRequest(url, options) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      return await fetch(url, {
        ...options,
        credentials: "omit",
        cache: "no-store",
        redirect: "error",
        referrerPolicy: "no-referrer",
        signal: controller.signal
      });
    } finally {
      clearTimeout(timeout);
    }
  }

  async function refreshLegacyAccessToken(config, refreshToken) {
    if (!refreshToken) return { status: "absent", accessToken: null };
    const response = await authRequest(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ refresh_token: refreshToken })
    });
    if ([400, 401].includes(response.status)) {
      return { status: "invalid", accessToken: null };
    }
    if (!response.ok) return { status: "failed", accessToken: null };
    const text = await readBoundedResponseText(response, MAX_SESSION_BYTES);
    if (!text) {
      return { status: "failed", accessToken: null };
    }
    const accessToken = JSON.parse(text)?.access_token;
    return isBoundedAccessToken(accessToken)
      ? { status: "refreshed", accessToken }
      : { status: "failed", accessToken: null };
  }

  async function readBoundedResponseText(response, maxBytes) {
    const advertisedLength = response.headers.get("Content-Length");
    if (advertisedLength !== null && /^\d+$/.test(advertisedLength.trim()) &&
        Number(advertisedLength) > maxBytes) {
      await response.body?.cancel().catch(() => {});
      throw new Error("Response exceeds the cleanup limit.");
    }
    if (!response.body || typeof response.body.getReader !== "function") {
      throw new Error("Bounded response streaming is unavailable.");
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: true });
    const chunks = [];
    let byteLength = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        byteLength += value.byteLength;
        if (byteLength > maxBytes || chunks.length >= MAX_RESPONSE_CHUNKS) {
          await reader.cancel().catch(() => {});
          throw new Error("Response exceeds the cleanup limit.");
        }
        chunks.push(decoder.decode(value, { stream: true }));
      }
    } finally {
      reader.releaseLock();
    }
    chunks.push(decoder.decode());
    return chunks.join("");
  }

  async function postLocalLogout(config, accessToken) {
    return authRequest(`${config.url}/auth/v1/logout?scope=local`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json"
      }
    });
  }

  async function revokeLegacySession(session) {
    const config = window.GYM_SUPABASE || {};
    if (!session || config.url !== "https://owrcbsrectdgaotndtxy.supabase.co" ||
        typeof config.anonKey !== "string" || config.anonKey.length < 8 || config.anonKey.length > 4096) {
      return false;
    }
    try {
      let accessConfirmed = !session.accessToken;
      if (session.accessToken) {
        const logoutResponse = await postLocalLogout(config, session.accessToken);
        if (!logoutResponse.ok && logoutResponse.status !== 401) return false;
        accessConfirmed = true;
      }
      if (!session.refreshToken) return accessConfirmed;
      const refreshed = await refreshLegacyAccessToken(config, session.refreshToken);
      if (refreshed.status === "invalid") return accessConfirmed;
      if (refreshed.status !== "refreshed" || !refreshed.accessToken) return false;
      return accessConfirmed && (await postLocalLogout(config, refreshed.accessToken)).ok;
    } catch {
      return false;
    }
  }

  function eraseCredentials() {
    let verified = true;
    for (const access of storageAccesses) {
      if (!access.available) {
        verified = false;
        continue;
      }
      for (const key of CREDENTIAL_KEYS) {
        try {
          access.storage.removeItem(key);
          if (access.storage.getItem(key) !== null) verified = false;
        } catch {
          verified = false;
        }
      }
    }
    return verified;
  }

  function prepareRevocationTracking(required) {
    if (!required) return true;
    let verified = true;
    for (const access of storageAccesses) {
      if (!access.available) {
        verified = false;
        continue;
      }
      try {
        access.storage.setItem(SESSION_REVOCATION_MARKER_KEY, "1");
        if (access.storage.getItem(SESSION_REVOCATION_MARKER_KEY) !== "1") verified = false;
      } catch {
        verified = false;
      }
    }
    return verified;
  }

  function clearRevocationTracking() {
    let verified = true;
    for (const access of storageAccesses) {
      if (!access.available) {
        verified = false;
        continue;
      }
      try {
        access.storage.removeItem(SESSION_REVOCATION_MARKER_KEY);
        if (access.storage.getItem(SESSION_REVOCATION_MARKER_KEY) !== null) verified = false;
      } catch {
        verified = false;
      }
    }
    return verified;
  }

  async function removeLegacyCacheEntries(cacheApi) {
    if (typeof cacheApi.open !== "function") return false;
    const names = await cacheApi.keys();
    if (!Array.isArray(names) || names.length > MAX_RUNTIME_ITEMS) return false;
    let requestCount = 0;
    for (const name of names.filter(key => key.startsWith(OWNED_STORAGE_PREFIX))) {
      const cache = await cacheApi.open(name);
      if (!cache || typeof cache.keys !== "function" || typeof cache.delete !== "function") {
        return false;
      }
      const requests = await cache.keys();
      if (!Array.isArray(requests)) return false;
      const matchingRequests = requests.filter(request => isWithinLegacyScope(request?.url));
      requestCount += matchingRequests.length;
      if (requestCount > MAX_RUNTIME_ITEMS) return false;
      const results = await Promise.all(
        matchingRequests.map(request => cache.delete(request))
      );
      if (!results.every(result => result === true)) return false;
    }
    return true;
  }

  async function removeLegacyRuntime() {
    let cachesRemoved = true;
    let cacheApi = null;
    try {
      cacheApi = window.caches || null;
    } catch {
      cachesRemoved = false;
    }
    if (cacheApi) {
      try {
        cachesRemoved = await removeLegacyCacheEntries(cacheApi);
      } catch {
        cachesRemoved = false;
      }
    }
    let workerRemoved = true;
    let serviceWorker = null;
    try {
      serviceWorker = window.navigator?.serviceWorker || null;
    } catch {
      workerRemoved = false;
    }
    if (serviceWorker) {
      try {
        const registrations = await serviceWorker.getRegistrations();
        if (!Array.isArray(registrations) || registrations.length > MAX_RUNTIME_ITEMS) return false;
        const results = await Promise.all(
          registrations
            .filter(registration => registration.scope === LEGACY_SERVICE_WORKER_SCOPE)
            .map(registration => registration.unregister())
        );
        workerRemoved = results.every(result => result === true);
      } catch {
        workerRemoved = false;
      }
    }
    return cachesRemoved && workerRemoved;
  }

  function isBackupDataKey(key) {
    return BACKUP_DATA_KEYS.has(key) || key.startsWith(ACCOUNT_STATE_PREFIX);
  }

  function inspectOwnedStorage() {
    const ownedEntries = [];
    const backupEntries = [];
    let complete = true;
    let totalBytes = 0;
    for (const access of storageAccesses) {
      if (!access.available) {
        complete = false;
        continue;
      }
      let length = 0;
      try {
        length = access.storage.length;
      } catch {
        complete = false;
        continue;
      }
      if (!Number.isSafeInteger(length) || length < 0 || length > MAX_STORAGE_KEYS) {
        complete = false;
      }
      const scanLength = Number.isSafeInteger(length) && length > 0
        ? Math.min(length, MAX_STORAGE_KEYS)
        : 0;
      for (let index = 0; index < scanLength; index += 1) {
        let key;
        let value;
        try {
          key = access.storage.key(index);
          if (typeof key !== "string" || !key.startsWith(OWNED_STORAGE_PREFIX)) continue;
          if (key.length > MAX_STORAGE_KEY_LENGTH) {
            complete = false;
            continue;
          }
          value = access.storage.getItem(key);
        } catch {
          complete = false;
          continue;
        }
        if (typeof value !== "string") {
          complete = false;
          continue;
        }
        const valueBytes = new TextEncoder().encode(value).byteLength;
        totalBytes += valueBytes;
        if (valueBytes > MAX_OWNED_VALUE_BYTES || totalBytes > MAX_OWNED_VALUE_BYTES ||
            ownedEntries.length >= MAX_OWNED_ENTRIES) {
          complete = false;
          continue;
        }
        const entry = { storage: access.name, key, value };
        ownedEntries.push(entry);
        if (isBackupDataKey(key)) backupEntries.push(entry);
      }
    }
    ownedEntries.sort((left, right) =>
      `${left.storage}:${left.key}`.localeCompare(`${right.storage}:${right.key}`)
    );
    backupEntries.sort((left, right) =>
      `${left.storage}:${left.key}`.localeCompare(`${right.storage}:${right.key}`)
    );
    return { complete, ownedEntries, backupEntries, totalBytes };
  }

  function snapshotsEqual(left, right) {
    if (!left || !right || left.complete !== right.complete ||
        left.ownedEntries.length !== right.ownedEntries.length) return false;
    return left.ownedEntries.every((entry, index) => {
      const other = right.ownedEntries[index];
      return entry.storage === other.storage && entry.key === other.key && entry.value === other.value;
    });
  }

  function showPrivateDataActions(inspection) {
    privateSnapshot = inspection;
    backupDownloaded = inspection.backupEntries.length === 0;
    if (dataSummary) {
      dataSummary.textContent = inspection.backupEntries.length
        ? `${inspection.backupEntries.length} private workout/account storage item(s) remain on this shared legacy origin. Download the offline recovery archive before removing them; the archive wrapper is not a direct GymApp import.`
        : "Only obsolete GymApp runtime metadata remains on this shared legacy origin. Confirm its removal to finish.";
      dataSummary.hidden = false;
    }
    if (backupButton) backupButton.hidden = inspection.backupEntries.length === 0;
    if (purgeButton) {
      purgeButton.hidden = false;
      purgeButton.disabled = !backupDownloaded;
    }
    setActions();
    setStatus("Stored credentials were removed and refresh-session revocation was confirmed. Finish the explicit private-data cleanup below.");
  }

  function finishWithoutPrivateData() {
    privateSnapshot = null;
    backupDownloaded = false;
    hideDataActions();
    setStatus("Stored credentials, GymApp caches, and the legacy service worker were removed. Any previously issued access token expires on its original short lifetime.");
    setActions({ canContinue: true });
  }

  function restartForRecreatedCredentials() {
    if (!coreCleanupComplete) return;
    coreCleanupComplete = false;
    pendingSessions = null;
    sessionReadComplete = false;
    privateSnapshot = null;
    backupDownloaded = false;
    setActions();
    hideDataActions();
    startCleanup();
  }

  async function continueSafely(event) {
    event.preventDefault();
    if (continuationRunning) return;
    const boundary = readLegacySessions();
    if (!coreCleanupComplete || !boundary.complete || boundary.sessions.length > 0) {
      restartForRecreatedCredentials();
      return;
    }
    const owned = inspectOwnedStorage();
    if (!owned.complete || owned.ownedEntries.length > 0) {
      preparePrivateDataActions();
      return;
    }
    continuationRunning = true;
    setActions();
    setStatus("Running final legacy-origin verification…");
    try {
      const runtimeRemoved = await removeLegacyRuntime();
      const finalBoundary = readLegacySessions();
      const finalOwned = inspectOwnedStorage();
      if (!runtimeRemoved || !coreCleanupComplete || !finalBoundary.complete ||
          finalBoundary.sessions.length > 0 || !finalOwned.complete ||
          finalOwned.ownedEntries.length > 0) {
        if (!finalBoundary.complete || finalBoundary.sessions.length > 0) {
          restartForRecreatedCredentials();
        } else if (!finalOwned.complete || finalOwned.ownedEntries.length > 0) {
          preparePrivateDataActions();
        } else {
          setStatus("Final cache or service-worker verification failed. Retry before continuing.");
          setActions({ canContinue: true, canRetry: true });
        }
        return;
      }
      window.location.assign(PUBLIC_SITE_URL);
    } catch {
      setStatus("Final legacy-origin verification failed. Retry before continuing.");
      setActions({ canContinue: true, canRetry: true });
    } finally {
      continuationRunning = false;
    }
  }

  function preparePrivateDataActions() {
    const inspection = inspectOwnedStorage();
    if (!inspection.complete) {
      setStatus("Credential cleanup completed, but the remaining legacy GymApp storage could not be safely enumerated. Keep this page open and remove this site's data manually.");
      setActions({ canRetry: true });
      return;
    }
    if (inspection.ownedEntries.length === 0) {
      finishWithoutPrivateData();
      return;
    }
    showPrivateDataActions(inspection);
  }

  function downloadPrivateBackup() {
    if (!coreCleanupComplete) return;
    const current = inspectOwnedStorage();
    if (!current.complete || current.backupEntries.length === 0) {
      setStatus("A bounded private backup could not be prepared. No workout data was deleted.");
      return;
    }
    const archive = {
      schemaVersion: 1,
      app: "GymApp",
      source: "legacy-origin-browser-storage",
      exportedAt: new Date().toISOString(),
      origin: LEGACY_ORIGIN,
      warning: "Private workout/account offline recovery archive. Keep it offline and do not share it. The wrapper itself is not accepted by GymApp Import JSON.",
      recoveryInstructions: [
        "Choose the gym-pwa-state-v2 or gym-pwa-account:* entry for the profile you need.",
        "Parse that entry's value as JSON and import that inner JSON value in GymApp on gymapptracker.com.",
        "A gym-pwa-garmin-enqueue-requests-v1 entry is retained only as private offline reference for a pending watch plan; do not import it directly.",
        "Do not import credential, Garmin pairing, or other runtime metadata; those fields are intentionally excluded."
      ],
      excluded: [
        REMOTE_SESSION_KEY,
        LEGACY_GARMIN_TOKEN_KEY,
        GARMIN_DEVICE_BINDINGS_KEY
      ],
      entries: current.backupEntries
    };
    let encoded;
    try {
      encoded = JSON.stringify(archive, null, 2);
      if (new TextEncoder().encode(encoded).byteLength > MAX_ARCHIVE_BYTES ||
          typeof Blob !== "function" || typeof URL.createObjectURL !== "function") {
        throw new Error("Backup is unavailable.");
      }
      const blobUrl = URL.createObjectURL(new Blob([encoded], { type: "application/json" }));
      const link = document.createElement("a");
      link.href = blobUrl;
      link.download = `gymapp-legacy-private-backup-${new Date().toISOString().slice(0, 10)}.json`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(blobUrl), 0);
    } catch {
      setStatus("The private backup download could not be started. No workout data was deleted.");
      return;
    }
    privateSnapshot = current;
    backupDownloaded = true;
    if (purgeButton) purgeButton.disabled = false;
    setStatus("Private backup download started. Verify that the file was saved, then explicitly remove the old-origin data.");
  }

  function purgePrivateData() {
    if (!coreCleanupComplete || !privateSnapshot) return;
    const current = inspectOwnedStorage();
    if (!current.complete) {
      setStatus("The old-origin storage changed or became unavailable. No additional data was deleted.");
      return;
    }
    if (!snapshotsEqual(privateSnapshot, current)) {
      privateSnapshot = current;
      backupDownloaded = current.backupEntries.length === 0;
      if (backupButton) backupButton.hidden = current.backupEntries.length === 0;
      if (purgeButton) purgeButton.disabled = !backupDownloaded;
      setStatus("Legacy GymApp data changed in another tab. Download a fresh backup before removal.");
      return;
    }
    if (current.backupEntries.length > 0 && !backupDownloaded) {
      setStatus("Download the private backup before removing old-origin workout/account data.");
      return;
    }
    const confirmation = "Permanently remove all GymApp data from this old browser address? Confirm only after the private backup file is saved. This cannot be undone.";
    if (typeof window.confirm !== "function" || !window.confirm(confirmation)) return;
    const afterConfirmation = inspectOwnedStorage();
    if (!afterConfirmation.complete || !snapshotsEqual(privateSnapshot, afterConfirmation)) {
      privateSnapshot = afterConfirmation.complete ? afterConfirmation : null;
      backupDownloaded = afterConfirmation.complete && afterConfirmation.backupEntries.length === 0;
      if (backupButton) {
        backupButton.hidden = !afterConfirmation.complete || afterConfirmation.backupEntries.length === 0;
      }
      if (purgeButton) purgeButton.disabled = !backupDownloaded;
      setStatus("Legacy GymApp data changed while confirmation was open. Download a fresh backup before removal.");
      return;
    }
    let removed = true;
    const byName = new Map(storageAccesses.map(access => [access.name, access]));
    for (const entry of afterConfirmation.ownedEntries) {
      const access = byName.get(entry.storage);
      if (!access?.available) {
        removed = false;
        continue;
      }
      try {
        access.storage.removeItem(entry.key);
        if (access.storage.getItem(entry.key) !== null) removed = false;
      } catch {
        removed = false;
      }
    }
    const remaining = inspectOwnedStorage();
    if (!removed || !remaining.complete || remaining.ownedEntries.length !== 0) {
      privateSnapshot = remaining.complete ? remaining : null;
      backupDownloaded = remaining.complete && remaining.backupEntries.length === 0;
      if (backupButton) {
        backupButton.hidden = !remaining.complete || remaining.backupEntries.length === 0;
      }
      if (purgeButton) {
        purgeButton.hidden = false;
        purgeButton.disabled = !backupDownloaded;
      }
      setStatus("Some legacy GymApp data could not be removed or was recreated. Keep this page open and retry after closing other old GymApp tabs.");
      if (!remaining.complete) setActions({ canRetry: true });
      return;
    }
    if (dataSummary) {
      dataSummary.textContent = "All GymApp-owned browser storage was removed from the shared legacy origin.";
      dataSummary.hidden = false;
    }
    if (backupButton) backupButton.hidden = true;
    if (purgeButton) purgeButton.hidden = true;
    finishWithoutPrivateData();
  }

  async function run() {
    if (window.__GYMAPP_TOP_LEVEL__ !== true || window.top !== window.self) return;
    if (window.location.origin !== LEGACY_ORIGIN ||
        !LEGACY_CLEANUP_PATHS.has(window.location.pathname) ||
        window.location.search !== "" || window.location.hash !== "") {
      setStatus("No legacy-origin cleanup is required on this site.");
      return;
    }
    if (pendingSessions === null) {
      const snapshot = readLegacySessions();
      pendingSessions = snapshot.sessions;
      sessionReadComplete = snapshot.complete;
    }
    const sessions = pendingSessions;
    const revocationTracked = prepareRevocationTracking(sessions.length > 0 || !sessionReadComplete);
    let credentialsRemoved = eraseCredentials();
    const [revocationResults, runtimeRemoved] = await Promise.all([
      Promise.all(sessions.map(revokeLegacySession)),
      removeLegacyRuntime()
    ]);
    pendingSessions = sessions.filter((_session, index) => !revocationResults[index]);
    let serverRevocationComplete = revocationTracked && sessionReadComplete &&
      pendingSessions.length === 0;
    if (serverRevocationComplete) {
      let stable = false;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        const observed = readLegacySessions({ ignoreMarker: true });
        if (!observed.complete) break;
        if (observed.sessions.length === 0) {
          stable = true;
          break;
        }
        stable = false;
        credentialsRemoved = eraseCredentials() && credentialsRemoved;
        const observedResults = await Promise.all(observed.sessions.map(revokeLegacySession));
        pendingSessions = observed.sessions.filter((_session, index) => !observedResults[index]);
        if (pendingSessions.length > 0) break;
      }
      serverRevocationComplete = stable && pendingSessions.length === 0;
    }
    if (serverRevocationComplete) {
      serverRevocationComplete = clearRevocationTracking();
      const afterClear = readLegacySessions({ ignoreMarker: true });
      if (!afterClear.complete || afterClear.sessions.length > 0) {
        prepareRevocationTracking(true);
        credentialsRemoved = eraseCredentials() && credentialsRemoved;
        pendingSessions = afterClear.sessions;
        serverRevocationComplete = false;
      }
    }
    if (credentialsRemoved && runtimeRemoved && serverRevocationComplete) {
      coreCleanupComplete = true;
      preparePrivateDataActions();
    } else if (credentialsRemoved && runtimeRemoved) {
      setStatus("Stored credentials, caches, and service worker were removed. Refresh-session revocation could not be confirmed; an administrator must review outstanding legacy sessions.");
      setActions({ canRetry: true });
    } else {
      setStatus("Legacy cleanup could not be fully verified. Do not restore the custom-domain redirect until site data and this GymApp service worker are removed manually.");
      setActions({ canRetry: true });
    }
  }

  function startCleanup() {
    if (cleanupRunning) return;
    cleanupRunning = true;
    coreCleanupComplete = false;
    setActions();
    hideDataActions();
    setStatus("Preparing secure cleanup…");
    run().catch(() => {
      prepareRevocationTracking(true);
      const credentialsRemoved = eraseCredentials();
      setStatus(credentialsRemoved
        ? "Local legacy credentials were removed, but runtime cleanup could not be fully verified."
        : "Legacy credential and runtime cleanup could not be fully verified; remove this site's data manually.");
      setActions({ canRetry: true });
    }).finally(() => {
      cleanupRunning = false;
    });
  }

  retryButton?.addEventListener("click", startCleanup);
  backupButton?.addEventListener("click", downloadPrivateBackup);
  purgeButton?.addEventListener("click", purgePrivateData);
  continueLink?.addEventListener?.("click", continueSafely);
  window.addEventListener?.("storage", event => {
    if (event?.key === REMOTE_SESSION_KEY || event?.key === SESSION_REVOCATION_MARKER_KEY) {
      restartForRecreatedCredentials();
    } else if (coreCleanupComplete && typeof event?.key === "string" &&
        event.key.startsWith(OWNED_STORAGE_PREFIX)) {
      preparePrivateDataActions();
    }
  });
  startCleanup();
})();
