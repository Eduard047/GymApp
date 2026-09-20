using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.Test as Test;

(:test, :compactWorkoutMode96)
function manualModeIgnoresEnabledLegacyAutoSetPreference(logger as Test.Logger) as Lang.Boolean {
    var oldMode = GymWorkoutMode.state;
    var oldPreference = GymStore.autoPromptEnabled;
    GymStore.autoPromptEnabled = true;

    GymWorkoutMode.state = GymWorkoutMode.MODE_FREE;
    var freeModeStaysDurationOnly = !GymWorkoutMode.allowsDetailedTracking() &&
        !GymSession.autoLogPrompt;
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    var plannedManualModeWorks = GymWorkoutMode.allowsDetailedTracking() &&
        !GymSession.autoLogPrompt;

    GymWorkoutMode.state = oldMode;
    GymStore.autoPromptEnabled = oldPreference;
    logger.debug("legacy auto-set preference stays inert for manual sets");
    return freeModeStaysDurationOnly && plannedManualModeWorks;
}

(:test, :compactWorkoutMode96)
function manualCaptureOmitsSetInterval(logger as Test.Logger) as Lang.Boolean {
    var valid = GymSession.capturedSetInterval(0, 120) == null;
    logger.debug("manual capture omitted per-set interval data");
    return valid;
}

(:test, :compactWorkoutMode96)
function freeModeStaysDurationOnlyAndQueuesPositiveDurationWorkout(logger as Test.Logger) as Lang.Boolean {
    var oldMode = GymWorkoutMode.state;
    var oldPreference = GymStore.autoPromptEnabled;
    GymStore.clearAccountScopedState();
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var device = "manual96-free-test";
    GymStore.accountBinding = owner;
    GymStore.stateOwnerBinding = owner;
    GymStore.deviceBinding = device;
    GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymStore.plan = [{"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 8}];
    GymStore.exerciseIndex = 0;
    GymStore.weight = 52.5;
    GymStore.reps = 8;
    GymStore.pending = [];
    GymStore.autoPromptEnabled = true;
    GymStore.runtimeWorkoutStartedAtSeconds = Toybox.Time.now().value();
    GymStore.activeWorkoutStartedAtSeconds = null;
    GymStore.resumedWorkoutIntervalsInvalid = false;
    GymWorkoutMode.state = GymWorkoutMode.MODE_FREE;
    GymSession.resetWorkoutMetrics();
    GymStore.timelineBase = null;
    GymSession.startedAt = GymStore.runtimeWorkoutStartedAtSeconds;
    GymSession.elapsedSeconds = 45;
    GymSession.hr = 126;
    GymSession.avgHr = 126;
    GymSession.maxHr = 126;
    GymSession.hrSamples = 1;
    GymSession.zone = 2;
    GymSession.gymCalories = 1.25;
    GymSession.recording = true;
    GymSession.paused = false;

    var rejectedSet = !GymWorkoutMode.allowsDetailedTracking() && !GymStore.addSet() &&
        GymStore.status == GymStatus.PLAN_ONLY && GymStore.sets.size() == 0 &&
        !GymSession.autoLogPrompt;
    var prepared = rejectedSet && GymStore.prepareWorkoutCommit();
    var fitSaved = prepared && GymStore.markPreparedWorkoutFitSaved();
    var message = fitSaved ? GymStore.preparedWorkoutMessage() : null;
    var payloadValid = message != null && GymStore.isValidWorkoutMessage(message) &&
        message.get("workoutMode").equals("free") &&
        message.get("durationSeconds") >= 1 && message.get("durationSeconds") <= 604800 &&
        message.get("sets") instanceof Lang.Array && message.get("sets").size() == 0 &&
        message.get("setMetrics") == null && message.get("setIntervals") == null &&
        message.get("plannedSetCount") == null &&
        message.get("plannedTargetSetCount") == null &&
        message.get("completedPlannedSetCount") == null;
    var queued = payloadValid && GymStore.queueWorkout(message);
    var storedQueue = Storage.getValue("pending");
    var queuedValid = queued && storedQueue instanceof Lang.Array &&
        storedQueue.size() == 1 && GymStore.isValidWorkoutMessage(storedQueue[0]) &&
        storedQueue[0].get("workoutMode").equals("free") &&
        storedQueue[0].get("durationSeconds") >= 1 &&
        storedQueue[0].get("sets").size() == 0;
    var valid = rejectedSet && payloadValid && queuedValid && GymStore.plan.size() == 1 &&
        GymStore.setField(GymStore.plan[0], "weight") == 52.5 &&
        GymStore.accountBinding.equals(owner) && GymStore.deviceBinding.equals(device);

    GymStore.clearAccountScopedState();
    GymWorkoutMode.state = oldMode;
    GymStore.autoPromptEnabled = oldPreference;
    GymSession.resetWorkoutMetrics();
    GymSession.startedAt = 0;
    GymSession.recording = false;
    GymSession.paused = false;
    logger.debug("FREE remained set-free and queued a positive-duration activity");
    return valid;
}

(:test, :compactWorkoutMode96)
class Manual96PlannedSetFixture {
    static var oldMode = null;
    static var oldPreference = false;
    static var oldExerciseCatalogRepairRequired = false;
    static var owner = null;
    static var device = null;
    static var startedAt = 0;
    static var expectQueuedWorkout = false;
    static var queuedWorkout = null;
    static var currentQueue = null;
    static var journalQueue = null;
    static var journalLoadOk = false;
    static var journalReferenceUnchanged = false;
    static var journalContentsPreserved = false;
    static var modeAllowsManualSets = false;
    static var legacyPromptStaysOff = false;
    static var validCurrentQueue = false;
    static var added = false;
    static var savedStatus = false;
    static var ownerPreserved = false;
    static var queueIdentityPreserved = false;
    static var queueContentsPreserved = false;
    static var validHeader = false;
    static var plannedModeAfter = false;
    static var setCountPreserved = false;
    static var planPreserved = false;
    static var recordedExercisePreserved = false;
    static var recordedWeightPreserved = false;
    static var recordedRepsPreserved = false;
    static var durableExercisePreserved = false;
    static var durableWeightPreserved = false;
    static var durableRepsPreserved = false;

    static function prepare(keepQueuedWorkout) {
        oldMode = GymWorkoutMode.state;
        oldPreference = GymStore.autoPromptEnabled;
        oldExerciseCatalogRepairRequired = GymStore.exerciseCatalogRepairRequired;
        GymStore.clearAccountScopedState();
        // This fixture is a validated, owner-bound workout. An earlier orphan
        // recovery test may have raised the read-only repair fence.
        GymStore.exerciseCatalogRepairRequired = false;
        owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        device = "manual96-owner-test";
        GymStore.accountBinding = owner;
        GymStore.stateOwnerBinding = owner;
        GymStore.deviceBinding = device;
        GymStore.pairingGeneration = null;
        journalLoadOk = GymPendingJournal.load();
        journalQueue = GymPendingJournal.entries;
        GymStore.exercises = ["Bench Press"];
        GymStore.exerciseCatalogNeedsWrite = true;
        GymStore.plan = [{"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 8}];
        GymStore.exerciseIndex = 0;
        GymStore.weight = 52.5;
        GymStore.reps = 8;
        startedAt = Toybox.Time.now().value() - 60;
        expectQueuedWorkout = keepQueuedWorkout;
        currentQueue = [];
        queuedWorkout = null;
        if (expectQueuedWorkout) {
            queuedWorkout = {
                "type" => "create_workout",
                "bindingVersion" => GymStore.bindingVersion,
                "requestId" => "manual96-queued-plan-001",
                "workoutMode" => "planned",
                "accountBinding" => owner,
                "deviceBinding" => device,
                "pairingGeneration" => null,
                "startedAtSeconds" => startedAt - 300,
                "durationSeconds" => 300,
                "gymCalories" => 8.0,
                "sets" => [{"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 8}],
                "plannedSetCount" => 1
            };
            currentQueue.add(queuedWorkout);
        }
        GymStore.pending = currentQueue;
        Storage.setValue("pending", currentQueue);
        GymStore.autoPromptEnabled = true;
        GymStore.runtimeWorkoutStartedAtSeconds = startedAt;
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
        GymSession.resetWorkoutMetrics();
        GymSession.startedAt = startedAt;
        GymSession.elapsedSeconds = 60;
        GymSession.hr = 132;
        GymSession.recording = true;
    }

    static function capturePreconditions() {
        modeAllowsManualSets = GymWorkoutMode.allowsDetailedTracking();
        legacyPromptStaysOff = !GymSession.autoLogPrompt;
        validCurrentQueue = GymStore.isValidPendingList(currentQueue);
        added = false;
    }

    static function capturePostconditions() {
        savedStatus = GymStore.status == GymStatus.SET_SAVED;
        ownerPreserved = GymStore.sameOptionalText(GymStore.accountBinding, owner) &&
            GymStore.sameOptionalText(GymStore.stateOwnerBinding, owner) &&
            GymStore.sameOptionalText(GymStore.deviceBinding, device);
        plannedModeAfter = GymWorkoutMode.isPlanned();
        setCountPreserved = GymStore.sets.size() == 1;
        var journalAfter = GymPendingJournal.entries;
        journalReferenceUnchanged = journalAfter == journalQueue;
        journalContentsPreserved = journalLoadOk && GymPendingJournal.readable &&
            journalQueue instanceof Lang.Array && journalQueue.size() == 0 &&
            journalAfter instanceof Lang.Array && journalAfter.size() == 0;
        queueIdentityPreserved = GymStore.pending == currentQueue &&
            (expectQueuedWorkout ? (currentQueue.size() == 1 &&
                currentQueue[0] == queuedWorkout &&
                GymStore.sameOptionalText(queuedWorkout.get("requestId"),
                    "manual96-queued-plan-001")) :
                currentQueue.size() == 0);
        var storedQueue = Storage.getValue("pending");
        queueContentsPreserved = GymStore.isValidPendingList(GymStore.pending) &&
            storedQueue instanceof Lang.Array && GymStore.isValidPendingList(storedQueue) &&
            (expectQueuedWorkout ? (GymStore.sameOptionalText(
                GymStore.pending[0].get("requestId"), "manual96-queued-plan-001") &&
                GymStore.sameOptionalText(storedQueue[0].get("requestId"),
                    "manual96-queued-plan-001")) :
                (GymStore.pending.size() == 0 && storedQueue.size() == 0));
        var header = Storage.getValue("activeWorkoutV1");
        planPreserved = GymStore.plan instanceof Lang.Array && GymStore.plan.size() == 1 &&
            GymStore.sameOptionalText(GymStore.setField(GymStore.plan[0], "exerciseName"),
                "Bench Press") &&
            GymStore.setField(GymStore.plan[0], "weight") == 52.5 &&
            GymStore.setField(GymStore.plan[0], "reps") == 8;
        if (setCountPreserved) {
            var recordedSet = GymSetAccess.at(GymStore.sets, 0);
            recordedExercisePreserved = GymStore.sameOptionalText(
                GymStore.setField(recordedSet, "exerciseName"), "Bench Press");
            recordedWeightPreserved = GymStore.setField(recordedSet, "weight") == 52.5;
            recordedRepsPreserved = GymStore.setField(recordedSet, "reps") == 8;
        }
        // Validating v6 rebinds the journal cache. Read the current live row
        // first so the assertion itself does not invalidate its set handle.
        validHeader = GymStore.isValidActiveWorkoutSnapshot(header) &&
            GymStore.sameOptionalText(header[1], owner) &&
            GymStore.sameOptionalText(header[2], device) && header[5] == 1;
        var durableRows = GymActiveJournal.restored(header);
        if (durableRows != null && durableRows.size() == 1) {
            var durableRecord = GymSetAccess.at(durableRows, 0);
            durableExercisePreserved = GymStore.sameOptionalText(
                GymStore.setField(durableRecord, "exerciseName"), "Bench Press");
            durableWeightPreserved = GymStore.setField(durableRecord, "weight") == 52.5;
            durableRepsPreserved = GymStore.setField(durableRecord, "reps") == 8;
        }
    }

    static function report(logger as Test.Logger) {
        if (passed()) { return; }
        logger.debug("manual96 planned add mode=" + modeAllowsManualSets.toString() +
            " promptOff=" + legacyPromptStaysOff.toString() +
            " queueExpected=" + expectQueuedWorkout.toString() +
            " queueValid=" + validCurrentQueue.toString() +
            " added=" + added.toString() + " status=" + GymStore.status.toString() +
            " saved=" + savedStatus.toString() + " sets=" + GymStore.sets.size().toString());
        logger.debug("manual96 planned add owner=" + ownerPreserved.toString() +
            " queueIdentity=" + queueIdentityPreserved.toString() +
            " queueContents=" + queueContentsPreserved.toString() +
            " header=" + validHeader.toString());
        logger.debug("manual96 planned state mode=" + plannedModeAfter.toString() +
            " journalLoaded=" + journalLoadOk.toString() +
            " journalIdentity=" + journalReferenceUnchanged.toString() +
            " journalContents=" + journalContentsPreserved.toString() +
            " oneSet=" + setCountPreserved.toString());
        logger.debug("manual96 planned data plan=" + planPreserved.toString() +
            " setName=" + recordedExercisePreserved.toString() +
            " weight=" + recordedWeightPreserved.toString() +
            " reps=" + recordedRepsPreserved.toString() +
            " durableName=" + durableExercisePreserved.toString() +
            " durableWeight=" + durableWeightPreserved.toString() +
            " durableReps=" + durableRepsPreserved.toString());
    }

    static function passed() {
        return modeAllowsManualSets && legacyPromptStaysOff && validCurrentQueue &&
            added && savedStatus && ownerPreserved && queueIdentityPreserved &&
            queueContentsPreserved && validHeader && plannedModeAfter && setCountPreserved &&
            journalContentsPreserved && planPreserved && recordedExercisePreserved &&
            recordedWeightPreserved && recordedRepsPreserved &&
            durableExercisePreserved && durableWeightPreserved && durableRepsPreserved;
    }

    static function cleanup() {
        GymStore.clearAccountScopedState();
        GymWorkoutMode.state = oldMode;
        GymStore.autoPromptEnabled = oldPreference;
        GymStore.exerciseCatalogRepairRequired = oldExerciseCatalogRepairRequired;
        GymSession.resetWorkoutMetrics();
        GymSession.startedAt = 0;
        GymSession.recording = false;
        GymSession.paused = false;
    }
}

(:test, :compactWorkoutMode96)
function plannedManualSetCommitPreservesOwnerAndCurrentQueue(logger as Test.Logger) as Lang.Boolean {
    Manual96PlannedSetFixture.prepare(true);
    Manual96PlannedSetFixture.capturePreconditions();
    if (Manual96PlannedSetFixture.modeAllowsManualSets &&
        Manual96PlannedSetFixture.legacyPromptStaysOff) {
        Manual96PlannedSetFixture.added = GymStore.addSet();
    }
    Manual96PlannedSetFixture.capturePostconditions();
    Manual96PlannedSetFixture.report(logger);
    var valid = Manual96PlannedSetFixture.passed();
    Manual96PlannedSetFixture.cleanup();
    return valid;
}

(:test, :compactWorkoutMode96)
function plannedManualSetCommitWorksWithEmptyQueue(logger as Test.Logger) as Lang.Boolean {
    Manual96PlannedSetFixture.prepare(false);
    Manual96PlannedSetFixture.capturePreconditions();
    if (Manual96PlannedSetFixture.modeAllowsManualSets &&
        Manual96PlannedSetFixture.legacyPromptStaysOff) {
        Manual96PlannedSetFixture.added = GymStore.addSet();
    }
    Manual96PlannedSetFixture.capturePostconditions();
    Manual96PlannedSetFixture.report(logger);
    var valid = Manual96PlannedSetFixture.passed();
    Manual96PlannedSetFixture.cleanup();
    return valid;
}

(:test, :compactWorkoutMode96)
function manual96ValidatesV6JournalWithoutResumingIt(logger as Test.Logger) as Lang.Boolean {
    var oldMode = GymWorkoutMode.state;
    GymStore.clearAccountScopedState();
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var device = "manual96-recovery-test";
    GymStore.accountBinding = owner;
    GymStore.stateOwnerBinding = owner;
    GymStore.deviceBinding = device;
    GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"];

    var planState = [{"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 8}];
    var queueState = [{"requestId" => "manual96-recovery-queue"}];
    GymStore.plan = planState;
    GymStore.pending = queueState;
    Storage.setValue("plan", planState);
    Storage.setValue("pending", queueState);

    var currentV6 = [6, owner, device, null, null, 0, 0, 1, 1, null];
    var validV6 = GymStore.isValidActiveWorkoutSnapshot(currentV6) &&
        GymActiveJournal.restored(currentV6) != null;
    var legacyV2 = [2, owner, device, null, null, [], null];
    var legacyV3 = [3, owner, device, null, null, [], null];
    var legacyV4 = [4, owner, device, null, null, [], [], [], null, null];
    var rejectedLegacy = !GymStore.isValidActiveWorkoutSnapshot(legacyV2) &&
        !GymStore.isValidActiveWorkoutSnapshot(legacyV3) &&
        !GymStore.isValidActiveWorkoutSnapshot(legacyV4);
    var storedPlan = Storage.getValue("plan");
    var storedQueue = Storage.getValue("pending");
    var statePreserved = GymStore.plan == planState && GymStore.pending == queueState &&
        storedPlan instanceof Lang.Array && storedPlan.size() == 1 &&
        GymStore.setField(storedPlan[0], "exerciseName").equals("Bench Press") &&
        GymStore.setField(storedPlan[0], "weight") == 52.5 &&
        storedQueue instanceof Lang.Array && storedQueue.size() == 1 &&
        storedQueue[0].get("requestId").equals("manual96-recovery-queue");

    GymStore.clearAccountScopedState();
    GymWorkoutMode.state = oldMode;
    logger.debug("96 KiB still validates v6 journal format and keeps plan and pending values");
    return validV6 && rejectedLegacy && statePreserved;
}

(:test, :compactWorkoutMode96)
class Manual96LoadFixture {
    static var storageKeys = [
        "accountBinding", "stateOwnerBinding", "storageSchemaVersion",
        "legacyUnboundState", "legacyQuarantineVersion", "deviceBinding",
        "pairingGeneration", "cloudDeviceBinding", "exercises", "plan",
        "pending", "pendingJournalV1", "phoneSyncFence",
        "lastPhoneSyncRevision", "lastPhoneSyncId", "phoneSyncStage",
        "cloudSyncStage", "cloudSyncFence", "lastCloudPlanRevision",
        "lastCloudPlanId", "currentEntryV1", "sets",
        "activeWorkoutStartedAtSeconds", "activeWorkoutV1", "activeRuntimeV1",
        "activeWorkoutModeV1", "preparedWorkoutV1", "queuedActiveRequestId",
        "weight", "reps", "weightStep", "restSecondsDefault",
        "autoPromptEnabled", "sensitivityIndex", "language",
        "tutorialHistoryV1", "lastWorkoutSyncV1", "deferredSync",
        "processedSyncIds", "queueEntry0-3", "queueEntry1-3",
        "queueName3-0", "activeRow2-0", "activeRow3-0"
    ];
    static var oldStorage = null;
    static var oldStorageKeys = null;
    static var oldStore = null;
    static var oldSession = null;
    static var oldMode = 0;
    static var oldActiveHeader = null;
    static var abandonedStartedAt = 0;
    static var newWorkoutStartedAt = 0;
    static var preparedRequestId = null;
    static const owner = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    static const device = "manual96-load-fixture";

    static function keysForRun(includeBankZero) {
        var keys = storageKeys.slice(null, null);
        if (includeBankZero) {
            // The large-set journal fixture deterministically uses bank 0.
            // Save only that bank's exact row/name/index keys before reuse.
            keys.add("queueEntry0-0");
            keys.add("queueEntry1-0");
            for (var i = 0; i < 60; i += 1) {
                keys.add("activeRow0-" + i.toString());
                keys.add("queueName0-" + i.toString());
            }
        }
        return keys;
    }

    static function begin(includeBankZero) {
        oldStorageKeys = keysForRun(includeBankZero);
        oldStorage = [];
        for (var i = 0; i < oldStorageKeys.size(); i += 1) {
            oldStorage.add(Storage.getValue(oldStorageKeys[i]));
        }
        oldStore = [
            GymStore.exercises, GymStore.sets, GymStore.plan,
            GymStore.persistedPlanSource, GymStore.persistedPlanBytes,
            GymStore.persistedPlanNeedsV5Write, GymStore.pending,
            GymStore.exerciseIndex, GymStore.weight, GymStore.reps,
            GymStore.exerciseCatalogNeedsWrite,
            GymStore.exerciseCatalogRepairRequired,
            GymStore.activeWorkoutStartedAtSeconds,
            GymStore.activeWorkoutSnapshotValid,
            GymStore.activeWorkoutTimelineValid, GymStore.timelineBase,
            GymStore.runtimeWorkoutStartedAtSeconds,
            GymStore.resumedWorkoutIntervalsInvalid, GymStore.status,
            GymStore.weightStep, GymStore.restSecondsDefault,
            GymStore.autoPromptEnabled, GymStore.sensitivityIndex,
            GymStore.language, GymStore.accountBinding,
            GymStore.stateOwnerBinding, GymStore.deviceBinding,
            GymStore.pairingGeneration, GymStore.cloudDeviceBinding,
            GymStore.deferredSync, GymStore.processedSyncIds,
            GymStore.lastPhoneSyncRevision, GymStore.lastPhoneSyncId,
            GymStore.lastPhoneSyncAccountBinding, GymStore.preparedWorkout,
            GymStore.lastWorkoutSyncAtSeconds, GymStore.tutorialHistory,
            GymStore.lastCloudPlanRevision, GymStore.lastCloudPlanId,
            GymStore.stagedPhoneSyncRevision, GymStore.stagedPhoneSyncId,
            GymStore.stagedPhoneAccountBinding, GymStore.stagedPhoneSyncMessage,
            GymStore.stagedCloudPlanRevision, GymStore.stagedCloudPlanId,
            GymStore.stagedCloudAccountBinding, GymStore.stagedCloudSyncMessage,
            GymStore.legacyUnboundState, GymStore.legacyCompactCount,
            GymStore.pairingRecoveryCommitLast, GymStore.lastSetUndoStartedAt,
            GymStore.lastSetBoost, GymStore.lastSetWasAutoPrompt,
            GymStore.lastSetStatistics, GymStore.lastLoggedSetEndSeconds,
            GymStore.lastSetPreviousLoggedEnd
        ];
        oldMode = GymWorkoutMode.state;
        oldSession = [
            GymSession.recording, GymSession.paused, GymSession.startedAt,
            GymSession.elapsedSeconds, GymSession.hr, GymSession.avgHr,
            GymSession.maxHr, GymSession.hrSamples, GymSession.zone,
            GymSession.gymCalories, GymSession.garminCalories
        ];
        oldActiveHeader = GymActiveJournal.snapshot();
    }

    static function clearKey(key) {
        try { Storage.deleteValue(key); } catch (e) { }
    }

    static function seedCommon() {
        var now = Toybox.Time.now().value();
        Storage.setValue("storageSchemaVersion", 6);
        Storage.setValue("accountBinding", owner);
        Storage.setValue("stateOwnerBinding", owner);
        Storage.setValue("deviceBinding", device);
        GymStore.exerciseCatalogRepairRequired = false;
        clearKey("pairingGeneration");
        clearKey("cloudDeviceBinding");
        clearKey("legacyUnboundState");
        clearKey("legacyQuarantineVersion");
        Storage.setValue("exercises", ["Bench Press"]);
        Storage.setValue("weight", 70.0);
        Storage.setValue("reps", 9);
        Storage.setValue("weightStep", 2.5);
        Storage.setValue("restSecondsDefault", 90);
        Storage.setValue("autoPromptEnabled", true);
        Storage.setValue("sensitivityIndex", 1);
        Storage.setValue("language", "en");
        Storage.setValue("phoneSyncFence", {
            "revision" => 7l,
            "id" => "manual96-phone-fence-007",
            "accountBinding" => owner
        });
        Storage.setValue("tutorialHistoryV1", []);
        Storage.setValue("processedSyncIds", []);
        clearKey("phoneSyncStage");
        clearKey("cloudSyncStage");
        clearKey("cloudSyncFence");
        clearKey("lastCloudPlanRevision");
        clearKey("lastCloudPlanId");
        clearKey("deferredSync");
        clearKey("lastWorkoutSyncV1");
        clearKey("preparedWorkoutV1");
        clearKey("queuedActiveRequestId");
        clearKey("activeRuntimeV1");
        Storage.setValue("currentEntryV1", [0, "Bench Press", 70.0, 9]);
        return now;
    }

    static function seedCurrentPlanAndQueue() {
        var now = seedCommon();
        var names = [];
        var weights = [];
        var setReps = [];
        for (var i = 0; i < 35; i += 1) {
            names.add("Bench Press");
            weights.add(40.0 + i);
            setReps.add(8 + (i % 3));
        }
        Storage.setValue("plan", [5, names, weights, setReps]);

        abandonedStartedAt = now - 120;
        var abandonedInterval = [360, 420, 4.0, null, 0, 0, 0, 0, 0, 0];
        var abandonedCheckpoint = [600, 8.0, null, 264, 2, 140, 132, 2];
        Storage.setValue("activeWorkoutV1", [
            6, owner, device, null, abandonedStartedAt, 1, 2, 301, 1,
            abandonedCheckpoint
        ]);
        Storage.setValue("activeRow2-0", [301, 0, 70.0, 9, abandonedInterval, 1]);
        Storage.setValue("activeWorkoutStartedAtSeconds", abandonedStartedAt);
        Storage.setValue("sets", []);
        Storage.setValue("activeWorkoutModeV1", [1, true]);
        Storage.setValue("currentEntryV1", [1, "Bench Press", 70.0, 9]);

        var pendingStart = now - 900;
        var pendingWorkout = {
            "type" => "create_workout",
            "bindingVersion" => GymStore.bindingVersion,
            "requestId" => "manual96-pending-001",
            "workoutMode" => "planned",
            "accountBinding" => owner,
            "deviceBinding" => device,
            "pairingGeneration" => null,
            "startedAtSeconds" => pendingStart,
            "durationSeconds" => 600,
            "gymCalories" => 8.0,
            "sets" => [{"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 8}],
            "setIntervals" => [[360, 420, 4.0, null, 0, 0, 0, 0, 0, 0]],
            "plannedSetCount" => 1
        };
        Storage.setValue("pending", [pendingWorkout]);

        var journalStart = now - 1800;
        var journalCheckpoint = [300, 4.0, null, 120, 1, 120, 120, 1];
        var journalHeader = [6, owner, device, null, journalStart, 1, 3, 201, 1,
            journalCheckpoint];
        var journalMetadata = {
            "type" => "create_workout",
            "bindingVersion" => GymStore.bindingVersion,
            "requestId" => "manual96-journal-001",
            "workoutMode" => "planned",
            "accountBinding" => owner,
            "deviceBinding" => device,
            "pairingGeneration" => null,
            "startedAtSeconds" => journalStart,
            "durationSeconds" => 300,
            "gymCalories" => 4.0,
            "plannedSetCount" => 1
        };
        Storage.setValue("activeRow3-0", [201, 0, 52.5, 8,
            [0, 120, 4.0, null, 0, 0, 0, 0, 0, 0], 1]);
        Storage.setValue("queueName3-0", [201, 0, "Bench Press"]);
        Storage.setValue("queueEntry0-3", [
            journalMetadata, journalHeader, GymStore.utf8Bytes("Bench Press").size()
        ]);
        clearKey("queueEntry1-3");
        Storage.setValue("pendingJournalV1", [3, 0, [3]]);
        return names.size() == 35 && GymStore.isValidPendingList([pendingWorkout]);
    }

    static function seedSingleAbandonedWorkout() {
        var now = seedCommon();
        abandonedStartedAt = now - 1200;
        Storage.setValue("plan", [5, ["Bench Press"], [45.0], [6]]);
        Storage.setValue("pending", []);
        Storage.setValue("pendingJournalV1", [3, 0, []]);
        Storage.setValue("activeWorkoutV1", [
            6, owner, device, null, abandonedStartedAt, 1, 2, 301, 1,
            [600, 8.0, null, 264, 2, 140, 132, 2]
        ]);
        Storage.setValue("activeRow2-0", [
            301, 0, 70.0, 9, [360, 420, 4.0, null, 0, 0, 0, 0, 0, 0], 1
        ]);
        Storage.setValue("activeWorkoutStartedAtSeconds", abandonedStartedAt);
        Storage.setValue("sets", []);
        Storage.setValue("activeWorkoutModeV1", [1, true]);
        clearKey("queueEntry0-3");
        clearKey("queueEntry1-3");
        clearKey("queueName3-0");
        clearKey("activeRow3-0");
        return true;
    }

    static function seedLargePlannedWorkout() {
        seedCommon();
        var names = [];
        var weights = [];
        var setReps = [];
        for (var i = 0; i < 15; i += 1) {
            names.add("Bench Press");
            weights.add(50.0);
            setReps.add(8);
        }
        Storage.setValue("plan", [5, names, weights, setReps]);
        Storage.setValue("pending", []);
        Storage.setValue("pendingJournalV1", [3, 0, []]);
        clearKey("activeWorkoutV1");
        clearKey("activeWorkoutStartedAtSeconds");
        clearKey("activeWorkoutModeV1");
        clearKey("activeRuntimeV1");
        clearKey("preparedWorkoutV1");
        clearKey("currentEntryV1");
        clearKey("queueEntry0-0");
        clearKey("queueEntry1-0");
        clearKey("queueEntry0-3");
        clearKey("queueEntry1-3");
        clearKey("queueName3-0");
        clearKey("activeRow2-0");
        clearKey("activeRow3-0");
        for (var row = 0; row < 60; row += 1) {
            clearKey("activeRow0-" + row.toString());
            clearKey("queueName0-" + row.toString());
        }
        return names.size() == 15;
    }

    static function largePlannedJournalOmitsIntervals(logger as Test.Logger) {
        var began = false;
        var setsAdded = 0;
        var activeValid = false;
        var mixedRejected = false;
        var malformedRejected = false;
        var restoredAfterValidation = false;
        var prepared = false;
        var fitSaved = false;
        var committed = false;
        var reloaded = false;
        var frameValid = false;
        try {
            GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
            GymSession.resetWorkoutMetrics();
            GymSession.recording = false;
            GymSession.paused = false;
            GymSession.startedAt = 0;
            GymStore.status = GymStatus.READY;
            GymStore.load();
            began = GymWorkoutMode.begin(true);
            if (began) {
                var startedAt = Toybox.Time.now().value();
                GymStore.runtimeWorkoutStartedAtSeconds = startedAt;
                GymSession.recording = true;
                GymSession.paused = false;
                GymSession.startedAt = startedAt;
                GymSession.elapsedSeconds = 15;
                GymSession.hr = 135;
                GymSession.avgHr = 120;
                GymSession.maxHr = 140;
                GymSession.hrSamples = 3;
                GymSession.zone = 2;
                GymSession.gymCalories = 5.0;
                GymSession.garminCalories = null;
                for (var setIndex = 0; setIndex < 15; setIndex += 1) {
                    if (!GymStore.addSet()) { break; }
                    setsAdded += 1;
                }
            }

            var active = Storage.getValue("activeWorkoutV1");
            var checkpoint = active instanceof Lang.Array && active.size() == 10 ?
                active[9] : null;
            var allRowsOmitIntervals = active instanceof Lang.Array &&
                active.size() == 10 && active[5] == 15;
            if (allRowsOmitIntervals) {
                for (var rowIndex = 0; rowIndex < 15; rowIndex += 1) {
                    var row = Storage.getValue("activeRow" + active[6].toString() +
                        "-" + rowIndex.toString());
                    if (!(row instanceof Lang.Array) || row.size() != 6 ||
                        row[0] != active[7] || row[1] != 0 || row[2] != 50.0 ||
                        row[3] != 8 || row[4] != null) {
                        allRowsOmitIntervals = false;
                        break;
                    }
                }
            }
            activeValid = setsAdded == 15 && allRowsOmitIntervals &&
                checkpoint instanceof Lang.Array && checkpoint.size() == 8 &&
                checkpoint[0] == 15 && checkpoint[1] == 5.0 && checkpoint[2] == null &&
                checkpoint[3] == 360 && checkpoint[4] == 3 && checkpoint[5] == 140 &&
                checkpoint[6] == 135 && checkpoint[7] == 2 &&
                GymStore.isValidActiveWorkoutSnapshot(active);

            if (activeValid) {
                var firstKey = "activeRow" + active[6].toString() + "-0";
                var firstRow = Storage.getValue(firstKey);
                var mixedInterval = [0, 1, 0.0, null, 0, 0, 0, 0, 0, 0];
                firstRow[4] = mixedInterval;
                Storage.setValue(firstKey, firstRow);
                mixedRejected = !GymStore.isValidActiveWorkoutSnapshot(active);
                firstRow[4] = ["invalid"];
                Storage.setValue(firstKey, firstRow);
                malformedRejected = !GymStore.isValidActiveWorkoutSnapshot(active);
                firstRow[4] = null;
                Storage.setValue(firstKey, firstRow);
                var restoredValid = GymStore.isValidActiveWorkoutSnapshot(active);
                var restored = restoredValid ? GymActiveJournal.restored(active) : null;
                restoredAfterValidation = restoredValid && restored != null &&
                    restored.size() == 15;
                if (restoredAfterValidation) {
                    // Direct validator calls refresh GymActiveJournal's lazy
                    // view; hand that view back to Store before finalization.
                    GymStore.sets = restored;
                }
            }

            prepared = restoredAfterValidation && GymStore.prepareWorkoutCommit();
            fitSaved = prepared && GymStore.markPreparedWorkoutFitSaved();
            var metadata = fitSaved ? GymStore.preparedWorkoutJournalMetadata(false) : null;
            var metadataValid = metadata instanceof Lang.Array &&
                GymStore.isValidWorkoutContext(metadata) && metadata[9] == 15 &&
                metadata[6] instanceof Lang.Array && metadata[6][0] == 15 &&
                metadata[6][1] == 5.0 && metadata[6][3] == 360 &&
                metadata[6][4] == 3 && metadata[6][5] == 140 &&
                GymStore.expandWorkoutMetadata(metadata).get("setIntervals") == null;
            var queueStarted = metadataValid && GymPendingJournal.begin(metadata) == 0;
            if (queueStarted) {
                committed = true;
                for (var advanceIndex = 0; advanceIndex < 16; advanceIndex += 1) {
                    var result = GymPendingJournal.advance();
                    if ((advanceIndex < 15 && result != 0) ||
                        (advanceIndex == 15 && result != 1)) {
                        committed = false;
                        break;
                    }
                }
            }
            reloaded = committed && GymPendingJournal.load() &&
                GymPendingJournal.entries.size() == 1 &&
                GymPendingJournal.contains(GymStore.preparedWorkout[4].toString());
            var frame = reloaded ? GymPendingJournal.nextMessage() : null;
            var frameSet = frame instanceof Lang.Dictionary ? frame.get("set") : null;
            var frameMetadata = frame instanceof Lang.Dictionary ? frame.get("metadata") : null;
            var storedFirst = Storage.getValue("activeRow" + active[6].toString() + "-0");
            frameValid = frame instanceof Lang.Dictionary &&
                frame.get("type").equals("workout_part") &&
                frame.get("interval") == null && frameSet instanceof Lang.Dictionary &&
                GymStore.sameOptionalText(frameSet.get("exerciseName"), "Bench Press") &&
                frameSet.get("weight") == 50.0 && frameSet.get("reps") == 8 &&
                frameMetadata instanceof Lang.Dictionary &&
                frameMetadata.get("durationSeconds") == 15 &&
                frameMetadata.get("gymCalories") == 5.0 &&
                frameMetadata.get("avgHeartRate") == 120 &&
                frameMetadata.get("maxHeartRate") == 140 &&
                frameMetadata.get("lastHeartRate") == 135 &&
                frameMetadata.get("heartRateZone") == 2 &&
                frameMetadata.get("setIntervals") == null &&
                storedFirst instanceof Lang.Array && storedFirst[4] == null;
        } catch (e) {
            logger.debug("manual96 large journal exception=" + e.toString());
        }
        if (!(began && setsAdded == 15 && activeValid && mixedRejected &&
            malformedRejected && restoredAfterValidation && prepared && fitSaved &&
            committed && reloaded && frameValid)) {
            logger.debug("manual96 large stages began=" + began.toString() +
                " sets=" + setsAdded.toString() + " active=" + activeValid.toString() +
                " mixed=" + mixedRejected.toString() + " malformed=" +
                malformedRejected.toString() + " restored=" + restoredAfterValidation.toString() +
                " prepared=" + prepared.toString() + " fit=" + fitSaved.toString() +
                " committed=" + committed.toString() + " reloaded=" + reloaded.toString() +
                " frame=" + frameValid.toString());
        }
        return began && setsAdded == 15 && activeValid && mixedRejected &&
            malformedRejected && restoredAfterValidation && prepared && fitSaved &&
            committed && reloaded && frameValid;
    }

    static function abandonedDraftStorageIsUnchanged() {
        var active = Storage.getValue("activeWorkoutV1");
        var row = Storage.getValue("activeRow2-0");
        var checkpoint = active instanceof Lang.Array && active.size() == 10 ?
            active[9] : null;
        var interval = row instanceof Lang.Array && row.size() == 6 ? row[4] : null;
        return active instanceof Lang.Array && active.size() == 10 &&
            active[0] == 6 && GymStore.sameOptionalText(active[1], owner) &&
            GymStore.sameOptionalText(active[2], device) && active[4] == abandonedStartedAt &&
            active[5] == 1 && active[6] == 2 && active[7] == 301 && active[8] == 1 &&
            checkpoint instanceof Lang.Array && checkpoint.size() == 8 &&
            checkpoint[0] == 600 && checkpoint[1] == 8.0 && checkpoint[3] == 264 &&
            checkpoint[4] == 2 && checkpoint[5] == 140 && checkpoint[6] == 132 &&
            checkpoint[7] == 2 && row instanceof Lang.Array && row.size() == 6 &&
            row[0] == 301 && row[1] == 0 && row[2] == 70.0 && row[3] == 9 &&
            interval instanceof Lang.Array && interval.size() == 10 &&
            interval[0] == 360 && interval[1] == 420 && interval[2] == 4.0;
    }

    static function freshReadyState() {
        return GymWorkoutMode.state == GymWorkoutMode.MODE_IDLE &&
            GymStore.status == GymStatus.READY && GymStore.sets.size() == 0 &&
            GymStore.activeWorkoutStartedAtSeconds == null &&
            GymStore.runtimeWorkoutStartedAtSeconds == null &&
            !GymStore.activeWorkoutSnapshotValid && !GymStore.activeWorkoutTimelineValid &&
            GymStore.timelineBase == null && !GymSession.recording && !GymSession.paused &&
            GymSession.startedAt == 0 && GymSession.elapsedSeconds == 0;
    }

    static function newWorkoutDraftIsFresh(startedAt) {
        var active = Storage.getValue("activeWorkoutV1");
        var row = active instanceof Lang.Array && active.size() == 10 ?
            Storage.getValue("activeRow" + active[6].toString() + "-0") : null;
        var checkpoint = active instanceof Lang.Array && active.size() == 10 ?
            active[9] : null;
        return active instanceof Lang.Array && active.size() == 10 && active[0] == 6 &&
            active[4] == startedAt && active[5] == 1 &&
            row instanceof Lang.Array && row.size() == 6 && row[0] == active[7] &&
            row[2] == 45.0 && row[3] == 6 && row[4] == null &&
            checkpoint instanceof Lang.Array && checkpoint.size() == 8 &&
            checkpoint[0] == 15 && checkpoint[1] == 0.0 && checkpoint[2] == null &&
            checkpoint[3] == 120 && checkpoint[4] == 1 && checkpoint[5] == 120 &&
            checkpoint[6] == 120 && checkpoint[7] == 1;
    }

    static function preparedRestartIsStable(fitSaved, requestId, startedAt, logger as Test.Logger) {
        var marker = GymStore.preparedWorkout;
        var setItem = GymStore.sets.size() == 1 ? GymSetAccess.at(GymStore.sets, 0) : null;
        var message = fitSaved ? GymStore.preparedWorkoutMessage() :
            GymStore.preparedWorkoutSetsOnlyMessage();
        var messageSets = message instanceof Lang.Dictionary ? message.get("sets") : null;
        var messageSet = messageSets instanceof Lang.Array && messageSets.size() == 1 ?
            messageSets[0] : null;
        var active = Storage.getValue("activeWorkoutV1");
        var activeRow = active instanceof Lang.Array && active.size() == 10 ?
            Storage.getValue("activeRow" + active[6].toString() + "-0") : null;
        var checkpoint = active instanceof Lang.Array && active.size() == 10 ?
            active[9] : null;
        var activeHeaderValid = active instanceof Lang.Array && active.size() == 10 &&
            active[0] == 6 && active[4] == startedAt && active[5] == 1;
        var checkpointValid = checkpoint instanceof Lang.Array && checkpoint.size() == 8 &&
            checkpoint[0] == 15 && checkpoint[1] == 0.0 && checkpoint[2] == null &&
            checkpoint[3] == 120 && checkpoint[4] == 1 && checkpoint[5] == 120 &&
            checkpoint[6] == 120 && checkpoint[7] == 1;
        var activeRowValid = activeRow instanceof Lang.Array && activeRow.size() == 6 &&
            activeRow[4] == null;
        var setValid = GymStore.sets.size() == 1 && setItem != null &&
            GymStore.sameOptionalText(GymStore.setField(setItem, "exerciseName"), "Bench Press") &&
            GymStore.setField(setItem, "weight") == 45.0 &&
            GymStore.setField(setItem, "reps") == 6;
        var markerValid = marker instanceof Lang.Array && marker.size() == 7 &&
            marker[5] == (fitSaved ? 1 : 0) &&
            GymStore.sameOptionalText(marker[4], requestId);
        var preparedValid = GymStore.hasPreparedWorkout() &&
            GymStore.preparedWorkoutFitSaved() == fitSaved;
        var aggregatePreserved = active instanceof Lang.Array && active.size() == 10 &&
            GymStore.activeWorkoutSnapshotValid &&
            GymActiveJournal.currentRecords() != null &&
            GymStore.activeWorkoutTimelineValid &&
            checkpointValid &&
            GymStore.timelineBase instanceof Lang.Array &&
            GymStore.timelineBase[0] == 15 && GymSession.elapsedSeconds == 0 &&
            activeRowValid;
        var messageValid = GymStore.isValidWorkoutMessage(message) &&
            GymStore.sameOptionalText(message.get("requestId"), requestId) &&
            message.get("startedAtSeconds") == startedAt &&
            message.get("durationSeconds") == 15 && message.get("gymCalories") == 0.0 &&
            message.get("avgHeartRate") == 120 && message.get("maxHeartRate") == 120 &&
            message.get("setIntervals") == null &&
            messageSet instanceof Lang.Dictionary &&
            GymStore.sameOptionalText(messageSet.get("exerciseName"), "Bench Press") &&
            messageSet.get("weight") == 45.0 && messageSet.get("reps") == 6;
        var messageMissingIntervals = message instanceof Lang.Dictionary &&
            message.get("setIntervals") == null;
        var cannotResumeOrStart = GymWorkoutMode.state == GymWorkoutMode.MODE_IDLE &&
            !GymWorkoutMode.canResume() && !GymWorkoutMode.begin(true) &&
            GymWorkoutMode.state == GymWorkoutMode.MODE_IDLE;
        var valid = preparedValid && markerValid && setValid &&
            GymStore.activeWorkoutStartedAtSeconds == startedAt &&
            activeHeaderValid && aggregatePreserved && messageValid &&
            cannotResumeOrStart;
        if (!valid) {
            logger.debug("manual96 prepared restart fit=" + fitSaved.toString() +
                " prepared=" + preparedValid.toString() + " marker=" + markerValid.toString() +
                " set=" + setValid.toString() + " header=" + activeHeaderValid.toString() +
                " checkpoint=" + checkpointValid.toString() + " row=" +
                activeRowValid.toString() + " aggregate=" + aggregatePreserved.toString() +
                " message=" + messageValid.toString() + " missingIntervals=" +
                messageMissingIntervals.toString() + " resume=" + cannotResumeOrStart.toString());
        }
        return valid;
    }

    static function workoutMessageIsFresh(message, startedAt, expectedDuration) {
        var messageSets = message instanceof Lang.Dictionary ? message.get("sets") : null;
        var item = messageSets instanceof Lang.Array && messageSets.size() == 1 ?
            messageSets[0] : null;
        return GymStore.isValidWorkoutMessage(message) &&
            GymStore.sameOptionalText(message.get("workoutMode"), "planned") &&
            message.get("startedAtSeconds") == startedAt &&
            message.get("durationSeconds") == expectedDuration &&
            message.get("gymCalories") == 0.0 &&
            message.get("avgHeartRate") == 120 && message.get("maxHeartRate") == 120 &&
            message.get("setIntervals") == null &&
            item instanceof Lang.Dictionary &&
            GymStore.sameOptionalText(item.get("exerciseName"), "Bench Press") &&
            item.get("weight") == 45.0 && item.get("reps") == 6;
    }

    static function queuedWorkoutIsFresh(startedAt, expectedDuration) {
        var queue = Storage.getValue("pending");
        return queue instanceof Lang.Array && queue.size() == 1 &&
            GymStore.isValidPendingList(queue) &&
            workoutMessageIsFresh(queue[0], startedAt, expectedDuration);
    }

    static function seedUnsupportedPlan() {
        seedCommon();
        clearKey("activeWorkoutV1");
        clearKey("activeWorkoutModeV1");
        clearKey("activeWorkoutStartedAtSeconds");
        clearKey("sets");
        var oldPlan = [{
            "exerciseName" => "Bench Press",
            "weight" => 62.5,
            "reps" => 7
        }];
        Storage.setValue("plan", oldPlan);
        Storage.setValue("pending", []);
        clearKey("pendingJournalV1");
        clearKey("queueEntry0-3");
        clearKey("queueEntry1-3");
        clearKey("queueName3-0");
        clearKey("activeRow2-0");
        clearKey("activeRow3-0");
        return true;
    }

    static function seedUnownedOrphanData() {
        var now = Toybox.Time.now().value();
        GymStore.exerciseCatalogRepairRequired = true;
        Storage.setValue("accountBinding", owner);
        clearKey("stateOwnerBinding");
        Storage.setValue("storageSchemaVersion", 6);
        Storage.setValue("deviceBinding", device);
        clearKey("pairingGeneration");
        clearKey("cloudDeviceBinding");
        clearKey("phoneSyncFence");
        clearKey("lastPhoneSyncRevision");
        clearKey("lastPhoneSyncId");
        Storage.setValue("exercises", ["Orphan Bench"]);
        Storage.setValue("plan", [{
            "exerciseName" => "Orphan Bench",
            "weight" => 62.5,
            "reps" => 7
        }]);

        var activeStart = now - 120;
        Storage.setValue("activeWorkoutV1", [
            6, owner, device, null, activeStart, 1, 2, 501, 1, null
        ]);
        Storage.setValue("activeRow2-0", [501, 0, 70.0, 8, null, 1]);
        Storage.setValue("sets", [{
            "exerciseName" => "Orphan Bench",
            "weight" => 70.0,
            "reps" => 8
        }]);
        Storage.setValue("activeWorkoutStartedAtSeconds", activeStart);

        var pendingWorkout = {
            "type" => "create_workout",
            "bindingVersion" => GymStore.bindingVersion,
            "requestId" => "manual96-orphan-pending-001",
            "workoutMode" => "planned",
            "accountBinding" => owner,
            "deviceBinding" => device,
            "pairingGeneration" => null,
            "startedAtSeconds" => now - 900,
            "durationSeconds" => 600,
            "gymCalories" => 8.0,
            "sets" => [{"exerciseName" => "Orphan Bench", "weight" => 62.5, "reps" => 7}],
            "plannedSetCount" => 1
        };
        Storage.setValue("pending", [pendingWorkout]);

        var journalStart = now - 1800;
        var journalHeader = [6, owner, device, null, journalStart, 1, 3, 601, 1, null];
        var journalMetadata = {
            "type" => "create_workout",
            "bindingVersion" => GymStore.bindingVersion,
            "requestId" => "manual96-orphan-journal-001",
            "workoutMode" => "planned",
            "accountBinding" => owner,
            "deviceBinding" => device,
            "pairingGeneration" => null,
            "startedAtSeconds" => journalStart,
            "durationSeconds" => 300,
            "gymCalories" => 4.0,
            "plannedSetCount" => 1
        };
        Storage.setValue("activeRow3-0", [601, 0, 52.5, 8, null, 1]);
        Storage.setValue("queueName3-0", [601, 0, "Orphan Bench"]);
        Storage.setValue("queueEntry0-3", [
            journalMetadata, journalHeader, GymStore.utf8Bytes("Orphan Bench").size()
        ]);
        clearKey("queueEntry1-3");
        Storage.setValue("pendingJournalV1", [3, 0, [3]]);
        return GymStore.isValidPendingList([pendingWorkout]);
    }

    static function storedCurrentPlanIsValid() {
        var value = Storage.getValue("plan");
        return value instanceof Lang.Array && value.size() == 4 &&
            value[0] == 5 && value[1] instanceof Lang.Array &&
            value[2] instanceof Lang.Array && value[3] instanceof Lang.Array &&
            value[1].size() == 35 && value[2].size() == 35 &&
            value[3].size() == 35 &&
            GymStore.sameOptionalText(value[1][34], "Bench Press") &&
            value[2][34] == 74.0 &&
            value[3][34] == 9;
    }

    static function currentLoadIsPreserved() {
        var normalPending = Storage.getValue("pending");
        var fence = Storage.getValue("phoneSyncFence");
        return GymStore.sameOptionalText(GymStore.accountBinding, owner) &&
            GymStore.sameOptionalText(GymStore.stateOwnerBinding, owner) &&
            GymStore.sameOptionalText(GymStore.deviceBinding, device) &&
            GymStore.plan.size() == 35 &&
            GymPlanAccess.valid(GymStore.plan, GymStore.maxPlanSets, true) &&
            GymStore.sameOptionalText(GymPlanAccess.nameAt(GymStore.plan, 34), "Bench Press") &&
            GymStore.setField(GymPlanAccess.at(GymStore.plan, 34), "weight") == 74.0 &&
            GymStore.setField(GymPlanAccess.at(GymStore.plan, 34), "reps") == 9 &&
            freshReadyState() && abandonedDraftStorageIsUnchanged() &&
            normalPending instanceof Lang.Array && normalPending.size() == 1 &&
            legacyPendingCompatibility(normalPending[0]) &&
            GymStore.sameOptionalText(
                normalPending[0].get("requestId"), "manual96-pending-001") &&
            GymStore.pendingCount() == 2 &&
            GymPendingJournal.entries.size() == 1 &&
            GymPendingJournal.contains("manual96-journal-001") &&
            legacyJournalFrameForwardsInterval() &&
            fence instanceof Lang.Dictionary &&
            GymStore.lastPhoneSyncRevision == 7l &&
            GymStore.sameOptionalText(
                GymStore.lastPhoneSyncId, "manual96-phone-fence-007") &&
            GymStore.sameOptionalText(GymStore.lastPhoneSyncAccountBinding, owner) &&
            storedCurrentPlanIsValid();
    }

    static function copyDictionary(value) {
        if (!(value instanceof Lang.Dictionary)) { return null; }
        var copy = {};
        var keys = value.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            copy.put(keys[i], value.get(keys[i]));
        }
        return copy;
    }

    static function legacyPendingCompatibility(message) {
        if (!(message instanceof Lang.Dictionary)) { return false; }
        var intervals = message.get("setIntervals");
        var interval = intervals instanceof Lang.Array && intervals.size() == 1 ?
            intervals[0] : null;
        var malformed = copyDictionary(message);
        if (malformed != null) {
            malformed.put("setIntervals", [[420, 360, 4.0, null, 0, 0, 0, 0, 0, 0]]);
        }
        var wrongDevice = {
            "bindingVersion" => GymStore.bindingVersion,
            "accountBinding" => owner,
            "deviceBinding" => "manual96-wrong-device",
            "pairingGeneration" => null
        };
        var wrongGeneration = {
            "bindingVersion" => GymStore.bindingVersion,
            "accountBinding" => owner,
            "deviceBinding" => device,
            "pairingGeneration" => owner
        };
        return GymStore.isValidWorkoutMessage(message) &&
            GymStore.isValidPendingList([message]) &&
            GymStore.bindingsMatch(message) &&
            GymStore.sameOptionalText(message.get("accountBinding"), owner) &&
            GymStore.sameOptionalText(message.get("deviceBinding"), device) &&
            message.get("pairingGeneration") == null &&
            interval instanceof Lang.Array && interval.size() == 10 &&
            interval[0] == 360 && interval[1] == 420 && interval[2] == 4.0 &&
            malformed != null && !GymStore.isValidWorkoutMessage(malformed) &&
            !GymStore.bindingsMatch(wrongDevice) && !GymStore.bindingsMatch(wrongGeneration);
    }

    static function drainedLegacyPendingKeepsJournal() {
        var pending = Storage.getValue("pending");
        return pending instanceof Lang.Array && pending.size() == 0 &&
            GymStore.pendingCount() == 1 && GymPendingJournal.entries.size() == 1 &&
            GymPendingJournal.contains("manual96-journal-001");
    }

    static function legacyJournalFrameForwardsInterval() {
        var frame = GymPendingJournal.nextMessage();
        var interval = frame instanceof Lang.Dictionary ? frame.get("interval") : null;
        return frame instanceof Lang.Dictionary &&
            frame.get("type").equals("workout_part") &&
            interval instanceof Lang.Array && interval.size() == 10 &&
            interval[0] == 0 && interval[1] == 120 && interval[2] == 4.0;
    }

    static function unsupportedPlanRemainsStored() {
        var value = Storage.getValue("plan");
        return GymStore.plan.size() == 0 &&
            value instanceof Lang.Array && value.size() == 1 &&
            value[0] instanceof Lang.Dictionary &&
            GymStore.sameOptionalText(value[0].get("exerciseName"), "Bench Press") &&
            value[0].get("weight") == 62.5 &&
            value[0].get("reps") == 7;
    }

    static function phoneSyncReplacedPlan() {
        var value = Storage.getValue("plan");
        return GymStore.plan.size() == 1 &&
            GymPlanAccess.valid(GymStore.plan, GymStore.maxPlanSets, true) &&
            GymStore.sameOptionalText(GymPlanAccess.nameAt(GymStore.plan, 0), "Squat") &&
            GymStore.setField(GymPlanAccess.at(GymStore.plan, 0), "weight") == 90.0 &&
            GymStore.setField(GymPlanAccess.at(GymStore.plan, 0), "reps") == 5 &&
            value instanceof Lang.Array && value.size() == 4 &&
            value[0] == 5 && value[1].size() == 1 &&
            GymStore.sameOptionalText(value[1][0], "Squat") && value[2][0] == 90.0 &&
            value[3][0] == 5 &&
            GymStore.lastPhoneSyncRevision == 8l &&
            GymStore.sameOptionalText(
                GymStore.lastPhoneSyncId, "manual96-phone-sync-008");
    }

    static function unownedOrphansRemainInert() {
        var planValue = Storage.getValue("plan");
        var active = Storage.getValue("activeWorkoutV1");
        var setMirror = Storage.getValue("sets");
        var storedPending = Storage.getValue("pending");
        var journal = Storage.getValue("pendingJournalV1");
        var journalEntry = Storage.getValue("queueEntry0-3");
        var activeRow = Storage.getValue("activeRow2-0");
        var queueRow = Storage.getValue("activeRow3-0");
        return GymStore.accountBinding == null && GymStore.stateOwnerBinding == null &&
            !GymStore.hasAccountBinding() && GymStore.exerciseCatalogRepairRequired &&
            GymStore.plan.size() == 0 && GymStore.sets.size() == 0 &&
            GymStore.pending.size() == 0 && GymStore.pendingCount() == 0 &&
            GymStore.activeWorkoutStartedAtSeconds == null &&
            !GymStore.activeWorkoutSnapshotValid &&
            GymPendingJournal.readable && GymPendingJournal.entries.size() == 0 &&
            GymStore.sameOptionalText(Storage.getValue("accountBinding"), owner) &&
            Storage.getValue("stateOwnerBinding") == null &&
            planValue instanceof Lang.Array && planValue.size() == 1 &&
            planValue[0] instanceof Lang.Dictionary &&
            GymStore.sameOptionalText(planValue[0].get("exerciseName"), "Orphan Bench") &&
            planValue[0].get("weight") == 62.5 && planValue[0].get("reps") == 7 &&
            active instanceof Lang.Array && active.size() == 10 && active[0] == 6 &&
            GymStore.sameOptionalText(active[1], owner) && active[7] == 501 &&
            setMirror instanceof Lang.Array && setMirror.size() == 1 &&
            setMirror[0] instanceof Lang.Dictionary &&
            GymStore.sameOptionalText(setMirror[0].get("exerciseName"), "Orphan Bench") &&
            storedPending instanceof Lang.Array && storedPending.size() == 1 &&
            GymStore.isValidPendingList(storedPending) &&
            GymStore.sameOptionalText(
                storedPending[0].get("requestId"), "manual96-orphan-pending-001") &&
            journal instanceof Lang.Array && journal.size() == 3 &&
            journal[0] == 3 && journal[1] == 0 && journal[2].size() == 1 &&
            journal[2][0] == 3 && journalEntry instanceof Lang.Array &&
            journalEntry.size() == 3 &&
            GymStore.sameOptionalText(
                journalEntry[0].get("requestId"), "manual96-orphan-journal-001") &&
            activeRow instanceof Lang.Array && activeRow[0] == 501 &&
            queueRow instanceof Lang.Array && queueRow[0] == 601;
    }

    static function restore() {
        var ok = true;
        for (var i = 0; i < oldStorageKeys.size(); i += 1) {
            try {
                if (oldStorage[i] == null) {
                    Storage.deleteValue(oldStorageKeys[i]);
                } else {
                    Storage.setValue(oldStorageKeys[i], oldStorage[i]);
                }
            } catch (e) {
                ok = false;
            }
        }
        // Rebuild private pending/estimate caches from the restored durable
        // queue before reattaching the saved live active-journal view.
        try {
            GymStore.load();
        } catch (e) {
            ok = false;
        }
        if (oldStore != null) {
            GymStore.exercises = oldStore[0];
            GymStore.sets = oldStore[1];
            GymStore.plan = oldStore[2];
            GymStore.persistedPlanSource = oldStore[3];
            GymStore.persistedPlanBytes = oldStore[4];
            GymStore.persistedPlanNeedsV5Write = oldStore[5];
            // Keep the queue reloaded above: its list, parked ids, and byte
            // estimate must remain one coherent cache after cleanup.
            GymStore.exerciseIndex = oldStore[7];
            GymStore.weight = oldStore[8];
            GymStore.reps = oldStore[9];
            GymStore.exerciseCatalogNeedsWrite = oldStore[10];
            GymStore.exerciseCatalogRepairRequired = oldStore[11];
            GymStore.activeWorkoutStartedAtSeconds = oldStore[12];
            GymStore.activeWorkoutSnapshotValid = oldStore[13];
            GymStore.activeWorkoutTimelineValid = oldStore[14];
            GymStore.timelineBase = oldStore[15];
            GymStore.runtimeWorkoutStartedAtSeconds = oldStore[16];
            GymStore.resumedWorkoutIntervalsInvalid = oldStore[17];
            GymStore.status = oldStore[18];
            GymStore.weightStep = oldStore[19];
            GymStore.restSecondsDefault = oldStore[20];
            GymStore.autoPromptEnabled = oldStore[21];
            GymStore.sensitivityIndex = oldStore[22];
            GymStore.language = oldStore[23];
            GymStore.accountBinding = oldStore[24];
            GymStore.stateOwnerBinding = oldStore[25];
            GymStore.deviceBinding = oldStore[26];
            GymStore.pairingGeneration = oldStore[27];
            GymStore.cloudDeviceBinding = oldStore[28];
            GymStore.deferredSync = oldStore[29];
            GymStore.processedSyncIds = oldStore[30];
            GymStore.lastPhoneSyncRevision = oldStore[31];
            GymStore.lastPhoneSyncId = oldStore[32];
            GymStore.lastPhoneSyncAccountBinding = oldStore[33];
            GymStore.preparedWorkout = oldStore[34];
            GymStore.lastWorkoutSyncAtSeconds = oldStore[35];
            GymStore.tutorialHistory = oldStore[36];
            GymStore.lastCloudPlanRevision = oldStore[37];
            GymStore.lastCloudPlanId = oldStore[38];
            GymStore.stagedPhoneSyncRevision = oldStore[39];
            GymStore.stagedPhoneSyncId = oldStore[40];
            GymStore.stagedPhoneAccountBinding = oldStore[41];
            GymStore.stagedPhoneSyncMessage = oldStore[42];
            GymStore.stagedCloudPlanRevision = oldStore[43];
            GymStore.stagedCloudPlanId = oldStore[44];
            GymStore.stagedCloudAccountBinding = oldStore[45];
            GymStore.stagedCloudSyncMessage = oldStore[46];
            GymStore.legacyUnboundState = oldStore[47];
            GymStore.legacyCompactCount = oldStore[48];
            GymStore.pairingRecoveryCommitLast = oldStore[49];
            GymStore.lastSetUndoStartedAt = oldStore[50];
            GymStore.lastSetBoost = oldStore[51];
            GymStore.lastSetWasAutoPrompt = oldStore[52];
            GymStore.lastSetStatistics = oldStore[53];
            GymStore.lastLoggedSetEndSeconds = oldStore[54];
            GymStore.lastSetPreviousLoggedEnd = oldStore[55];
        }
        GymWorkoutMode.state = oldMode;
        if (oldSession != null) {
            GymSession.recording = oldSession[0];
            GymSession.paused = oldSession[1];
            GymSession.startedAt = oldSession[2];
            GymSession.elapsedSeconds = oldSession[3];
            GymSession.hr = oldSession[4];
            GymSession.avgHr = oldSession[5];
            GymSession.maxHr = oldSession[6];
            GymSession.hrSamples = oldSession[7];
            GymSession.zone = oldSession[8];
            GymSession.gymCalories = oldSession[9];
            GymSession.garminCalories = oldSession[10];
        }
        GymActiveJournal.reset();
        oldStorageKeys = null;
        preparedRequestId = null;
        if (GymStore.hasAccountBinding() && oldActiveHeader != null) {
            if (GymStore.isValidActiveWorkoutSnapshot(oldActiveHeader)) {
                var restored = GymActiveJournal.restored(oldActiveHeader);
                if (restored != null) {
                    GymStore.sets = restored;
                } else {
                    ok = false;
                    GymStore.sets = [];
                    GymStore.activeWorkoutSnapshotValid = false;
                    GymStore.activeWorkoutTimelineValid = false;
                    GymStore.timelineBase = null;
                }
            } else {
                ok = false;
                GymStore.sets = [];
                GymStore.activeWorkoutSnapshotValid = false;
                GymStore.activeWorkoutTimelineValid = false;
                GymStore.timelineBase = null;
            }
        }
        if (GymStore.hasAccountBinding()) {
            if (!GymPendingJournal.load()) { ok = false; }
        } else {
            GymPendingJournal.reset();
        }
        return ok;
    }
}

(:test, :compactWorkoutMode96)
function currentV5PlanAndQueuesSurviveManual96Restart(logger as Test.Logger) as Lang.Boolean {
    Manual96LoadFixture.begin(false);
    var seeded = false;
    var beforeSave = false;
    var saved = false;
    var afterSave = false;
    var legacyDrained = false;
    var journalSurvivedDrain = false;
    var valid = false;
    try {
        seeded = Manual96LoadFixture.seedCurrentPlanAndQueue();
        GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
        GymSession.resetWorkoutMetrics();
        GymSession.recording = false;
        GymSession.paused = false;
        GymSession.startedAt = 0;
        GymStore.status = GymStatus.READY;
        GymStore.load();
        beforeSave = Manual96LoadFixture.currentLoadIsPreserved();
        saved = GymStore.save();
        afterSave = Manual96LoadFixture.currentLoadIsPreserved();
        legacyDrained = afterSave && GymStore.removePendingByRequestId("manual96-pending-001");
        journalSurvivedDrain = legacyDrained &&
            Manual96LoadFixture.drainedLegacyPendingKeepsJournal();
        valid = seeded && beforeSave && saved && afterSave && legacyDrained &&
            journalSurvivedDrain;
    } catch (e) {
        logger.debug("manual96 current load fixture error=" + e.toString());
    }
    var restored = Manual96LoadFixture.restore();
    logger.debug("manual96 current load seeded=" + seeded.toString() +
        " beforeSave=" + beforeSave.toString() + " saved=" + saved.toString() +
        " afterSave=" + afterSave.toString() + " legacyDrained=" + legacyDrained.toString() +
        " journal=" + journalSurvivedDrain.toString() + " restored=" + restored.toString());
    return valid && restored;
}

(:test, :compactWorkoutMode96)
function manual96LargeSetJournalKeepsAggregateMetricsWithoutIntervals(logger as Test.Logger) as Lang.Boolean {
    Manual96LoadFixture.begin(true);
    var seeded = false;
    var valid = false;
    try {
        seeded = Manual96LoadFixture.seedLargePlannedWorkout();
        valid = seeded && Manual96LoadFixture.largePlannedJournalOmitsIntervals(logger);
    } catch (e) {
        logger.debug("manual96 large journal fixture error=" + e.toString());
    }
    var restored = Manual96LoadFixture.restore();
    logger.debug("manual96 large journal seeded=" + seeded.toString() +
        " valid=" + valid.toString() + " restored=" + restored.toString());
    return seeded && valid && restored;
}

(:test, :compactWorkoutMode96)
function manual96NewStartDoesNotReuseAbandonedSetOrTimeline(logger as Test.Logger) as Lang.Boolean {
    Manual96LoadFixture.begin(false);
    var seeded = false;
    var readyAfterRestart = false;
    var savedNormally = false;
    var draftUnchangedAfterSave = false;
    var startedFresh = false;
    var addedFreshSet = false;
    var freshDraft = false;
    var prepared = false;
    var phase0Recovered = false;
    var phase0UnknownDecision = false;
    var fitSaved = false;
    var phase1Recovered = false;
    var messageValid = false;
    var queued = false;
    var valid = false;
    try {
        seeded = Manual96LoadFixture.seedSingleAbandonedWorkout();
        GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
        GymSession.resetWorkoutMetrics();
        GymSession.recording = false;
        GymSession.paused = false;
        GymSession.startedAt = 0;
        GymStore.status = GymStatus.READY;
        GymStore.load();
        readyAfterRestart = Manual96LoadFixture.freshReadyState() &&
            Manual96LoadFixture.abandonedDraftStorageIsUnchanged() &&
            GymStore.plan.size() == 1 && GymStore.pendingCount() == 0;
        savedNormally = GymStore.save();
        draftUnchangedAfterSave = Manual96LoadFixture.freshReadyState() &&
            Manual96LoadFixture.abandonedDraftStorageIsUnchanged();

        startedFresh = GymWorkoutMode.begin(true) && GymWorkoutMode.isPlanned() &&
            GymStore.sets.size() == 0 && GymStore.activeWorkoutStartedAtSeconds == null &&
            GymStore.timelineBase == null;
        if (startedFresh) {
            Manual96LoadFixture.newWorkoutStartedAt = Toybox.Time.now().value();
            GymStore.runtimeWorkoutStartedAtSeconds =
                Manual96LoadFixture.newWorkoutStartedAt;
            GymSession.recording = true;
            GymSession.paused = false;
            GymSession.startedAt = Manual96LoadFixture.newWorkoutStartedAt;
            GymSession.elapsedSeconds = 15;
            GymSession.hr = 120;
            GymSession.avgHr = 120;
            GymSession.maxHr = 120;
            GymSession.hrSamples = 1;
            GymSession.zone = 1;
            GymSession.gymCalories = 0.0;
            GymSession.garminCalories = null;
            addedFreshSet = GymStore.addSet();
        }
        freshDraft = addedFreshSet && Manual96LoadFixture.newWorkoutDraftIsFresh(
            Manual96LoadFixture.newWorkoutStartedAt);
        prepared = freshDraft && GymStore.prepareWorkoutCommit();
        if (prepared) {
            Manual96LoadFixture.preparedRequestId = GymStore.preparedWorkout[4].toString();
            GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
            GymSession.recording = false;
            GymSession.paused = false;
            GymSession.startedAt = 0;
            GymSession.resetWorkoutMetrics();
            GymStore.load();
            phase0Recovered = Manual96LoadFixture.preparedRestartIsStable(false,
                Manual96LoadFixture.preparedRequestId,
                Manual96LoadFixture.newWorkoutStartedAt, logger);
            phase0UnknownDecision = GymSession.fitOutcomeUnknownAfterRestart() &&
                GymStore.pendingCount() == 0;
        }
        fitSaved = phase0Recovered && phase0UnknownDecision &&
            GymStore.markPreparedWorkoutFitSaved();
        if (fitSaved) {
            GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
            GymSession.recording = false;
            GymSession.paused = false;
            GymSession.startedAt = 0;
            GymSession.resetWorkoutMetrics();
            GymStore.load();
            phase1Recovered = Manual96LoadFixture.preparedRestartIsStable(true,
                Manual96LoadFixture.preparedRequestId,
                Manual96LoadFixture.newWorkoutStartedAt, logger);
        }
        var message = fitSaved ? GymStore.preparedWorkoutMessage() : null;
        messageValid = phase1Recovered && fitSaved && GymStore.isValidWorkoutMessage(message) &&
            GymStore.sameOptionalText(message.get("requestId"),
                Manual96LoadFixture.preparedRequestId) &&
            message.get("startedAtSeconds") == Manual96LoadFixture.newWorkoutStartedAt;
        queued = messageValid && GymStore.queueWorkout(message) &&
            Manual96LoadFixture.queuedWorkoutIsFresh(
                Manual96LoadFixture.newWorkoutStartedAt, 15);
        valid = seeded && readyAfterRestart && savedNormally && draftUnchangedAfterSave &&
            startedFresh && addedFreshSet && freshDraft && prepared && phase0Recovered &&
            phase0UnknownDecision && fitSaved && phase1Recovered &&
            messageValid && queued;
    } catch (e) {
        logger.debug("manual96 fresh-start fixture error=" + e.toString());
    }
    var restored = Manual96LoadFixture.restore();
    logger.debug("manual96 fresh-start seeded=" + seeded.toString() +
        " ready=" + readyAfterRestart.toString() + " save=" + savedNormally.toString() +
        " stored=" + draftUnchangedAfterSave.toString() +
        " began=" + startedFresh.toString() + " added=" + addedFreshSet.toString() +
        " draft=" + freshDraft.toString() + " prepared=" + prepared.toString() +
        " phase0=" + phase0Recovered.toString() +
        " unknown=" + phase0UnknownDecision.toString() +
        " fit=" + fitSaved.toString() + " message=" + messageValid.toString() +
        " phase1=" + phase1Recovered.toString() + " queued=" + queued.toString() +
        " restored=" + restored.toString());
    return valid && restored;
}

(:test, :compactWorkoutMode96)
function unsupportedManual96PlanWaitsForPhoneReplacement(logger as Test.Logger) as Lang.Boolean {
    Manual96LoadFixture.begin(false);
    var seeded = false;
    var ignored = false;
    var saved = false;
    var stillStored = false;
    var applied = false;
    var replaced = false;
    var valid = false;
    try {
        seeded = Manual96LoadFixture.seedUnsupportedPlan();
        GymStore.load();
        ignored = Manual96LoadFixture.unsupportedPlanRemainsStored();
        saved = GymStore.save();
        stillStored = Manual96LoadFixture.unsupportedPlanRemainsStored();
        GymSession.recording = false;
        GymSession.paused = false;
        GymSession.startedAt = 0;
        GymSession.elapsedSeconds = 0;
        var sync = {
            "type" => "sync",
            "bindingVersion" => GymStore.bindingVersion,
            "syncId" => "manual96-phone-sync-008",
            "requestId" => "manual96-phone-sync-008",
            "accountBinding" => Manual96LoadFixture.owner,
            "deviceBinding" => Manual96LoadFixture.device,
            "syncRevision" => 8l,
            "planNames" => ["Squat"],
            "planWeights" => [90.0],
            "planReps" => [5],
            "exercises" => ["Bench Press", "Squat"],
            "language" => "en"
        };
        applied = GymStore.applyPhoneSync(sync);
        replaced = Manual96LoadFixture.phoneSyncReplacedPlan();
        valid = seeded && ignored && saved && stillStored && applied && replaced;
    } catch (e) {
        logger.debug("manual96 unsupported plan fixture error=" + e.toString());
    }
    var restored = Manual96LoadFixture.restore();
    logger.debug("manual96 raw plan seeded=" + seeded.toString() +
        " ignored=" + ignored.toString() + " saved=" + saved.toString() +
        " stillStored=" + stillStored.toString() + " applied=" + applied.toString() +
        " replaced=" + replaced.toString() + " restored=" + restored.toString());
    return valid && restored;
}

(:test, :compactWorkoutMode96)
function unownedManual96OrphansStayInertAndBlockSave(logger as Test.Logger) as Lang.Boolean {
    Manual96LoadFixture.begin(false);
    var seeded = false;
    var loadedInert = false;
    var saveAccepted = false;
    var preservedAfterSave = false;
    var valid = false;
    try {
        seeded = Manual96LoadFixture.seedUnownedOrphanData();
        GymStore.load();
        loadedInert = Manual96LoadFixture.unownedOrphansRemainInert();
        saveAccepted = GymStore.save();
        preservedAfterSave = Manual96LoadFixture.unownedOrphansRemainInert();
        valid = seeded && loadedInert && !saveAccepted && preservedAfterSave;
    } catch (e) {
        logger.debug("manual96 unowned orphan fixture error=" + e.toString());
    }
    var restored = Manual96LoadFixture.restore();
    logger.debug("manual96 unowned orphans seeded=" + seeded.toString() +
        " inert=" + loadedInert.toString() + " saveAccepted=" + saveAccepted.toString() +
        " preserved=" + preservedAfterSave.toString() + " restored=" + restored.toString());
    return valid && restored;
}
