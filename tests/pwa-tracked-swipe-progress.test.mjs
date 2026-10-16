import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const source = await readFile("pwa/app.js", "utf8");
const styles = await readFile("pwa/styles.css", "utf8");

const between = (from, to) => {
  const start = source.indexOf(from);
  assert.notEqual(start, -1, `missing ${from}`);
  const end = source.indexOf(to, start);
  assert.notEqual(end, -1, `missing ${to}`);
  return source.slice(start, end);
};

const plain = value => JSON.parse(JSON.stringify(value));

test("the shipped bundles are byte copies of the working files", async () => {
  assert.equal(source, await readFile("pwa/app.v138.js", "utf8"));
  assert.equal(styles, await readFile("pwa/styles.v106.css", "utf8"));
});

// Pure decisions plus the page rules of every navigator, evaluated in isolation.
const rulesSource = between("const PAGE_SWIPE_LOCK_SLOP", "function pageSwipeReducedMotion()");

function rulesContext(state = {}) {
  const context = vm.createContext({
    Math,
    Object,
    workoutHistoryPeriod: "week",
    workoutWeekOffset: 0,
    monthOffsets: { workouts: 0, progress: 0 },
    trainingReviewOffset: 0,
    activeMonthScope: () => "progress",
    ...state
  });
  vm.runInContext(rulesSource, context);
  return context;
}

const run = (context, code) => vm.runInContext(code, context);

test("one generalized controller serves the history panel, the weekly review and the progress months", () => {
  const context = rulesContext();
  const targets = plain(run(context, "PAGE_SWIPE_TARGETS.map(({ selector }) => selector)"));
  assert.deepEqual(targets, [".training-history", ".training-week-review", ".activity-heatmap-card, .progress-month-swipe"]);
  assert.equal(run(context, "Object.isFrozen(PAGE_SWIPE_TARGETS)"), true);
  assert.equal(run(context, "PAGE_SWIPE_TARGETS[0].step === applyHistoryPageStep && PAGE_SWIPE_TARGETS[0].bounds === historyPageBounds"), true);
  assert.equal(run(context, "PAGE_SWIPE_TARGETS[1].step === applyWeeklyReviewPageStep && PAGE_SWIPE_TARGETS[1].bounds === weeklyReviewPageBounds"), true);
  assert.equal(run(context, "PAGE_SWIPE_TARGETS[2].step === applyProgressMonthPageStep && PAGE_SWIPE_TARGETS[2].bounds === progressMonthPageBounds"), true);
  // No second controller: one set of listeners and one pointer-state holder.
  assert.equal((source.match(/addEventListener\("pointermove", movePageSwipe/g) || []).length, 1);
  assert.equal((source.match(/addEventListener\("pointerdown", beginPageSwipe/g) || []).length, 1);
  assert.equal((source.match(/let pageSwipe = null;/g) || []).length, 1);
  assert.equal(/HistorySwipe|historySwipe/.test(source), false, "no leftover history-only controller names");
});

test("the weekly review swipe uses the same limits as its buttons", () => {
  const context = rulesContext();
  assert.deepEqual(plain(run(context, "weeklyReviewPageBounds()")), { canPrevious: true, canNext: false });
  assert.equal(run(context, "applyWeeklyReviewPageStep('next')"), false, "no week after the current one");
  assert.equal(context.trainingReviewOffset, 0);
  assert.equal(run(context, "applyWeeklyReviewPageStep('previous')"), true);
  assert.equal(context.trainingReviewOffset, -1);
  assert.equal(run(context, "applyWeeklyReviewPageStep('next')"), true);
  assert.equal(context.trainingReviewOffset, 0);
  context.trainingReviewOffset = -520;
  assert.equal(run(context, "applyWeeklyReviewPageStep('previous')"), false, "the button range ends at -520");
  assert.equal(context.trainingReviewOffset, -520);
  assert.deepEqual(plain(run(context, "weeklyReviewPageBounds()")), { canPrevious: false, canNext: true });
  context.trainingReviewOffset = -519;
  assert.equal(run(context, "applyWeeklyReviewPageStep('previous')"), true);
  assert.equal(context.trainingReviewOffset, -520);
  // The buttons enforce the identical range.
  assert.match(source, /trainingReviewOffset <= -520 \? "disabled" : ""/);
  assert.match(source, /trainingReviewOffset === 0 \? "disabled" : ""/);
  assert.match(source, /offset >= -520 && offset <= 0\) \{ trainingReviewOffset = offset/);
});

test("the progress month swipe uses the scope and the limits of the month buttons", () => {
  const context = rulesContext();
  assert.deepEqual(plain(run(context, "progressMonthPageBounds()")), { canPrevious: true, canNext: false });
  assert.equal(run(context, "applyProgressMonthPageStep('next')"), false, "no month after the current one");
  assert.equal(context.monthOffsets.progress, 0);
  assert.equal(run(context, "applyProgressMonthPageStep('previous')"), true);
  assert.equal(context.monthOffsets.progress, -1);
  assert.equal(context.monthOffsets.workouts, 0, "the Today month is untouched");
  assert.equal(run(context, "applyProgressMonthPageStep('next')"), true);
  assert.equal(context.monthOffsets.progress, 0);
  context.monthOffsets.progress = -1200;
  assert.equal(run(context, "applyProgressMonthPageStep('previous')"), false);
  assert.equal(context.monthOffsets.progress, -1200);
  context.monthOffsets.progress = -1199;
  assert.equal(run(context, "applyProgressMonthPageStep('previous')"), true);
  assert.equal(context.monthOffsets.progress, -1200);
  // Follows the same scope the chevron buttons resolve.
  const scoped = rulesContext({ activeMonthScope: () => "workouts" });
  assert.equal(run(scoped, "applyProgressMonthPageStep('previous')"), true);
  assert.equal(scoped.monthOffsets.workouts, -1);
  assert.equal(scoped.monthOffsets.progress, 0);
  assert.match(source, /action === "month-prev"\) \{ monthOffsets\[activeMonthScope\(\)\] = Math\.max\(-1200,/);
  assert.match(source, /action === "month-next"\) \{ monthOffsets\[activeMonthScope\(\)\] = Math\.min\(0,/);
});

test("the history panel keeps its week and month rules", () => {
  const context = rulesContext();
  assert.equal(run(context, "applyHistoryPageStep('next')"), false);
  assert.equal(run(context, "applyHistoryPageStep('previous')"), true);
  assert.equal(context.workoutWeekOffset, -1);
  context.workoutWeekOffset = -5200;
  assert.equal(run(context, "applyHistoryPageStep('previous')"), false);
  context.workoutHistoryPeriod = "month";
  assert.equal(run(context, "applyHistoryPageStep('previous')"), true);
  assert.equal(context.monthOffsets.workouts, -1);
  assert.equal(context.trainingReviewOffset, 0, "other navigators are untouched");
  assert.equal(context.monthOffsets.progress, 0);
});

test("a swipe toward a page that does not exist rubber-bands and never commits, per navigator", () => {
  const context = rulesContext();
  for (const bounds of ["weeklyReviewPageBounds", "progressMonthPageBounds"]) {
    const { canPrevious, canNext } = plain(run(context, `${bounds}()`));
    assert.equal(run(context, `pageSwipeCommitDirection(-300, -2, 400, ${canPrevious}, ${canNext})`), null);
    assert.equal(run(context, `pageSwipeCommitDirection(300, 2, 400, ${canPrevious}, ${canNext})`), "previous");
    const banded = run(context, `pageSwipeDisplacement(-300, 400, ${canPrevious}, ${canNext})`);
    assert.ok(banded < 0 && banded > -300 * 0.55, `damped at the limit, got ${banded}`);
    assert.equal(run(context, `pageSwipeDisplacement(120, 400, ${canPrevious}, ${canNext})`), 120, "1:1 toward an older page");
  }
});

// The controller, driven through a small fake of the DOM.
const controllerSource = between("function pageSwipeReducedMotion()", "function inertModalBackground(");

function controllerHarness({ reduced = false, selectors = [".training-week-review"], bounds = null } = {}) {
  const timers = [];
  const log = { renders: 0, resets: 0 };
  let clock = 0;
  const makeCard = () => ({
    selectors,
    isConnected: true,
    offsetWidth: 400,
    style: {},
    classList: {
      names: new Set(),
      add(name) { this.names.add(name); },
      remove(name) { this.names.delete(name); },
      contains(name) { return this.names.has(name); }
    },
    closest(selector) {
      if (selector === "input, select, textarea") return null;
      return selector.split(",").map(part => part.trim()).some(part => this.selectors.includes(part)) ? this : null;
    },
    getBoundingClientRect() { return { width: 400 }; },
    setPointerCapture() { this.captured = true; },
    releasePointerCapture() { this.captured = false; }
  });
  let card = makeCard();
  const app = {
    querySelector(selector) {
      return card && selector.split(",").map(part => part.trim()).some(part => card.selectors.includes(part)) ? card : null;
    }
  };
  const context = vm.createContext({
    Math,
    Object,
    Number,
    app,
    performance: { now: () => clock },
    window: { matchMedia: () => ({ matches: reduced }), getSelection: () => null },
    setTimeout(fn, ms) { timers.push({ fn, ms }); return timers.length; },
    clearTimeout() {},
    render() {
      log.renders += 1;
      card = makeCard();
    },
    workoutHistoryPeriod: "week",
    workoutWeekOffset: 0,
    monthOffsets: { workouts: 0, progress: 0 },
    trainingReviewOffset: -3,
    activeMonthScope: () => "progress"
  });
  vm.runInContext(rulesSource + controllerSource, context);
  const pointer = (x, y = 0, id = 1) => ({ pointerId: id, clientX: x, clientY: y, isPrimary: true, button: 0, target: card });
  return {
    context,
    log,
    timers,
    get card() { return card; },
    detach() { card.isConnected = false; card = null; },
    tick(ms) { clock += ms; },
    down: (x, y) => vm.runInContext("beginPageSwipe", context)(pointer(x, y)),
    move: (x, y) => vm.runInContext("movePageSwipe", context)(pointer(x, y)),
    up: (x, y) => vm.runInContext("endPageSwipe", context)(pointer(x, y), false),
    cancel: (x, y) => vm.runInContext("endPageSwipe", context)(pointer(x, y), true),
    flush() { while (timers.length) timers.shift().fn(); }
  };
}

function drag(harness, { from = 200, to, steps = 6, stepMs = 20 }) {
  harness.down(from, 0);
  for (let i = 1; i <= steps; i += 1) {
    harness.tick(stepMs);
    harness.move(from + (to - from) * i / steps, 0);
  }
  harness.up(to, 0);
}

test("the weekly review card follows a drag and commits a long swipe to the older week", () => {
  const harness = controllerHarness();
  const card = harness.card;
  harness.down(200, 0);
  harness.tick(20);
  harness.move(260, 2);
  assert.equal(card.classList.contains("swiping"), true);
  assert.equal(card.captured, true);
  assert.match(card.style.transform, /translate3d\(60px/, "follows the pointer 1:1");
  harness.tick(20);
  harness.move(380, 2);
  harness.up(380, 2);
  assert.match(card.style.transform, /translate3d\(400px/, "slides out in the drag direction");
  assert.equal(harness.context.trainingReviewOffset, -3, "the page changes after the exit animation");
  harness.timers.shift().fn();
  assert.equal(harness.context.trainingReviewOffset, -4);
  assert.equal(harness.log.renders, 1);
  assert.match(harness.card.style.transition, /transform 300ms/, "the new page slides in and settles at rest");
  assert.equal(harness.card.style.transform, "");
});

test("a swipe left on the current week rubber-bands back without changing the week", () => {
  const harness = controllerHarness();
  harness.context.trainingReviewOffset = 0;
  const card = harness.card;
  drag(harness, { from: 300, to: 20, steps: 8, stepMs: 8 });
  assert.equal(harness.timers.length >= 1, true);
  harness.flush();
  assert.equal(harness.context.trainingReviewOffset, 0);
  assert.equal(harness.log.renders, 0);
  assert.equal(card.style.transform, "", "settles back to rest");
});

test("a short slow drag springs back, a flick commits and vertical movement is left to scrolling", () => {
  const slow = controllerHarness();
  drag(slow, { from: 200, to: 260, steps: 6, stepMs: 200 });
  slow.flush();
  assert.equal(slow.context.trainingReviewOffset, -3);
  assert.equal(slow.log.renders, 0);

  const flick = controllerHarness();
  drag(flick, { from: 200, to: 140, steps: 4, stepMs: 20 });
  flick.flush();
  assert.equal(flick.context.trainingReviewOffset, -2, "a quick swipe left goes to the newer week");

  const vertical = controllerHarness();
  vertical.down(200, 0);
  vertical.tick(20);
  vertical.move(204, 60);
  vertical.up(204, 60);
  assert.equal(vertical.card.classList.contains("swiping"), false);
  assert.notEqual(vertical.card.captured, true, "a vertical gesture never captures the pointer");
  assert.equal(vertical.timers.length, 0);
});

test("a plain tap, a drag from the leading edge and a cancelled drag change nothing", () => {
  const tap = controllerHarness();
  tap.down(200, 0);
  tap.up(200, 0);
  assert.notEqual(tap.card.captured, true);
  assert.equal(tap.timers.length, 0);

  const edge = controllerHarness();
  edge.down(10, 0);
  edge.tick(20);
  edge.move(200, 0);
  edge.up(200, 0);
  assert.equal(edge.card.classList.contains("swiping"), false);
  assert.equal(edge.timers.length, 0);

  const cancelled = controllerHarness();
  cancelled.down(200, 0);
  cancelled.tick(20);
  cancelled.move(390, 0);
  cancelled.cancel(390, 0);
  cancelled.flush();
  assert.equal(cancelled.context.trainingReviewOffset, -3);
  assert.equal(cancelled.log.renders, 0);
});

test("leaving the screen during the exit slide drops the page change", () => {
  const harness = controllerHarness();
  drag(harness, { from: 100, to: 390, steps: 4, stepMs: 20 });
  harness.detach();
  harness.flush();
  assert.equal(harness.context.trainingReviewOffset, -3);
  assert.equal(harness.log.renders, 0);
});

test("a new touch during the exit slide finishes the pending change first", () => {
  const harness = controllerHarness();
  drag(harness, { from: 100, to: 390, steps: 4, stepMs: 20 });
  assert.equal(harness.context.trainingReviewOffset, -3);
  harness.down(200, 0);
  assert.equal(harness.context.trainingReviewOffset, -4);
  assert.equal(harness.log.renders, 1);
});

test("Reduce Motion fades out and in without tracking the pointer", () => {
  const harness = controllerHarness({ reduced: true });
  const card = harness.card;
  harness.down(200, 0);
  harness.tick(20);
  harness.move(300, 0);
  assert.equal(card.style.transform, undefined, "no tracking while reduced");
  harness.tick(20);
  harness.move(390, 0);
  harness.up(390, 0);
  assert.match(card.style.transition, /opacity 90ms/);
  assert.equal(card.style.opacity, "0");
  assert.equal(harness.timers[0].ms, 90);
  harness.timers.shift().fn();
  assert.equal(harness.context.trainingReviewOffset, -4);
  assert.equal(harness.card.style.opacity, "", "the new page fades in and then rests");
  assert.match(harness.card.style.transition, /opacity 150ms/);
});

test("the progress month swipe selects the previous month from the heatmap card and the exercise page", () => {
  for (const selectors of [[".activity-heatmap-card"], [".progress-month-swipe"]]) {
    const harness = controllerHarness({ selectors });
    drag(harness, { from: 100, to: 390, steps: 4, stepMs: 20 });
    harness.flush();
    assert.equal(harness.context.monthOffsets.progress, -1, selectors[0]);
    assert.equal(harness.context.trainingReviewOffset, -3, "the weekly review is untouched");
  }
});

test("the history panel still pages through the same controller", () => {
  const harness = controllerHarness({ selectors: [".training-history"] });
  drag(harness, { from: 100, to: 390, steps: 4, stepMs: 20 });
  harness.flush();
  assert.equal(harness.context.workoutWeekOffset, -1);
  assert.equal(harness.context.trainingReviewOffset, -3);
});

// Wiring in the markup and styles.
test("every navigator keeps its buttons and renders inside a registered swipe panel", () => {
  const review = between("function trainingWeeklyReviewMarkup()", "function progressScreen()");
  assert.match(review, /<section class="panel training-week-review">/);
  assert.equal((review.match(/data-action="training-review-week"/g) || []).length, 2, "both week buttons stay");

  const heatmap = between("function activityHeatmapCard()", "function muscleMapCard()");
  assert.match(heatmap, /<section class="panel highlighted activity-heatmap-card">/);
  assert.match(heatmap, /\$\{monthNavigatorInline\(\)\}/, "the heatmap keeps its month buttons");

  const exercises = between("function exerciseProgressPanel()", "function progressHistoryGroups(");
  assert.equal((exercises.match(/<div class="progress-month-swipe">\$\{monthNavigatorInline\(\)\}/g) || []).length, 2, "both exercise states open the swipe page");
  assert.equal((exercises.match(/<\/div>`;\n/g) || []).length >= 2, true, "both exercise states close it");
  const navigator = between("function monthNavigatorInline()", "function pluralForm(");
  for (const action of ["month-prev", "month-current", "month-next"]) assert.match(navigator, new RegExp(`data-action="${action}"`));
});

test("the swipe panels keep vertical scrolling and suppress text selection while dragging", () => {
  assert.match(styles, /\.training-history \{[^}]*touch-action: pan-y;/);
  assert.match(styles, /\.training-week-review,\s*\.activity-heatmap-card,\s*\.progress-month-swipe \{\s*touch-action: pan-y;/);
  assert.match(styles, /\.progress-month-swipe \{[^}]*display: grid;[^}]*gap: 12px;/);
  assert.match(styles, /\.training-week-review\.swiping,\s*\.activity-heatmap-card\.swiping,\s*\.progress-month-swipe\.swiping \{[^}]*user-select: none;/);
});

test("the controller ignores form fields and keeps the edge inset and capture", () => {
  const controller = between("function beginPageSwipe(", "function inertModalBackground(");
  assert.match(controller, /closest\?\.\("input, select, textarea"\)/);
  assert.match(controller, /event\.clientX < PAGE_SWIPE_EDGE_INSET/);
  assert.match(controller, /setPointerCapture\(event\.pointerId\)/);
  assert.match(controller, /if \(swipe\.reduced\) return;/);
});
