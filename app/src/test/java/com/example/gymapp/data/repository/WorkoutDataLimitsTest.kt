package com.example.gymapp.data.repository

import org.json.JSONObject
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
        val arrayCount = WorkoutDataLimits.MAX_JSON_VALUE_COUNT / 90_000 + 1
        val excessiveValueGraph = "[" +
            List(arrayCount) { boundedLargeArray }.joinToString(",") + "]"
        assertTrue(excessiveValueGraph.length <= WorkoutDataLimits.MAX_BACKUP_BYTES)
        assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(excessiveValueGraph)
        }
    }

    @Test
    fun valueCountPreflightAdmitsAndroidBackupAtEveryRowLimit() {
        // Android/PWA shape at MAX_EXERCISES, MAX_SESSIONS and MAX_TOTAL_SETS with one set per
        // block (the most blocks the set limit allows). Only the value count is under test, so
        // the byte budget is raised to the preflight maximum.
        val (raw, values) = rowLimitBackup(
            weightsPerExercise = 16,
            blockLoadProfileHeaders = false
        )

        assertEquals(837_028, values)
        assertTrue(values <= WorkoutDataLimits.MAX_JSON_VALUE_COUNT)
        WorkoutDataLimits.requireSafeJsonEnvelope(raw, maximumBytes = PREFLIGHT_MAX_BYTES)
    }

    @Test
    fun valueCountPreflightRejectsWorstCaseShapeToBoundImportHeap() {
        // Documented trade-off: 128 weights on every exercise plus a load-profile header on all
        // 100k one-set blocks is a valid row-limit shape in theory, but admitting ~1.47M values
        // would let a hostile file allocate that many org.json objects on import.
        val (raw, values) = rowLimitBackup(
            weightsPerExercise = ExerciseLoadProfile.MAX_WEIGHT_OPTIONS,
            blockLoadProfileHeaders = true
        )

        assertTrue(values > WorkoutDataLimits.MAX_JSON_VALUE_COUNT)
        val error = assertThrows(IllegalArgumentException::class.java) {
            WorkoutDataLimits.requireSafeJsonEnvelope(raw, maximumBytes = PREFLIGHT_MAX_BYTES)
        }
        assertEquals("Backup exceeds the JSON value limit.", error.message)
    }

    /** Builds a compact backup at every row limit and returns it with its JSON value count. */
    private fun rowLimitBackup(
        weightsPerExercise: Int,
        blockLoadProfileHeaders: Boolean
    ): Pair<String, Int> {
        val blocksPerSession = WorkoutDataLimits.MAX_TOTAL_SETS / WorkoutDataLimits.MAX_SESSIONS
        val weights = (0 until weightsPerExercise).joinToString(",")
        var values = 0
        val raw = StringBuilder(14 * 1_024 * 1_024)
        raw.append("{\"schemaVersion\":2,\"exportedAt\":1,\"app\":\"GymApp\",")
        raw.append("\"diagnostics\":false,\"catalogSeedVersion\":1,")
        raw.append("\"owner\":{\"accountId\":null,\"userId\":null,\"email\":null,\"remote\":false},")
        values += 1 + 5 + 5
        raw.append("\"exercises\":[")
        values += 1
        repeat(WorkoutDataLimits.MAX_EXERCISES) { index ->
            if (index > 0) raw.append(',')
            raw.append("{\"name\":\"e$index\",\"catalogKey\":\"k\",\"favorite\":false,")
            raw.append("\"loadProfile\":{\"direction\":\"a\",\"allowedWeightsKg\":[$weights]}}")
            values += 7 + weightsPerExercise
        }
        raw.append("],\"sessions\":[")
        values += 1
        repeat(WorkoutDataLimits.MAX_SESSIONS) { sessionIndex ->
            if (sessionIndex > 0) raw.append(',')
            raw.append("{\"date\":1,\"note\":null,\"durationSeconds\":1,\"exercises\":[")
            values += 5
            repeat(blocksPerSession) { blockIndex ->
                if (blockIndex > 0) raw.append(',')
                raw.append("{\"name\":\"a\",\"catalogKey\":\"a\",")
                if (blockLoadProfileHeaders) {
                    raw.append("\"favorite\":false,")
                    raw.append("\"loadProfile\":{\"direction\":\"a\",\"allowedWeightsKg\":[]},")
                    values += 4
                }
                raw.append("\"sets\":[{\"weight\":0,\"reps\":1}]}")
                values += 4 + 3
            }
            raw.append("]}")
        }
        raw.append("],\"summary\":{\"exerciseCount\":1,\"sessionCount\":1,\"setCount\":1,\"totalVolume\":0},")
        values += 5
        raw.append("\"extensions\":{\"pwa\":{\"version\":1,\"language\":\"en\",\"mappings\":{")
        values += 5
        val muscles = List(32) { "\"m\"" }.joinToString(",")
        repeat(WorkoutDataLimits.MAX_EXERCISES) { index ->
            if (index > 0) raw.append(',')
            raw.append("\"e$index\":[$muscles]")
            values += 1 + 32
        }
        raw.append("},\"profile\":{\"split\":\"a\",\"days\":3,\"goal\":\"a\",\"calories\":1}}}}")
        values += 5
        return raw.toString() to values
    }

    private companion object {
        const val PREFLIGHT_MAX_BYTES = 16 * 1_024 * 1_024
    }

    @Test
    fun manualBackupExportIsCompactAndRoundTrips() {
        val root = JSONObject(
            """
            {
              "schemaVersion": 2,
              "exercises": [{"name": "Bench Press"}],
              "sessions": [{
                "date": 1700000000000,
                "note": "line one\nline two",
                "exercises": [{"name": "Bench Press", "sets": [{"weight": 60, "reps": 8}]}]
              }]
            }
            """.trimIndent()
        )

        val exported = serializeBackupForExport(root)

        assertFalse(exported.contains('\n'))
        assertFalse(exported.contains("  "))
        assertEquals(root.toString(), exported)
        assertEquals(
            "line one\nline two",
            JSONObject(exported).getJSONArray("sessions").getJSONObject(0).getString("note")
        )
    }

    @Test
    fun legacyPrettyPrintedBackupStillPassesImportPreflightAndValidation() {
        val pretty = JSONObject(
            """
            {
              "schemaVersion": 2,
              "exercises": [{"name": "Bench Press", "favorite": true}],
              "sessions": [{
                "date": 1700000000000,
                "note": "Legs",
                "exercises": [{"name": "Bench Press", "sets": [{"weight": 60, "reps": 8}]}]
              }]
            }
            """.trimIndent()
        ).toString(2)
        assertTrue(pretty.contains('\n'))

        WorkoutDataLimits.requireSafeJsonEnvelope(pretty)
        val validated = BackupImportValidator.validate(JSONObject(pretty))

        assertEquals(1, validated.exercises.size)
        val set = validated.sessions.single().blocks.single().sets.single()
        assertEquals(60.0, set.weight, 0.0)
        assertEquals(8, set.reps)
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
