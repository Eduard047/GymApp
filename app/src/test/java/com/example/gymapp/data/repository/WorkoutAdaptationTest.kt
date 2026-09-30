package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseWithDetails
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    @Test
    fun skipCandidateIsNullWhenNothingIsUnrecorded() {
        val source = twoBlocks(
            first = listOf(set("a1", "b1", 0, 100), set("a2", "b1", 1, 200)),
            second = listOf(set("c1", "b2", 0, null))
        )
        assertNull(WorkoutAdaptation.buildSkipCandidate(source, "b1"))
        assertNull(WorkoutAdaptation.buildSkipCandidate(source, "missing"))
    }

    @Test
    fun skipCandidateIsNullForTheOnlyExerciseWithNoRecordedSets() {
        val source = twoBlocks(first = listOf(set("a1", "b1", 0, null), set("a2", "b1", 1, null)), second = null)
        assertNull(WorkoutAdaptation.buildSkipCandidate(source, "b1"))
    }

    @Test
    fun skipCandidateRemovesAnUntouchedBlockAndReindexesTheRest() {
        val source = twoBlocks(
            first = listOf(set("a1", "b1", 0, null), set("a2", "b1", 1, null)),
            second = listOf(set("c1", "b2", 0, 100), set("c2", "b2", 1, null))
        )
        val result = requireNotNull(WorkoutAdaptation.buildSkipCandidate(source, "b1"))
        assertEquals(listOf("b2"), result.exercises.map { it.activeWorkoutExercise.id })
        assertEquals(0, result.exercises[0].activeWorkoutExercise.orderIndex)
        assertEquals(source.exercises[1].sets, result.exercises[0].sets)
        assertEquals(source.activeWorkout, result.activeWorkout)
    }

    @Test
    fun skipCandidateTrimsABlockWithRecordedSetsToThoseSetsOnly() {
        val source = twoBlocks(
            first = listOf(set("a1", "b1", 0, 100), set("a2", "b1", 1, null), set("a3", "b1", 2, null)),
            second = listOf(set("c1", "b2", 0, null))
        )
        val result = requireNotNull(WorkoutAdaptation.buildSkipCandidate(source, "b1"))
        assertEquals(listOf("b1", "b2"), result.exercises.map { it.activeWorkoutExercise.id })
        assertEquals(listOf(source.exercises[0].sets[0]), result.exercises[0].sets)
        assertEquals(source.exercises[1].sets, result.exercises[1].sets)
    }

    @Test
    fun skipCandidateCanTrimTheOnlyExerciseWhenItHasRecordedSets() {
        val source = twoBlocks(first = listOf(set("a1", "b1", 0, 100), set("a2", "b1", 1, null)), second = null)
        val result = requireNotNull(WorkoutAdaptation.buildSkipCandidate(source, "b1"))
        assertEquals(1, result.exercises.size)
        assertEquals(listOf("a1"), result.exercises[0].sets.map { it.id })
    }

    private fun set(id: String, block: String, order: Int, completedAt: Long?) =
        ActiveWorkoutSetEntity(id, block, 20.0, 8, order, completedAt)

    private fun twoBlocks(first: List<ActiveWorkoutSetEntity>, second: List<ActiveWorkoutSetEntity>?) = ActiveWorkoutDetails(
        ActiveWorkoutEntity(1, 1, null, 1, 0, null),
        listOfNotNull(
            ActiveWorkoutExerciseWithDetails(ActiveWorkoutExerciseEntity("b1", 1, "Bench Press", "bench_press", 0), first),
            second?.let { ActiveWorkoutExerciseWithDetails(ActiveWorkoutExerciseEntity("b2", 1, "Squat", "squat", 1), it) }
        )
    )

    private fun details(completed: ActiveWorkoutSetEntity, pending: ActiveWorkoutSetEntity) = ActiveWorkoutDetails(
        ActiveWorkoutEntity(1, 1, null, 1, 0, null),
        listOf(ActiveWorkoutExerciseWithDetails(ActiveWorkoutExerciseEntity("block", 1, "Assisted Pull-up", "assisted_pull_up", 0), listOf(completed, pending)))
    )
}
