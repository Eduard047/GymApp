using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;

// A bounded bank pool holds immutable rows. activeWorkoutV1 is the only commit
// point: an interrupted append or replacement leaves the old header readable.
// Rows are never a phone payload and are accepted only with the header epoch.
class GymActiveJournal {
    private static var header = null;
    private static var records = null;
    private static var legacyCount = -1;
    private static var rowCacheRef = null;
    private static var rowCache = null;
    private static var intervalTotals = null;
    static var stagingBytes = 0;

    static function reset() {
        header = null; records = null; legacyCount = -1; stagingBytes = 0;
        rowCacheRef = null; rowCache = null; intervalTotals = null;
    }

    static function snapshot() { return header; }
    static function releaseReadCache() { rowCacheRef = null; rowCache = null; }
    static function currentRecords() { return records; }

    static function rememberLegacy(value) {
        if (value[0] != 6) { legacyCount = value[5].size(); }
    }

    static function key(bank, index) {
        return "activeRow" + bank.toString() + "-" + index.toString();
    }

    // Callers establish the enclosing array shape before reading its binding tuple.
    static function validBindings(value) {
        return GymStore.isValidAccountBinding(value[1]) &&
            GymStore.isBoundedText(value[2], GymStore.maxBindingLength) &&
            GymStore.isValidOptionalAccountBinding(value[3]);
    }

    static function validHeader(value) {
        if (!(value instanceof Lang.Array) || value.size() != 10 || !(value[0] instanceof Lang.Number) || value[0] != 6 ||
            !validBindings(value) ||
            !GymStore.isBoundedInteger(value[5], 0, GymStore.maxWorkoutSets) ||
            !GymStore.isBoundedInteger(value[6], 0, 9) ||
            !GymStore.isBoundedInteger(value[7], 1, 2147483647) ||
            !GymStore.isBoundedInteger(value[8], 1, 2147483647) ||
            (value[9] != null && !GymStore.isValidTimelineCheckpoint(value[9]))) {
            return false;
        }
        return value[4] == null ? (value[5] == 0 || value[9] == null) :
            (GymStore.isValidWorkoutStartedAtSeconds(value[4]) &&
                (value[5] > 0 || value[9] != null));
    }

    static function validate(value) {
        reset();
        if (!validHeader(value)) { return false; }
        var restored = allocateRows(value[5]);
        var checkpoint = value[9];
        var previousEnd = 0;
        var gymSum = 0.0;
        var garminSum = 0.0;
        var hasGarmin = false;
        var nameBytes = 0;
        try {
            for (var i = 0; i < value[5]; i += 1) {
                var row = Storage.getValue(key(value[6], i));
                if (!(row instanceof Lang.Array) || row.size() != 6 ||
                    row[0] != value[7] ||
                    !GymStore.isBoundedInteger(row[1], 0, GymStore.exercises.size() - 1) ||
                    !GymStore.isValidWeight(row[2]) || !GymStore.isValidReps(row[3]) ||
                    !GymStore.isBoundedInteger(row[5], 1, value[8])) { return false; }
                var interval = row[4];
                if (checkpoint == null) {
                    if (interval != null) { return false; }
                } else {
                    if (!GymStore.isValidSetInterval(interval) ||
                        interval[0] < previousEnd || interval[1] > checkpoint[0]) {
                        return false;
                    }
                    previousEnd = interval[1];
                    gymSum += interval[2].toFloat();
                    if (interval[3] != null) {
                        hasGarmin = true;
                        garminSum += interval[3].toFloat();
                    }
                }
                var name = GymStore.exercises[row[1]];
                nameBytes += GymStore.utf8Bytes(name).size();
                if (nameBytes > 12000) { return false; }
                rememberRow(restored, name, row, i);
            }
        } catch (e) { return false; }
        if (checkpoint != null && (gymSum > checkpoint[1].toFloat() + 0.1 ||
            (hasGarmin && (checkpoint[2] == null ||
                garminSum > checkpoint[2].toFloat() + 0.1)))) { return false; }
        // Publish only after every stored row has passed validation. Keeping this
        // exact result avoids a second full storage read in the same callback.
        if (GymStore.activeWorkoutSnapshotMatchesBindings(value)) {
            value[1] = GymStore.accountBinding;
            value[2] = GymStore.deviceBinding;
            value[3] = GymStore.pairingGeneration;
        }
        header = value;
        records = finishRows(value, restored, nameBytes);
        intervalTotals = [previousEnd, gymSum, garminSum, hasGarmin];
        return true;
    }

    (:fullLegacyState)
    static function allocateRows(count) { return []; }
    (:compactLegacyState)
    static function allocateRows(count) { return new [count == 0 ? 0 :
        (count > GymWorkoutMode.recordingSetLimit ? count : GymWorkoutMode.recordingSetLimit)]b; }
    (:fullLegacyState)
    static function rememberRow(rows, name, row, index) {
        rows.add(GymStore.restoredSet(name, row[2], row[3], row[4]));
    }
    (:compactLegacyState)
    static function rememberRow(rows, name, row, index) {
        rows[index] = row[1];
    }
    (:fullLegacyState)
    static function finishRows(value, rows, bytes) { return rows; }
    (:compactLegacyState)
    static function finishRows(value, rows, bytes) { return new GymJournalList(value, rows, bytes); }

    (:compactLegacyState)
    static function isRecord(value) {
        return value instanceof Lang.Array && value.size() == 4 && value[2] == :journalRecord && value[1] instanceof Lang.Number && value[3] instanceof Lang.Array;
    }

    (:compactLegacyState)
    static function countExercise(name) {
        if (records == null || GymStore.sets != records ||
            !GymStore.activeWorkoutSnapshotMatchesBindings(header)) { return 0; }
        var index = GymStore.exerciseIndexForName(name);
        var count = 0;
        for (var i = 0; i < records.count; i += 1) {
            if (records.data[i] == index) { count += 1; }
        }
        return count;
    }

    (:compactLegacyState)
    static function get(value, field) {
        var record = value;
        if (!field.equals("exerciseName") && !field.equals("weight") && !field.equals("reps") && !field.equals("setInterval")) {
            return null;
        }
        var index = record[1];
        // A live handle belongs to one exact published header. Appends never
        // overwrite its referenced prefix; replacement/undo commits invalidate
        // old handles before an index can be reused. Rows still require the
        // committed epoch and a revision no newer than that header.
        // validate/commit already checked this immutable header's shape and binding
        // syntax. Reads still compare the exact live owner/device/generation,
        // without rescanning both 64-character hashes for every field.
        if (header == null || records == null || index >= records.size() ||
            index < 0 || index >= header[5] || record[3] != header ||
            !header[1].equals(GymStore.accountBinding) ||
            !header[2].equals(GymStore.deviceBinding) ||
            !GymStore.sameOptionalText(header[3], GymStore.pairingGeneration)) { return null; }
        if (field.equals("exerciseName")) { return record[0]; }
        if (rowCacheRef != record) {
            rowCacheRef = null; rowCache = null;
            try { rowCache = Storage.getValue(key(header[6], index)); }
            catch (e) { return null; }
            if (!(rowCache instanceof Lang.Array) || rowCache.size() != 6 ||
                rowCache[0] != header[7] || !GymStore.isBoundedInteger(rowCache[5], 1, header[8]) ||
                !GymStore.isBoundedInteger(rowCache[1], 0, GymStore.exercises.size() - 1) ||
                !GymStore.exercises[rowCache[1]].equals(record[0]) ||
                !GymStore.isValidWeight(rowCache[2]) || !GymStore.isValidReps(rowCache[3]) ||
                (rowCache[4] != null && !GymStore.isValidSetInterval(rowCache[4]))) {
                rowCache = null; return null;
            }
            rowCacheRef = record;
        }
        return field.equals("weight") ? rowCache[2] :
            (field.equals("reps") ? rowCache[3] :
                (rowCache[4] == null ? null : rowCache[4].slice(null, null)));
    }

    static function restored(value) {
        return header == value || validate(value) ? records : null;
    }

    static function clear() {
        reset();
        for (var bank = 0; bank < 10; bank += 1) {
            for (var i = 0; i < GymStore.maxWorkoutSets; i += 1) {
                try { Storage.deleteValue(key(bank, i)); }
                catch (e) { return false; }
            }
        }
        return true;
    }

    // Reclaim only beyond a committed prefix or within a proven unreferenced bank.
    // A failed cleanup leaves harmless unreferenced rows for a later retry.
    static function pruneTail(bank, count) {
        for (var r = count; r < GymStore.maxWorkoutSets; r += 1) {
            try { Storage.deleteValue(key(bank, r)); }
            catch (e) { break; }
        }
    }

    (:fullLegacyState)
    static function queueNameStorageBytes() { return null; }

    (:compactLegacyState)
    static function queueNameStorageBytes() {
        return uniqueNameStorageBytes(records.data, records.count);
    }

    (:compactLegacyState)
    private static function uniqueNameStorageBytes(directory, count) {
        var seen = 0l;
        var bytes = 0;
        for (var i = 0; i < count; i += 1) {
            var index = directory[i];
            var bit = 1l << index;
            if ((seen & bit) == 0) {
                seen |= bit;
                bytes += 64 + GymStore.utf8Bytes(GymStore.exercises[index]).size();
            }
        }
        return bytes;
    }

    (:compactLegacyState)
    static function commit(next, origin, checkpoint) {
        if (checkpoint != null && !GymStore.isValidTimelineCheckpoint(checkpoint)) { return false; }
        var previousEnd = 0;
        var gymSum = 0.0;
        var garminSum = 0.0;
        var hasGarmin = false;
        var reusable = header != null && !GymPendingJournal.pins(header[6]) &&
            GymStore.activeWorkoutSnapshotMatchesBindings(header) &&
            header[8] < 2147483647 && header[4] == origin &&
            (header[9] == null) == (checkpoint == null);
        if (GymSetAccess.isJournal(next) &&
            (next.source != header || (next.count < header[5] && next.tail.size() > 0))) {
            reusable = false;
        }
        var checkedFrom = GymSetAccess.isJournal(next) && next.source == header ? next.count : 0;
        for (var i = checkedFrom; i < next.size(); i += 1) {
            var item = GymSetAccess.at(next, i);
            var index = GymStore.exerciseIndexForName(GymStore.setField(item, "exerciseName"));
            if (index < 0) { return false; }
            if (reusable && i < records.size() &&
                (!isRecord(item) || item[3] != header || item[1] != i)) {
                reusable = false;
            }
        }
        var intervalStart = reusable && next.size() >= records.size() ? records.size() : 0;
        if (intervalStart > 0 && intervalTotals != null) {
            previousEnd = intervalTotals[0]; gymSum = intervalTotals[1];
            garminSum = intervalTotals[2]; hasGarmin = intervalTotals[3];
        }
        if (checkpoint != null) {
            for (var t = intervalStart; t < next.size(); t += 1) {
                var interval = GymStore.setField(GymSetAccess.at(next, t), "setInterval");
                if (!GymStore.isValidSetInterval(interval) ||
                    interval[0] < previousEnd || interval[1] > checkpoint[0]) { return false; }
                previousEnd = interval[1];
                gymSum += interval[2].toFloat();
                if (interval[3] != null) { hasGarmin = true; garminSum += interval[3].toFloat(); }
                // The validator reads a private copy from setField. Do not keep
                // the final copy alive beside the storage serialization buffer.
                interval = null;
            }
        }
        if (checkpoint != null && (previousEnd > checkpoint[0] ||
            gymSum > checkpoint[1].toFloat() + 0.1 || (hasGarmin &&
                (checkpoint[2] == null || garminSum > checkpoint[2].toFloat() + 0.1)))) {
            return false;
        }
        var previous = header;
        if (previous == null && legacyCount < 0) {
            try { previous = Storage.getValue("activeWorkoutV1"); }
            catch (e) { return false; }
        }
        var bank = reusable ? header[6] :
            GymPendingJournal.availableBank(validHeader(previous) ? previous[6] : -1);
        if (bank < 0) { return false; }
        var epoch = reusable ? header[7] :
            (validHeader(previous) ? previous[7] % 2147483647 + 1 : 1);
        var revision = reusable ? header[8] + 1 : 1;
        var value = [6, GymStore.accountBinding, GymStore.deviceBinding,
            GymStore.pairingGeneration, origin, next.size(), bank, epoch, revision, checkpoint];
        // A pinned previous bank is already included in the durable queue
        // estimate. Moving the active pointer must not charge its rows twice.
        stagingBytes = reusable ? 0 : (legacyCount >= 0 ? legacyCount * 160 :
            (validHeader(previous) && !GymPendingJournal.pins(previous[6]) ?
                previous[5] * 160 : 0));
        var start = reusable ? records.size() : 0;
        // The directory is immutable inside the published prefix. Appending
        // may fill its unused capacity; undo only shortens the visible prefix.
        // A replacement which changes a referenced index takes a separate copy.
        var sharedDirectory = GymSetAccess.isJournal(next) && next.source == header &&
            next.data.size() >= next.size() &&
            (next.tail.size() == 0 || next.count == header[5]);
        var directory = sharedDirectory ? next.data : allocateRows(next.size());
        var nameBytes = sharedDirectory ? next.nameBytes : 0;
        var directoryStart = sharedDirectory ? next.count : 0;
        for (var d = directoryStart; d < next.size(); d += 1) {
            var entry = GymSetAccess.at(next, d);
            var entryName = GymStore.setField(entry, "exerciseName");
            directory[d] = GymStore.exerciseIndexForName(entryName);
            nameBytes += GymStore.utf8Bytes(entryName).size();
        }
        // Reserve the eventual queue representation before accepting more work.
        // Each row is shared; only name framing and two metadata slots are extra.
        // Each context shares the header's owner, origin, count and checkpoint.
        // Its generated workout ID is at most 36 characters; mode and plan
        // counts add at most 48 encoded bytes over the replaced numeric fields.
        // Reserve two entry slots (4 headers + 2 * 48), plus 192 framing bytes.
        // The existing active-header reservation covers its smaller tombstone.
        if (origin != null && !GymPendingJournal.pins(bank)) {
            stagingBytes += 288 + 4 * GymStore.estimatedValueBytes(value) +
                uniqueNameStorageBytes(directory, next.size());
            if (GymStore.preparedWorkout == null) {
                // The later FIT transaction adds its owner-bound prepared
                // record and request marker. Keep room before accepting a set.
                stagingBytes += 128 + GymStore.estimatedValueBytes(value[1]) +
                    GymStore.estimatedValueBytes(value[2]) + GymStore.estimatedValueBytes(value[3]);
            }
        }
        var withinBudget = validHeader(value) && GymStore.isWithinStorageBudgetForActiveSnapshot(value);
        stagingBytes = 0;
        if (!withinBudget) {
            GymStore.status = GymStatus.STORE_FULL;
            return false;
        }
        // Timeline preparation can refill the last-row read cache after the
        // sensor pause. It is disposable; storage writes need that headroom.
        releaseReadCache();
        if (!reusable) { pruneTail(bank, 0); }
        try {
            for (var r = start; r < next.size(); r += 1) {
                var record = GymSetAccess.at(next, r);
                Storage.setValue(key(bank, r), [epoch,
                    directory[r],
                    GymStore.setField(record, "weight"), GymStore.setField(record, "reps"),
                    // Serialization borrows the validated immutable interval;
                    // UI callers still receive copies through setField().
                    checkpoint == null ? null : (GymRecordedSet.isRecord(record) ?
                        record[3] : GymStore.setField(record, "setInterval")), revision]);
            }
            Storage.setValue("activeWorkoutV1", value);
        } catch (e) { return false; }
        header = value;
        if (reusable && value[5] < previous[5]) { pruneTail(bank, value[5]); }
        legacyCount = -1;
        intervalTotals = [previousEnd, gymSum, garminSum, hasGarmin];
        rowCacheRef = null; rowCache = null;
        if (GymSetAccess.isJournal(next)) {
            next.source = value; next.data = directory; next.count = value[5];
            next.nameBytes = nameBytes; next.tail = []; records = next;
        } else { records = finishRows(value, directory, nameBytes); }
        // Reclaim only an old bank which has no queue readers. A completed workout
        // continues to reference its exact rows after the active pointer moves.
        if (!reusable && validHeader(previous) && !GymPendingJournal.pins(previous[6])) {
            pruneTail(previous[6], 0);
        }
        return true;
    }
}
