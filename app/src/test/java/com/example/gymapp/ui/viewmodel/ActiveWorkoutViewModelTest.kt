package com.example.gymapp.ui.viewmodel

import com.example.gymapp.R
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseWithDetails
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.AddActiveWorkoutSetResult
import com.example.gymapp.data.repository.ApplyActiveWorkoutAdaptationResult
import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import com.example.gymapp.data.repository.SaveActiveWorkoutExerciseResult
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
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
    fun skipRemainingSetsReportsFrozenLivePlanStaleAndSuccessSeparately() {
        assertEquals(
            R.string.active_workout_remaining_sets_skipped,
            activeWorkoutSkipOutcomeMessage(ApplyActiveWorkoutAdaptationResult.Applied(revision = 5L))
        )
        assertEquals(
            R.string.training_adaptation_live_blocked,
            activeWorkoutSkipOutcomeMessage(ApplyActiveWorkoutAdaptationResult.LivePlanFrozen)
        )
        assertEquals(
            R.string.active_workout_changed,
            activeWorkoutSkipOutcomeMessage(ApplyActiveWorkoutAdaptationResult.Stale)
        )
        assertEquals(
            R.string.active_workout_changed,
            activeWorkoutSkipOutcomeMessage(ApplyActiveWorkoutAdaptationResult.Missing)
        )
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

    @Test
    fun `outside a live room any recorded set can be undone but a pending set cannot`() {
        assertTrue(activeWorkoutSetUndoAllowed(isCompleted = true, isUndoTarget = true, inLiveRoom = false))
        assertTrue(activeWorkoutSetUndoAllowed(isCompleted = true, isUndoTarget = false, inLiveRoom = false))
        assertFalse(activeWorkoutSetUndoAllowed(isCompleted = false, isUndoTarget = false, inLiveRoom = false))
    }

    @Test
    fun `live gate off allows only the latest recorded set in a live room`() {
        assertTrue(
            activeWorkoutSetUndoAllowed(
                isCompleted = true, isUndoTarget = true, inLiveRoom = true, liveUndoAnySetEnabled = false
            )
        )
        assertFalse(
            activeWorkoutSetUndoAllowed(
                isCompleted = true, isUndoTarget = false, inLiveRoom = true, liveUndoAnySetEnabled = false
            )
        )
        assertTrue(com.example.gymapp.auth.LIVE_UNDO_ANY_SET_ENABLED)
        assertTrue(activeWorkoutSetUndoAllowed(isCompleted = true, isUndoTarget = false, inLiveRoom = true))
    }

    @Test
    fun `live gate on allows any recorded set in a live room`() {
        assertTrue(
            activeWorkoutSetUndoAllowed(
                isCompleted = true, isUndoTarget = false, inLiveRoom = true, liveUndoAnySetEnabled = true
            )
        )
        assertFalse(
            activeWorkoutSetUndoAllowed(
                isCompleted = false, isUndoTarget = false, inLiveRoom = true, liveUndoAnySetEnabled = true
            )
        )
    }

    @Test
    fun `batch undo stays available only while nothing else changed`() {
        val batch = ActiveWorkoutBatchUndo(
            setIdsInUndoOrder = listOf("b", "a"),
            restoreUndoableSetId = null,
            revisionAfterBatch = 5L,
            liveRoomId = null
        )
        val ready = workout(revision = 5L, completed = setOf("a", "b"))

        assertTrue(activeWorkoutBatchUndoAvailable(batch, ready, liveRoomId = null))
        // Another mutation bumped the revision.
        assertFalse(activeWorkoutBatchUndoAvailable(batch, workout(6L, setOf("a", "b")), null))
        // A batch set is no longer recorded.
        assertFalse(activeWorkoutBatchUndoAvailable(batch, workout(5L, setOf("a")), null))
        // Workout finished or discarded.
        assertFalse(activeWorkoutBatchUndoAvailable(batch, null, null))
        assertFalse(activeWorkoutBatchUndoAvailable(null, ready, null))
        // The live room changed after the batch.
        assertFalse(activeWorkoutBatchUndoAvailable(batch, ready, liveRoomId = "lr_x"))
        assertTrue(
            activeWorkoutBatchUndoAvailable(batch.copy(liveRoomId = "lr_x"), ready, liveRoomId = "lr_x")
        )
    }

    private fun replaceWorkout(completed: Set<String> = emptySet()) = ActiveWorkoutDetails(
        activeWorkout = ActiveWorkoutEntity(
            id = 1L, date = 0L, note = null, startedAt = 1_000L, revision = 3L, undoableSetId = null
        ),
        exercises = listOf(
            ActiveWorkoutExerciseWithDetails(
                ActiveWorkoutExerciseEntity("e0", 1L, "Squat", null, 0),
                listOf(ActiveWorkoutSetEntity("s0", "e0", 100.0, 5, 0, null))
            ),
            ActiveWorkoutExerciseWithDetails(
                ActiveWorkoutExerciseEntity("e1", 1L, "Bench", null, 1),
                listOf("a", "b").mapIndexed { index, id ->
                    ActiveWorkoutSetEntity(id, "e1", 50.0, 8, index, if (id in completed) 2_000L else null)
                }
            ),
            ActiveWorkoutExerciseWithDetails(
                ActiveWorkoutExerciseEntity("e2", 1L, "Row", null, 2),
                listOf(ActiveWorkoutSetEntity("s2", "e2", 40.0, 10, 0, null))
            )
        )
    )

    private fun historyEntry(setId: Long, exerciseId: Long, weight: Double, reps: Int, order: Int) =
        ExerciseHistoryEntry(
            setId = setId, sessionId = 1L, sessionDate = 10L, exerciseId = exerciseId,
            exerciseName = "X", weight = weight, reps = reps, setOrderIndex = order
        )

    @Test
    fun replaceIsHiddenOnceAnySetIsRecorded() {
        fun ui(done: Boolean) = ActiveWorkoutSetUiState(
            id = "s", orderIndex = 0, weightInput = "", repsInput = "", isCompleted = done, completedAt = null
        )
        assertTrue(activeWorkoutExerciseCanBeReplaced(listOf(ui(false), ui(false))))
        assertFalse(activeWorkoutExerciseCanBeReplaced(listOf(ui(false), ui(true))))
        val bench = ExerciseEntity(id = 9L, name = "Incline Press")
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseReplaceBlock(replaceWorkout(), "e1", bench, inLiveRoom = false, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.HasRecordedSets,
            activeWorkoutExerciseReplaceBlock(replaceWorkout(setOf("b")), "e1", bench, false, false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.LiveRoom,
            activeWorkoutExerciseReplaceBlock(replaceWorkout(), "e1", bench, inLiveRoom = true, operationInProgress = false)
        )
        assertEquals(
            ActiveWorkoutEditBlock.Missing,
            activeWorkoutExerciseReplaceBlock(replaceWorkout(), "nope", bench, false, false)
        )
    }

    @Test
    fun replaceRejectsAnExerciseAlreadyElsewhereInTheWorkout() {
        val row = ExerciseEntity(id = 4L, name = "Row")
        assertEquals(
            ActiveWorkoutEditBlock.Duplicate,
            activeWorkoutExerciseReplaceBlock(replaceWorkout(), "e1", row, false, false)
        )
        // Picking the exercise's own name is not a duplicate of itself.
        assertEquals(
            ActiveWorkoutEditBlock.Allowed,
            activeWorkoutExerciseReplaceBlock(replaceWorkout(), "e1", ExerciseEntity(id = 2L, name = "Bench"), false, false)
        )
    }

    @Test
    fun replacementSetsFollowTheLastSessionSeed() {
        val history = listOf(
            historyEntry(1, 9L, 60.0, 8, 0),
            historyEntry(2, 9L, 65.0, 6, 1),
            historyEntry(3, 9L, 70.0, 4, 2)
        )
        val old = listOf(SetSeed(50.0, 8), SetSeed(50.0, 8))
        assertEquals(
            listOf(SetSeed(60.0, 8), SetSeed(65.0, 6), SetSeed(70.0, 4)),
            activeWorkoutReplacementSets(old, history, 9L)
        )
    }

    @Test
    fun replacementSetsWithoutSeedKeepCountAndRepsWithLastWeightOrZero() {
        val old = listOf(SetSeed(50.0, 8), SetSeed(52.5, 6), SetSeed(55.0, 5))
        // No history for the new exercise at all: same count and reps, weight 0.
        assertEquals(
            listOf(SetSeed(0.0, 8), SetSeed(0.0, 6), SetSeed(0.0, 5)),
            activeWorkoutReplacementSets(old, emptyList(), 9L)
        )
        // History exists but has no usable reps: no seed, last known weight is applied.
        val weightOnly = listOf(historyEntry(1, 9L, 42.5, 0, 0))
        assertEquals(
            listOf(SetSeed(42.5, 8), SetSeed(42.5, 6), SetSeed(42.5, 5)),
            activeWorkoutReplacementSets(old, weightOnly, 9L)
        )
    }

    @Test
    fun replaceOutcomeMessagesCoverTheRefusals() {
        assertEquals(
            R.string.replace_exercise_done,
            activeWorkoutReplaceExerciseOutcomeMessage(
                com.example.gymapp.data.repository.ReplaceActiveWorkoutExerciseResult.Replaced(4L)
            )
        )
        assertEquals(
            R.string.active_workout_exercise_already_added,
            activeWorkoutReplaceExerciseOutcomeMessage(
                com.example.gymapp.data.repository.ReplaceActiveWorkoutExerciseResult.AlreadyInWorkout
            )
        )
    }

    private fun workout(revision: Long, completed: Set<String>) = ActiveWorkoutDetails(
        activeWorkout = ActiveWorkoutEntity(
            id = 1L,
            date = 0L,
            note = null,
            startedAt = 1_000L,
            revision = revision,
            undoableSetId = null
        ),
        exercises = listOf(
            ActiveWorkoutExerciseWithDetails(
                activeWorkoutExercise = ActiveWorkoutExerciseEntity("e", 1L, "Bench", null, 0),
                sets = listOf("a", "b", "c").mapIndexed { index, id ->
                    ActiveWorkoutSetEntity(id, "e", 50.0, 8, index, if (id in completed) 2_000L else null)
                }
            )
        )
    )

    @Test
    fun draftParsingSavesEachValidHalfAndSkipsPartialText() {
        assertEquals(ActiveWorkoutSetDraft(82.5, 8), parseActiveWorkoutSetDraft("82,5", "8"))
        // Cleared weight is 0 kg, exactly like recordSet's parser.
        assertEquals(ActiveWorkoutSetDraft(0.0, 8), parseActiveWorkoutSetDraft("", "8"))
        // A half-typed field is skipped while the other valid half is still saved.
        assertEquals(ActiveWorkoutSetDraft(60.0, null), parseActiveWorkoutSetDraft("60", ""))
        assertEquals(ActiveWorkoutSetDraft(null, 5), parseActiveWorkoutSetDraft(".", "5"))
        assertEquals(ActiveWorkoutSetDraft(null, null), parseActiveWorkoutSetDraft("abc", "0"))
        assertEquals(ActiveWorkoutSetDraft(60.0, null), parseActiveWorkoutSetDraft("60", "10001"))
    }

    @Test
    fun draftSaverCollapsesRapidEditsIntoOneWriteAfterThePause() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val written = Channel<String>(Channel.UNLIMITED)
        val saver = ActiveWorkoutDraftSaver(scope, debounceMillis = 60L) { written.send(it) }
        try {
            repeat(5) {
                saver.schedule("set-a")
                delay(10L)
            }
            assertEquals("set-a", withTimeout(2_000L) { written.receive() })
            delay(150L)
            assertTrue(written.tryReceive().isFailure)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun draftSaverFlushWritesEverySetOnceEvenAfterItsScopeIsCancelled() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val written = CopyOnWriteArrayList<String>()
        val saver = ActiveWorkoutDraftSaver(scope, debounceMillis = 10_000L) { written += it }
        saver.schedule("set-a")
        saver.schedule("set-b")
        // The ViewModel scope is cancelled before onCleared runs; the flush must still write.
        scope.cancel()
        saver.flush()
        assertEquals(listOf("set-a", "set-b"), written.toList())
        saver.flush()
        assertEquals(2, written.size)
    }

    @Test
    fun draftSaverFlushInWritesPendingSetsOnIndependentScopeAfterOwnerScopeIsCancelled() = runBlocking {
        val ownerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val flushScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val written = CopyOnWriteArrayList<String>()
        val saver = ActiveWorkoutDraftSaver(ownerScope, debounceMillis = 10_000L) { written += it }
        try {
            saver.schedule("set-a")
            saver.schedule("set-b")
            // Mirrors ON_STOP followed by viewModelScope cancellation: the flush is launched, then
            // the owner scope dies; the write must still complete exactly once per set.
            val job = saver.flushIn(flushScope)
            ownerScope.cancel()
            withTimeout(2_000L) { job.join() }
            assertEquals(listOf("set-a", "set-b"), written.toList())
            withTimeout(2_000L) { saver.flushIn(flushScope).join() }
            assertEquals(2, written.size)
        } finally {
            flushScope.cancel()
        }
    }
}
