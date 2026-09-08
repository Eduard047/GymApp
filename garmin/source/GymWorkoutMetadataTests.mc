using Toybox.Test as Test;
using Toybox.Lang as Lang;
using Toybox.Application.Storage as Storage;

(:test)
function checkpointMetadataKeepsExactMetricsAndPlanProgress(logger as Test.Logger) as Lang.Boolean {
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var cp = [60, 2.123456789d, 3, 360, 3, 140, 120, 1];
    var context = ["metadata-request", owner, "metadata-device", null, 1700000000, false, cp, 1, 1, 2];
    var value = GymStore.expandWorkoutMetadata(context);
    return value != null && value["startedAtSeconds"] == 1700000000 &&
        value["durationSeconds"] == 60 && value["gymCalories"] == 2.123456789d &&
        value["garminCalories"] == 3 && value["avgHeartRate"] == 120 &&
        value["maxHeartRate"] == 140 && value["lastHeartRate"] == 120 &&
        value["heartRateZone"] == 1 && value["plannedSetCount"] == 2 &&
        value["plannedTargetSetCount"] == 1 && value["completedPlannedSetCount"] == 1 &&
        !value.hasKey("pairingGeneration") && !value.hasKey("sets") &&
        GymStore.isValidWorkoutMetadata(value, 2);
}

(:test)
function freeCheckpointMetadataOmitsUnavailableOptionalFields(logger as Test.Logger) as Lang.Boolean {
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var context = ["free-metadata-request", owner, "metadata-device", null, 1700000000, true,
        [60, 2.0, null, 0, 0, 0, null, 0], 0, 0, 0];
    var value = GymStore.expandWorkoutMetadata(context);
    return value != null && GymStore.isValidWorkoutMetadata(value, 0) &&
        value["workoutMode"].equals("free") && !value.hasKey("avgHeartRate") &&
        !value.hasKey("lastHeartRate") && !value.hasKey("maxHeartRate") &&
        !value.hasKey("garminCalories") && !value.hasKey("plannedSetCount") &&
        !value.hasKey("plannedTargetSetCount") && !value.hasKey("completedPlannedSetCount");
}

(:test)
function malformedCheckpointMetadataCannotExpand(logger as Test.Logger) as Lang.Boolean {
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var context = ["metadata-request", owner, "metadata-device", null, 1700000000, false,
        [60, 2.0, null, 0, 0, 0, null, 0], 1, 1, 2];
    var invalid = [null, [], context.slice(0, 9)];
    for (var i = 0; i < invalid.size(); i += 1) {
        if (GymStore.expandWorkoutMetadata(invalid[i]) != null) { return false; }
    }
    var modes = [null, "false", 1];
    for (var i = 0; i < modes.size(); i += 1) {
        var copy = context.slice(null, null); copy[5] = modes[i];
        if (GymStore.expandWorkoutMetadata(copy) != null) { return false; }
    }
    for (var index = 7; index <= 9; index += 1) {
        var copy = context.slice(null, null); copy[index] = 61;
        if (GymStore.expandWorkoutMetadata(copy) != null) { return false; }
    }
    var copy = context.slice(null, null); copy[6] = [1, 2];
    if (GymStore.expandWorkoutMetadata(copy) != null) { return false; }
    copy = context.slice(null, null); copy[3] = "not-a-binding";
    return GymStore.expandWorkoutMetadata(copy) == null;
}

(:test, :compactLegacyState)
function queuedCheckpointMetadataSurvivesRestartAndRejectsAnotherHeader(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare()) { return false; }
    var entry = PendingJournalFixture.entry();
    var header = entry[1];
    entry[0] = ["pending-journal-request-001", header[1], header[2], header[3], header[4], false, header[9], 0, 0, header[5]];
    if (!GymPendingJournal.validEntry(entry)) { return false; }
    Storage.setValue("pendingJournalV1", [2, [entry]]);
    GymPendingJournal.reset();
    if (!GymPendingJournal.load()) { return false; }
    var frame = GymPendingJournal.frame(0, "checkpoint-attempt");
    if (frame == null || frame["metadata"]["durationSeconds"] != 60 ||
        frame["set"]["weight"] != 52.123456789d) { return false; }
    entry = PendingJournalFixture.entry();
    entry[0][9] = 1;
    if (GymPendingJournal.validEntry(entry)) { return false; }
    entry[0][9] = 2;
    entry[0][1] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    return !GymPendingJournal.validEntry(entry);
}

(:test, :compactLegacyState)
function queueContextValidationMatchesPhoneMetadataContract(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "metadata-parity-device";
    var modes = [false, true];
    var checkpoints = [null, [0, 0.0, null, 0, 0, 0, null, 0],
        [60, 12.123456789d, 10, 1300, 10, 160, 150, 3]];
    for (var mode = 0; mode < 2; mode += 1) {
        for (var c = 0; c < checkpoints.size(); c += 1) {
            for (var count = 0; count <= 2; count += 1) {
                for (var target = 0; target <= 2; target += 1) {
                    for (var completed = 0; completed <= 2; completed += 1) {
                        var context = ["context-parity-request", GymStore.accountBinding,
                            GymStore.deviceBinding, null, 1700000000, modes[mode],
                            checkpoints[c], target, completed, count];
                        var header = [6, GymStore.accountBinding, GymStore.deviceBinding,
                            null, 1700000000, count, 0, 1, 1, checkpoints[c]];
                        var metadata = GymStore.expandWorkoutMetadata(context);
                        var expected = GymActiveJournal.validHeader(header) &&
                            GymStore.isValidWorkoutMetadata(metadata, count);
                        if (GymPendingJournal.validEntry([context, header, 0]) != expected) {
                            logger.debug("Context and phone metadata validity differ");
                            return false;
                        }
                    }
                }
            }
        }
    }
    GymStore.clearAccountScopedState();
    return true;
}
