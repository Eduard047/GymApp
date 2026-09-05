package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseWithDetails
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import org.junit.Assert.assertEquals
import org.junit.Test

class WorkoutAdaptationTest {
    @Test
    fun tooHardPreservesCompletedSetsAndUsesMachineDirection() {
        val source = details(
            completed = ActiveWorkoutSetEntity("done", "block", 20.0, 8, 0, 100),
            pending = ActiveWorkoutSetEntity("next", "block", 20.0, 8, 1, null)
        )
        val result = requireNotNull(WorkoutAdaptation.build(
            source,
            reason = "tooHard",
            profiles = mapOf(7L to ExerciseLoadProfile(ExerciseLoadDirection.LowerIsHarder, listOf(15.0, 20.0, 25.0))),
            exerciseId = { 7L }
        ))

        assertEquals(source.exercises[0].sets[0], result.exercises[0].sets[0])
        assertEquals(25.0, result.exercises[0].sets[1].weight, 0.0)
    }

    @Test
    fun timeCutNeverDropsCompletedWork() {
        val source = details(
            completed = ActiveWorkoutSetEntity("done", "block", 20.0, 8, 0, 100),
            pending = ActiveWorkoutSetEntity("next", "block", 20.0, 8, 1, null)
        )
        val result = requireNotNull(WorkoutAdaptation.build(source, "timeCut", minutes = 10, exerciseId = { 7L }))
        assertEquals(source.exercises[0].sets[0], result.exercises[0].sets[0])
    }

    private fun details(completed: ActiveWorkoutSetEntity, pending: ActiveWorkoutSetEntity) = ActiveWorkoutDetails(
        ActiveWorkoutEntity(1, 1, null, 1, 0, null),
        listOf(ActiveWorkoutExerciseWithDetails(ActiveWorkoutExerciseEntity("block", 1, "Assisted Pull-up", "assisted_pull_up", 0), listOf(completed, pending)))
    )
}
