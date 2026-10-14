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

// Pure helpers only: the haptic helper and the stepper hold schedule, evaluated without the rest of the app.
const helperSource = [
  slice("const HAPTIC_PATTERNS", "function flushRecordSetHaptic"),
  slice("const STEPPER_HOLD_SCHEDULE", "function stepperStepFeedback")
].join("\n");

function loadHelpers({ navigator, now = () => 0 } = {}) {
  const context = { navigator, Date: { now: () => now() }, Array, Object, Number, Math, Infinity };
  vm.createContext(context);
  vm.runInContext(`${helperSource}\nglobalThis.api = { haptic, stepperRepeatNextAtMs, STEPPER_HOLD_SCHEDULE, HAPTIC_PATTERNS, msUntilNextTimerTick, armEnterAnimation, enterAnimationFor, takePending: () => { const p = pendingEnterAnimation; pendingEnterAnimation = null; return p; } };`, context);
  return context.api;
}

test("stepper hold schedule: first repeat at 350 ms, 8 steps/s, 16 steps/s after 1.5 s", () => {
  const { stepperRepeatNextAtMs } = loadHelpers({ navigator: {} });
  const times = [];
  for (let at = stepperRepeatNextAtMs(null); at <= 3000; at = stepperRepeatNextAtMs(at)) times.push(at);
  assert.equal(times[0], 350);
  assert.equal(times[1] - times[0], 125);
  const slow = times.filter(at => at <= 1500);
  assert.ok(slow.length > 1);
  assert.ok(slow.slice(1).every((at, index) => at - slow[index] === 125), "8 steps/s before 1.5 s");
  const fast = times.filter(at => at >= 1500);
  assert.ok(fast.length > 3);
  assert.ok(fast.slice(1).every((at, index) => at - fast[index] === 62.5), "16 steps/s from 1.5 s");
  // Between 0 and 1 s: 1 + floor((1000 - 350) / 125) = 6 steps.
  assert.equal(times.filter(at => at <= 1000).length, 6);
});

test("haptic helper maps kinds to the DESIGN.md vibrate patterns", () => {
  const calls = [];
  const { haptic } = loadHelpers({ navigator: { vibrate: pattern => { calls.push(pattern); return true; } } });
  for (const kind of ["record", "pr", "undo", "destructive", "error"]) assert.equal(haptic(kind), true);
  assert.equal(JSON.stringify(calls), JSON.stringify([15, [20, 40, 20], 8, 30, [30, 50, 30]]));
  assert.equal(haptic("unknown"), false);
  assert.equal(calls.length, 5);
});

test("stepper tick haptic is throttled to at most 10 per second", () => {
  let clock = 1000;
  const calls = [];
  const { haptic } = loadHelpers({ navigator: { vibrate: pattern => { calls.push(pattern); return true; } }, now: () => clock });
  for (let i = 0; i < 20; i += 1) { // 16 steps/s for ~1.25 s
    haptic("tick");
    clock += 62.5;
  }
  assert.ok(calls.every(pattern => pattern === 6));
  assert.ok(calls.length <= 13 && calls.length >= 10, `ticks: ${calls.length}`);
});

test("haptic helper is a silent no-op without the Vibration API or when vibrate throws", () => {
  assert.equal(loadHelpers({ navigator: {} }).haptic("record"), false);
  assert.equal(loadHelpers({ navigator: undefined }).haptic("pr"), false);
  const throwing = loadHelpers({ navigator: { vibrate() { throw new Error("blocked"); } } });
  assert.equal(throwing.haptic("undo"), false);
});

test("PR haptic replaces the record-set haptic and the old 40 ms vibrate is gone", () => {
  assert.ok(!appSource.includes("navigator.vibrate?.(40)"));
  const notify = slice("function notifyNewPersonalRecords", "function personalRecordBadgeMarkup");
  assert.ok(notify.includes('recordSetHapticPending = false;') && notify.includes('haptic("pr")'));
  const record = slice("async function recordActiveSet", "// Undoes one recorded set");
  assert.ok(record.indexOf("recordSetHapticPending = true") < record.indexOf("flushRecordSetHaptic()"));
});

test("press feedback and hover rules in styles.css", () => {
  assert.ok(!/\.button:not\(:disabled\):active\s*\{\s*transform:\s*translateY/.test(cssSource));
  assert.ok(!/\.buttonlike:active\s*\{\s*transform:\s*translateY/.test(cssSource));
  assert.match(cssSource, /\.active-set-step:not\(:disabled\):active,[\s\S]*?\{\s*transform: scale\(0\.97\);\s*transition: transform 100ms ease-out;/);
  assert.match(cssSource, /\.tab-button:active \.tab-icon \{\s*transform: scale\(0\.92\)/);
  assert.match(cssSource, /html \{\s*touch-action: manipulation;/);
  // Reduced motion: opacity instead of scale.
  const reduced = cssSource.slice(cssSource.indexOf(".focus-lens-action:active { transform: none; }"));
  assert.match(reduced.slice(0, 900), /transform: none;\s*opacity: 0\.7;/);
  // Every :hover rule sits inside a hover-capable media query.
  let depthStack = [];
  const lines = cssSource.split("\n");
  let unwrapped = 0;
  for (const line of lines) {
    const t = line.trim();
    if (/^@media \(hover: hover\) and \(pointer: fine\) \{/.test(t)) depthStack.push("hover");
    else if (t.startsWith("@") && t.endsWith("{")) depthStack.push("other");
    const opens = (line.match(/\{/g) || []).length;
    const closes = (line.match(/\}/g) || []).length;
    if (line.includes(":hover") && !depthStack.includes("hover") && !t.startsWith("/*")) unwrapped += 1;
    if (t === "}" && depthStack.length && closes > opens) depthStack.pop();
  }
  assert.equal(unwrapped, 0, "unwrapped :hover rules");
});

test("hold gesture repeats through the shared step function, survives a replaced button, and swallows the release click", () => {
  const holdSource = slice("const STEPPER_HOLD_SCHEDULE", "function handleActiveSetContextMenu");
  let clock = 0;
  const timers = [];
  const steps = [];
  let limit = Infinity;
  const makeButton = () => ({
    isConnected: true,
    disabled: false,
    dataset: { action: "active-step-weight", dir: "1", id: "7" },
    setPointerCapture() {},
    closest(selector) { return selector.includes("active-set-step") ? this : null; }
  });
  let button = makeButton();
  const context = {
    Date: { now: () => clock },
    setTimeout: (fn, delay) => { timers.push({ fn, at: clock + delay }); return timers.length; },
    clearTimeout: id => { if (timers[id - 1]) timers[id - 1].fn = null; },
    Number, Boolean, Math, Object,
    app: { querySelectorAll: () => [button] },
    eventTargetElement: event => event.target,
    haptic: () => true,
    applyActiveStep: (id, field, dir) => { if (steps.length >= limit) return false; steps.push({ id, field, dir }); return true; },
    applyDraftStep: () => false,
    applySavedStep: () => false
  };
  vm.createContext(context);
  vm.runInContext(`${holdSource}\nglobalThis.api = { beginStepperHold, endStepperHold, swallowStepperHoldClick, hold: () => stepperHold };`, context);
  const advance = ms => {
    const end = clock + ms;
    for (;;) {
      const next = timers.filter(t => t.fn).sort((a, b) => a.at - b.at)[0];
      if (!next || next.at > end) break;
      clock = Math.max(clock, next.at);
      const fn = next.fn; next.fn = null; fn();
    }
    clock = end;
  };
  const { beginStepperHold, endStepperHold, swallowStepperHoldClick, hold } = context.api;

  beginStepperHold({ pointerId: 1, button: 0, target: button });
  advance(349);
  assert.equal(steps.length, 0, "a short press leaves the single step to the click");
  advance(1);
  assert.equal(steps.length, 1, "first repeat at 350 ms");
  advance(125 * 3);
  assert.equal(steps.length, 4);
  // A render replaces the pressed button: the hold re-acquires the new element and keeps repeating.
  button.isConnected = false;
  button = makeButton();
  advance(125);
  assert.equal(steps.length, 5);
  assert.equal(hold().button, button);
  assert.deepEqual(JSON.parse(JSON.stringify(steps[0])), { id: 7, field: "weight", dir: 1 });
  endStepperHold(true);
  const before = steps.length;
  assert.equal(swallowStepperHoldClick({ target: button, preventDefault() {}, stopPropagation() {} }), true);
  assert.equal(swallowStepperHoldClick({ target: button }), false, "only the one release click is swallowed");
  advance(1000);
  assert.equal(steps.length, before, "release stops the repeat");

  // Reaching the limit stops repeating but the click is still swallowed; a plain tap is not.
  steps.length = 0; limit = 2; clock += 10000;
  beginStepperHold({ pointerId: 2, button: 0, target: button });
  advance(2000);
  assert.equal(steps.length, 2);
  endStepperHold(true);
  assert.equal(swallowStepperHoldClick({ target: button, preventDefault() {}, stopPropagation() {} }), true);
  limit = Infinity; clock += 10000;
  beginStepperHold({ pointerId: 3, button: 0, target: button });
  advance(100);
  endStepperHold(true);
  assert.equal(swallowStepperHoldClick({ target: button }), false, "a tap keeps its click");
});

test("rest-end haptic is the DESIGN.md pattern and fires through the helper", () => {
  const calls = [];
  const { haptic, HAPTIC_PATTERNS } = loadHelpers({ navigator: { vibrate: pattern => { calls.push(pattern); return true; } } });
  assert.equal(JSON.stringify(HAPTIC_PATTERNS.restEnd), JSON.stringify([60, 80, 60]));
  assert.equal(haptic("restEnd"), true);
  assert.equal(JSON.stringify(calls), JSON.stringify([[60, 80, 60]]));
});

test("rest timer ticks align to the next whole-second boundary of the nearest deadline", () => {
  const { msUntilNextTimerTick } = loadHelpers({ navigator: {} });
  assert.equal(msUntilNextTimerTick(10_000, []), 1000, "no rest: plain 1 s cadence");
  assert.equal(msUntilNextTimerTick(10_000, [10_000 + 5_300]), 300);
  assert.equal(msUntilNextTimerTick(10_000, [10_000 + 5_000]), 1000, "exactly on a boundary waits a full second");
  assert.equal(msUntilNextTimerTick(10_000, [10_000 + 5_300, 10_000 + 7_900]), 300, "nearest boundary wins");
  assert.equal(msUntilNextTimerTick(10_000, [10_000 - 1, Number.NaN]), 1000, "expired and invalid deadlines are ignored");
  assert.equal(msUntilNextTimerTick(10_000, [10_000 + 3_005]), 20, "never busy-loops");
});

test("enter animation marker is one-shot per kind and carries its details", () => {
  const { armEnterAnimation, enterAnimationFor, takePending } = loadHelpers({ navigator: {} });
  assert.equal(enterAnimationFor("set-record"), null);
  armEnterAnimation("set-record", { setId: 7, previousCompleted: 2 });
  assert.equal(enterAnimationFor("live-panel"), null);
  assert.equal(enterAnimationFor("set-record").setId, 7);
  assert.equal(takePending().kind, "set-record");
  assert.equal(enterAnimationFor("set-record"), null);
});

test("render clears the marker in finally and entry animations key off data-enter only", () => {
  const render = slice("function render() {", "function settleActiveRingProgress");
  assert.match(render, /finally\s*\{[\s\S]*pendingEnterAnimation = null;/);
  for (const selector of [
    ".active-live-participant-panel[data-enter]:not([hidden])",
    ".active-set-confirmation[data-enter]",
    ".active-set-check[data-enter]",
    ".active-set-row.current[data-enter]"
  ]) assert.ok(cssSource.includes(selector), selector);
  assert.doesNotMatch(cssSource, /\.active-live-participant-panel:not\(\[hidden\]\)\s*\{\s*animation/);
  const reduced = cssSource.slice(cssSource.lastIndexOf("@media (prefers-reduced-motion: reduce) {\n  *,"));
  assert.match(reduced, /active-set-check\[data-enter\][\s\S]*active-enter-fade 150ms/);
  assert.match(reduced, /\.active-set-rest\.rest-ended \.active-set-rest-time \{ animation: none; \}/);
});
