using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;

// A queue entry pins an immutable active bank. The small index is the commit
// point; no full workout dictionary is required to finish a long recording.
class GymPendingJournal {
    static var entries = [];
    static var readable = true;
    private static var staged = null;
    private static var nextName = 0;
    private static var stagedTotals = null;
    private static var dirty = false;
    private static var transferId = null;
    private static var attempt = null;
    private static var offset = 0;
    private static var sentAt = null;
    private static var indexSlot = 0;
    private static var stagedNameBytes = null;

    // Version 2 stores an exact checkpoint context instead of repeating every
    // wire key. Version 1 dictionaries remain readable until acknowledged.
    static function metadataOf(entry) {
        var value = entry[0];
        if (value instanceof Lang.Dictionary) { return value; }
        if (!(value instanceof Lang.Array) || value.size() != 10 || value[9] != entry[1][5]) { return null; }
        return GymStore.expandWorkoutMetadata(value);
    }

    private static function requestIdOf(entry) {
        return entry.size() == 9 ? entry[0] :
            (entry[0] instanceof Lang.Array ? entry[0][0] : entry[0]["requestId"]);
    }

    // Flat runtime references retain only the exact immutable identity/version
    // tuple; the owner tuple and checkpoint remain on disk. These are never
    // a stored/wire format; old versions 1/2 remain full entries until committed.
    private static function reference(entry, names) {
        var h = entry[1];
        return [requestIdOf(entry), h[3], h[4], h[5], h[6], h[7], h[8], entry[2],
            entryStorageBytes(entry, names)];
    }
    private static function resolve(entry) as Lang.Array or Null {
        if (entry.size() != 9) { return entry; }
        try {
            var stored = Storage.getValue(entryKey(indexSlot, entry[4]));
            if (!matchesGeneration(stored, entry[1]) ||
                !requestIdOf(stored).equals(entry[0])) { return null; }
            var h = stored[1];
            for (var i = 4; i <= 8; i += 1) {
                if (h[i] != entry[i - 2]) { return null; }
            }
            if (stored[2] != entry[7]) { return null; }
            shareBindings(stored, entry[1]);
            return stored;
        } catch (e) { return null; }
    }

    private static function bankOf(entry) { return entry.size() == 9 ? entry[4] : entry[1][6]; }
    private static function nameBytesOf(entry) { return entry.size() == 9 ? entry[7] : entry[2]; }

    private static function entryKey(slot, bank) {
        return "queueEntry" + slot.toString() + "-" + bank.toString();
    }

    // Each value is bounded to one workout. Write the inactive slot first,
    // then switch the tiny index; a failed write keeps the entire previous slot.
    private static function storeIndex(next) {
        var slot = 1 - indexSlot;
        var banks = [];
        try {
            for (var i = 0; i < next.size(); i += 1) {
                var entry = resolve(next[i]);
                if (entry == null) { return false; }
                var bank = entry[1][6];
                Storage.setValue(entryKey(slot, bank), entry);
                banks.add(bank);
                entry = null;
            }
            Storage.setValue("pendingJournalV1", [3, slot, banks]);
        } catch (e) { return false; }
        // Resolve against the old slot before switching runtime references.
        for (var j = 0; j < next.size(); j += 1) {
            if (next[j].size() != 9) { next[j] = reference(next[j], next[j] == staged ? stagedNameBytes : null); }
        }
        indexSlot = slot;
        return true;
    }

    static function reset() { stagedNameBytes = null; indexSlot = 0; entries = []; readable = true; dirty = false; transferId = null; attempt = null; offset = 0; sentAt = null; staged = null; nextName = 0; stagedTotals = null; }

    static function nameKey(bank, index) {
        return "queueName" + bank.toString() + "-" + index.toString();
    }

    static function pins(bank) {
        for (var i = 0; i < entries.size(); i += 1) {
            if (bankOf(entries[i]) == bank) { return true; }
        }
        return false;
    }

    static function availableBank(previous) {
        if (!readable) { return -1; }
        for (var bank = 0; bank < 10; bank += 1) {
            if (bank != previous && !pins(bank)) { return bank; }
        }
        return -1;
    }

    static function validEntry(value) { return matchesGeneration(value, GymStore.pairingGeneration); }

    private static function matchesGeneration(value, generation) {
        if (!(value instanceof Lang.Array) || value.size() != 3 ||
            !GymActiveJournal.validHeader(value[1]) ||
            !GymStore.isBoundedInteger(value[2], 0, 12000) ||
            !GymStore.hasAccountBinding()) { return false; }
        var header = value[1];
        var metadata = value[0];
        var context = metadata instanceof Lang.Array;
        if (context) {
            if (!GymStore.isValidWorkoutContext(metadata) || metadata[9] != header[5] ||
                (metadata[5] ? (header[5] != 0 || metadata[6] == null || metadata[6][0] < 1) :
                    header[5] < 1)) { return false; }
        } else if (!GymStore.isValidWorkoutMetadata(metadata, header[5]) ||
            metadata["sets"] != null || metadata["setIntervals"] != null ||
            metadata["setMetrics"] != null) { return false; }
        return (context ? metadata[4] : metadata["startedAtSeconds"]) == header[4] &&
            (context ? metadata[1] : metadata["accountBinding"]).equals(GymStore.accountBinding) &&
            (context ? metadata[2] : metadata["deviceBinding"]).equals(GymStore.deviceBinding) &&
            header[1].equals(GymStore.accountBinding) && header[2].equals(GymStore.deviceBinding) &&
            GymStore.sameOptionalText(header[3], generation) &&
            GymStore.sameOptionalText(context ? metadata[3] : metadata["pairingGeneration"], generation);
    }

    static function row(entry, index) {
        var header = entry[1];
        if (!GymStore.isBoundedInteger(index, 0, header[5] - 1)) { return null; }
        try {
            var value = Storage.getValue(GymActiveJournal.key(header[6], index));
            if (!(value instanceof Lang.Array) || value.size() != 6 ||
                !GymStore.isBoundedInteger(value[1], 0, 59)) { return null; }
            var name = Storage.getValue(nameKey(header[6], value[1]));
            if (!(value instanceof Lang.Array) || value.size() != 6 ||
                value[0] != header[7] || !GymStore.isBoundedInteger(value[5], 1, header[8]) ||
                !GymStore.isValidWeight(value[2]) || !GymStore.isValidReps(value[3]) ||
                !(name instanceof Lang.Array) || name.size() != 3 || name[0] != header[7] ||
                name[1] != value[1] || !GymStore.isValidExerciseName(name[2]) ||
                (header[9] == null ? value[4] != null : !GymStore.isValidSetInterval(value[4]))) {
                return null;
            }
            return [name[2], value[2], value[3], value[4], value[1]];
        } catch (e) { return null; }
    }

    // Called only after the complete owner/device/generation validation. Stored
    // metadata repeats the same immutable strings; reuse their exact live values
    // before the serializer allocates its own output buffer.
    private static function shareBindings(entry, generation) {
        var header = entry[1];
        header[1] = GymStore.accountBinding;
        header[2] = GymStore.deviceBinding;
        header[3] = generation;
        var metadata = entry[0];
        if (metadata instanceof Lang.Array) {
            metadata[1] = header[1]; metadata[2] = header[2]; metadata[3] = generation;
        } else {
            metadata["accountBinding"] = header[1];
            metadata["deviceBinding"] = header[2];
            if (metadata["pairingGeneration"] != null) { metadata["pairingGeneration"] = generation; }
        }
    }

    static function load() {
        reset();
        var value = null;
        try { value = Storage.getValue("pendingJournalV1"); }
        catch (e) { readable = false; return false; }
        if (value == null) { return true; }
        if (!(value instanceof Lang.Array) || value.size() < 2 ||
            !(value[0] instanceof Lang.Number)) { readable = false; return false; }
        var source = null;
        if (value[0] == 3) {
            if (value.size() != 3 || !(value[1] instanceof Lang.Number) ||
                (value[1] != 0 && value[1] != 1)) { readable = false; return false; }
            indexSlot = value[1]; source = value[2];
        } else {
            if (value.size() != 2 || (value[0] != 1 && value[0] != 2)) {
                readable = false; return false;
            }
            source = value[1];
        }
        if (!(source instanceof Lang.Array) || source.size() > 8) { readable = false; return false; }
        var next = [];
        // Never publish only a valid prefix of an unreadable queue.
        var bytes = 0;
        var recovery = GymStore.stagedPairingRecoveryTarget();
        if (source.size() + GymStore.pendingCount() > 8) { readable = false; return false; }
        for (var i = 0; i < source.size(); i += 1) {
            var entry = source[i];
            if (value[0] == 3) {
                if (!(entry instanceof Lang.Number) || entry < 0 || entry > 9) { readable = false; return false; }
                try { entry = Storage.getValue(entryKey(indexSlot, entry)); }
                catch (e) { readable = false; return false; }
                if (!(entry instanceof Lang.Array) || entry.size() != 3 ||
                    !GymActiveJournal.validHeader(entry[1]) || entry[1][6] != source[i]) { readable = false; return false; }
            }
            if (!(entry instanceof Lang.Array) || entry.size() != 3 ||
                (value[0] == 1 && !(entry[0] instanceof Lang.Dictionary))) {
                readable = false; return false;
            }
            if (!validEntry(entry) && (recovery == null || !matchesGeneration(entry, recovery))) {
                readable = false; return false;
            }
            for (var p = 0; p < i; p += 1) {
                if (bankOf(next[p]) == entry[1][6] ||
                    requestIdOf(next[p]).equals(requestIdOf(entry))) {
                    readable = false; return false;
                }
            }
            var nameBytes = 0;
            var uniqueNameBytes = 0; var seenNames = 0l;
            var totals = [0, 0.0, 0.0];
            for (var r = 0; r < entry[1][5]; r += 1) {
                var item = row(entry, r);
                if (item == null || !addInterval(entry, totals, item[3])) {
                    readable = false; return false;
                }
                var size = GymStore.utf8Bytes(item[0]).size();
                nameBytes += size;
                var bit = 1l << item[4];
                if ((seenNames & bit) == 0) {
                    seenNames |= bit; uniqueNameBytes += 64 + size;
                }
            }
            if (nameBytes != entry[2]) { readable = false; return false; }
            shareBindings(entry, GymStore.sameOptionalText(entry[1][3], GymStore.pairingGeneration) ?
                GymStore.pairingGeneration : recovery);
            bytes += nameBytes;
            next.add(value[0] == 3 ? reference(entry, uniqueNameBytes) : entry);
        }
        if (bytes > 12000) { readable = false; return false; }
        entries = next;
        return true;
    }

    // Returns 0 while names are being pinned, 1 after the durable queue commit,
    // or -1 on failure. The active snapshot/marker remain intact on every failure.
    static function begin(metadata) {
        staged = null; nextName = 0; stagedTotals = null;
        if (!(metadata instanceof Lang.Dictionary) && !(metadata instanceof Lang.Array)) { return -1; }
        if (!readable || GymStore.pendingCount() >= 8 ||
            !GymStore.hasPreparedWorkout() || (!GymStore.preparedWorkoutFitSaved() &&
                !GymSession.fitOutcomeUnknownAfterRestart())) { return -1; }
        var header = GymActiveJournal.snapshot();
        if (header == null || pins(header[6]) || header[5] != GymStore.sets.size()) { return -1; }
        if (metadata instanceof Lang.Dictionary) {
            metadata.remove("sets"); metadata.remove("setMetrics"); metadata.remove("setIntervals");
        }
        var value = [metadata, header, 0];
        if (!validEntry(value) ||
            !GymStore.preparedWorkout[4].equals(requestIdOf(value))) { return -1; }
        if (!clearBankNames(header[6])) { return -1; }
        stagedNameBytes = GymActiveJournal.queueNameStorageBytes();
        staged = value; stagedTotals = [0, 0.0, 0.0];
        return 0;
    }

    static function advance() {
        if (staged == null || !validEntry(staged) || !GymStore.hasPreparedWorkout() ||
            (!GymStore.preparedWorkoutFitSaved() && !GymSession.fitOutcomeUnknownAfterRestart()) ||
            !GymStore.preparedWorkout[4].equals(requestIdOf(staged)) ||
            GymActiveJournal.snapshot() != staged[1]) { staged = null; return -1; }
        try {
            if (nextName < staged[1][5]) {
                var value = Storage.getValue(GymActiveJournal.key(staged[1][6], nextName));
                if (!(value instanceof Lang.Array) || value.size() != 6 ||
                    value[0] != staged[1][7] ||
                    !GymStore.isBoundedInteger(value[5], 1, staged[1][8]) ||
                    !GymStore.isValidWeight(value[2]) || !GymStore.isValidReps(value[3]) ||
                    !GymStore.isBoundedInteger(value[1], 0, GymStore.exercises.size() - 1)) {
                    staged = null; return -1;
                }
                if ((staged[1][9] != null && !GymStore.isValidSetInterval(value[4])) ||
                    !addInterval(staged, stagedTotals, value[4])) { staged = null; return -1; }
                var name = GymStore.exercises[value[1]];
                var bytes = GymStore.utf8Bytes(name).size();
                if (staged[2] + bytes + totalNameBytes() > 12000) { staged = null; return -1; }
                Storage.setValue(nameKey(staged[1][6], value[1]), [value[0], value[1], name]);
                staged[2] += bytes; nextName += 1;
                return 0;
            }
            var next = entries.slice(null, null);
            next.add(staged);
            // The existing prepared ID is also the recovery marker when an index
            // commit wins but its later active tombstone does not.
            var previousEntries = entries;
            entries = next;
            var withinBudget = false;
            try { withinBudget = GymStore.isWithinStorageBudget(); }
            catch (budgetError) { withinBudget = false; }
            entries = previousEntries;
            if (!withinBudget) { staged = null; return -1; }
            Storage.setValue("queuedActiveRequestId", GymStore.preparedWorkout[4]);
            if (!storeIndex(next)) { staged = null; return -1; }
            entries = next; staged = null; nextName = 0;
            return 1;
        } catch (e) { staged = null; return -1; }
    }

    // Validate chronological slices against both the committed checkpoint and
    // outgoing totals. This same check applies during append and after restart.
    private static function addInterval(entry, totals, interval) {
        var checkpoint = entry[1][9];
        if (checkpoint == null) { return interval == null; }
        // Entry validation already checked both legacy dictionaries and compact
        // contexts. Read only the three totals needed here; expanding the wire
        // dictionary for each row consumes the headroom needed to save on FR55.
        var metadata = entry[0];
        var context = metadata instanceof Lang.Array;
        var summary = context ? metadata[6] : metadata;
        if (summary == null) { return false; }
        var duration = context ? summary[0] : summary["durationSeconds"];
        var gymCalories = context ? summary[1] : summary["gymCalories"];
        var garminCalories = context ? summary[2] : summary["garminCalories"];
        // row() and advance() validate each interval once before this aggregate check.
        if (interval[0] < totals[0] ||
            duration == null || interval[1] > checkpoint[0] ||
            interval[1] > duration) { return false; }
        totals[0] = interval[1]; totals[1] += interval[2].toFloat();
        if (interval[3] != null) {
            if (checkpoint[2] == null || garminCalories == null) { return false; }
            totals[2] += interval[3].toFloat();
        }
        return gymCalories != null &&
            totals[1] <= checkpoint[1].toFloat() + 0.1 &&
            totals[1] <= gymCalories.toFloat() + 0.1 &&
            (checkpoint[2] == null || totals[2] <= checkpoint[2].toFloat() + 0.1) &&
            (garminCalories == null || totals[2] <= garminCalories.toFloat() + 0.1);
    }

    private static function entryStorageBytes(entry, names) {
        var header = entry[1];
        // Immutable rows share one stored name per catalog index. The separate
        // 12 KiB wire limit still counts every repeated name, as before.
        // Two serialized entry slots require 136 bytes of measured framing;
        // retain 192 for their framing and share of the small index.
        return 192 + 2 * GymStore.estimatedValueBytes(entry) + header[5] * 160 +
            (names == null ? header[5] * 64 + entry[2] : names);
    }

    static function estimatedBytes() {
        var bytes = 0;
        for (var i = 0; i < entries.size(); i += 1) {
            // Both index slots hold the same bounded entry. Use its actual
            // encoded-value estimate plus per-entry framing reserve.
            var entry = entries[i];
            bytes += entry.size() == 9 ? entry[8] :
                entryStorageBytes(entry, entry == staged ? stagedNameBytes : null);
        }
        return bytes;
    }

    static function clearBankNames(bank) {
        for (var n = 0; n < 60; n += 1) {
            try { Storage.deleteValue(nameKey(bank, n)); }
            catch (e) { return false; }
        }
        return true;
    }

    static function clear() {
        reset();
        try { Storage.deleteValue("pendingJournalV1"); }
        catch (e) { readable = false; return false; }
        for (var bank = 0; bank < 10; bank += 1) {
            try {
                Storage.deleteValue(entryKey(0, bank));
                Storage.deleteValue(entryKey(1, bank));
            } catch (e) { return false; }
            if (!clearBankNames(bank)) { return false; }
        }
        return true;
    }

    static function origin(requestId) {
        if (!readable) { return null; }
        for (var i = 0; i < entries.size(); i += 1) {
            if (requestIdOf(entries[i]).equals(requestId)) {
                var entry = resolve(entries[i]);
                if (validEntry(entry)) { return entry[1][4]; }
            }
        }
        return null;
    }

    static function contains(requestId) { return origin(requestId) != null; }

    static function rotate(previous, next) {
        if (!readable || !GymStore.isValidOptionalAccountBinding(previous) ||
            !GymStore.isValidAccountBinding(next)) { return false; }
        var rotated = [];
        for (var i = 0; i < entries.size(); i += 1) {
            var entry = resolve(entries[i]);
            if (!matchesGeneration(entry, previous) && !matchesGeneration(entry, next)) { return false; }
            var metadata = {};
            var source = metadataOf(entry);
            var keys = source.keys();
            for (var k = 0; k < keys.size(); k += 1) { metadata.put(keys[k], source[keys[k]]); }
            metadata.put("pairingGeneration", next);
            var header = (entry[1] as Lang.Array).slice(null, null); header[3] = next;
            rotated.add([metadata, header, entry[2]]);
        }
        entries = rotated; dirty = entries.size() > 0;
        return true;
    }

    // The enclosing phone-stage transaction persists this index before publishing
    // its new generation. A restart accepts only that exact staged generation.
    static function save() {
        if (!readable) { return false; }
        if (!dirty) { return true; }
        for (var i = 0; i < entries.size(); i += 1) {
            if (!validEntry(resolve(entries[i]))) { return false; }
        }
        if (!storeIndex(entries)) { return false; }
        dirty = false;
        return true;
    }

    static function remove(requestId) {
        if (!contains(requestId) || entries.size() == 0 ||
            !requestIdOf(entries[0]).equals(requestId) ||
            (GymStore.hasPreparedWorkout() &&
                GymStore.preparedWorkout[4].equals(requestId))) { return false; }
        var bank = bankOf(entries[0]);
        var next = entries.slice(1, null);
        if (!storeIndex(next)) { return false; }
        entries = next; dirty = false;
        // Index removal is the commit. An interrupted cleanup leaves only bounded
        // unreferenced rows, which are overwritten when this bank is reused.
        try {
            Storage.deleteValue(entryKey(0, bank));
            Storage.deleteValue(entryKey(1, bank));
            var active = Storage.getValue("activeWorkoutV1");
            if (GymActiveJournal.validHeader(active) && active[6] == bank) { return true; }
            for (var i = 0; i < 60; i += 1) {
                Storage.deleteValue(GymActiveJournal.key(bank, i));
                Storage.deleteValue(nameKey(bank, i));
            }
        } catch (e) { }
        return true;
    }

    static function totalNameBytes() {
        var bytes = 0;
        for (var i = 0; i < entries.size(); i += 1) { bytes += nameBytesOf(entries[i]); }
        bytes += GymStore.legacyPendingNameBytes();
        return bytes;
    }

    static function nextMessage() {
        if (!readable || entries.size() == 0) { return null; }
        var id = requestIdOf(entries[0]);
        if (transferId == null || !transferId.equals(id) ||
            (sentAt != null && GymStore.timerElapsedMs(sentAt) >= 20000l)) { offset = 0; }
        transferId = id;
        attempt = GymStore.nextRequestId("part");
        sentAt = Toybox.System.getTimer();
        return frame(offset, attempt);
    }

    static function acknowledgePart(message) {
        var entry = entries.size() == 0 ? null : resolve(entries[0]);
        if (!(message instanceof Lang.Dictionary) || message.size() != 9 ||
            !GymStore.bindingsMatch(message) || !readable || entries.size() == 0 ||
            !validEntry(entry) || transferId == null || attempt == null ||
            !GymStore.sameOptionalText(message["type"], "workout_part_ack") ||
            !(message["transferVersion"] instanceof Lang.Number) || message["transferVersion"] != 1 ||
            !GymStore.sameOptionalText(message["requestId"], transferId) ||
            !GymStore.sameOptionalText(message["attemptId"], attempt) ||
            !requestIdOf(entries[0]).equals(transferId) ||
            !GymStore.isBoundedInteger(message["nextOffset"], offset + 1, entry[1][5] - 1)) { return false; }
        // Only a fresh, exact phone response advances this in-memory cursor.
        // No partial response removes any persistent workout data.
        offset = message["nextOffset"]; attempt = null; sentAt = null;
        return true;
    }

    static function frame(offset, attemptId) {
        if (!GymStore.isBoundedText(attemptId, GymStore.maxBindingLength)) { return null; }
        if (!readable || entries.size() == 0) { return null; }
        var entry = resolve(entries[0]);
        if (!validEntry(entry)) { return null; }
        var count = entry[1][5];
        if (!GymStore.isBoundedInteger(offset, 0, count == 0 ? 0 : count - 1)) { return null; }
        var message = {"type" => "workout_part", "transferVersion" => 1,
            "offset" => offset, "totalSets" => count, "attemptId" => attemptId, "metadata" => metadataOf(entry)};
        if (count > 0) {
            var item = row(entry, offset);
            if (item == null) { return null; }
            message.put("set", {"exerciseName" => item[0], "weight" => item[1], "reps" => item[2]});
            if (item[3] != null) { message.put("interval", item[3]); }
        }
        return message;
    }
}
