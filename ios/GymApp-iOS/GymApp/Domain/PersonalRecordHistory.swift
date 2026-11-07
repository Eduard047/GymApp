import Foundation

/// What a historical record beat; a set that beats both is reported as `.weight`.
enum PersonalRecordHistoryKind: String, Equatable, Sendable {
    case weight
    case estimatedOneRepMax
}

/// One set that broke the exercise's record when it was logged.
struct PersonalRecordHistoryEvent: Identifiable, Equatable, Sendable {
    var id: UUID { setID }
    let setID: UUID
    let workoutID: UUID
    let date: Date
    let weight: Double
    let reps: Int
    let setOrderIndex: Int
    let kind: PersonalRecordHistoryKind
}

/// Replays one exercise's whole history in date order with the live-PR rules
/// (`LivePersonalRecords.evaluate` / `advanced`): the first session only sets the
/// baseline (it never holds a record, even when every set is 0 kg), a 0 kg set is
/// never a record, a tie is not a record, and each set is compared with the best of
/// everything logged before it (earlier sessions and earlier sets of its own session, walked
/// block by block like the stored workout's record chips: block index, then set index).
/// Same shared fixture as Android: shared/pr-history-v1.json.
enum PersonalRecordHistory {
    /// The most records the progress screen ever lists.
    static let maximumCount = 50

    /// At most `limit` events, newest first.
    static func replay(_ history: [ExerciseHistoryEntry], limit: Int = maximumCount) -> [PersonalRecordHistoryEvent] {
        guard !history.isEmpty, limit > 0 else { return [] }
        let sessions = Dictionary(grouping: history, by: \.workoutID).values.sorted { left, right in
            let leftDate = left[0].sessionDate
            let rightDate = right[0].sessionDate
            if leftDate != rightDate { return leftDate < rightDate }
            return left[0].workoutID.uuidString < right[0].workoutID.uuidString
        }

        var best: PersonalRecordBaseline?
        var events: [PersonalRecordHistoryEvent] = []
        for session in sessions {
            let isBaseline = best == nil
            var running = best ?? PersonalRecordBaseline(bestWeight: 0, bestEstimatedOneRepMax: 0)
            let sets = session.sorted { left, right in
                if left.blockOrderIndex != right.blockOrderIndex { return left.blockOrderIndex < right.blockOrderIndex }
                if left.setOrderIndex != right.setOrderIndex { return left.setOrderIndex < right.setOrderIndex }
                return left.setID.uuidString < right.setID.uuidString
            }
            for set in sets {
                if !isBaseline, set.weight > 0 {
                    let result = LivePersonalRecords.evaluate(weight: set.weight, reps: set.reps, against: running)
                    if result.weight || result.estimatedOneRepMax {
                        events.append(
                            PersonalRecordHistoryEvent(
                                setID: set.setID,
                                workoutID: set.workoutID,
                                date: set.sessionDate,
                                weight: set.weight,
                                reps: set.reps,
                                setOrderIndex: set.setOrderIndex,
                                kind: result.weight ? .weight : .estimatedOneRepMax
                            )
                        )
                    }
                }
                running = LivePersonalRecords.advanced(running, weight: set.weight, reps: set.reps)
            }
            best = running
        }
        return Array(events.reversed().prefix(limit))
    }
}
