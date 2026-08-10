package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.LiveCanonicalExercise
import com.example.gymapp.auth.LiveCanonicalPlan
import com.example.gymapp.auth.LiveCanonicalSet
import com.example.gymapp.auth.LiveCompletedSet
import com.example.gymapp.auth.LiveParticipant
import com.example.gymapp.auth.LiveProfile
import com.example.gymapp.auth.LiveProgress
import com.example.gymapp.auth.LiveRoomSnapshot
import com.example.gymapp.auth.LiveWorkoutSnapshot
import com.example.gymapp.auth.LiveWorkoutSummary
import com.example.gymapp.data.repository.LivePendingOperation
import com.example.gymapp.data.repository.LivePendingOperationKind
import com.example.gymapp.data.repository.LiveWorkoutBinding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutQueueReconcileTest {
    @Test
    fun `unknown successful completion is dropped and unchanged next request keeps its id`() {
        val binding = binding(
            listOf(
                operation("11111111-1111-4111-8111-111111111111", "s_01_01", 1, 80.0),
                operation("22222222-2222-4222-8222-222222222222", "s_01_02", 2, 82.5)
            )
        )
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding,
            snapshot = snapshot(
                revision = 2,
                completed = listOf(LiveCompletedSet("s_01_01", 80.0, 8, NOW)),
                undoable = "s_01_01"
            )
        )

        assertTrue(result is LiveQueueReconcileResult.Reconciled)
        val rebased = (result as LiveQueueReconcileResult.Reconciled).binding
        assertEquals(2, rebased.progressRevision)
        assertEquals(1, rebased.pendingOperations.size)
        assertEquals("s_01_02", rebased.pendingOperations.single().serverSetId)
        assertEquals(2, rebased.pendingOperations.single().expectedProgressRevision)
        assertEquals(
            "22222222-2222-4222-8222-222222222222",
            rebased.pendingOperations.single().clientOperationId
        )
    }

    @Test
    fun `same set with different remote values detaches instead of overwriting`() {
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(listOf(operation("11111111-1111-4111-8111-111111111111", "s_01_01", 1, 80.0))),
            snapshot = snapshot(
                revision = 2,
                completed = listOf(LiveCompletedSet("s_01_01", 120.0, 8, NOW)),
                undoable = "s_01_01"
            )
        )

        assertEquals(LiveQueueReconcileResult.Unsafe, result)
    }

    @Test
    fun `already finished receipt is removed after reconnect`() {
        val finish = LivePendingOperation(
            clientOperationId = "11111111-1111-4111-8111-111111111111",
            kind = LivePendingOperationKind.Finish,
            expectedProgressRevision = 1,
            serverSetId = null,
            weight = null,
            reps = null
        )
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(listOf(finish)),
            snapshot = snapshot(2, emptyList(), null, selfState = "finished", finishedAt = NOW)
        ) as LiveQueueReconcileResult.Reconciled

        assertTrue(result.binding.pendingOperations.isEmpty())
        assertTrue(result.binding.localFinished)
    }

    @Test
    fun `complete then undo stays ordered when neither request reached the server`() {
        val complete = operation(
            "11111111-1111-4111-8111-111111111111",
            "s_01_01",
            1,
            80.0
        )
        val undo = LivePendingOperation(
            clientOperationId = "22222222-2222-4222-8222-222222222222",
            kind = LivePendingOperationKind.UndoSet,
            expectedProgressRevision = 2,
            serverSetId = "s_01_01",
            weight = null,
            reps = null
        )

        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(listOf(complete, undo)),
            snapshot = snapshot(1, emptyList(), null)
        ) as LiveQueueReconcileResult.Reconciled

        assertEquals(listOf(complete, undo), result.binding.pendingOperations)
    }

    @Test
    fun `complete then undo drops exactly the remotely applied prefix`() {
        val complete = operation(
            "11111111-1111-4111-8111-111111111111",
            "s_01_01",
            1,
            80.0
        )
        val undo = LivePendingOperation(
            clientOperationId = "22222222-2222-4222-8222-222222222222",
            kind = LivePendingOperationKind.UndoSet,
            expectedProgressRevision = 2,
            serverSetId = "s_01_01",
            weight = null,
            reps = null
        )
        val queue = listOf(complete, undo)

        val afterComplete = reconcileLiveQueueWithSnapshot(
            binding = binding(queue),
            snapshot = snapshot(
                revision = 2,
                completed = listOf(LiveCompletedSet("s_01_01", 80.0, 8, NOW)),
                undoable = "s_01_01"
            )
        ) as LiveQueueReconcileResult.Reconciled
        assertEquals(listOf(undo), afterComplete.binding.pendingOperations)

        val afterUndo = reconcileLiveQueueWithSnapshot(
            binding = binding(queue),
            snapshot = snapshot(revision = 3, completed = emptyList(), undoable = null)
        ) as LiveQueueReconcileResult.Reconciled
        assertTrue(afterUndo.binding.pendingOperations.isEmpty())
    }

    @Test
    fun `unrelated own progress revision fails closed`() {
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(
                listOf(
                    operation(
                        "11111111-1111-4111-8111-111111111111",
                        "s_01_01",
                        1,
                        80.0
                    )
                )
            ),
            snapshot = snapshot(
                revision = 3,
                completed = listOf(LiveCompletedSet("s_01_02", 82.5, 8, NOW)),
                undoable = "s_01_02"
            )
        )

        assertEquals(LiveQueueReconcileResult.Unsafe, result)
    }

    private fun operation(
        id: String,
        setId: String,
        revision: Int,
        weight: Double
    ) = LivePendingOperation(
        clientOperationId = id,
        kind = LivePendingOperationKind.CompleteSet,
        expectedProgressRevision = revision,
        serverSetId = setId,
        weight = weight,
        reps = 8
    )

    private fun binding(queue: List<LivePendingOperation>) = LiveWorkoutBinding(
        userId = "42345678-1234-4123-8123-123456789abc",
        sessionGeneration = "52345678-1234-4123-8123-123456789abc",
        roomId = ROOM_ID,
        role = "owner",
        peerProfileId = "p_0123456789abcdef0123456789abcdef",
        peerDisplayName = "Partner",
        roomRevision = 3,
        membershipRevision = 1,
        progressRevision = 1,
        workoutStartedAt = 1_786_330_800_000L,
        serverToLocalSetIds = mapOf(
            "s_01_01" to "62345678-1234-4123-8123-123456789abc",
            "s_01_02" to "72345678-1234-4123-8123-123456789abc"
        ),
        localFinished = queue.any { it.kind == LivePendingOperationKind.Finish },
        pendingOperations = queue
    )

    private fun snapshot(
        revision: Int,
        completed: List<LiveCompletedSet>,
        undoable: String?,
        selfState: String = "joined",
        finishedAt: String? = null
    ): LiveWorkoutSnapshot {
        val summary = LiveWorkoutSummary(1, 2, listOf("Bench press"))
        val plan = LiveCanonicalPlan(
            listOf(
                LiveCanonicalExercise(
                    exerciseId = "e_01",
                    name = "Bench press",
                    catalogKey = "bench_press",
                    sets = listOf(
                        LiveCanonicalSet("s_01_01", 80.0, 8),
                        LiveCanonicalSet("s_01_02", 82.5, 8)
                    )
                )
            )
        )
        val self = LiveParticipant(
            isSelf = true,
            profile = LiveProfile("p_${"1".repeat(32)}", "Owner"),
            role = "owner",
            state = selfState,
            membershipRevision = 2,
            joinedAt = NOW,
            finishedAt = finishedAt,
            departedAt = null,
            progress = LiveProgress(revision, completed, undoable, finishedAt)
        )
        val peer = LiveParticipant(
            isSelf = false,
            profile = LiveProfile("p_${"2".repeat(32)}", "Partner"),
            role = "participant",
            state = "joined",
            membershipRevision = 1,
            joinedAt = NOW,
            finishedAt = null,
            departedAt = null,
            progress = LiveProgress(1, emptyList(), null, null)
        )
        return LiveWorkoutSnapshot(
            room = LiveRoomSnapshot(
                roomId = ROOM_ID,
                status = "active",
                roomRevision = 4,
                closeReason = null,
                createdAt = NOW,
                inviteExpiresAt = LATER,
                startedAt = NOW,
                activeExpiresAt = LATER,
                endedAt = null,
                summary = summary
            ),
            plan = plan,
            participants = listOf(self, peer)
        )
    }

    private companion object {
        const val ROOM_ID = "lr_0123456789abcdef0123456789abcdef"
        const val NOW = "2026-08-10T09:00:00Z"
        const val LATER = "2026-08-10T11:00:00Z"
    }
}
