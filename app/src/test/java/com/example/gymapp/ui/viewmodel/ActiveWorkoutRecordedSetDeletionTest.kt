package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.DeleteActiveWorkoutSetResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutRecordedSetDeletionTest {
    @Test
    fun committedDeletionStopsTheRestTimerOfTheDeletedUndoTarget() = runBlocking {
        var restStopped = false
        val outcome = persistActiveWorkoutMutationAndReconcileRest(
            persist = { DeleteActiveWorkoutSetResult.Deleted(revision = 3L, clearedUndo = true) },
            isCommitted = { it is DeleteActiveWorkoutSetResult.Deleted },
            stopRest = {
                restStopped = true
                true
            }
        )
        assertTrue(restStopped)
        assertEquals(ActiveWorkoutRestReconciliationStatus.Reconciled, outcome.restStatus)
    }

    @Test
    fun failedRestCleanupIsReportedAfterACommittedDeletion() = runBlocking {
        val outcome = persistActiveWorkoutMutationAndReconcileRest(
            persist = { DeleteActiveWorkoutSetResult.Deleted(revision = 3L, clearedUndo = true) },
            isCommitted = { it is DeleteActiveWorkoutSetResult.Deleted },
            stopRest = { false }
        )
        assertEquals(ActiveWorkoutRestReconciliationStatus.Failed, outcome.restStatus)
    }

    @Test
    fun refusedDeletionNeverTouchesTheRestTimer() = runBlocking {
        for (refused in listOf(
            DeleteActiveWorkoutSetResult.Stale,
            DeleteActiveWorkoutSetResult.LastSet,
            DeleteActiveWorkoutSetResult.LivePlanFrozen,
            DeleteActiveWorkoutSetResult.TargetChanged
        )) {
            var restStopped = false
            val outcome = persistActiveWorkoutMutationAndReconcileRest(
                persist = { refused },
                isCommitted = { it is DeleteActiveWorkoutSetResult.Deleted },
                stopRest = {
                    restStopped = true
                    true
                }
            )
            assertFalse(restStopped)
            assertEquals(ActiveWorkoutRestReconciliationStatus.NotRequired, outcome.restStatus)
        }
    }
}
