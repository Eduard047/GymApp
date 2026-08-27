package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.AddActiveWorkoutSetResult
import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import com.example.gymapp.data.repository.SaveActiveWorkoutExerciseResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutViewModelTest {
    @Test
    fun validSetInputAcceptsBlankAsZeroExplicitZeroAndCommaDecimal() {
        assertEquals(
            ParsedActiveWorkoutSet(weight = 0.0, reps = 8),
            parseActiveWorkoutSetInput("", "8")
        )
        assertEquals(
            ParsedActiveWorkoutSet(weight = 0.0, reps = 12),
            parseActiveWorkoutSetInput("0", "12")
        )
        assertEquals(
            ParsedActiveWorkoutSet(weight = 82.5, reps = 8),
            parseActiveWorkoutSetInput("82,5", "8")
        )
    }

    @Test
    fun invalidSetInputRejectsNonFiniteAndOutOfBoundsValues() {
        assertNull(parseActiveWorkoutSetInput("NaN", "8"))
        assertNull(parseActiveWorkoutSetInput("Infinity", "8"))
        assertNull(parseActiveWorkoutSetInput("1000001", "8"))
        assertNull(parseActiveWorkoutSetInput("20", "0"))
        assertNull(parseActiveWorkoutSetInput("20", "10001"))
        assertNull(parseActiveWorkoutSetInput("20", "1".repeat(11)))
    }

    @Test
    fun restStartsOnlyAfterDurableRecordSucceeds() = runBlocking {
        var persisted = false
        var restStarted = false

        val result = persistActiveWorkoutSetBeforeRest(
            persist = {
                assertFalse(restStarted)
                persisted = true
                RecordActiveWorkoutSetResult.Recorded(revision = 4L)
            },
            startRest = {
                assertTrue(persisted)
                restStarted = true
            }
        )

        assertEquals(ActiveWorkoutRecordAndRestResult.RecordedAndTimerStarted, result)
        assertTrue(restStarted)
    }

    @Test
    fun staleRecordDoesNotStartRest() = runBlocking {
        var restStarted = false

        val result = persistActiveWorkoutSetBeforeRest(
            persist = { RecordActiveWorkoutSetResult.Stale },
            startRest = { restStarted = true }
        )

        assertEquals(
            ActiveWorkoutRecordAndRestResult.NotRecorded(RecordActiveWorkoutSetResult.Stale),
            result
        )
        assertFalse(restStarted)
    }

    @Test
    fun timerFailureDoesNotUndoRecordedSet() = runBlocking {
        val result = persistActiveWorkoutSetBeforeRest(
            persist = { RecordActiveWorkoutSetResult.Recorded(revision = 1L) },
            startRest = { error("synthetic timer failure") }
        )

        assertEquals(ActiveWorkoutRecordAndRestResult.RecordedButTimerFailed, result)
    }

    @Test
    fun recordThenSaveExerciseStopsTheOwnedRestTimer() = runBlocking {
        var restRunning = false
        assertEquals(
            ActiveWorkoutRecordAndRestResult.RecordedAndTimerStarted,
            persistActiveWorkoutSetBeforeRest(
                persist = { RecordActiveWorkoutSetResult.Recorded(revision = 2L) },
                startRest = { restRunning = true }
            )
        )

        val result = persistActiveWorkoutMutationAndReconcileRest<
            SaveActiveWorkoutExerciseResult
        >(
            persist = { SaveActiveWorkoutExerciseResult.Saved(revision = 3L, count = 2) },
            isCommitted = { it is SaveActiveWorkoutExerciseResult.Saved },
            stopRest = {
                val stopped = restRunning
                restRunning = false
                stopped
            }
        )

        assertTrue(result.repositoryResult is SaveActiveWorkoutExerciseResult.Saved)
        assertEquals(ActiveWorkoutRestReconciliationStatus.Reconciled, result.restStatus)
        assertFalse(restRunning)
    }

    @Test
    fun recordThenAddSetStopsTheOwnedRestTimer() = runBlocking {
        var restRunning = false
        persistActiveWorkoutSetBeforeRest(
            persist = { RecordActiveWorkoutSetResult.Recorded(revision = 5L) },
            startRest = { restRunning = true }
        )

        val result = persistActiveWorkoutMutationAndReconcileRest<AddActiveWorkoutSetResult>(
            persist = { AddActiveWorkoutSetResult.Added(revision = 6L, setId = "new-set") },
            isCommitted = { it is AddActiveWorkoutSetResult.Added },
            stopRest = {
                val stopped = restRunning
                restRunning = false
                stopped
            }
        )

        assertTrue(result.repositoryResult is AddActiveWorkoutSetResult.Added)
        assertEquals(ActiveWorkoutRestReconciliationStatus.Reconciled, result.restStatus)
        assertFalse(restRunning)
    }

    @Test
    fun committedStructuralMutationPreservesCleanupFailureForUserWarning() = runBlocking {
        val result = persistActiveWorkoutMutationAndReconcileRest<
            SaveActiveWorkoutExerciseResult
        >(
            persist = { SaveActiveWorkoutExerciseResult.Saved(revision = 8L, count = 1) },
            isCommitted = { it is SaveActiveWorkoutExerciseResult.Saved },
            stopRest = { false }
        )

        assertEquals(ActiveWorkoutRestReconciliationStatus.Failed, result.restStatus)
    }

    @Test
    fun wallClockTotalRunsContinuouslyFromDurableWorkoutStart() {
        val startedAt = 10_000L

        assertEquals(30L, totalWorkoutElapsedSeconds(startedAt, nowMillis = 40_000L))
        assertEquals(95L, totalWorkoutElapsedSeconds(startedAt, nowMillis = 105_000L))
        assertEquals(0L, totalWorkoutElapsedSeconds(startedAt, nowMillis = 5_000L))
        assertEquals(0L, totalWorkoutElapsedSeconds(null, nowMillis = 105_000L))
    }

    @Test
    fun displayedWorkoutTimeIncludesRest() {
        assertEquals(
            40L,
            resolvedWorkoutElapsedSeconds(10_000L, nowMillis = 50_000L)
        )
        assertEquals(
            80L,
            resolvedWorkoutElapsedSeconds(10_000L, nowMillis = 90_000L)
        )
        assertEquals(
            95L,
            resolvedWorkoutElapsedSeconds(10_000L, nowMillis = 105_000L)
        )
    }

    @Test
    fun clearedUndoWithAnyCompletedSetIsDurableRestRecoveryMarker() {
        assertTrue(
            shouldReconcileRestAfterUndoCleared(
                undoableSetId = null,
                setCompletionStates = listOf(true, true)
            )
        )
        assertFalse(
            shouldReconcileRestAfterUndoCleared(
                undoableSetId = "last-recorded-set",
                setCompletionStates = listOf(true, true)
            )
        )
        assertTrue(
            shouldReconcileRestAfterUndoCleared(
                undoableSetId = null,
                setCompletionStates = listOf(true, false)
            )
        )
        assertFalse(
            shouldReconcileRestAfterUndoCleared(
                undoableSetId = null,
                setCompletionStates = emptyList()
            )
        )
    }

    @Test
    fun partialWorkoutRetriesFailedRestCleanupFromTheSameDurableSnapshot() {
        var stopAttempts = 0
        val completionStates = listOf(true, false)

        val first = reconcileRestAfterDurableWorkoutSnapshot(
            undoableSetId = null,
            setCompletionStates = completionStates,
            timerReady = true,
            stopRest = {
                stopAttempts += 1
                false
            }
        )
        val retried = reconcileRestAfterDurableWorkoutSnapshot(
            undoableSetId = null,
            setCompletionStates = completionStates,
            timerReady = true,
            stopRest = {
                stopAttempts += 1
                true
            }
        )

        assertEquals(ActiveWorkoutRestReconciliationStatus.Failed, first)
        assertEquals(ActiveWorkoutRestReconciliationStatus.Reconciled, retried)
        assertEquals(2, stopAttempts)
    }

    @Test
    fun recordGateRejectsConcurrentAndReplayClicks() {
        val gate = ActiveWorkoutSetRecordGate()

        assertTrue(gate.tryStart("first-set"))
        assertFalse(gate.tryStart("first-set"))
        assertFalse(gate.tryStart("second-set"))
        assertEquals(setOf("first-set"), gate.inFlight.value)

        gate.finish("first-set")
        assertTrue(gate.tryStart("second-set"))
    }

    @Test
    fun restTimerMutationsAreGatedByEveryWorkoutOperation() {
        assertFalse(
            activeWorkoutOperationInProgress(
                setRecordingsInFlight = emptySet(),
                isRecordingAll = false,
                isFinishing = false,
                isDiscarding = false,
                undoingSetId = null
            )
        )
        listOf(
            activeWorkoutOperationInProgress(setOf("set-1"), false, false, false, null),
            activeWorkoutOperationInProgress(emptySet(), true, false, false, null),
            activeWorkoutOperationInProgress(emptySet(), false, true, false, null),
            activeWorkoutOperationInProgress(emptySet(), false, false, true, null),
            activeWorkoutOperationInProgress(emptySet(), false, false, false, "set-1")
        ).forEach(::assertTrue)
    }

    @Test
    fun bulkInputValidationIsAllOrNothingAndDetectsMissingRows() {
        val valid = parseActiveWorkoutSetBatch(
            listOf(
                ActiveWorkoutSetInputForBatch("first", "20", "10"),
                ActiveWorkoutSetInputForBatch("second", "22,5", "8")
            )
        )
        assertTrue(valid is ParsedActiveWorkoutSetBatch.Valid)
        assertEquals(2, (valid as ParsedActiveWorkoutSetBatch.Valid).updates.size)

        val invalid = parseActiveWorkoutSetBatch(
            listOf(
                ActiveWorkoutSetInputForBatch("first", "20", "10"),
                ActiveWorkoutSetInputForBatch("second", "NaN", "8")
            )
        )
        assertEquals(ParsedActiveWorkoutSetBatch.Invalid("second"), invalid)
        assertFalse(
            hasCompleteActiveWorkoutSetInputs(
                pendingSetIds = listOf("first", "second"),
                availableInputIds = setOf("first")
            )
        )
        assertTrue(
            hasCompleteActiveWorkoutSetInputs(
                pendingSetIds = listOf("first", "second"),
                availableInputIds = setOf("first", "second", "unrelated")
            )
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun bulkInputValidationRejectsDuplicateSetIdentifiers() {
        parseActiveWorkoutSetBatch(
            listOf(
                ActiveWorkoutSetInputForBatch("same", "20", "10"),
                ActiveWorkoutSetInputForBatch("same", "22", "8")
            )
        )
    }
}
