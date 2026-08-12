import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [contractSource, androidProfile, androidExperience, androidCoach, androidGuidance,
  iosCoach, iosGuidance, iosStore] = await Promise.all([
  readFile("shared/training-experience-v1.json", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/util/TrainingProfileManager.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/TrainingExperience.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/WorkoutRecommendationEngine.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/util/TrainingGuidanceManager.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/RecommendationEngine.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/TrainingGuidance.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Data/WorkoutStore.swift", "utf8")
]);
const contract = JSON.parse(contractSource);

test("training experience v1 fixes one canonical cross-platform contract", () => {
  assert.deepEqual(contract.clients, ["android", "ios"]);
  assert.deepEqual(contract.profileDefaults, {
    split: "upperLower",
    workoutsPerWeek: 4,
    goal: "aestheticFatLoss",
    calorieMode: "deficit"
  });
  assert.deepEqual(contract.activation.splitByWorkoutsPerWeek, {
    2: "fullBody", 3: "fullBody", 4: "upperLower", 5: "pushPullLegs", 6: "pushPullLegs"
  });
  assert.deepEqual(contract.activation.calorieModeByGoal, {
    aestheticFatLoss: "deficit",
    muscleGain: "surplus",
    strength: "maintenance",
    balanced: "maintenance"
  });
  assert.deepEqual(contract.feedback.values, ["easy", "normal", "hard"]);
  assert.equal(contract.feedback.maximumEntries, 128);
  assert.equal(contract.feedback.coachMaximumAgeDays, 7);
  assert.deepEqual(contract.smartPlan, {
    maximumExercises: 8,
    maximumWorkingSets: 24,
    maximumSetsPerExercise: 4
  });
  assert.deepEqual(contract.launchSeed, {
    accountBound: true,
    profileCatalogAndHistoryBound: true,
    maximumAgeMilliseconds: 300000,
    futureSkewMilliseconds: 60000,
    oneTimeUse: true
  });
  assert.equal(contract.weeklyRhythm.primaryHabitMetric, "profileTargetWeeklyStreak");
  assert.deepEqual(contract.weeklyRhythm.streakAchievementWeeks, [2, 4, 8]);
});

test("Android and iOS retain the same missing-profile defaults", () => {
  assert.match(androidProfile, /TrainingSplit\.UpperLower[\s\S]*workoutsPerWeek: Int = 4[\s\S]*TrainingGoal\.AestheticFatLoss[\s\S]*CalorieMode\.Deficit/);
  assert.match(iosCoach, /split: TrainingSplit = \.upperLower[\s\S]*workoutsPerWeek: Int = 4[\s\S]*goal: TrainingGoal = \.aestheticFatLoss[\s\S]*calorieMode: CalorieMode = \.deficit/);
});

test("both native clients enforce the feedback and Smart-plan safety bounds", () => {
  assert.match(androidExperience, /Easy\("easy"\)[\s\S]*Normal\("normal"\)[\s\S]*Hard\("hard"\)/);
  assert.match(androidCoach, /SMART_WORKOUT_MAX_EXERCISES = 8/);
  assert.match(androidCoach, /SMART_WORKOUT_MAX_TOTAL_SETS = 24/);
  assert.match(androidCoach, /SMART_WORKOUT_MAX_SETS_PER_EXERCISE = 4/);
  assert.match(androidGuidance, /MAX_FEEDBACK_ENTRIES = 128/);

  assert.match(iosGuidance, /case easy[\s\S]*case normal[\s\S]*case hard/);
  assert.match(iosCoach, /return min\(8, max\(4, budget \/ 3\)\)/);
  assert.match(iosCoach, /maximumSmartPlanSetCount = 24/);
  assert.match(iosStore, /maximumWorkoutFeedbackEntries = 128/);

});

test("feedback remains a local account sidecar instead of changing portable sessions", () => {
  assert.equal(contract.feedback.storage, "accountLocalSidecar");
  assert.equal(contract.feedback.cloudAndBackupSessionShapeUnchanged, true);
  assert.match(androidGuidance, /gym_training_guidance_v1/);
  assert.match(iosStore, /workoutFeedback: \[PersistedWorkoutFeedback\]\?/);
});
