"use strict";

if (window.__GYMAPP_TOP_LEVEL__ !== true || window.top !== window.self) {
  throw new DOMException(
    "GymApp authentication callback must run in a top-level browsing context.",
    "SecurityError"
  );
}

const NATIVE_AUTH_CALLBACK_PATHS = new Set([
  "/auth/android-callback.html",
  "/auth/ios-callback.html"
]);

// A verified App/Universal Link is normally delivered straight to the native
// app. If association fails and the browser renders this fallback, remove the
// one-time code or error from browser history before displaying any content.
if (NATIVE_AUTH_CALLBACK_PATHS.has(window.location.pathname) &&
    (window.location.search || window.location.hash)) {
  window.history.replaceState(null, "", window.location.pathname);
}

window.addEventListener("DOMContentLoaded", () => {
  const title = document.querySelector("#confirmation-title");
  const message = document.querySelector("#confirmation-message");
  const button = document.querySelector("#open-app");
  if (title) title.textContent = "Open the newest link in GymApp";
  if (message) {
    message.textContent =
      "This secure callback was not claimed by the installed app. Update GymApp, then request and open a new confirmation or password reset email on this device.";
  }
  if (button) {
    button.textContent = "Return to GymApp website";
    button.setAttribute("href", "https://gymapptracker.com/");
  }
}, { once: true });
