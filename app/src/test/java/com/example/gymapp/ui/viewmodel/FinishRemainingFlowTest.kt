package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.RecordActiveWorkoutSetsResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FinishRemainingFlowTest {
    @Test
    fun recordedBatchFinishesAgainstTheNewRevision() {
        val result = RecordActiveWorkoutSetsResult.Recorded(revision = 7L, count = 3)
        assertEquals(7L, activeWorkoutFinishRevisionAfterRecord(finishAfter = true, result = result))
    }

    @Test
    fun plainRecordAllNeverFinishes() {
        val result = RecordActiveWorkoutSetsResult.Recorded(revision = 7L, count = 3)
        assertNull(activeWorkoutFinishRevisionAfterRecord(finishAfter = false, result = result))
    }

    @Test
    fun failedRecordingNeverFinishes() {
        listOf(
            RecordActiveWorkoutSetsResult.Missing,
            RecordActiveWorkoutSetsResult.Stale,
            RecordActiveWorkoutSetsResult.TargetChanged,
            RecordActiveWorkoutSetsResult.AlreadyCompleted
        ).forEach { result ->
            assertNull(activeWorkoutFinishRevisionAfterRecord(finishAfter = true, result = result))
        }
    }
}
