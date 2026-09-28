package com.example.gymapp.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutNotificationContentTest {
    private val exercises = listOf(
        WorkoutNotificationExercise(
            "Bench Press",
            listOf(
                WorkoutNotificationSet("b1", 60.0, 8, completed = true),
                WorkoutNotificationSet("b2", 60.0, 8, completed = true)
            )
        ),
        WorkoutNotificationExercise(
            "Squat",
            listOf(
                WorkoutNotificationSet("s1", 100.0, 5, completed = true),
                WorkoutNotificationSet("s2", 102.5, 5, completed = false),
                WorkoutNotificationSet("s3", 102.5, 5, completed = false)
            )
        )
    )

    private fun content(restEndsAt: Long? = null, live: Boolean = false, list: List<WorkoutNotificationExercise> = exercises) =
        activeWorkoutNotificationContent(
            sessionStartedAt = 1_000L,
            revision = 7L,
            exercises = list,
            restEndsAt = restEndsAt,
            nowMillis = 10_000L,
            isLiveWorkout = live
        )

    @Test
    fun showsTheFirstUnfinishedSetOfTheCurrentExercise() {
        val content = content()
        assertEquals("Squat", content.exerciseName)
        assertEquals(2, content.setNumber)
        assertEquals(3, content.setCount)
        assertEquals(3, content.completedSets)
        assertEquals(5, content.totalSets)
        assertEquals("s2", content.nextSetId)
        assertEquals(102.5, content.nextWeight!!, 0.0)
        assertEquals(5, content.nextReps)
        assertEquals(7L, content.revision)
        assertTrue(content.canLogSet)
    }

    @Test
    fun restIsShownOnlyWhileItIsStillRunning() {
        assertEquals(20_000L, content(restEndsAt = 20_000L).restEndsAt)
        assertNull(content(restEndsAt = 9_000L).restEndsAt)
        assertNull(content().restEndsAt)
    }

    @Test
    fun liveRoomsAndFinishedWorkoutsOfferNoLogAction() {
        assertFalse(content(live = true).canLogSet)
        val done = exercises.map { exercise -> exercise.copy(sets = exercise.sets.map { it.copy(completed = true) }) }
        val finished = content(list = done)
        assertNull(finished.nextSetId)
        assertNull(finished.exerciseName)
        assertEquals(0, finished.setNumber)
        assertFalse(finished.canLogSet)
    }
}
