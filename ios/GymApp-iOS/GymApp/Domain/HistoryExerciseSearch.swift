import Foundation

/// Past-workout search by exercise name (shared/history-exercise-search-v1.json).
///
/// The query is trimmed; a blank query returns the workouts unchanged. A workout matches when ANY of
/// its stored exercise names matches the trimmed query with the exercise-picker matcher
/// (`ExerciseFilterEngine`, the twin of Android `exerciseNameMatchesLocalizedQuery`). The input order
/// is kept; the filter itself is uncapped, UIs render at most `displayLimit` of the newest matches.
enum HistoryExerciseSearch {
    static let displayLimit = 30
    /// Same cap as the exercise picker's query.
    static let maximumQueryCharacters = 256

    static func filter<T>(
        _ workouts: [T],
        query: String,
        exerciseNames: (T) -> [String]
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return workouts }
        // The matcher is heavy: evaluate it once per distinct exercise name, not once per workout.
        var matchByName: [String: Bool] = [:]
        return workouts.filter { workout in
            exerciseNames(workout).contains { name in
                if let cached = matchByName[name] { return cached }
                let matches = exerciseNameMatches(name, query: trimmed)
                matchByName[name] = matches
                return matches
            }
        }
    }

    private static func exerciseNameMatches(_ name: String, query: String) -> Bool {
        !ExerciseFilterEngine.filtered(
            exercises: [Exercise(name: name)],
            query: query,
            bodyFilter: .all,
            muscleFilter: nil,
            favoritesOnly: false,
            sortMode: .name,
            muscleMappings: [],
            sessionCounts: [:]
        ).isEmpty
    }
}
