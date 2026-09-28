package com.example.gymapp.service

/** One set of the running workout, as the notification needs it. */
internal data class WorkoutNotificationSet(
    val id: String,
    val weight: Double,
    val reps: Int,
    val completed: Boolean
)

internal data class WorkoutNotificationExercise(
    val name: String,
    val sets: List<WorkoutNotificationSet>
)

/**
 * What the ongoing "active workout" notification shows, the Android counterpart of the iOS Live
 * Activity: the current exercise, "Set N of M", overall progress, and either the rest countdown or
 * the next set. The Log set action carries the exact set and workout revision it was built for, so
 * a repeated or stale tap cannot record another set; Skip rest carries the rest deadline it ends.
 */
internal data class ActiveWorkoutNotificationContent(
    val sessionStartedAt: Long,
    val revision: Long,
    val exerciseName: String?,
    val setNumber: Int,
    val setCount: Int,
    val completedSets: Int,
    val totalSets: Int,
    val nextSetId: String?,
    val nextWeight: Double?,
    val nextReps: Int?,
    /** Set only while a rest timer is still running. */
    val restEndsAt: Long?,
    /** Live rooms record through the room's sync, which only the app screen can do. */
    val canLogSet: Boolean
)

internal fun activeWorkoutNotificationContent(
    sessionStartedAt: Long,
    revision: Long,
    exercises: List<WorkoutNotificationExercise>,
    restEndsAt: Long?,
    nowMillis: Long,
    isLiveWorkout: Boolean
): ActiveWorkoutNotificationContent {
    val currentExercise = exercises.firstOrNull { exercise -> exercise.sets.any { !it.completed } }
    val currentIndex = currentExercise?.sets?.indexOfFirst { !it.completed } ?: -1
    val currentSet = currentExercise?.sets?.getOrNull(currentIndex)
    val allSets = exercises.flatMap { it.sets }
    return ActiveWorkoutNotificationContent(
        sessionStartedAt = sessionStartedAt,
        revision = revision,
        exerciseName = currentExercise?.name,
        setNumber = currentIndex + 1,
        setCount = currentExercise?.sets?.size ?: 0,
        completedSets = allSets.count { it.completed },
        totalSets = allSets.size,
        nextSetId = currentSet?.id,
        nextWeight = currentSet?.weight,
        nextReps = currentSet?.reps,
        restEndsAt = restEndsAt?.takeIf { it > nowMillis },
        canLogSet = currentSet != null && !isLiveWorkout
    )
}
