using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.Test as Test;

(:test, :compactLegacyState)
class PendingJournalFixture {
static function entry() {
    var index = Storage.getValue("pendingJournalV1");
    return index[0] == 3 ? Storage.getValue("queueEntry" + index[1] + "-" + index[2][0]) : index[1][0];
}

static function prepare() { return prepareCount(2); }

static function prepareCount(count) { return prepareWithLegacy(count, 0); }

static function prepareWithLegacy(count, legacyCount) {
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "pending-journal-test";
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    for (var l = 0; l < legacyCount; l += 1) {
        var legacySets = [];
        for (var n = 0; n <= l; n += 1) {
            legacySets.add({"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8});
        }
        GymStore.pending.add({"type" => "create_workout", "bindingVersion" => 2,
            "requestId" => "reserved-legacy-" + l.toString(), "workoutMode" => "planned",
            "accountBinding" => GymStore.accountBinding, "deviceBinding" => GymStore.deviceBinding,
            "startedAtSeconds" => 1699990000 + l, "sets" => legacySets});
    }
    var checkpoint = [count * 30, count.toFloat(), null, 0, 0, 0, null, 0];
    var next = [];
    for (var i = 0; i < count; i += 1) {
        next.add(GymStore.restoredSet("Bench Press", i == 0 ? 52.123456789d : 55.0,
            i == 0 ? 8 : 9, [i * 30, (i + 1) * 30, 1.0, null, 0, 0, 0, 0, 0, 0]));
    }
    if (!GymStore.persistActiveWorkoutSnapshot(next, 1700000000, checkpoint)) { return false; }
    GymStore.sets = next;
    GymStore.activeWorkoutStartedAtSeconds = 1700000000;
    GymStore.timelineBase = checkpoint;
    GymStore.preparedWorkout = [2, GymStore.accountBinding, GymStore.deviceBinding, null,
        "pending-journal-request-001", 1, false];
    var metadata = {"type" => "create_workout", "bindingVersion" => 2,
        "workoutMode" => "planned", "requestId" => "pending-journal-request-001",
        "accountBinding" => GymStore.accountBinding, "deviceBinding" => GymStore.deviceBinding,
        "startedAtSeconds" => 1700000000, "durationSeconds" => count * 30, "gymCalories" => count.toFloat()};
    if (legacyCount > 0) {
        metadata = ["pending-journal-request-001", GymStore.accountBinding, GymStore.deviceBinding,
            null, 1700000000, false, checkpoint, 0, 0, count];
    }
    if (GymPendingJournal.begin(metadata) != 0) { return false; }
    if (GymPendingJournal.advance() != 0 || GymPendingJournal.entries.size() != 0) { return false; }
    if (Storage.getValue("pendingJournalV1") != null) { return false; }
    for (var row = 1; row < count; row += 1) {
        if (GymPendingJournal.advance() != 0) { return false; }
    }
    if (GymPendingJournal.advance() != 1) { return false; }
    return true;
}

}

(:test, :compactLegacyState)
function pendingJournalPinsOriginalRowsAndNamesAcrossNewWorkout(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare()) { return false; }
    var bank = PendingJournalFixture.entry()[1][6];
    if (!GymStore.persistEmptyActiveWorkoutSnapshot() || Storage.getValue("activeWorkoutV1")[6] == bank) { return false; }
    GymStore.exercises = ["Squat"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymPendingJournal.reset();
    if (!GymPendingJournal.load()) { return false; }
    var first = GymPendingJournal.frame(0, "pending-test-attempt-001");
    var last = GymPendingJournal.frame(1, "pending-test-attempt-002");
    if (first == null || last == null || !first["set"]["exerciseName"].equals("Bench Press") ||
        first["set"]["weight"] != 52.123456789d ||
        last["set"]["reps"] != 9 ||
        last["interval"][0] != 30) { return false; }
    GymStore.accountBinding = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    return GymPendingJournal.frame(0, "pending-test-attempt-001") == null;
}

(:test, :compactLegacyState)
function pendingJournalRejectsInterruptedMissingRowsAndStalePreparation(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare()) { return false; }
    GymStore.accountBinding = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    // Retained queue belongs to the previous owner; it may not load under this one.
    if (GymPendingJournal.load() || GymPendingJournal.readable) { return false; }
    if (GymPendingJournal.availableBank(-1) != -1) { return false; }
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    if (!GymPendingJournal.load()) { return false; }
    var bank = PendingJournalFixture.entry()[1][6];
    Storage.deleteValue(GymActiveJournal.key(bank, 1));
    if (GymPendingJournal.load() || GymPendingJournal.entries.size() != 0) { return false; }
    GymStore.clearAccountScopedState();
    return GymPendingJournal.entries.size() == 0 && GymPendingJournal.readable;
}

(:test, :compactLegacyState)
function pendingJournalRecoversCommittedQueueBeforeWholeWorkoutAck(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.save()) { return false; }
    var request = "pending-journal-request-001";
    var bank = PendingJournalFixture.entry()[1][6];
    // Simulate a process restart after index commit but before active cleanup.
    GymStore.load();
    if (GymStore.sets.size() != 0 || GymStore.hasPreparedWorkout() ||
        GymStore.pendingCount() != 1 || !GymPendingJournal.contains(request)) { return false; }
    if (GymStore.removePendingByRequestId("another-workout-request") ||
        !GymPendingJournal.contains(request)) { return false; }
    if (!GymStore.removePendingByRequestId(request) || GymStore.pendingCount() != 0 ||
        Storage.getValue(GymActiveJournal.key(bank, 0)) != null ||
        Storage.getValue(GymPendingJournal.nameKey(bank, 0)) != null) { return false; }
    GymStore.load();
    return GymStore.pendingCount() == 0 && GymStore.sets.size() == 0 &&
        !GymStore.removePendingByRequestId(request);
}

(:test, :compactLegacyState)
function pendingJournalRotatesOnlyTheCurrentOwnerAndExactGeneration(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var next = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var wrong = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    GymStore.pairingGeneration = next;
    if (GymPendingJournal.rotate(wrong, next) ||
        !GymPendingJournal.rotate(null, next) || !GymPendingJournal.save()) { return false; }
    GymPendingJournal.reset();
    if (!GymPendingJournal.load()) { return false; }
    var message = GymPendingJournal.frame(0, "pending-test-attempt-001");
    if (message == null || !message["metadata"]["pairingGeneration"].equals(next) ||
        message["set"]["weight"] != 52.123456789d) { return false; }
    GymStore.pairingGeneration = wrong;
    if (GymPendingJournal.load() || GymPendingJournal.availableBank(-1) != -1) { return false; }
    GymStore.pairingGeneration = next;
    if (!GymPendingJournal.load()) { return false; }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState)
function pendingJournalPartialAckNeverDeletesAndRejectsStaleAttempt(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var first = GymPendingJournal.nextMessage();
    if (first == null || first["offset"] != 0) { return false; }
    var ack = {"type" => "workout_part_ack", "transferVersion" => 1,
        "requestId" => "pending-journal-request-001", "attemptId" => first["attemptId"],
        "nextOffset" => 1, "bindingVersion" => 2,
        "accountBinding" => GymStore.accountBinding, "deviceBinding" => GymStore.deviceBinding,
        "pairingGeneration" => GymStore.pairingGeneration};
    ack["transferVersion"] = 1.0;
    if (GymPendingJournal.acknowledgePart(ack)) { return false; }
    ack["transferVersion"] = 1;
    if (!GymPendingJournal.acknowledgePart(ack) || GymStore.pendingCount() != 1 ||
        GymPendingJournal.acknowledgePart(ack)) { return false; }
    var second = GymPendingJournal.nextMessage();
    if (second == null || second["offset"] != 1 ||
        first["attemptId"].equals(second["attemptId"]) ||
        GymPendingJournal.acknowledgePart(ack)) { return false; }
    ack["attemptId"] = second["attemptId"]; ack["nextOffset"] = 2;
    if (GymPendingJournal.acknowledgePart(ack) || GymStore.pendingCount() != 1) { return false; }
    GymPendingJournal.reset();
    if (!GymPendingJournal.load() || GymPendingJournal.nextMessage()["offset"] != 1) { return false; }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState, :richWorkoutMode)
function legacyPendingParkingPreservesDiskAndOrderingAcrossRestart(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare()) { return false; }
    var legacyId = "legacy-workout-request-001";
    GymStore.pending = [{"type" => "create_workout", "bindingVersion" => 2,
        "requestId" => legacyId, "workoutMode" => "planned", "startedAtSeconds" => 1700000000,
        "accountBinding" => GymStore.accountBinding, "deviceBinding" => GymStore.deviceBinding,
        "sets" => [{"exerciseName" => "Bench Press", "weight" => 73.123456789d, "reps" => 7}]}];
    GymStore.clearPreparedWorkout("pending-journal-request-001");
    var rows = [];
    for (var i = 0; i < 15; i += 1) {
        rows.add(GymStore.restoredSet("Bench Press", 50.0, 8,
            [i * 30, (i + 1) * 30, 1.0, null, 0, 0, 0, 0, 0, 0]));
    }
    var checkpoint = [450, 15.0, null, 0, 0, 0, null, 0];
    if (!GymStore.persistActiveWorkoutSnapshot(rows, 1700000100, checkpoint)) { return false; }
    GymStore.sets = rows; GymStore.activeWorkoutStartedAtSeconds = 1700000100;
    GymStore.timelineBase = checkpoint;
    if (!GymStore.save()) { return false; }
    GymStore.parkPendingDuringLongWorkout(GymStore.sets.size());
    if (GymStore.pending.size() != 0 || GymStore.pendingCount() != 2 ||
        GymStore.restorePendingForMutation() || !GymStore.save()) { return false; }
    GymStore.load();
    if (GymStore.sets.size() != 15 || GymStore.pendingCount() != 2 || GymStore.pending.size() != 0 ||
        ((Storage.getValue("pending")[0] as Lang.Dictionary)["sets"][0] as Lang.Dictionary)["weight"] != 73.123456789d) { return false; }
    if (!GymStore.clearActiveWorkout()) { return false; }
    var connected = GymComm.isPhoneConnected();
    var available = GymStore.pendingMessage();
    if (connected ? (available == null || !available["requestId"].equals(legacyId)) :
        (available != null || GymStore.pending.size() != 0)) { return false; }
    if (!GymStore.restorePendingForMutation() ||
        !(GymStore.pending[0] as Lang.Dictionary)["requestId"].equals(legacyId) ||
        ((GymStore.pending[0] as Lang.Dictionary)["sets"][0] as Lang.Dictionary)["weight"] != 73.123456789d) { return false; }
    // FR55 parks the legacy queue at idle too; larger profiles retain it.
    GymStore.parkPendingDuringLongWorkout(0);
    var idleSize = GymWorkoutMode.recordingSetLimit == 30 ? 0 : 1;
    if (GymStore.pending.size() != idleSize || !GymStore.save()) { return false; }
    GymStore.load();
    if (GymStore.sets.size() != 0 || GymStore.pending.size() != idleSize ||
        GymStore.pendingCount() != 2 || !GymStore.restorePendingForMutation()) { return false; }
    if (!GymStore.removePendingByRequestId(legacyId) || GymStore.pendingCount() != 1 ||
        !GymPendingJournal.contains("pending-journal-request-001")) { return false; }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState)
function longQueuedBankIsNotChargedTwiceWhenClearingActiveWorkout(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepareCount(30)) { return false; }
    var queuedBank = PendingJournalFixture.entry()[1][6];
    if (!GymStore.persistEmptyActiveWorkoutSnapshot() ||
        Storage.getValue("activeWorkoutV1")[5] != 0 ||
        Storage.getValue("activeWorkoutV1")[6] == queuedBank ||
        !GymPendingJournal.pins(queuedBank)) { return false; }
    GymStore.sets = [];
    GymStore.activeWorkoutStartedAtSeconds = null;
    GymStore.preparedWorkout = null;
    GymPendingJournal.reset();
    return GymPendingJournal.load() && GymPendingJournal.entries.size() == 1 &&
        PendingJournalFixture.entry()[1][5] == 30 &&
        GymPendingJournal.row(PendingJournalFixture.entry(), 0)[1] == 52.123456789d &&
        GymPendingJournal.row(PendingJournalFixture.entry(), 29)[2] == 9;
}

(:test, :compactLegacyState)
function queueIndexSwitchKeepsPreviousEntriesUntilCommit(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare()) { return false; }
    var committed = Storage.getValue("pendingJournalV1");
    if (committed[0] != 3 || committed[2].size() != 1) { return false; }
    var bank = committed[2][0];
    var inactiveSlot = 1 - committed[1];
    var key = "queueEntry" + inactiveSlot.toString() + "-" + bank.toString();
    Storage.setValue(key, [null, null, null]);
    GymPendingJournal.reset();
    if (!GymPendingJournal.load() ||
        !GymPendingJournal.contains("pending-journal-request-001")) { return false; }
    Storage.setValue("pendingJournalV1", [3, inactiveSlot, [bank]]);
    GymPendingJournal.reset();
    if (GymPendingJournal.load() || GymPendingJournal.readable ||
        GymPendingJournal.entries.size() != 0) { return false; }
    Storage.setValue("pendingJournalV1", committed);
    GymPendingJournal.reset();
    var ok = GymPendingJournal.load() &&
        GymPendingJournal.frame(0, "committed-slot")["set"]["weight"] == 52.123456789d;
    GymStore.clearAccountScopedState();
    return ok;
}

(:test, :compactLegacyState)
function olderQueueAckKeepsANewerPreparedWorkout(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var nextOrigin = 1700000500;
    var checkpoint = [10, 1.0, null, 0, 0, 0, null, 0];
    if (!GymStore.persistActiveWorkoutSnapshot([], nextOrigin, checkpoint)) { return false; }
    GymStore.sets = []; GymStore.activeWorkoutStartedAtSeconds = nextOrigin;
    GymStore.timelineBase = checkpoint;
    GymStore.preparedWorkout = [2, GymStore.accountBinding, GymStore.deviceBinding, null,
        "newer-prepared-workout", 1, true];
    Storage.setValue("preparedWorkoutV1", GymStore.preparedWorkout);
    if (!GymStore.removePendingByRequestId("pending-journal-request-001") ||
        GymStore.pendingCount() != 0 || !GymStore.hasPreparedWorkout() ||
        !GymStore.preparedWorkout[4].equals("newer-prepared-workout") ||
        Storage.getValue("activeWorkoutV1")[4] != nextOrigin) { return false; }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState)
function parkedLegacyQueueStillCountsTowardEightWorkoutLimit(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var committed = Storage.getValue("pendingJournalV1");
    GymStore.pending = [];
    for (var i = 0; i < 8; i += 1) {
        GymStore.pending.add({"type" => "create_workout", "bindingVersion" => 2,
            "requestId" => "legacy-limit-" + i.toString(), "workoutMode" => "planned",
            "startedAtSeconds" => 1700000000 + i,
            "accountBinding" => GymStore.accountBinding, "deviceBinding" => GymStore.deviceBinding,
            "sets" => [{"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8}]});
    }
    GymStore.parkPendingDuringLongWorkout(30);
    if (GymStore.pending.size() != 0 || GymStore.pendingCount() != 9) { return false; }
    GymPendingJournal.reset();
    var ok = !GymPendingJournal.load() && !GymPendingJournal.readable &&
        GymPendingJournal.entries.size() == 0 &&
        Storage.getValue("pendingJournalV1")[1] == committed[1];
    GymStore.clearAccountScopedState();
    return ok;
}

(:test, :compactLegacyState)
function compactSyncStageRejectsUnsupportedSourceWithoutWriting(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    var message = {"requestId" => "ignored-cloud-stage"};
    if (GymStore.stageSync(message, "cloud") ||
        GymStore.isExactStagedSync(message, "cloud") ||
        GymStore.syncMessagesEqual(message, message, "cloud") ||
        GymStore.syncRevisionStatus(message, "cloud") != -1 ||
        Storage.getValue("phoneSyncStage") != null ||
        Storage.getValue("cloudSyncStage") != null) { return false; }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState, :richWorkoutMode)
function admittedWorkoutKeepsRoomForItsQueueAndEmptyCommit(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepareWithLegacy(60, 2) || !GymStore.recoverQueuedWorkout()) { return false; }
    if (GymStore.pendingCount() != 3) { return false; }
    var checkpoint = [5, 0.119, null, 0, 0, 0, null, 0];
    var accepted = GymStore.persistActiveWorkoutSnapshot([], 1700003000, checkpoint);
    if (!accepted) {
        var prior = Storage.getValue("activeWorkoutV1");
        var kept = (GymStore.status == GymStatus.STORE_FULL) && prior[4] == null &&
            prior[5] == 0 && GymStore.pendingCount() == 3;
        GymStore.clearAccountScopedState();
        return kept;
    }
    GymStore.activeWorkoutStartedAtSeconds = 1700003000;
    GymStore.timelineBase = checkpoint;
    GymStore.sets = [];
    GymStore.preparedWorkout = [2, GymStore.accountBinding, GymStore.deviceBinding,
        null, "reserved-free-workout", 1, true];
    var metadata = ["reserved-free-workout", GymStore.accountBinding, GymStore.deviceBinding,
        null, 1700003000, true, checkpoint, 0, 0, 0];
    var ok = GymPendingJournal.begin(metadata) == 0 && GymPendingJournal.advance() == 1 &&
        GymStore.recoverQueuedWorkout() && GymStore.pendingCount() == 4 &&
        Storage.getValue("activeWorkoutV1")[4] == null && !GymStore.hasPreparedWorkout();
    GymStore.clearAccountScopedState();
    return ok;
}

(:test, :compactLegacyState)
function pendingMetadataTotalsRejectConflictsInBothFormats(logger as Test.Logger) as Lang.Boolean {
    for (var format = 0; format < 2; format += 1) {
        for (var field = 0; field < 2; field += 1) {
            if (!PendingJournalFixture.prepareWithLegacy(2, format)) { return false; }
            GymPendingJournal.reset();
            if (!GymPendingJournal.load() || GymPendingJournal.entries.size() != 1) { return false; }
            var index = Storage.getValue("pendingJournalV1");
            var key = "queueEntry" + index[1].toString() + "-" + index[2][0].toString();
            var entry = Storage.getValue(key);
            var metadata = entry[0];
            if (metadata instanceof Lang.Dictionary) {
                metadata[field == 0 ? "durationSeconds" : "gymCalories"] = 1;
            } else if (metadata instanceof Lang.Array) { metadata[6][field] = 1; }
            else { return false; }
            Storage.setValue(key, entry);
            GymPendingJournal.reset();
            if (GymPendingJournal.load() || GymPendingJournal.readable ||
                GymPendingJournal.entries.size() != 0) { return false; }
            // Reject the inconsistent payload without deleting the durable index.
            if (Storage.getValue("pendingJournalV1")[1] != index[1]) { return false; }
        }
    }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState)
function queueReferencesRejectReplacedRecordsAndUnreadableSave(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var index = Storage.getValue("pendingJournalV1");
    var key = "queueEntry" + index[1] + "-" + index[2][0];
    var original = Storage.getValue(key);
    var entry = Storage.getValue(key);
    var header = entry[1] as Lang.Array;
    header[7] += 1;
    Storage.setValue(key, entry);
    if (GymPendingJournal.frame(0, "replaced-record") != null ||
        GymStore.removePendingByRequestId("pending-journal-request-001") ||
        Storage.getValue("pendingJournalV1")[2].size() != 1) { return false; }
    Storage.setValue(key, original);
    if (GymPendingJournal.frame(0, "original-record") == null) { return false; }
    GymPendingJournal.readable = false;
    GymStore.pending = [{"mustNotPersist" => true}];
    var before = Storage.getValue("pending");
    if (GymStore.save() || Storage.getValue("pending").size() != before.size()) { return false; }
    GymStore.pending = []; GymPendingJournal.readable = true;
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :compactLegacyState, :richWorkoutMode)
function fullQueueRefusesNewModesWithoutWritingWorkoutState(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepareWithLegacy(1, 7) ||
        !GymStore.recoverQueuedWorkout() || GymStore.pendingCount() != 8) { return false; }
    GymWorkoutMode.clear();
    var before = Storage.getValue("activeWorkoutV1");
    var exercise = GymStore.exerciseIndex;
    var weight = GymStore.weight;
    var reps = GymStore.reps;
    var plan = GymStore.plan;
    if (GymWorkoutMode.begin(true) || GymWorkoutMode.begin(false) ||
        GymStore.status != GymStatus.QUEUE_FULL || !GymWorkoutMode.isIdle() ||
        GymStore.pendingCount() != 8 || GymStore.plan != plan ||
        GymStore.exerciseIndex != exercise || GymStore.weight != weight || GymStore.reps != reps ||
        Storage.getValue("activeWorkoutModeV1") != null) { return false; }
    var after = Storage.getValue("activeWorkoutV1");
    for (var i = 4; i < 9; i += 1) { if (before[i] != after[i]) { return false; } }
    GymStore.clearAccountScopedState();
    return true;
}

(:test, :notFr55Memory)
function discardAllClearsAnUnreadableQueueAndItsStrayBanks(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    Storage.deleteValue("activeWorkoutV1");
    Storage.setValue("pendingJournalV1", "damaged");
    Storage.setValue("sendProgressV1", [1]);
    var banks = [0, 4, 9];
    for (var i = 0; i < banks.size(); i += 1) {
        Storage.setValue("queueEntry0-" + banks[i].toString(), [1]);
        Storage.setValue("queueEntry1-" + banks[i].toString(), [1]);
        Storage.setValue(GymActiveJournal.key(banks[i], 0), [1]);
        Storage.setValue(GymPendingJournal.nameKey(banks[i], 59), [1]);
    }
    if (GymPendingJournal.load() || GymPendingJournal.readable) { return false; }
    var cleared = GymPendingJournal.discardAll();
    var ok = cleared && GymPendingJournal.readable && GymPendingJournal.entries.size() == 0 &&
        Storage.getValue("pendingJournalV1") == null && Storage.getValue("sendProgressV1") == null;
    for (var j = 0; j < banks.size(); j += 1) {
        ok = ok && Storage.getValue("queueEntry0-" + banks[j].toString()) == null &&
            Storage.getValue("queueEntry1-" + banks[j].toString()) == null &&
            Storage.getValue(GymActiveJournal.key(banks[j], 0)) == null &&
            Storage.getValue(GymPendingJournal.nameKey(banks[j], 59)) == null;
    }
    GymStore.clearAccountScopedState();
    return ok;
}

(:test, :notFr55Memory)
function discardUnsentQueueEscapesAnUnreadableJournal(logger as Test.Logger) as Lang.Boolean {
    GymStore.clearAccountScopedState();
    Storage.deleteValue("activeWorkoutV1");
    Storage.setValue("pendingJournalV1", "damaged");
    if (GymPendingJournal.load() || GymPendingJournal.readable) { return false; }
    GymWorkoutMode.clear();
    // The damaged queue blocks a new workout with its own status, not "full".
    var blocked = !GymWorkoutMode.begin(false) && GymStore.status == GymStatus.QUEUE_BROKEN;
    var cleared = GymStore.discardUnsentQueue();
    var ok = blocked && cleared && GymPendingJournal.readable &&
        Storage.getValue("pendingJournalV1") == null && GymStore.pendingCount() == 0;
    GymStore.clearAccountScopedState();
    return ok;
}

// A nack for the queue head must be judged on owner and device only: its
// generation is the phone's and differs from the watch's by definition.
(:test, :compactLegacyState)
function nackIgnoresGenerationAndNeverTouchesTheQueue(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var head = "pending-journal-request-001";
    // The watch holds no generation (the queue was built before pairing
    // rotated), the phone's nack carries its own.
    var nack = {"type" => "nack", "reason" => "generation_mismatch", "requestId" => head,
        "bindingVersion" => 2, "accountBinding" => GymStore.accountBinding,
        "deviceBinding" => GymStore.deviceBinding,
        "pairingGeneration" => "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"};
    GymStore.status = GymStatus.READY;
    GymComm.nackDelayMs = 0;
    GymComm.nackSyncWanted = false;
    GymComm.handleNack(nack);
    var ok = GymStore.bindingsMatchIgnoringGeneration(nack) && !GymStore.bindingsMatch(nack) &&
        (GymStore.status == GymStatus.PAIR_OLD) && GymComm.nackDelayMs == 60000 &&
        GymComm.nackSyncWanted && GymStore.pendingCount() == 1 &&
        GymPendingJournal.contains(head);
    nack["reason"] = "rate_limited";
    nack.remove("requestId");
    GymComm.handleNack(nack);
    ok = ok && (GymStore.status == GymStatus.RATE_LIMITED) && GymComm.nackDelayMs == 300000 &&
        !GymComm.nackSyncWanted && GymStore.pendingCount() == 1;
    nack["reason"] = "reset_required";
    GymComm.handleNack(nack);
    ok = ok && (GymStore.status == GymStatus.RESET_REQUIRED);
    var refusals = ["invalid", "rejected", "binding_mismatch"];
    for (var i = 0; i < refusals.size(); i += 1) {
        nack["reason"] = refusals[i];
        GymStore.status = GymStatus.READY;
        GymComm.handleNack(nack);
        ok = ok && (GymStore.status == GymStatus.REFUSED) && GymComm.nackDelayMs == 300000 &&
            GymStore.pendingCount() == 1 && GymPendingJournal.contains(head);
    }
    GymComm.nackDelayMs = 0;
    GymComm.nackSyncWanted = false;
    GymStore.clearAccountScopedState();
    return ok;
}

(:test, :compactLegacyState)
function nackForAnotherRequestOrOwnerOrReasonIsIgnoredOrBad(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepare() || !GymStore.recoverQueuedWorkout()) { return false; }
    var nack = {"type" => "nack", "reason" => "rejected",
        "requestId" => "some-other-request", "bindingVersion" => 2,
        "accountBinding" => GymStore.accountBinding, "deviceBinding" => GymStore.deviceBinding};
    GymStore.status = GymStatus.READY;
    GymComm.nackDelayMs = 0;
    GymComm.handleNack(nack);
    // Foreign request id: no status, no delay, queue intact.
    var ok = (GymStore.status == GymStatus.READY) && GymComm.nackDelayMs == 0 &&
        GymStore.pendingCount() == 1;
    nack["requestId"] = "pending-journal-request-001";
    nack["deviceBinding"] = "another-device";
    GymComm.handleNack(nack);
    ok = ok && (GymStore.status == GymStatus.BAD_ACK) && GymComm.nackDelayMs == 0;
    nack["deviceBinding"] = GymStore.deviceBinding;
    nack["reason"] = "surprise";
    GymStore.status = GymStatus.READY;
    GymComm.handleNack(nack);
    ok = ok && (GymStore.status == GymStatus.BAD_ACK) && GymComm.nackDelayMs == 0;
    nack["reason"] = 7;
    GymStore.status = GymStatus.READY;
    GymComm.handleNack(nack);
    ok = ok && (GymStore.status == GymStatus.BAD_ACK) && GymStore.pendingCount() == 1 &&
        GymPendingJournal.contains("pending-journal-request-001");
    GymStore.clearAccountScopedState();
    return ok;
}

// Delete-next removes exactly the head (legacy entries first, then the
// journal) and never counts as a phone acknowledgement.
(:test, :compactLegacyState, :richWorkoutMode)
function discardPendingHeadRemovesOnlyTheHead(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepareWithLegacy(2, 2) || !GymStore.recoverQueuedWorkout()) { return false; }
    var syncedAt = GymStore.lastWorkoutSyncAtSeconds;
    if (GymStore.pendingCount() != 3 ||
        !GymStore.pendingHeadRequestId().equals("reserved-legacy-0")) { return false; }
    if (!GymStore.discardPendingHead() || GymStore.pendingCount() != 2 ||
        !GymStore.pendingHeadRequestId().equals("reserved-legacy-1") ||
        Storage.getValue("pending").size() != 1 ||
        !GymPendingJournal.contains("pending-journal-request-001")) { return false; }
    if (!GymStore.discardPendingHead() || GymStore.pendingCount() != 1 ||
        !GymStore.pendingHeadRequestId().equals("pending-journal-request-001") ||
        Storage.getValue("pending").size() != 0) { return false; }
    if (!GymStore.discardPendingHead() || GymStore.pendingCount() != 0 ||
        GymStore.pendingHeadRequestId() != null ||
        GymPendingJournal.contains("pending-journal-request-001")) { return false; }
    var empty = !GymStore.discardPendingHead();
    GymStore.clearAccountScopedState();
    return empty && GymStore.lastWorkoutSyncAtSeconds == syncedAt;
}

(:test, :compactLegacyState, :richWorkoutMode)
function discardPendingHeadIsRefusedWhileRecording(logger as Test.Logger) as Lang.Boolean {
    if (!PendingJournalFixture.prepareWithLegacy(2, 1) || !GymStore.recoverQueuedWorkout()) { return false; }
    GymSession.recording = true;
    var refused = !GymStore.discardPendingHead() && GymStore.pendingCount() == 2;
    GymSession.recording = false;
    GymStore.clearAccountScopedState();
    return refused;
}
