import Foundation

/// A watch workout (Apple Watch, Garmin) that reaches the phone after the user already saved the
/// same session on the phone would otherwise be stored twice. Pure so the rule is unit-tested
/// without the services or the store.
enum LateWatchArrivalDecision: Equatable {
    /// Store the arrival as before (also when it overlaps a workout that differs from it).
    case store
    /// Store nothing: a stored workout already holds this session. The caller still commits its
    /// receipt and sends a positive acknowledgement so the watch clears its queue.
    case skip
}

struct LateWatchArrivalSet: Equatable, Sendable {
    let exerciseName: String
    let weight: Double
    let reps: Int
}

struct LateWatchArrivalStoredWorkout: Equatable, Sendable {
    let startMillis: Int64
    let durationSeconds: Int?
    let sets: [LateWatchArrivalSet]
}

enum LateWatchArrivalRule {
    /// - Activity-only arrival (no sets): `.skip` only when a stored workout with sets and a
    ///   positive duration really covers it: their actual time intersection (no tolerance) is at
    ///   least half the arrival's duration (a zero-length arrival must lie inside it). A separate
    ///   back-to-back session (phone 10:00-11:00, watch run 11:01-11:31) is stored, and a stored
    ///   workout without a duration never causes this skip. Only the arrival's watch metrics are
    ///   not kept; the stored workout keeps its own.
    /// - Arrival with sets overlapping a stored workout with exactly the same sets (names
    ///   trimmed and case-folded, weight, reps, order within each exercise): `.skip`. Overlap here
    ///   is the Health import rule (`HealthImportRules.overlaps`, 120 s tolerance).
    /// - Anything else, including an overlapping workout with different sets: `.store`.
    static func decide(
        startMillis: Int64,
        endMillis: Int64,
        sets: [LateWatchArrivalSet],
        stored: [LateWatchArrivalStoredWorkout]
    ) -> LateWatchArrivalDecision {
        let end = max(endMillis, startMillis)
        if sets.isEmpty {
            let covered = stored.contains { workout in
                !workout.sets.isEmpty && coversActivity(startMillis: startMillis, endMillis: end, workout: workout)
            }
            return covered ? .skip : .store
        }
        let arrivalSets = canonical(sets)
        let covered = stored.contains { workout in
            guard !workout.sets.isEmpty,
                  HealthImportRules.overlaps(
                      startMillis: startMillis,
                      endMillis: end,
                      existing: HealthImportExistingWorkout(
                          startMillis: workout.startMillis,
                          durationSeconds: workout.durationSeconds
                      )
                  ) else {
                return false
            }
            return canonical(workout.sets) == arrivalSets
        }
        return covered ? .skip : .store
    }

    /// Whether `workout` really holds an activity-only arrival: the actual intersection of the
    /// two intervals (no tolerance) is at least half the arrival's duration. A zero-length
    /// arrival must lie inside the stored workout. A stored workout without a positive duration
    /// never covers anything.
    private static func coversActivity(
        startMillis: Int64,
        endMillis: Int64,
        workout: LateWatchArrivalStoredWorkout
    ) -> Bool {
        guard let seconds = workout.durationSeconds, seconds > 0 else { return false }
        let storedStart = workout.startMillis
        let (length, lengthOverflow) = Int64(seconds).multipliedReportingOverflow(by: 1_000)
        let (sum, sumOverflow) = storedStart.addingReportingOverflow(length)
        let storedEnd = (lengthOverflow || sumOverflow) ? Int64.max : sum
        let (arrivalLength, arrivalOverflow) = endMillis.subtractingReportingOverflow(startMillis)
        if arrivalOverflow { return false }
        if arrivalLength <= 0 { return startMillis >= storedStart && startMillis <= storedEnd }
        let (intersection, intersectionOverflow) = min(endMillis, storedEnd)
            .subtractingReportingOverflow(max(startMillis, storedStart))
        if intersectionOverflow || intersection <= 0 { return false }
        return intersection >= arrivalLength - arrivalLength / 2
    }

    /// The store's workouts in the rule's shape; set names are resolved through the store's
    /// exercise list (an unknown exercise id becomes an empty name, which never matches a
    /// watch set because watch sets always carry a name).
    static func storedWorkouts(
        _ workouts: [WorkoutSession],
        exerciseNames: [UUID: String]
    ) -> [LateWatchArrivalStoredWorkout] {
        workouts.map { workout in
            LateWatchArrivalStoredWorkout(
                startMillis: workout.date.gymEpochMilliseconds,
                durationSeconds: workout.durationSeconds,
                sets: workout.exercises.flatMap { block in
                    block.sets.map {
                        LateWatchArrivalSet(
                            exerciseName: exerciseNames[block.exerciseID] ?? "",
                            weight: $0.weight,
                            reps: $0.reps
                        )
                    }
                }
            )
        }
    }

    private struct CanonicalSet: Equatable {
        let key: String
        let weight: Double
        let reps: Int
    }

    /// Sets grouped by exercise in first-appearance order, each exercise keeping its own set
    /// order: the store keeps one block per exercise, so an interleaved watch order (A, B, A)
    /// is stored as (A, A, B) and must still compare equal.
    private static func canonical(_ sets: [LateWatchArrivalSet]) -> [CanonicalSet] {
        var order: [String] = []
        var grouped: [String: [CanonicalSet]] = [:]
        for set in sets {
            let key = set.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(.init(key: key, weight: set.weight == 0 ? 0 : set.weight, reps: set.reps))
        }
        return order.flatMap { grouped[$0] ?? [] }
    }
}
