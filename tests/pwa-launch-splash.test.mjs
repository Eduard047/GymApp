import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, stylesSource, indexSource, iosSplash] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/styles.css", "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/IntroSplashView.swift", "utf8")
]);

function block(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = stylesSource.match(new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`));
  assert.ok(match, `${selector} rule must exist`);
  return match[1];
}

const splashSource = (() => {
  const start = appSource.indexOf("const BOOT_SPLASH_VISIBLE_MS");
  const end = appSource.indexOf("async function registerCurrentServiceWorker", start);
  assert.ok(start >= 0 && end > start);
  return appSource.slice(start, end);
})();

class FakeElement {
  constructor(tag) {
    this.tagName = tag;
    this.children = [];
    this.attributes = new Map();
    this.classes = new Set();
    this.isConnected = true;
    this.textContent = "";
    this.removed = false;
    this.classList = {
      add: name => this.classes.add(name),
      contains: name => this.classes.has(name)
    };
  }
  set className(value) { this.classes = new Set(String(value).split(/\s+/).filter(Boolean)); }
  get className() { return [...this.classes].join(" "); }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  removeAttribute(name) { this.attributes.delete(name); }
  append(...nodes) { this.children.push(...nodes); }
  remove() { this.isConnected = false; this.removed = true; }
  find(cls) {
    for (const child of this.children) {
      if (child.classes.has(cls)) return child;
      const nested = child.find(cls);
      if (nested) return nested;
    }
    return null;
  }
}

function splashHarness({ language = "en", reduced = false, withSplash = true } = {}) {
  const timers = [];
  let nextId = 1;
  const splash = withSplash ? new FakeElement("div") : null;
  splash?.setAttribute("aria-hidden", "true");
  const context = vm.createContext({
    state: { language },
    tx3: (en, uk, ru) => (language === "uk" ? uk : language === "ru" ? ru : en),
    document: {
      getElementById: id => (id === "boot-splash" ? splash : null),
      createElement: tag => new FakeElement(tag)
    },
    window: {
      matchMedia: query => ({ matches: reduced && query === "(prefers-reduced-motion: reduce)" })
    },
    setTimeout: (fn, ms) => {
      const id = nextId++;
      timers.push({ id, fn, ms, cleared: false });
      return id;
    },
    clearTimeout: id => {
      const timer = timers.find(entry => entry.id === id);
      if (timer) timer.cleared = true;
    }
  });
  vm.runInContext(`${splashSource}
    globalThis.startBootSplash = startBootSplash;
    globalThis.dismissBootSplash = dismissBootSplash;`, context);
  const fire = ms => {
    for (const timer of timers.filter(entry => entry.ms === ms && !entry.cleared)) {
      timer.cleared = true;
      timer.fn();
    }
  };
  return { context, splash, timers, fire };
}

test("index.html carries a static, decorative boot mark that stays hidden without the new CSS", () => {
  assert.match(
    indexSource,
    /<body>\s*<div id="boot-splash" class="boot-splash" aria-hidden="true" hidden><img class="boot-splash-mark" src="\.\/icon-512\.png" width="120" height="120" alt=""[^>]*><\/div>\s*<div id="app"/
  );
  assert.ok(indexSource.indexOf('id="boot-splash"') < indexSource.indexOf('id="app"'));
  assert.ok(indexSource.indexOf('id="boot-splash"') < indexSource.indexOf("app.v"));
  assert.doesNotMatch(indexSource, /<boot|style=|<style|onload=|onerror=/i);
  assert.match(indexSource, /style-src 'self';/);
  assert.match(indexSource, /img-src 'self' data:/);
});

test("the boot splash keeps the launch-screen frame: 120px mark exactly centred on the canvas colour", () => {
  const splash = block(".boot-splash");
  assert.match(splash, /display:\s*block/);
  assert.match(splash, /position:\s*fixed/);
  assert.match(splash, /inset:\s*0/);
  assert.match(splash, /background:\s*var\(--background\)/);
  const mark = block(".boot-splash-mark");
  assert.match(mark, /position:\s*absolute/);
  assert.match(mark, /top:\s*50%/);
  assert.match(mark, /left:\s*50%/);
  assert.match(mark, /width:\s*120px/);
  assert.match(mark, /height:\s*120px/);
  assert.match(mark, /transform:\s*translate\(-50%,\s*-50%\)/);
  assert.doesNotMatch(mark, /animation|transition/);
  assert.match(stylesSource, /:root\s*\{[^}]*--background:\s*#f7faff/);
  assert.match(stylesSource, /:root\[data-theme="dark"\]\s*\{[^}]*--background:\s*#071321/);
});

test("splash text is anchored below the mark's own centre so lower content never moves the mark", () => {
  const stack = block(".boot-splash-stack");
  assert.match(stack, /top:\s*calc\(50% \+ 60px \+ 24px\)/);
  assert.match(stack, /position:\s*absolute/);
  assert.match(block(".boot-splash-copy"), /animation:\s*boot-splash-fade-in 250ms ease-out both/);
  assert.match(block(".boot-splash-title"), /font-weight:\s*700/);
  assert.match(iosSplash, /iconSize: CGFloat = 120/);
  assert.match(iosSplash, /Spacing\.xLarge/);
  assert.match(iosSplash, /duration: 0\.25/);
});

test("the splash dismisses with a 280ms fade and 1.015 scale, honours reduced motion, and has a CSS failsafe", () => {
  const leaving = block(".boot-splash.leaving");
  assert.match(leaving, /opacity:\s*0/);
  assert.match(leaving, /transform:\s*scale\(1\.015\)/);
  assert.match(leaving, /opacity 280ms/);
  assert.match(leaving, /pointer-events:\s*none/);
  assert.match(stylesSource, /@media \(prefers-reduced-motion: reduce\)\s*\{\s*\.boot-splash-copy,\s*\.boot-splash-spinner \{ animation: none; \}\s*\.boot-splash\.leaving \{ transform: none; transition: none; \}/);
  assert.match(block(".boot-splash"), /animation:\s*boot-splash-failsafe 1ms linear 8s forwards/);
  assert.match(stylesSource, /@keyframes boot-splash-failsafe \{ to \{ opacity: 0; visibility: hidden; pointer-events: none; \} \}/);
});

test("splash fades in text immediately, adds the spinner only after 1s, and removes the node after 1.4s", () => {
  for (const [language, tagline, label] of [
    ["en", "Build strength with focus and consistency.", "Preparing your session"],
    ["uk", "Розвивай силу з фокусом і системністю.", "Готуємо твою сесію"],
    ["ru", "Развивай силу с фокусом и системностью.", "Готовим твою сессию"]
  ]) {
    const harness = splashHarness({ language });
    const { context, splash, timers, fire } = harness;
    assert.equal(context.startBootSplash(), true);
    assert.equal(splash.getAttribute("aria-hidden"), null, "the splash owns a status region, so it is not hidden");
    assert.equal(splash.find("boot-splash-title").textContent, "GymApp");
    assert.equal(splash.find("boot-splash-tagline").textContent, tagline);
    assert.equal(splash.find("boot-splash-copy").getAttribute("aria-hidden"), "true");
    assert.equal(splash.find("boot-splash-spinner"), null, "no spinner on a fast start");
    assert.deepEqual(timers.map(timer => timer.ms).sort((a, b) => a - b), [1000, 1400]);

    fire(1000);
    const spinner = splash.find("boot-splash-spinner");
    assert.ok(spinner);
    assert.equal(spinner.getAttribute("role"), "status");
    assert.equal(spinner.getAttribute("aria-label"), label);
    assert.equal(splash.removed, false);

    fire(1400);
    assert.equal(splash.classes.has("leaving"), true);
    assert.equal(splash.removed, false, "the node stays for the fade");
    fire(320);
    assert.equal(splash.removed, true);
  }
});

test("a fast dismissal cancels the spinner so it never appears", () => {
  const { context, splash, timers, fire } = splashHarness();
  context.startBootSplash();
  fire(1400);
  fire(1000);
  assert.equal(splash.find("boot-splash-spinner"), null);
  assert.ok(timers.filter(timer => timer.ms === 1000).every(timer => timer.cleared));
  fire(320);
  assert.equal(splash.removed, true);
});

test("reduced motion removes the splash without the scale fade", () => {
  const { context, splash, fire } = splashHarness({ reduced: true });
  context.startBootSplash();
  fire(1400);
  assert.equal(splash.classes.has("leaving"), false);
  assert.equal(splash.removed, true);
});

test("the splash runs once per page load and tolerates a missing boot element", () => {
  const { context, splash, timers } = splashHarness();
  assert.equal(context.startBootSplash(), true);
  const timerCount = timers.length;
  const childCount = splash.children.length;
  assert.equal(context.startBootSplash(), false);
  assert.equal(timers.length, timerCount);
  assert.equal(splash.children.length, childCount);
  assert.equal(splashHarness({ withSplash: false }).context.startBootSplash(), false);
  assert.match(appSource, /\nstartBootSplash\(\);\n\nif \(!handleEmailConfirmationRedirect\(\)\) \{/);
  const renderSource = appSource.slice(appSource.indexOf("\nfunction render() {"), appSource.indexOf("\nfunction ", appSource.indexOf("\nfunction render() {") + 10));
  assert.doesNotMatch(renderSource, /startBootSplash|boot-splash/);
});

test("new splash sources use function declarations and keep the showToast boundary intact", () => {
  assert.match(splashSource, /function bootSplashPrefersReducedMotion\(\)/);
  assert.match(splashSource, /function dismissBootSplash\(splash\)/);
  assert.match(splashSource, /function startBootSplash\(\)/);
  assert.ok(appSource.indexOf("\nfunction showToast") > 0);
  assert.ok(appSource.indexOf("function scrubServiceWorkerRefreshParameter()") < appSource.indexOf("\nfunction showToast"));
  assert.doesNotMatch(splashSource, /innerHTML|\.style\b|setAttribute\("style"/);
});
