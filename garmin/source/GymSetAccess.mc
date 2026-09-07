using Toybox.Lang as Lang;

// Phone and Object Store values remain ordinary arrays of dictionaries. Only
// the validated active journal owns this private, bounded runtime collection.
class GymSetAccess {
    (:fullLegacyState)
    static function at(value, index) { return value[index]; }

    (:compactLegacyState)
    static function at(value, index) {
        return value instanceof GymJournalList ? value.at(index) : value[index];
    }

    (:fullLegacyState, :inline)
    static function isJournal(value) { return false; }

    (:compactLegacyState, :inline)
    static function isJournal(value) { return value instanceof GymJournalList; }

    (:fullLegacyState, :inline)
    static function committed(value) { return value; }

    (:compactLegacyState, :inline)
    static function committed(value) { return GymActiveJournal.currentRecords(); }
}

(:compactLegacyState)
class GymJournalList {
    var source;
    var data;
    var count;
    var nameBytes;
    var tail;

    function initialize(header, rows, bytes) {
        source = header; data = rows; count = header[5]; nameBytes = bytes; tail = [];
    }

    function size() { return count + tail.size(); }

    function at(index) {
        if (index >= count) { return tail[index - count]; }
        var name = GymStore.exercises[data[index]];
        return [name, index, :journalRecord, source];
    }

    function add(item) { tail.add(item); }

    function slice(start, end) {
        start = start == null ? 0 : start;
        end = end == null ? size() : end;
        // The live append/undo paths share the immutable prefix. Keep the
        // ordinary slice result for other callers, without changing its values.
        if (start != 0) {
            var result = [];
            for (var i = start; i < end; i += 1) { result.add(at(i)); }
            return result;
        }
        var result = new GymJournalList(source, data, nameBytes);
        result.count = end < count ? end : count;
        for (var r = result.count; r < count; r += 1) {
            result.nameBytes -= GymStore.utf8Bytes(GymStore.exercises[data[r]]).size();
        }
        result.tail = end > count ? tail.slice(0, end - count) : [];
        return result;
    }

    function valid(maximum, allowEmpty) {
        return source == GymActiveJournal.snapshot() &&
            GymStore.activeWorkoutSnapshotMatchesBindings(source) &&
            count >= 0 && count <= source[5] && data.size() >= count &&
            size() <= maximum && (allowEmpty || size() > 0) &&
            GymStore.isValidLiveSetList(tail, maximum - count, true) &&
            nameBytes + GymStore.setListNameBytes(tail) <= 12000;
    }
}
