package com.example.gymapp.ui.screens

/**
 * Past-workout search by exercise name (shared/history-exercise-search-v1.json).
 *
 * The query is trimmed; a blank query returns [workouts] unchanged. A workout matches when ANY of its
 * stored exercise names matches the trimmed query with the exercise-picker matcher
 * ([exerciseNameMatchesLocalizedQuery]: same normalization, aliases, transliteration, tokens and
 * muscle/equipment terms as the picker). Order of [workouts] is kept; runs on the full set, before any
 * week/month grouping.
 */
internal fun <T> filterWorkoutsByExerciseQuery(
    workouts: List<T>,
    query: String,
    exerciseNames: (T) -> List<String>
): List<T> {
    val trimmed = query.trim()
    if (trimmed.isEmpty()) return workouts
    // The matcher is heavy: evaluate it once per distinct exercise name, not once per workout.
    val matchByName = HashMap<String, Boolean>()
    return workouts.filter { workout ->
        exerciseNames(workout).any { name ->
            matchByName.getOrPut(name) { exerciseNameMatchesLocalizedQuery(name, trimmed) }
        }
    }
}

/** UIs render at most this many of the newest matches (the filter itself is uncapped). */
internal const val HISTORY_SEARCH_DISPLAY_LIMIT = 30
