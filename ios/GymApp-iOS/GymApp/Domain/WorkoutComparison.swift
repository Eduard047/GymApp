import Foundation

/// One compared number: the current workout against the previous matching one.
struct WorkoutComparisonMetric: Equatable {
    let current: Double
    let previous: Double
    /// Differences smaller than this are shown as "no change" (0 for whole counts,
    /// half of the displayed decimal step for volume).
    let tolerance: Double

    var delta: Double { current - previous }
    var isUnchanged: Bool { abs(delta) <= tolerance }
}

/// Sets, reps and volume of a saved workout against the previous workout that trained
/// exactly the same exercises. Mirrors the Android and web rule.
struct WorkoutComparison: Equatable {
    let previousWorkoutID: UUID
    let previousDate: Date
    let matchedExerciseCount: Int
    let sets: WorkoutComparisonMetric
    let reps: WorkoutComparisonMetric
    let volume: WorkoutComparisonMetric
}

enum WorkoutComparisonEngine {
    private struct Snapshot {
        let id: UUID
        let date: Date
        let exerciseSignature: [String]
        let setCount: Int
        let totalReps: Int
        let totalVolume: Double
    }

    /// Finds the latest earlier workout whose set of exercises equals the current one.
    ///
    /// - Exercises match by catalog key (built-in) or normalized name (custom), counting
    ///   only exercises that have at least one recorded set, each exercise once.
    /// - "Earlier" means an older date, or the same date with a smaller id; the newest
    ///   such workout wins (ties broken by id) so the result is deterministic.
    /// - A workout without sets, or with an unreadable weight or rep count, never
    ///   matches and never has a comparison.
    /// Reads only the already-loaded local workouts and exercise list.
    static func comparison(
        for workoutID: UUID,
        workouts: [WorkoutSession],
        exercises: [Exercise]
    ) -> WorkoutComparison? {
        let limits = BackupImportLimits.standard
        guard workouts.count <= limits.maximumSessions,
              let currentWorkout = workouts.first(where: { $0.id == workoutID }) else { return nil }
        var keysByExerciseID: [UUID: String] = [:]
        keysByExerciseID.reserveCapacity(exercises.count)
        for exercise in exercises {
            keysByExerciseID[exercise.id] = FriendGhosts.exerciseKey(
                catalogKey: exercise.catalogKey,
                name: exercise.name
            )
        }
        guard let current = snapshot(of: currentWorkout, keys: keysByExerciseID, limits: limits) else {
            return nil
        }
        var previous: Snapshot?
        for candidate in workouts where candidate.id != current.id {
            guard isEarlier(candidate.date, candidate.id, than: current.date, current.id),
                  previous.map({ isEarlier($0.date, $0.id, than: candidate.date, candidate.id) }) ?? true,
                  let snapshot = snapshot(of: candidate, keys: keysByExerciseID, limits: limits),
                  snapshot.exerciseSignature == current.exerciseSignature else { continue }
            previous = snapshot
        }
        guard let previous else { return nil }
        return WorkoutComparison(
            previousWorkoutID: previous.id,
            previousDate: previous.date,
            matchedExerciseCount: current.exerciseSignature.count,
            sets: WorkoutComparisonMetric(
                current: Double(current.setCount),
                previous: Double(previous.setCount),
                tolerance: 0
            ),
            reps: WorkoutComparisonMetric(
                current: Double(current.totalReps),
                previous: Double(previous.totalReps),
                tolerance: 0
            ),
            volume: WorkoutComparisonMetric(
                current: current.totalVolume,
                previous: previous.totalVolume,
                tolerance: 0.05
            )
        )
    }

    private static func isEarlier(_ date: Date, _ id: UUID, than otherDate: Date, _ otherID: UUID) -> Bool {
        date < otherDate || (date == otherDate && id.uuidString < otherID.uuidString)
    }

    private static func snapshot(
        of workout: WorkoutSession,
        keys: [UUID: String],
        limits: BackupImportLimits
    ) -> Snapshot? {
        guard !workout.exercises.isEmpty,
              workout.exercises.count <= limits.maximumExercisesPerSession else { return nil }
        var signature = Set<String>()
        var setCount = 0
        var totalReps = 0
        var totalVolume = 0.0
        for block in workout.exercises where !block.sets.isEmpty {
            guard let key = keys[block.exerciseID],
                  block.sets.count <= limits.maximumSetsPerExercise else { return nil }
            signature.insert(key)
            for set in block.sets {
                guard set.weight.isFinite, set.weight >= 0, set.reps >= 0 else { return nil }
                setCount += 1
                totalReps += set.reps
                totalVolume += set.weight * Double(set.reps)
            }
        }
        guard setCount > 0, totalVolume.isFinite else { return nil }
        return Snapshot(
            id: workout.id,
            date: workout.date,
            exerciseSignature: signature.sorted(),
            setCount: setCount,
            totalReps: totalReps,
            totalVolume: totalVolume
        )
    }
}
