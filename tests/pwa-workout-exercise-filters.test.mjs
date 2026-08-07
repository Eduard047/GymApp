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

test("workout catalog picker and exercise library reuse the same filter controls", () => {
  const addWorkout = section("function addWorkoutScreen()", "function trainingProfilePanel()");
  const library = section("function exercisesScreen()", "function exerciseFilterControls(");
  const controls = section("function exerciseFilterControls(", "const exerciseBodyMuscles");
  const picker = section("function workoutExercisePickerMarkup(", "function toggleExerciseFavorite(");

  assert.match(addWorkout, /data-action="open-workout-exercise-picker"/);
  assert.doesNotMatch(addWorkout, /id="exercise-search"/);
  assert.doesNotMatch(addWorkout, /class="exercise-select"/);
  assert.match(picker, /exerciseFilterControls\(rows\.length\)/);
  assert.match(picker, /exerciseMediaThumbnail/);
  assert.match(picker, /exerciseSearchReasonMarkup/);
  assert.match(picker, /data-action="select-workout-exercise"/);
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
  assert.match(controls, /maxlength="\$\{EXERCISE_SEARCH_QUERY_MAX_CHARS\}"/);
  assert.match(app, /const EXERCISE_SEARCH_QUERY_MAX_CHARS = 256;/);
  assert.match(
    app,
    /exerciseSearchQuery = exerciseSearch\.value\.slice\(0, EXERCISE_SEARCH_QUERY_MAX_CHARS\);/
  );
  assert.doesNotMatch(controls, /maxlength="120"/);
});

test("workout picker uses filtered results while legacy option helper retains current values", () => {
  const options = section("function draftExerciseOptions(", "function smartPanel(");
  const filter = section("function filteredLibraryExercises()", "function exerciseWorkoutCount(");
  const selection = section("function selectWorkoutExercise(", "function quickAddExercise(");
  const quickAdd = section("function quickAddExercise(", "function detailAddSet(");

  assert.match(options, /const options = \[\.\.\.state\.exercises\]/);
  assert.match(options, /options\.unshift/);
  assert.match(options, /exercisesMatch\(exercise, block\)/);
  assert.match(filter, /exerciseSearchMatch/);
  assert.match(filter, /searchMatch\.score/);
  assert.match(filter, /exerciseFavoritesOnly/);
  assert.match(filter, /exerciseBodyFilter/);
  assert.match(filter, /exerciseMuscleFilter/);
  assert.match(filter, /exerciseSortMode === "most"/);
  assert.match(filter, /exerciseWorkoutCount/);
  assert.match(selection, /workoutDraft\.blocks\.unshift\(nextBlock\)/);
  assert.match(quickAdd, /session\.sets\.unshift\(set\)/);
  assert.doesNotMatch(quickAdd, /session\.sets\.push/);
});
