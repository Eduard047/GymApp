using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.Test as Test;

(:test, :compactLegacyState)
function activeJournalKeepsCommittedPrefixAcrossInterruptedAppend(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "row-journal-test";
    GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    var first = GymStore.restoredSet("Bench Press", 52.5, 8,
        [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0]);
    var second = GymStore.restoredSet("Bench Press", 55.0, 9,
        [30, 60, 2.0, 1, 0, 0, 0, 0, 0, 0]);
    var checkpoint = [60, 3.0, 1, 0, 0, 0, null, 0];
    if (!GymStore.persistActiveWorkoutSnapshot([first, second], 1700000000, checkpoint)) {
        return false;
    }
    var old = Storage.getValue("activeWorkoutV1");
    // A row written before the header commit is not part of the saved workout.
    Storage.setValue(GymActiveJournal.key(old[6], 2),
        [old[7], 0, 99.0, 10, [60, 90, 1.0, null, 0, 0, 0, 0, 0, 0], old[8] + 1]);
    GymStore.resetActiveWorkoutSnapshotState();
    if (!GymStore.isValidActiveWorkoutSnapshot(old)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(old);
    if (GymStore.sets.size() != 2 || GymStore.setField(GymSetAccess.at(GymStore.sets, 1), "weight") != 55.0) {
        return false;
    }
    var oldSecond = GymSetAccess.at(GymStore.sets, 1);
    // Undo commits the lower count; a later append replaces only the now-unreferenced row.
    if (!GymStore.persistActiveWorkoutSnapshot(GymStore.sets.slice(0, 1),
        1700000000, checkpoint)) { return false; }
    var undo = Storage.getValue("activeWorkoutV1");
    if (undo[6] != old[6] || undo[5] != 1 ||
        !GymStore.isValidActiveWorkoutSnapshot(undo)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(undo);
    if (GymStore.sets.size() != 1 || GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "weight") != 52.5 ||
        GymStore.setField(oldSecond, "weight") != null) { return false; }
    var replacement = GymStore.sets.slice(null, null);
    replacement.add(GymStore.restoredSet("Bench Press", 80.0, 9,
        [30, 60, 2.0, 1, 0, 0, 0, 0, 0, 0]));
    if (!GymStore.persistActiveWorkoutSnapshot(replacement, 1700000000, checkpoint) ||
        GymStore.setField(GymSetAccess.at(replacement, 1), "weight") != 80.0 ||
        GymStore.setField(oldSecond, "weight") != null ||
        GymStore.isValidSetList(replacement, 60, false)) { return false; }
    var interval = GymStore.setField(GymSetAccess.at(replacement, 1), "setInterval");
    interval[2] = 999.0;
    if (GymStore.setField(GymSetAccess.at(replacement, 1), "setInterval")[2] != 2.0) { return false; }
    var serializable = false;
    try { Storage.setValue("journal-reference-boundary-test", GymSetAccess.at(replacement, 1)); serializable = true; }
    catch (e) { }
    if (serializable) { Storage.deleteValue("journal-reference-boundary-test"); }
    return !serializable;
}

(:test, :compactLegacyState)
function activeJournalRejectsMissingWrongEpochAndMalformedRows(logger as Test.Logger) as Lang.Boolean {
    var owner = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.accountBinding = owner; GymStore.stateOwnerBinding = owner;
    GymStore.deviceBinding = "row-journal-test"; GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"];
    var header = [6, owner, "row-journal-test", null, 1700000000,
        1, 1, 123, 1, [30, 1.0, null, 0, 0, 0, null, 0]];
    var key = GymActiveJournal.key(1, 0);
    Storage.deleteValue(key);
    if (GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    var row = [122, 0, 52.123456789d, 8, [0, 30, 0.123456789d, null, 0, 0, 0, 0, 0, 0], 1];
    Storage.setValue(key, row);
    if (GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    row[0] = 123;
    Storage.setValue(key, row);
    if (!GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(header);
    if (GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "weight") != 52.123456789d ||
        GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "setInterval")[2] != 0.123456789d) { return false; }
    row[4][1] = 31;
    Storage.setValue(key, row);
    if (GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    row[4][1] = 30; row[3] = 0;
    Storage.setValue(key, row);
    if (GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    header[6] = 2;
    return !GymStore.isValidActiveWorkoutSnapshot(header);
}

(:test, :compactLegacyState)
function activeJournalReplacementCannotOverwritePreviousBankBeforeCommit(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "row-journal-test";
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    var checkpoint = [30, 1.0, null, 0, 0, 0, null, 0];
    var item = GymStore.restoredSet("Bench Press", 50.0, 8,
        [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0]);
    if (!GymStore.persistActiveWorkoutSnapshot([item], 1700000000, checkpoint)) { return false; }
    var old = Storage.getValue("activeWorkoutV1");
    // Simulate a replacement interrupted before its header became durable.
    Storage.setValue(GymActiveJournal.key(1 - old[6], 0),
        [old[7] + 1, 0, 90.0, 12, [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0], 1]);
    GymActiveJournal.reset();
    if (!GymStore.isValidActiveWorkoutSnapshot(old)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(old);
    if (GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "weight") != 50.0) { return false; }
    item = GymStore.restoredSet("Bench Press", 90.0, 12,
        [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0]);
    if (!GymStore.persistActiveWorkoutSnapshot([item], 1700000000, checkpoint)) { return false; }
    var replaced = Storage.getValue("activeWorkoutV1");
    if (replaced[6] == old[6] || replaced[7] == old[7] ||
        !GymStore.isValidActiveWorkoutSnapshot(replaced)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(replaced);
    return GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "weight") == 90.0;
}

(:test, :compactLegacyState, :richWorkoutMode)
function journalUndoRestoresRemovedExerciseAndExactPickerAcrossReload(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "journal-undo-test";
    GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press", "Squat"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    GymSession.recording = false; GymSession.elapsedSeconds = 0;
    GymSession.gymCalories = 0.0; GymSession.garminCalories = null;
    GymSession.hrSamples = 0; GymSession.setBoostCalories = 0.0;
    var origin = Toybox.Time.now().value() - 60;
    var checkpoint = [60, 3.0, null, 0, 0, 0, null, 0];
    var items = [
        GymStore.restoredSet("Bench Press", 50.0, 8, [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0]),
        GymStore.restoredSet("Squat", 82.123456789d, 9, [30, 60, 2.0, null, 0, 0, 0, 0, 0, 0])
    ];
    if (!GymStore.persistActiveWorkoutSnapshot(items, origin, checkpoint)) { return false; }
    var header = Storage.getValue("activeWorkoutV1");
    if (!GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(header);
    GymStore.clearTransientSetActions();
    GymStore.lastSetUndoStartedAt = Toybox.System.getTimer();
    if (!GymStore.undoLastSet() || GymStore.sets.size() != 1 ||
        !GymStore.currentExercise().equals("Squat") ||
        GymStore.weight != 82.123456789d || GymStore.reps != 9) { return false; }
    header = Storage.getValue("activeWorkoutV1");
    if (Storage.getValue(GymActiveJournal.key(header[6], 1)) != null ||
        Storage.getValue(GymActiveJournal.key(header[6], 0)) == null) { return false; }
    var entry = Storage.getValue("currentEntryV1");
    GymStore.resetActiveWorkoutSnapshotState();
    if (!GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(header);
    GymStore.exerciseIndex = 0; GymStore.weight = 1.0; GymStore.reps = 1;
    GymStore.restoreCurrentEntry(entry);
    return GymStore.sets.size() == 1 && GymStore.currentExercise().equals("Squat") &&
        GymStore.weight instanceof Lang.Double && GymStore.weight == 82.123456789d &&
        GymStore.reps == 9 &&
        GymStore.setField(GymSetAccess.at(GymStore.sets, 0), "weight") == 50.0;
}

(:test, :compactLegacyState)
function journalHandlesRequireExactHeaderAndRejectUncommittedRowRevision(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "journal-handle-test"; GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"]; GymStore.exerciseCatalogNeedsWrite = true;
    var checkpoint = [30, 1.0, null, 0, 0, 0, null, 0];
    var item = GymStore.restoredSet("Bench Press", 50.0, 8,
        [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0]);
    if (!GymStore.persistActiveWorkoutSnapshot([item], 1700000000, checkpoint)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(Storage.getValue("activeWorkoutV1"));
    var handle = GymSetAccess.at(GymStore.sets, 0);
    if (GymStore.setField(handle, "weight") != 50.0 || GymStore.sets.data.size() != GymWorkoutMode.recordingSetLimit) { return false; }
    // An ordinary checkpoint changes the published header without rewriting
    // the immutable row. Newly issued handles still read the older valid row.
    if (!GymStore.persistActiveWorkoutSnapshot(GymStore.sets.slice(null, null),
        1700000000, checkpoint)) { return false; }
    GymStore.sets = GymSetAccess.committed(GymStore.sets);
    if (GymStore.setField(handle, "weight") != null ||
        GymStore.setField(handle, "exerciseName") != null) { return false; }
    var current = GymSetAccess.at(GymStore.sets, 0);
    if (GymStore.setField(current, "weight") != 50.0) { return false; }
    var header = GymActiveJournal.snapshot();
    var key = GymActiveJournal.key(header[6], 0);
    var oldRow = Storage.getValue(key);
    var futureRow = oldRow.slice(null, null); futureRow[5] = header[8] + 1;
    Storage.setValue(key, futureRow); GymActiveJournal.releaseReadCache();
    var rejected = GymStore.setField(current, "weight") == null;
    Storage.setValue(key, oldRow); GymActiveJournal.releaseReadCache();
    return rejected && GymStore.setField(current, "weight") == 50.0;
}

(:test, :compactLegacyState)
function journalDirectorySharesOnlyItsImmutablePrefix(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "directory-test"; GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press", "Squat"]; GymStore.exerciseCatalogNeedsWrite = true;
    var checkpoint = [60, 2.0, null, 0, 0, 0, null, 0];
    var items = [
        GymStore.restoredSet("Bench Press", 50.0, 8, [0, 30, 1.0, null, 0, 0, 0, 0, 0, 0]),
        GymStore.restoredSet("Squat", 60.0, 8, [30, 60, 1.0, null, 0, 0, 0, 0, 0, 0])
    ];
    if (!GymStore.persistActiveWorkoutSnapshot(items, 1700000000, checkpoint)) { return false; }
    GymStore.sets = GymSetAccess.committed(items);
    var original = GymStore.sets.data;
    if (!GymStore.persistActiveWorkoutSnapshot(GymStore.sets, 1700000000, checkpoint) ||
        GymStore.sets.data != original) { return false; }
    var append = GymStore.sets.slice(null, null);
    append.add(GymStore.restoredSet("Bench Press", 55.0, 9,
        [60, 90, 1.0, null, 0, 0, 0, 0, 0, 0]));
    if (!GymStore.persistActiveWorkoutSnapshot(append, 1700000000,
        [90, 3.0, null, 0, 0, 0, null, 0]) || append.data != original ||
        GymStore.setField(GymSetAccess.at(append, 2), "weight") != 55.0) { return false; }
    var bank = GymActiveJournal.snapshot()[6];
    var replacement = append.slice(0, 1);
    replacement.add(GymStore.restoredSet("Squat", 75.0, 10,
        [30, 60, 1.0, null, 0, 0, 0, 0, 0, 0]));
    if (!GymStore.persistActiveWorkoutSnapshot(replacement, 1700000000, checkpoint) ||
        replacement.data == original || GymActiveJournal.snapshot()[6] == bank) { return false; }
    return GymStore.setField(GymSetAccess.at(replacement, 0), "weight") == 50.0 &&
        GymStore.setField(GymSetAccess.at(replacement, 1), "weight") == 75.0;
}

(:test, :compactLegacyState)
function recordingCapacityCommitsThirtyAndRejectsOverflow(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "capacity-test"; GymStore.pairingGeneration = null;
    GymStore.exercises = ["Bench Press"]; GymStore.exerciseCatalogNeedsWrite = true;
    GymStore.plan = [{"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8}];
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    var capacity = GymStore.maxNewWorkoutSets;
    if (GymActiveJournal.allocateRows(1).size() != capacity ||
        GymActiveJournal.allocateRows(0).size() != 0 ||
        GymActiveJournal.allocateRows(60).size() != 60) { return false; }
    var items = [];
    for (var i = 0; i < capacity; i += 1) {
        items.add(GymStore.restoredSet("Bench Press", 50.0 + i, 8, null));
    }
    // The final permitted set must commit before the next one is refused.
    if (!GymStore.persistActiveWorkoutSnapshot(items.slice(0, capacity - 1), null, null)) { return false; }
    var header = Storage.getValue("activeWorkoutV1");
    if (!GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(header);
    GymStore.exerciseIndex = 0; GymStore.weight = 82.5; GymStore.reps = 9;
    GymSession.recording = false; GymSession.startedAt = 0;
    GymSession.elapsedSeconds = 0; GymSession.gymCalories = 0.0;
    GymSession.setBoostCalories = 0.0; GymSession.garminCalories = null;
    if (!GymStore.addSet() || GymStore.sets.size() != capacity ||
        GymStore.setField(GymSetAccess.at(GymStore.sets, capacity - 1), "weight") != 82.5) {
        logger.debug("Final permitted set failed: " + GymStatus.text(GymStore.status));
        return false;
    }
    // At the new limit, rejection must happen before any journal write.
    header = Storage.getValue("activeWorkoutV1");
    if (!GymStore.isValidActiveWorkoutSnapshot(header)) { return false; }
    GymStore.restoreActiveWorkoutSnapshot(header);
    var before = GymStore.sets;
    return !GymStore.addSet() && (GymStore.status == GymStatus.SET_LIMIT) &&
        GymStore.sets == before && Storage.getValue("activeWorkoutV1")[5] == capacity;
}
