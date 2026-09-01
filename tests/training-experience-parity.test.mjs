import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [contractSource, androidProfile, androidExperience, androidCoach, androidGuidance,
  iosCoach, iosGuidance, iosStore, pwaCoach] = await Promise.all([
  readFile("shared/training-experience-v1.json", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/util/TrainingProfileManager.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/TrainingExperience.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/WorkoutRecommendationEngine.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/util/TrainingGuidanceManager.kt", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/RecommendationEngine.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/TrainingGuidance.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Data/WorkoutStore.swift", "utf8"),
  readFile("pwa/app.js", "utf8")
]);
const contract = JSON.parse(contractSource);

test("training experience v1 fixes one canonical cross-platform contract", () => {
  assert.deepEqual(contract.clients, ["android", "ios", "pwa"]);
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
  assert.equal(contract.smartPlan.minimumExercises, 4);
  assert.equal(contract.smartPlan.maximumExercises, 8);
  assert.equal(contract.smartPlan.minimumSetsPerExercise, 3);
  assert.equal(contract.smartPlan.maximumSetsPerExercise, 4);
  assert.equal(contract.smartPlan.maximumWorkingSets, 24);
  assert.deepEqual(contract.smartPlan.frequencyBaseSets, {
    2: 20, 3: 18, 4: 16, 5: 15, 6: 14
  });
  assert.deepEqual(contract.smartPlan.goalSetAdjustment, {
    aestheticFatLoss: -2, muscleGain: 2, strength: -1, balanced: 0
  });
  assert.deepEqual(contract.smartPlan.calorieSetAdjustment, {
    deficit: -2, maintenance: 0, surplus: 2
  });
  assert.deepEqual(contract.smartPlan.effortSetAdjustment, {
    recovery: -3, standard: 0, hard: 1
  });
  assert.deepEqual(contract.smartPlan.minimumWorkingSets, {
    recovery: 12, standard: 12, hard: 13
  });
  assert.equal(contract.smartPlan.hardReservedSets, 1);
  assert.equal(contract.smartPlan.exerciseCountRounding, "floor");
  assert.deepEqual(contract.launchSeed, {
    accountBound: true,
    profileCatalogAndHistoryBound: true,
    maximumAgeMilliseconds: 300000,
    futureSkewMilliseconds: 60000,
    oneTimeUse: true
  });
  assert.equal(contract.weeklyRhythm.primaryHabitMetric, "profileTargetWeeklyStreak");
  assert.deepEqual(contract.weeklyRhythm.streakAchievementWeeks, [2, 4, 8]);
  assert.deepEqual(contract.weeklyRhythm.todayHistoryNavigation, {
    range: "currentOrPastWeekOnly",
    controls: ["previous", "current", "next", "swipe"],
    selectedWeekIncludesSavedWorkoutLinks: true,
    futureWeekDisabled: true,
    accountBoundPresentationState: true
  });
});

test("Android and iOS retain the same missing-profile defaults", () => {
  assert.match(androidProfile, /TrainingSplit\.UpperLower[\s\S]*workoutsPerWeek: Int = 4[\s\S]*TrainingGoal\.AestheticFatLoss[\s\S]*CalorieMode\.Deficit/);
  assert.match(iosCoach, /split: TrainingSplit = \.upperLower[\s\S]*workoutsPerWeek: Int = 4[\s\S]*goal: TrainingGoal = \.aestheticFatLoss[\s\S]*calorieMode: CalorieMode = \.deficit/);
});

test("all three clients enforce the same Smart-plan budget formula and safety bounds", () => {
  assert.match(androidExperience, /Easy\("easy"\)[\s\S]*Normal\("normal"\)[\s\S]*Hard\("hard"\)/);
  assert.match(androidCoach, /SMART_WORKOUT_MAX_EXERCISES = 8/);
  assert.match(androidCoach, /SMART_WORKOUT_MAX_TOTAL_SETS = 24/);
  assert.match(androidCoach, /SMART_WORKOUT_MAX_SETS_PER_EXERCISE = 4/);
  assert.match(androidCoach, /2 -> 20[\s\S]*3 -> 18[\s\S]*4 -> 16[\s\S]*5 -> 15[\s\S]*else -> 14/);
  assert.match(androidCoach, /TrainingGoal\.AestheticFatLoss -> -2/);
  assert.match(androidCoach, /CalorieMode\.Deficit -> -2/);
  assert.match(androidCoach, /SmartWorkoutEffort\.Hard -> 1/);
  assert.match(androidGuidance, /MAX_FEEDBACK_ENTRIES = 128/);

  assert.match(iosGuidance, /case easy[\s\S]*case normal[\s\S]*case hard/);
  assert.match(iosCoach, /let reservedHardSets = effort == \.hard \? 1 : 0[\s\S]*return min\(8, max\(4, \(budget - reservedHardSets\) \/ 3\)\)/);
  assert.match(iosCoach, /case 2: 20[\s\S]*case 3: 18[\s\S]*case 4: 16[\s\S]*case 5: 15[\s\S]*default: 14/);
  assert.match(iosCoach, /case \.aestheticFatLoss: -2/);
  assert.match(iosCoach, /case \.deficit: -2/);
  assert.match(iosCoach, /case \.hard: 1/);
  assert.match(iosCoach, /maximumSmartPlanSetCount = 24/);
  assert.match(iosStore, /maximumWorkoutFeedbackEntries = 128/);

  assert.match(pwaCoach, /days === 2 \? 20 : days === 3 \? 18 : days === 4 \? 16 : days === 5 \? 15 : 14/);
  assert.match(pwaCoach, /profile\?\.goal === "Aesthetic Cut" \? -2/);
  assert.match(pwaCoach, /profile\?\.calories === "Deficit" \? -2/);
  assert.match(pwaCoach, /appliedEffort === "Recovery" \? -3 : appliedEffort === "Hard" \? 1 : 0/);
  assert.match(pwaCoach, /Math\.floor\(\(sessionSetBudget - reservedHardSets\) \/ 3\)/);
});

test("feedback remains a local account sidecar instead of changing portable sessions", () => {
  assert.equal(contract.feedback.storage, "accountLocalSidecar");
  assert.equal(contract.feedback.cloudAndBackupSessionShapeUnchanged, true);
  assert.match(androidGuidance, /gym_training_guidance_v1/);
  assert.match(iosStore, /workoutFeedback: \[PersistedWorkoutFeedback\]\?/);
});
