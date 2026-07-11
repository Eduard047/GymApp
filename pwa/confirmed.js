"use strict";

const PUBLIC_SITE_URL = "https://gymapptracker.com/";
const ANDROID_AUTH_CALLBACK_URL = "com.setforge.gymapp://auth/callback";
const IOS_AUTH_CALLBACK_URL = "com.setforge.gymapp.ios://auth/callback";
const IOS_STATE_PATTERN = /^[A-Za-z0-9_-]{32}$/;
const button = document.querySelector("#open-app");
const title = document.querySelector("#confirmation-title");
const message = document.querySelector("#confirmation-message");
const rawSearch = window.location.search.replace(/^\?/, "");
const rawHash = window.location.hash.replace(/^#/, "");
const IOS_QUERY_KEYS = new Set([
  "platform",
  "state",
  "code",
  "error",
  "error_description"
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

function parseBridgeQuery() {
  const values = new Map();
  let malformed = false;
  let tokenLike = false;

  for (const pair of rawSearch.split("&").filter(Boolean)) {
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
    if (!IOS_QUERY_KEYS.has(key)) continue;

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

const bridgeQuery = parseBridgeQuery();

function configureIOSBridge() {
  const platforms = bridgeQuery.getAll("platform");
  const states = bridgeQuery.getAll("state");
  const codes = bridgeQuery.getAll("code");
  const errors = bridgeQuery.getAll("error");
  const descriptions = bridgeQuery.getAll("error_description");
  const state = states[0] || "";
  const hasCode = codes.length === 1 && isSafeValue(codes[0], 2048);
  const hasError = errors.length === 1 && isSafeValue(errors[0], 128);
  const hasDescription = descriptions.length === 1 && isSafeValue(descriptions[0], 1024);
  const invalid = platforms.length !== 1 || platforms[0] !== "ios" ||
    states.length !== 1 || !IOS_STATE_PATTERN.test(state) ||
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
    return;
  }

  const appUrl = new URL(`${IOS_AUTH_CALLBACK_URL}/${state}`);
  if (hasCode) {
    appUrl.searchParams.set("code", codes[0]);
    setContent(
      "Email confirmed",
      "Open GymApp to finish the secure sign-in.",
      "Open GymApp for iOS",
      appUrl.toString()
    );
    return;
  }

  appUrl.searchParams.set("error", errors[0]);
  if (hasDescription) appUrl.searchParams.set("error_description", descriptions[0]);
  setContent(
    "Confirmation could not be completed",
    "Open GymApp to review the authentication error and try again.",
    "Return to GymApp for iOS",
    appUrl.toString()
  );
}

function configureAndroidBridge() {
  setContent(
    "Email confirmed",
    "Your account is ready. Open GymApp to continue.",
    "Open GymApp",
    `${ANDROID_AUTH_CALLBACK_URL}${window.location.search}${window.location.hash}`
  );
}

function configureWebReturn() {
  setContent(
    "Email confirmed",
    "Your account is ready. Return to GymApp and log in.",
    "Return to GymApp",
    PUBLIC_SITE_URL
  );
}

const platform = bridgeQuery.getAll("platform")[0] || null;
if (platform === "ios") {
  configureIOSBridge();
} else if (platform === "web") {
  configureWebReturn();
} else if (platform === null || platform === "android") {
  configureAndroidBridge();
} else {
  setContent(
    "Confirmation link unavailable",
    "This confirmation link targets an unsupported platform.",
    "Return to GymApp website",
    PUBLIC_SITE_URL
  );
}

if (window.location.search || window.location.hash) {
  window.history.replaceState(null, "", window.location.pathname);
}
