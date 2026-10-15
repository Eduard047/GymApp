import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const source = await readFile("pwa/app.js", "utf8");
const slice = (from, to) => source.slice(source.indexOf(from), source.indexOf(to, source.indexOf(from)));
const transitionSource = slice("const routeTransition = ", "function render() {");
const navigationSource = slice("function push(name, params = {}) {", "function svg(name");

function fixture({ viewTransitions = true } = {}) {
  const calls = { render: 0, start: 0, callbacks: [], timers: [] };
  const main = { dataset: { scrollKey: "workouts:root", navDepth: "1" } };
  const document = { documentElement: { dataset: {} }, visibilityState: "visible" };
  if (viewTransitions) {
    document.startViewTransition = callback => {
      calls.start += 1;
      calls.callbacks.push(callback);
      return { finished: Promise.resolve(), ready: Promise.resolve(), updateCallbackDone: Promise.resolve() };
    };
  }
  const context = vm.createContext({
    document, history: { state: null }, Number, Map, Boolean,
    nav: [{ name: "workouts" }], modal: null, languageMenuOpen: false, exerciseFilterMenuOpen: false, planEditorMenu: null,
    activeAccount: { id: "a" }, activeWorkout: null, workoutDraft: null, onboardingTour: null, exerciseDrag: null,
    sheetEngine: { drag: null }, workoutDraftLiveSendInProgress: false, workoutDetailEditSessionId: null,
    routeScrollPositions: new Map(),
    app: { querySelector: selector => (selector.startsWith("main") ? main : null), classList: { contains: () => true } },
    isRootRoute: name => ["workouts", "exercises", "progress", "leaderboard"].includes(name),
    pushNavigationHistory() {}, replaceNavigationHistory() {}, persistWorkoutDraft() {}, createDraft: () => ({}),
    focusStableScreenContext() {}, closeModal: () => true,
    setTimeout: callback => calls.timers.push(callback), clearTimeout() {},
    // render() stand-in: the screen on the DOM follows the nav stack, as the real render does.
    render() {
      calls.render += 1;
      const top = context.nav[context.nav.length - 1];
      main.dataset.scrollKey = `${top.name}:${top.id ?? "root"}`;
      main.dataset.navDepth = String(context.nav.length);
    }
  });
  vm.runInContext(`function route() { return nav[nav.length - 1]; }\n${transitionSource}\n${navigationSource}`, context);
  return { context, calls };
}

const run = (context, code) => vm.runInContext(code, context);

test("a navigation while a view transition is pending is ignored until the deferred render has run", () => {
  const { context, calls } = fixture();
  run(context, 'push("detail", { id: 7 })');
  assert.equal(calls.start, 1);
  assert.equal(run(context, "routeTransition.pending"), true);
  assert.equal(calls.render, 0, "the DOM swap waits for the transition callback");
  assert.equal(run(context, "nav.length"), 2);
  assert.equal(context.document.documentElement.dataset.navTransition, "push");

  run(context, 'push("ranks")');
  assert.equal(run(context, "nav.length"), 2, "double tap must not push a second screen");
  assert.equal(run(context, 'goRoot("progress")'), false);
  assert.equal(run(context, "route().name"), "detail");
  assert.equal(run(context, "back()"), false);
  assert.equal(run(context, "nav.length"), 2);
  assert.equal(calls.start, 1, "ignored navigations never start another transition");

  calls.callbacks[0]();
  assert.equal(calls.render, 1);
  assert.equal(run(context, "routeTransition.pending"), false);

  run(context, "back()");
  assert.equal(run(context, "nav.length"), 1, "navigation works again once the deferred render has run");
});

test("renderRoute flushes a pending transition before it starts its own", () => {
  const { context, calls } = fixture();
  const order = [];
  const render = context.render;
  context.render = () => { order.push("render"); render(); };
  context.afterFirst = () => order.push("afterFirst");
  context.afterSecond = () => order.push("afterSecond");
  run(context, "nav = [{ name: \"workouts\" }, { name: \"add\" }]; renderRoute(afterFirst)");
  assert.deepEqual(order, []);
  run(context, "nav = [{ name: \"workouts\" }]; renderRoute(afterSecond)");
  // The flush renders the stack as it is now, so the second change lands on the same screen and renders directly.
  assert.deepEqual(order, ["render", "afterFirst", "render", "afterSecond"]);
  assert.equal(run(context, "routeTransition.pending"), false);
  assert.equal(calls.start, 1);
});

test("without startViewTransition a route change renders directly", () => {
  const { context, calls } = fixture({ viewTransitions: false });
  run(context, 'push("detail", { id: 7 })');
  assert.equal(calls.render, 1);
  assert.equal(run(context, "routeTransition.pending"), false);
  assert.equal(context.document.documentElement.dataset.navTransition, undefined);
  run(context, 'push("ranks")');
  assert.equal(run(context, "nav.length"), 3, "nothing is pending, so the next navigation proceeds");
  assert.equal(calls.render, 2);
});

test("popstate finishes a pending route change before applying the browser navigation", () => {
  assert.match(source, /addEventListener\("popstate", event => \{\s*(?:\/\/[^\n]*\n\s*)*if \(routeTransition\.pending\) routeTransitionFlush\(\);/);
});
