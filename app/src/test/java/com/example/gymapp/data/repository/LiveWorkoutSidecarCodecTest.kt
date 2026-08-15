package com.example.gymapp.data.repository

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LiveWorkoutSidecarCodecTest {
    @Test
    fun `draft send receipt survives process restart with exact security binding`() {
        val receipt = draftSendReceipt()
        val persisted = LiveWorkoutDraftSendReceiptCodec.encode(receipt)

        assertEquals(receipt, LiveWorkoutDraftSendReceiptCodec.decode(persisted))
        assertEquals(
            receipt.copy(roomId = "lr_1123456789abcdef0123456789abcdef"),
            LiveWorkoutDraftSendReceiptCodec.decode(
                LiveWorkoutDraftSendReceiptCodec.encode(
                    receipt.copy(roomId = "lr_1123456789abcdef0123456789abcdef")
                )
            )
        )
    }

    @Test
    fun `draft send receipt rejects partial or substituted restart identity`() {
        val receipt = draftSendReceipt()
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutDraftSendReceiptCodec.encode(receipt.copy(draftBindingId = "not-a-uuid"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutDraftSendReceiptCodec.encode(receipt.copy(draftFingerprint = "b".repeat(63)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutDraftSendReceiptCodec.encode(
                receipt.copy(recipientFriendshipId = "f_ffffffffffffffffffffffffffffffff")
                    .copy(recipientFriendshipRevision = 0)
            )
        }
        val unknownField = JSONObject(LiveWorkoutDraftSendReceiptCodec.encode(receipt))
            .put("accessToken", "must-never-be-stored")
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutDraftSendReceiptCodec.decode(unknownField.toString())
        }
    }

    @Test
    fun `reservation codec is account session room and expiry bound`() {
        val reservation = LiveWorkoutReservation(
            userId = "42345678-1234-4123-8123-123456789abc",
            sessionGeneration = "52345678-1234-4123-8123-123456789abc",
            role = "owner",
            operationId = "12345678-1234-4123-8123-123456789abc",
            roomId = "lr_0123456789abcdef0123456789abcdef",
            phase = LiveWorkoutReservationPhase.Waiting,
            createdAt = 1_786_330_800_000L,
            expiresAt = 1_786_417_200_000L
        )

        assertEquals(
            reservation,
            LiveWorkoutReservationCodec.decode(LiveWorkoutReservationCodec.encode(reservation))
        )
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutReservationCodec.encode(
                reservation.copy(sessionGeneration = "wrong-session")
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutReservationCodec.encode(
                reservation.copy(phase = LiveWorkoutReservationPhase.Preparing)
            )
        }
    }

    @Test
    fun `codec round trips account binding mapping and idempotent queue`() {
        val binding = binding(
            pendingOperations = listOf(
                LivePendingOperation(
                    clientOperationId = "12345678-1234-4123-8123-123456789abc",
                    kind = LivePendingOperationKind.CompleteSet,
                    expectedProgressRevision = 1,
                    serverSetId = "s_01_01",
                    weight = 82.5,
                    reps = 7
                ),
                LivePendingOperation(
                    clientOperationId = "22345678-1234-4123-8123-123456789abc",
                    kind = LivePendingOperationKind.Finish,
                    expectedProgressRevision = 2,
                    serverSetId = null,
                    weight = null,
                    reps = null
                )
            )
        )

        assertEquals(binding, LiveWorkoutSidecarCodec.decode(LiveWorkoutSidecarCodec.encode(binding)))
    }

    @Test
    fun `codec round trips a durable prepared local mutation`() {
        val operation = LivePendingOperation(
            clientOperationId = "12345678-1234-4123-8123-123456789abc",
            kind = LivePendingOperationKind.CompleteSet,
            expectedProgressRevision = 1,
            serverSetId = "s_01_01",
            weight = 82.5,
            reps = 7
        )
        val binding = binding(
            preparedMutation = LivePreparedMutation(
                localMutationId = "22345678-1234-4123-8123-123456789abc",
                kind = LivePreparedMutationKind.CompleteSet,
                expectedLocalRevision = 9,
                operations = listOf(operation)
            )
        )

        assertEquals(binding, LiveWorkoutSidecarCodec.decode(LiveWorkoutSidecarCodec.encode(binding)))
    }

    @Test
    fun `codec keeps reading version one sidecars after the prepared mutation upgrade`() {
        val binding = binding()
        val legacy = JSONObject(LiveWorkoutSidecarCodec.encode(binding))
            .put("version", 1)
            .apply { remove("preparedMutation") }

        assertEquals(binding, LiveWorkoutSidecarCodec.decode(legacy.toString()))
    }

    @Test
    fun `codec rejects malformed operation shape and unknown fields`() {
        val root = JSONObject(LiveWorkoutSidecarCodec.encode(binding()))
        root.put("accessToken", "must-never-be-stored")
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutSidecarCodec.decode(root.toString())
        }

        val invalid = binding(
            pendingOperations = listOf(
                LivePendingOperation(
                    clientOperationId = "12345678-1234-4123-8123-123456789abc",
                    kind = LivePendingOperationKind.UndoSet,
                    expectedProgressRevision = 2,
                    serverSetId = "s_01_01",
                    weight = 80.0,
                    reps = null
                )
            )
        )
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutSidecarCodec.encode(invalid)
        }

        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutSidecarCodec.decode(
                LiveWorkoutSidecarCodec.encode(binding()) + " trailing"
            )
        }
    }

    @Test
    fun `codec rejects mapping outside canonical local workout ids`() {
        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutSidecarCodec.encode(
                binding(serverToLocalSetIds = mapOf("s_01_01" to "not-a-local-id"))
            )
        }
    }

    @Test
    fun `codec rejects a queue whose expected revision skips canonical order`() {
        val skipped = binding(
            pendingOperations = listOf(
                LivePendingOperation(
                    clientOperationId = "12345678-1234-4123-8123-123456789abc",
                    kind = LivePendingOperationKind.CompleteSet,
                    expectedProgressRevision = 2,
                    serverSetId = "s_01_01",
                    weight = 80.0,
                    reps = 8
                )
            )
        )

        assertThrows(IllegalArgumentException::class.java) {
            LiveWorkoutSidecarCodec.encode(skipped)
        }
    }

    private fun binding(
        serverToLocalSetIds: Map<String, String> = mapOf(
            "s_01_01" to "32345678-1234-4123-8123-123456789abc"
        ),
        pendingOperations: List<LivePendingOperation> = emptyList(),
        preparedMutation: LivePreparedMutation? = null,
        localFinished: Boolean = pendingOperations.any {
            it.kind == LivePendingOperationKind.Finish
        }
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
        workoutStartedAt = 1_786_330_800_000L,
        serverToLocalSetIds = serverToLocalSetIds,
        localFinished = localFinished,
        pendingOperations = pendingOperations,
        preparedMutation = preparedMutation
    )

    private fun draftSendReceipt() = LiveWorkoutDraftSendReceipt(
        userId = "42345678-1234-4123-8123-123456789abc",
        sessionGeneration = "52345678-1234-4123-8123-123456789abc",
        draftBindingId = "62345678-1234-4123-8123-123456789abc",
        recipientProfileId = "p_0123456789abcdef0123456789abcdef",
        recipientFriendshipId = "f_0123456789abcdef0123456789abcdef",
        recipientFriendshipRevision = 7,
        operationId = "12345678-1234-4123-8123-123456789abc",
        roomId = null,
        draftFingerprint = "a".repeat(64),
        createdAt = 1_786_330_800_000L,
        expiresAt = 1_786_417_200_000L
    )
}
