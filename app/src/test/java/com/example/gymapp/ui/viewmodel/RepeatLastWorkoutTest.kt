package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutExerciseDraft
import com.example.gymapp.data.repository.WorkoutSetDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RepeatLastWorkoutTest {
    private fun exercise(
        id: Long,
        vararg sets: Pair<Double, Int>
    ) = WorkoutExerciseWithDetails(
        workoutExercise = WorkoutExerciseEntity(id = id * 10, sessionId = 1L, exerciseId = id, orderIndex = id.toInt()),
        exercise = ExerciseEntity(id = id, name = "Exercise $id"),
        sets = sets.mapIndexed { index, (weight, reps) ->
            SetEntryEntity(
                id = id * 100 + index,
                workoutExerciseId = id * 10,
                weight = weight,
                reps = reps,
                orderIndex = index
            )
        }
    )

    private fun template(vararg exercises: WorkoutExerciseWithDetails) = WorkoutSessionDetails(
        session = WorkoutSessionEntity(id = 1L, date = 1_000L, note = "Heavy day"),
        workoutExercises = exercises.toList()
    )

    private fun summary(setCount: Int) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(id = 1L, date = 1_000L, note = null),
        exerciseCount = if (setCount > 0) 1 else 0,
        setCount = setCount,
        totalVolume = 0.0
    )

    @Test
    fun seedKeepsStoredOrderWithEditorFormattedWeightsAndPlainReps() {
        val seed = repeatLastWorkoutSeed(
            template(exercise(7L, 62.5 to 8, 60.0 to 10), exercise(3L, 20.0 to 12))
        )

        assertEquals(listOf(7L, 3L), seed.map { it.first })
        assertEquals(
            listOf(SetInputState("62.5", "8"), SetInputState("60", "10")),
            seed[0].second
        )
        assertEquals(listOf(SetInputState("20", "12")), seed[1].second)
    }

    @Test
    fun directDraftsMatchWhatTheEditorStartsAfterRepeat() {
        val source = template(exercise(7L, 62.5 to 8, 60.0 to 10), exercise(3L, 20.0 to 12))
        // The editor path: seed -> ExerciseInputState -> parseDrafts at Start.
        val editorDrafts = parseExerciseInputDrafts(
            repeatLastWorkoutSeed(source).mapIndexed { index, (id, sets) ->
                ExerciseInputState(draftId = 50L + index, exerciseId = id, sets = sets)
            }
        )

        assertEquals(editorDrafts, repeatLastWorkoutDrafts(source))
        assertEquals(
            listOf(
                WorkoutExerciseDraft(7L, listOf(WorkoutSetDraft(62.5, 8), WorkoutSetDraft(60.0, 10))),
                WorkoutExerciseDraft(3L, listOf(WorkoutSetDraft(20.0, 12)))
            ),
            repeatLastWorkoutDrafts(source)
        )
    }

    @Test
    fun directDraftsAreEmptyWhenTheWorkoutHasNoSetsOrBreaksALimit() {
        assertTrue(repeatLastWorkoutDrafts(template()).isEmpty())
        assertTrue(repeatLastWorkoutDrafts(template(exercise(7L))).isEmpty())
        assertTrue(repeatLastWorkoutDrafts(template(exercise(7L, 60.0 to 0))).isEmpty())
        val tooMany = template(
            *Array(WorkoutDataLimits.MAX_EXERCISES_PER_SESSION + 1) { exercise(it + 1L, 20.0 to 10) }
        )
        assertTrue(repeatLastWorkoutDrafts(tooMany).isEmpty())
    }

    @Test
    fun actionIsHiddenWithoutHistoryOrWithAnActiveOrRetainedWorkout() {
        val emptyHistory = canRepeatLastWorkout(emptyList())
        assertFalse(emptyHistory)
        assertFalse(canRepeatLastWorkout(listOf(summary(setCount = 0))))
        val withHistory = canRepeatLastWorkout(listOf(summary(setCount = 3)))
        assertTrue(withHistory)

        assertTrue(shouldShowRepeatLastWorkoutAction(withHistory, hasActiveWorkout = false, hasRetainedWorkoutDraft = false))
        assertFalse(shouldShowRepeatLastWorkoutAction(emptyHistory, hasActiveWorkout = false, hasRetainedWorkoutDraft = false))
        assertFalse(shouldShowRepeatLastWorkoutAction(withHistory, hasActiveWorkout = true, hasRetainedWorkoutDraft = false))
        assertFalse(shouldShowRepeatLastWorkoutAction(withHistory, hasActiveWorkout = false, hasRetainedWorkoutDraft = true))
    }
}
