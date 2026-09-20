using Toybox.Lang;
using Toybox.Test;

(:test)
function phoneCatalogRefreshPreservesPlanAndIncludesRequiredNames(logger as Test.Logger) as Lang.Boolean {
    var previousPlan = GymStore.plan;
    var previousExercises = GymStore.exercises;
    var plan = [{"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 9}];
    GymStore.plan = plan;
    GymStore.exercises = ["Bench Press"];
    GymStore.applyValidatedSync({"bindingSource" => "phone", "language" => "ru",
        "planNames" => [], "planWeights" => [], "planReps" => [],
        "exercises" => ["Squat", "Squat"]});
    var valid = GymStore.plan == plan && GymStore.plan.size() == 1 &&
        GymStore.setField(GymStore.plan[0], "weight") == 52.5 &&
        GymStore.setField(GymStore.plan[0], "reps") == 9 &&
        GymStore.exercises.size() == 2 &&
        GymStore.containsName(GymStore.exercises, "Bench Press") &&
        GymStore.containsName(GymStore.exercises, "Squat");
    GymStore.applyValidatedSync({"bindingSource" => "phone", "language" => "ru",
        "planNames" => ["Deadlift"], "planWeights" => [75.0], "planReps" => [6],
        "exercises" => ["Squat"]});
    valid = valid && GymStore.plan.size() == 1 &&
        GymStore.setField(GymStore.plan[0], "exerciseName").equals("Deadlift") &&
        GymStore.setField(GymStore.plan[0], "weight") == 75.0 &&
        GymStore.setField(GymStore.plan[0], "reps") == 6;
    GymStore.plan = previousPlan;
    GymStore.exercises = previousExercises;
    return valid;
}

(:test, :compactLegacyState)
function freshPhonePlanUsesV5ColumnsAndOneLazyRowCache(logger as Test.Logger) as Lang.Boolean {
    var beforePlan = GymStore.plan;
    var beforePlanSource = GymStore.persistedPlanSource;
    var beforePlanBytes = GymStore.persistedPlanBytes;
    var beforePlanNeedsWrite = GymStore.persistedPlanNeedsV5Write;
    var beforeExercises = GymStore.exercises;
    var beforeExerciseCatalogNeedsWrite = GymStore.exerciseCatalogNeedsWrite;
    var beforeLanguage = GymStore.language;
    var beforeExerciseIndex = GymStore.exerciseIndex;
    var beforeWeight = GymStore.weight;
    var beforeReps = GymStore.reps;
    var beforeStatus = GymStore.status;
    var beforeMode = GymWorkoutMode.state;
    var names = ["Bench Press", "Squat", "Deadlift"];
    var weights = [50.0, 80.0, 110.0];
    var setReps = [8, 5, 3];
    var incoming = {"bindingSource" => "phone", "planNames" => names,
        "planWeights" => weights, "planReps" => setReps,
        "exercises" => ["Bench Press", "Squat", "Deadlift"]};
    GymStore.applyValidatedSync(incoming);
    var freshPlan = GymStore.plan;
    var stored = GymStore.storedPlan();
    var first = GymPlanAccess.at(freshPlan, 0);
    var firstAgain = GymPlanAccess.at(freshPlan, 0);
    var second = GymPlanAccess.at(freshPlan, 1);
    var valid = GymPlanAccess.isCompact(freshPlan) &&
        GymPlanAccess.valid(freshPlan, GymStore.maxPlanSets, false) &&
        GymPlanAccess.size(freshPlan) == 3 && stored instanceof Lang.Array &&
        stored.size() == 4 && stored[0] == 5 && stored[1] == names &&
        stored[2] == weights && stored[3] == setReps &&
        first instanceof Lang.Dictionary && first.size() == 3 &&
        firstAgain == first && second instanceof Lang.Dictionary && second != first &&
        GymStore.setField(first, "exerciseName").equals("Bench Press") &&
        GymStore.setField(first, "weight") == 50.0 &&
        GymStore.setField(first, "reps") == 8 &&
        GymPlanAccess.nameAt(freshPlan, 2).equals("Deadlift") &&
        GymStore.syncPlanMatchesCurrentState(incoming);

    // A restored V5 value stays columnar; row access keeps only its one-entry cache.
    GymStore.plan = GymStore.restoredPlan(stored);
    var restored = GymStore.plan;
    var restoredRow = GymPlanAccess.at(restored, 2);
    valid = valid && GymPlanAccess.valid(restored, GymStore.maxPlanSets, false) &&
        GymPlanAccess.isCompact(restored) && GymPlanAccess.nameAt(restored, 2).equals("Deadlift") &&
        GymStore.setField(restoredRow, "weight") == 110.0 &&
        GymStore.setField(restoredRow, "reps") == 3 &&
        !GymStore.persistedPlanNeedsV5Write;

    GymStore.plan = beforePlan;
    GymStore.persistedPlanSource = beforePlanSource;
    GymStore.persistedPlanBytes = beforePlanBytes;
    GymStore.persistedPlanNeedsV5Write = beforePlanNeedsWrite;
    GymStore.exercises = beforeExercises;
    GymStore.exerciseCatalogNeedsWrite = beforeExerciseCatalogNeedsWrite;
    GymStore.language = beforeLanguage;
    GymStore.exerciseIndex = beforeExerciseIndex;
    GymStore.weight = beforeWeight;
    GymStore.reps = beforeReps;
    GymStore.status = beforeStatus;
    GymWorkoutMode.state = beforeMode;
    return valid;
}

(:test, :compactLegacyState)
function newPhonePlanCapKeepsLargerLegacyPlansReadable(logger as Test.Logger) as Lang.Boolean {
    var beforePlan = GymStore.plan;
    var beforePlanSource = GymStore.persistedPlanSource;
    var beforePlanBytes = GymStore.persistedPlanBytes;
    var beforePlanNeedsWrite = GymStore.persistedPlanNeedsV5Write;
    var beforeStatus = GymStore.status;
    var beforeAccount = GymStore.accountBinding;
    var beforeOwner = GymStore.stateOwnerBinding;
    var beforeDevice = GymStore.deviceBinding;
    var beforeGeneration = GymStore.pairingGeneration;
    var beforeRevision = GymStore.lastPhoneSyncRevision;
    var beforeRevisionId = GymStore.lastPhoneSyncId;
    var beforeRevisionOwner = GymStore.lastPhoneSyncAccountBinding;
    var beforeStageRevision = GymStore.stagedPhoneSyncRevision;
    var beforeStageId = GymStore.stagedPhoneSyncId;
    var beforeStageOwner = GymStore.stagedPhoneAccountBinding;
    var beforeStageMessage = GymStore.stagedPhoneSyncMessage;
    var beforeLocalSnapshot = GymLocalWorkout.snapshot;
    var beforeLocalReadFailed = GymLocalWorkout.readFailed;

    var legacyRows = [];
    var names30 = [];
    var weights30 = [];
    var reps30 = [];
    for (var i = 0; i < 30; i += 1) {
        legacyRows.add({"exerciseName" => "Bench Press", "weight" => 50.0 + i,
            "reps" => 8});
        names30.add("Bench Press");
        weights30.add(50.0 + i);
        reps30.add(8);
    }
    legacyRows.add({"exerciseName" => "Bench Press", "weight" => 80.0, "reps" => 8});
    var names31 = names30.slice(0, 30);
    var weights31 = weights30.slice(0, 30);
    var reps31 = reps30.slice(0, 30);
    names31.add("Bench Press");
    weights31.add(80.0);
    reps31.add(8);
    var legacyPlan = GymStore.restoredPlan(legacyRows);
    GymStore.plan = legacyPlan;
    var legacyStored = GymStore.storedPlan();
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var device = "new-plan-cap-test";
    var message = {"type" => "sync", "bindingVersion" => GymStore.bindingVersion,
        "requestId" => "new-plan-cap-31", "syncId" => "new-plan-cap-31",
        "accountBinding" => owner, "deviceBinding" => device,
        "syncRevision" => 1, "planNames" => names31,
        "planWeights" => weights31, "planReps" => reps31,
        "exercises" => ["Bench Press"]};
    var message30 = {"type" => "sync", "bindingVersion" => GymStore.bindingVersion,
        "requestId" => "new-plan-cap-30", "syncId" => "new-plan-cap-30",
        "accountBinding" => owner, "deviceBinding" => device,
        "syncRevision" => 1, "planNames" => names30,
        "planWeights" => weights30, "planReps" => reps30,
        "exercises" => ["Bench Press"]};

    GymStore.accountBinding = owner;
    GymStore.stateOwnerBinding = owner;
    GymStore.deviceBinding = device;
    GymStore.pairingGeneration = null;
    GymStore.lastPhoneSyncRevision = 0l;
    GymStore.lastPhoneSyncId = null;
    GymStore.lastPhoneSyncAccountBinding = null;
    GymStore.stagedPhoneSyncRevision = 0l;
    GymStore.stagedPhoneSyncId = null;
    GymStore.stagedPhoneAccountBinding = null;
    GymStore.stagedPhoneSyncMessage = null;
    GymLocalWorkout.snapshot = null;
    GymLocalWorkout.readFailed = false;

    var rejectedAsNew = !GymStore.applyPhoneSync(message) &&
        GymStore.status == GymStatus.BAD_SYNC;
    var valid = GymStore.maxNewWorkoutSets == 30 && GymStore.maxPlanSets == 60 &&
        legacyPlan instanceof GymPlanList && GymPlanAccess.size(legacyPlan) == 31 &&
        GymPlanAccess.valid(legacyPlan, GymStore.maxPlanSets, false) &&
        legacyStored instanceof Lang.Array && legacyStored[0] == 5 &&
        legacyStored[1].size() == 31 &&
        GymStore.isValidSyncMessage(message30, "phone") &&
        GymStore.isValidSyncMessage(message, "phone") && rejectedAsNew;

    GymStore.plan = beforePlan;
    GymStore.persistedPlanSource = beforePlanSource;
    GymStore.persistedPlanBytes = beforePlanBytes;
    GymStore.persistedPlanNeedsV5Write = beforePlanNeedsWrite;
    GymStore.status = beforeStatus;
    GymStore.accountBinding = beforeAccount;
    GymStore.stateOwnerBinding = beforeOwner;
    GymStore.deviceBinding = beforeDevice;
    GymStore.pairingGeneration = beforeGeneration;
    GymStore.lastPhoneSyncRevision = beforeRevision;
    GymStore.lastPhoneSyncId = beforeRevisionId;
    GymStore.lastPhoneSyncAccountBinding = beforeRevisionOwner;
    GymStore.stagedPhoneSyncRevision = beforeStageRevision;
    GymStore.stagedPhoneSyncId = beforeStageId;
    GymStore.stagedPhoneAccountBinding = beforeStageOwner;
    GymStore.stagedPhoneSyncMessage = beforeStageMessage;
    GymLocalWorkout.snapshot = beforeLocalSnapshot;
    GymLocalWorkout.readFailed = beforeLocalReadFailed;
    return valid;
}

(:test)
function mergedPhoneCatalogKeepsPlanNamesInsideByteBudget(logger as Test.Logger) as Lang.Boolean {
    var previousPlan = GymStore.plan;
    var previousExercises = GymStore.exercises;
    var prefix = "Ж";
    for (var n = 0; n < 7; n += 1) { prefix += prefix; }
    var plan = [];
    var catalog = [];
    for (var i = 0; i < 30; i += 1) {
        plan.add({"exerciseName" => prefix + "p" + i, "weight" => 50.0, "reps" => 8});
        catalog.add(prefix + "c" + i);
    }
    GymStore.plan = plan;
    GymStore.exercises = [];
    GymStore.applyValidatedSync({"bindingSource" => "phone", "planNames" => [],
        "planWeights" => [], "planReps" => [], "exercises" => catalog});
    var valid = GymStore.isValidExerciseList(GymStore.exercises, 60) &&
        GymStore.exercises.size() >= 30 && GymStore.exercises.size() < 60;
    for (var p = 0; p < plan.size(); p += 1) {
        valid = valid && GymStore.containsName(GymStore.exercises, plan[p]["exerciseName"]);
    }
    GymStore.plan = previousPlan;
    GymStore.exercises = previousExercises;
    return valid;
}

(:test, :compactLegacyState, :richWorkoutMode)
function compactCalorieFallbackKeepsExistingProfileResults(logger as Test.Logger) as Lang.Boolean {
    GymSession.resetWorkoutMetrics();
    GymSession.restingHr = 60;
    GymSession.zone = 3;
    GymSession.activeSetSeen = true;
    GymSession.effortState = GymSession.EFFORT_ACTIVE;
    var cases = [[120, 7.144], [140, 8.392], [160, 9.64], [185, 11.2]];
    for (var i = 0; i < cases.size(); i += 1) {
        GymSession.hr = cases[i][0];
        var result = GymSession.metForHeartRate();
        if (GymSession.absolute(result - cases[i][1]) > 0.0001) { return false; }
    }
    GymSession.resetWorkoutMetrics();
    return true;
}

(:test, :richWorkoutMode)
function capturedSetUndoRestoresDetectorEvidenceAndOwnsItsInterval(logger as Test.Logger) as Lang.Boolean {
    GymSession.resetWorkoutMetrics();
    GymSession.elapsedSeconds = 35;
    GymSession.activeSetSeen = true;
    GymSession.activeStartSeconds = 10;
    GymSession.lastSetEndSeconds = 30;
    GymSession.currentSetStartHr = 110;
    GymSession.currentSetPeakHr = 150;
    GymSession.currentSetEndHr = 130;
    GymSession.currentSetMaxConfidence = 72;
    GymSession.setConfidence = 65;
    GymSession.restoredSetInterval = [10, 30, 2.0, null, 0, 0, 0, 0, 0, 0];
    var statistics = GymSession.captureSetStatistics();
    GymSession.clearAutoPrompt();
    GymSession.restoreSetAfterUndo(statistics, true);
    var valid = GymSession.autoLogPrompt && GymSession.activeSetSeen &&
        GymSession.activeStartSeconds == 10 && GymSession.lastSetEndSeconds == 30 &&
        GymSession.currentSetStartHr == 110 && GymSession.currentSetPeakHr == 150 &&
        GymSession.currentSetEndHr == 130 && GymSession.currentSetMaxConfidence == 72 &&
        GymSession.restoredSetInterval[0] == 10 && GymSession.restoredSetInterval[2] == 2.0;
    var capturedInterval = GymSession.setStatistic(statistics, 7);
    capturedInterval[2] = 99.0;
    valid = valid && GymSession.restoredSetInterval[2] == 2.0;
    GymSession.clearAutoPrompt();
    GymSession.resetWorkoutMetrics();
    return valid;
}

(:test)
function restoredPhonePlanAdvancesExactWeightAndRepsAfterEachSet(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "plan-progression-test";
    GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymStore.plan = GymStore.restoredPlan([
        {"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 9},
        {"exerciseName" => "Bench Press", "weight" => 55.0, "reps" => 8}]);
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    GymStore.exerciseIndex = 0;
    GymSession.clearAutoPrompt();
    GymSession.resetWorkoutMetrics();
    GymSession.startedAt = Toybox.Time.now().value();
    GymSession.elapsedSeconds = 30;
    if (!GymStore.applyCurrentPlanSet() || GymStore.weight != 52.5 || GymStore.reps != 9 ||
        !GymStore.addSet() || GymStore.sets.size() != 1 ||
        GymStore.weight != 55.0 || GymStore.reps != 8) { return false; }
    GymSession.elapsedSeconds = 60;
    if (!GymStore.addSet() || GymStore.sets.size() != 2) { return false; }
    var first = GymSetAccess.at(GymStore.sets, 0);
    var second = GymSetAccess.at(GymStore.sets, 1);
    var valid = GymStore.setField(first, "weight") == 52.5 &&
        GymStore.setField(first, "reps") == 9 &&
        GymStore.setField(second, "weight") == 55.0 && GymStore.setField(second, "reps") == 8;
    GymStore.clearAccountScopedState();
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :compactLegacyState)
function journalCountsAndNameReservationKeepExactOwnerAndHighCatalogIndices(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "indexed-name-test";
    GymStore.pairingGeneration = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    GymStore.exercises = [];
    for (var i = 0; i < 60; i += 1) { GymStore.exercises.add("Exercise " + i.toString()); }
    GymStore.exerciseCatalogNeedsWrite = true;
    var indices = [0, 32, 59, 32];
    var rows = [];
    for (var n = 0; n < indices.size(); n += 1) {
        rows.add(GymStore.restoredSet(GymStore.exercises[indices[n]], 52.5, 9,
            [n * 30, (n + 1) * 30, 1.0, null, 0, 0, 0, 0, 0, 0]));
    }
    var valid = GymStore.persistActiveWorkoutSnapshot(rows, 1700000000,
        [120, 4.0, null, 0, 0, 0, null, 0]);
    GymStore.sets = GymActiveJournal.currentRecords();
    if (!valid || GymStore.completedSetsForExercise("Exercise 32") != 2 ||
        GymActiveJournal.queueNameStorageBytes() != 224) { return false; }
    var first = GymSetAccess.at(GymStore.sets, 0);
    GymStore.deviceBinding = "another-device";
    valid = GymStore.setField(first, "weight") == null &&
        GymStore.completedSetsForExercise("Exercise 32") == 0;
    GymStore.deviceBinding = "indexed-name-test";
    GymStore.pairingGeneration = null;
    valid = valid && GymStore.setField(first, "weight") == null;
    GymStore.clearAccountScopedState();
    LocalWorkoutFixture.reset();
    return valid;
}
