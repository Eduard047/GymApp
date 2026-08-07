package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutTimerLedgerTest {
    @Test
    fun manualStopResumesActiveTimeWithoutCountingRest() {
        var now = 10_000L
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val ledger = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        ledger.switchAccount(ACCOUNT)
        assertTrue(ledger.ensureSession(ACCOUNT, SESSION_START))

        now = 20_000L
        assertTrue(ledger.startRest(ACCOUNT, SESSION_START, seconds = 90))
        now = 50_000L
        assertEquals(10_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
        assertEquals(60, activeWorkoutRestSecondsRemaining(ledger.snapshot.value, now))

        assertTrue(ledger.resume(ACCOUNT, SESSION_START))
        now = 60_000L
        assertEquals(20_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
        assertEquals(0, activeWorkoutRestSecondsRemaining(ledger.snapshot.value, now))
    }

    @Test
    fun expiredRestRestoresAtDeadlineWithoutDoubleCounting() {
        var now = 10_000L
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val first = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        first.switchAccount(ACCOUNT)
        first.ensureSession(ACCOUNT, SESSION_START)
        now = 20_000L
        assertTrue(first.startRest(ACCOUNT, SESSION_START, seconds = 30))

        now = 40_000L
        val reopenedDuringRest = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        reopenedDuringRest.switchAccount(ACCOUNT)
        assertEquals(10_000L, activeWorkoutElapsedMillis(reopenedDuringRest.snapshot.value, now))
        assertEquals(10, activeWorkoutRestSecondsRemaining(reopenedDuringRest.snapshot.value, now))

        now = 60_000L
        assertEquals(20_000L, activeWorkoutElapsedMillis(reopenedDuringRest.snapshot.value, now))
        assertTrue(reopenedDuringRest.resumeIfExpired(ACCOUNT, SESSION_START))
        assertEquals(50_000L, reopenedDuringRest.snapshot.value?.activeSegmentStartedAt)

        now = 70_000L
        val reopenedAfterExpiry = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        reopenedAfterExpiry.switchAccount(ACCOUNT)
        assertEquals(30_000L, activeWorkoutElapsedMillis(reopenedAfterExpiry.snapshot.value, now))
    }

    @Test
    fun subtractingRemainingRestToZeroResumesImmediately() {
        var now = 10_000L
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val ledger = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        ledger.switchAccount(ACCOUNT)
        ledger.ensureSession(ACCOUNT, SESSION_START)
        now = 20_000L
        ledger.startRest(ACCOUNT, SESSION_START, seconds = 20)
        now = 25_000L

        assertEquals(0, ledger.adjustRest(ACCOUNT, SESSION_START, deltaSeconds = -15))
        assertNull(ledger.snapshot.value?.restEndsAt)
        assertEquals(25_000L, ledger.snapshot.value?.activeSegmentStartedAt)
        now = 30_000L
        assertEquals(15_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
    }

    @Test
    fun extendingRestMovesOnlyTheResumeDeadline() {
        var now = 10_000L
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val ledger = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        ledger.switchAccount(ACCOUNT)
        ledger.ensureSession(ACCOUNT, SESSION_START)
        now = 20_000L
        ledger.startRest(ACCOUNT, SESSION_START, seconds = 20)
        now = 25_000L

        assertEquals(30, ledger.adjustRest(ACCOUNT, SESSION_START, deltaSeconds = 15))
        now = 50_000L
        assertEquals(10_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
        assertEquals(5, activeWorkoutRestSecondsRemaining(ledger.snapshot.value, now))

        now = 60_000L
        assertTrue(ledger.resumeIfExpired(ACCOUNT, SESSION_START))
        assertEquals(15_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
        now = 70_000L
        assertEquals(25_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
    }

    @Test
    fun staleAdjustmentCannotRestartAnExpiredRest() {
        var now = 10_000L
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val ledger = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        ledger.switchAccount(ACCOUNT)
        ledger.ensureSession(ACCOUNT, SESSION_START)
        now = 20_000L
        ledger.startRest(ACCOUNT, SESSION_START, seconds = 20)
        now = 50_000L

        assertEquals(0, ledger.adjustRest(ACCOUNT, SESSION_START, deltaSeconds = 15))
        assertNull(ledger.snapshot.value?.restEndsAt)
        assertEquals(40_000L, ledger.snapshot.value?.activeSegmentStartedAt)
        assertEquals(20_000L, activeWorkoutElapsedMillis(ledger.snapshot.value, now))
    }

    @Test
    fun persistenceFailureDoesNotPublishFalseRestState() {
        var now = 10_000L
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val ledger = ActiveWorkoutTimerLedger(persistence, nowMillis = { now })
        ledger.switchAccount(ACCOUNT)
        ledger.ensureSession(ACCOUNT, SESSION_START)
        val before = ledger.snapshot.value
        now = 20_000L
        persistence.failNextSave = true

        assertFalse(ledger.startRest(ACCOUNT, SESSION_START, seconds = 90))
        assertEquals(before, ledger.snapshot.value)
        assertNull(ledger.snapshot.value?.restEndsAt)
    }

    @Test
    fun accountSwitchClearsSnapshotAndPersistedSession() {
        val persistence = InMemoryActiveWorkoutTimerPersistence()
        val ledger = ActiveWorkoutTimerLedger(persistence, nowMillis = { 10_000L })
        ledger.switchAccount(ACCOUNT)
        ledger.ensureSession(ACCOUNT, SESSION_START)

        ledger.switchAccount(OTHER_ACCOUNT)
        assertNull(ledger.snapshot.value)
        assertNull(persistence.load())
        assertFalse(ledger.clear(ACCOUNT, SESSION_START))

        ledger.switchAccount(ACCOUNT)
        assertNull(ledger.snapshot.value)
    }

    @Test
    fun foreignOwnerAndCorruptedRestSnapshotFailClosed() {
        val foreign = InMemoryActiveWorkoutTimerPersistence(
            ActiveWorkoutTimerSnapshot(
                accountKey = OTHER_ACCOUNT,
                sessionStartedAt = SESSION_START,
                accumulatedActiveMillis = 0L,
                activeSegmentStartedAt = SESSION_START,
                restEndsAt = null
            )
        )
        val foreignLedger = ActiveWorkoutTimerLedger(foreign, nowMillis = { 20_000L })
        foreignLedger.switchAccount(ACCOUNT)
        assertNull(foreignLedger.snapshot.value)

        val corrupted = InMemoryActiveWorkoutTimerPersistence(
            ActiveWorkoutTimerSnapshot(
                accountKey = ACCOUNT,
                sessionStartedAt = SESSION_START,
                accumulatedActiveMillis = 5_000L,
                activeSegmentStartedAt = null,
                restEndsAt = SESSION_START - 1L
            )
        )
        val corruptedLedger = ActiveWorkoutTimerLedger(corrupted, nowMillis = { 20_000L })
        corruptedLedger.switchAccount(ACCOUNT)
        assertNull(corruptedLedger.snapshot.value)
    }

    private class InMemoryActiveWorkoutTimerPersistence(
        initial: ActiveWorkoutTimerSnapshot? = null
    ) : ActiveWorkoutTimerPersistence {
        private var stored: ActiveWorkoutTimerSnapshot? = initial
        var failNextSave = false

        override fun load(): ActiveWorkoutTimerSnapshot? = stored?.copy()

        override fun save(snapshot: ActiveWorkoutTimerSnapshot?): Boolean {
            if (failNextSave) {
                failNextSave = false
                return false
            }
            stored = snapshot?.copy()
            return true
        }
    }

    private companion object {
        const val ACCOUNT = "a" +
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        const val OTHER_ACCOUNT = "b" +
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        const val SESSION_START = 10_000L
    }
}
