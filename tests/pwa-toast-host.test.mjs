import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const [appSource, cssSource] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/styles.css", "utf8")
]);

function slice(start, end) {
  const from = appSource.indexOf(start);
  const to = appSource.indexOf(end, from);
  assert.ok(from >= 0 && to > from, `source markers not found: ${start}`);
  return appSource.slice(from, to);
}

const toastSource = slice("const TOAST_DURATION_MS", "const BOOT_SPLASH_VISIBLE_MS");
const bannerSource = slice("const BANNER_EXIT_OPACITY_MS", "function clearActiveBatchUndo()");

function pure() {
  const context = { Math, Number, String, Array, Object, Date, Date: Date, Map, clearTimeout() {}, setTimeout() {} };
  vm.createContext(context);
  vm.runInContext(`${toastSource}\n${bannerSource}\nglobalThis.api = { toastNormalize, toastDurationMs, toastInitialState, toastReduce, toastDeadlineMs, toastSwipeAxis, toastSwipeOffset, toastSwipeDecision, toastExitPlan, bannerExitPlan };`, context);
  return context.api;
}

const api = pure();
const show = (state, message, now, action, kind) => api.toastReduce(state, { type: "show", message, now, action, kind });

test("a toast lasts 4s, 6s with an action, and expires on schedule", () => {
  let state = show(api.toastInitialState(), "Copied.", 1000);
  assert.equal(state.current.text, "Copied.");
  assert.equal(api.toastDeadlineMs(state, 1000), 4000);
  assert.equal(api.toastDeadlineMs(state, 2500), 2500);
  assert.equal(api.toastReduce(state, { type: "expire", now: 3000 }), state, "early expire is ignored");
  assert.equal(api.toastReduce(state, { type: "expire", now: 5000 }).current, null);
  state = show(api.toastInitialState(), "Deleted.", 0, { label: "Undo", onAction() {} });
  assert.equal(api.toastDeadlineMs(state, 0), 6000);
  assert.equal(state.current.action.label, "Undo");
});

test("duration by kind: info 4s, info+action 6s, plain error 6s, error with an action persists until dismissed", () => {
  const action = { label: "Retry", onAction() {} };
  assert.equal(api.toastDeadlineMs(show(api.toastInitialState(), "i", 0), 0), 4000);
  assert.equal(api.toastDeadlineMs(show(api.toastInitialState(), "i", 0, action), 0), 6000);
  assert.equal(api.toastDeadlineMs(show(api.toastInitialState(), "e", 0, undefined, "error"), 0), 6000);
  const sticky = show(api.toastInitialState(), "e", 0, action, "error");
  assert.equal(sticky.current.kind, "error");
  assert.equal(api.toastDeadlineMs(sticky, 0), null);
  assert.equal(api.toastReduce(sticky, { type: "expire", now: 1e9 }), sticky, "never expires");
  const paused = api.toastReduce(api.toastReduce(sticky, { type: "pause", reason: "hover", now: 5 }), { type: "resume", reason: "hover", now: 9 });
  assert.equal(api.toastDeadlineMs(paused, 1e9), null, "pause/resume keeps it persistent");
  assert.equal(api.toastReduce(sticky, { type: "dismiss", id: sticky.current.id }).current, null);
  assert.equal(show(api.toastInitialState(), "x", 0, undefined, "bogus").current.kind, "info");
});

test("a new toast replaces the current one, never stacks, and restarts the timer unpaused", () => {
  let state = show(api.toastInitialState(), "First", 0);
  state = api.toastReduce(state, { type: "pause", reason: "hover", now: 100 });
  const second = show(state, "Second", 500);
  assert.equal(second.current.text, "Second");
  assert.notEqual(second.current.id, state.current.id);
  assert.deepEqual([...second.pauses], []);
  assert.equal(api.toastDeadlineMs(second, 500), 4000);
  assert.equal(Object.keys(second).includes("queue"), false);
});

test("pausing freezes the remaining time; every pause reason must be released to resume", () => {
  let state = show(api.toastInitialState(), "Saved.", 0);
  state = api.toastReduce(state, { type: "pause", reason: "hover", now: 1000 });
  assert.equal(api.toastDeadlineMs(state, 9000), null);
  state = api.toastReduce(state, { type: "pause", reason: "focus", now: 2000 });
  state = api.toastReduce(state, { type: "resume", reason: "hover", now: 3000 });
  assert.equal(api.toastDeadlineMs(state, 4000), null, "focus still holds it");
  state = api.toastReduce(state, { type: "resume", reason: "focus", now: 10000 });
  assert.equal(api.toastDeadlineMs(state, 10000), 3000, "3000ms were left when it was paused at 1000");
  assert.equal(api.toastReduce(state, { type: "pause", reason: "focus", now: 10000 }).pauses.length, 1);
  assert.equal(api.toastReduce(state, { type: "expire", now: 13000 }).current, null);
});

test("dismiss and clear remove the toast; a stale dismiss id is ignored; empty text is dropped", () => {
  const state = show(api.toastInitialState(), "  Hello \n world  ", 0);
  assert.equal(state.current.text, "Hello world");
  assert.equal(api.toastReduce(state, { type: "dismiss", id: state.current.id + 1 }), state);
  assert.equal(api.toastReduce(state, { type: "dismiss", id: state.current.id }).current, null);
  assert.equal(api.toastReduce(state, { type: "clear" }).current, null);
  assert.equal(api.toastReduce(state, { type: "clear" }).sequence, state.sequence, "ids keep counting after a clear");
  assert.equal(show(api.toastInitialState(), "   ", 0).current, null);
  assert.equal(show(api.toastInitialState(), undefined, 0).current, null);
  assert.equal(show(api.toastInitialState(), "x".repeat(900), 0).current.text.length, 300);
});

test("an action needs a label and a handler, otherwise it is dropped", () => {
  assert.equal(api.toastNormalize("Hi", { label: "Undo" }).action, null);
  assert.equal(api.toastNormalize("Hi", { onAction() {} }).action, null);
  assert.equal(api.toastNormalize("Hi", { label: "  ", onAction() {} }).action, null);
  assert.equal(api.toastNormalize("Hi", { label: "Undo", onAction() {} }).action.label, "Undo");
  assert.equal(api.toastDurationMs(api.toastNormalize("Hi", {})), 4000);
});

test("swipe: axis locks after the slop, follows 1:1 down/sideways, rubber-bands upward, and dismisses by distance or velocity", () => {
  assert.equal(api.toastSwipeAxis(2, 3), null);
  assert.equal(api.toastSwipeAxis(4, 20), "y");
  assert.equal(api.toastSwipeAxis(-30, 5), "x");
  assert.deepEqual({ ...api.toastSwipeOffset({ axis: "y", dx: 40, dy: 25 }) }, { x: 0, y: 25 });
  assert.deepEqual({ ...api.toastSwipeOffset({ axis: "x", dx: -50, dy: 9 }) }, { x: -50, y: 0 });
  const up = api.toastSwipeOffset({ axis: "y", dy: -500 });
  assert.ok(up.y < 0 && up.y > -12, "upward pull stays under the 12px rubber-band cap");
  assert.equal(api.toastSwipeDecision({ axis: "y", distance: 41, velocity: 0 }), "dismiss");
  assert.equal(api.toastSwipeDecision({ axis: "y", distance: 10, velocity: 0.8 }), "dismiss");
  assert.equal(api.toastSwipeDecision({ axis: "y", distance: 10, velocity: 0.2 }), "restore");
  assert.equal(api.toastSwipeDecision({ axis: "y", distance: -80, velocity: -0.9 }), "restore", "upward never dismisses");
  assert.equal(api.toastSwipeDecision({ axis: "x", distance: -80, velocity: 0 }), "dismiss");
  assert.equal(api.toastSwipeDecision({ axis: "x", distance: 20, velocity: -0.7 }), "dismiss");
  assert.equal(api.toastSwipeDecision({ axis: null, distance: 500, velocity: 5 }), "restore");
});

test("exit plan: mirrored slide toward the bottom at ~80% of the 300ms enter, opacity 90ms; opacity only under reduced motion", () => {
  const plan = api.toastExitPlan({});
  assert.equal(plan.transformMs, 240);
  assert.equal(plan.opacityMs, 90);
  assert.match(plan.transform[1], /16px/);
  assert.equal(api.toastExitPlan({ reduced: true }).transform, null);
  assert.equal(api.toastExitPlan({ reduced: true }).opacityMs, 90);
  const side = api.toastExitPlan({ axis: "x", x: -60 });
  assert.match(side.transform[1], /-180px/);
});

test("banner exit plan: 90ms opacity + 200ms height collapse cancelling the row gap; none for reduced motion or zero height", () => {
  const plan = api.bannerExitPlan({ height: 52, gap: 12 });
  assert.equal(plan.opacityMs, 90);
  assert.equal(plan.collapseMs, 200);
  assert.deepEqual({ ...plan.from }, { height: "52px", marginBottom: "0px" });
  assert.deepEqual({ ...plan.to }, { height: "0px", marginBottom: "-12px" });
  assert.equal(api.bannerExitPlan({ height: 52, gap: 0 }).to.marginBottom, "0px");
  assert.equal(api.bannerExitPlan({ height: 52, reduced: true }), null);
  assert.equal(api.bannerExitPlan({ height: 0 }), null);
  assert.equal(api.bannerExitPlan({ height: Number.NaN }), null);
});

// ---- Host glue against a tiny fake DOM -----------------------------------------------------------
function fakeNode(tag) {
  const node = {
    tag, children: [], parent: null, attrs: new Map(), classes: new Set(), dataset: {}, style: {}, listeners: new Map(),
    isConnected: true, inert: false, textContent: "", id: "", className: "",
    setAttribute(key, value) { node.attrs.set(key, String(value)); },
    getAttribute(key) { return node.attrs.get(key) ?? null; },
    classList: { add: name => node.classes.add(name), contains: name => node.classes.has(name) },
    appendChild(child) { child.parent = node; node.children.push(child); return child; },
    addEventListener(type, listener) { node.listeners.set(type, listener); },
    contains: other => other === node || node.children.some(child => child.contains(other)),
    querySelectorAll: selector => selector === ".toast" ? node.children.filter(child => child.className.includes("toast")) : [],
    remove() { node.isConnected = false; if (node.parent) node.parent.children = node.parent.children.filter(child => child !== node); },
    animate() { return {}; }
  };
  return node;
}

function host({ reduced = false } = {}) {
  const body = fakeNode("body");
  const timers = [];
  const context = {
    Math, Number, String, Array, Object, Date, Map,
    activeAccount: { id: "a" },
    document: { body, createElement: tag => fakeNode(tag) },
    window: {},
    sheetAccountKey: () => String(context.activeAccount?.id ?? ""),
    sheetPrefersReducedMotion: () => reduced,
    sheetDragVelocity: () => 0,
    setTimeout: (fn, ms) => { timers.push({ fn, ms, live: true }); return timers.length; },
    clearTimeout: id => { if (timers[id - 1]) timers[id - 1].live = false; },
    timers, body
  };
  vm.createContext(context);
  vm.runInContext(`${toastSource}\nglobalThis.api = { showToast, toastHost, toastClearAll, toastReconcileAccount };`, context);
  return context;
}

test("the host keeps one persistent polite live region on <body>; a toast is a capsule with textContent only", () => {
  const ctx = host();
  ctx.api.showToast("<b>Hi</b>");
  const [region] = ctx.body.children;
  assert.equal(region.id, "toast-region");
  assert.equal(region.getAttribute("role"), "status");
  assert.equal(region.getAttribute("aria-live"), "polite");
  assert.equal(region.children.length, 1);
  assert.equal(region.children[0].children[0].textContent, "<b>Hi</b>");
  ctx.api.showToast("Again");
  assert.equal(ctx.body.children.length, 1, "the region is created once");
});

test("a replacement leaves the old toast (aria-hidden, inert, leaving) and the timeout dismisses the new one", () => {
  const ctx = host();
  ctx.api.showToast("One");
  const first = ctx.api.toastHost.element;
  ctx.api.showToast("Two");
  assert.ok(first.classes.has("toast-leaving"));
  assert.equal(first.getAttribute("aria-hidden"), "true");
  assert.equal(first.inert, true);
  assert.notEqual(ctx.api.toastHost.element, first);
  assert.equal(ctx.api.toastHost.state.current.text, "Two");
  const live = ctx.timers.filter(timer => timer.live && timer.ms >= 3900);
  assert.ok(live.length >= 1, "the 4s dismissal timer is armed");
});

test("tap dismisses; the action runs first and then dismisses", () => {
  const ctx = host();
  let ran = 0;
  ctx.api.showToast("Deleted", { action: { label: "Undo", onAction: () => { ran += 1; } } });
  const element = ctx.api.toastHost.element;
  assert.equal(element.children.length, 2);
  element.listeners.get("click")({ target: { closest: selector => (selector === ".toast-action" ? {} : null) } });
  assert.equal(ran, 1);
  assert.equal(ctx.api.toastHost.state.current, null);
  ctx.api.showToast("Plain");
  ctx.api.toastHost.element.listeners.get("click")({ target: { closest: () => null } });
  assert.equal(ran, 1);
  assert.equal(ctx.api.toastHost.state.current, null);
});

test("hover pauses, an account switch clears pending toasts at once, and a different profile never sees them", () => {
  const ctx = host();
  ctx.api.showToast("Mine");
  ctx.api.toastHost.element.listeners.get("pointerenter")({ pointerType: "mouse" });
  assert.deepEqual([...ctx.api.toastHost.state.pauses], ["hover"]);
  ctx.activeAccount = { id: "b" };
  ctx.api.toastReconcileAccount();
  assert.equal(ctx.api.toastHost.state.current, null);
  assert.equal(ctx.api.toastHost.region.children.length, 0);
  ctx.api.showToast("Theirs");
  assert.equal(ctx.api.toastHost.state.current.text, "Theirs");
});

test("without a DOM the host still tracks state and never throws", () => {
  const context = { Math, Number, String, Array, Object, Date, Map, sheetAccountKey: () => "", sheetPrefersReducedMotion: () => false, setTimeout: () => 1, clearTimeout() {}, document: {}, window: {} };
  vm.createContext(context);
  vm.runInContext(`${toastSource}\nglobalThis.api = { showToast, toastHost };`, context);
  context.api.showToast("No DOM");
  assert.equal(context.api.toastHost.state.current.text, "No DOM");
});

// ---- Source and style contracts ------------------------------------------------------------------
test("no screen template carries its own #toast; render() reconciles the account and runs the banner exit hooks", () => {
  assert.doesNotMatch(appSource, /id="toast"/);
  assert.doesNotMatch(appSource, /querySelector\(["']#toast["']\)/);
  assert.doesNotMatch(appSource, /toastTimer/);
  const render = slice("function render() {", "bannerExitAfterRender(leavingBanners);\n") + "bannerExitAfterRender(leavingBanners);\n";
  assert.match(render, /sheetEngineBeforeRender\(\);\s*toastReconcileAccount\(\);\s*const leavingBanners = bannerExitCapture\(\);/);
  assert.match(render, /finally \{\s*renderDateFormatters = previousDateFormatters;\s*bannerExitAfterRender\(leavingBanners\);/);
  assert.match(appSource, /toastClearAll\(\);\s*saveState\(\);\s*syncWebPushIfEnabled\(\);/, "a language switch clears pending toasts");
});

test("toast CSS: above the sheet, below nothing that matters, chip material with fallbacks, reduced motion is opacity only", () => {
  const rule = name => new RegExp(`${name.replace(/[.\\[\]]/g, "\\$&")} \\{([^}]*)\\}`).exec(cssSource)?.[1] ?? "";
  const zToast = Number(/z-index:\s*(\d+)/.exec(rule(".toast-region"))?.[1]);
  const zModal = Number(/z-index:\s*(\d+)/.exec(rule(".modal"))?.[1]);
  assert.equal(zToast, 60);
  assert.ok(zToast > zModal);
  assert.match(rule(".toast-region"), /bottom:\s*calc\(104px \+ env\(safe-area-inset-bottom\)\)/);
  assert.match(rule(".toast-region"), /max-width:\s*560px/);
  assert.match(rule(".toast"), /border-radius:\s*var\(--radius-capsule\)/);
  assert.match(rule(".toast"), /var\(--shadow-floating\)/);
  assert.match(rule(".toast-text"), /line-clamp:\s*2/);
  assert.match(cssSource, /\.toast \{\s*background: color-mix\(in srgb, var\(--surface-strong\) 70%, transparent\);\s*-webkit-backdrop-filter: blur\(14px\) saturate\(140%\);/);
  assert.match(cssSource, /:root\[data-theme="dark"\] \.toast \{ background: color-mix\(in srgb, var\(--surface-strong\) 66%, transparent\); \}/);
  assert.match(cssSource, /@media \(prefers-reduced-transparency: reduce\) \{\s*\.toast,[^}]*background: var\(--surface-strong\);[^}]*backdrop-filter: none;/);
  assert.match(cssSource, /@media \(prefers-reduced-motion: reduce\) \{\s*\.toast \{ animation: toast-fade-in 150ms linear backwards !important; \}/);
  assert.match(cssSource, /\.banner-exit \{ overflow: hidden; pointer-events: none; \}/);
  assert.doesNotMatch(cssSource, /^\.toast \{[^}]*var\(--sage\)/m);
});

test("the CSP-safe toast code never writes style attributes or inline style markup", () => {
  assert.doesNotMatch(toastSource + bannerSource, /setAttribute\(["']style["']|style="|cssText/);
});

test("both banners carry a kind marker, and their removal goes through the exit placeholder", () => {
  assert.match(appSource, /data-banner-kind="set" data-active-set-confirmation=/);
  assert.match(appSource, /data-banner-kind="batch" data-active-batch-undo=/);
  assert.match(appSource, /bannerExitBegin\(\{ node, kind: "set" \}\)/);
  assert.match(appSource, /bannerExitBegin\(\{ node, kind: "batch" \}\)/);
});

// ---- Banner exit glue against a tiny fake DOM ----------------------------------------------------
function fakeTree() {
  const make = tag => {
    const node = {
      tag, children: [], parentNode: null, attrs: new Map(), dataset: {}, isConnected: true, inert: false, className: "", offsetHeight: 0, animations: [],
      setAttribute(key, value) { node.attrs.set(key, String(value)); },
      removeAttribute(key) { node.attrs.delete(key); },
      appendChild(child) { child.parentNode = node; node.children.push(child); return child; },
      insertBefore(child, before) {
        child.parentNode?.children && (child.parentNode.children = child.parentNode.children.filter(item => item !== child));
        child.parentNode = node;
        const index = before ? node.children.indexOf(before) : -1;
        if (index < 0) node.children.push(child); else node.children.splice(index, 0, child);
        return child;
      },
      querySelectorAll: () => [],
      remove() { node.isConnected = false; if (node.parentNode) node.parentNode.children = node.parentNode.children.filter(item => item !== node); },
      animate(keyframes, options) { node.animations.push({ keyframes, options }); return { cancel() {} }; },
      getAnimations: () => []
    };
    return node;
  };
  return make;
}

function bannerContext({ reduced = false } = {}) {
  const make = fakeTree();
  const timers = [];
  const screen = make("div");
  const list = make("section");
  list.className = "active-workout-list";
  const banner = make("div");
  banner.dataset.bannerKind = "set";
  banner.offsetHeight = 52;
  banner.attrs.set("data-active-set-confirmation", "7");
  screen.appendChild(banner);
  screen.appendChild(list);
  const context = {
    Math, Number, String, Array, Object, Date, Map,
    app: {
      querySelectorAll: selector => (selector === "[data-banner-kind]" ? collect(context.app.root) : []),
      querySelector: selector => {
        if (selector === ".active-workout-list") return findClass(context.app.root, "active-workout-list");
        const kind = /data-banner-kind="(\w+)"/.exec(selector)?.[1];
        return kind ? collect(context.app.root).find(node => node.dataset.bannerKind === kind) || null : null;
      },
      root: screen
    },
    document: { createElement: tag => make(tag), body: make("body") },
    window: { getComputedStyle: () => ({ rowGap: "12px" }) },
    sheetAccountKey: () => "a",
    sheetPrefersReducedMotion: () => reduced,
    setTimeout: fn => { timers.push(fn); return timers.length; },
    clearTimeout() {},
    timers, make, screen, list, banner
  };
  const collect = node => node.children.flatMap(child => [...(child.dataset.bannerKind ? [child] : []), ...collect(child)]);
  const findClass = (node, name) => node.children.map(child => (child.className === name ? child : findClass(child, name))).find(Boolean) || null;
  vm.createContext(context);
  vm.runInContext(`${bannerSource}\nglobalThis.api = { bannerExitBegin, bannerExitCapture, bannerExitAfterRender, bannerExits };`, context);
  return context;
}

test("clearing a banner in place wraps it in a collapsing, inert placeholder that is removed when the timer fires", () => {
  const ctx = bannerContext();
  assert.equal(ctx.api.bannerExitBegin({ node: ctx.banner, kind: "set" }), true);
  const placeholder = ctx.screen.children[0];
  assert.equal(placeholder.className, "banner-exit");
  assert.equal(placeholder.children[0], ctx.banner);
  assert.equal(ctx.banner.attrs.has("data-active-set-confirmation"), false, "the leaving copy is no longer found as a live banner");
  assert.equal(ctx.banner.attrs.get("aria-hidden"), "true");
  assert.equal(ctx.banner.inert, true);
  assert.equal(placeholder.animations[0].options.duration, 200);
  assert.deepEqual({ ...placeholder.animations[0].keyframes[1] }, { height: "0px", marginBottom: "-12px" });
  assert.equal(ctx.banner.animations[0].options.duration, 90);
  ctx.timers[0]();
  assert.equal(ctx.screen.children.includes(placeholder), false);
  assert.equal(ctx.api.bannerExits.size, 0);
});

test("reduced motion removes the banner at once", () => {
  const ctx = bannerContext({ reduced: true });
  assert.equal(ctx.api.bannerExitBegin({ node: ctx.banner, kind: "set" }), false);
  assert.equal(ctx.screen.children.includes(ctx.banner), false);
  assert.equal(ctx.screen.children.some(child => child.className === "banner-exit"), false);
});

test("a render that drops the banner re-inserts a placeholder before the list; a replacement or a left screen does not", () => {
  const ctx = bannerContext();
  const captured = ctx.api.bannerExitCapture();
  assert.equal(captured.banners.length, 1);
  assert.equal(captured.banners[0].height, 52);
  // render(): #app is rebuilt, so the old nodes are disconnected and the new tree has the list but no banner.
  ctx.banner.isConnected = false;
  const fresh = ctx.make("div");
  const freshList = ctx.make("section");
  freshList.className = "active-workout-list";
  fresh.appendChild(freshList);
  ctx.app.root = fresh;
  ctx.api.bannerExitAfterRender(captured);
  assert.equal(fresh.children[0].className, "banner-exit");
  assert.equal(fresh.children[1], freshList);
  assert.equal(fresh.children[0].animations[0].options.duration, 200);

  // Another banner of the same kind replaces it: no exit.
  const replaced = bannerContext();
  const cap2 = replaced.api.bannerExitCapture();
  replaced.banner.isConnected = false;
  const next = replaced.make("div");
  const nextBanner = replaced.make("div");
  nextBanner.dataset.bannerKind = "set";
  const nextList = replaced.make("section");
  nextList.className = "active-workout-list";
  next.appendChild(nextBanner);
  next.appendChild(nextList);
  replaced.app.root = next;
  replaced.api.bannerExitAfterRender(cap2);
  assert.equal(next.children.length, 2);

  // Leaving the screen (no list): no exit.
  const left = bannerContext();
  const cap3 = left.api.bannerExitCapture();
  left.banner.isConnected = false;
  left.app.root = left.make("div");
  left.api.bannerExitAfterRender(cap3);
  assert.equal(left.app.root.children.length, 0);
});

test("a placeholder that is still collapsing survives the render and is re-attached before the list", () => {
  const ctx = bannerContext();
  ctx.api.bannerExitBegin({ node: ctx.banner, kind: "set" });
  const placeholder = ctx.screen.children[0];
  const captured = ctx.api.bannerExitCapture();
  const fresh = ctx.make("div");
  const freshList = ctx.make("section");
  freshList.className = "active-workout-list";
  fresh.appendChild(freshList);
  ctx.app.root = fresh;
  ctx.api.bannerExitAfterRender(captured);
  assert.equal(fresh.children[0], placeholder);
  assert.equal(ctx.api.bannerExits.size, 1);
});
