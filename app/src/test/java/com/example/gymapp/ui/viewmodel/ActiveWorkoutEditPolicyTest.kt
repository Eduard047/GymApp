package com.example.gymapp.ui.viewmodel

import com.example.gymapp.R
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseWithDetails
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.AddActiveWorkoutExerciseResult
import com.example.gymapp.data.repository.DeleteActiveWorkoutSetResult
import com.example.gymapp.data.repository.RemoveActiveWorkoutExerciseResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ActiveWorkoutEditPolicyTest {
    private fun workout(vararg setStates: List<Boolean>): ActiveWorkoutDetails = ActiveWorkoutDetails(
        activeWorkout = ActiveWorkoutEntity(1L, 0L, null, 0L, 0L, null),
        exercises = setStates.mapIndexed { e, states ->
            ActiveWorkoutExerciseWithDetails(
                ActiveWorkoutExerciseEntity("e$e", 1L, "Exercise $e", null, e),
                states.mapIndexed { s, done ->
                    ActiveWorkoutSetEntity("e$e-s$s", "e$e", 10.0, 5, s, if (done) 1L else null)
                }
            )
        }
    )

    @Test
    fun pendingSetOfMultiSetExerciseCanBeDeleted() {
        val details = workout(listOf(true, false, false))
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutSetDeletionBlock(details, "e0-s2", inLiveRoom = false, operationInProgress = false)
        )
    }

    @Test
    fun recordedSetsAreDeletableButLastSetIsNot() {
        val details = workout(listOf(true, false), listOf(false), listOf(true))
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutSetDeletionBlock(details, "e0-s0", false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.LastSet,
            activeWorkoutSetDeletionBlock(details, "e2-s0", false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.LastSet,
            activeWorkoutSetDeletionBlock(details, "e1-s0", false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutSetDeletionBlock(details, "gone", false, false)
        )
    }

    @Test
    fun setDeletionIsBlockedInLiveRoomAndWhileBusy() {
        val details = workout(listOf(false, false))
        assertEquals(
            ActiveWorkoutEditBlock.LiveRoom,
            activeWorkoutSetDeletionBlock(details, "e0-s1", inLiveRoom = true, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Busy,
            activeWorkoutSetDeletionBlock(details, "e0-s1", inLiveRoom = false, operationInProgress = true)
        )
    }

    @Test
    fun exerciseWithRecordedSetsCanBeRemovedUnlessLastOrLive() {
        val two = workout(listOf(true, false), listOf(false))
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseRemovalBlock(two, "e0", inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.LiveRoom,
            activeWorkoutExerciseRemovalBlock(two, "e0", inLiveRoom = true, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Busy,
            activeWorkoutExerciseRemovalBlock(two, "e0", inLiveRoom = false, operationInProgress = true)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseRemovalBlock(two, "zzz", false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.LastExercise,
            activeWorkoutExerciseRemovalBlock(workout(listOf(false)), "e0", false, false)
        )
    }

    @Test
    fun staleAndFrozenResultsSurfaceTheRightMessage() {
        assertNull(activeWorkoutDeleteSetOutcomeMessage(DeleteActiveWorkoutSetResult.Deleted(2L)))
        assertEquals(
            R.string.active_workout_changed,
            activeWorkoutDeleteSetOutcomeMessage(DeleteActiveWorkoutSetResult.Stale)
        )
        assertEquals(
            R.string.training_adaptation_live_blocked,
            activeWorkoutDeleteSetOutcomeMessage(DeleteActiveWorkoutSetResult.LivePlanFrozen)
        )
        assertEquals(
            R.string.active_workout_last_set_message,
            activeWorkoutDeleteSetOutcomeMessage(DeleteActiveWorkoutSetResult.LastSet)
        )
        assertNull(activeWorkoutDeleteSetOutcomeMessage(DeleteActiveWorkoutSetResult.Deleted(3L, true)))
        assertNull(
            activeWorkoutRemoveExerciseOutcomeMessage(
                RemoveActiveWorkoutExerciseResult.Removed(2L, 0, false)
            )
        )
        assertEquals(
            R.string.active_workout_changed,
            activeWorkoutRemoveExerciseOutcomeMessage(RemoveActiveWorkoutExerciseResult.Stale)
        )
        assertEquals(
            R.string.training_adaptation_live_blocked,
            activeWorkoutRemoveExerciseOutcomeMessage(RemoveActiveWorkoutExerciseResult.LivePlanFrozen)
        )
    }

    @Test
    fun addingAnExerciseIsBlockedInLiveRoomsBusyAndMissingWorkouts() {
        val details = workout(listOf(false))
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseAdditionBlock(details, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.LiveRoom,
            activeWorkoutExerciseAdditionBlock(details, inLiveRoom = true, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Busy,
            activeWorkoutExerciseAdditionBlock(details, inLiveRoom = false, operationInProgress = true)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseAdditionBlock(null, inLiveRoom = false, operationInProgress = false)
        )
    }

    @Test
    fun addExerciseOutcomesSurfaceTheRightMessage() {
        assertNull(activeWorkoutAddExerciseOutcomeMessage(AddActiveWorkoutExerciseResult.Added(2L, "x")))
        assertEquals(
            R.string.active_workout_changed,
            activeWorkoutAddExerciseOutcomeMessage(AddActiveWorkoutExerciseResult.Stale)
        )
        assertEquals(
            R.string.training_adaptation_live_blocked,
            activeWorkoutAddExerciseOutcomeMessage(AddActiveWorkoutExerciseResult.LivePlanFrozen)
        )
        assertEquals(
            R.string.active_workout_exercise_limit_reached,
            activeWorkoutAddExerciseOutcomeMessage(AddActiveWorkoutExerciseResult.LimitReached)
        )
        assertEquals(
            R.string.active_workout_exercise_already_added,
            activeWorkoutAddExerciseOutcomeMessage(AddActiveWorkoutExerciseResult.AlreadyInWorkout)
        )
    }

    @Test
    fun pickerOffersOnlyExercisesNotAlreadyInTheWorkout() {
        val details = workout(listOf(false), listOf(false))
        val catalog = listOf(
            ExerciseEntity(id = 1L, name = "Exercise 0"),
            ExerciseEntity(id = 2L, name = "Exercise 1"),
            ExerciseEntity(id = 3L, name = "Exercise 9")
        )
        assertEquals(
            listOf(3L),
            activeWorkoutExercisesAvailableToAdd(catalog, details).map { it.id }
        )
        assertEquals(3, activeWorkoutExercisesAvailableToAdd(catalog, null).size)
    }
}
