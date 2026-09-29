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

test("Android account actions stay on their exact account type", async () => {
  const [profile, sheet] = await Promise.all([
    readFile("app/src/main/java/com/example/gymapp/ui/screens/ProfileScreen.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/ui/screens/AccountSettingsSheet.kt", "utf8")
  ]);

  // Deletion rows: one branch per account type, at the very bottom of the sheet.
  const start = sheet.indexOf("private fun AccountDeleteRow(");
  const end = sheet.indexOf("\n}\n", start);
  assert.ok(start >= 0 && end > start, "account delete row source section is missing");
  const deleteRow = sheet.slice(start, end);
  const cloudBranch = deleteRow.indexOf("if (isCloudAccount) {");
  const localBranch = deleteRow.indexOf("} else {", cloudBranch);
  assert.ok(cloudBranch >= 0 && localBranch > cloudBranch, "account type split is missing");
  const cloudActions = deleteRow.slice(cloudBranch, localBranch);
  const localActions = deleteRow.slice(localBranch);
  assert.match(cloudActions, /onDeleteAccount/, "cloud-account deletion must be cloud-only");
  assert.doesNotMatch(cloudActions, /onDeleteLocalProfile/);
  assert.match(localActions, /onDeleteLocalProfile/, "local-profile deletion must be local-only");
  assert.doesNotMatch(localActions, /onDeleteAccount/, "local profiles must never render cloud-account actions");

  // Change password is cloud-only inside the sheet body.
  const body = sheet.slice(0, start);
  assert.match(
    body,
    /if \(state\.isCloudAccount\) \{\s*SettingsRow\(\s*icon = Icons\.Default\.Lock,[^}]*onClick = onChangePassword/,
    "change password must sit in a cloud-only branch"
  );
  assert.equal(body.indexOf("onDeleteAccount()"), -1, "sheet must not delete without confirmation");

  // Confirmation flows stay in Profile: the sheet only opens them.
  assert.match(profile, /onDeleteAccount = \{ showAccountDeletion = true \}/);
  assert.match(profile, /onDeleteLocalProfile = \{ showLocalProfileDeletion = true \}/);
  assert.match(profile, /DeleteCloudAccountDialog\(/);
  assert.match(profile, /local_profile_delete_confirm_title/);
});
