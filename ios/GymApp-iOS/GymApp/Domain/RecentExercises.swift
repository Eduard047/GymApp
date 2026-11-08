import Foundation

/// One logged exercise block, flattened for the picker's "Recent" rules (shared/recent-exercises-v1.json).
/// Android feeds one row per set; sets of one block collapse to the same position, so a block row
/// is equivalent.
struct RecentExerciseRow<ExerciseID: Hashable> {
    let exerciseID: ExerciseID
    /// Tie-break between sessions with the same date: the higher value is the newer session.
    let sessionID: Int
    let date: Double
    let blockOrderIndex: Int
}

enum GymRecentExercises {
    /// Most exercises shown in the picker's "Recent" section.
    static let maxCount = 8

    /// Same rules as Android `recentExerciseIds`: sessions newest first (date desc, ties: higher
    /// session id), exercises inside a session by block order, each exercise once at its first
    /// position, only exercises the picker lists (`pickerIDs`) and they do not use up a slot when
    /// skipped, at most `limit`. A non-blank `query` hides the section (empty result).
    static func ids<ExerciseID: Hashable>(
        history: [RecentExerciseRow<ExerciseID>],
        pickerIDs: Set<ExerciseID>,
        query: String = "",
        limit: Int = maxCount
    ) -> [ExerciseID] {
        guard limit > 0,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !history.isEmpty, !pickerIDs.isEmpty else { return [] }
        var best: [ExerciseID: (row: RecentExerciseRow<ExerciseID>, firstSeen: Int)] = [:]
        for (position, row) in history.enumerated() where pickerIDs.contains(row.exerciseID) {
            if let current = best[row.exerciseID] {
                if isNewer(row, than: current.row) { best[row.exerciseID] = (row, current.firstSeen) }
            } else {
                best[row.exerciseID] = (row, position)
            }
        }
        return best.values
            .sorted { lhs, rhs in
                if lhs.row.date != rhs.row.date { return lhs.row.date > rhs.row.date }
                if lhs.row.sessionID != rhs.row.sessionID { return lhs.row.sessionID > rhs.row.sessionID }
                if lhs.row.blockOrderIndex != rhs.row.blockOrderIndex {
                    return lhs.row.blockOrderIndex < rhs.row.blockOrderIndex
                }
                return lhs.firstSeen < rhs.firstSeen
            }
            .prefix(limit)
            .map(\.row.exerciseID)
    }

    /// Same rules over the stored (completed) workouts in one pass. A workout's position in
    /// `workouts` (append order) is its session id, so a later-stored workout wins a date tie.
    /// Blocks without sets are skipped, like Android which has no row for them.
    static func ids(
        workouts: [WorkoutSession],
        pickerIDs: Set<UUID>,
        query: String = "",
        limit: Int = maxCount
    ) -> [UUID] {
        var rows: [RecentExerciseRow<UUID>] = []
        for (sessionIndex, workout) in workouts.enumerated() {
            let date = workout.date.timeIntervalSinceReferenceDate
            for (blockIndex, block) in workout.exercises.enumerated()
            where !block.sets.isEmpty && pickerIDs.contains(block.exerciseID) {
                rows.append(RecentExerciseRow(
                    exerciseID: block.exerciseID,
                    sessionID: sessionIndex,
                    date: date,
                    blockOrderIndex: blockIndex
                ))
            }
        }
        return ids(history: rows, pickerIDs: pickerIDs, query: query, limit: limit)
    }

    private static func isNewer<ExerciseID>(
        _ lhs: RecentExerciseRow<ExerciseID>,
        than rhs: RecentExerciseRow<ExerciseID>
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.sessionID != rhs.sessionID { return lhs.sessionID > rhs.sessionID }
        return lhs.blockOrderIndex < rhs.blockOrderIndex
    }
}
