import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [styles, app, appBundle, stylesBundle] = await Promise.all([
  readFile("pwa/styles.css", "utf8"),
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/app.v143.js", "utf8"),
  readFile("pwa/styles.v111.css", "utf8")
]);

function rules(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return [...styles.matchAll(new RegExp(`(?:^|\\n|,\\s*)${escaped}\\s*(?:,[^{}]*)?\\{([^}]*)\\}`, "g"))].map(match => match[1]);
}

function functionSource(name) {
  const start = app.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  const open = app.indexOf("{", app.indexOf(")", start));
  let depth = 0;
  for (let index = open; index < app.length; index += 1) {
    if (app[index] === "{") depth += 1;
    if (app[index] === "}") depth -= 1;
    if (depth === 0) return app.slice(start, index + 1);
  }
  throw new Error(`${name} is unterminated`);
}

test("the shipped v142 bundles are byte copies of the working files", () => {
  assert.equal(appBundle, app);
  assert.equal(stylesBundle, styles);
});

test("all four root tabs use one body large title and the overlay bar; pushed screens keep the compact bar", () => {
  const roots = functionSource("routeHasBodyTitle");
  for (const name of ["workouts", "exercises", "progress", "leaderboard"]) assert.match(roots, new RegExp(`"${name}"`));
  for (const name of ["add", "active", "detail", "summary", "ranks"]) assert.doesNotMatch(roots, new RegExp(`"${name}"`));
  assert.match(app, /<header class="topbar\$\{routeHasBodyTitle\(current\.name\) \? " topbar-root-title" : ""\}">/);
  assert.doesNotMatch(app, /topbar-title-hidden/);
  assert.doesNotMatch(styles, /topbar-title-hidden/);
  // Progress and Profile get the same screen-copy title Today and Exercises already render.
  assert.match(functionSource("rootTitleMarkup"), /class="screen-copy compact root-title"><h2>\$\{titleForRoute\(current\)\}<\/h2>/);
  assert.match(app, /current\.name === "progress"\) return rootTitleMarkup\(current\) \+ progressScreen\(\)/);
  assert.match(app, /current\.name === "leaderboard"\) return rootTitleMarkup\(current\) \+ friendsProfileScreen\(\)/);
  assert.match(app, /class="screen-copy workouts-screen-copy"><div><h2>/);
  assert.match(app, /class="screen-copy compact exercises-header"[^>]*><h2>/);
  // The compact bar still carries the back control and the centred title for pushed screens.
  assert.match(app, /nav\.length > 1 \? `<button class="icon-button topbar-action" data-action="back"/);
  assert.match(rules(".topbar h1").join("\n"), /text-align: center;/);
});

test("the root bar takes no layout space and materializes on scroll, not by moving content", () => {
  const rest = rules(".topbar.topbar-root-title").join("\n");
  assert.match(rest, /position: absolute;/);
  assert.match(rest, /top: 0;/);
  assert.match(rest, /opacity: 0;/);
  assert.match(rest, /pointer-events: none;/);
  assert.match(rest, /transition: opacity 150ms ease-out;/);
  assert.doesNotMatch(rest, /margin-top|height:\s*0/);
  assert.match(rules(".root-route-shell.title-collapsed .topbar.topbar-root-title").join("\n"), /opacity: 1;/);
  assert.match(rules(".topbar.topbar-root-title + .screen").join("\n"), /height: 100%;/);
  assert.match(rules(".root-route-shell").join("\n"), /position: relative;/);
  // The bar keeps its material and hairline from .topbar; it is not a gradient, mask or shadow.
  const bar = rules(".topbar").join("\n");
  assert.match(bar, /border-bottom: 1px solid var\(--line\);/);
  assert.match(bar, /background: var\(--topbar-surface\);/);
  assert.doesNotMatch(rest + bar, /gradient|box-shadow|mask/);
});

test("scrolling past 24px collapses only root-tab titles; other bars keep their old behaviour", () => {
  assert.match(app, /const TOPBAR_SCROLL_THRESHOLD = 24;/);
  const sync = functionSource("syncTopbarVisibility");
  assert.match(sync, /scrollTop \|\| 0\) > TOPBAR_SCROLL_THRESHOLD/);
  assert.match(sync, /classList\.toggle\("title-collapsed", rootTitle && scrolled\)/);
  assert.match(sync, /classList\.toggle\("topbar-collapsed", !rootTitle && scrolled\)/);
  assert.match(sync, /querySelector\("\.topbar-root-title"\)/);
});

test("the four root titles share one size, rhythm and 44px row", () => {
  const shared = rules(".screen-copy.root-title").join("\n");
  assert.match(shared, /min-height: 44px;/);
  assert.match(shared, /align-items: center;/);
  assert.match(styles, /\.screen-copy\.root-title,\s*\.workouts-screen-copy,\s*\.exercises-header \{ min-height: 44px; align-items: center; \}/);
  assert.match(rules(".screen-copy h2").join("\n"), /font-size: 2rem;[^}]*letter-spacing: -0\.01em;/);
  // Today sits on the same 10px top inset the other tabs get from the screen padding, with no per-width override.
  assert.match(rules(".workouts-screen-copy").join("\n"), /margin: 10px 16px 12px;/);
  assert.doesNotMatch(styles, /\.workouts-screen-copy \{ align-items: start; \}/);
});

test("reduced motion removes the bar fade and reduced transparency keeps a solid bar", () => {
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\) \{\s*\*,[^}]*transition-duration: 0\.01ms !important;/);
  assert.match(styles, /@media \(prefers-reduced-transparency: reduce\) \{\s*\.topbar,\s*\.bottom-nav \{[^}]*backdrop-filter: none;[^}]*\}\s*\.topbar \{ background: var\(--background\); \}/);
});
