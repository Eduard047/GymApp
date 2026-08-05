package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutViewModelTest {
    @Test
    fun validSetInputAcceptsBlankWeightAndCommaDecimal() {
        assertEquals(ParsedActiveWorkoutSet(weight = 0.0, reps = 12), parseActiveWorkoutSetInput("", "12"))
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
    fun recordGateRejectsConcurrentAndReplayClicks() {
        val gate = ActiveWorkoutSetRecordGate()

        assertTrue(gate.tryStart("first-set"))
        assertFalse(gate.tryStart("first-set"))
        assertFalse(gate.tryStart("second-set"))
        assertEquals(setOf("first-set"), gate.inFlight.value)

        gate.finish("first-set")
        assertTrue(gate.tryStart("second-set"))
    }
}
