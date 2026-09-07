import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const [
  contractSource,
  pwaSource,
  pwaRussianSource,
  iosTutorialSource,
  iosWorkoutsSource,
  iosActiveWorkoutSource,
  androidTodaySource,
  androidTodayViewModel,
  androidActiveWorkoutSource,
  androidEnglish,
  androidUkrainian,
  androidRussian
] = await Promise.all([
  readFile(new URL("shared/product-experience-v2.json", root), "utf8"),
  readFile(new URL("pwa/app.js", root), "utf8"),
  readFile(new URL("pwa/russian-text.js", root), "utf8"),
  readFile(new URL("ios/GymApp-iOS/GymApp/UI/Components/AppTutorialOverlay.swift", root), "utf8"),
  readFile(new URL("ios/GymApp-iOS/GymApp/UI/Screens/WorkoutsView.swift", root), "utf8"),
  readFile(new URL("ios/GymApp-iOS/GymApp/UI/Screens/ActiveWorkoutView.swift", root), "utf8"),
  readFile(new URL("app/src/main/java/com/example/gymapp/ui/screens/WorkoutListScreen.kt", root), "utf8"),
  readFile(new URL("app/src/main/java/com/example/gymapp/ui/viewmodel/WorkoutListViewModel.kt", root), "utf8"),
  readFile(new URL("app/src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt", root), "utf8"),
  readFile(new URL("app/src/main/res/values/strings.xml", root), "utf8"),
  readFile(new URL("app/src/main/res/values-uk/strings.xml", root), "utf8"),
  readFile(new URL("app/src/main/res/values-ru/strings.xml", root), "utf8")
]);
const contract = JSON.parse(contractSource);

test("product experience v2 defines one full-client navigation and tutorial", () => {
  assert.equal(contract.schemaVersion, 2);
  assert.equal(contract.productVersion, "3.3.0");
  assert.deepEqual(contract.fullClients, ["android", "ios", "pwa"]);
  assert.deepEqual(contract.navigation.fullClientTabOrder, [
    "today",
    "exercises",
    "progress",
    "profile"
  ]);
  assert.equal(
    contract.navigation.profile,
    "friendsLiveWorkoutsAccountProfilesDevicesSettingsAndHelp"
  );
  assert.deepEqual(contract.terminology.profileSections, [
    "friendsAndLive",
    "accountAndDevices"
  ]);
  assert.deepEqual(
    contract.tutorial.steps.map(step => step.id),
    ["todayFocus", "todayPrimaryAction", "exercises", "progress", "profile"]
  );
  assert.equal(contract.tutorial.automaticRunsPerAccountOrLocalProfile, 1);
  assert.equal(contract.tutorial.manualReplayPath, "profile.help.showTutorial");
  assert.equal(contract.tutorial.accountBound, true);
  assert.equal(contract.tutorial.lateOldAccountResult, "ignored");
  assert.ok(contract.tutorial.deferWhile.includes("pushOrDeepLinkTarget"));
  assert.ok(contract.tutorial.deferWhile.includes("activeWorkout"));
  assert.equal(contract.tutorial.accessibility.reducedMotionDisablesHaloAnimation, true);
});

test("today, first workout, and progress use the same information architecture", () => {
  assert.deepEqual(contract.firstWorkout.entryActionsInOrder, [
    "startPlan",
    "createManually",
    "adjustRecommendation"
  ]);
  assert.deepEqual(contract.firstWorkout.adjustRecommendationContains, [
    "goal", "daysPerWeek", "effort", "editPlan"
  ]);
  assert.deepEqual(contract.todayFocusLens.states, [
    "recommendedPlan",
    "activeWorkout",
    "completedToday",
    "recovery"
  ]);
  assert.deepEqual(contract.todayFocusLens.trainingHistory.periodsInOrder, ["week", "month"]);
  assert.equal(contract.todayFocusLens.trainingHistory.defaultPeriod, "week");
  assert.equal(contract.todayFocusLens.trainingHistory.singleSurface, true);
  assert.equal(contract.todayFocusLens.trainingHistory.oneNavigatorForSelectedPeriod, true);
  assert.equal(contract.todayFocusLens.trainingHistory.oneWorkoutListFilteredToSelectedPeriod, true);
  assert.equal(contract.todayFocusLens.trainingHistory.separateWeeklyAndSavedWorkoutSections, false);
  assert.deepEqual(contract.todayFocusLens.trainingHistory.sharedMetricsInOrder, [
    "completedWorkouts", "trainingMinutes", "totalVolume"
  ]);
  assert.deepEqual(contract.todayFocusLens.trainingHistory.week.controls, [
    "previousWeek", "returnToCurrentWeek", "nextWeek", "horizontalSwipe"
  ]);
  assert.deepEqual(contract.todayFocusLens.trainingHistory.month.controls, [
    "previousMonth", "returnToCurrentMonth", "nextMonth", "horizontalSwipe"
  ]);
  assert.equal(contract.todayFocusLens.trainingHistory.week.minimumOffset, -5200);
  assert.equal(contract.todayFocusLens.trainingHistory.month.minimumOffset, -1200);
  assert.equal(contract.todayFocusLens.trainingHistory.futureNavigationDisabled, true);
  assert.equal(contract.todayFocusLens.completedToday.suppresses.includes("recovery"), true);
  assert.deepEqual(contract.todayFocusLens.completedToday.actionsInOrder, ["createAnotherWorkout"]);
  assert.deepEqual(contract.todayFocusLens.retainedDraftOverride, {
    appliesToStates: ["recommendedPlan", "completedToday", "recovery", "firstWorkoutActivation"],
    actionsInOrder: ["continuePlan", "cancelPlan"],
    continueOutcome: "openSameAccountRetainedDraftWithoutReplacement",
    cancelPlan: {
      visibleWithoutOverflow: true,
      confirmationRequired: true,
      removes: ["sameAccountRetainedDraft", "selectedLiveRecipient"],
      preserves: ["completedWorkoutHistory", "activeWorkout"]
    }
  });
  assert.equal(contract.todayFocusLens.lifetimeMetricsPlacement, "today.heroAndProgress.overview");
  assert.equal(contract.todayFocusLens.heatmapPlacement, "progress.overview");
  assert.equal(contract.todayFocusLens.muscleLoadPlacement, "progress.overview");
  assert.deepEqual(contract.todayFocusLens.progressiveDisclosure.activeWorkoutExercises, {
    current: "expanded",
    completed: "collapsed",
    upcoming: "collapsed"
  });
  assert.deepEqual(contract.todayFocusLens.activeWorkout.hero.primaryMetrics, [
    "elapsed", "completed"
  ]);
  assert.equal(contract.todayFocusLens.activeWorkout.hero.secondaryContext, "startedAt");
  assert.equal(
    contract.todayFocusLens.activeWorkout.hero.everyTimeValueHasVisibleLabel,
    true
  );
  assert.equal(
    contract.todayFocusLens.progressiveDisclosure.destructiveActions,
    "collapsedBehindMoreOptions"
  );
  assert.equal(contract.terminology.missionsPlacement, "progress.goals");
});

test("Today exposes one bounded week or month history surface on every full client", () => {
  assert.match(pwaSource, /data-action="history-period" data-period="week"/);
  assert.match(pwaSource, /data-action="history-period" data-period="month"/);
  assert.match(pwaSource, /data-action="\$\{period\}-prev"/);
  assert.match(pwaSource, /data-action="\$\{period\}-current"/);
  assert.match(pwaSource, /data-action="\$\{period\}-next"/);
  assert.match(pwaSource, /Math\.max\(-5200, workoutWeekOffset - 1\)/);
  assert.match(pwaSource, /Math\.max\(-1200, monthOffsets\.workouts - 1\)/);
  assert.match(pwaSource, /training-history-list/);
  assert.match(pwaSource, /training-history-row/);

  assert.match(iosWorkoutsSource, /@State private var weekOffset = 0/);
  assert.match(iosWorkoutsSource, /@State private var historyPeriod: TrainingHistoryPeriod = \.week/);
  assert.match(iosWorkoutsSource, /weekOffset = max\(-5_200, weekOffset - 1\)/);
  assert.match(iosWorkoutsSource, /monthOffset = max\(-1_200, monthOffset - 1\)/);
  assert.match(iosWorkoutsSource, /private var trainingHistoryPanel: some View/);
  assert.match(iosWorkoutsSource, /let workouts = historyPeriod == \.week/);

  assert.match(androidTodaySource, /TrainingHistoryPanel\(/);
  assert.match(androidTodaySource, /TrainingHistoryPeriod\.Week/);
  assert.match(androidTodaySource, /TrainingHistoryPeriod\.Month/);
  assert.match(androidTodaySource, /val historyWorkouts = when/);
  assert.match(androidTodaySource, /onPreviousWeek/);
  assert.match(androidTodayViewModel, /fun previousWeek\(\)/);
  assert.match(androidTodayViewModel, /fun previousMonth\(\)/);
  assert.match(androidTodayViewModel, /coerceAtLeast\(-5_200\)/);
  assert.match(androidTodayViewModel, /coerceAtLeast\(-1_200\)/);
  assert.match(androidTodayViewModel, /monthlyTrainingSummary = monthlyTrainingSummary/);
});

test("retained plans expose a confirmed, history-preserving cancel action on every full client", () => {
  assert.match(pwaSource, /data-action="cancel-retained-plan"/);
  assert.match(pwaSource, /requestDiscardWorkoutDraft\([\s\S]*"today"/);
  assert.match(iosWorkoutsSource, /onCancelPlan/);
  assert.match(iosWorkoutsSource, /showsRetainedPlanCancelConfirmation/);
  assert.match(androidTodaySource, /onCancelRetainedPlan/);
  assert.match(androidTodaySource, /today_cancel_plan_title/);
});

test("live mutation recovery and push navigation preserve confirmed server work", () => {
  assert.equal(
    contract.socialAndLive.successfulMutationRefreshFailure.state,
    "confirmedRestoring"
  );
  assert.equal(
    contract.socialAndLive.successfulMutationRefreshFailure.mustNotReportMutationFailure,
    true
  );
  assert.equal(contract.socialAndLive.liveAcceptance.visibleAction, "startTogether");
  assert.equal(
    contract.socialAndLive.liveAcceptance.authoritativeRoomStatusAfterAccept,
    "active"
  );
  assert.deepEqual(
    contract.socialAndLive.liveAcceptance.legacyMutationResponseStatusesAccepted,
    ["ready", "active"]
  );
  assert.equal(contract.socialAndLive.liveAcceptance.ownerOnlyStartActionVisible, false);
  assert.deepEqual(contract.socialAndLive.pushTarget.preserve, [
    "type",
    "opaqueObjectId",
    "revision",
    "accountBinding"
  ]);
  assert.equal(
    contract.socialAndLive.pushTarget.workoutInviteResolution,
    "boundedCursorSearchUntilFoundCursorEndsOrWindowCaps"
  );
  assert.equal(contract.socialAndLive.workoutInbox.listPayload, "metadataOnly");
  assert.equal(contract.socialAndLive.workoutInbox.maximumResponseBytes, 256 * 1024);
  assert.equal(contract.socialAndLive.workoutInbox.incomingPageSize, 10);
  assert.equal(contract.socialAndLive.workoutInbox.incomingPageMayBeShort, true);
  assert.equal(contract.socialAndLive.workoutInbox.cursorRequiresNonemptyPage, true);
  assert.equal(contract.socialAndLive.workoutInbox.cursorMatchesLastIncomingRow, true);
  assert.equal(contract.socialAndLive.workoutInbox.maximumPages, 20);
  assert.equal(contract.socialAndLive.workoutInbox.maximumRpcPageRequests, 20);
  assert.equal(contract.socialAndLive.workoutInbox.maximumPendingIncomingCount, 25);
  assert.equal(contract.socialAndLive.workoutInbox.maximumIncomingItems, 20);
  assert.equal(contract.socialAndLive.workoutInbox.maximumOutgoingItems, 20);
  assert.equal(contract.socialAndLive.workoutInbox.maximumRenderedItems, 40);
  assert.equal(
    contract.socialAndLive.workoutInbox.loadMoreAction,
    "visibleOnlyWhenNextCursorExists"
  );
  assert.equal(
    contract.socialAndLive.workoutInbox.snapshotMismatch,
    "replaceWithFreshFirstPage"
  );
  assert.equal(contract.socialAndLive.workoutInbox.loadMoreChunkMaximumItems, 10);
  assert.equal(
    contract.socialAndLive.workoutInbox.loadMoreFetch,
    "boundedLoopUntilChunkFullCursorEndsOrWindowCaps"
  );
});

test("Garmin saves FIT before sync and exposes recoverable queue state", () => {
  assert.deepEqual(contract.garmin.finishTransaction.states, [
    "active",
    "prepared",
    "fitSaved",
    "queued",
    "acknowledged"
  ]);
  assert.equal(contract.garmin.finishTransaction.fitSaveBeforeQueue, true);
  assert.equal(contract.garmin.finishTransaction.discardNeverSendsPreparedWorkout, true);
  assert.equal(contract.garmin.finishTransaction.queueFailureNeverBlocksLocalFitSave, true);
  assert.equal(contract.garmin.sync.pendingCountVisible, true);
  assert.equal(contract.garmin.sync.automaticRetry, true);
  assert.equal(contract.garmin.tutorial.manualReplayPath, "settings.tutorial");
});

test("all visible contract copy is complete for EN, UK, and RU", () => {
  const localizedObjects = [
    contract.terminology.firstPlanAction,
    contract.terminology.manualPlanAction,
    contract.terminology.reviewExercisesAction,
    contract.terminology.tutorialAction,
    contract.terminology.liveAcceptAction,
    contract.todayFocusLens.activeWorkout.hero.elapsed,
    contract.todayFocusLens.activeWorkout.hero.completed,
    contract.todayFocusLens.activeWorkout.hero.startedAt,
    ...contract.tutorial.steps.flatMap(step => [step.title, step.body])
  ];
  for (const copy of localizedObjects) {
    assert.deepEqual(Object.keys(copy), ["en", "uk", "ru"]);
    for (const locale of ["en", "uk", "ru"]) {
      assert.equal(typeof copy[locale], "string");
      assert.ok(copy[locale].trim().length > 0);
    }
  }
});

test("PWA visible terminology implements the shared product experience", () => {
  assert.match(
    pwaSource,
    /tx3\("Use suggested plan", "Використати пораду", "Использовать рекомендацию"\)/
  );
  assert.match(pwaSource, /tx\("Start plan", "Почати план"\)/);
  assert.match(pwaSource, /tx\("Edit plan", "Редагувати план"\)/);
  assert.match(
    pwaSource,
    /tx3\("Build manually", "Створити вручну", "Собрать вручную"\)/
  );
  assert.match(pwaSource, /goals:\s*\{[\s\S]*tx\("Goals", "Цілі"\)/);
  assert.match(pwaSource, /tx\("Start together", "Почати разом"\)/);
  assert.match(pwaRussianSource, /\["Start together", "Начать вместе"\]/);
  assert.match(pwaRussianSource, /\["Goals", "Цели"\]/);
});

test("active-workout hero disambiguates elapsed, completed, and start time on every client", () => {
  const hero = contract.todayFocusLens.activeWorkout.hero;

  assert.ok(pwaSource.includes(
    `tx3("${hero.elapsed.en}", "${hero.elapsed.uk}", "${hero.elapsed.ru}")`
  ));
  assert.ok(pwaSource.includes(
    `tx3("${hero.completed.en}", "${hero.completed.uk}", "${hero.completed.ru}")`
  ));
  assert.ok(pwaSource.includes(
    `tx3("${hero.startedAt.en}", "${hero.startedAt.uk}", "${hero.startedAt.ru}")`
  ));
  assert.match(pwaSource, /active-workout-metrics compact/);
  assert.match(pwaSource, /active-workout-started/);

  for (const copy of [
    ...Object.values(hero.elapsed),
    ...Object.values(hero.completed),
    ...Object.values(hero.startedAt)
  ]) {
    assert.ok(iosActiveWorkoutSource.includes(`"${copy}`));
  }
  assert.match(iosActiveWorkoutSource, /GymMetricTile/);

  for (const [source, locale] of [
    [androidEnglish, "en"],
    [androidUkrainian, "uk"],
    [androidRussian, "ru"]
  ]) {
    assert.ok(source.includes(
      `name="active_workout_elapsed_label">${hero.elapsed[locale]}</string>`
    ));
    assert.ok(source.includes(
      `name="active_workout_completed_label">${hero.completed[locale]}</string>`
    ));
    assert.ok(source.includes(
      `name="active_workout_started_at">${hero.startedAt[locale]} %1$s</string>`
    ));
  }
  assert.match(androidActiveWorkoutSource, /R\.string\.active_workout_elapsed_label/);
  assert.match(androidActiveWorkoutSource, /R\.string\.active_workout_completed_label/);
  assert.match(androidActiveWorkoutSource, /R\.string\.active_workout_started_at/);
  assert.match(androidActiveWorkoutSource, /MetricTile\(/);
});

test("first-plan actions use one cross-client terminology contract", () => {
  for (const copy of Object.values(contract.terminology.firstPlanAction)) {
    assert.ok(iosWorkoutsSource.includes(copy));
  }
  assert.ok(androidEnglish.includes(
    `name="activation_start_plan">${contract.terminology.firstPlanAction.en}</string>`
  ));
  assert.ok(androidUkrainian.includes(
    `name="activation_start_plan">${contract.terminology.firstPlanAction.uk}</string>`
  ));
  assert.ok(androidRussian.includes(
    `name="activation_start_plan">${contract.terminology.firstPlanAction.ru}</string>`
  ));
  for (const copy of Object.values(contract.terminology.manualPlanAction)) {
    assert.ok(iosWorkoutsSource.includes(copy));
  }
  assert.ok(androidEnglish.includes(
    `name="activation_build_manually">${contract.terminology.manualPlanAction.en}</string>`
  ));
  assert.ok(androidUkrainian.includes(
    `name="activation_build_manually">${contract.terminology.manualPlanAction.uk}</string>`
  ));
  assert.ok(androidRussian.includes(
    `name="activation_build_manually">${contract.terminology.manualPlanAction.ru}</string>`
  ));
  for (const copy of Object.values(contract.terminology.reviewExercisesAction)) {
    assert.ok(iosWorkoutsSource.includes(copy));
  }
  assert.ok(androidEnglish.includes(
    `name="activation_edit_plan">${contract.terminology.reviewExercisesAction.en}</string>`
  ));
  assert.ok(androidUkrainian.includes(
    `name="activation_edit_plan">${contract.terminology.reviewExercisesAction.uk}</string>`
  ));
  assert.ok(androidRussian.includes(
    `name="activation_edit_plan">${contract.terminology.reviewExercisesAction.ru}</string>`
  ));
});

test("active-workout destructive actions stay behind an explicit more-options control", () => {
  assert.match(
    pwaSource,
    /<details class="active-workout-more">[\s\S]*?data-action="discard-active-workout"/
  );
  assert.match(iosActiveWorkoutSource, /Menu \{[\s\S]*?Button\(role: \.destructive\)/);
  assert.match(iosActiveWorkoutSource, /"More workout options"/);
  assert.match(androidActiveWorkoutSource, /showMoreWorkoutOptions/);
  assert.match(androidActiveWorkoutSource, /R\.string\.active_workout_more_options/);
  assert.match(
    androidActiveWorkoutSource,
    /if \(showMoreWorkoutOptions\) \{[\s\S]*?R\.string\.active_workout_discard_action/
  );
});

test("Profile tutorial copy matches the shared concise destination on every client", () => {
  const profileStep = contract.tutorial.steps.find(step => step.id === "profile");
  assert.ok(profileStep);
  assert.deepEqual(profileStep.body, {
    en: "Friends, live workouts, account, devices, and help are here.",
    uk: "Тут є друзі, спільні тренування, акаунт, пристрої та допомога.",
    ru: "Здесь находятся друзья, совместные тренировки, аккаунт, устройства и помощь."
  });

  assert.ok(pwaSource.includes(profileStep.body.en));
  assert.ok(pwaSource.includes(profileStep.body.uk));
  assert.ok(pwaRussianSource.includes(profileStep.body.ru));
  for (const copy of Object.values(profileStep.body)) {
    assert.ok(iosTutorialSource.includes(copy));
  }
  assert.ok(androidEnglish.includes(`>${profileStep.body.en}</string>`));
  assert.ok(androidUkrainian.includes(`>${profileStep.body.uk}</string>`));
  assert.ok(androidRussian.includes(`>${profileStep.body.ru}</string>`));
});

test("iOS tutorial stays compact while accessibility copy scrolls above pinned actions", () => {
  assert.match(
    iosTutorialSource,
    /height: usesBoundedScroll \? maximumCardHeight : nil/
  );
  assert.match(
    iosTutorialSource,
    /usesBoundedScroll \? size\.height \/ 2 : appTutorialCardCenterY/
  );
  assert.match(
    iosTutorialSource,
    /ScrollView\(\.vertical\) \{\s*tutorialCopy[\s\S]{0,180}\.frame\(maxHeight: \.infinity\)\s*\n\s*Divider\(\)\s*\n[\s\S]{0,500}tutorialActionsVertical\s*\.fixedSize\(horizontal: false, vertical: true\)/
  );
  assert.match(
    iosTutorialSource,
    /else \{\s*VStack\(alignment: \.leading, spacing: 14\) \{\s*tutorialCopy\s*tutorialActions\s*\}\s*\.fixedSize\(horizontal: false, vertical: true\)/
  );
  assert.match(iosTutorialSource, /ViewThatFits\(in: \.horizontal\)/);
});

test("iOS tutorial measures the selected native tab instead of guessing its geometry", () => {
  assert.match(iosTutorialSource, /selectedItem\.accessibilityFrame/);
  assert.match(
    iosTutorialSource,
    /window\.coordinateSpace\.convert\([\s\S]{0,120}from: window\.screen\.coordinateSpace/
  );
  assert.match(
    iosTutorialSource,
    /measurement\.target == expectedTarget/
  );
  assert.match(iosTutorialSource, /tabBar\.hitTest\(/);
  assert.match(iosTutorialSource, /candidate as\? UIControl/);
  assert.match(iosTutorialSource, /control\.convert\(control\.bounds, to: window\)/);
  assert.match(iosTutorialSource, /appTutorialOrderedTabFrames\(/);
  assert.doesNotMatch(iosTutorialSource, /proxy\.size\.width\s*\/\s*4/);
  assert.doesNotMatch(iosTutorialSource, /proxy\.size\.height\s*-\s*64/);
  assert.doesNotMatch(iosTutorialSource, /height:\s*58/);
  assert.doesNotMatch(iosTutorialSource, /\.subviews\b/);
  assert.doesNotMatch(iosTutorialSource, /value\(forKey:/);
  assert.doesNotMatch(iosTutorialSource, /NSClassFromString/);
  assert.doesNotMatch(iosTutorialSource, /TUTORIAL_PROBE_DEBUG/);
});
