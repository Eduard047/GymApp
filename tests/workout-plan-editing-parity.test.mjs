import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [
  contractSource,
  androidWorkouts,
  androidEditor,
  androidEditorViewModel,
  androidWorkoutListViewModel,
  androidTrainingExperience,
  androidNavigation,
  androidDestinations,
  androidActive,
  androidRepository,
  androidDataLimits,
  androidLaunchPlan,
  androidSharedWorkout,
  androidGarminSyncSecurity,
  androidWeightInput,
  androidEnglish,
  androidUkrainian,
  androidRussian,
  iosWorkouts,
  iosEditor,
  iosEditorComponents,
  iosRoot,
  iosActive,
  iosTrainingGuidance,
  iosSharedWorkout,
  iosGarminCloud,
  iosActiveStore,
  iosLocalizationSource,
  iosCoreParityTests,
  rootHtml,
  sharedWorkoutHtml,
  sharedWorkoutScript
] = await Promise.all([
  readFile("shared/workout-plan-editing-v1.json", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/WorkoutListScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/AddWorkoutScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/AddWorkoutViewModel.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/viewmodel/WorkoutListViewModel.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/TrainingExperience.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/navigation/GymNavGraph.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/navigation/AppDestination.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/GymRepository.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/WorkoutDataLimits.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/SmartWorkoutLaunchPlan.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/data/repository/SharedWorkoutLink.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncSecurity.kt", "utf8"),
  readFile("app/src/main/java/com/example/gymapp/util/WeightInputParser.kt", "utf8"),
  readFile("app/src/main/res/values/strings.xml", "utf8"),
  readFile("app/src/main/res/values-uk/strings.xml", "utf8"),
  readFile("app/src/main/res/values-ru/strings.xml", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/WorkoutsView.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/AddWorkoutView.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Components/WorkoutEditorComponents.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/App/AppRootView.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/UI/Screens/ActiveWorkoutView.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/TrainingGuidance.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Domain/SharedWorkoutLink.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Services/GarminCloudService.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Data/ActiveWorkoutStore.swift", "utf8"),
  readFile("ios/GymApp-iOS/GymApp/Resources/Localizable.xcstrings", "utf8"),
  readFile("ios/GymApp-iOS/GymAppTests/CoreParityTests.swift", "utf8"),
  readFile("pwa/index.html", "utf8"),
  readFile("pwa/workout/index.html", "utf8"),
  readFile("pwa/workout/landing.v2.js", "utf8")
]);

const contract = JSON.parse(contractSource);
const iosLocalization = JSON.parse(iosLocalizationSource);

function assertOrdered(source, markers, label) {
  let previous = -1;
  for (const marker of markers) {
    const current = source.indexOf(marker);
    assert.notEqual(current, -1, `${label} is missing ${marker}`);
    assert.ok(current > previous, `${label} must place ${marker} after the prior surface`);
    previous = current;
  }
}

function functionBody(source, signature) {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `Missing function ${signature}`);
  const nextFunction = source.indexOf("\n    private func ", start + signature.length);
  const nextProperty = source.indexOf("\n    private var ", start + signature.length);
  const boundaries = [nextFunction, nextProperty].filter(index => index > start);
  const end = boundaries.length ? Math.min(...boundaries) : source.length;
  return source.slice(start, end);
}

function iosTranslation(key, locale) {
  return iosLocalization.strings[key]?.localizations?.[locale]?.stringUnit?.value;
}

test("workout-plan editing v1 defines one exact native flow and browser exception", () => {
  assert.equal(contract.schemaVersion, 1);
  assert.deepEqual(contract.scope, {
    fullEditors: ["android", "ios"],
    browser: "shared-plan-preview-and-native-handoff-only"
  });
  assert.deepEqual(contract.locales.order, ["en", "uk", "ru"]);
  assert.deepEqual(contract.locales.copy.todayEditPlan, {
    en: "Edit plan",
    uk: "Редагувати план",
    ru: "Редактировать план"
  });
  assert.deepEqual(contract.locales.copy.todayStartPlan, {
    en: "Start plan",
    uk: "Почати план",
    ru: "Начать план"
  });
  assert.deepEqual(contract.locales.copy.editorTitle, {
    en: "Workout plan",
    uk: "План тренування",
    ru: "План тренировки"
  });
  assert.deepEqual(contract.locales.copy.startWorkout, {
    en: "Start workout",
    uk: "Почати тренування",
    ru: "Начать тренировку"
  });
  assert.deepEqual(contract.locales.copy.continueWorkout, {
    en: "Continue workout",
    uk: "Продовжити тренування",
    ru: "Продолжить тренировку"
  });
  assert.deepEqual(contract.locales.copy.syncPlanToGarmin, {
    en: "Sync plan to Garmin",
    uk: "Синхронізувати план із Garmin",
    ru: "Синхронизировать план с Garmin"
  });
  assert.deepEqual(contract.locales.copy.clearPlan, {
    en: "Clear plan",
    uk: "Очистити план",
    ru: "Очистить план"
  });
  assert.deepEqual(contract.locales.copy.clearPlanTitle, {
    en: "Clear workout plan?",
    uk: "Очистити план тренування?",
    ru: "Очистить план тренировки?"
  });
  assert.deepEqual(contract.locales.copy.clearPlanMessage, {
    en: "All exercises and sets will be removed.",
    uk: "Усі вправи й підходи буде видалено.",
    ru: "Все упражнения и подходы будут удалены."
  });
  assert.deepEqual(contract.locales.copy.keepPlan, {
    en: "Keep plan",
    uk: "Залишити план",
    ru: "Оставить план"
  });
  assert.deepEqual(contract.locales.copy.smartCoachTitle, {
    en: "Smart Coach",
    uk: "Розумний тренер",
    ru: "Умный тренер"
  });
  assert.deepEqual(contract.locales.copy.addExercise, {
    en: "Add exercise",
    uk: "Додати вправу",
    ru: "Добавить упражнение"
  });
  assert.deepEqual(contract.locales.copy.buildSmartWorkout, {
    en: "Build smart workout",
    uk: "Створити розумне тренування",
    ru: "Создать умную тренировку"
  });
  assert.deepEqual(contract.todayRecommended, {
    actionsInOrder: ["startPlan", "editPlan"],
    startPlanProminence: "primary",
    editPlanProminence: "secondary",
    bothUseSameValidatedLaunchSnapshot: true,
    startPlanOpensEditor: false,
    oneTimeClaimCommitsBeforeActiveWorkoutWrite: true,
    claimedSnapshotMayRetryAfterActiveWriteFailure: false,
    freshSnapshotMayRetryAfterActiveWriteFailure: true,
    startPlanCreatesActiveWorkoutAtomically: true,
    alreadyActiveResultIsSuccess: false,
    startPlanCreatesCompletedHistory: false,
    startPlanSyncsGarmin: false,
    startPlanSharesPlan: false,
    failureLeavesTodayActionable: true
  });
  assert.deepEqual(contract.screenOrder, [
    "coachSettings",
    "smartCoach",
    "editableExercisesAndSets",
    "startWorkout",
    "secondaryOptions"
  ]);
  assert.deepEqual(contract.coachSettings, {
    storage: "accountProfile",
    persistence: "immediate",
    countsAsPlanDraftMutation: false,
    discardPlanChangesEffect: "preserved"
  });
  assert.deepEqual(contract.editableOperations, [
    "addExercise",
    "removeExercise",
    "replaceExercise",
    "addSet",
    "removeSet",
    "editWeight",
    "editReps",
    "regenerateSmartTargets",
    "copyPreviousWorkoutIntoDraft"
  ]);
  assert.equal(contract.draftRules.savePlanActionVisible, false);
  assert.equal(contract.draftRules.initialHydrationIsDirty, false);
  assert.equal(contract.draftRules.dirtyCancelRequiresConfirmation, true);
  assert.equal(contract.draftRules.dirtyGestureDismissAllowed, false);
  assert.equal(contract.draftRules.sourceHistoryMutation, "none");
  assert.deepEqual(contract.clearPlan, {
    scope: "planEditorOnly",
    placement: "editableExercisesAndSets",
    visibleWhen: "draftIsNonempty",
    requiresConfirmation: true,
    emptyRepresentation: "zeroExerciseDrafts",
    clearInOneLocalEditorMutation: [
      "exerciseDraftsAndSets",
      "generatedSmartPlan",
      "smartGeneratedDraftIds",
      "smartPlanStaleFlag",
      "replacementOrAlternativePicker",
      "garminDraftSubmission",
      "garminSyncResultAndError",
      "validationErrorsBoundToRemovedDraft"
    ],
    preserve: [
      "trainingProfile",
      "selectedSmartEffort",
      "workoutDate",
      "note",
      "workoutHistory",
      "activeWorkout",
      "accountSession",
      "garminDeviceBinding"
    ],
    networkCalls: [],
    historyMutation: "none",
    activeWorkoutMutation: "none",
    accountMutation: "none",
    garminRemoteMutation: "none",
    lateGarminResultMayRestoreClearedState: false,
    resultIsDirty: true,
    emptyStateActionsInOrder: ["addExercise"],
    startShareAndGarminActionsEnabledWhenEmpty: false
  });
  assert.deepEqual(contract.setValueSemantics, {
    weightUnit: "kg",
    unknownRecommendedWeightMaterializesAs: 0,
    zeroWeightIsValid: true,
    textualWeightBlankIsInvalidAtActionBoundary: true,
    weightMustBeFinite: true,
    minimumWeightInclusive: 0,
    maximumWeightInclusive: 1_000_000,
    minimumRepsInclusive: 1,
    maximumRepsInclusive: 10_000,
    sameMeaningRequiredAcross: [
      "editor",
      "todayDirectStart",
      "activeWorkoutDraft",
      "sharedWorkoutPayload",
      "garminPlanPayload"
    ]
  });
  assert.equal(contract.garmin.action, "syncCurrentEditedDraft");
  assert.equal(contract.garmin.idempotency, "stableRequestIdPerExactDraftRevision");
  assert.equal(contract.garmin.requestIdRotatesAfterDraftMutation, true);
  assert.equal(contract.garmin.createsActiveWorkout, false);
  assert.equal(contract.garmin.createsCompletedHistory, false);
  assert.deepEqual(contract.activeWorkoutException, {
    todayAction: "continueWorkout",
    editPlanEntryVisible: false,
    secondActiveWorkoutAllowed: false,
    sharedLivePlanRemainsFrozen: true
  });
  assert.deepEqual(contract.launchSecurity, {
    accountBound: true,
    profileCatalogAndHistoryBound: true,
    maximumAgeMilliseconds: 300000,
    futureSkewMilliseconds: 60000,
    oneTimeUse: true,
    claimLifetime: {
      android: "processRestorableSavedState",
      ios: "rootLocalNonRestorableSeedIdentity"
    },
    rawJsonPlanInNavigationArgument: false,
    navigationHandoff: {
      android: "boundedValidatedOpaqueLaunchToken",
      androidMaximumTokenCharacters: 12000,
      ios: "rootLocalValidatedSeedObject"
    }
  });

  assert.deepEqual(
    contract.transitions.map(({ from, action, to }) => [from, action, to]),
    [
      ["todayRecommended", "startPlan", "activeWorkout"],
      ["todayRecommended", "editPlan", "planEditorClean"],
      ["planEditorClean", "cancel", "todayRecommended"],
      ["planEditorClean", "editDraft", "planEditorDirty"],
      ["planEditorDirty", "cancel", "dirtyCancelConfirmation"],
      ["dirtyCancelConfirmation", "keepEditing", "planEditorDirty"],
      ["dirtyCancelConfirmation", "discardChanges", "todayRecommended"],
      ["planEditorCleanOrDirty", "startWorkout", "activeWorkout"],
      ["planEditorCleanOrDirty", "syncPlanToGarmin", "samePlanEditorState"],
      ["planEditorNonempty", "clearPlan", "clearPlanConfirmation"],
      ["clearPlanConfirmation", "keepPlan", "samePlanEditorState"],
      ["clearPlanConfirmation", "clearPlan", "planEditorEmptyDirty"],
      ["todayWithActiveWorkout", "continueWorkout", "activeWorkout"]
    ]
  );
});

test("Android exposes direct Start plan plus Edit plan and the canonical editor order", () => {
  assert.match(androidEnglish, /<string name="(?:today|activation)_start_plan">Start plan<\/string>/);
  assert.match(androidUkrainian, /<string name="(?:today|activation)_start_plan">Почати план<\/string>/);
  assert.match(androidRussian, /<string name="(?:today|activation)_start_plan">Начать план<\/string>/);
  assert.match(androidEnglish, /<string name="today_edit_plan">Edit plan<\/string>/);
  assert.match(androidUkrainian, /<string name="today_edit_plan">Редагувати план<\/string>/);
  assert.match(androidRussian, /<string name="today_edit_plan">Редактировать план<\/string>/);
  assert.match(androidEnglish, /<string name="title_workout_plan">Workout plan<\/string>/);
  assert.match(androidUkrainian, /<string name="title_workout_plan">План тренування<\/string>/);
  assert.match(androidRussian, /<string name="title_workout_plan">План тренировки<\/string>/);
  assert.match(androidWorkouts, /launchToken[\s\S]*R\.string\.(?:today|activation)_start_plan/);
  assert.match(androidWorkouts, /launchToken[\s\S]*R\.string\.today_edit_plan/);
  assert.match(androidWorkouts, /onStartPlan/);
  assert.match(androidWorkouts, /onOpenPlan/);
  assert.match(androidDestinations, /data object AddWorkout[\s\S]*labelRes = R\.string\.title_workout_plan/);
  assert.match(androidNavigation, /startsWith\(AppDestination\.AddWorkout\.route\)[\s\S]*R\.string\.title_workout_plan/);
  assert.doesNotMatch(androidEnglish, /name="action_save_plan"/);
  assert.doesNotMatch(androidEditor, /R\.string\.action_save_plan/);
  for (const [source, expected] of [
    [androidEnglish, ["Smart Coach", "Add exercise", "Build smart workout"]],
    [androidUkrainian, ["Розумний тренер", "Додати вправу", "Створити розумне тренування"]],
    [androidRussian, ["Умный тренер", "Добавить упражнение", "Создать умную тренировку"]]
  ]) {
    for (const copy of expected) {
      assert.ok(source.includes(`>${copy}</string>`), `Missing exact Android plan copy: ${copy}`);
    }
  }

  assertOrdered(androidEditor, [
    "TrainingProfilePanel(",
    "SmartCoachPanel(",
    "itemsIndexed(",
    "onClick = onStartWorkout",
    "add_workout_plan_templates"
  ], "Android workout-plan editor");

  for (const operation of [
    "onAddExerciseDraft",
    "onRemoveExerciseDraft",
    "onExerciseSelected",
    "onAddSet",
    "onRemoveSet",
    "onSetWeightChanged",
    "onSetRepsChanged",
    "onGenerateSmartWorkout",
    "onCopyWorkoutTemplate"
  ]) {
    assert.match(androidEditor, new RegExp(`\\b${operation}\\b`));
  }
});

test("iOS exposes the same direct Start plan, Edit plan, and editor order", () => {
  assert.match(
    iosWorkouts,
    /gymText\(\s*"Start plan",\s*"Почати план",\s*"Начать план"/s
  );
  assert.match(
    iosWorkouts,
    /gymText\(\s*"Edit plan",\s*"Редагувати план",\s*"Редактировать план"/s
  );
  assertOrdered(iosWorkouts, [
    "_ = onStartPlan(launchSeed)",
    "_ = onAddWorkout(launchSeed)"
  ], "iOS Today recommended actions");
  assert.match(
    iosEditor,
    /navigationTitle\([\s\S]*"Workout plan"[\s\S]*"План тренування"[\s\S]*"План тренировки"/
  );
  assert.doesNotMatch(iosEditor, /"Save plan"/);
  for (const [key, uk, ru] of [
    ["Smart Coach", "Розумний тренер", "Умный тренер"],
    ["Add exercise", "Додати вправу", "Добавить упражнение"],
    ["Build smart workout", "Створити розумне тренування", "Создать умную тренировку"]
  ]) {
    assert.equal(iosTranslation(key, "uk"), uk);
    assert.equal(iosTranslation(key, "ru"), ru);
  }
  const iosEditorStackStart = iosEditor.indexOf("LazyVStack(spacing:");
  const iosEditorStackEnd = iosEditor.indexOf(".padding(.horizontal", iosEditorStackStart);
  const iosEditorStack = iosEditor.slice(iosEditorStackStart, iosEditorStackEnd);
  assert.doesNotMatch(iosEditorStack, /\bhero\b/);
  assert.doesNotMatch(iosEditor, /private var hero: some View/);
  assertOrdered(iosEditorStack, [
    "profilePanel",
    "smartCoachPanel",
    "editorSection",
    "startWorkoutButton",
    "secondaryOptions"
  ], "iOS workout-plan editor");

  const iosCoachStart = iosEditor.indexOf("private var smartCoachPanel: some View");
  const iosCoachEnd = iosEditor.indexOf("private var editorSection: some View", iosCoachStart);
  assert.ok(iosCoachStart >= 0 && iosCoachEnd > iosCoachStart);
  const iosCoach = iosEditor.slice(iosCoachStart, iosCoachEnd);
  assert.match(iosCoach, /LazyVGrid\(/);
  assert.match(iosCoach, /GridItem\(\.flexible\(\), spacing: 8\)[\s\S]*GridItem\(\.flexible\(\), spacing: 8\)/);
  assert.doesNotMatch(iosCoach, /ScrollView\(\.horizontal\)/);

  for (const copy of [
    "Program", "Програма", "Программа",
    "Training days", "Тренувальні дні", "Тренировочные дни",
    "Upper / Lower", "Верх / низ", "Верх/низ",
    "Aesthetic Cut", "Естетика / сушка", "Эстетика/сушка"
  ]) {
    assert.ok(iosEditor.includes(`"${copy}"`), `Missing exact iOS Coach setting copy: ${copy}`);
  }

  for (const operation of [
    "addExercise",
    "onDeleteExercise",
    "showAlternatives",
    "applySmartCoach",
    "applyPreviousWorkout"
  ]) {
    assert.match(iosEditor, new RegExp(`\\b${operation}\\b`));
  }
  assert.match(iosEditorComponents, /draft\.sets\.append\(/);
  assert.match(iosEditorComponents, /draft\.sets\.removeAll/);
  assert.match(iosEditorComponents, /draft\.sets\[index\] = value/);
});

test("Edit plan is mutation-free while direct Start plan and editor Start are active-workout transitions", () => {
  assert.match(
    androidWorkouts,
    /launchToken\?\.let \{ token ->[\s\S]*OutlinedButton\([\s\S]*onClick = \{ onOpenPlan\(token\) \}/
  );
  assert.match(androidNavigation, /onOpenPlan = \{ launchToken[\s\S]*addWorkoutRoute\(launchToken\)/);
  assert.match(androidDestinations, /launchToken\.length in 1\.\.12_000/);
  assert.match(androidDestinations, /Regex\("\^\[A-Za-z0-9_-\]\+\$"\)/);

  const androidDirectNavigationStart = androidNavigation.indexOf(
    "onStartPlan = { launchToken ->"
  );
  const androidDirectNavigationEnd = androidNavigation.indexOf(
    "onOpenPlan = { launchToken ->",
    androidDirectNavigationStart
  );
  assert.ok(
    androidDirectNavigationStart >= 0 && androidDirectNavigationEnd > androidDirectNavigationStart
  );
  const androidDirectNavigation = androidNavigation.slice(
    androidDirectNavigationStart,
    androidDirectNavigationEnd
  );
  assert.match(androidDirectNavigation, /viewModel\.startRecommendedPlan\(launchToken\)/);
  assert.match(androidDirectNavigation, /AppDestination\.ActiveWorkout\.route/);
  assert.match(androidDirectNavigation, /else \{\s*viewModel\.refreshTodayPlan\(\)/);
  assert.doesNotMatch(androidDirectNavigation, /addWorkoutRoute|AddWorkout\.route/);

  const androidDirectStartStart = androidWorkoutListViewModel.indexOf(
    "internal suspend fun startRecommendedPlan(encoded: String): Boolean"
  );
  const androidDirectStartEnd = androidWorkoutListViewModel.indexOf(
    "\n    private fun rejectPendingActivation(",
    androidDirectStartStart
  );
  assert.ok(androidDirectStartStart >= 0 && androidDirectStartEnd > androidDirectStartStart);
  const androidDirectStart = androidWorkoutListViewModel.slice(
    androidDirectStartStart,
    androidDirectStartEnd
  );
  assert.match(androidDirectStart, /recommendedLaunchMutationMutex\.withLock/);
  assert.match(androidDirectStart, /resolveLaunchPlan\(encoded\)/);
  assert.match(androidDirectStart, /SmartWorkoutLaunchOrigin\.Recommended/);
  assert.match(androidDirectStart, /RecommendedWorkoutStartCommitter\.start\(/);
  assert.match(androidDirectStart, /savedStateHandle\[CONSUMED_LAUNCHES_KEY\] = consumed/);
  assert.match(androidDirectStart, /repository\.startActiveWorkout\(/);
  assert.doesNotMatch(
    androidDirectStart,
    /addWorkoutRoute|createWorkout|saveWorkout|syncPlanToWatch|pushWorkoutPlan|Garmin|share/
  );

  const androidCommitterStart = androidTrainingExperience.indexOf(
    "internal object RecommendedWorkoutStartCommitter"
  );
  const androidCommitterEnd = androidTrainingExperience.indexOf(
    "\ninternal data class PendingFirstWorkoutActivation",
    androidCommitterStart
  );
  assert.ok(androidCommitterStart >= 0 && androidCommitterEnd > androidCommitterStart);
  const androidCommitter = androidTrainingExperience.slice(
    androidCommitterStart,
    androidCommitterEnd
  );
  assertOrdered(
    androidCommitter,
    [
      "materializeSmartWorkoutDrafts(plan)",
      "runCatching(claimAndPersist)",
      "startActiveWorkout(drafts)"
    ],
    "Android direct Start one-time claim"
  );
  assert.match(
    androidCommitter,
    /return startActiveWorkout\(drafts\) == StartActiveWorkoutResult\.Started/
  );
  assert.doesNotMatch(androidCommitter, /AlreadyActive|release|rollback/i);

  assert.match(androidEditorViewModel, /fun startWorkout\(\)[\s\S]*repository\.startActiveWorkout\(/);
  const androidLaunchHydrationStart = androidEditorViewModel.indexOf(
    "private fun applyLaunchPlanUnchecked("
  );
  const androidLaunchHydration = androidEditorViewModel.slice(
    androidLaunchHydrationStart,
    androidEditorViewModel.indexOf("\n    fun updateNote", androidLaunchHydrationStart)
  );
  assert.doesNotMatch(androidLaunchHydration, /markDraftDirty\(/);
  const androidSharedHydrationStart = androidEditorViewModel.indexOf(
    "internal suspend fun applySharedWorkoutPlan("
  );
  const androidSharedHydration = androidEditorViewModel.slice(
    androidSharedHydrationStart,
    androidEditorViewModel.indexOf("\n    private fun applyLaunchPlan", androidSharedHydrationStart)
  );
  assert.doesNotMatch(androidSharedHydration, /markDraftDirty\(/);

  assert.match(iosWorkouts, /_ = onAddWorkout\(launchSeed\)/);
  assert.match(iosRoot, /workoutLaunchSeed = launchSeed[\s\S]*showsAddWorkout = true/);
  assert.match(
    iosRoot,
    /onStartPlan: \{ launchSeed in[\s\S]*DirectWorkoutPlanStarter\.start\([\s\S]*showsActiveWorkout = true/
  );
  const iosDirectStart = iosTrainingGuidance.slice(
    iosTrainingGuidance.indexOf("enum DirectWorkoutPlanStarter"),
    iosTrainingGuidance.indexOf("\n}", iosTrainingGuidance.indexOf("enum DirectWorkoutPlanStarter")) + 2
  );
  assert.match(iosDirectStart, /seed\.isValid\(/);
  assert.match(iosDirectStart, /activeWorkoutStore\.draft == nil/);
  assert.match(iosDirectStart, /activeWorkoutStore\.accountStorageKey == workoutStore\.accountStorageKey/);
  assert.match(iosDirectStart, /WorkoutLaunchSeedUseGate\.claim\(/);
  assert.match(iosDirectStart, /activeWorkoutStore\.start\(/);
  assertOrdered(
    iosDirectStart,
    ["WorkoutLaunchSeedUseGate.claim(", "activeWorkoutStore.start("],
    "iOS direct Start one-time claim"
  );
  assert.doesNotMatch(
    iosDirectStart,
    /WorkoutLaunchSeedUseGate\.release\(/,
    "A claimed iOS snapshot must stay consumed after a failed active-workout write"
  );
  assert.doesNotMatch(iosDirectStart, /createWorkout|garminCloud|submit\(|share/);
  const iosFailedClaimRegressionStart = iosCoreParityTests.indexOf(
    "func testDirectSmartPlanStartsExactActiveDraftOnceAndRejectsInvalidState()"
  );
  const iosFailedClaimRegressionEnd = iosCoreParityTests.indexOf(
    "\n    func ",
    iosFailedClaimRegressionStart + 8
  );
  assert.ok(
    iosFailedClaimRegressionStart >= 0 &&
      iosFailedClaimRegressionEnd > iosFailedClaimRegressionStart
  );
  const iosFailedClaimRegression = iosCoreParityTests.slice(
    iosFailedClaimRegressionStart,
    iosFailedClaimRegressionEnd
  );
  assert.match(iosFailedClaimRegression, /let failedSeed = seed\(\)/);
  assert.ok(
    (iosFailedClaimRegression.match(/seed: failedSeed/g) ?? []).length >= 2,
    "iOS must retry the exact failed seed in its one-time-claim regression"
  );
  assert.match(iosFailedClaimRegression, /A claimed exact seed remains consumed/);
  assert.match(iosFailedClaimRegression, /seed: seed\(\)/);
  assert.match(iosFailedClaimRegression, /A fresh seed may retry after the failed exact seed/);
  assert.match(iosFailedClaimRegression, /XCTAssertTrue\(store\.workouts\.isEmpty\)/);
  const iosStart = functionBody(iosEditor, "private func startWorkout()");
  assert.match(iosStart, /activeWorkoutStore\.start\(/);
  assert.doesNotMatch(iosStart, /store\.createWorkout\(|garminCloud\.submit\(/);
});

test("unknown recommended weight becomes explicit zero across every plan boundary", () => {
  assert.match(
    androidEditorViewModel,
    /fun smartWorkoutWeightInput\(weight: Double\?\): String \{[\s\S]*weight \?: 0\.0[\s\S]*WorkoutDataLimits\.isValidWeight\(resolved\)/
  );
  assert.ok(
    (androidEditorViewModel.match(/weight = smartWorkoutWeightInput\(set\.weight\)/g) ?? []).length >= 3,
    "Android must materialize nullable weights for launch, generated, and applied recommendations"
  );
  assert.match(
    androidEditorViewModel,
    /private fun parseDrafts\([\s\S]*parseWeightInputOrNull\(set\.weight\)[\s\S]*WorkoutDataLimits\.isValidWeight\(weight\)/
  );
  assert.match(
    androidEditorViewModel,
    /private fun parseNamedDrafts\([\s\S]*parseWeightInputOrNull\(set\.weight\)[\s\S]*WorkoutDataLimits\.isValidWeight\(parsedWeight\)/
  );
  assert.match(
    androidDataLimits,
    /isValidWeight\(weight: Double\)[\s\S]*weight\.isFinite\(\) && weight >= 0\.0 && weight <= MAX_WEIGHT/
  );
  assert.match(androidDataLimits, /isValidReps\(reps: Int\): Boolean = reps in 1\.\.MAX_REPS/);
  assert.match(androidWeightInput, /if \(normalized\.isBlank\(\)\) return null/);
  assert.match(
    androidWeightInput,
    /normalized\.toDoubleOrNull\(\)\?\.takeIf\(WorkoutDataLimits::isValidWeight\)/
  );
  assert.match(
    androidLaunchPlan,
    /fun materializeSmartWorkoutDrafts\([\s\S]*val weight = set\.weight \?: 0\.0[\s\S]*WorkoutDataLimits\.isValidWeight\(weight\)[\s\S]*WorkoutDataLimits\.isValidReps\(set\.reps\)/
  );
  assert.match(
    androidRepository,
    /startActiveWorkout\([\s\S]*requireValidWorkout\([\s\S]*ActiveWorkoutSetEntity\([\s\S]*weight = set\.weight/
  );
  assert.match(
    androidSharedWorkout,
    /set\.weight\.isFinite\(\) && set\.weight in 0\.0\.\.MAX_WEIGHT/
  );
  assert.match(
    androidGarminSyncSecurity,
    /val weight = requiredFiniteDouble\(item, "weight"\)[\s\S]*require\(WorkoutDataLimits\.isValidWeight\(weight\)\)/
  );

  assert.match(iosEditorComponents, /weight = recommendedSet\.weight \?\? 0/);
  assert.doesNotMatch(iosEditorComponents, /requiresWeightSelection/);
  assert.match(
    iosEditorComponents,
    /var isReadyForSave: Bool \{[\s\S]*weight\.isFinite && \(0 \.\.\. 1_000_000\)\.contains\(weight\)/
  );
  assert.match(iosTrainingGuidance, /weight: set\.weight \?\? 0/);
  assert.match(
    iosActiveStore,
    /validate\(weight: Double, reps: Int\)[\s\S]*weight\.isFinite, \(0 \.\.\. maximumWeight\)\.contains\(weight\)[\s\S]*\(1 \.\.\. maximumReps\)\.contains\(reps\)/
  );
  assert.match(
    iosSharedWorkout,
    /set\.weight\.isFinite[\s\S]*\(0 \.\.\. SharedWorkoutLinkEncoder\.maximumWeight\)\.contains\(set\.weight\)/
  );
  assert.match(
    iosGarminCloud,
    /set\.weight\.isFinite[\s\S]*\(0 \.\.\. maximumWeight\)\.contains\(set\.weight\)[\s\S]*\(1 \.\.\. maximumReps\)\.contains\(set\.reps\)/
  );
});

test("dirty Back or Cancel requires the exact discard confirmation on both native platforms", () => {
  for (const [source, expected] of [
    [androidEnglish, ["Discard plan changes?", "Your edits will be lost.", "Keep editing", "Discard changes"]],
    [androidUkrainian, ["Відкинути зміни плану?", "Зміни буде втрачено.", "Продовжити редагування", "Відкинути зміни"]],
    [androidRussian, ["Отменить изменения плана?", "Изменения будут потеряны.", "Продолжить редактирование", "Отменить изменения"]]
  ]) {
    for (const copy of expected) assert.ok(source.includes(`>${copy}</string>`), `Missing Android copy: ${copy}`);
  }
  assert.match(androidEditor, /workout_plan_discard_title/);
  assert.match(androidEditor, /workout_plan_keep_editing/);
  assert.match(androidEditor, /workout_plan_discard_changes/);
  assert.match(
    androidEditor,
    /if \(workoutPlanCloseRequiresConfirmation\(uiState\.isDirty\)\) \{\s*showDiscardConfirmation = true\s*\} else \{\s*onDiscardPlan\(\)\s*\}/
  );
  assert.match(androidEditor, /workoutPlanCloseRequiresConfirmation\(isDirty: Boolean\): Boolean = isDirty/);
  assert.match(androidEditor, /BackHandler\(onBack = requestClose\)/);
  assert.match(androidEditor, /onDirtyStateChanged\(uiState\.isDirty\)/);
  assert.match(androidEditor, /AlertDialog\(/);
  assert.match(
    androidNavigation,
    /startsWith\(AppDestination\.AddWorkout\.route\)[\s\S]*addWorkoutDraftDirty[\s\S]*addWorkoutCloseRequestVersion \+= 1L/
  );

  for (const copy of [
    "Discard plan changes?",
    "Відкинути зміни плану?",
    "Отменить изменения плана?",
    "Your edits will be lost.",
    "Зміни буде втрачено.",
    "Изменения будут потеряны.",
    "Keep editing",
    "Продовжити редагування",
    "Продолжить редактирование",
    "Discard changes",
    "Відкинути зміни",
    "Отменить изменения"
  ]) {
    assert.ok(iosEditor.includes(copy), `Missing iOS copy: ${copy}`);
  }
  assert.match(iosEditor, /confirmationDialog|\.alert\(/);
  assert.match(iosEditor, /isDirty|hasUnsaved|draft.*changed/i);
  assert.match(iosEditor, /interactiveDismissDisabled/);
  assert.match(
    iosEditor,
    /private func requestCancel\(\)[\s\S]*if hasUnsavedPlanChanges[\s\S]*showingDiscardConfirmation = true[\s\S]*else \{[\s\S]*onCancel\(\)/
  );
});

test("Clear plan is editor-only, confirmed, local, and leaves an actionable empty editor", () => {
  assert.equal(contract.clearPlan.scope, "planEditorOnly");
  assert.equal(contract.clearPlan.visibleWhen, "draftIsNonempty");
  assert.equal(contract.clearPlan.requiresConfirmation, true);
  assert.equal(contract.clearPlan.emptyRepresentation, "zeroExerciseDrafts");
  assert.deepEqual(contract.clearPlan.networkCalls, []);
  assert.equal(contract.clearPlan.historyMutation, "none");
  assert.equal(contract.clearPlan.activeWorkoutMutation, "none");
  assert.equal(contract.clearPlan.accountMutation, "none");
  assert.equal(contract.clearPlan.garminRemoteMutation, "none");
  assert.equal(contract.clearPlan.lateGarminResultMayRestoreClearedState, false);
  assert.equal(contract.clearPlan.resultIsDirty, true);
  assert.deepEqual(contract.clearPlan.emptyStateActionsInOrder, [
    "addExercise"
  ]);
  assert.ok(contract.clearPlan.preserve.includes("trainingProfile"));
  assert.ok(contract.clearPlan.preserve.includes("selectedSmartEffort"));
  assert.ok(contract.clearPlan.clearInOneLocalEditorMutation.includes("garminDraftSubmission"));
  assert.ok(contract.clearPlan.clearInOneLocalEditorMutation.includes("replacementOrAlternativePicker"));

  for (const [source, expected] of [
    [androidEnglish, ["Clear plan", "Clear workout plan?", "All exercises and sets will be removed.", "Keep plan"]],
    [androidUkrainian, ["Очистити план", "Очистити план тренування?", "Усі вправи й підходи буде видалено.", "Залишити план"]],
    [androidRussian, ["Очистить план", "Очистить план тренировки?", "Все упражнения и подходы будут удалены.", "Оставить план"]]
  ]) {
    for (const copy of expected) {
      assert.ok(source.includes(`>${copy}</string>`), `Missing exact Android Clear plan copy: ${copy}`);
    }
  }
  assert.match(
    androidEditor,
    /if \(uiState\.exerciseDrafts\.isNotEmpty\(\)\) \{[\s\S]*showClearConfirmation = true[\s\S]*workout_plan_clear_action/
  );
  assert.match(
    androidEditor,
    /if \(showClearConfirmation\) \{[\s\S]*AlertDialog\([\s\S]*workout_plan_clear_title[\s\S]*workout_plan_clear_message[\s\S]*onClearPlan\(\)/
  );
  const androidClearStart = androidEditorViewModel.indexOf("fun clearWorkoutPlan(): Boolean");
  const androidClearEnd = androidEditorViewModel.indexOf(
    "\n    fun updateExerciseSelection(",
    androidClearStart
  );
  assert.ok(androidClearStart >= 0 && androidClearEnd > androidClearStart);
  const androidClear = androidEditorViewModel.slice(androidClearStart, androidClearEnd);
  for (const mutation of [
    "resetWatchPlanSyncResult()",
    "generatedSmartPlan.value = null",
    "smartAlternativePicker.value = null",
    "exerciseDrafts.value = emptyList()",
    "hasValidationError.value = false",
    "markDraftDirty()"
  ]) {
    assert.ok(androidClear.includes(mutation), `Android Clear plan is missing ${mutation}`);
  }
  assert.doesNotMatch(
    androidClear,
    /trainingProfile|smartWorkoutEffort|workoutDate|note\.value|repository\.|syncClient\.|startActiveWorkout|pushWorkoutPlan/
  );
  assert.match(
    androidEditorViewModel,
    /private fun resetWatchPlanSyncResult\(\) \{\s*watchPlanSyncGeneration \+= 1L[\s\S]*didSyncPlanToWatch\.value = null[\s\S]*watchPlanSyncError\.value = null/
  );
  assert.match(
    androidEditorViewModel,
    /if \(watchPlanSyncResultIsCurrent\(syncGeneration, watchPlanSyncGeneration\)\) \{[\s\S]*didSyncPlanToWatch\.value = true/
  );
  const androidEmptyStart = androidEditor.indexOf("if (uiState.exerciseDrafts.isEmpty()) {");
  const androidEmptyEnd = androidEditor.indexOf("\n        itemsIndexed(", androidEmptyStart);
  assert.ok(androidEmptyStart >= 0 && androidEmptyEnd > androidEmptyStart);
  const androidEmpty = androidEditor.slice(androidEmptyStart, androidEmptyEnd);
  assert.match(androidEmpty, /R\.string\.action_add_exercise/);
  assert.doesNotMatch(androidEmpty, /R\.string\.action_generate_smart_workout/);
  assert.match(
    androidEditor,
    /title = stringResource\(R\.string\.title_exercises\)[\s\S]{0,900}if \(uiState\.exerciseDrafts\.isNotEmpty\(\)\) \{\s*Button\(onClick = onAddExerciseDraft\)/
  );
  assert.match(
    androidEditor,
    /onClick = onStartWorkout[\s\S]*enabled = !uiState\.isSaving && uiState\.exerciseDrafts\.isNotEmpty\(\)/
  );
  assert.match(
    androidEditor,
    /onClick = onSyncPlanToWatch[\s\S]*enabled = selectedExerciseCount > 0/
  );
  assert.match(
    androidEditor,
    /onClick = onShareWorkout[\s\S]*enabled = selectedExerciseCount > 0/
  );

  for (const copy of [
    "Clear plan",
    "Очистити план",
    "Очистить план",
    "Clear workout plan?",
    "Очистити план тренування?",
    "Очистить план тренировки?",
    "All exercises and sets will be removed.",
    "Усі вправи й підходи буде видалено.",
    "Все упражнения и подходы будут удалены.",
    "Keep plan",
    "Залишити план",
    "Оставить план"
  ]) {
    assert.ok(iosEditor.includes(copy), `Missing exact iOS Clear plan copy: ${copy}`);
  }
  assert.match(iosEditor, /if !drafts\.isEmpty \{[\s\S]*showingClearPlanConfirmation = true/);
  assert.match(iosEditor, /\.confirmationDialog\([\s\S]*isPresented: \$showingClearPlanConfirmation/);
  const iosClear = functionBody(iosEditor, "private func clearPlan()");
  for (const mutation of [
    "drafts.removeAll()",
    "latestSmartPlan = nil",
    "smartGeneratedDraftIDs.removeAll()",
    "smartPlanIsStale = false",
    "replacementRequest = nil",
    "garminDraftSubmission = nil"
  ]) {
    assert.ok(iosClear.includes(mutation), `iOS Clear plan is missing ${mutation}`);
  }
  assert.doesNotMatch(
    iosClear,
    /profile\s*=|selectedEffort\s*=|store\.|activeWorkoutStore\.|garminCloud\.|submit\(|onStarted\(|onSaved\(/
  );
  assert.match(iosEditor, /garminDraftSubmission == submission/);
  assert.match(iosEditor, /\.disabled\(isSaving \|\| drafts\.isEmpty \|\| activeWorkoutStore\.draft != nil\)/);
  assert.match(iosEditor, /\.disabled\(isSaving \|\| drafts\.isEmpty\)/);
  assert.match(iosEditor, /drafts\.isEmpty \|\| garminCloud\.isWorking/);
  const iosEmptyStart = iosEditor.indexOf("if drafts.isEmpty {");
  const iosEmptyEnd = iosEditor.indexOf("} else {", iosEmptyStart);
  const iosEmpty = iosEditor.slice(iosEmptyStart, iosEmptyEnd);
  assert.match(iosEmpty, /"Add exercise"/);
  assert.doesNotMatch(iosEmpty, /"Build smart workout"|Button\(action: applySmartCoach\)/);
  assert.doesNotMatch(iosEmpty, /GymContentUnavailableView|"No exercises"|GymPanel/);
  assert.match(iosEmpty, /\.buttonStyle\(GymPrimaryButtonStyle\(\)\)/);
  const iosExerciseHeaderStart = iosEditor.indexOf("private var editorSection: some View");
  const iosExerciseHeaderEnd = iosEditor.indexOf("if drafts.isEmpty {", iosExerciseHeaderStart);
  const iosExerciseHeader = iosEditor.slice(iosExerciseHeaderStart, iosExerciseHeaderEnd);
  assert.match(iosExerciseHeader, /if !drafts\.isEmpty \{[\s\S]*Label\("Add", systemImage: "plus"\)/);
  assert.doesNotMatch(androidActive, /clear[_A-Za-z]*plan|onClearPlan/i);
  assert.doesNotMatch(iosActive, /clear\s*plan|clearPlan/i);
});

test("Garmin sync submits the edited draft without starting or writing workout history", () => {
  assert.match(androidEnglish, /<string name="action_sync_plan_to_garmin">Sync plan to Garmin<\/string>/);
  assert.match(androidUkrainian, /<string name="action_sync_plan_to_garmin">Синхронізувати план із Garmin<\/string>/);
  assert.match(androidRussian, /<string name="action_sync_plan_to_garmin">Синхронизировать план с Garmin<\/string>/);
  assert.match(androidEditor, /R\.string\.action_sync_plan_to_garmin/);
  const androidSyncStart = androidEditorViewModel.indexOf("fun syncPlanToWatch()");
  const androidSyncEnd = androidEditorViewModel.indexOf("\n    fun openWorkoutTemplatePicker", androidSyncStart);
  assert.ok(androidSyncStart >= 0 && androidSyncEnd > androidSyncStart);
  const androidSync = androidEditorViewModel.slice(androidSyncStart, androidSyncEnd);
  assert.match(androidSync, /parseNamedDrafts\([\s\S]*syncClient\.pushWorkoutPlan\(/);
  assert.doesNotMatch(androidSync, /startActiveWorkout|saveWorkout|createWorkout|addSession/);

  assert.match(
    iosEditor,
    /gymText\(\s*"Sync plan to Garmin",\s*"Синхронізувати план із Garmin",\s*"Синхронизировать план с Garmin"/s
  );
  const iosSync = functionBody(iosEditor, "private func syncPlanToGarmin()");
  const iosSyncKey = functionBody(
    iosEditor,
    "private func currentGarminSyncKey(binding: GarminDeviceBinding)"
  );
  assert.match(iosSyncKey, /accountStorageKey: store\.accountStorageKey/);
  assert.match(iosSyncKey, /deviceID: binding\.deviceID/);
  assert.match(iosSyncKey, /drafts: drafts/);
  assert.match(iosSync, /garminCloud\.submit\(/);
  assert.match(iosSync, /prepareGarminDraftSubmission\([\s\S]*existing: garminDraftSubmission/);
  assert.match(
    iosEditor,
    /if let existing, existing\.key == key[\s\S]*return existing[\s\S]*clientRequestID: makeRequestID\(\)/
  );
  assert.match(
    iosSync,
    /store\.accountStorageKey == submission\.key\.accountStorageKey[\s\S]*selectedDevice\?\.deviceID == submission\.key\.deviceID[\s\S]*currentGarminSyncKey\(binding: binding\) == submission\.key/
  );
  assert.doesNotMatch(iosSync, /store\.createWorkout\(|activeWorkoutStore\.start\(|onSaved\(|onStarted\(/);
});

test("an active workout keeps Continue instead of exposing a second plan editor", () => {
  assert.match(androidWorkouts, /hasActiveWorkout[\s\S]*R\.string\.action_continue_workout/);
  assert.doesNotMatch(androidActive, /onAddExerciseDraft|onRemoveExerciseDraft|onGenerateSmartWorkout/);
  assert.match(iosWorkouts, /hasActiveWorkout[\s\S]*"Continue workout"/);
  assert.match(iosRoot, /if activeWorkoutStore\.draft != nil[\s\S]*showsActiveWorkout = true[\s\S]*return false/);
  assert.doesNotMatch(iosActive, /applySmartCoach|showingExercisePicker|removeExercise/);
});

test("browser remains a retirement landing plus validated native handoff, never a plan editor", () => {
  assert.equal(contract.browserException.rootWorkoutEditor, false);
  assert.equal(contract.browserException.sharedWorkoutRoute, "/workout/");
  assert.equal(contract.browserException.browserDraftPersistence, false);
  assert.equal(contract.browserException.continueOnWebsiteAction, false);
  assert.doesNotMatch(rootHtml, /app\.v\d+\.js|shared-workout|workout-editor|add-workout/i);
  assert.match(sharedWorkoutHtml, /shared-workout\.v\d+\.js/);
  assert.match(sharedWorkoutHtml, /landing\.v2\.js/);
  assert.doesNotMatch(sharedWorkoutHtml, /app\.v\d+\.js|continue-web|Continue on website/);
  assert.doesNotMatch(sharedWorkoutHtml, /<(?:form|input|textarea|select)\b/i);
  assert.match(sharedWorkoutScript, /codec\?\.fromHash|codec\.fromHash/);
  assert.match(sharedWorkoutScript, /ANDROID_SCHEME/);
  assert.match(sharedWorkoutScript, /IOS_SCHEME/);
  assert.doesNotMatch(sharedWorkoutScript, /localStorage|indexedDB|createWorkout|startWorkout/);
});
