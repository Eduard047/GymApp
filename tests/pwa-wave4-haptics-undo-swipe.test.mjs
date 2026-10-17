import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const source = await readFile("pwa/app.js", "utf8");
const between = (from, to) => {
  const start = source.indexOf(from);
  assert.notEqual(start, -1, `missing ${from}`);
  const end = source.indexOf(to, start);
  assert.notEqual(end, -1, `missing ${to}`);
  return source.slice(start, end);
};

test("the shipped bundles are byte copies of the working files", async () => {
  assert.equal(source, await readFile("pwa/app.v143.js", "utf8"));
  assert.equal(await readFile("pwa/styles.css", "utf8"), await readFile("pwa/styles.v111.css", "utf8"));
});

// Haptics gate.
const hapticsSource = between("const HAPTIC_PATTERNS", "function flushRecordSetHaptic()");

function hapticsContext({ stored = null, vibrate = true, throwStorage = false } = {}) {
  const calls = [];
  const writes = [];
  const context = vm.createContext({
    Date,
    Array,
    localStorage: {
      getItem() { if (throwStorage) throw new Error("blocked"); return stored; },
      setItem(key, value) { if (throwStorage) throw new Error("blocked"); writes.push([key, value]); stored = value; },
      removeItem(key) { if (throwStorage) throw new Error("blocked"); writes.push([key, null]); stored = null; }
    },
    navigator: vibrate ? { vibrate(pattern) { calls.push(pattern); return true; } } : {}
  });
  vm.runInContext(hapticsSource, context);
  return { context, calls, writes };
}

test("haptics default to on and only an explicit off value disables them", () => {
  const { context } = hapticsContext();
  for (const [raw, expected] of [[null, true], ["off", false], ["on", true], ["", true], ["0", true], [undefined, true]]) {
    assert.equal(vm.runInContext(`hapticsEnabledFromStored(${JSON.stringify(raw ?? null)})`, context), expected);
  }
});

test("the haptic helper vibrates while enabled and is silent once the switch is off", () => {
  const { context, calls, writes } = hapticsContext();
  assert.equal(vm.runInContext(`haptic("undo")`, context), true);
  assert.deepEqual(calls, [8]);
  assert.equal(vm.runInContext("setHapticsEnabled(false)", context), false);
  assert.deepEqual(writes.at(-1), ["gym-pwa-haptics-v1", "off"]);
  assert.equal(vm.runInContext(`haptic("pr")`, context), false);
  assert.deepEqual(calls, [8], "no vibration while off");
  assert.equal(vm.runInContext("setHapticsEnabled(true)", context), true);
  assert.deepEqual(writes.at(-1), ["gym-pwa-haptics-v1", null], "on is stored as the absence of a value");
  assert.equal(vm.runInContext(`haptic("pr")`, context), true);
});

test("a stored off preference is honored on load and unreadable storage keeps haptics on", () => {
  const off = hapticsContext({ stored: "off" });
  assert.equal(vm.runInContext(`haptic("undo")`, off.context), false);
  assert.deepEqual(off.calls, []);
  const blocked = hapticsContext({ throwStorage: true });
  assert.equal(vm.runInContext(`haptic("undo")`, blocked.context), true);
  assert.equal(vm.runInContext("setHapticsEnabled(false)", blocked.context), false, "the choice still applies this session");
  assert.equal(vm.runInContext(`haptic("undo")`, blocked.context), false);
  const none = hapticsContext({ vibrate: false });
  assert.equal(vm.runInContext(`haptic("undo")`, none.context), false);
});

test("every navigator.vibrate call goes through the one gated helper", () => {
  const calls = source.match(/navigator\.vibrate\s*\(/g) || [];
  assert.equal(calls.length, 1);
  const helper = between("function haptic(kind) {", "function flushRecordSetHaptic()");
  assert.match(helper, /navigator\.vibrate\(/);
  assert.match(helper, /if \(!hapticsEnabled\(\)\) return false;/);
  assert.ok(helper.indexOf("hapticsEnabled()") < helper.indexOf("navigator.vibrate("));
  assert.equal(/\.vibrate\s*\(/.test(source.replace(helper, "")), false);
});

test("the Profile settings expose the Haptics switch with the localized label and switch semantics", () => {
  const row = between("function profileHapticsRow()", "function accountIdentityValue()");
  assert.match(row, /tx3\("Haptics", "Тактильний відгук", "Тактильный отклик"\)/);
  assert.match(row, /role="switch" aria-checked="\$\{on\}"/);
  assert.match(row, /action: "toggle-haptics"/);
  assert.match(source, /profileLanguageRow\(\), profileHapticsRow\(\), trainingSettingsProfilePanel\(\)/);
  assert.match(source, /if \(action === "toggle-haptics"\) \{[\s\S]*?setHapticsEnabled\(!hapticsEnabled\(\)\)/);
});

// Pending-set Undo wiring (guard behavior is covered in pwa-active-workout.test.mjs).
test("deleting a pending set offers a 6 s Undo toast and a recorded-set delete keeps its confirm sheet", () => {
  const remove = between("async function deleteActiveWorkoutSet(", "function restoredPendingSetWorkout(");
  assert.match(remove, /if \(!location\.set\.completed\) \{\s*deletedPendingSet = \{/);
  assert.match(remove, /if \(result\.value === true && deletedPendingSet\) offerPendingSetUndo\(deletedPendingSet\)/);
  const offer = between("function offerPendingSetUndo(", "async function restoreDeletedPendingSet(");
  assert.match(offer, /tx3\("Set deleted", "Підхід видалено", "Подход удалён"\)/);
  assert.match(offer, /tx3\("Undo", "Скасувати", "Отменить"\)/);
  assert.match(source, /const TOAST_ACTION_DURATION_MS = 6000;/);
  assert.match(source, /action === "request-delete-active-set"[\s\S]*?requestDeleteActiveSet\(/);
  assert.match(source, /type: "confirm-delete-active-set"/);
  const restore = between("async function restoreDeletedPendingSet(", "function canRemoveActiveExercise(");
  assert.match(restore, /liveWorkoutBinding\?\.localWorkoutId === loaded\.workout\.id/);
  assert.match(restore, /haptic\("undo"\)/);
});

// Tracked page swipe decisions.
const swipeSource = between("const PAGE_SWIPE_LOCK_SLOP", "function pageSwipeReducedMotion()");
const swipeContext = vm.createContext({ Math, workoutHistoryPeriod: "week", workoutWeekOffset: 0, monthOffsets: { workouts: 0 } });
vm.runInContext(swipeSource, swipeContext);
const swipe = (code, vars = {}) => {
  Object.assign(swipeContext, vars);
  return vm.runInContext(code, swipeContext);
};

test("the swipe locks to an axis only after the slop and with a horizontal bias", () => {
  assert.equal(swipe("pageSwipeLockAxis(5, 2)"), null);
  assert.equal(swipe("pageSwipeLockAxis(12, 3)"), "x");
  assert.equal(swipe("pageSwipeLockAxis(-12, 3)"), "x");
  assert.equal(swipe("pageSwipeLockAxis(3, 12)"), "y");
  assert.equal(swipe("pageSwipeLockAxis(10, 9)"), "y", "needs more than 1.2x vertical to own the gesture");
});

test("the page follows the pointer 1:1 toward a page and rubber-bands where there is none", () => {
  assert.equal(swipe("pageSwipeDisplacement(120, 400, true, true)"), 120);
  assert.equal(swipe("pageSwipeDisplacement(-120, 400, true, true)"), -120);
  assert.equal(swipe("pageSwipeDisplacement(900, 400, true, true)"), 400, "never past the page width");
  const banded = swipe("pageSwipeDisplacement(-300, 400, true, false)");
  assert.ok(banded < 0 && banded > -300 * 0.55, `damped, got ${banded}`);
  assert.ok(swipe("pageSwipeDisplacement(-3000, 400, true, false)") > -400, "bounded by the width");
  assert.equal(swipe("pageSwipeDisplacement(0, 400, true, true)"), 0);
  assert.equal(swipe("pageSwipeDisplacement(50, 0, true, true)"), 0);
});

test("a release commits at 40% of the width or a flick with the drag, never against it", () => {
  const commit = (t, v, prev = true, next = true) => swipe(`pageSwipeCommitDirection(${t}, ${v}, 400, ${prev}, ${next})`);
  assert.equal(commit(160, 0), "previous", "exactly 40%");
  assert.equal(commit(159, 0), null);
  assert.equal(commit(-170, 0), "next");
  assert.equal(commit(30, 0.6), "previous", "flick with the drag");
  assert.equal(commit(-30, -0.6), "next");
  assert.equal(commit(30, 0.5), null, "0.5 px/ms is not above the flick speed");
  assert.equal(commit(250, -0.8), null, "a flick against the drag springs back");
  assert.equal(commit(200, 0, false, true), null, "no previous page");
  assert.equal(commit(-200, 0, true, false), null, "no next page");
  assert.equal(commit(0, 2), null);
});

test("pointer velocity comes from the recent samples in px per ms", () => {
  assert.equal(swipe("pageSwipeVelocity([], 100)"), 0);
  assert.equal(swipe("pageSwipeVelocity([{ t: 90, x: 0 }], 100)"), 0);
  assert.equal(swipe("pageSwipeVelocity([{ t: 0, x: 0 }, { t: 100, x: 600 }], 100)"), 6);
  assert.equal(swipe("pageSwipeVelocity([{ t: 0, x: 0 }, { t: 150, x: 40 }, { t: 190, x: 80 }], 200)"), 1, "samples older than 100 ms are ignored");
  assert.equal(swipe("pageSwipeVelocity([{ t: 150, x: 80 }, { t: 190, x: 40 }], 200)"), -1, "direction follows the pointer");
});

test("history page steps respect the bounds of the week and month ranges", () => {
  assert.equal(swipe("applyHistoryPageStep('next')", { workoutHistoryPeriod: "week", workoutWeekOffset: 0 }), false);
  assert.equal(swipe("applyHistoryPageStep('previous')"), true);
  assert.equal(swipeContext.workoutWeekOffset, -1);
  assert.equal(swipe("applyHistoryPageStep('next')"), true);
  assert.equal(swipeContext.workoutWeekOffset, 0);
  assert.equal(swipe("applyHistoryPageStep('previous')", { workoutWeekOffset: -5200 }), false);
  swipeContext.monthOffsets.workouts = 0;
  assert.equal(swipe("applyHistoryPageStep('previous')", { workoutHistoryPeriod: "month" }), true);
  assert.equal(swipeContext.monthOffsets.workouts, -1);
  assert.equal(swipe("applyHistoryPageStep('previous')", { monthOffsets: { workouts: -1200 } }), false);
  assert.deepEqual(JSON.parse(JSON.stringify(swipe("historyPageBounds()", { monthOffsets: { workouts: -3 } }))), { canPrevious: true, canNext: true });
});

test("the swipe controller uses pointer events with capture, an edge inset and a no-tracking reduced-motion path", () => {
  const controller = between("function beginPageSwipe(", "function inertModalBackground(");
  assert.match(controller, /event\.clientX < PAGE_SWIPE_EDGE_INSET/);
  assert.match(controller, /setPointerCapture\(event\.pointerId\)/);
  assert.match(controller, /if \(swipe\.reduced\) return;/);
  assert.match(controller, /PAGE_SWIPE_FADE_OUT_MS/);
  assert.match(controller, /finishPageSwipePending\(\);\s*card = app\.querySelector/, "an interrupting touch finishes the pending change first");
  assert.match(source, /const PAGE_SWIPE_FADE_OUT_MS = 90;/);
  assert.match(source, /const PAGE_SWIPE_FADE_IN_MS = 150;/);
  assert.match(source, /app\.addEventListener\("pointermove", movePageSwipe/);
  assert.equal(/Math\.abs\(deltaX\) < 72/.test(source), false, "the 72 px non-tracking swipe is gone");
});

test("the stylesheet keeps vertical scrolling on the history panel and styles the switch", async () => {
  const styles = await readFile("pwa/styles.css", "utf8");
  assert.match(styles, /\.training-history \{[^}]*touch-action: pan-y;/);
  assert.match(styles, /\.training-history\.swiping \{[^}]*user-select: none;/);
  assert.match(styles, /\.settings-switch\.on i \{ transform: translateX\(20px\); \}/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\) \{\s*\.settings-switch/);
});
