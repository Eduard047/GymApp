import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [guardSource, appSource, confirmedSource, indexHtml, confirmedHtml, styles, confirmedStyles] =
  await Promise.all([
    readFile("pwa/frame-guard.js", "utf8"),
    readFile("pwa/app.js", "utf8"),
    readFile("pwa/confirmed.js", "utf8"),
    readFile("pwa/index.html", "utf8"),
    readFile("pwa/confirmed.html", "utf8"),
    readFile("pwa/styles.css", "utf8"),
    readFile("pwa/confirmed.css", "utf8")
  ]);

function classList(initial = ["frame-pending"]) {
  const values = new Set(initial);
  return {
    add: (...items) => items.forEach(item => values.add(item)),
    remove: (...items) => items.forEach(item => values.delete(item)),
    contains: item => values.has(item)
  };
}

function guardContext({ framed }) {
  let domReady = null;
  const replaced = [];
  const root = { classList: classList(), dataset: {} };
  const body = { replaceChildren: (...nodes) => replaced.push(nodes) };
  const document = {
    readyState: "loading",
    documentElement: root,
    body,
    addEventListener(type, callback) {
      if (type === "DOMContentLoaded") domReady = callback;
    },
    createElement(tagName) {
      return {
        tagName,
        className: "",
        textContent: "",
        children: [],
        attributes: new Map(),
        setAttribute(name, value) { this.attributes.set(name, String(value)); },
        append(...nodes) { this.children.push(...nodes); }
      };
    }
  };
  const window = {};
  window.self = window;
  window.top = framed ? {} : window;
  const context = { document, window };
  vm.runInNewContext(guardSource, context);
  return { window, root, replaced, runDomReady: () => domReady?.() };
}

test("frame guard is the earliest script and both documents start fail-closed", () => {
  for (const html of [indexHtml, confirmedHtml]) {
    assert.match(html, /<html[^>]+class="frame-pending"/);
    const guardIndex = html.indexOf('<script src="./frame-guard.v50.js"></script>');
    assert.equal(html.indexOf("<script"), guardIndex);
    const nextScriptIndex = html.indexOf("<script", guardIndex + 1);
    assert.ok(guardIndex > 0 && (nextScriptIndex === -1 || guardIndex < nextScriptIndex));
    assert.doesNotMatch(html.slice(guardIndex, guardIndex + 70), /defer|async/);
  }
  assert.match(styles, /html\.frame-pending body \{ visibility: hidden !important; \}/);
  assert.match(confirmedStyles, /html\.frame-pending body \{ visibility: hidden !important; \}/);
  assert.match(appSource.slice(0, 350), /__GYMAPP_TOP_LEVEL__ !== true[\s\S]*window\.top !== window\.self/);
  assert.match(confirmedSource.slice(0, 350), /__GYMAPP_TOP_LEVEL__ !== true[\s\S]*window\.top !== window\.self/);
});

test("main CSP blocks inline code and limits cloud connections to the configured project", () => {
  assert.match(indexHtml, /style-src 'self'/);
  assert.doesNotMatch(indexHtml, /unsafe-inline|https:\/\/\*\.supabase\.co|img-src[^;]*blob:/);
  assert.match(indexHtml, /connect-src 'self' https:\/\/owrcbsrectdgaotndtxy\.supabase\.co/);
  assert.match(indexHtml, /form-action 'none'/);
  assert.doesNotMatch(appSource, /\sstyle\s*=/i);
});

test("top-level guard unhides the document without reading application state", () => {
  const result = guardContext({ framed: false });
  assert.equal(result.window.__GYMAPP_TOP_LEVEL__, true);
  assert.equal(result.root.classList.contains("frame-pending"), false);
  assert.equal(result.root.dataset.frameGuard, "top-level");
  assert.equal(result.replaced.length, 0);
});

test("framed guard keeps content hidden until it replaces the body with inert text", () => {
  const result = guardContext({ framed: true });
  assert.equal(result.window.__GYMAPP_TOP_LEVEL__, false);
  assert.equal(result.root.classList.contains("frame-pending"), true);
  result.runDomReady();
  assert.equal(result.replaced.length, 1);
  const panel = result.replaced[0][0];
  assert.equal(panel.tagName, "main");
  assert.equal(panel.children.length, 2);
  assert.match(panel.children[0].textContent, /cannot run inside another site/i);
  assert.equal(result.root.classList.contains("frame-blocked"), true);
  assert.equal(result.root.classList.contains("frame-pending"), false);
  assert.equal(panel.children.some(child => child.tagName === "a" || child.tagName === "button"), false);
});
