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
import com.example.gymapp.data.repository.MoveActiveWorkoutExerciseResult
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

    @Test
    fun exerciseMoveIsAllowedInsideTheListAndSilentAtTheEdges() {
        val details = workout(listOf(false), listOf(false), listOf(false))
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseMoveBlock(details, "e1", -1, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseMoveBlock(details, "e1", 1, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.AtEdge,
            activeWorkoutExerciseMoveBlock(details, "e0", -1, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.AtEdge,
            activeWorkoutExerciseMoveBlock(details, "e2", 1, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.AtEdge,
            activeWorkoutExerciseMoveBlock(workout(listOf(false)), "e0", 1, false, false)
        )
    }

    @Test
    fun exerciseMoveIsRefusedInLiveRoomWhileBusyAndForUnknownExercises() {
        val details = workout(listOf(false), listOf(false))
        assertEquals(
            ActiveWorkoutEditBlock.LiveRoom,
            activeWorkoutExerciseMoveBlock(details, "e0", 1, inLiveRoom = true, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Busy,
            activeWorkoutExerciseMoveBlock(details, "e0", 1, inLiveRoom = false, operationInProgress = true)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseMoveBlock(details, "gone", 1, false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseMoveBlock(null, "e0", 1, false, false)
        )
    }

    @Test
    fun moveOutcomeMessagesAreSilentOnSuccessAndNoChange() {
        assertNull(activeWorkoutMoveExerciseOutcomeMessage(MoveActiveWorkoutExerciseResult.Moved(2L)))
        assertNull(activeWorkoutMoveExerciseOutcomeMessage(MoveActiveWorkoutExerciseResult.NoChange))
        assertEquals(
            R.string.active_workout_missing,
            activeWorkoutMoveExerciseOutcomeMessage(MoveActiveWorkoutExerciseResult.Missing)
        )
        assertEquals(
            R.string.training_adaptation_live_blocked,
            activeWorkoutMoveExerciseOutcomeMessage(MoveActiveWorkoutExerciseResult.LivePlanFrozen)
        )
        assertEquals(
            R.string.active_workout_changed,
            activeWorkoutMoveExerciseOutcomeMessage(MoveActiveWorkoutExerciseResult.Stale)
        )
    }

    @Test
    fun exerciseMoveToIsAllowedForAnyOtherSlotAndSilentForTheSameOrOutOfRange() {
        val details = workout(listOf(false), listOf(false), listOf(false), listOf(false))
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseMoveToBlock(details, "e0", 3, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseMoveToBlock(details, "e3", 0, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.AtEdge,
            activeWorkoutExerciseMoveToBlock(details, "e1", 1, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.AtEdge,
            activeWorkoutExerciseMoveToBlock(details, "e1", 4, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.AtEdge,
            activeWorkoutExerciseMoveToBlock(details, "e1", -1, inLiveRoom = false, operationInProgress = false)
        )
    }

    @Test
    fun exerciseMoveToIsRefusedInLiveRoomWhileBusyAndForUnknownExercises() {
        val details = workout(listOf(false), listOf(false), listOf(false))
        assertEquals(
            ActiveWorkoutEditBlock.LiveRoom,
            activeWorkoutExerciseMoveToBlock(details, "e0", 2, inLiveRoom = true, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Busy,
            activeWorkoutExerciseMoveToBlock(details, "e0", 2, inLiveRoom = false, operationInProgress = true)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseMoveToBlock(details, "gone", 2, false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseMoveToBlock(null, "e0", 2, false, false)
        )
    }

    @Test
    fun deletedPendingSetKeepsIdValuesAndPosition() {
        val details = workout(listOf(true, false, false))
        val deleted = activeWorkoutDeletedPendingSet(details, "e0-s1", null, null, token = 7L)!!
        assertEquals("e0", deleted.exerciseId)
        assertEquals("e0-s1", deleted.set.id)
        assertEquals(1, deleted.index)
        assertEquals(10.0, deleted.set.weight, 0.0)
        assertEquals(5, deleted.set.reps)
        assertEquals(7L, deleted.token)
    }

    @Test
    fun deletedPendingSetUsesTheTypedValuesWhenTheyParse() {
        val details = workout(listOf(false, false))
        val typed = activeWorkoutDeletedPendingSet(details, "e0-s1", "62.5", "8", token = 1L)!!
        assertEquals(62.5, typed.set.weight, 0.0)
        assertEquals(8, typed.set.reps)
        val garbage = activeWorkoutDeletedPendingSet(details, "e0-s1", "abc", "8", token = 2L)!!
        assertEquals(10.0, garbage.set.weight, 0.0)
        assertEquals(5, garbage.set.reps)
    }

    @Test
    fun recordedOrMissingSetsOfferNoUndo() {
        val details = workout(listOf(true, false))
        assertNull(activeWorkoutDeletedPendingSet(details, "e0-s0", null, null, token = 1L))
        assertNull(activeWorkoutDeletedPendingSet(details, "nope", null, null, token = 1L))
    }

    @Test
    fun restoredSetPositionClampsIntoTheCurrentSetCount() {
        assertEquals(0, com.example.gymapp.data.repository.restoredSetPosition(-3, 4))
        assertEquals(2, com.example.gymapp.data.repository.restoredSetPosition(2, 4))
        assertEquals(4, com.example.gymapp.data.repository.restoredSetPosition(9, 4))
    }

    @Test
    fun stepButtonTouchTargetIsAtLeast48dpAndNeverOverlapsItsPair() {
        assertEquals(144, com.example.gymapp.ui.screens.setEditorStepTouchWidthPx(total = 400, targetPx = 144, visiblePx = 84))
        assertEquals(100, com.example.gymapp.ui.screens.setEditorStepTouchWidthPx(total = 200, targetPx = 144, visiblePx = 84))
    }
}
