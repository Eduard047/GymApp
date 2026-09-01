import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [app, styles, index, manifestSource, worker] = await Promise.all([
  readFile("pwa/app.js", "utf8"),
  readFile("pwa/styles.css", "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("pwa/manifest.webmanifest", "utf8"),
  readFile("pwa/sw.js", "utf8")
]);

test("root routes reserve real mobile navigation clearance and use a desktop side rail", () => {
  assert.match(styles, /--bottom-nav-clearance:\s*calc\([^;]*env\(safe-area-inset-bottom\)\)/);
  assert.match(styles, /\.workouts-scroll\s*\{[\s\S]*?padding:\s*0 12px var\(--bottom-nav-clearance\);[\s\S]*?\}/);
  assert.match(styles, /\.screen-workouts\s*\{[\s\S]*?padding:\s*0;[\s\S]*?\}/);
  assert.match(styles, /@media \(min-width: 900px\)[\s\S]*?\.root-route-shell \.bottom-nav\s*\{[\s\S]*?grid-template-columns:\s*1fr;[\s\S]*?transform:\s*translateY\(-50%\);/);
  assert.match(styles, /html\[lang="ru"\] \.root-route-shell \.tab-button > span:last-child\s*\{[\s\S]*?font-size:\s*11px;[\s\S]*?overflow:\s*visible;[\s\S]*?text-overflow:\s*clip;/);
  assert.match(styles, /\.root-route-shell \.screen\s*\{[\s\S]*?width:\s*min\(calc\(100% - 144px\), 1180px\);/);
  assert.match(app, /classList\?\.toggle\("root-route-shell", isRootRoute\(current\.name\)\)/);
});

test("exercise density, active workout disclosure, and empty progress remain accessible", () => {
  assert.match(app, /data-action="open-exercise-filters"[^>]*aria-haspopup="dialog"/);
  assert.match(app, /function activeExerciseFilterCount\(\)/);
  assert.match(app, /bottomSheet\(exerciseFilterSheetMarkup\(\), "exercise-filter-title"\)/);
  assert.match(app, /data-action="open-exercise-more"[^>]*aria-haspopup="dialog"/);
  assert.match(app, /bottomSheet\(exerciseMoreSheetMarkup\(modal\.exerciseId\), "exercise-more-title"\)/);
  assert.match(app, /const modalElement = app\.querySelector\("\.modal"\);\s*if \(modalElement\)/);
  assert.match(app, /function muscleMapSelectionList\(data\)/);
  assert.match(app, /class="muscle-map-selector" role="group"/);
  assert.match(app, /data-action="select-muscle"[^>]*aria-pressed=/);
  assert.match(app, /returnFocus: stableActionReturnFocus\("open-exercise-filters", el\)/);
  assert.match(app, /returnFocus: stableActionReturnFocus\("open-exercise-more", el\)/);
  assert.match(app, /class="hero-panel progress-empty-state"/);
  assert.match(styles, /\.active-workout-exercise\.current \.active-exercise-actions\s*\{[\s\S]*?position:\s*sticky;/);
  assert.match(styles, /@media \(max-width: 460px\) and \(max-height: 640px\)/);
});

test("progress grids stay inside narrow mobile viewports", () => {
  assert.match(
    styles,
    /\.progress-hub,\s*\.progress-hub-panel\s*\{[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\);[\s\S]*?min-width:\s*0;/
  );
  assert.match(
    styles,
    /@media \(max-width: 460px\)[\s\S]*?\.solo-progress-hero \.metric-grid\s*\{[\s\S]*?grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);/
  );
});

test("each full-screen account state and logged route exposes one meaningful H1", () => {
  assert.match(app, /<h1 class="auth-wordmark">GymApp<\/h1>/);
  assert.match(app, /<h1>\$\{titleForRoute\(current\)\}<\/h1>/);
  for (const title of [
    "Finishing cloud sign-in",
    "Cloud sync needs your choice",
    "Choose a new password",
    "Cloud data recovery"
  ]) {
    assert.match(app, new RegExp(`<h1>\\$\\{tx\\("${title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
  }
  assert.match(app, /workouts:\s*tx3\("Today"/);
  assert.match(app, /exercises:\s*t\("exercises"\)/);
  assert.doesNotMatch(app, /workouts:\s*""|exercises:\s*""/);
});

test("install metadata and immutable PWA entrypoints are one coherent GymApp release", () => {
  const manifest = JSON.parse(manifestSource);
  assert.equal(manifest.name, "GymApp");
  assert.equal(manifest.short_name, "GymApp");
  assert.equal(manifest.theme_color, "#f7faff");
  assert.equal(manifest.background_color, "#f7faff");
  assert.equal(Object.hasOwn(manifest, "orientation"), false);
  assert.match(index, /<title>GymApp — Workout Tracker<\/title>/);
  assert.match(index, /apple-mobile-web-app-title" content="GymApp"/);
  for (const asset of ["styles.v82.css", "russian-text.v86.js", "app.v106.js"]) {
    assert.ok(index.includes(`./${asset}`), `index references ${asset}`);
    assert.ok(worker.includes(`"./${asset}"`), `service worker caches ${asset}`);
  }
  assert.match(worker, /const CACHE_VERSION = "v148";/);
});
