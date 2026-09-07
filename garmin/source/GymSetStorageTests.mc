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
        logger.debug("Checkpoint denied: " + GymStore.status);
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
