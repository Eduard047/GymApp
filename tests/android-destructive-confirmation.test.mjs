import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const placeholderPattern = /%(?:\d+\$)?[a-zA-Z@]/g;

function stringValue(source, key) {
  return source.match(new RegExp(`<string\\s+name="${key}">([^<]*)<\\/string>`))?.[1];
}

test("Android persisted-delete controls name the exact visible target", async () => {
  const [english, ukrainian, russian, exerciseList, workoutDetail, exerciseProgress, workoutList] =
    await Promise.all([
      readFile("app/src/main/res/values/strings.xml", "utf8"),
      readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
      readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
      readFile("app/src/main/java/com/example/gymapp/ui/screens/ExerciseListScreen.kt", "utf8"),
      readFile("app/src/main/java/com/example/gymapp/ui/screens/WorkoutDetailScreen.kt", "utf8"),
      readFile("app/src/main/java/com/example/gymapp/ui/screens/ExerciseProgressScreen.kt", "utf8"),
      readFile("app/src/main/java/com/example/gymapp/ui/screens/WorkoutListScreen.kt", "utf8")
    ]);

  const targetLabels = [
    "cd_delete_exercise_named",
    "cd_delete_set_named",
    "cd_delete_history_set_named",
    "cd_delete_workout_on"
  ];
  for (const key of targetLabels) {
    const englishValue = stringValue(english, key);
    assert.ok(englishValue, `missing English ${key}`);
    for (const [locale, source] of [["uk", ukrainian], ["ru", russian]]) {
      const localizedValue = stringValue(source, key);
      assert.ok(localizedValue, `missing ${locale} ${key}`);
      assert.deepEqual(
        localizedValue.match(placeholderPattern),
        englishValue.match(placeholderPattern),
        `${locale} placeholders for ${key}`
      );
    }
  }

  const destructiveScreens = [exerciseList, workoutDetail, exerciseProgress, workoutList];
  destructiveScreens.forEach(source => {
    assert.doesNotMatch(
      source,
      /contentDescription\s*=\s*stringResource\(R\.string\.cd_delete\)/,
      "persisted delete controls must not use a generic accessible name"
    );
  });
  assert.match(exerciseList, /R\.string\.cd_delete_exercise_named/);
  assert.match(workoutDetail, /R\.string\.cd_delete_set_named/);
  assert.match(workoutDetail, /R\.string\.cd_delete_workout_on/);
  assert.doesNotMatch(exerciseProgress, /R\.string\.cd_delete_history_set_named/);
  assert.doesNotMatch(workoutList, /R\.string\.cd_delete_workout_on/);
});
