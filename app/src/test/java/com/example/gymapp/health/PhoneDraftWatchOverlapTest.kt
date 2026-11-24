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
        fromHealthImport: Boolean = false
    ) = StoredWorkoutOverlapCandidate(
        startMillis = startMillis,
        durationSeconds = durationSeconds,
        fromGarmin = fromGarmin,
        fromHealthImport = fromHealthImport
    )

    private val minute = 60 * 1_000L
    private val hour = 60 * minute

    @Test
    fun wearWorkoutInsideTheDraftWindowOverlaps() {
        val start = draftStart + 5 * 60 * 1_000L
        val wear = candidate(start)
        assertTrue(
            PhoneDraftWatchOverlap.watchWorkoutCovers(
                draftStart,
                draftEnd,
                listOf(wear),
                wearCreateReceiptTimes = listOf(start + 46 * minute)
            )
        )
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
        val start = draftStart + 5 * minute
        val phone = candidate(start)
        val receipts = listOf(start - 1L)
        assertFalse(PhoneDraftWatchOverlap.isFromWatchOrImport(phone, listOf(phone), receipts))
        assertFalse(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, listOf(phone), receipts))
    }

    @Test
    fun wearReceiptAfterTheWindowDoesNotMarkIt() {
        val start = draftStart + 5 * minute
        val phone = candidate(start, durationSeconds = 45 * 60L)
        val windowEnd = start + 45 * minute + PhoneDraftWatchOverlap.WEAR_RECEIPT_WINDOW_MILLIS
        assertTrue(PhoneDraftWatchOverlap.isFromWear(phone, listOf(phone), listOf(windowEnd)))
        assertFalse(PhoneDraftWatchOverlap.isFromWear(phone, listOf(phone), listOf(windowEnd + 1L)))
    }

    @Test
    fun laterWearWorkoutReceiptDoesNotMarkAnEarlierPhoneWorkout() {
        // Phone workout A 10:00-11:00 is saved; a Wear workout W 11:05-11:30 syncs at 11:31;
        // phone workout B starts at 11:01. A ended just inside the tolerance of B but is not a
        // watch workout, so finishing B must not prompt.
        val phoneA = candidate(draftStart - 61 * minute, durationSeconds = 60 * 60L)
        val wearW = candidate(draftStart + 4 * minute, durationSeconds = 25 * 60L)
        val receipts = listOf(draftStart + 30 * minute)
        val all = listOf(phoneA, wearW)
        assertFalse(PhoneDraftWatchOverlap.isFromWear(phoneA, all, receipts))
        assertTrue(PhoneDraftWatchOverlap.isFromWear(wearW, all, receipts))
        // B overlaps only A (B ends more than the tolerance before W starts): no prompt.
        assertFalse(
            PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftStart + minute, all, receipts)
        )
        // B that also covers W still prompts.
        assertTrue(PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftEnd, all, receipts))
    }

    @Test
    fun wearReceiptHoursAfterAnUnrelatedPhoneWorkoutDoesNotMarkIt() {
        // The old global "newest receipt" marked every earlier workout; a receipt 7 h after A ends does not.
        val phoneA = candidate(draftStart - 61 * minute, durationSeconds = 60 * 60L)
        val receipts = listOf(draftStart - minute + 7 * hour)
        assertFalse(
            PhoneDraftWatchOverlap.watchWorkoutCovers(draftStart, draftStart + 2 * minute, listOf(phoneA), receipts)
        )
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
