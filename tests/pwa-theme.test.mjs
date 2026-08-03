import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const themeSource = readFileSync(new URL("../pwa/theme.js", import.meta.url), "utf8");
const indexHtml = readFileSync(new URL("../pwa/index.html", import.meta.url), "utf8");
const styles = readFileSync(new URL("../pwa/styles.css", import.meta.url), "utf8");
const appSource = readFileSync(new URL("../pwa/app.js", import.meta.url), "utf8");
const russianSource = readFileSync(new URL("../pwa/russian-text.js", import.meta.url), "utf8");

function loadTheme({ stored = null, dark = false, storageThrows = false } = {}) {
  const attributes = new Map();
  const storage = new Map(stored == null ? [] : [["gym-pwa-theme-v1", stored]]);
  const windowListeners = new Map();
  const mediaListeners = new Map();
  const themeColor = {
    setAttribute(name, value) { attributes.set(`meta:${name}`, value); }
  };
  const root = {
    style: {},
    setAttribute(name, value) { attributes.set(name, value); }
  };
  const media = {
    matches: dark,
    addEventListener(type, listener) { mediaListeners.set(type, listener); }
  };
  const window = {
    matchMedia(query) {
      assert.equal(query, "(prefers-color-scheme: dark)");
      return media;
    },
    localStorage: {
      getItem(key) {
        if (storageThrows) throw new DOMException("blocked", "SecurityError");
        return storage.get(key) ?? null;
      },
      setItem(key, value) {
        if (storageThrows) throw new DOMException("blocked", "SecurityError");
        storage.set(key, value);
      }
    },
    addEventListener(type, listener) { windowListeners.set(type, listener); }
  };
  const document = {
    documentElement: root,
    getElementById(id) { return id === "app-theme-color" ? themeColor : null; }
  };

  vm.runInNewContext(themeSource, { DOMException, Map, Object, Set, document, window });
  return { attributes, media, mediaListeners, storage, window, windowListeners };
}

test("theme preference validates storage and applies before the stylesheet", () => {
  assert.ok(indexHtml.indexOf("theme.v56.js") < indexHtml.indexOf("styles.v61.css"));
  assert.match(indexHtml, /id="app-theme-color" name="theme-color"/);
  assert.match(styles, /:root\[data-theme="dark"\]/);
  assert.doesNotMatch(styles, /@media \(prefers-color-scheme: dark\)/);

  const invalid = loadTheme({ stored: "<script>", dark: true });
  assert.equal(invalid.window.GymThemePreference.getPreference(), "system");
  assert.equal(invalid.attributes.get("data-theme"), "dark");
  assert.equal(invalid.attributes.get("meta:content"), "#071321");
});

test("light, dark, and system choices persist and follow system changes", () => {
  const runtime = loadTheme({ dark: true });
  const api = runtime.window.GymThemePreference;

  assert.equal(api.setPreference("light"), true);
  assert.equal(runtime.storage.get("gym-pwa-theme-v1"), "light");
  assert.equal(runtime.attributes.get("data-theme"), "light");
  assert.equal(runtime.attributes.get("meta:content"), "#f7faff");
  assert.equal(api.setPreference("sepia"), false);
  assert.equal(api.getPreference(), "light");

  assert.equal(api.setPreference("system"), true);
  runtime.media.matches = false;
  runtime.mediaListeners.get("change")();
  assert.equal(runtime.attributes.get("data-theme"), "light");
});

test("theme remains usable when browser storage is unavailable", () => {
  const runtime = loadTheme({ dark: false, storageThrows: true });
  assert.equal(runtime.window.GymThemePreference.setPreference("dark"), true);
  assert.equal(runtime.window.GymThemePreference.getPreference(), "dark");
  assert.equal(runtime.attributes.get("data-theme"), "dark");
});

test("PWA exposes an accessible localized three-way theme switch", () => {
  assert.match(appSource, /role="radiogroup"/);
  assert.match(appSource, /role="radio" aria-checked=/);
  assert.match(appSource, /\["system", "light", "dark"\]/);
  assert.match(appSource, /themePreferencePanel\("auth"\)/);
  assert.match(appSource, /\$\{themePreferencePanel\(\)\}/);
  for (const label of ["Appearance", "Color theme", "System", "Light", "Dark"]) {
    assert.match(russianSource, new RegExp(`\\["${label}"`));
  }
});
