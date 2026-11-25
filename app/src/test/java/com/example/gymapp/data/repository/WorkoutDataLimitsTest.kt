package com.example.gymapp.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutDataLimitsTest {
    @Test
    fun numericLimitsRejectNonFiniteAndOutOfRangeWorkoutValues() {
        assertFalse(WorkoutDataLimits.isValidWeight(Double.NaN))
        assertFalse(WorkoutDataLimits.isValidWeight(Double.POSITIVE_INFINITY))
        assertFalse(WorkoutDataLimits.isValidWeight(-0.01))
        assertFalse(WorkoutDataLimits.isValidWeight(WorkoutDataLimits.MAX_WEIGHT + 0.01))
        assertTrue(WorkoutDataLimits.isValidWeight(0.0))
        assertTrue(WorkoutDataLimits.isValidWeight(WorkoutDataLimits.MAX_WEIGHT))

        assertFalse(WorkoutDataLimits.isValidReps(0))
        assertFalse(WorkoutDataLimits.isValidReps(WorkoutDataLimits.MAX_REPS + 1))
        assertTrue(WorkoutDataLimits.isValidReps(1))
        assertTrue(WorkoutDataLimits.isValidReps(WorkoutDataLimits.MAX_REPS))

        assertTrue(WorkoutDataLimits.canAddSets(WorkoutDataLimits.MAX_TOTAL_SETS - 1, 1))
        assertFalse(WorkoutDataLimits.canAddSets(WorkoutDataLimits.MAX_TOTAL_SETS, 1))
        assertFalse(WorkoutDataLimits.canAddSets(Int.MAX_VALUE, Int.MAX_VALUE))
    }

    @Test
    fun rawJsonEnvelopeRejectsExcessiveDepthBeforeParsing() {
        val tooDeep = "[".repeat(WorkoutDataLimits.MAX_JSON_NESTING_DEPTH + 1) +
            "]".repeat(WorkoutDataLimits.MAX_JSON_NESTING_DEPTH + 1)

        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(tooDeep)
        }
        WorkoutDataLimits.requireSafeJsonEnvelope("{\"sessions\":[]}")
    }

    @Test
    fun rawJsonEnvelopeBoundsArraysAndTotalValuesBeforeDomAllocation() {
        val oversizedArray = "[" +
            "0,".repeat(WorkoutDataLimits.MAX_JSON_ARRAY_ENTRIES) +
            "0]"
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(oversizedArray)
        }

        val boundedLargeArray = "[" + "0,".repeat(89_999) + "0]"
        val excessiveValueGraph = "[" + List(4) { boundedLargeArray }.joinToString(",") + "]"
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(excessiveValueGraph)
        }
    }

    @Test
    fun rawJsonEnvelopeRejectsDuplicateKeysAndOversizedObjects() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope("{\"sessions\":[],\"sessions\":[]}")
        }

        val oversizedObject = buildString {
            append('{')
            repeat(WorkoutDataLimits.MAX_JSON_OBJECT_MEMBERS + 1) { index ->
                if (index > 0) append(',')
                append('"').append('k').append(index).append("\":0")
            }
            append('}')
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(oversizedObject)
        }
    }

    @Test
    fun rawJsonEnvelopeRejectsOversizedNumberTokensBeforeDomAllocation() {
        WorkoutDataLimits.requireSafeJsonEnvelope("{\"value\":-123.5e+20}")

        val oversizedInteger = "{\"value\":" +
            "9".repeat(WorkoutDataLimits.MAX_JSON_NUMBER_CHARS + 1) + "}"
        val oversizedExponent = "{\"value\":1e" +
            "9".repeat(WorkoutDataLimits.MAX_JSON_NUMBER_CHARS) + "}"
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(oversizedInteger)
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(oversizedExponent)
        }
    }

    @Test
    fun rawJsonEnvelopeCountsUtf8BytesInsteadOfUtf16Characters() {
        val multiByte = "{\"x\":\"" + "€".repeat(WorkoutDataLimits.MAX_BACKUP_BYTES / 3) + "\"}"

        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(multiByte)
        }
    }

    @Test
    fun editorRetentionRejectsOversizedClipboardTextBeforeStateAssignment() {
        assertTrue(WorkoutDataLimits.canRetainBackupText("{\"sessions\":[]}"))
        assertFalse(
            WorkoutDataLimits.canRetainBackupText(
                "a".repeat(WorkoutDataLimits.MAX_BACKUP_BYTES + 1)
            )
        )
        assertFalse(
            WorkoutDataLimits.canRetainBackupText(
                "€".repeat(WorkoutDataLimits.MAX_BACKUP_BYTES / 3 + 1)
            )
        )
    }

    @Test
    fun fieldLimitsBoundUtf8AndRawJsonStrings() {
        assertTrue(WorkoutDataLimits.isValidExerciseName("🏋".repeat(160)))
        assertFalse(WorkoutDataLimits.isValidExerciseName("🏋".repeat(161)))
        assertTrue(WorkoutDataLimits.isValidNote("€".repeat(4_000)))
        assertTrue(WorkoutDataLimits.isValidNote("line one\nline two"))
        assertFalse(WorkoutDataLimits.isValidNote("unsafe\u0001note"))
        assertNull(WorkoutDataLimits.noteFailure(null))
        assertNull(WorkoutDataLimits.noteFailure("tab\tand\r\nnewline"))
        assertEquals(WorkoutDataLimits.NoteFailure.CONTROL_CHARACTER, WorkoutDataLimits.noteFailure("unsafe\u0001note"))
        assertEquals(WorkoutDataLimits.NoteFailure.TOO_LONG, WorkoutDataLimits.noteFailure("x".repeat(4_001)))
        assertEquals(WorkoutDataLimits.NoteFailure.TOO_LONG, WorkoutDataLimits.noteFailure("\u0001".repeat(4_001)))
        assertFalse(WorkoutDataLimits.isValidExerciseName("unsafe\u0001name"))

        val oversizedString =
            "{\"x\":\"" + "a".repeat(WorkoutDataLimits.MAX_JSON_STRING_BYTES + 1) + "\"}"
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(oversizedString)
        }
    }

    @Test
    fun projectedBackupBudgetFailsBeforeLargeDatabaseMaterialization() {
        assertTrue(
            WorkoutDataLimits.isBackupProjectionWithinLimit(
                exerciseCount = 10,
                sessionCount = 10,
                workoutExerciseCount = 20,
                setCount = 100,
                textUtf8Bytes = 10_000
            )
        )
        assertFalse(
            WorkoutDataLimits.isBackupProjectionWithinLimit(
                exerciseCount = 2_000,
                sessionCount = 5_000,
                workoutExerciseCount = 100_000,
                setCount = 100_000,
                textUtf8Bytes = WorkoutDataLimits.MAX_BACKUP_BYTES.toLong()
            )
        )
    }

    @Test
    fun finishedActiveWorkoutDurationIsClampedInsteadOfRejected() {
        val start = 1_750_000_000_000L
        val day = 24L * 60L * 60L * 1_000L
        val max = WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS

        // An 8-day-old workout (or a clock jump forward) still finishes, at the 7-day maximum.
        assertEquals(max, WorkoutDataLimits.clampedActiveWorkoutDurationSeconds(start, start + 8L * day))
        assertTrue(WorkoutDataLimits.isValidWorkoutDuration(max))
        // A clock moved back before the start saves zero seconds.
        assertEquals(0L, WorkoutDataLimits.clampedActiveWorkoutDurationSeconds(start, start - 5_000L))
        assertEquals(0L, WorkoutDataLimits.clampedActiveWorkoutDurationSeconds(start, start))
        // Normal workouts keep whole seconds, truncated.
        assertEquals(3_600L, WorkoutDataLimits.clampedActiveWorkoutDurationSeconds(start, start + 3_600_999L))
        assertEquals(max, WorkoutDataLimits.clampedActiveWorkoutDurationSeconds(start, start + max * 1_000L))
        // Corrupt extremes never overflow into a negative duration.
        assertEquals(max, WorkoutDataLimits.clampedActiveWorkoutDurationSeconds(Long.MIN_VALUE, Long.MAX_VALUE))
        // Strict validation for imported/synced data is unchanged.
        assertFalse(WorkoutDataLimits.isValidWorkoutDuration(max + 1L))
        assertFalse(WorkoutDataLimits.isValidWorkoutDuration(-1L))
    }
}
