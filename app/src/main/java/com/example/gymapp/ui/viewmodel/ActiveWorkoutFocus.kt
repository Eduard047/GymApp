package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ActiveWorkoutDetails

/** What the Today focus card shows for a workout in progress. */
data class ActiveWorkoutFocus(
    /** Raw stored name of the first exercise that still has an open set. */
    val exerciseName: String?,
    /** One-based position of the first open set inside that exercise. */
    val currentSetNumber: Int,
    val completedSets: Int,
    val totalSets: Int
)

fun activeWorkoutFocus(details: ActiveWorkoutDetails?): ActiveWorkoutFocus? {
    details ?: return null
    val exercises = details.exercises.sortedBy { it.activeWorkoutExercise.orderIndex }
    val allSets = exercises.flatMap { it.sets }
    val current = exercises.firstOrNull { exercise -> exercise.sets.any { it.completedAt == null } }
    val setIndex = current
        ?.sets
        ?.sortedBy { it.orderIndex }
        ?.indexOfFirst { it.completedAt == null }
        ?: 0
    return ActiveWorkoutFocus(
        exerciseName = current?.activeWorkoutExercise?.exerciseName,
        currentSetNumber = setIndex.coerceAtLeast(0) + 1,
        completedSets = allSets.count { it.completedAt != null },
        totalSets = allSets.size
    )
}
