"use strict";

if (window.__GYMAPP_TOP_LEVEL__ !== true || window.top !== window.self) {
  throw new DOMException("GymApp confirmation must run in a top-level browsing context.", "SecurityError");
}

const PUBLIC_SITE_URL = "https://gymapptracker.com/";
const ANDROID_AUTH_CALLBACK_URLS = Object.freeze({
  production: "com.setforge.gymapp://auth/callback",
  qa: "com.setforge.gymapp.dev://auth/callback"
});
const IOS_AUTH_CALLBACK_URL = "com.setforge.gymapp.ios://auth/callback";
const AUTH_STATE_PATTERN = /^[A-Za-z0-9_-]{32}$/;
const AUTH_CODE_PATTERN = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
const WEB_AUTH_TRANSACTION_KEY = "gym-pwa-auth-transaction-v1";
const WEB_AUTH_TRANSACTION_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const button = document.querySelector("#open-app");
const title = document.querySelector("#confirmation-title");
const message = document.querySelector("#confirmation-message");
const rawSearch = window.location.search.replace(/^\?/, "");
const rawHash = window.location.hash.replace(/^#/, "");
const BRIDGE_PARAMETER_MAX_LENGTH = 8192;
const BRIDGE_PARAMETER_MAX_PAIRS = 32;
if (rawSearch.length > BRIDGE_PARAMETER_MAX_LENGTH || rawHash.length > BRIDGE_PARAMETER_MAX_LENGTH ||
    (rawSearch && rawSearch.split("&").length > BRIDGE_PARAMETER_MAX_PAIRS) ||
    (rawHash && rawHash.split("&").length > BRIDGE_PARAMETER_MAX_PAIRS)) {
  window.history.replaceState(null, "", window.location.pathname);
}
const BRIDGE_QUERY_KEYS = new Set([
  "platform",
  "variant",
  "state",
  "purpose",
  "code",
  "error",
  "error_description",
  "error_code"
]);

function setContent(nextTitle, nextMessage, buttonText, href) {
  if (title) title.textContent = nextTitle;
  if (message) message.textContent = nextMessage;
  if (button) {
    button.textContent = buttonText;
    button.setAttribute("href", href);
  }
}

function isSafeValue(value, maxLength) {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= maxLength &&
    !/[\u0000-\u001F\u007F]/.test(value);
}

function decodeQueryComponent(value) {
  return decodeURIComponent(value.replace(/\+/g, " "));
}

function parseBridgeParameters(rawValue) {
  const values = new Map();
  let malformed = rawValue.length > BRIDGE_PARAMETER_MAX_LENGTH ||
    (rawValue && rawValue.split("&").length > BRIDGE_PARAMETER_MAX_PAIRS);
  let tokenLike = false;

  if (malformed) return { malformed, tokenLike, getAll: () => [] };

  for (const pair of rawValue.split("&").filter(Boolean)) {
    const separator = pair.indexOf("=");
    const rawKey = separator >= 0 ? pair.slice(0, separator) : pair;
    const rawValue = separator >= 0 ? pair.slice(separator + 1) : "";
    let key;
    try {
      key = decodeQueryComponent(rawKey);
    } catch {
      malformed = true;
      continue;
    }

    if (key.toLowerCase().includes("token")) {
      tokenLike = true;
      continue;
    }
    if (!BRIDGE_QUERY_KEYS.has(key)) continue;

    try {
      const entries = values.get(key) || [];
      entries.push(decodeQueryComponent(rawValue));
      values.set(key, entries);
    } catch {
      malformed = true;
    }
  }

  return {
    malformed,
    tokenLike,
    getAll(key) {
      return values.get(key) || [];
    }
  };
}

const bridgeQuery = parseBridgeParameters(rawSearch);
const bridgeFragment = parseBridgeParameters(rawHash);

function loadWebAuthTransaction() {
  try {
    const raw = window.localStorage?.getItem(WEB_AUTH_TRANSACTION_KEY);
    if (!raw || new TextEncoder().encode(raw).byteLength > 4096) {
      window.localStorage?.removeItem(WEB_AUTH_TRANSACTION_KEY);
      return null;
    }
    const value = JSON.parse(raw);
    if (!value || typeof value !== "object" || Array.isArray(value) || value.version !== 1 ||
        !["signup", "recovery"].includes(value.purpose) ||
        !AUTH_STATE_PATTERN.test(value.state || "") ||
        !/^[A-Za-z0-9_-]{43,128}$/.test(value.verifier || "") ||
        typeof value.email !== "string" || value.email.length > 254 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.email) ||
        !Number.isSafeInteger(value.createdAt) || value.createdAt > Date.now() + 60_000 ||
        Date.now() - value.createdAt > WEB_AUTH_TRANSACTION_MAX_AGE_MS) {
      window.localStorage?.removeItem(WEB_AUTH_TRANSACTION_KEY);
      return null;
    }
    return value;
  } catch {
    return null;
  }
}

function configureIOSBridge() {
  const platforms = bridgeQuery.getAll("platform");
  const variants = bridgeQuery.getAll("variant");
  const states = bridgeQuery.getAll("state");
  const purposes = bridgeQuery.getAll("purpose");
  const codes = bridgeQuery.getAll("code");
  const errors = bridgeQuery.getAll("error");
  const descriptions = bridgeQuery.getAll("error_description");
  const state = states[0] || "";
  const purpose = purposes[0] || "signup";
  const hasCode = codes.length === 1 && isSafeValue(codes[0], 2048);
  const hasError = errors.length === 1 && isSafeValue(errors[0], 128);
  const hasDescription = descriptions.length === 1 && isSafeValue(descriptions[0], 1024);
  const invalid = platforms.length !== 1 || platforms[0] !== "ios" ||
    variants.length !== 0 ||
    states.length !== 1 || !AUTH_STATE_PATTERN.test(state) ||
    purposes.length > 1 || !["signup", "recovery"].includes(purpose) ||
    rawHash.length > 0 || bridgeQuery.malformed || bridgeQuery.tokenLike ||
    codes.length > 1 || errors.length > 1 || descriptions.length > 1 ||
    hasCode === hasError || (descriptions.length > 0 && !hasError) ||
    (codes.length === 1 && !hasCode) || (errors.length === 1 && !hasError) ||
    (descriptions.length === 1 && !hasDescription);

  if (invalid) {
    setContent(
      "Confirmation link unavailable",
      "This iOS confirmation link is invalid or uses an unsupported authentication flow.",
      "Return to GymApp website",
      PUBLIC_SITE_URL
    );
    return false;
  }

  const appUrl = new URL(`${IOS_AUTH_CALLBACK_URL}/${state}`);
  if (hasCode) {
    appUrl.searchParams.set("code", codes[0]);
    if (purpose === "recovery") {
      setContent(
        "Password reset verified",
        "GymApp is opening so you can choose a new password. If it does not open, tap the button below.",
        "Open GymApp to reset password",
        appUrl.toString()
      );
    } else {
      setContent(
        "Email confirmed",
        "GymApp is opening to finish the secure sign-in. If it does not open, tap the button below.",
        "Open GymApp for iOS",
        appUrl.toString()
      );
    }
    try {
      window.location.assign(appUrl.toString());
    } catch {
      // Some in-app browsers block custom schemes. The visible button remains the fallback.
    }
    return true;
  }

  appUrl.searchParams.set("error", errors[0]);
  if (hasDescription) appUrl.searchParams.set("error_description", descriptions[0]);
  if (purpose === "recovery") {
    setContent(
      "Password reset could not be verified",
      "Open GymApp to review the error, then request a new password reset email.",
      "Return to GymApp for iOS",
      appUrl.toString()
    );
  } else {
    setContent(
      "Confirmation could not be completed",
      "Open GymApp to review the authentication error and try again.",
      "Return to GymApp for iOS",
      appUrl.toString()
    );
  }
  try {
    window.location.assign(appUrl.toString());
  } catch {
    // Keep the manual fallback available when automatic launch is unavailable.
  }
  return true;
}

function configureAndroidBridge() {
  const platforms = bridgeQuery.getAll("platform");
  const variants = bridgeQuery.getAll("variant");
  const states = bridgeQuery.getAll("state");
  const purposes = bridgeQuery.getAll("purpose");
  const codes = bridgeQuery.getAll("code");
  const errors = bridgeQuery.getAll("error");
  const descriptions = bridgeQuery.getAll("error_description");
  const isPKCECallback = variants.length > 0 || purposes.length > 0 || states.length > 0 ||
    codes.length > 0 || errors.length > 0 || descriptions.length > 0;

  if (isPKCECallback) {
    const state = states[0] || "";
    const purpose = purposes[0] || "";
    const hasCode = codes.length === 1 && AUTH_CODE_PATTERN.test(codes[0]);
    const hasError = errors.length === 1 && isSafeValue(errors[0], 128);
    const hasDescription = descriptions.length === 1 && isSafeValue(descriptions[0], 1024);
    const invalid = platforms.length !== 1 || platforms[0] !== "android" ||
      variants.length > 1 || (variants.length === 1 && variants[0] !== "qa") ||
      states.length !== 1 || !AUTH_STATE_PATTERN.test(state) ||
      purposes.length !== 1 || !["signup", "recovery"].includes(purpose) ||
      rawHash.length > 0 || bridgeQuery.malformed || bridgeQuery.tokenLike ||
      codes.length > 1 || errors.length > 1 || descriptions.length > 1 ||
      hasCode === hasError || (descriptions.length > 0 && !hasError) ||
      (codes.length === 1 && !hasCode) || (errors.length === 1 && !hasError) ||
      (descriptions.length === 1 && !hasDescription);
    if (invalid) {
      setContent(
        "Confirmation link unavailable",
        "This Android confirmation link is invalid or uses an unsupported authentication flow.",
        "Return to GymApp website",
        PUBLIC_SITE_URL
      );
      return false;
    }

    const callbackUrl = variants[0] === "qa"
      ? ANDROID_AUTH_CALLBACK_URLS.qa
      : ANDROID_AUTH_CALLBACK_URLS.production;
    const appUrl = new URL(callbackUrl);
    appUrl.searchParams.set("state", state);
    appUrl.searchParams.set("purpose", purpose);
    if (hasCode) {
      appUrl.searchParams.set("code", codes[0]);
      if (purpose === "recovery") {
        setContent(
          "Password reset verified",
          "Tap below to return to GymApp and choose a new password.",
          "Open GymApp to reset password",
          appUrl.toString()
        );
      } else {
        setContent(
          "Email confirmed",
          "Tap below to finish the secure sign-in on the Android device where registration started.",
          "Open GymApp",
          appUrl.toString()
        );
      }
    } else {
      appUrl.searchParams.set("error", errors[0]);
      if (hasDescription) appUrl.searchParams.set("error_description", descriptions[0]);
      if (purpose === "recovery") {
        setContent(
          "Password reset could not be verified",
          "Open GymApp to review the error, then request a new password reset email.",
          "Return to GymApp",
          appUrl.toString()
        );
      } else {
        setContent(
          "Confirmation could not be completed",
          "Open GymApp to review the error, then request a new confirmation email.",
          "Return to GymApp",
          appUrl.toString()
        );
      }
    }
    // Keep the HTTPS page as a user-action boundary. The custom scheme opens only
    // after the person taps the visible button, not when an email scanner loads it.
    return true;
  }

  setContent(
    "Confirmation link unavailable",
    "Request a new confirmation or password reset email from the latest GymApp version.",
    "Return to GymApp website",
    PUBLIC_SITE_URL
  );
  return false;
}

function configureWebReturn() {
  const platforms = bridgeQuery.getAll("platform");
  const variants = bridgeQuery.getAll("variant");
  const states = bridgeQuery.getAll("state");
  const purposes = bridgeQuery.getAll("purpose");
  const codes = bridgeQuery.getAll("code");
  const errors = [...bridgeQuery.getAll("error"), ...bridgeFragment.getAll("error")];
  const descriptions = [...bridgeQuery.getAll("error_description"), ...bridgeFragment.getAll("error_description")];
  const errorCodes = [...bridgeQuery.getAll("error_code"), ...bridgeFragment.getAll("error_code")];
  const hasError = errors.length === 1 && isSafeValue(errors[0], 128);
  const hasDescription = descriptions.length === 1 && isSafeValue(descriptions[0], 1024);
  const hasErrorCode = errorCodes.length === 1 && isSafeValue(errorCodes[0], 128);
  const storedTransaction = loadWebAuthTransaction();
  const callbackMalformed = platforms.length !== 1 || platforms[0] !== "web" ||
    variants.length > 0 || bridgeQuery.malformed || bridgeQuery.tokenLike ||
    bridgeFragment.malformed || bridgeFragment.tokenLike ||
    states.length > 0 || purposes.length > 0 || codes.length > 1 ||
    errors.length > 1 || descriptions.length > 1 || errorCodes.length > 1 ||
    (errors.length === 1 && !hasError) || (descriptions.length > 0 && !hasDescription) ||
    (errorCodes.length > 0 && !hasErrorCode) ||
    ((descriptions.length > 0 || errorCodes.length > 0) && !hasError) ||
    (hasError && codes.length > 0);

  if (callbackMalformed) {
    setContent(
      "Confirmation link unavailable",
      "This web confirmation link is invalid or uses an unsupported authentication flow.",
      "Return to GymApp website",
      PUBLIC_SITE_URL
    );
    return false;
  }

  if (hasError) {
    const recoveryError = storedTransaction?.purpose === "recovery";
    setContent(
      recoveryError ? "Password reset could not be verified" : "Confirmation could not be completed",
      recoveryError
        ? "This password reset link expired or is unavailable. Return to GymApp and request a new reset email."
        : "This confirmation link expired or is unavailable. Return to GymApp and request a new confirmation email.",
      "Return to GymApp",
      PUBLIC_SITE_URL
    );
    return false;
  }

  if (codes.length === 1 && AUTH_CODE_PATTERN.test(codes[0]) && rawHash.length === 0 && storedTransaction) {
    const appUrl = new URL(PUBLIC_SITE_URL);
    appUrl.searchParams.set("platform", "web");
    appUrl.searchParams.set("state", storedTransaction.state);
    appUrl.searchParams.set("purpose", storedTransaction.purpose);
    appUrl.searchParams.set("code", codes[0]);
    if (storedTransaction.purpose === "recovery") {
      setContent(
        "Password reset verified",
        "Continue to GymApp in this browser to choose a new password.",
        "Continue to reset password",
        appUrl.toString()
      );
    } else {
      setContent(
        "Email confirmed",
        "Continue to GymApp in this browser to finish signing in.",
        "Continue to GymApp",
        appUrl.toString()
      );
    }
    return true;
  }

  if (codes.length > 0 || bridgeQuery.getAll("error_code").length > 0 ||
      bridgeFragment.getAll("error_code").length > 0) {
    setContent(
      "Confirmation link unavailable",
      "Return to GymApp and request a new confirmation or password reset email in this browser.",
      "Return to GymApp website",
      PUBLIC_SITE_URL
    );
    return false;
  }
  setContent(
    "Confirmation link unavailable",
    "Request a new confirmation or password reset email from GymApp in this browser.",
    "Return to GymApp website",
    PUBLIC_SITE_URL
  );
  return false;
}

const platform = bridgeQuery.getAll("platform")[0] || null;
let preserveCallbackURL = false;
if (platform === "ios") {
  preserveCallbackURL = configureIOSBridge();
} else if (platform === "web") {
  preserveCallbackURL = configureWebReturn();
} else if (platform === null || platform === "android") {
  preserveCallbackURL = configureAndroidBridge();
} else {
  setContent(
    "Confirmation link unavailable",
    "This confirmation link targets an unsupported platform.",
    "Return to GymApp website",
    PUBLIC_SITE_URL
  );
}

// A valid PKCE code is short-lived, single-use and unusable without the verifier
// held by the requesting app. Retaining it lets a reload or browser restore offer
// the same manual Open GymApp fallback. Token-bearing and invalid callbacks are
// still scrubbed immediately, and the page sends no referrer.
if (!preserveCallbackURL && (window.location.search || window.location.hash)) {
  window.history.replaceState(null, "", window.location.pathname);
}
