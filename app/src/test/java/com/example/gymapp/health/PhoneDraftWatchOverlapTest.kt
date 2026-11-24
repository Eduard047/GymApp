package com.example.gymapp.health

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneDraftWatchOverlapTest {

    private val draftStart = 1_800_000_000_000L
    private val draftEnd = draftStart + 60 * 60 * 1_000L

    private fun candidate(
        startMillis: Long,
        durationSeconds: Long? = 45 * 60L,
        fromGarmin: Boolean = false,
        fromHealthImport: Boolean = false,
        latestWearCreateReceiptAt: Long? = null
    ) = StoredWorkoutOverlapCandidate(
        startMillis = startMillis,
        durationSeconds = durationSeconds,
        fromGarmin = fromGarmin,
        fromHealthImport = fromHealthImport,
        latestWearCreateReceiptAt = latestWearCreateReceiptAt
    )

    @Test
    fun wearWorkoutInsideTheDraftWindowOverlaps() {
        val start = draftStart + 5 * 60 * 1_000L
        val wear = candidate(start, latestWearCreateReceiptAt = start + 46 * 60 * 1_000L)
        assertTrue(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(wear)))
    }

    @Test
    fun garminAndHealthImportWorkoutsOverlap() {
        val start = draftStart + 10 * 60 * 1_000L
        assertTrue(
            PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(candidate(start, fromGarmin = true)))
        )
        assertTrue(
            PhoneDraftWatchOverlap.watchWorkoutCovers(
                draftStart,
                draftEnd,
                listOf(candidate(start, fromHealthImport = true))
            )
        )
    }

    @Test
    fun watchWorkoutOutsideTheDraftWindowDoesNotOverlap() {
        val start = draftEnd + 30 * 60 * 1_000L
        val garmin = candidate(start, fromGarmin = true)
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(garmin)))
    }

    @Test
    fun phoneWorkoutInTheSameWindowIsIgnored() {
        val start = draftStart + 5 * 60 * 1_000L
        val phone = candidate(start)
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(phone)))
    }

    @Test
    fun wearReceiptOlderThanTheWorkoutDoesNotMarkIt() {
        val start = draftStart + 5 * 60 * 1_000L
        val phone = candidate(start, latestWearCreateReceiptAt = start - 1L)
        assertFalse(PhoneDraftWatchOverlap.isFromWatchOrImport(phone))
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(phone)))
    }

    @Test
    fun toleranceEdgeIsInclusiveAndOneMillisecondBeyondIsNot() {
        val tolerance = HealthImportRules.OVERLAP_TOLERANCE_MILLIS
        // Watch workout that ended exactly 120 s before the draft started: still the same session.
        val endedJustBefore = candidate(
            startMillis = draftStart - tolerance - 30 * 60 * 1_000L,
            durationSeconds = 30 * 60L,
            fromGarmin = true
        )
        assertTrue(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(endedJustBefore)))
        val endedTooEarly = endedJustBefore.copy(startMillis = endedJustBefore.startMillis - 1L)
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(endedTooEarly)))

        // Watch workout that started exactly 120 s after the draft ended.
        val startedJustAfter = candidate(draftEnd + tolerance, fromHealthImport = true)
        assertTrue(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(startedJustAfter)))
        val startedTooLate = startedJustAfter.copy(startMillis = draftEnd + tolerance + 1L)
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(startedTooLate)))
    }

    @Test
    fun invalidDraftWindowNeverOverlaps() {
        val garmin = candidate(draftStart, fromGarmin = true)
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(0L, draftEnd, listOf(garmin)))
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftEnd, draftStart, listOf(garmin)))
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, emptyList()))
    }
}
