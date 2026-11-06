import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const APP_STORE_URL = "https://apps.apple.com/app/id6797458372";

function functionBody(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `Missing function: ${name}`);
  const next = source.indexOf("\nfunction ", start + 1);
  return source.slice(start, next === -1 ? undefined : next);
}

test("PWA defines the official App Store listing next to the Google Play link", async () => {
  const app = await readFile("pwa/app.js", "utf8");

  assert.equal(app.includes(`const APP_STORE_APP_URL = "${APP_STORE_URL}";`), true);
  assert.equal(app.split(APP_STORE_URL).length - 1, 1, "Keep the listing URL defined exactly once");
});

test("PWA offers the App Store first in the download card and the profile links", async () => {
  const app = await readFile("pwa/app.js", "utf8");
  const panel = functionBody(app, "storeDownloadPanel");

  assert.match(
    panel,
    /class="store-download-link" href="\$\{escapeAttr\(APP_STORE_APP_URL\)\}" target="_blank" rel="noopener noreferrer"/
  );
  assert.equal(
    panel.indexOf("APP_STORE_APP_URL") < panel.indexOf("GOOGLE_PLAY_APP_URL"),
    true,
    "App Store button comes before Google Play"
  );
  assert.equal(panel.includes("<strong>App Store</strong>"), true);
  assert.match(panel, /iPhone/);

  assert.match(app, /settingsRowMarkup\(\{[^\n]*href: APP_STORE_APP_URL, trailing: external \}\)/);
  assert.equal(
    app.indexOf("href: APP_STORE_APP_URL") < app.indexOf("href: GOOGLE_PLAY_APP_URL"),
    true,
    "App Store row comes before Google Play"
  );
});

test("the bundle served by index.html carries the App Store link", async () => {
  const [index, app] = await Promise.all([readFile("pwa/index.html", "utf8"), readFile("pwa/app.js", "utf8")]);
  const bundleName = index.match(/<script src="\.\/(app\.v\d+\.js)" defer><\/script>/)?.[1];
  assert.notEqual(bundleName, undefined, "index.html references a versioned app bundle");

  const bundle = await readFile(`pwa/${bundleName}`, "utf8");
  assert.equal(bundle.includes(`const APP_STORE_APP_URL = "${APP_STORE_URL}";`), true);
  assert.equal(bundle, app, "the shipped bundle is a byte copy of the working file");
});
