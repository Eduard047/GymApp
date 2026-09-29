package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseWithDetails
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ActiveWorkoutFocusTest {
    private fun exercise(id: String, name: String, order: Int, vararg done: Boolean) =
        ActiveWorkoutExerciseWithDetails(
            activeWorkoutExercise = ActiveWorkoutExerciseEntity(id, 1L, name, null, order),
            sets = done.mapIndexed { index, completed ->
                ActiveWorkoutSetEntity("$id-$index", id, 50.0, 8, index, if (completed) 10L else null)
            }
        )

    private fun details(vararg exercises: ActiveWorkoutExerciseWithDetails) = ActiveWorkoutDetails(
        activeWorkout = ActiveWorkoutEntity(1L, 0L, null, 0L, 0L, null),
        exercises = exercises.toList()
    )

    @Test
    fun noWorkoutMeansNoFocus() {
        assertNull(activeWorkoutFocus(null))
    }

    @Test
    fun focusesFirstExerciseByOrderWithAnOpenSet() {
        val focus = activeWorkoutFocus(
            details(
                exercise("b", "Squat", 1, false, false),
                exercise("a", "Bench Press", 0, true, true),
                exercise("c", "Row", 2, false)
            )
        )!!
        assertEquals("Squat", focus.exerciseName)
        assertEquals(1, focus.currentSetNumber)
        assertEquals(2, focus.completedSets)
        assertEquals(5, focus.totalSets)
    }

    @Test
    fun currentSetIsFirstOpenSetInsideTheExercise() {
        val focus = activeWorkoutFocus(details(exercise("a", "Bench Press", 0, true, true, false)))!!
        assertEquals("Bench Press", focus.exerciseName)
        assertEquals(3, focus.currentSetNumber)
    }

    @Test
    fun allSetsDoneHasNoExerciseName() {
        val focus = activeWorkoutFocus(details(exercise("a", "Bench Press", 0, true, true)))!!
        assertNull(focus.exerciseName)
        assertEquals(2, focus.completedSets)
        assertEquals(2, focus.totalSets)
    }
}
