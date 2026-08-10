package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.LivePendingOperation
import com.example.gymapp.data.repository.LivePendingOperationKind
import com.example.gymapp.data.repository.LivePreparedMutation
import com.example.gymapp.data.repository.LivePreparedMutationKind
import com.example.gymapp.data.repository.LiveWorkoutBinding
import com.example.gymapp.data.repository.LiveWorkoutSidecarCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutPreparedMutationTest {
    @Test
    fun `single set committed before sidecar promotion is recovered after restart`() {
        val prepared = completeOperation(
            id = "11111111-1111-4111-8111-111111111111",
            revision = 1,
            serverSetId = "s_01_01",
            weight = 82.5,
            reps = 7
        )
        val restarted = restart(
            binding(
                preparedMutation = LivePreparedMutation(
                    localMutationId = "21111111-1111-4111-8111-111111111111",
                    kind = LivePreparedMutationKind.CompleteSet,
                    expectedLocalRevision = 7,
                    operations = listOf(prepared)
                )
            )
        )
        val local = localWorkout(
            revision = 8,
            undoableSetId = LOCAL_SET_1,
            set1 = LiveLocalSetState(LOCAL_SET_1, 82.5, 7, true)
        )

        assertEquals(
            LivePreparedMutationResolution.Promote,
            resolvePreparedLiveMutation(restarted, local)
        )
        val recovered = promotePreparedLiveMutation(restarted)
        assertEquals(listOf(prepared), recovered.pendingOperations)
        assertNull(recovered.preparedMutation)
    }

    @Test
    fun `record all committed before sidecar promotion recovers every set in order`() {
        val operations = listOf(
            completeOperation(
                id = "11111111-1111-4111-8111-111111111111",
                revision = 1,
                serverSetId = "s_01_01",
                weight = 80.0,
                reps = 8
            ),
            completeOperation(
                id = "21111111-1111-4111-8111-111111111111",
                revision = 2,
                serverSetId = "s_01_02",
                weight = 85.0,
                reps = 6
            )
        )
        val restarted = restart(
            binding(
                preparedMutation = LivePreparedMutation(
                    localMutationId = "31111111-1111-4111-8111-111111111111",
                    kind = LivePreparedMutationKind.CompleteBatch,
                    expectedLocalRevision = 12,
                    operations = operations
                )
            )
        )
        val local = localWorkout(
            revision = 13,
            undoableSetId = null,
            set1 = LiveLocalSetState(LOCAL_SET_1, 80.0, 8, true),
            set2 = LiveLocalSetState(LOCAL_SET_2, 85.0, 6, true)
        )

        assertEquals(
            LivePreparedMutationResolution.Promote,
            resolvePreparedLiveMutation(restarted, local)
        )
        assertEquals(operations, promotePreparedLiveMutation(restarted).pendingOperations)
    }

    @Test
    fun `prepared set with unchanged Room revision is cancelled without network work`() {
        val restarted = restart(
            binding(
                preparedMutation = LivePreparedMutation(
                    localMutationId = "21111111-1111-4111-8111-111111111111",
                    kind = LivePreparedMutationKind.CompleteSet,
                    expectedLocalRevision = 7,
                    operations = listOf(
                        completeOperation(
                            id = "11111111-1111-4111-8111-111111111111",
                            revision = 1,
                            serverSetId = "s_01_01",
                            weight = 82.5,
                            reps = 7
                        )
                    )
                )
            )
        )

        assertEquals(
            LivePreparedMutationResolution.Cancel,
            resolvePreparedLiveMutation(restarted, localWorkout(revision = 7))
        )
    }

    @Test
    fun `undo recovered after restart remains behind its unsent complete`() {
        val complete = completeOperation(
            id = "11111111-1111-4111-8111-111111111111",
            revision = 1,
            serverSetId = "s_01_01",
            weight = 80.0,
            reps = 8
        )
        val undo = LivePendingOperation(
            clientOperationId = "21111111-1111-4111-8111-111111111111",
            kind = LivePendingOperationKind.UndoSet,
            expectedProgressRevision = 2,
            serverSetId = "s_01_01",
            weight = null,
            reps = null
        )
        val restarted = restart(
            binding(
                pendingOperations = listOf(complete),
                preparedMutation = LivePreparedMutation(
                    localMutationId = "31111111-1111-4111-8111-111111111111",
                    kind = LivePreparedMutationKind.UndoSet,
                    expectedLocalRevision = 10,
                    operations = listOf(undo)
                )
            )
        )
        val afterUndo = localWorkout(
            revision = 11,
            undoableSetId = null,
            set1 = LiveLocalSetState(LOCAL_SET_1, 80.0, 8, false)
        )

        assertEquals(
            LivePreparedMutationResolution.Promote,
            resolvePreparedLiveMutation(restarted, afterUndo)
        )
        val recovered = promotePreparedLiveMutation(restarted)
        assertEquals(listOf(complete, undo), recovered.pendingOperations)
        assertEquals(listOf(1, 2), recovered.pendingOperations.map { it.expectedProgressRevision })
    }

    @Test
    fun `finish committed in Room is recovered after restart while precommit finish is cancelled`() {
        val finish = LivePendingOperation(
            clientOperationId = "11111111-1111-4111-8111-111111111111",
            kind = LivePendingOperationKind.Finish,
            expectedProgressRevision = 1,
            serverSetId = null,
            weight = null,
            reps = null
        )
        val restarted = restart(
            binding(
                preparedMutation = LivePreparedMutation(
                    localMutationId = "21111111-1111-4111-8111-111111111111",
                    kind = LivePreparedMutationKind.Finish,
                    expectedLocalRevision = 14,
                    operations = listOf(finish)
                )
            )
        )

        assertEquals(
            LivePreparedMutationResolution.Cancel,
            resolvePreparedLiveMutation(restarted, localWorkout(revision = 14))
        )
        assertEquals(
            LivePreparedMutationResolution.Promote,
            resolvePreparedLiveMutation(restarted, local = null)
        )
        val recovered = promotePreparedLiveMutation(restarted)
        assertTrue(recovered.localFinished)
        assertNull(recovered.preparedMutation)
        assertEquals(listOf(finish), recovered.pendingOperations)
        assertFalse(restarted.localFinished)
    }

    private fun restart(binding: LiveWorkoutBinding): LiveWorkoutBinding =
        LiveWorkoutSidecarCodec.decode(LiveWorkoutSidecarCodec.encode(binding))

    private fun localWorkout(
        revision: Long,
        undoableSetId: String? = null,
        set1: LiveLocalSetState = LiveLocalSetState(LOCAL_SET_1, 80.0, 8, false),
        set2: LiveLocalSetState = LiveLocalSetState(LOCAL_SET_2, 85.0, 6, false)
    ) = LiveLocalWorkoutState(
        startedAt = STARTED_AT,
        revision = revision,
        undoableSetId = undoableSetId,
        sets = mapOf(LOCAL_SET_1 to set1, LOCAL_SET_2 to set2)
    )

    private fun completeOperation(
        id: String,
        revision: Int,
        serverSetId: String,
        weight: Double,
        reps: Int
    ) = LivePendingOperation(
        clientOperationId = id,
        kind = LivePendingOperationKind.CompleteSet,
        expectedProgressRevision = revision,
        serverSetId = serverSetId,
        weight = weight,
        reps = reps
    )

    private fun binding(
        pendingOperations: List<LivePendingOperation> = emptyList(),
        preparedMutation: LivePreparedMutation? = null
    ) = LiveWorkoutBinding(
        userId = "42345678-1234-4123-8123-123456789abc",
        sessionGeneration = "52345678-1234-4123-8123-123456789abc",
        roomId = "lr_0123456789abcdef0123456789abcdef",
        role = "owner",
        peerProfileId = "p_0123456789abcdef0123456789abcdef",
        peerDisplayName = "Partner",
        roomRevision = 3,
        membershipRevision = 1,
        progressRevision = 1,
        workoutStartedAt = STARTED_AT,
        serverToLocalSetIds = mapOf(
            "s_01_01" to LOCAL_SET_1,
            "s_01_02" to LOCAL_SET_2
        ),
        pendingOperations = pendingOperations,
        preparedMutation = preparedMutation
    )

    private companion object {
        const val STARTED_AT = 1_786_330_800_000L
        const val LOCAL_SET_1 = "62345678-1234-4123-8123-123456789abc"
        const val LOCAL_SET_2 = "72345678-1234-4123-8123-123456789abc"
    }
}
