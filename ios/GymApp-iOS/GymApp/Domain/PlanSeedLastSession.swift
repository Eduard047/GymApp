import Foundation

/// One logged set, flattened for the plan-seed rules (shared/plan-seed-last-session-v1.json).
struct PlanSeedHistoryRow<ExerciseID: Hashable> {
    let exerciseID: ExerciseID
    /// Tie-break between sessions with the same date: the higher value is the newer session.
    let sessionID: Int
    let date: Double
    let blockOrderIndex: Int
    let setOrderIndex: Int
    let weight: Double
    let reps: Int
}

/// One set copied from the last session into a freshly picked plan card.
struct PlanSeedSet: Equatable {
    let weight: Double
    let reps: Int
}

enum GymPlanSeed {
    /// Most sets copied from the last session into a freshly picked card.
    static let maxSeedSets = 10

    /// Sets of the exercise's LAST completed session, for the picker's "add exercise" path.
    /// Same rules as Android `lastSessionSetSeed`: newest date wins (ties: highest session id),
    /// only the first block of the exercise in that session counts, sets go in set order,
    /// reps <= 0 are skipped, weight 0 is kept, at most `min(10, 100)` sets. Nil when there is
    /// nothing to copy, so the caller keeps the default one-set card.
    static func lastSessionSetSeed<ExerciseID: Hashable>(
        exerciseID: ExerciseID,
        history: [PlanSeedHistoryRow<ExerciseID>]
    ) -> [PlanSeedSet]? {
        let entries = history.filter { $0.exerciseID == exerciseID }
        guard let last = entries.max(by: { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : lhs.sessionID < rhs.sessionID
        }) else { return nil }
        let inSession = entries.filter { $0.date == last.date && $0.sessionID == last.sessionID }
        guard let firstBlock = inSession.map(\.blockOrderIndex).min() else { return nil }
        let limit = min(maxSeedSets, WorkoutEditorLimits.maxSetsPerExercise)
        let seed = inSession
            .filter { $0.blockOrderIndex == firstBlock && $0.reps > 0 }
            .sorted { $0.setOrderIndex < $1.setOrderIndex }
            .prefix(limit)
            .map { PlanSeedSet(weight: $0.weight, reps: $0.reps) }
        return seed.isEmpty ? nil : Array(seed)
    }

    /// Same rules over the stored workouts. A workout's position in `workouts` (append order)
    /// is its session id, so a later-stored workout wins a date tie. Only workouts that
    /// contain the exercise are flattened, so the scan stays one cheap pass.
    static func lastSessionSetSeed(
        exerciseID: UUID,
        workouts: [WorkoutSession]
    ) -> [PlanSeedSet]? {
        var rows: [PlanSeedHistoryRow<UUID>] = []
        for (sessionIndex, workout) in workouts.enumerated() {
            for (blockIndex, block) in workout.exercises.enumerated() where block.exerciseID == exerciseID {
                for (setIndex, set) in block.sets.enumerated() {
                    rows.append(PlanSeedHistoryRow(
                        exerciseID: exerciseID,
                        sessionID: sessionIndex,
                        date: workout.date.timeIntervalSinceReferenceDate,
                        blockOrderIndex: blockIndex,
                        setOrderIndex: setIndex,
                        weight: set.weight,
                        reps: set.reps
                    ))
                }
            }
        }
        return lastSessionSetSeed(exerciseID: exerciseID, history: rows)
    }

    /// Card for an exercise picked from the picker: seeded sets when the exercise has a
    /// completed session, otherwise one set of 10 reps with the last known weight.
    static func pickerDraft(exerciseID: UUID, workouts: [WorkoutSession], lastWeight: Double?)
        -> WorkoutEditorExerciseDraft {
        if let seed = lastSessionSetSeed(exerciseID: exerciseID, workouts: workouts) {
            return WorkoutEditorExerciseDraft(
                exerciseID: exerciseID,
                sets: seed.map { WorkoutEditorSetDraft(weight: $0.weight, reps: $0.reps) }
            )
        }
        return WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(weight: lastWeight ?? 0, reps: 10)]
        )
    }
}
