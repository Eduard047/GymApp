package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.repository.SetDeletionImpact
import com.example.gymapp.data.repository.SetDeletionSnapshot
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections

class StagedDeletionTest {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val committed: MutableList<String> = Collections.synchronizedList(mutableListOf())
    private val timerGate = CompletableDeferred<Unit>()

    @After
    fun tearDown() = scope.cancel()

    private fun staged(
        onCommit: suspend (String) -> Unit = { committed += it }
    ) = StagedDeletion(
        scope = scope,
        waitFor = { timerGate.await() },
        detachedScope = scope,
        onCommit = onCommit
    )

    @Test
    fun stagedItemIsPendingAndNothingIsCommittedYet() = runBlocking {
        val deletion = staged()
        deletion.stage("set-1")
        assertEquals("set-1", deletion.pending.value)
        assertTrue(committed.isEmpty())
    }

    @Test
    fun undoRestoresTheItemAndNeverCommits() = runBlocking {
        val deletion = staged()
        deletion.stage("set-1")
        assertTrue(deletion.undo())
        assertNull(deletion.pending.value)
        timerGate.complete(Unit)
        deletion.commitNow()
        assertTrue(committed.isEmpty())
        assertFalse(deletion.undo())
    }

    @Test
    fun timeoutCommitsExactlyOnce() = runBlocking {
        val done = CompletableDeferred<Unit>()
        val deletion = staged { committed += it; done.complete(Unit) }
        deletion.stage("set-1")
        timerGate.complete(Unit)
        withTimeout(5_000) { done.await() }
        withTimeout(5_000) { while (deletion.pending.value != null) kotlinx.coroutines.yield() }
        deletion.commitNow()
        assertEquals(listOf("set-1"), committed.toList())
        assertNull(deletion.pending.value)
    }

    @Test
    fun leavingTheScreenCommitsImmediately() = runBlocking {
        val done = CompletableDeferred<Unit>()
        val deletion = staged { committed += it; done.complete(Unit) }
        deletion.stage("exercise-9")
        deletion.commitDetached()
        withTimeout(5_000) { done.await() }
        assertEquals(listOf("exercise-9"), committed.toList())
    }

    @Test
    fun commitNowWaitsForTheWriteAndClearsPending() = runBlocking {
        val deletion = staged()
        deletion.stage("set-1")
        deletion.commitNow()
        assertEquals(listOf("set-1"), committed.toList())
        assertNull(deletion.pending.value)
    }

    @Test
    fun anotherDeletionCommitsThePreviousOneFirst() = runBlocking {
        val deletion = staged()
        deletion.stage("set-1")
        deletion.stage("set-2")
        assertEquals(listOf("set-1"), committed.toList())
        assertEquals("set-2", deletion.pending.value)
        assertTrue(deletion.undo())
        assertEquals(listOf("set-1"), committed.toList())
    }

    @Test
    fun undoWithNothingPendingDoesNothing() {
        assertFalse(staged().undo())
    }

    private fun block(id: Long, vararg setIds: Long) = WorkoutExerciseWithDetails(
        workoutExercise = WorkoutExerciseEntity(id = id, sessionId = 1, exerciseId = id, orderIndex = id.toInt()),
        exercise = ExerciseEntity(id = id, name = "Exercise $id"),
        sets = setIds.mapIndexed { index, setId ->
            SetEntryEntity(id = setId, workoutExerciseId = id, weight = 50.0, reps = 5, orderIndex = index)
        }
    )

    private val details = WorkoutSessionDetails(
        session = WorkoutSessionEntity(id = 1, date = 0, note = null),
        workoutExercises = listOf(block(10, 100, 101), block(20, 200))
    )

    private fun snapshot(setId: Long, blockId: Long, impact: SetDeletionImpact) = SetDeletionSnapshot(
        setId = setId, workoutExerciseId = blockId, workoutSessionId = 1, exerciseId = blockId,
        exerciseName = "Exercise $blockId", sessionDate = 0, weight = 50.0, reps = 5, orderIndex = 0,
        displayOrdinal = 1, setsInExerciseBlock = 2, exerciseBlocksInWorkout = 2, impact = impact,
        removedWorkoutExercise = null, removedWorkoutSession = null, removedGarminProvenance = null,
        deletionStoreToken = "t"
    )

    @Test
    fun nothingStagedLeavesTheDetailsUntouched() {
        assertEquals(details, details.withoutStagedRemoval(null))
    }

    @Test
    fun stagedSetIsHiddenFromItsExerciseOnly() {
        val shown = details.withoutStagedRemoval(
            WorkoutDetailStagedRemoval.Set(snapshot(100, 10, SetDeletionImpact.SetOnly))
        )
        assertEquals(listOf(101L), shown.workoutExercises[0].sets.map { it.id })
        assertEquals(listOf(200L), shown.workoutExercises[1].sets.map { it.id })
    }

    @Test
    fun stagedFinalSetHidesItsWholeExerciseBlock() {
        val shown = details.withoutStagedRemoval(
            WorkoutDetailStagedRemoval.Set(snapshot(200, 20, SetDeletionImpact.ExerciseBlock))
        )
        assertEquals(listOf(10L), shown.workoutExercises.map { it.workoutExercise.id })
    }

    @Test
    fun stagedExerciseIsHidden() {
        val shown = details.withoutStagedRemoval(WorkoutDetailStagedRemoval.Exercise(10))
        assertEquals(listOf(20L), shown.workoutExercises.map { it.workoutExercise.id })
    }
}
