"use strict";

(() => {
  const locales = new Map([
    ["en", "english"],
    ["uk", "ukrainian"],
    ["ru", "russian"]
  ]);
  const buttons = [...document.querySelectorAll("[data-language]")];
  const panels = new Map(
    [...locales].map(([locale, id]) => [locale, document.getElementById(id)])
  );

  if (!buttons.length || [...panels.values()].some(panel => !panel)) return;

  function localeFromHash() {
    const id = window.location.hash.slice(1).toLowerCase();
    return [...locales].find(([locale, panelID]) => (
      panelID === id || id.startsWith(`${locale}-`)
    ))?.[0] || null;
  }

  function preferredLocale() {
    const fromHash = localeFromHash();
    if (fromHash) return fromHash;

    for (const language of navigator.languages || [navigator.language]) {
      const base = String(language || "").toLowerCase().split("-")[0];
      if (locales.has(base)) return base;
    }
    return "en";
  }

  function selectLocale(locale, updateHash) {
    const safeLocale = locales.has(locale) ? locale : "en";

    for (const button of buttons) {
      const selected = button.dataset.language === safeLocale;
      button.setAttribute("aria-pressed", String(selected));
    }

    for (const [panelLocale, panel] of panels) {
      panel.hidden = panelLocale !== safeLocale;
    }

    document.documentElement.lang = safeLocale;
    if (updateHash) {
      window.history.replaceState(null, "", `#${locales.get(safeLocale)}`);
    }
  }

  for (const button of buttons) {
    button.addEventListener("click", () => selectLocale(button.dataset.language, true));
  }

  window.addEventListener("hashchange", () => selectLocale(localeFromHash() || "en", false));
  selectLocale(preferredLocale(), false);
})();
