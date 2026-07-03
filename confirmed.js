"use strict";

const ANDROID_AUTH_CALLBACK_URL = "com.setforge.gymapp://auth/callback";
const button = document.querySelector("#open-app");
const appUrl = `${ANDROID_AUTH_CALLBACK_URL}${window.location.search}${window.location.hash}`;

if (button) {
  button.setAttribute("href", appUrl);
}

if (window.location.search || window.location.hash) {
  window.history.replaceState(null, "", window.location.pathname);
}
