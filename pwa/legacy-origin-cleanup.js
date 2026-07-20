"use strict";

(() => {
  const LEGACY_ORIGIN = "https://eduard047.github.io";
  const LEGACY_PATH_PREFIX = "/GymApp/";
  const LEGACY_CLEANUP_PATH = `${LEGACY_PATH_PREFIX}legacy-origin-cleanup.html`;
  const LEGACY_SERVICE_WORKER_SCOPE = `${LEGACY_ORIGIN}${LEGACY_PATH_PREFIX}`;
  const REMOTE_SESSION_KEY = "gym-pwa-supabase-session-v1";
  const AUTH_KEY = "gym-pwa-active-account-v1";
  const LEGACY_GARMIN_TOKEN_KEY = "gym-pwa-garmin-device-token-v1";
  const MAX_SESSION_BYTES = 64 * 1024;
  const status = document.querySelector("#cleanup-status");

  const setStatus = message => {
    if (status) status.textContent = message;
  };

  function isBoundedToken(value) {
    return typeof value === "string" && value.length >= 16 && value.length <= 16384;
  }

  function readLegacySession() {
    try {
      const raw = localStorage.getItem(REMOTE_SESSION_KEY);
      if (!raw || new TextEncoder().encode(raw).byteLength > MAX_SESSION_BYTES) return null;
      const parsed = JSON.parse(raw);
      const accessToken = isBoundedToken(parsed?.access_token) ? parsed.access_token : null;
      const refreshToken = isBoundedToken(parsed?.refresh_token) ? parsed.refresh_token : null;
      return accessToken || refreshToken ? { accessToken, refreshToken } : null;
    } catch {
      return null;
    }
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
    if (!refreshToken) return null;
    const response = await authRequest(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: {
        apikey: config.anonKey,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ refresh_token: refreshToken })
    });
    if (!response.ok) return null;
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_SESSION_BYTES) return null;
    const accessToken = JSON.parse(text)?.access_token;
    return isBoundedToken(accessToken) ? accessToken : null;
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
      if (session.accessToken) {
        const logoutResponse = await postLocalLogout(config, session.accessToken);
        if (logoutResponse.ok) return true;
        if (logoutResponse.status !== 401) return false;
      }
      const refreshedAccessToken = await refreshLegacyAccessToken(config, session.refreshToken);
      if (!refreshedAccessToken) return false;
      return (await postLocalLogout(config, refreshedAccessToken)).ok;
    } catch {
      return false;
    }
  }

  function eraseCredentials() {
    let verified = true;
    for (const storage of [localStorage, sessionStorage]) {
      for (const key of [REMOTE_SESSION_KEY, AUTH_KEY, LEGACY_GARMIN_TOKEN_KEY]) {
        try {
          storage.removeItem(key);
          if (storage.getItem(key) !== null) verified = false;
        } catch {
          verified = false;
        }
      }
    }
    return verified;
  }

  async function removeLegacyRuntime() {
    let cachesRemoved = true;
    if ("caches" in window) {
      try {
        const keys = await caches.keys();
        const results = await Promise.all(
          keys.filter(key => key.startsWith("gym-pwa-")).map(key => caches.delete(key))
        );
        cachesRemoved = results.every(result => result === true);
      } catch {
        cachesRemoved = false;
      }
    }
    let workerRemoved = true;
    if ("serviceWorker" in navigator) {
      try {
        const registrations = await navigator.serviceWorker.getRegistrations();
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

  async function run() {
    if (window.__GYMAPP_TOP_LEVEL__ !== true || window.top !== window.self) return;
    if (window.location.origin !== LEGACY_ORIGIN ||
        window.location.pathname !== LEGACY_CLEANUP_PATH ||
        window.location.search !== "" || window.location.hash !== "") {
      setStatus("No legacy-origin cleanup is required on this site.");
      return;
    }
    const session = readLegacySession();
    const credentialsRemoved = eraseCredentials();
    const [revoked, runtimeRemoved] = await Promise.all([
      revokeLegacySession(session),
      removeLegacyRuntime()
    ]);
    const serverRevocationComplete = revoked || !session;
    if (credentialsRemoved && runtimeRemoved && serverRevocationComplete) {
      setStatus("Legacy credentials, caches, and service worker were removed and verified.");
    } else if (credentialsRemoved && runtimeRemoved) {
      setStatus("Local credentials, caches, and service worker were removed. Server revocation could not be confirmed; an administrator must revoke outstanding legacy sessions.");
    } else {
      setStatus("Legacy cleanup could not be fully verified. Do not restore the custom-domain redirect until site data and this GymApp service worker are removed manually.");
    }
  }

  run().catch(() => {
    const credentialsRemoved = eraseCredentials();
    setStatus(credentialsRemoved
      ? "Local legacy credentials were removed, but runtime cleanup could not be fully verified."
      : "Legacy credential and runtime cleanup could not be fully verified; remove this site's data manually.");
  });
})();
