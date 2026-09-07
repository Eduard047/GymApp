using Toybox.Lang as Lang;

// A new completed set exists only until its journal row commits. Keep exact
// numeric values and a private interval copy; no encoded duplicate is needed.
(:compactLegacyState)
class GymRecordedSet {
    static function create(name, weight, reps, interval) {
        if (!GymStore.isValidExerciseName(name) || !GymStore.isValidWeight(weight) ||
            !GymStore.isValidReps(reps) ||
            (interval != null && !GymStore.isValidSetInterval(interval))) { return null; }
        return [name, weight, reps, interval == null ? null : interval.slice(null, null),
            :validatedGymRecord, GymStore.utf8Bytes(name).size()];
    }
    static function isRecord(value) {
        return value instanceof Lang.Array && value.size() == 6 && value[4] == :validatedGymRecord;
    }
    static function get(record, key) {
        if (key.equals("exerciseName")) { return record[0]; }
        if (key.equals("weight")) { return record[1]; }
        if (key.equals("reps")) { return record[2]; }
        if (key.equals("setInterval")) { return record[3] == null ? null : record[3].slice(null, null); }
        return null;
    }
}
