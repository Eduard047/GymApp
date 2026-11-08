import Foundation

/// One logged set reduced to what the untrained-muscles hint needs: its date, reps and the
/// contribution weight of each muscle it trains.
struct UntrainedMuscleSet: Equatable, Sendable {
    let date: Date
    let reps: Int
    let muscles: [String: Double]
}

/// shared/untrained-muscles-v1.json, identical to Android's `untrainedMuscleIds`.
enum GymUntrainedMuscles {
    /// Major muscles the hint can name, in heatmap display order. This is the set the Balance
    /// recommendation already watches; the heatmap has no coarser groups.
    static let majorMuscleIDs = ["chest", "lats", "upperBack", "glutes", "quads", "hamstrings"]
    static let minWorkouts = 3
    static let recentWorkoutDays = 30
    static let untrainedDays = 10
    static let maxGroups = 3

    /// Ids of major muscles with no training for 10+ local days (or never), never-trained first then
    /// longest untrained first, ties in display order, at most 3. Empty for a user with fewer than 3
    /// workouts or no workout in the last 30 days. Only sets with reps > 0 and a positive
    /// contribution weight count as training.
    static func untrainedMuscleIDs(
        workoutDates: [Date],
        sets: [UntrainedMuscleSet],
        now: Date,
        calendar: Calendar
    ) -> [String] {
        guard workoutDates.count >= minWorkouts else { return [] }
        let today = calendar.startOfDay(for: now)
        func daysSince(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
        }
        guard workoutDates.contains(where: { daysSince($0) <= recentWorkoutDays }) else { return [] }

        var lastTrained: [String: Date] = [:]
        for set in sets where set.reps > 0 {
            for (muscleID, weight) in set.muscles
            where weight > 0 && majorMuscleIDs.contains(muscleID) {
                if let previous = lastTrained[muscleID], previous >= set.date { continue }
                lastTrained[muscleID] = set.date
            }
        }

        var candidates: [(index: Int, id: String, days: Int)] = []
        for (index, muscleID) in majorMuscleIDs.enumerated() {
            let days = lastTrained[muscleID].map(daysSince) ?? Int.max
            if days >= untrainedDays {
                candidates.append((index, muscleID, days))
            }
        }
        candidates.sort { lhs, rhs in
            lhs.days != rhs.days ? lhs.days > rhs.days : lhs.index < rhs.index
        }
        return candidates.prefix(maxGroups).map(\.id)
    }

    /// Builds the hint's muscle ids from the full history. Cheap single pass; the muscle lookup is
    /// cached per exercise name.
    static func hintMuscleIDs(
        history: [ExerciseHistoryEntry],
        workoutDates: [Date],
        mappings: [ExerciseMuscleMapping],
        now: Date,
        calendar: Calendar
    ) -> [String] {
        guard workoutDates.count >= minWorkouts else { return [] }
        let manualMappings = MuscleMappingEngine.manualContributionMap(from: mappings)
        var musclesByExercise: [String: [String: Double]] = [:]
        var sets: [UntrainedMuscleSet] = []
        sets.reserveCapacity(history.count)
        for entry in history where entry.reps > 0 {
            let muscles: [String: Double]
            if let cached = musclesByExercise[entry.exerciseName] {
                muscles = cached
            } else {
                var map: [String: Double] = [:]
                for contribution in MuscleMappingEngine.contributions(
                    for: entry.exerciseName,
                    manualMappings: manualMappings
                ) where majorMuscleIDs.contains(contribution.muscleID) {
                    map[contribution.muscleID] = contribution.weight
                }
                musclesByExercise[entry.exerciseName] = map
                muscles = map
            }
            if !muscles.isEmpty {
                sets.append(UntrainedMuscleSet(date: entry.sessionDate, reps: entry.reps, muscles: muscles))
            }
        }
        return untrainedMuscleIDs(workoutDates: workoutDates, sets: sets, now: now, calendar: calendar)
    }
}
