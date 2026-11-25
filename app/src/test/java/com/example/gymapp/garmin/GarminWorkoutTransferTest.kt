package com.example.gymapp.garmin

import org.junit.Assert.*
import org.junit.Test

class GarminWorkoutTransferTest {
    private val now = 1_780_000_000_000L
    private val binding = GarminBinding("a".repeat(64), "transfer-test-device", "b".repeat(64))
    private fun frame(offset: Int, total: Int = 60): MutableMap<Any?, Any?> = mutableMapOf(
        "type" to "workout_part", "transferVersion" to 1, "attemptId" to "transfer-attempt-$offset", "offset" to offset, "totalSets" to total,
        "metadata" to mapOf(
            "type" to "create_workout", "bindingVersion" to 2,
            "workoutMode" to "planned", "requestId" to "workout-transfer-test-001",
            "accountBinding" to binding.account, "deviceBinding" to binding.device,
            "pairingGeneration" to binding.pairingGeneration,
            "startedAtSeconds" to now / 1000 - 3600, "durationSeconds" to 3600,
            "gymCalories" to 60.0, "plannedSetCount" to total,
            "plannedTargetSetCount" to total, "completedPlannedSetCount" to total
        ),
        "set" to mapOf("exerciseName" to "Bench Press", "weight" to 50.0 + offset, "reps" to 8),
        "interval" to listOf(offset * 30, offset * 30 + 30, 1.0, null, 0, 0, 0, 0, 0, 0)
    )

    @Test fun attemptIdentityIsValidatedAndEchoedWithoutChangingDurableRows() {
        val first = GarminWorkoutTransfer.accept(null, frame(0), binding, now)!!
        val retry = frame(0).apply { this["attemptId"] = "transfer-retry-00001" }
        val replay = GarminWorkoutTransfer.accept(first.state, retry, binding, now)!!
        assertEquals("transfer-retry-00001", replay.attemptId)
        assertEquals(first.state, replay.state)
        for (invalid in listOf(null, "", "short", "a".repeat(129), "invalid-attempt\nvalue", 17)) {
            retry["attemptId"] = invalid
            assertNull(GarminWorkoutTransfer.accept(first.state, retry, binding, now))
        }
    }

    @Test fun sixtySetsSurviveSerializedRestartAndCompleteExactlyOnce() {
        var state: String? = null
        for (offset in 0 until 60) {
            val result = GarminWorkoutTransfer.accept(state, frame(offset), binding, now)!!
            assertEquals(offset + 1, result.nextOffset)
            if (offset < 59) assertNull(result.completeMessage)
            else {
                val parsed = parseGarminWorkoutCommand(result.completeMessage!!, now)!!
                assertEquals(60, parsed.sets.size)
                assertEquals(109.0, parsed.sets.last().weight, 0.0)
                assertEquals(60, parsed.setIntervals.size)
            }
            state = result.state
            val replay = GarminWorkoutTransfer.accept(state, frame(offset), binding, now)!!
            assertEquals(state, replay.state)
        }
    }

    @Test fun rejectsGapsConflictsOwnershipAndChangedMetadataWithoutMutatingPrefix() {
        val first = GarminWorkoutTransfer.accept(null, frame(0), binding, now)!!
        assertNull(GarminWorkoutTransfer.accept(first.state, frame(2), binding, now))
        val conflict = frame(0).apply { this["set"] = mapOf("exerciseName" to "Squat", "weight" to 50, "reps" to 8) }
        assertNull(GarminWorkoutTransfer.accept(first.state, conflict, binding, now))
        assertNull(GarminWorkoutTransfer.accept(first.state, frame(1), binding.copy(account = "c".repeat(64)), now))
        assertNull(GarminWorkoutTransfer.accept(first.state, frame(1), binding.copy(pairingGeneration = "c".repeat(64)), now))
        assertNull(GarminWorkoutTransfer.accept(first.state, frame(1, 59), binding, now))
        assertNotNull(GarminWorkoutTransfer.accept(first.state, frame(1), binding, now))
    }

    @Test fun validatesStoredPrefixAndAggregateIntervals() {
        val first = GarminWorkoutTransfer.accept(null, frame(0, 2), binding, now)!!
        assertNull(GarminWorkoutTransfer.accept(first.state.replace("Bench Press", ""), frame(1, 2), binding, now))
        val overlap = frame(1, 2).apply { this["interval"] = listOf(0, 30, 1.0, null, 0, 0, 0, 0, 0, 0) }
        assertNull(GarminWorkoutTransfer.accept(first.state, overlap, binding, now))
        val missing = frame(1, 2).apply { remove("interval") }
        assertNull(GarminWorkoutTransfer.accept(first.state, missing, binding, now))
    }

    @Test fun rejectsMalformedOversizedAndExpiredContinuationButAllowsCleanRetry() {
        assertNull(GarminWorkoutTransfer.accept(null, frame(0).apply { this["offset"] = true }, binding, now))
        assertNull(GarminWorkoutTransfer.accept(null, frame(0).apply { this["extra"] = "x" }, binding, now))
        assertNull(GarminWorkoutTransfer.accept(null, frame(0).apply { this["interval"] = listOf(Double.NaN) }, binding, now))
        val oversized = frame(0).apply { this["set"] = mapOf("exerciseName" to "x".repeat(641), "weight" to 0, "reps" to 1) }
        assertNull(GarminWorkoutTransfer.accept(null, oversized, binding, now))
        assertNull(GarminWorkoutTransfer.accept("[".repeat(100), frame(0), binding, now))
        val first = GarminWorkoutTransfer.accept(null, frame(0), binding, now)!!
        assertNull(GarminWorkoutTransfer.accept(first.state, frame(1), binding, now + 86_400_001))
        assertNotNull(GarminWorkoutTransfer.accept(first.state, frame(0), binding, now + 86_400_001))
    }

    @Test fun freeWorkoutKeepsMetricsAndHasNoInventedSets() {
        val free = frame(0).apply {
            this["totalSets"] = 0
            remove("set"); remove("interval")
            @Suppress("UNCHECKED_CAST")
            this["metadata"] = (this["metadata"] as Map<String, Any>).toMutableMap().apply {
                this["workoutMode"] = "free"
                remove("plannedSetCount"); remove("plannedTargetSetCount"); remove("completedPlannedSetCount")
            }
        }
        val step = GarminWorkoutTransfer.accept(null, free, binding, now)!!
        val workout = parseGarminWorkoutCommand(step.completeMessage!!, now)!!
        assertEquals(GarminWorkoutMode.Free, workout.mode)
        assertTrue(workout.sets.isEmpty())
        assertEquals(3600L, workout.durationSeconds)
    }
    @Test fun fileStoreRestartsAndRefusesBadWritesWithoutLosingAcknowledgedPrefix() {
        val directory = kotlin.io.path.createTempDirectory("garmin-transfer-store-test").toFile()
        try {
            val file = java.io.File(directory, "parts.json")
            val first = GarminWorkoutTransferStore(file).accept(frame(0, 2), binding, now)!!
            assertNull(GarminWorkoutTransferStore(file).accept(frame(1, 3), binding, now))
            assertEquals(first.state, file.readText())
            assertTrue(GarminWorkoutTransferStore(file).clearAccount("c".repeat(64)))
            assertEquals(first.state, file.readText())
            assertNotNull(GarminWorkoutTransferStore(file).accept(frame(1, 2), binding, now)?.completeMessage)
            assertTrue(GarminWorkoutTransferStore(file).clearAccount(binding.account))
            assertFalse(file.exists())
            assertTrue(directory.listFiles()!!.isEmpty())
        } finally { directory.deleteRecursively() }
    }

    @Test fun freshBoundGenerationRestartsOnlyFromOffsetZero() {
        val first = GarminWorkoutTransfer.accept(null, frame(0), binding, now)!!
        val nextBinding = binding.copy(pairingGeneration = "c".repeat(64))
        fun next(offset: Int) = frame(offset).apply {
            @Suppress("UNCHECKED_CAST")
            this["metadata"] = (this["metadata"] as Map<String, Any>).toMutableMap().apply {
                this["pairingGeneration"] = nextBinding.pairingGeneration
            }
        }
        assertNull(GarminWorkoutTransfer.accept(first.state, next(1), nextBinding, now))
        assertEquals(1, GarminWorkoutTransfer.accept(first.state, next(0), nextBinding, now)?.nextOffset)
        val frame = frame(0)
        val copy = GarminWorkoutTransfer.copyFrame(frame)!!
        frame["metadata"] = emptyMap<String, Any>()
        val envelope = boundedGarminInboundEnvelopes(listOf(copy)).single()
        assertEquals(GarminInboundCommandKind.Workout, envelope.kind)
        assertNotNull(GarminWorkoutTransfer.accept(null, envelope.command, binding, now))
        assertNotNull(GarminWorkoutTransfer.accept(null, copy, binding, now))
    }


    private fun otherRequest(offset: Int, total: Int = 60) = frame(offset, total).apply {
        @Suppress("UNCHECKED_CAST")
        this["metadata"] = (this["metadata"] as Map<String, Any>).toMutableMap().apply {
            this["requestId"] = "workout-transfer-test-002"
        }
    }

    @Test fun firstFrameOfAnotherRequestReplacesRetainedStagingFromTheSameWatch() {
        // Workout A was half received (or retained after a rejection) and is no longer the head.
        var state = GarminWorkoutTransfer.accept(null, frame(0, 3), binding, now)!!.state
        state = GarminWorkoutTransfer.accept(state, frame(1, 3), binding, now)!!.state
        val replaced = GarminWorkoutTransfer.accept(state, otherRequest(0, 2), binding, now)!!
        assertEquals(1, replaced.nextOffset)
        assertTrue(replaced.state.contains("workout-transfer-test-002"))
        assertFalse(replaced.state.contains("workout-transfer-test-001"))
        assertNotNull(GarminWorkoutTransfer.accept(replaced.state, otherRequest(1, 2), binding, now)?.completeMessage)
        // A continuation frame of another request never replaces anything.
        assertNull(GarminWorkoutTransfer.accept(state, otherRequest(1, 3), binding, now))
        // Another account or generation is still not this watch's staging to continue.
        assertNull(GarminWorkoutTransfer.accept(state, otherRequest(0, 2), binding.copy(account = "c".repeat(64)), now))
    }

    @Test fun firstFrameOfTheSameRequestKeepsRetainedStaging() {
        var state = GarminWorkoutTransfer.accept(null, frame(0, 3), binding, now)!!.state
        state = GarminWorkoutTransfer.accept(state, frame(1, 3), binding, now)!!.state
        val restart = frame(0, 3).apply { this["attemptId"] = "transfer-restart-0001" }
        val resumed = GarminWorkoutTransfer.accept(state, restart, binding, now)!!
        assertEquals(2, resumed.nextOffset)
        assertEquals(state, resumed.state)
        // Same request ID with changed metadata is still a conflict, not a replacement.
        assertNull(GarminWorkoutTransfer.accept(state, frame(0, 4), binding, now))
    }

    @Test fun unreadableStoreFileIsDiscardedAndDoesNotBlockReceiveOrCleanup() {
        val directory = kotlin.io.path.createTempDirectory("garmin-transfer-store-corrupt").toFile()
        try {
            val file = java.io.File(directory, "parts.json")
            file.writeText("{\"version\":1,\"createdAt\":")
            assertFalse(GarminWorkoutTransfer.isReadableState(file.readText()))
            assertEquals(1, GarminWorkoutTransferStore(file).accept(frame(0, 2), binding, now)?.nextOffset)
            assertTrue(GarminWorkoutTransfer.isReadableState(file.readText()))

            // A corrupt file plus a frame that cannot start a transfer: the file is still removed.
            file.writeBytes(byteArrayOf(0xC3.toByte(), 0x28))
            assertNull(GarminWorkoutTransferStore(file).accept(frame(1, 2), binding, now))
            assertFalse(file.exists())

            // Account cleanup no longer aborts on an unreadable file.
            file.writeText("not json")
            assertTrue(GarminWorkoutTransferStore(file).clearAccount("c".repeat(64)))
            assertFalse(file.exists())
        } finally { directory.deleteRecursively() }
    }
}
