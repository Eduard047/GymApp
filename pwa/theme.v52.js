"use strict";

(() => {
  const STORAGE_KEY = "gym-pwa-theme-v1";
  const ALLOWED_PREFERENCES = new Set(["system", "light", "dark"]);
  const DARK_MEDIA_QUERY = "(prefers-color-scheme: dark)";
  const THEME_COLORS = Object.freeze({ light: "#f7faff", dark: "#071321" });
  const root = document.documentElement;
  const darkMedia = typeof window.matchMedia === "function"
    ? window.matchMedia(DARK_MEDIA_QUERY)
    : null;

  function storedPreference() {
    try {
      const value = window.localStorage.getItem(STORAGE_KEY);
      return ALLOWED_PREFERENCES.has(value) ? value : "system";
    } catch {
      return "system";
    }
  }

  let preference = storedPreference();

  function resolvedTheme() {
    if (preference === "light" || preference === "dark") return preference;
    return darkMedia?.matches ? "dark" : "light";
  }

  function syncVisibleControls() {
    if (typeof document.querySelectorAll !== "function") return;
    document.querySelectorAll('button[data-action="set-theme"][data-theme]').forEach(button => {
      const selected = button.getAttribute("data-theme") === preference;
      button.classList.toggle("selected", selected);
      button.setAttribute("aria-checked", String(selected));
    });
  }

  function applyTheme() {
    const theme = resolvedTheme();
    root.setAttribute("data-theme", theme);
    root.style.colorScheme = theme;
    const themeColor = document.getElementById("app-theme-color");
    themeColor?.setAttribute("content", THEME_COLORS[theme]);
    syncVisibleControls();
  }

  function setPreference(value) {
    if (!ALLOWED_PREFERENCES.has(value)) return false;
    preference = value;
    try {
      window.localStorage.setItem(STORAGE_KEY, value);
    } catch {
      // The selected theme still applies for this tab when storage is unavailable.
    }
    applyTheme();
    return true;
  }

  const onSystemThemeChange = () => {
    if (preference === "system") applyTheme();
  };
  if (typeof darkMedia?.addEventListener === "function") {
    darkMedia.addEventListener("change", onSystemThemeChange);
  } else if (typeof darkMedia?.addListener === "function") {
    darkMedia.addListener(onSystemThemeChange);
  }

  window.addEventListener("storage", event => {
    if (event.key !== STORAGE_KEY) return;
    preference = ALLOWED_PREFERENCES.has(event.newValue) ? event.newValue : "system";
    applyTheme();
  });

  window.GymThemePreference = Object.freeze({
    getPreference: () => preference,
    getResolvedTheme: resolvedTheme,
    setPreference
  });

  applyTheme();
})();
