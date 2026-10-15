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

// The engine block from the constants to the gesture binding, evaluated with small fakes.
const engineSource = slice("const SHEET_ENTER_MS", "// Runs from bindEvents() once the new .modal exists.");

function fakeElement(name, children = {}) {
  const attrs = new Map();
  const classes = new Set();
  const element = {
    name, children, inert: false, removed: false, parent: null,
    classList: { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c) },
    setAttribute: (key, value) => attrs.set(key, value),
    removeAttribute: key => attrs.delete(key),
    attrs, classes,
    querySelector: selector => children[selector] || null,
    querySelectorAll: () => [],
    remove() { element.removed = true; if (element.parent) element.parent.list = element.parent.list.filter(item => item !== element); },
    animate: () => ({}),
    offsetHeight: 400
  };
  return element;
}

// primed: run one render hook first so the account key is established (the first ever render never makes a ghost).
function loadEngine({ activeAccount = { id: "a" }, modal = null, present = null, reduced = false, primed = true } = {}) {
  const body = { list: [], appendChild(element) { element.parent = body; body.list.push(element); } };
  const timers = [];
  const context = {
    Date, Math, Number, Array, Object, String, Boolean, Promise,
    activeAccount, modal, closeModalCalls: 0,
    closeModal() { context.closeModalCalls += 1; },
    app: { querySelector: selector => (selector === ".modal" ? context.present : null) },
    present,
    document: { body },
    window: {
      matchMedia: query => ({ matches: reduced && query.includes("reduced-motion") }),
      getComputedStyle: () => ({ transform: "none", opacity: "1" })
    },
    setTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearTimeout: () => {},
    timers
  };
  vm.createContext(context);
  vm.runInContext(`${engineSource}\nglobalThis.api = { sheetEngine, sheetDismissDecision, sheetDragOffset, sheetDragVelocity, sheetScrimProgress, sheetExitDurationMs, sheetEnterActive, sheetEngineBeforeRender, sheetDragDefersRender, dismissSheet, sheetRemoveGhost };`, context);
  if (primed) {
    const initial = context.present;
    context.present = null;
    context.api.sheetEngineBeforeRender();
    context.present = initial;
    context.api.sheetEngine.enterStart = null;
  }
  return { api: context.api, context, body, timers };
}

test("dismiss decision: velocity above 0.5 px/ms or travel above 40% dismisses, otherwise restore", () => {
  const { api } = loadEngine();
  assert.equal(api.sheetDismissDecision({ distance: 10, height: 500, velocity: 0.51 }), "dismiss");
  assert.equal(api.sheetDismissDecision({ distance: 10, height: 500, velocity: 0.5 }), "restore");
  assert.equal(api.sheetDismissDecision({ distance: 201, height: 500, velocity: 0 }), "dismiss");
  assert.equal(api.sheetDismissDecision({ distance: 200, height: 500, velocity: 0 }), "restore");
  assert.equal(api.sheetDismissDecision({ distance: 300, height: 500, velocity: -1 }), "dismiss", "distance alone is enough");
  assert.equal(api.sheetDismissDecision({ distance: -30, height: 500, velocity: -2 }), "restore");
  assert.equal(api.sheetDismissDecision({ distance: 50, height: 0, velocity: 0 }), "restore");
  assert.equal(api.sheetDismissDecision({}), "restore");
  assert.equal(api.sheetDismissDecision({ distance: NaN, height: NaN, velocity: NaN }), "restore");
});

test("drag offset is 1:1 downward and rubber-bands upward below the cap", () => {
  const { api } = loadEngine();
  assert.equal(api.sheetDragOffset(120), 120);
  assert.equal(api.sheetDragOffset(0), 0);
  const small = api.sheetDragOffset(-10);
  const large = api.sheetDragOffset(-1000);
  assert.ok(small < 0 && small > -10, "damped");
  assert.ok(large < small && large > -16, "approaches but never reaches the 16px cap");
  assert.equal(api.sheetDragOffset(NaN), 0);
});

test("drag velocity uses the last ~100ms of samples", () => {
  const { api } = loadEngine();
  assert.equal(api.sheetDragVelocity([]), 0);
  assert.equal(api.sheetDragVelocity([{ t: 0, y: 0 }]), 0);
  assert.equal(api.sheetDragVelocity([{ t: 0, y: 0 }, { t: 0, y: 50 }]), 0);
  // Slow start, then a fast last 50ms: the old samples fall outside the window.
  const samples = [{ t: 0, y: 0 }, { t: 100, y: 10 }, { t: 250, y: 20 }, { t: 300, y: 70 }];
  assert.equal(api.sheetDragVelocity(samples), (70 - 20) / 50);
  assert.ok(api.sheetDragVelocity([{ t: 0, y: 100 }, { t: 50, y: 60 }]) < 0, "upward is negative");
});

test("scrim progress follows travel and clamps", () => {
  const { api } = loadEngine();
  assert.equal(api.sheetScrimProgress(100, 400), 0.25);
  assert.equal(api.sheetScrimProgress(-20, 400), 0);
  assert.equal(api.sheetScrimProgress(900, 400), 1);
  assert.equal(api.sheetScrimProgress(10, 0), 0);
});

test("exit duration: 240ms from rest, shorter when partway down or fast, 90ms fade under reduced motion", () => {
  const { api } = loadEngine();
  assert.equal(api.sheetExitDurationMs(), 240);
  assert.equal(api.sheetExitDurationMs({ reduced: true, offset: 200, height: 400 }), 90);
  assert.ok(api.sheetExitDurationMs({ offset: 300, height: 400 }) < 240);
  const fast = api.sheetExitDurationMs({ offset: 100, height: 400, velocity: 2 });
  assert.ok(fast >= 120 && fast < 240);
});

function sheetFixture() {
  const panel = fakeElement("panel");
  const scrim = fakeElement("scrim");
  return fakeElement("modal", { ".modal-panel": panel, ".sheet-scrim": scrim });
}

test("closing a sheet moves it to a body ghost that is removed by the fallback timer", () => {
  const modalElement = sheetFixture();
  const { api, body, timers } = loadEngine({ modal: null, present: modalElement });
  api.sheetEngineBeforeRender();
  assert.equal(body.list.length, 1);
  assert.equal(body.list[0], modalElement);
  assert.ok(modalElement.classes.has("sheet-ghost"));
  assert.equal(modalElement.attrs.get("aria-hidden"), "true");
  assert.equal(modalElement.attrs.has("role"), false, "ghost is not a dialog");
  assert.equal(modalElement.inert, true);
  assert.equal(timers.length, 1);
  assert.ok(timers[0].ms >= 240);
  timers[0].fn();
  assert.equal(body.list.length, 0);
  assert.equal(api.sheetEngine.ghost, null);
});

test("a ghost is removed immediately when a new sheet opens, an account switches, or the account signs out", () => {
  for (const scenario of ["new-sheet", "account-switch", "sign-out"]) {
    const modalElement = sheetFixture();
    const harness = loadEngine({ modal: null, present: modalElement });
    harness.api.sheetEngineBeforeRender();
    assert.equal(harness.body.list.length, 1, `${scenario}: ghost created`);
    harness.context.present = null;
    if (scenario === "new-sheet") harness.context.modal = { type: "rename" };
    if (scenario === "account-switch") harness.context.activeAccount = { id: "b" };
    if (scenario === "sign-out") harness.context.activeAccount = null;
    harness.api.sheetEngineBeforeRender();
    assert.equal(harness.body.list.length, 0, `${scenario}: ghost gone at once`);
    assert.equal(harness.api.sheetEngine.ghost, null);
  }
});

test("no ghost is made when the account changed in the same render that closed the sheet", () => {
  const modalElement = sheetFixture();
  const harness = loadEngine({ modal: null, present: modalElement });
  harness.api.sheetEngineBeforeRender(); // establishes account key "a"
  harness.api.sheetRemoveGhost();
  const next = sheetFixture();
  harness.context.present = next;
  harness.context.activeAccount = { id: "b" };
  harness.api.sheetEngineBeforeRender();
  assert.equal(harness.body.list.length, 0);
  assert.equal(next.removed, true);
});

test("enter is flagged only for a newly opened sheet and for the 300ms after it", () => {
  const harness = loadEngine({ modal: { type: "rename" }, present: null });
  assert.equal(harness.api.sheetEnterActive(), false);
  harness.api.sheetEngineBeforeRender();
  assert.equal(harness.api.sheetEnterActive(), true);
  // Re-render of the same open sheet keeps the enter window; it does not restart it.
  const started = harness.api.sheetEngine.enterStart;
  harness.context.present = sheetFixture();
  harness.api.sheetEngineBeforeRender();
  assert.equal(harness.api.sheetEngine.enterStart, started);
  harness.context.modal = null;
  harness.context.present = null;
  harness.api.sheetEngineBeforeRender();
  assert.equal(harness.api.sheetEnterActive(), false);
});

test("an active drag defers render; dismissal only ever goes through closeModal", () => {
  const harness = loadEngine();
  assert.equal(harness.api.sheetDragDefersRender(), false);
  harness.api.sheetEngine.drag = { active: true };
  assert.equal(harness.api.sheetDragDefersRender(), true);
  assert.equal(harness.api.sheetEngine.deferredRender, true);
  harness.api.dismissSheet();
  assert.equal(harness.context.closeModalCalls, 1);
  assert.match(slice("function dismissSheet()", "// Runs from bindEvents()"), /^function dismissSheet\(\) \{\s*closeModal\(\);\s*\}\s*$/);
});

test("render hooks the engine, markup carries the scrim and enter class, and Esc/scrim route to dismissSheet", () => {
  assert.match(appSource, /if \(sheetDragDefersRender\(\)\) return;\s*sheetEngineBeforeRender\(\);/);
  assert.match(appSource, /<div class="modal\$\{sheetEnterActive\(\) \? " sheet-enter" : ""\}" role=/);
  assert.match(appSource, /<div class="sheet-scrim" aria-hidden="true"><\/div><section class="modal-panel/);
  assert.match(appSource, /event\.target\?\.classList\?\.contains\("sheet-scrim"\)\) dismissSheet\(\)/);
  assert.match(appSource, /event\.key === "Escape" && !event\.defaultPrevented && modal && app\.querySelector\?\.\("\.modal"\)/);
  assert.match(appSource, /setPointerCapture/);
  // CSP is style-src 'self': the engine styles elements through CSSOM only.
  assert.doesNotMatch(engineSource, /style="/);
  assert.doesNotMatch(engineSource, /\.innerHTML|cssText|setAttribute\("style"/);
});

test("sheet CSS: enter/exit, scrim, overscroll containment, material and fallbacks", () => {
  assert.match(cssSource, /\.modal\.sheet-enter \.modal-panel \{\s*animation: sheet-rise 300ms cubic-bezier\(0\.2, 0\.9, 0\.1, 1\)/);
  assert.match(cssSource, /\.modal\.sheet-enter \.sheet-scrim \{\s*animation: sheet-fade-in 150ms/);
  assert.match(cssSource, /\.sheet-scrim \{[^}]*opacity: calc\(1 - var\(--sheet-progress, 0\)\)/);
  assert.match(cssSource, /\.modal \{[^}]*overscroll-behavior: contain/);
  assert.match(cssSource, /\.modal-panel \{[^}]*overscroll-behavior: contain/);
  assert.match(cssSource, /backdrop-filter: blur\(28px\) saturate\(160%\)/);
  assert.match(cssSource, /@supports not \(\(backdrop-filter: blur\(1px\)\) or \(-webkit-backdrop-filter: blur\(1px\)\)\) \{[^}]*background: var\(--surface-strong\)/);
  assert.match(cssSource, /@media \(prefers-reduced-transparency: reduce\) \{\s*\.modal-panel,[^}]*background: var\(--surface-strong\);[^}]*backdrop-filter: none/);
  const reduced = cssSource.match(/@media \(prefers-reduced-motion: reduce\) \{\s*\.modal\.sheet-enter \.modal-panel \{[^}]*\}[\s\S]*?\n\}/)?.[0] || "";
  assert.match(reduced, /sheet-fade-in 150ms linear[^;]*!important/);
  assert.doesNotMatch(reduced, /sheet-rise/);
  assert.match(cssSource, /--scrim: rgba\(7, 19, 33, 0\.4\)/);
  assert.match(cssSource, /--scrim: rgba\(0, 0, 0, 0\.56\)/);
  assert.match(cssSource, /\.sheet-handle::after \{[^}]*width: 36px;[^}]*height: 5px;/);
});

test("the dragging rules come after the enter rules so a running enter animation cannot fight the finger", () => {
  const enter = cssSource.indexOf(".modal.sheet-enter .modal-panel {");
  const reduced = cssSource.lastIndexOf(".modal.sheet-enter .sheet-scrim {");
  const dragging = cssSource.indexOf(".modal.sheet-dragging .modal-panel {");
  assert.ok(enter > 0 && dragging > reduced && reduced > enter);
  assert.match(cssSource, /\.modal\.sheet-dragging \.modal-panel \{\s*animation: none !important;/);
  assert.match(cssSource, /\.modal\.sheet-dragging \.sheet-scrim \{ animation: none !important; \}/);
});
