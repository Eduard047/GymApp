using Toybox.Test;
using Toybox.Lang;
using Toybox.Application.Storage;

(:test)
class LocalWorkoutFixture {
    (:notFr55Memory, :richWorkoutMode)
    static function resetLocalWorkoutCheckpoint() as Void {
        GymLocalWorkout.lastCheckpoint = null;
    }

    (:fr55Memory)
    static function resetLocalWorkoutCheckpoint() as Void {
    }

    (:compactWorkoutMode96)
    static function resetLocalWorkoutCheckpoint() as Void {
    }

    static function reset() {
    GymStore.accountBinding = null;
    GymStore.deviceBinding = null;
    GymStore.stateOwnerBinding = null;
    GymStore.pairingGeneration = null;
    GymStore.legacyUnboundState = false;
    GymStore.sets = [];
    GymStore.plan = [];
    GymStore.timelineBase = null;
    GymLocalWorkout.snapshot = null;
    GymLocalWorkout.readFailed = false;
    LocalWorkoutFixture.resetLocalWorkoutCheckpoint();
    GymSession.startedAt = 0;
    GymSession.fitSaved = false;
    GymSession.recording = false;
    GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
    Storage.deleteValue("localFreeWorkoutV1");
    }
}

(:test, :notFr55Memory, :richWorkoutMode)
function localWorkoutRestoresMetricsWithoutRecording(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    var saved = [1, 0, 1700000000, [300, 24.5, 20, 1200, 10, 140, 125, 2]];
    if (!GymLocalWorkout.write(saved)) { return false; }
    GymLocalWorkout.restore();
    var valid = GymLocalWorkout.snapshot[2] == 1700000000 &&
        GymStore.timelineBase[0] == 300 && GymStore.totalGymCalories() >= 24.5 &&
        GymStore.hasUnfinishedWorkout() && GymWorkoutMode.isFree() &&
        !GymSession.recording && GymLocalWorkout.blocksPairing();
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :notFr55Memory, :richWorkoutMode)
function localWorkoutRejectsInvalidReplacementAndOwner(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    var saved = [1, 0, 1700000000, [300, 24.5, null, 0, 0, 0, null, 0]];
    if (!GymLocalWorkout.write(saved)) { return false; }
    var bad = [1, 0, 1700000000, [604801, 0.0, null, 0, 0, 0, null, 0]];
    if (GymLocalWorkout.write(bad) || GymLocalWorkout.snapshot != saved) { return false; }
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    if (GymLocalWorkout.write(saved) || GymLocalWorkout.clear()) { return false; }
    GymLocalWorkout.restore();
    var valid = GymLocalWorkout.snapshot == null && GymStore.timelineBase == null &&
        Storage.getValue("localFreeWorkoutV1")[3][0] == 300;
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :notFr55Memory, :richWorkoutMode)
function localWorkoutUnknownFitCannotSaveAgain(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    GymSession.session = null;
    if (!GymLocalWorkout.write([1, 1, 1700000000,
        [300, 24.5, null, 0, 0, 0, null, 0]])) { return false; }
    GymLocalWorkout.restore();
    var valid = GymLocalWorkout.needsDecision() && !GymLocalWorkout.finish() &&
        GymLocalWorkout.snapshot[1] == 1 && !GymSession.recording &&
        Storage.getValue("localFreeWorkoutV1")[1] == 1;
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :notFr55Memory, :richWorkoutMode)
function localWorkoutCorruptionPreservesJournal(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    Storage.setValue("localFreeWorkoutV1", [9, 0]);
    GymLocalWorkout.restore();
    var valid = GymLocalWorkout.readFailed && GymLocalWorkout.blocksPairing() &&
        !GymWorkoutMode.begin(false) && !GymLocalWorkout.clear() &&
        Storage.getValue("localFreeWorkoutV1")[0] == 9;
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :notFr55Memory, :richWorkoutMode)
function localWorkoutPhaseAndTombstoneRoundTrip(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    if (!GymLocalWorkout.write([1, 0, 1700000000,
        [300, 24.5, null, 0, 0, 0, null, 0]])) { return false; }
    if (!GymLocalWorkout.setPhase(1)) { return false; }
    GymLocalWorkout.restore();
    if (!GymLocalWorkout.needsDecision() || !GymLocalWorkout.setPhase(2)) { return false; }
    GymLocalWorkout.restore();
    if (GymLocalWorkout.snapshot[1] != 2 || !GymLocalWorkout.clear()) { return false; }
    GymLocalWorkout.restore();
    var valid = GymLocalWorkout.snapshot == null && GymStore.timelineBase == null &&
        Storage.getValue("localFreeWorkoutV1") == null;
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :notFr55Memory, :richWorkoutMode)
function localWorkoutPairingCannotReplaceRecovery(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    var saved = [1, 0, 1700000000, [300, 24.5, null, 0, 0, 0, null, 0]];
    if (!GymLocalWorkout.write(saved)) { return false; }
    var message = {"type" => "sync", "bindingVersion" => 2,
        "accountBinding" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "deviceBinding" => "recovery-test", "requestId" => "recovery-sync-1",
        "syncId" => "recovery-sync-1", "syncRevision" => 1,
        "planNames" => [], "planWeights" => [], "planReps" => [],
        "exercises" => [], "resetWorkout" => true};
    var valid = GymStore.isValidSyncMessage(message, "phone") &&
        !GymStore.applyPhoneSync(message) && GymStore.accountBinding == null &&
        GymStore.deviceBinding == null && GymLocalWorkout.snapshot == saved &&
        Storage.getValue("localFreeWorkoutV1")[3][0] == 300;
    LocalWorkoutFixture.reset();
    return valid;
}

// Constrained watches expose the real 128 KiB object-store quota even when the
// unit-test runner raises the process heap. Fill only synthetic test keys.
(:test, :notFr55Memory, :compactLegacyState, :richWorkoutMode)
function localWorkoutFullStorageRetainsDurableCheckpoint(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    var saved = [1, 0, 1700000000, [0, 0.0, null, 0, 0, 0, null, 0]];
    if (!GymLocalWorkout.write(saved)) { return false; }
    var filler = "0123456789abcdef";
    for (var i = 0; i < 8; i += 1) { filler += filler; }
    var count = 0;
    var fineCount = 0;
    var filled = false;
    try {
        for (count = 0; count < 64; count += 1) {
            Storage.setValue("recoveryFill" + count.toString(), filler);
        }
    } catch (e) {
        filled = true;
    }
    if (filled) {
        try {
            for (fineCount = 0; fineCount < 512; fineCount += 1) {
                Storage.setValue("recoveryFine" + fineCount.toString(), true);
            }
        } catch (e) {}
    }
    var accepted = GymLocalWorkout.write([1, 0, 1700000000,
        [300, 24.5, 20, 1200, 10, 140, 125, 2]]);
    logger.debug("Quota filled=" + filled.toString() + " chunks=" + count.toString() + " tail=" + fineCount.toString() + " accepted=" + accepted.toString());
    // Fixed-size overwrites may succeed even when a new key cannot fit. Both
    // outcomes must match the actual durable commit, never a partial update.
    var valid = filled && (accepted ?
        (GymLocalWorkout.snapshot[3][0] == 300 &&
            Storage.getValue("localFreeWorkoutV1")[3][0] == 300) :
        (GymLocalWorkout.snapshot == saved &&
            Storage.getValue("localFreeWorkoutV1")[3][0] == 0));
    for (var j = 0; j < count; j += 1) {
        Storage.deleteValue("recoveryFill" + j.toString());
    }
    for (var j = 0; j < fineCount; j += 1) {
        Storage.deleteValue("recoveryFine" + j.toString());
    }
    valid = valid && GymLocalWorkout.write([1, 0, 1700000000,
        [300, 24.5, 20, 1200, 10, 140, 125, 2]]);
    logger.debug("Storage full preserved checkpoint and retry=" + valid.toString());
    LocalWorkoutFixture.reset();
    return valid;
}

(:test, :compactWorkoutMode96)
function compact96IgnoresLocalFreeRecoveryWithoutDeletingIt(logger as Test.Logger) as Lang.Boolean {
    var previousMarker = Storage.getValue("localFreeWorkoutV1");
    var previousSnapshot = GymLocalWorkout.snapshot;
    var previousReadFailed = GymLocalWorkout.readFailed;
    var previousTimeline = GymStore.timelineBase;
    var previousMode = GymWorkoutMode.state;
    var previousPlan = GymStore.plan;
    var previousPending = GymStore.pending;
    var previousFitSaved = GymSession.fitSaved;
    var marker = [1, 0, 1700000000, [300, 24.5, 20, 1200, 10, 140, 125, 2]];
    var testPlan = [["compact96-plan-sentinel"]];
    var testPending = [{"id" => "compact96-pending-sentinel"}];

    Storage.setValue("localFreeWorkoutV1", marker);
    GymLocalWorkout.snapshot = null;
    GymLocalWorkout.readFailed = false;
    GymStore.timelineBase = null;
    GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
    GymStore.plan = testPlan;
    GymStore.pending = testPending;
    GymSession.fitSaved = false;
    GymLocalWorkout.restore();

    var checkpointed = GymLocalWorkout.checkpoint(true);
    var cleared = GymLocalWorkout.clear();
    var stored = Storage.getValue("localFreeWorkoutV1");
    var markerRetained = stored instanceof Lang.Array && stored.size() == 4 &&
        stored[3] instanceof Lang.Array && stored[3][0] == 300;
    var valid = GymLocalWorkout.snapshot == null && !GymLocalWorkout.readFailed &&
        !GymLocalWorkout.needsDecision() && !GymLocalWorkout.blocksPairing() &&
        !GymLocalWorkout.finish() && GymStore.timelineBase == null &&
        GymWorkoutMode.state == GymWorkoutMode.MODE_IDLE && checkpointed && cleared &&
        GymStore.plan == testPlan && GymStore.pending == testPending &&
        !GymSession.fitSaved && markerRetained;

    if (previousMarker == null) {
        Storage.deleteValue("localFreeWorkoutV1");
    } else {
        Storage.setValue("localFreeWorkoutV1", previousMarker);
    }
    GymLocalWorkout.snapshot = previousSnapshot;
    GymLocalWorkout.readFailed = previousReadFailed;
    GymStore.timelineBase = previousTimeline;
    GymWorkoutMode.state = previousMode;
    GymStore.plan = previousPlan;
    GymStore.pending = previousPending;
    GymSession.fitSaved = previousFitSaved;
    return valid;
}

(:test, :fr55Memory)
function fr55IgnoresObsoleteLocalWorkoutMarker(logger as Test.Logger) as Lang.Boolean {
    var previousMarker = Storage.getValue("localFreeWorkoutV1");
    var previousSnapshot = GymLocalWorkout.snapshot;
    var previousReadFailed = GymLocalWorkout.readFailed;
    var previousTimeline = GymStore.timelineBase;
    var previousMode = GymWorkoutMode.state;

    Storage.setValue("localFreeWorkoutV1",
        [1, 0, 1700000000, [300, 24.5, 20, 1200, 10, 140, 125, 2]]);
    GymLocalWorkout.snapshot = null;
    GymLocalWorkout.readFailed = false;
    GymStore.timelineBase = null;
    GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
    GymLocalWorkout.restore();

    var stored = Storage.getValue("localFreeWorkoutV1");
    var markerRetained = stored instanceof Lang.Array && stored.size() == 4 &&
        stored[3] instanceof Lang.Array && stored[3][0] == 300;
    var valid = GymLocalWorkout.snapshot == null && !GymLocalWorkout.readFailed &&
        !GymLocalWorkout.needsDecision() && !GymLocalWorkout.blocksPairing() &&
        !GymLocalWorkout.finish() && GymStore.timelineBase == null &&
        GymWorkoutMode.state == GymWorkoutMode.MODE_IDLE && markerRetained;

    if (previousMarker == null) {
        Storage.deleteValue("localFreeWorkoutV1");
    } else {
        Storage.setValue("localFreeWorkoutV1", previousMarker);
    }
    GymLocalWorkout.snapshot = previousSnapshot;
    GymLocalWorkout.readFailed = previousReadFailed;
    GymStore.timelineBase = previousTimeline;
    GymWorkoutMode.state = previousMode;
    return valid;
}

(:test, :fr55Memory)
function fr55RecoveryStubsPreserveFitAndQueues(logger as Test.Logger) as Lang.Boolean {
    var previousMarker = Storage.getValue("localFreeWorkoutV1");
    var previousSnapshot = GymLocalWorkout.snapshot;
    var previousReadFailed = GymLocalWorkout.readFailed;
    var previousPlan = GymStore.plan;
    var previousPending = GymStore.pending;
    var previousFitSaved = GymSession.fitSaved;
    var marker = [1, 0, 1700000000, [300, 24.5, 20, 1200, 10, 140, 125, 2]];
    var testPlan = [["fr55-plan-sentinel"]];
    var testPending = [{"id" => "fr55-pending-sentinel"}];

    Storage.setValue("localFreeWorkoutV1", marker);
    GymLocalWorkout.snapshot = null;
    GymLocalWorkout.readFailed = false;
    GymStore.plan = testPlan;
    GymStore.pending = testPending;
    GymSession.fitSaved = false;

    var checkpointed = GymLocalWorkout.checkpoint(true);
    var cleared = GymLocalWorkout.clear();
    var stored = Storage.getValue("localFreeWorkoutV1");
    var markerRetained = stored instanceof Lang.Array && stored.size() == 4 &&
        stored[3] instanceof Lang.Array && stored[3][0] == 300;
    var valid = checkpointed && cleared && GymLocalWorkout.snapshot == null &&
        !GymLocalWorkout.readFailed && !GymSession.fitSaved &&
        GymStore.plan == testPlan && GymStore.pending == testPending && markerRetained;

    if (previousMarker == null) {
        Storage.deleteValue("localFreeWorkoutV1");
    } else {
        Storage.setValue("localFreeWorkoutV1", previousMarker);
    }
    GymLocalWorkout.snapshot = previousSnapshot;
    GymLocalWorkout.readFailed = previousReadFailed;
    GymStore.plan = previousPlan;
    GymStore.pending = previousPending;
    GymSession.fitSaved = previousFitSaved;
    return valid;
}
