using Toybox.Test as Test;
using Toybox.Lang as Lang;

(:test, :compactLegacyState)
function liveRecordFactoryRejectsInvalidFieldsAndCannotBecomeWireData(logger as Test.Logger) as Lang.Boolean {
    var interval = [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0];
    if (GymRecordedSet.create("", 50.0, 8, interval) != null ||
        GymRecordedSet.create("Bench Press", -1.0, 8, interval) != null ||
        GymRecordedSet.create("Bench Press", 50.0, 0, interval) != null ||
        GymRecordedSet.create("Bench Press", 50.0, 8, [0, 1]) != null) { return false; }
    var record = GymRecordedSet.create("Bench Press", 50.0, 8, interval);
    interval[0] = 1000;
    if (!GymStore.isValidLiveSetList([record], 60, false) ||
        GymStore.setField(record, "setInterval")[0] != 0 ||
        GymStore.isValidSetList([record], 60, false)) { return false; }
    var persisted = false;
    try { Toybox.Application.Storage.setValue("record-boundary-test", record); persisted = true; }
    catch (e) { }
    if (persisted) { Toybox.Application.Storage.deleteValue("record-boundary-test"); }
    return !persisted;
}

(:test)
function pendingBudgetCacheTracksPairingAndAcknowledgement(logger as Test.Logger) as Lang.Boolean {
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var generation = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    GymStore.accountBinding = owner; GymStore.stateOwnerBinding = owner;
    GymStore.deviceBinding = "cache-test"; GymStore.pairingGeneration = null;
    GymStore.preparedWorkout = null; GymStore.sets = []; GymStore.plan = [];
    GymStore.deferredSync = null;
    Toybox.Application.Storage.deleteValue("queuedActiveRequestId");
    var message = {"type" => "create_workout", "bindingVersion" => 2,
        "accountBinding" => owner, "deviceBinding" => "cache-test",
        "requestId" => "cache-request", "workoutMode" => "free", "sets" => [],
        "startedAtSeconds" => 1700000000, "durationSeconds" => 60, "gymCalories" => 1.0};
    GymStore.pending = [message];
    if (!GymStore.isValidWorkoutMessage(message)) { return false; }
    var before = GymStore.estimatedPendingBytes();
    if (before != GymStore.estimatedValueBytes(GymStore.pending) ||
        !GymStore.rotatePairingGenerationForPending(null, generation)) { return false; }
    GymStore.pairingGeneration = generation;
    if (GymStore.estimatedPendingBytes() <= before ||
        GymStore.estimatedPendingBytes() != GymStore.estimatedValueBytes(GymStore.pending)) {
        return false;
    }
    if (!GymStore.removePendingByRequestId("cache-request") || GymStore.pending.size() != 0) {
        return false;
    }
    return GymStore.estimatedPendingBytes() == GymStore.estimatedValueBytes(GymStore.pending);
}

(:test)
function compactSnapshotEstimateCoversMaximumNumericColumns(logger as Test.Logger) as Lang.Boolean {
    var names = []; var weights = []; var reps = []; var intervals = [];
    for (var i = 0; i < 60; i += 1) {
        names.add(0); weights.add(1000000.0); reps.add(10000);
        intervals.add([i * 7200, (i + 1) * 7200, 100000.0, 100000,
            0, 0, 0, 0, 0, 7200]);
    }
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var snapshot = [4, owner, owner + owner, owner, 2147483647,
        names, weights, reps, intervals,
        [432000, 6000000.0, 6000000, 103680000, 432000, 240, 240, 5]];
    return GymStore.isValidActiveWorkoutSnapshot(snapshot) &&
        GymStore.estimatedActiveSnapshotBytes(snapshot) >=
        GymStore.estimatedValueBytes(snapshot);
}

(:test)
function recordedSetPreservesValuesAndCompactInterval(logger as Test.Logger) as Lang.Boolean {
    var interval = [12, 30, 4.0, null, 0, 0, 0, 0, 0, 0];
    var statistics = {"activeSeconds" => 18, "startHeartRate" => 110,
        "peakHeartRate" => 130, "endHeartRate" => 120, "detectionConfidence" => 80};
    var recorded = GymStore.recordedSet("Bench Press", 52.5, 8, statistics, 90, interval);
    if (!GymStore.setField(recorded, "exerciseName").equals("Bench Press") ||
        GymStore.setField(recorded, "weight") != 52.5 || GymStore.setField(recorded, "reps") != 8) {
        return false;
    }
    var restoredInterval = GymStore.setField(recorded, "setInterval");
    for (var i = 0; i < 10; i += 1) {
        if (restoredInterval[i] != interval[i]) { return false; }
    }
    if (GymStore.keepsSetDiagnostics) {
        return GymStore.setField(recorded, "peakHeartRate") == 130;
    }
    logger.debug("Compact set retains exact values and no duplicate detector history");
    return GymStore.isSetRecord(recorded) && GymStore.setField(recorded, "peakHeartRate") == null;
}

(:test)
function recordedIntervalsPreserveExactNumbersAndRejectMalformedCheckpoints(logger as Test.Logger) as Lang.Boolean {
    var interval = [597600, 604800, 0.123456789d, 100000, 1200, 1200, 1200, 1200, 1200, 1200];
    var precise = GymStore.restoredSet("Bench Press", 52.123456789d, 8, interval);
    if (!(GymStore.setField(precise, "weight") instanceof Lang.Double) ||
        GymStore.setField(precise, "weight") != 52.123456789d) { return false; }
    var restored = GymStore.setField(precise, "setInterval");
    for (var i = 0; i < 10; i += 1) { if (restored[i] != interval[i]) { return false; } }
    if (!(restored[2] instanceof Lang.Double)) { return false; }
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var checkpoint = [604800, 1.0, 100000, 0, 0, 0, null, 0];
    var snapshot = [4, owner, "column-test", null, 1700000000,
        [0], [52.123456789d], [10000], [interval], checkpoint];
    if (!GymStore.isValidActiveWorkoutSnapshot(snapshot)) { return false; }
    snapshot[8] = [];
    if (GymStore.isValidActiveWorkoutSnapshot(snapshot)) { return false; }
    snapshot[8] = [interval]; interval[2] = 100001.0;
    if (GymStore.isValidActiveWorkoutSnapshot(snapshot)) { return false; }
    interval[2] = 0.123456789d; interval[4] = 65535;
    return !GymStore.isValidActiveWorkoutSnapshot(snapshot);
}

(:test, :notFr55Memory, :richWorkoutMode)
function boundLoadDefersLegacyMirrorUntilSnapshotDecision(logger as Test.Logger) as Lang.Boolean {
    var previousStoredSets = Toybox.Application.Storage.getValue("sets");
    var previousStoredStartedAt = Toybox.Application.Storage.getValue("activeWorkoutStartedAtSeconds");
    var previousSets = GymStore.sets;
    var previousStartedAt = GymStore.activeWorkoutStartedAtSeconds;
    var previousIntervalsInvalid = GymStore.resumedWorkoutIntervalsInvalid;
    var previousOwner = GymStore.accountBinding;
    var previousStateOwner = GymStore.stateOwnerBinding;
    var previousDevice = GymStore.deviceBinding;
    var previousGeneration = GymStore.pairingGeneration;

    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var otherOwner = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var device = "deferred-mirror-test";
    var startedAt = 1700000000;
    var mirror = [
        {"exerciseName" => "Bench Press", "weight" => 52.5, "reps" => 8,
            "setInterval" => [0, 30, 4.0, null, 0, 0, 0, 0, 0, 0]},
        {"exerciseName" => "Squat", "weight" => 75.0, "reps" => 10,
            "setInterval" => [30, 60, 3.0, null, 0, 0, 0, 0, 0, 0]}
    ];
    var validActive = [2, owner, device, null, startedAt, mirror, null];
    var wrongOwnerActive = [2, otherOwner, device, null, startedAt, mirror, null];
    var corruptActive = ["corrupt active snapshot"];
    var retainedCatalogSnapshot = [4, owner, device, null, startedAt, [], [], []];
    var passed = false;

    try {
        Toybox.Application.Storage.setValue("sets", mirror);
        Toybox.Application.Storage.setValue("activeWorkoutStartedAtSeconds", startedAt);
        GymStore.accountBinding = owner;
        GymStore.stateOwnerBinding = owner;
        GymStore.deviceBinding = device;
        GymStore.pairingGeneration = null;

        GymStore.sets = [];
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var coldFallback = GymStore.restoreLegacySetMirrorIfSnapshotAbsent(null) &&
            GymStore.sets.size() == 2 &&
            GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "weight") == 52.5 &&
            GymStore.setField(GymSetAccess.at(GymStore.sets, 1), "reps") == 10 &&
            GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "setInterval")[2] == 4.0 &&
            GymStore.activeWorkoutStartedAtSeconds == startedAt &&
            GymStore.resumedWorkoutIntervalsInvalid;

        GymStore.sets = [];
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var validSnapshotSuppressesMirror =
            GymStore.isValidActiveWorkoutSnapshot(validActive) &&
            GymStore.activeWorkoutSnapshotMatchesBindings(validActive) &&
            !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(validActive) &&
            GymStore.sets.size() == 0 &&
            GymStore.activeWorkoutStartedAtSeconds == null &&
            !GymStore.resumedWorkoutIntervalsInvalid;

        GymStore.sets = [];
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var corruptSnapshotSuppressesMirror =
            !GymStore.isValidActiveWorkoutSnapshot(corruptActive) &&
            !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(corruptActive) &&
            GymStore.sets.size() == 0;

        GymStore.sets = [];
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var wrongOwnerSuppressesMirror =
            GymStore.isValidActiveWorkoutSnapshot(wrongOwnerActive) &&
            !GymStore.activeWorkoutSnapshotMatchesBindings(wrongOwnerActive) &&
            !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(wrongOwnerActive) &&
            GymStore.sets.size() == 0;

        // A null saved value is the state after catalog repair successfully deletes
        // the unsupported snapshot. A retained v4 value models deletion failure.
        GymStore.sets = [];
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var catalogDeleteSuccessRestoresMirror =
            GymStore.restoreLegacySetMirrorIfSnapshotAbsent(null) &&
            GymStore.sets.size() == 2 &&
            GymStore.activeWorkoutStartedAtSeconds == startedAt;

        GymStore.sets = [];
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var catalogDeleteFailureKeepsMirrorSuppressed =
            retainedCatalogSnapshot[0] == 4 &&
            !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(retainedCatalogSnapshot) &&
            GymStore.sets.size() == 0 &&
            GymStore.activeWorkoutStartedAtSeconds == null;

        passed = coldFallback && validSnapshotSuppressesMirror &&
            corruptSnapshotSuppressesMirror && wrongOwnerSuppressesMirror &&
            catalogDeleteSuccessRestoresMirror && catalogDeleteFailureKeepsMirrorSuppressed;
    } catch (e) {
        logger.debug("Deferred mirror fixture failed: " + e.toString());
    }

    try {
        if (previousStoredSets == null) { Toybox.Application.Storage.deleteValue("sets"); }
        else { Toybox.Application.Storage.setValue("sets", previousStoredSets); }
        if (previousStoredStartedAt == null) { Toybox.Application.Storage.deleteValue("activeWorkoutStartedAtSeconds"); }
        else { Toybox.Application.Storage.setValue("activeWorkoutStartedAtSeconds", previousStoredStartedAt); }
    } catch (e) {
        passed = false;
    }
    GymStore.sets = previousSets;
    GymStore.activeWorkoutStartedAtSeconds = previousStartedAt;
    GymStore.resumedWorkoutIntervalsInvalid = previousIntervalsInvalid;
    GymStore.accountBinding = previousOwner;
    GymStore.stateOwnerBinding = previousStateOwner;
    GymStore.deviceBinding = previousDevice;
    GymStore.pairingGeneration = previousGeneration;
    return passed;
}

(:test, :fr55Memory)
function fr55IgnoresLegacySetMirrorWithoutClearingCurrentState(logger as Test.Logger) as Lang.Boolean {
    var previousStoredSets = Toybox.Application.Storage.getValue("sets");
    var previousStoredStartedAt = Toybox.Application.Storage.getValue("activeWorkoutStartedAtSeconds");
    var previousSets = GymStore.sets;
    var previousPlan = GymStore.plan;
    var previousPending = GymStore.pending;
    var previousStartedAt = GymStore.activeWorkoutStartedAtSeconds;
    var previousRuntimeStartedAt = GymStore.runtimeWorkoutStartedAtSeconds;
    var previousTimeline = GymStore.timelineBase;
    var previousSnapshotValid = GymStore.activeWorkoutSnapshotValid;
    var previousTimelineValid = GymStore.activeWorkoutTimelineValid;
    var previousIntervalsInvalid = GymStore.resumedWorkoutIntervalsInvalid;
    var previousStatus = GymStore.status;
    var passed = false;

    var legacySets = [
        {"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8}
    ];
    var legacyStartedAt = 1699999900;
    var currentSets = [GymStore.recordedSet("Squat", 80.0, 6, {}, null,
        [0, 30, 4.0, null, 0, 0, 0, 0, 0, 0])];
    var currentPlan = [{"exerciseName" => "Bench Press", "weight" => 60.0, "reps" => 8}];
    var currentPending = [{"requestId" => "fr55-recovery-test"}];
    var currentTimeline = [30, 4.0, null, 0, 0, 0, null, 0];
    var currentStartedAt = 1700000000;

    try {
        Toybox.Application.Storage.setValue("sets", legacySets);
        Toybox.Application.Storage.setValue("activeWorkoutStartedAtSeconds", legacyStartedAt);
        GymStore.sets = currentSets;
        GymStore.plan = currentPlan;
        GymStore.pending = currentPending;
        GymStore.activeWorkoutStartedAtSeconds = currentStartedAt;
        GymStore.runtimeWorkoutStartedAtSeconds = currentStartedAt;
        GymStore.timelineBase = currentTimeline;
        GymStore.activeWorkoutSnapshotValid = true;
        GymStore.activeWorkoutTimelineValid = true;
        GymStore.resumedWorkoutIntervalsInvalid = false;

        var ignoredNullMirror = !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(null) &&
            GymStore.sets == currentSets &&
            GymStore.activeWorkoutStartedAtSeconds == currentStartedAt &&
            GymStore.runtimeWorkoutStartedAtSeconds == currentStartedAt &&
            GymStore.timelineBase == currentTimeline &&
            GymStore.activeWorkoutSnapshotValid && GymStore.activeWorkoutTimelineValid &&
            !GymStore.resumedWorkoutIntervalsInvalid &&
            GymStore.plan == currentPlan && GymStore.pending == currentPending;
        var ignoredInvalidMirror = !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(["invalid"]) &&
            GymStore.sets == currentSets &&
            GymStore.activeWorkoutStartedAtSeconds == currentStartedAt &&
            GymStore.runtimeWorkoutStartedAtSeconds == currentStartedAt &&
            GymStore.timelineBase == currentTimeline &&
            GymStore.activeWorkoutSnapshotValid && GymStore.activeWorkoutTimelineValid &&
            !GymStore.resumedWorkoutIntervalsInvalid &&
            GymStore.plan == currentPlan && GymStore.pending == currentPending;
        var mirrorRemainsStored =
            Toybox.Application.Storage.getValue("activeWorkoutStartedAtSeconds") == legacyStartedAt;
        var storedMirror = Toybox.Application.Storage.getValue("sets");
        mirrorRemainsStored = mirrorRemainsStored && storedMirror instanceof Lang.Array &&
            storedMirror.size() == 1 &&
            GymStore.setField(GymSetAccess.at(storedMirror, 0), "weight") == 50.0;
        passed = ignoredNullMirror && ignoredInvalidMirror && mirrorRemainsStored;
    } catch (e) {
        logger.debug("FR55 legacy mirror fixture failed: " + e.toString());
    }

    try {
        if (previousStoredSets == null) { Toybox.Application.Storage.deleteValue("sets"); }
        else { Toybox.Application.Storage.setValue("sets", previousStoredSets); }
        if (previousStoredStartedAt == null) {
            Toybox.Application.Storage.deleteValue("activeWorkoutStartedAtSeconds");
        } else {
            Toybox.Application.Storage.setValue("activeWorkoutStartedAtSeconds", previousStoredStartedAt);
        }
    } catch (e) {
        passed = false;
    }
    GymStore.sets = previousSets;
    GymStore.plan = previousPlan;
    GymStore.pending = previousPending;
    GymStore.activeWorkoutStartedAtSeconds = previousStartedAt;
    GymStore.runtimeWorkoutStartedAtSeconds = previousRuntimeStartedAt;
    GymStore.timelineBase = previousTimeline;
    GymStore.activeWorkoutSnapshotValid = previousSnapshotValid;
    GymStore.activeWorkoutTimelineValid = previousTimelineValid;
    GymStore.resumedWorkoutIntervalsInvalid = previousIntervalsInvalid;
    GymStore.status = previousStatus;
    return passed;
}

(:test, :fr55Memory)
function fr55DropsOwnerlessActiveStateAndKeepsPlanAndPending(logger as Test.Logger) as Lang.Boolean {
    var previousSets = GymStore.sets;
    var previousPlan = GymStore.plan;
    var previousPending = GymStore.pending;
    var previousStartedAt = GymStore.activeWorkoutStartedAtSeconds;
    var previousRuntimeStartedAt = GymStore.runtimeWorkoutStartedAtSeconds;
    var previousRuntimeCheckpoint = GymStore.lastRuntimeCheckpointTimerMs;
    var previousTimeline = GymStore.timelineBase;
    var previousSnapshotValid = GymStore.activeWorkoutSnapshotValid;
    var previousTimelineValid = GymStore.activeWorkoutTimelineValid;
    var previousIntervalsInvalid = GymStore.resumedWorkoutIntervalsInvalid;
    var previousLegacyCount = GymStore.legacyCompactCount;
    var previousJournalSnapshot = GymActiveJournal.snapshot();
    var previousJournalStagingBytes = GymActiveJournal.stagingBytes;

    var staleSets = [GymStore.recordedSet("Bench Press", 50.0, 8, {}, null, null)];
    var keptPlan = [{"exerciseName" => "Squat", "weight" => 80.0, "reps" => 5}];
    var keptPending = [{"requestId" => "fr55-quarantine-test"}];
    var keptStartedAt = 1700000000;
    var keptRuntimeStartedAt = 1699999900;
    var keptTimeline = [30, 4.0, null, 0, 0, 0, null, 0];

    GymStore.sets = staleSets;
    GymStore.plan = keptPlan;
    GymStore.pending = keptPending;
    GymStore.activeWorkoutStartedAtSeconds = keptStartedAt;
    GymStore.runtimeWorkoutStartedAtSeconds = keptRuntimeStartedAt;
    GymStore.lastRuntimeCheckpointTimerMs = 12000;
    GymStore.timelineBase = keptTimeline;
    GymStore.activeWorkoutSnapshotValid = true;
    GymStore.activeWorkoutTimelineValid = true;
    GymStore.resumedWorkoutIntervalsInvalid = true;
    GymStore.legacyCompactCount = 1;

    GymStore.discardLegacyUnboundActiveWorkout();
    var clearedActive = GymStore.sets.size() == 0 &&
        GymStore.activeWorkoutStartedAtSeconds == null &&
        GymStore.runtimeWorkoutStartedAtSeconds == null &&
        GymStore.lastRuntimeCheckpointTimerMs == null &&
        GymStore.timelineBase == null &&
        !GymStore.activeWorkoutSnapshotValid &&
        !GymStore.activeWorkoutTimelineValid &&
        !GymStore.resumedWorkoutIntervalsInvalid &&
        GymStore.legacyCompactCount == 0 &&
        GymActiveJournal.snapshot() == null;
    var preservedRecovery = GymStore.plan == keptPlan && GymStore.pending == keptPending;

    GymStore.sets = staleSets;
    GymStore.activeWorkoutStartedAtSeconds = keptStartedAt;
    GymStore.runtimeWorkoutStartedAtSeconds = keptRuntimeStartedAt;
    GymStore.lastRuntimeCheckpointTimerMs = 12000;
    GymStore.timelineBase = keptTimeline;
    GymStore.activeWorkoutSnapshotValid = true;
    GymStore.activeWorkoutTimelineValid = true;
    GymStore.resumedWorkoutIntervalsInvalid = true;
    GymStore.legacyCompactCount = -2;
    GymStore.discardLegacyUnboundActiveWorkout();
    var malformedQuarantineRemainsFailClosed =
        GymStore.sets.size() == 0 &&
        GymStore.activeWorkoutStartedAtSeconds == null &&
        GymStore.runtimeWorkoutStartedAtSeconds == null &&
        GymStore.lastRuntimeCheckpointTimerMs == null &&
        GymStore.timelineBase == null &&
        !GymStore.activeWorkoutSnapshotValid &&
        !GymStore.activeWorkoutTimelineValid &&
        !GymStore.resumedWorkoutIntervalsInvalid &&
        GymStore.legacyCompactCount == -2 &&
        GymStore.plan == keptPlan && GymStore.pending == keptPending;

    GymStore.sets = previousSets;
    GymStore.plan = previousPlan;
    GymStore.pending = previousPending;
    GymStore.activeWorkoutStartedAtSeconds = previousStartedAt;
    GymStore.runtimeWorkoutStartedAtSeconds = previousRuntimeStartedAt;
    GymStore.lastRuntimeCheckpointTimerMs = previousRuntimeCheckpoint;
    GymStore.timelineBase = previousTimeline;
    GymStore.activeWorkoutSnapshotValid = previousSnapshotValid;
    GymStore.activeWorkoutTimelineValid = previousTimelineValid;
    GymStore.resumedWorkoutIntervalsInvalid = previousIntervalsInvalid;
    GymStore.legacyCompactCount = previousLegacyCount;
    var restoredJournal = previousJournalSnapshot == null ? true :
        GymActiveJournal.validate(previousJournalSnapshot);
    GymActiveJournal.stagingBytes = previousJournalStagingBytes;
    return clearedActive && preservedRecovery && malformedQuarantineRemainsFailClosed &&
        restoredJournal;
}

(:test, :compactWorkoutMode96)
function compact96SkipsLegacyMirrorAndPreservesQuarantine(logger as Test.Logger) as Lang.Boolean {
    var previousStoredSets = Toybox.Application.Storage.getValue("sets");
    var previousStoredStartedAt = Toybox.Application.Storage.getValue("activeWorkoutStartedAtSeconds");
    var previousSets = GymStore.sets;
    var previousPlan = GymStore.plan;
    var previousPending = GymStore.pending;
    var previousStartedAt = GymStore.activeWorkoutStartedAtSeconds;
    var previousRuntimeStartedAt = GymStore.runtimeWorkoutStartedAtSeconds;
    var previousRuntimeCheckpoint = GymStore.lastRuntimeCheckpointTimerMs;
    var previousTimeline = GymStore.timelineBase;
    var previousSnapshotValid = GymStore.activeWorkoutSnapshotValid;
    var previousTimelineValid = GymStore.activeWorkoutTimelineValid;
    var previousIntervalsInvalid = GymStore.resumedWorkoutIntervalsInvalid;
    var previousLegacyCount = GymStore.legacyCompactCount;
    var previousJournalSnapshot = GymActiveJournal.snapshot();
    var previousJournalStagingBytes = GymActiveJournal.stagingBytes;
    var legacySets = [{"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8}];
    var legacyStartedAt = 1699999900;
    var currentSets = [GymStore.recordedSet("Squat", 80.0, 6, {}, null, null)];
    var currentPlan = [{"exerciseName" => "Bench Press", "weight" => 60.0, "reps" => 8}];
    var currentPending = [{"requestId" => "compact96-recovery-test"}];
    var currentStartedAt = 1700000000;
    var passed = false;

    try {
        Toybox.Application.Storage.setValue("sets", legacySets);
        Toybox.Application.Storage.setValue("activeWorkoutStartedAtSeconds", legacyStartedAt);
        GymStore.sets = [];
        GymStore.plan = currentPlan;
        GymStore.pending = currentPending;
        GymStore.activeWorkoutStartedAtSeconds = null;
        GymStore.resumedWorkoutIntervalsInvalid = false;
        var coldMirrorSuppressed =
            !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(null) &&
            GymStore.sets.size() == 0 && GymStore.activeWorkoutStartedAtSeconds == null;

        GymStore.sets = currentSets;
        GymStore.activeWorkoutStartedAtSeconds = currentStartedAt;
        GymStore.runtimeWorkoutStartedAtSeconds = currentStartedAt;
        GymStore.timelineBase = [30, 4.0, null, 0, 0, 0, null, 0];
        GymStore.activeWorkoutSnapshotValid = true;
        GymStore.activeWorkoutTimelineValid = true;
        var invalidMirrorLeavesCurrentState =
            !GymStore.restoreLegacySetMirrorIfSnapshotAbsent(["invalid"]) &&
            GymStore.sets == currentSets &&
            GymStore.activeWorkoutStartedAtSeconds == currentStartedAt &&
            GymStore.runtimeWorkoutStartedAtSeconds == currentStartedAt &&
            GymStore.activeWorkoutSnapshotValid && GymStore.activeWorkoutTimelineValid &&
            GymStore.plan == currentPlan && GymStore.pending == currentPending;
        var storedMirror = Toybox.Application.Storage.getValue("sets");
        var mirrorStillStored =
            Toybox.Application.Storage.getValue("activeWorkoutStartedAtSeconds") == legacyStartedAt &&
            storedMirror instanceof Lang.Array && storedMirror.size() == 1 &&
            GymStore.setField(GymSetAccess.at(storedMirror, 0), "weight") == 50.0;

        GymStore.sets = currentSets;
        GymStore.activeWorkoutStartedAtSeconds = currentStartedAt;
        GymStore.runtimeWorkoutStartedAtSeconds = currentStartedAt;
        GymStore.lastRuntimeCheckpointTimerMs = 12000;
        GymStore.timelineBase = [30, 4.0, null, 0, 0, 0, null, 0];
        GymStore.activeWorkoutSnapshotValid = true;
        GymStore.activeWorkoutTimelineValid = true;
        GymStore.resumedWorkoutIntervalsInvalid = true;
        GymStore.legacyCompactCount = -2;
        GymStore.discardLegacyUnboundActiveWorkout();
        var badQuarantineStillFailsClosed = GymStore.sets.size() == 0 &&
            GymStore.activeWorkoutStartedAtSeconds == null &&
            GymStore.runtimeWorkoutStartedAtSeconds == null &&
            GymStore.lastRuntimeCheckpointTimerMs == null && GymStore.timelineBase == null &&
            !GymStore.activeWorkoutSnapshotValid && !GymStore.activeWorkoutTimelineValid &&
            !GymStore.resumedWorkoutIntervalsInvalid && GymStore.legacyCompactCount == -2 &&
            GymActiveJournal.snapshot() == null &&
            GymStore.plan == currentPlan && GymStore.pending == currentPending;
        passed = coldMirrorSuppressed && invalidMirrorLeavesCurrentState &&
            mirrorStillStored && badQuarantineStillFailsClosed;
    } catch (e) {
        logger.debug("Compact 96 recovery fixture failed: " + e.toString());
    }

    try {
        if (previousStoredSets == null) { Toybox.Application.Storage.deleteValue("sets"); }
        else { Toybox.Application.Storage.setValue("sets", previousStoredSets); }
        if (previousStoredStartedAt == null) {
            Toybox.Application.Storage.deleteValue("activeWorkoutStartedAtSeconds");
        } else {
            Toybox.Application.Storage.setValue("activeWorkoutStartedAtSeconds", previousStoredStartedAt);
        }
    } catch (e) {
        passed = false;
    }
    GymStore.sets = previousSets;
    GymStore.plan = previousPlan;
    GymStore.pending = previousPending;
    GymStore.activeWorkoutStartedAtSeconds = previousStartedAt;
    GymStore.runtimeWorkoutStartedAtSeconds = previousRuntimeStartedAt;
    GymStore.lastRuntimeCheckpointTimerMs = previousRuntimeCheckpoint;
    GymStore.timelineBase = previousTimeline;
    GymStore.activeWorkoutSnapshotValid = previousSnapshotValid;
    GymStore.activeWorkoutTimelineValid = previousTimelineValid;
    GymStore.resumedWorkoutIntervalsInvalid = previousIntervalsInvalid;
    GymStore.legacyCompactCount = previousLegacyCount;
    var restoredJournal = previousJournalSnapshot == null ? true :
        GymActiveJournal.validate(previousJournalSnapshot);
    GymActiveJournal.stagingBytes = previousJournalStagingBytes;
    return passed && restoredJournal;
}

(:test)
function sixtySetCheckpointRestoresAndRejectsOverflow(logger as Test.Logger) as Lang.Boolean {
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "checkpoint-test";
    GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymStore.plan = [];
    GymStore.pending = [];
    GymStore.deferredSync = null;
    GymStore.sets = [];
    logger.debug("Free before sets: " + Toybox.System.getSystemStats().freeMemory.toString());
    var records = [];
    for (var i = 0; i < 60; i += 1) {
        records.add(GymStore.recordedSet("Bench Press", 50.0 + i, 8, {}, null,
            [i * 30, (i + 1) * 30, 4.0, null, 0, 0, 0, 0, 0, 0]));
    }
    logger.debug("Free with 60 sets: " + Toybox.System.getSystemStats().freeMemory.toString());
    var checkpoint = [1800, 240.0, null, 0, 0, 0, null, 0];
    var origin = Toybox.Time.now().value() - 1800;
    if (!GymStore.persistActiveWorkoutSnapshot(records, origin, checkpoint)) {
        logger.debug("Checkpoint denied: " + GymStatus.text(GymStore.status));
        return false;
    }
    records = null;
    var saved = Toybox.Application.Storage.getValue("activeWorkoutV1");
    if (!GymStore.isValidActiveWorkoutSnapshot(saved) ||
        !GymStore.activeWorkoutSnapshotMatchesBindings(saved)) {
        return false;
    }
    GymStore.restoreActiveWorkoutSnapshot(saved);
    saved = null;
    if (GymStore.sets.size() != 60 || GymStore.setField(GymSetAccess.at(GymStore.sets, 59), "weight") != 109.0 ||
        GymStore.activeWorkoutStartedAtSeconds != origin) {
        return false;
    }
    GymStore.sets.add(GymStore.recordedSet("Bench Press", 55.0, 8, {}, null, null));
    if (GymStore.persistActiveWorkoutSnapshot(GymStore.sets, origin, checkpoint)) {
        return false;
    }
    GymStore.sets = [];
    saved = Toybox.Application.Storage.getValue("activeWorkoutV1");
    GymStore.restoreActiveWorkoutSnapshot(saved);
    logger.debug("Restored after denied overflow: " + GymStore.sets.size().toString());
    if (GymStore.sets.size() != 60 || GymStore.setField(GymSetAccess.at(GymStore.sets, 59), "weight") != 109.0) {
        return false;
    }
    // The compact live type must never become an accepted phone wire type.
    if (!GymStore.keepsSetDiagnostics && GymStore.isValidSetList(GymStore.sets, 60, false)) {
        return false;
    }
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    GymSession.recording = false;
    GymSession.elapsedSeconds = 0;
    GymSession.gymCalories = 0.0;
    GymSession.garminCalories = null;
    GymSession.hrSamples = 0;
    GymSession.startedAt = origin;
    GymStore.preparedWorkout = null;
    // Fixture phase transition verifies the queue contract, not the FIT API.
    if (!GymStore.prepareWorkoutCommit() || !GymStore.markPreparedWorkoutFitSaved()) {
        return false;
    }
    var memoryBeforeMessage = Toybox.System.getSystemStats().freeMemory;
    var message = GymStore.preparedWorkoutMessage();
    logger.debug("Sixty-set outgoing message bytes: " +
        (memoryBeforeMessage - Toybox.System.getSystemStats().freeMemory).toString());
    if (!GymStore.isValidWorkoutMessage(message) || message.get("sets").size() != 60 ||
        message.get("setIntervals").size() != 60) { return false; }
    for (var j = 0; j < 60; j += 1) {
        var item = message.get("sets")[j];
        if (!(item instanceof Lang.Dictionary) || item.size() != 3 ||
            !GymStore.setField(item, "exerciseName").equals("Bench Press") || GymStore.setField(item, "weight") != 50.0 + j ||
            GymStore.setField(item, "reps") != 8 || message.get("setIntervals")[j][1] != (j + 1) * 30) {
            return false;
        }
    }
    // Mutable session/timeline adjustments must not change the completed set or
    // the outgoing message that shares its immutable interval.
    var completedInterval = GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "setInterval");
    var adjustedInterval = GymStore.setIntervalForCurrentTimeline(completedInterval);
    adjustedInterval[2] = 999.0;
    if (completedInterval[2] != 4.0 || message.get("setIntervals")[0][2] != 4.0) {
        return false;
    }
    if (!GymStore.appendWorkout(message) || GymStore.sets.size() != 60 ||
        !GymStore.hasPreparedWorkout()) { return false; }
    // The append is durable before the next callback; the active/prepared
    // fence still prevents an early send or a second FIT save.
    if (!Toybox.Application.Storage.getValue("queuedActiveRequestId").equals(message.get("requestId"))) {
        return false;
    }
    if (!GymStore.recoverQueuedWorkout() || GymStore.sets.size() != 0) { return false; }
    // Replaying the original request cannot append it a second time.
    if (!GymStore.queueWorkout(message) || GymStore.pending.size() != 1) { return false; }
    var queued = Toybox.Application.Storage.getValue("pending");
    if (!(queued instanceof Lang.Array) || !GymStore.isValidPendingList(queued) ||
        queued.size() != 1) { return false; }
    var queuedMessage = queued[0] as Lang.Dictionary;
    var queuedSets = queuedMessage.get("sets");
    return queuedSets instanceof Lang.Array && queuedSets.size() == 60;
}

(:test)
function utf8ValidationKeepsExactBytesAndOwnerAlphabet(logger as Test.Logger) as Lang.Boolean {
    var samples = ["", "Bench Press", "Жим штанги", "Підйом", "é", "é", "🏋️"];
    for (var i = 0; i < samples.size(); i += 1) {
        var expected = samples[i].toUtf8Array();
        var actual = GymStore.utf8Bytes(samples[i]);
        if (actual.size() != expected.size()) { return false; }
        for (var j = 0; j < expected.size(); j += 1) {
            if (actual[j] != expected[j]) { return false; }
        }
    }
    var valid = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    if (!GymStore.isValidAccountBinding(valid) ||
        GymStore.isValidAccountBinding(valid.toUpper()) ||
        GymStore.isValidAccountBinding(valid.substring(0, 63) + "ё") ||
        GymStore.isValidAccountBinding(valid.substring(0, 63)) ||
        GymStore.isValidAccountBinding(valid + "0") ||
        GymStore.isValidAccountBinding(null)) { return false; }
    var name = "";
    for (var k = 0; k < 160; k += 1) { name += "Ж"; }
    if (!GymStore.isValidExerciseName(name) || GymStore.isValidExerciseName(name + "Ж")) {
        return false;
    }
    var before = Toybox.System.getSystemStats().freeMemory;
    var packed = GymStore.utf8Bytes(name);
    var packedCost = before - Toybox.System.getSystemStats().freeMemory;
    packed = null;
    before = Toybox.System.getSystemStats().freeMemory;
    var boxed = name.toUtf8Array();
    var boxedCost = before - Toybox.System.getSystemStats().freeMemory;
    logger.debug("UTF-8 bytes " + boxed.size() + ": packed=" + packedCost + " boxed=" + boxedCost);
    return packedCost < boxedCost;
}

(:test)
function exerciseLabelsPreserveLanguageCacheAndCustomNames(logger as Test.Logger) as Lang.Boolean {
    var examples = [
        ["Bench Press", "Жим штанги лежачи", "Жим штанги лежа"],
        ["Straight Arm Pulldown", "Журавель — тяга прямими руками", "Журавель — тяга прямыми руками"],
        ["Curl", "Згинання рук", "Сгибание рук"]
    ];
    var languages = ["en", "uk", "ru", "uk", "en"];
    for (var i = 0; i < languages.size(); i += 1) {
        GymStore.language = languages[i];
        var column = languages[i].equals("uk") ? 1 : languages[i].equals("ru") ? 2 : 0;
        for (var j = 0; j < examples.size(); j += 1) {
            var expected = examples[j][column];
            var first = GymStore.localizedExerciseName(examples[j][0]);
            var cached = GymStore.localizedExerciseName(examples[j][0]);
            if (!first.equals(expected) || !cached.equals(expected)) { return false; }
        }
        var custom = "Bench Press|Жим штанги лежачи";
        if (!GymStore.localizedExerciseName(custom).equals(custom) ||
            !GymStore.localizedExerciseName("~Curl").equals("~Curl")) { return false; }
    }
    return true;
}

(:test)
function plannedFirstTargetSurvivesZeroSetRestart(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "first-target-test";
    GymStore.exercises = ["Bench Press", "Squat"];
    GymStore.plan = [{"exerciseName" => "Squat", "weight" => 72.5, "reps" => 8}];
    GymStore.activeWorkoutStartedAtSeconds = null;
    GymStore.runtimeWorkoutStartedAtSeconds = null;
    GymStore.activeWorkoutSnapshotValid = false;
    GymStore.exerciseIndex = 0;
    GymStore.weight = 50.0;
    GymStore.reps = 10;
    if (!GymStore.saveCurrentEntry() || !GymWorkoutMode.begin(true)) { return false; }
    GymStore.exerciseIndex = 0;
    GymStore.weight = 50.0;
    GymStore.reps = 10;
    var saved = Toybox.Application.Storage.getValue("currentEntryV1");
    var valid = GymStore.restoreCurrentEntry(saved) && GymStore.sets.size() == 0 &&
        GymStore.currentExercise().equals("Squat") && GymStore.weight == 72.5 && GymStore.reps == 8;
    LocalWorkoutFixture.reset();
    return valid;
}

(:test)
function cachedBindingSyntaxDoesNotAuthorizeAnotherOwner(logger as Test.Logger) as Lang.Boolean {
    var first = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var second = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var third = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    var previous = [GymStore.accountBinding, GymStore.stateOwnerBinding,
        GymStore.deviceBinding, GymStore.pairingGeneration];
    var passed = GymStore.isValidAccountBinding(first) &&
        GymStore.isValidAccountBinding(second) && GymStore.isValidAccountBinding(first) &&
        GymStore.isValidAccountBinding(third) && GymStore.isValidAccountBinding(second) &&
        !GymStore.isValidAccountBinding([first]) &&
        !GymStore.isValidAccountBinding(first.toUpper()) &&
        !GymStore.isValidAccountBinding(first.substring(0, 63) + " ");
    GymStore.accountBinding = second;
    GymStore.stateOwnerBinding = second;
    GymStore.deviceBinding = "syntax-cache-test";
    GymStore.pairingGeneration = third;
    var message = {"bindingVersion" => 2, "accountBinding" => first,
        "deviceBinding" => "syntax-cache-test", "pairingGeneration" => third};
    passed = passed && !GymStore.bindingsMatch(message);
    message.put("accountBinding", second);
    passed = passed && GymStore.bindingsMatch(message);
    message.put("pairingGeneration", first);
    passed = passed && !GymStore.bindingsMatch(message);
    GymStore.accountBinding = previous[0];
    GymStore.stateOwnerBinding = previous[1];
    GymStore.deviceBinding = previous[2];
    GymStore.pairingGeneration = previous[3];
    return passed;
}

(:test)
function plannedProgressCountsEachTargetAtMostOnce(logger as Test.Logger) as Lang.Boolean {
    var previousPlan = GymStore.plan;
    var previousSets = GymStore.sets;
    var bench = {"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8};
    var squat = {"exerciseName" => "Squat", "weight" => 60.0, "reps" => 8};
    var extra = {"exerciseName" => "Deadlift", "weight" => 70.0, "reps" => 8};
    GymStore.plan = [bench, squat, bench];
    GymStore.sets = [extra, bench, bench, bench, squat, extra];
    var valid = GymStore.completedPlannedSetCount() == 3;
    GymStore.sets = [extra, bench];
    valid = valid && GymStore.completedPlannedSetCount() == 1;
    GymStore.plan = [];
    valid = valid && GymStore.completedPlannedSetCount() == 0;
    GymStore.plan = previousPlan; GymStore.sets = previousSets;
    return valid;
}

(:test, :compactLegacyState)
function compactLegacyPlanMigratesSimpleRowsAndPreservesOptionalFields(logger as Test.Logger) as Lang.Boolean {
    var beforePlan = GymStore.plan;
    var beforeSource = GymStore.persistedPlanSource;
    var beforeBytes = GymStore.persistedPlanBytes;
    var beforeNeedsWrite = GymStore.persistedPlanNeedsV5Write;
    var beforeExercises = GymStore.exercises;
    var beforeCatalogNeedsWrite = GymStore.exerciseCatalogNeedsWrite;

    var simpleRows = [
        {"exerciseName" => "Жим штанги", "weight" => 52.5, "reps" => 8},
        {"exerciseName" => "Присед", "weight" => 80.0, "reps" => 5}
    ];
    var legacyBytes = GymStore.estimatedValueBytes(simpleRows);
    var migrated = GymStore.restoredPlan(simpleRows);
    GymStore.plan = migrated;
    var stored = GymStore.storedPlan();
    var simpleOk = migrated instanceof GymPlanList &&
        GymPlanAccess.valid(migrated, GymStore.maxPlanSets, false) &&
        GymStore.persistedPlanNeedsV5Write && stored instanceof Lang.Array &&
        stored.size() == 4 && stored[0] == 5 && stored[1][0].equals("Жим штанги") &&
        stored[1][1].equals("Присед") && stored[2][0] == 52.5 && stored[3][1] == 5 &&
        GymStore.persistedPlanBytes == legacyBytes;

    var optionalRows = [{"exerciseName" => "Custom", "weight" => 0, "reps" => 12,
        "activeSeconds" => 20.0,
        "setInterval" => [0, 20, 1.0, null, 0, 0, 0, 0, 0, 0]}];
    var optionalBytes = GymStore.estimatedValueBytes(optionalRows);
    var fallback = GymStore.restoredPlan(optionalRows);
    GymStore.plan = fallback;
    var preserved = GymStore.storedPlan();
    var optionalOk = fallback == optionalRows && preserved == optionalRows &&
        !GymStore.persistedPlanNeedsV5Write &&
        GymStore.setField(preserved[0], "activeSeconds") == 20.0 &&
        GymStore.setField(preserved[0], "setInterval")[1] == 20 &&
        GymStore.persistedPlanBytes == optionalBytes &&
        GymStore.estimatedValueBytes(preserved) == optionalBytes;

    GymStore.plan = beforePlan; GymStore.persistedPlanSource = beforeSource;
    GymStore.persistedPlanBytes = beforeBytes;
    GymStore.persistedPlanNeedsV5Write = beforeNeedsWrite;
    GymStore.exercises = beforeExercises;
    GymStore.exerciseCatalogNeedsWrite = beforeCatalogNeedsWrite;
    return simpleOk && optionalOk;
}

(:test, :compactLegacyState)
function compactV5PlanRejectsMalformedColumnsAndOversizedNameBudget(logger as Test.Logger) as Lang.Boolean {
    var beforePlanSource = GymStore.persistedPlanSource;
    var beforePlanBytes = GymStore.persistedPlanBytes;
    var beforeNeedsWrite = GymStore.persistedPlanNeedsV5Write;

    var names60 = [];
    var weights60 = [];
    var reps60 = [];
    for (var i = 0; i < GymStore.maxPlanSets; i += 1) {
        names60.add("Bench Press");
        weights60.add(50.0);
        reps60.add(8);
    }
    var legacySizedPlan = new GymPlanList([5, names60, weights60, reps60]);
    var countOk = legacySizedPlan.valid(GymStore.maxPlanSets, false) &&
        !legacySizedPlan.valid(GymStore.maxNewWorkoutSets, false);

    var malformed = new GymPlanList([5, ["Bench Press", "Squat"], [50.0], [8]]);
    var malformedRejected = !malformed.valid(GymStore.maxPlanSets, false);
    var longName = "";
    for (var c = 0; c < 101; c += 1) { longName += "Ж"; }
    var overBudgetNames = [];
    var overBudgetWeights = [];
    var overBudgetReps = [];
    for (var n = 0; n < GymStore.maxPlanSets; n += 1) {
        overBudgetNames.add(longName);
        overBudgetWeights.add(50.0);
        overBudgetReps.add(8);
    }
    var overBudget = new GymPlanList([5, overBudgetNames,
        overBudgetWeights, overBudgetReps]);
    var budgetRejected = !GymStore.isValidExerciseList(overBudgetNames,
        GymStore.maxPlanSets) && !overBudget.valid(GymStore.maxPlanSets, false);
    var restoredOverBudget = GymStore.restoredPlan([5, overBudgetNames,
        overBudgetWeights, overBudgetReps]);
    budgetRejected = budgetRejected && restoredOverBudget == null &&
        !GymStore.persistedPlanNeedsV5Write;
    var restoredMalformed = GymStore.restoredPlan([5, ["Bench Press", "Squat"],
        [50.0], [8]]);
    var malformedStateSafe = restoredMalformed == null &&
        !GymStore.persistedPlanNeedsV5Write;

    GymStore.persistedPlanSource = beforePlanSource;
    GymStore.persistedPlanBytes = beforePlanBytes;
    GymStore.persistedPlanNeedsV5Write = beforeNeedsWrite;
    return countOk && malformedRejected && budgetRejected && malformedStateSafe;
}

(:test)
function optionalSetMetricBoundsRemainExact(logger as Test.Logger) as Lang.Boolean {
    var names = ["activeSeconds", "restBeforeSeconds", "startHeartRate", "peakHeartRate",
        "endHeartRate", "recoveryHeartRateDrop", "detectionConfidence"];
    var bounds = [7200.0, 86400.0, 240.0, 240.0, 240.0, 240.0, 100.0];
    var record = {"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8};
    var metrics = [null, null, null, null, null, null, null];
    for (var m = 0; m < names.size(); m += 1) {
        var allowed = [null, 0, bounds[m]];
        for (var a = 0; a < allowed.size(); a += 1) {
            record[names[m]] = allowed[a]; metrics[m] = allowed[a];
            if (!GymStore.isValidSetList([record], 60, false) ||
                !GymStore.isValidSetMetricsList([metrics], [record])) { return false; }
        }
        var denied = [-0.01, bounds[m] + 0.01, "1", true, [], {}];
        for (var d = 0; d < denied.size(); d += 1) {
            record[names[m]] = denied[d]; metrics[m] = denied[d];
            if (GymStore.isValidSetList([record], 60, false) ||
                GymStore.isValidSetMetricsList([metrics], [record])) { return false; }
        }
        record.remove(names[m]); metrics[m] = null;
    }
    return !GymStore.isValidSetMetricsList([[null]], [record]) &&
        !GymStore.isValidSetMetricsList([{}], [record]) &&
        !GymStore.isValidSetMetricsList([], [record]);
}
