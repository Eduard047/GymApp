using Toybox.Lang as Lang;

class GymPlanAccess {
    static function size(value) { return value.size(); }

    (:fullLegacyState, :inline)
    static function at(value, index) { return value[index]; }

    (:compactLegacyState, :inline)
    static function at(value, index) {
        return value instanceof GymPlanList ? value.at(index) : value[index];
    }

    (:fullLegacyState, :inline)
    static function nameAt(value, index) {
        var item = value[index];
        return GymStore.isSetRecord(item) ? GymStore.setField(item, "exerciseName") : null;
    }

    (:compactLegacyState, :inline)
    static function nameAt(value, index) {
        if (value instanceof GymPlanList) { return value.columns[1][index]; }
        var item = value[index];
        return GymStore.isSetRecord(item) ? GymStore.setField(item, "exerciseName") : null;
    }

    (:fullLegacyState, :inline)
    static function valid(value, maximum, allowEmpty) { return false; }

    (:compactLegacyState, :inline)
    static function valid(value, maximum, allowEmpty) {
        return value instanceof GymPlanList && value.valid(maximum, allowEmpty);
    }
}

(:compactLegacyState)
class GymPlanList {
    var columns;
    var cachedIndex;
    var cachedRow;

    function initialize(savedColumns) {
        columns = savedColumns;
        cachedIndex = -1;
        cachedRow = null;
    }

    function size() { return columns[1].size(); }

    function valid(maximum, allowEmpty) {
        if (!(columns instanceof Lang.Array) || columns.size() != 4 ||
            !(columns[0] instanceof Lang.Number) || columns[0] != 5 ||
            !(columns[1] instanceof Lang.Array) ||
            (!allowEmpty && columns[1].size() == 0)) { return false; }
        return GymStore.isValidPlanColumns(
            columns[1], columns[2], columns[3], maximum
        );
    }

    function at(index) {
        if (index < 0 || index >= size()) { return null; }
        if (cachedIndex != index) {
            cachedRow = {
                "exerciseName" => columns[1][index],
                "weight" => columns[2][index],
                "reps" => columns[3][index]
            };
            cachedIndex = index;
        }
        return cachedRow;
    }

}
