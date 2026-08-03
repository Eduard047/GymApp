import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../pwa/app.js", import.meta.url), "utf8");

function section(start, end) {
  const from = app.indexOf(start);
  const to = app.indexOf(end, from + start.length);
  assert.ok(from >= 0, `missing ${start}`);
  assert.ok(to > from, `missing ${end}`);
  return app.slice(from, to);
}

test("workout creation and exercise library reuse the same filter controls", () => {
  const addWorkout = section("function addWorkoutScreen()", "function trainingProfilePanel()");
  const library = section("function exercisesScreen()", "function exerciseFilterControls(");
  const controls = section("function exerciseFilterControls(", "const exerciseBodyMuscles");

  assert.match(addWorkout, /exerciseFilterControls\(filteredLibraryExercises\(\)\.length\)/);
  assert.match(library, /exerciseFilterControls\(mappingRows\.length\)/);
  for (const contract of [
    /id="exercise-search"/,
    /data-action="exercise-favorites-filter"/,
    /data-action="exercise-body-filter"/,
    /data-action="exercise-sort"/,
    /data-action="exercise-muscle-filter"/
  ]) {
    assert.match(controls, contract);
  }
});

test("workout selectors use filtered results but retain their current selection", () => {
  const options = section("function draftExerciseOptions(", "function smartPanel(");
  const filter = section("function filteredLibraryExercises()", "function exerciseWorkoutCount(");

  assert.match(options, /const options = filteredLibraryExercises\(\)/);
  assert.match(options, /options\.unshift/);
  assert.match(options, /exercisesMatch\(exercise, block\)/);
  assert.match(filter, /exerciseMatchesSearch/);
  assert.match(filter, /exerciseFavoritesOnly/);
  assert.match(filter, /exerciseBodyFilter/);
  assert.match(filter, /exerciseMuscleFilter/);
  assert.match(filter, /exerciseSortMode === "most"/);
  assert.match(filter, /exerciseWorkoutCount/);
});
