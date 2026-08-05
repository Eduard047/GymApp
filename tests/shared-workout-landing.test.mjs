import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import test from "node:test";

const require = createRequire(import.meta.url);
const codec = require("../pwa/shared-workout.js");
const landing = require("../pwa/workout/landing.js");
const html = readFileSync(new URL("../pwa/workout/index.html", import.meta.url), "utf8");
const source = readFileSync(new URL("../pwa/workout/landing.js", import.meta.url), "utf8");

const plan = {
  exercises: [
    {
      catalogKey: "bench_press",
      name: "Bench Press",
      sets: [{ weight: 60, reps: 8 }, { weight: 65, reps: 6 }]
    },
    {
      name: "Custom movement",
      sets: [{ weight: 0, reps: 12 }]
    }
  ]
};

test("landing parses the canonical fragment and builds all three explicit destinations", () => {
  const encoded = codec.encode(plan);
  const result = landing.parse(`https://gymapptracker.com/workout/#workout=${encoded}`);

  assert.deepEqual(result.plan, codec.normalize(plan));
  assert.deepEqual(result.summary, {
    exerciseCount: 2,
    setCount: 3,
    volume: 870
  });
  assert.deepEqual(result.links, {
    android: `com.setforge.gymapp://workout/#workout=${encoded}`,
    ios: `com.setforge.gymapp.ios://workout/#workout=${encoded}`,
    web: `https://gymapptracker.com/#workout=${encoded}`
  });
});

test("landing accepts loopback preview but rejects non-canonical public URLs", () => {
  const encoded = codec.encode(plan);
  assert.equal(
    landing.parse(`http://127.0.0.1/workout/#workout=${encoded}`).summary.setCount,
    3
  );
  for (const url of [
    `http://gymapptracker.com/workout/#workout=${encoded}`,
    `https://www.gymapptracker.com/workout/#workout=${encoded}`,
    `https://evil.example/workout/#workout=${encoded}`,
    `https://gymapptracker.com/other/workout/#workout=${encoded}`,
    `https://user:password@gymapptracker.com/workout/#workout=${encoded}`,
    `https://gymapptracker.com/workout/?utm_source=test#workout=${encoded}`,
    `https://gymapptracker.com/workout/#workout=${encoded}&workout=${encoded}`,
    `https://gymapptracker.com/workout/#workout=${encoded}&access_token=secret`,
    `https://gymapptracker.com/workout/#workout=${"a".repeat(codec.LIMITS.encodedLength + 1)}`
  ]) {
    assert.throws(() => landing.parse(url), TypeError, url);
  }
});

test("landing is a bounded, script-only renderer with a strict standalone CSP", () => {
  assert.match(html, /Content-Security-Policy[^>]+default-src 'none'/);
  assert.match(html, /connect-src 'none'/);
  assert.match(html, /frame-ancestors 'none'/);
  assert.doesNotMatch(html, /unsafe-inline|unsafe-eval/);
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)[^>]*>/i);
  assert.doesNotMatch(html, /<style\b/i);
  assert.doesNotMatch(html, /\son[a-z]+\s*=/i);
  assert.match(html, /<html lang="en" class="frame-pending">/);
  assert.ok(html.indexOf("../frame-guard.v56.js") < html.indexOf("../shared-workout.v65.js"));
  assert.match(html, /\.\.\/shared-workout\.v65\.js/);
  assert.match(html, /\.\/landing\.v2\.js/);
  assert.match(html, /\.\/landing\.v1\.css/);
  assert.match(source, /textContent/);
  assert.doesNotMatch(source, /\.innerHTML|insertAdjacentHTML|document\.write/);
  assert.match(source, /addEventListener\("hashchange", render\)/);

  const versionedScript = readFileSync(new URL("../pwa/workout/landing.v2.js", import.meta.url));
  const versionedStyle = readFileSync(new URL("../pwa/workout/landing.v1.css", import.meta.url));
  assert.equal(versionedScript.equals(readFileSync(new URL("../pwa/workout/landing.js", import.meta.url))), true);
  assert.equal(versionedStyle.equals(readFileSync(new URL("../pwa/workout/landing.css", import.meta.url))), true);
});

test("landing language choice is bounded to English, Ukrainian, and Russian", () => {
  assert.equal(landing.languageFor({ language: "uk-UA" }), "uk");
  assert.equal(landing.languageFor({ language: "ru-RU" }), "ru");
  assert.equal(landing.languageFor({ language: "de-DE" }), "en");
});

function fakeNode() {
  const attributes = new Map();
  const classes = new Set();
  return {
    textContent: "",
    href: "",
    children: [],
    className: "",
    attributes,
    classList: {
      add(value) { classes.add(value); },
      remove(value) { classes.delete(value); },
      contains(value) { return classes.has(value); }
    },
    append(...children) { this.children.push(...children); },
    replaceChildren(...children) { this.children = children; },
    setAttribute(name, value) { attributes.set(name, String(value)); },
    removeAttribute(name) {
      attributes.delete(name);
      if (name === "href") this.href = "";
    }
  };
}

function fakeDocument() {
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, fakeNode());
    return nodes.get(id);
  };
  return {
    documentElement: { lang: "en" },
    title: "",
    nodes,
    getElementById: node,
    querySelector(selector) {
      return node(`selector:${selector}`);
    },
    createElement() { return fakeNode(); }
  };
}

test("landing clears stale plans and actions before every fragment remount", () => {
  const document = fakeDocument();
  const encoded = codec.encode(plan);
  const validUrl = `https://gymapptracker.com/workout/#workout=${encoded}`;

  assert.ok(landing.mount(document, validUrl, { language: "en", userAgent: "Android" }));
  assert.equal(document.nodes.get("preview-panel").attributes.has("hidden"), false);
  assert.equal(document.nodes.get("action-panel").attributes.has("hidden"), false);
  assert.equal(document.nodes.get("invalid-panel").attributes.has("hidden"), true);
  assert.equal(document.nodes.get("exercise-list").children.length, 2);
  assert.match(document.nodes.get("open-android").href, /^com\.setforge\.gymapp:/);
  assert.equal(document.nodes.get("open-android").classList.contains("recommended"), true);

  assert.equal(landing.mount(document, "https://gymapptracker.com/workout/#workout=***", {
    language: "en",
    userAgent: "Android"
  }), null);
  assert.equal(document.nodes.get("preview-panel").attributes.has("hidden"), true);
  assert.equal(document.nodes.get("action-panel").attributes.has("hidden"), true);
  assert.equal(document.nodes.get("invalid-panel").attributes.has("hidden"), false);
  assert.equal(document.nodes.get("exercise-list").children.length, 0);
  assert.equal(document.nodes.get("open-android").href, "");
  assert.equal(document.nodes.get("open-android").classList.contains("recommended"), false);
});
