import Foundation

struct WeeklyReview {
    struct Insight: Identifiable {
        var id: UUID { current.exerciseID }
        let previous: ExerciseHistoryEntry
        let current: ExerciseHistoryEntry
    }
    let start: Date
    let end: Date
    let partial: Bool
    let trainingDays: Int
    let sessions: [ExerciseHistoryEntry]
    let comparableCount: Int
    let insights: [Insight]

    /// Entries with `lower <= sessionDate <= throughInclusive` and `sessionDate < beforeExclusive`,
    /// found by binary search. `history` must be sorted by `sessionDate`, newest first.
    static func window(
        _ history: [ExerciseHistoryEntry],
        from lower: Date,
        through upperInclusive: Date,
        before upperExclusive: Date
    ) -> ArraySlice<ExerciseHistoryEntry> {
        func partitionPoint(_ isBefore: (Date) -> Bool) -> Int {
            var low = 0, high = history.count
            while low < high {
                let mid = (low + high) / 2
                if isBefore(history[mid].sessionDate) { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let start = partitionPoint { $0 > upperInclusive || $0 >= upperExclusive }
        let end = partitionPoint { $0 >= lower }
        return history[start ..< max(start, end)]
    }

    /// Pass `historySortedNewestFirst: true` only for `allExerciseHistory()`-style input;
    /// it narrows the scan to the two-week window without changing the result.
    static func build(_ history: [ExerciseHistoryEntry], offset: Int = 0, now: Date = Date(), calendar: Calendar = .current, historySortedNewestFirst: Bool = false) -> WeeklyReview {
        var calendar = calendar
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let start = calendar.date(byAdding: .day, value: min(0, max(-520, offset)) * 7, to: monday)!
        let until = calendar.date(byAdding: .day, value: 7, to: start)!
        let before = calendar.date(byAdding: .day, value: -7, to: start)!
        let candidates: ArraySlice<ExerciseHistoryEntry> = historySortedNewestFirst
            ? window(history, from: before, through: now, before: until)
            : history[...]
        let valid = candidates.filter { $0.sessionDate <= now && $0.sessionDate >= before && $0.sessionDate < until &&
            $0.weight.isFinite && (0 ... 1_000_000).contains($0.weight) && (1 ... 10_000).contains($0.reps) }
        let current = valid.filter { $0.sessionDate >= start }
        let previous = valid.filter { $0.sessionDate < start }
        struct Key: Hashable { let exercise: UUID; let weight: Double }
        func best(_ rows: [ExerciseHistoryEntry]) -> [Key: ExerciseHistoryEntry] {
            Dictionary(grouping: rows, by: { Key(exercise: $0.exerciseID, weight: $0.weight) }).mapValues { sets in
                sets.max { a, b in
                    if a.reps != b.reps { return a.reps < b.reps }
                    if a.sessionDate != b.sessionDate { return a.sessionDate < b.sessionDate }
                    return a.setID.uuidString < b.setID.uuidString
                }!
            }
        }
        let previousBest = best(previous)
        let comparisons = best(current).compactMap { key, set in previousBest[key].map { Insight(previous: $0, current: set) } }
        var seen = Set<UUID>()
        let insights = comparisons.filter { $0.current.reps != $0.previous.reps }.sorted { a, b in
            let ad = abs(a.current.reps - a.previous.reps), bd = abs(b.current.reps - b.previous.reps)
            if ad != bd { return ad > bd }
            if a.current.exerciseID != b.current.exerciseID { return a.current.exerciseID.uuidString < b.current.exerciseID.uuidString }
            return a.current.weight < b.current.weight
        }.filter { seen.insert($0.current.exerciseID).inserted }
        let sessions = Dictionary(grouping: current, by: \.workoutID).values.compactMap(\.first).sorted { $0.sessionDate > $1.sessionDate }
        return WeeklyReview(start: start, end: calendar.date(byAdding: .day, value: -1, to: until)!, partial: offset == 0,
            trainingDays: Set(current.map { calendar.startOfDay(for: $0.sessionDate) }).count,
            sessions: sessions, comparableCount: comparisons.count, insights: Array(insights.prefix(3)))
    }
}
