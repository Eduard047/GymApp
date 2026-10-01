import Foundation

/// Epley one-rep-max estimate. Live records, the post-workout summary, and
/// history models all use this single formula so their records never diverge.
enum GymOneRepMax {
    static func estimate(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }
}

/// History-only bests for one exercise, taken before the current workout.
struct PersonalRecordBaseline: Equatable, Sendable {
    let bestWeight: Double
    let bestEstimatedOneRepMax: Double
}

/// Detects personal records while a workout is running.
///
/// Rules: an exercise needs logged history (its first session never sets a
/// record); a 0 kg set is never a record; matching the best is not a record;
/// and each set is compared with the better of the history best and every set
/// recorded earlier in this workout. Records are derived from the draft rather
/// than stored, so undoing a set removes its record as well.
enum LivePersonalRecords {
    /// Tolerance for comparing estimates computed from different weight/rep pairs.
    static let estimateTolerance = 1e-9

    /// Which record kinds one set achieves against the best seen so far. A 0 kg
    /// set never qualifies. Weight must be strictly greater; the estimate must
    /// exceed the best by more than `estimateTolerance`.
    static func evaluate(
        weight: Double,
        reps: Int,
        against best: PersonalRecordBaseline
    ) -> (weight: Bool, estimatedOneRepMax: Bool) {
        guard weight > 0 else { return (false, false) }
        let estimate = GymOneRepMax.estimate(weight: weight, reps: reps)
        return (
            weight > best.bestWeight,
            estimate > best.bestEstimatedOneRepMax + estimateTolerance
        )
    }

    /// The running best after a set has been performed.
    static func advanced(
        _ best: PersonalRecordBaseline,
        weight: Double,
        reps: Int
    ) -> PersonalRecordBaseline {
        guard weight > 0 else { return best }
        return PersonalRecordBaseline(
            bestWeight: max(best.bestWeight, weight),
            bestEstimatedOneRepMax: max(
                best.bestEstimatedOneRepMax,
                GymOneRepMax.estimate(weight: weight, reps: reps)
            )
        )
    }

    static func baselines(history: [ExerciseHistoryEntry]) -> [UUID: PersonalRecordBaseline] {
        Dictionary(grouping: history, by: \.exerciseID).mapValues { entries in
            PersonalRecordBaseline(
                bestWeight: entries.map(\.weight).max() ?? 0,
                bestEstimatedOneRepMax: entries.map(\.estimatedOneRepMax).max() ?? 0
            )
        }
    }

    static func recordSetIDs(
        in draft: ActiveWorkoutDraft,
        baselines: [UUID: PersonalRecordBaseline]
    ) -> Set<UUID> {
        var completed: [CompletedSet] = []
        for (exerciseIndex, exercise) in draft.exercises.enumerated() {
            for (setIndex, set) in exercise.sets.enumerated() {
                guard let completedAt = set.completedAt else { continue }
                completed.append(
                    CompletedSet(
                        exerciseID: exercise.exerciseID,
                        set: set,
                        completedAt: completedAt,
                        exerciseIndex: exerciseIndex,
                        setIndex: setIndex
                    )
                )
            }
        }
        completed.sort { (left: CompletedSet, right: CompletedSet) -> Bool in
            if left.completedAt != right.completedAt {
                return left.completedAt < right.completedAt
            }
            if left.exerciseIndex != right.exerciseIndex {
                return left.exerciseIndex < right.exerciseIndex
            }
            return left.setIndex < right.setIndex
        }

        var bests = baselines
        var records = Set<UUID>()
        for entry in completed {
            guard entry.set.weight > 0, let best = bests[entry.exerciseID] else { continue }
            let result = evaluate(weight: entry.set.weight, reps: entry.set.reps, against: best)
            if result.weight || result.estimatedOneRepMax {
                records.insert(entry.set.id)
            }
            bests[entry.exerciseID] = advanced(best, weight: entry.set.weight, reps: entry.set.reps)
        }
        return records
    }

    private struct CompletedSet {
        let exerciseID: UUID
        let set: ActiveWorkoutSet
        let completedAt: Date
        let exerciseIndex: Int
        let setIndex: Int
    }
}
