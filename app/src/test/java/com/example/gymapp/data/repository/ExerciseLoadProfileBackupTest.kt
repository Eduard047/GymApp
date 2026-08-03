package com.example.gymapp.data.repository

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ExerciseLoadProfileBackupTest {
    @Test
    fun legacyExerciseWithoutLoadProfileRemainsValid() {
        val validated = BackupImportValidator.validate(backup(exercise("Bench Press")))

        assertNull(validated.exercises.single().loadProfile)
    }

    @Test
    fun exactMachineWeightsRoundTripThroughValidationAndCanonicalDigest() {
        val plain = backup(exercise("Lat Pulldown"))
        val configured = backup(
            exercise(
                name = "Lat Pulldown",
                direction = "higherIsHarder",
                weights = listOf(69.0, 73.0, 77.0)
            )
        )

        val profile = BackupImportValidator.validate(configured).exercises.single().loadProfile

        assertEquals(ExerciseLoadDirection.HigherIsHarder, profile?.direction)
        assertEquals(listOf(69.0, 73.0, 77.0), profile?.allowedWeightsKg)
        assertNotEquals(canonicalWorkoutPayloadDigest(plain), canonicalWorkoutPayloadDigest(configured))
    }

    @Test
    fun redundantIOSWorkoutLoadProfileMustMatchCatalogAndDoesNotChangeDigest() {
        val configured = backup(
            exercise(
                name = "Lat Pulldown",
                direction = "higherIsHarder",
                weights = listOf(69.0, 73.0, 77.0)
            )
        )
        val baseline = JSONObject(configured.toString()).apply {
            put(
                "sessions",
                JSONArray().put(
                    JSONObject()
                        .put("date", 1_750_000_000_000L)
                        .put(
                            "exercises",
                            JSONArray().put(
                                exercise(name = "Lat Pulldown").put(
                                    "sets",
                                    JSONArray().put(
                                        JSONObject().put("weight", 73.0).put("reps", 8)
                                    )
                                )
                            )
                        )
                )
            )
        }
        val redundant = JSONObject(baseline.toString()).apply {
            getJSONArray("sessions")
                .getJSONObject(0)
                .getJSONArray("exercises")
                .getJSONObject(0)
                .put(
                    "loadProfile",
                    JSONObject()
                        .put("direction", "higherIsHarder")
                        .put("allowedWeightsKg", JSONArray(listOf(69.0, 73.0, 77.0)))
                )
        }

        val validated = BackupImportValidator.validate(redundant)
        assertEquals(
            listOf(69.0, 73.0, 77.0),
            validated.exercises.single().loadProfile?.allowedWeightsKg
        )
        assertNull(validated.sessions.single().blocks.single().exercise.loadProfile)
        assertEquals(
            canonicalWorkoutPayloadDigest(baseline),
            canonicalWorkoutPayloadDigest(redundant)
        )

        val mismatched = JSONObject(redundant.toString()).apply {
            getJSONArray("sessions")
                .getJSONObject(0)
                .getJSONArray("exercises")
                .getJSONObject(0)
                .getJSONObject("loadProfile")
                .put("allowedWeightsKg", JSONArray(listOf(70.0, 75.0, 80.0)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupImportValidator.validate(mismatched)
        }
    }

    @Test
    fun loadProfileRejectsUnsupportedDirectionUnsortedDuplicatesAndOversizedLists() {
        listOf(
            exercise("Machine", "sideways", listOf(5.0, 10.0)),
            exercise("Machine", "higherIsHarder", listOf(10.0, 5.0)),
            exercise("Machine", "higherIsHarder", listOf(5.0, 5.0)),
            exercise(
                "Machine",
                "higherIsHarder",
                List(ExerciseLoadProfile.MAX_WEIGHT_OPTIONS + 1) { it.toDouble() }
            )
        ).forEach { invalidExercise ->
            assertThrows(IllegalArgumentException::class.java) {
                BackupImportValidator.validate(backup(invalidExercise))
            }
        }
    }

    @Test
    fun loadProfileRejectsNonNumericAndOutOfRangeWeights() {
        val nonNumeric = exercise("Machine", "higherIsHarder", listOf(5.0, 10.0))
        nonNumeric.getJSONObject("loadProfile")
            .getJSONArray("allowedWeightsKg")
            .put("heavy")
        val outOfRange = exercise(
            "Machine",
            "higherIsHarder",
            listOf(5.0, WorkoutDataLimits.MAX_WEIGHT + 1.0)
        )

        listOf(nonNumeric, outOfRange).forEach { invalidExercise ->
            assertThrows(IllegalArgumentException::class.java) {
                BackupImportValidator.validate(backup(invalidExercise))
            }
        }
    }

    private fun exercise(
        name: String,
        direction: String? = null,
        weights: List<Double> = emptyList()
    ): JSONObject = JSONObject()
        .put("name", name)
        .apply {
            if (direction != null) {
                put(
                    "loadProfile",
                    JSONObject()
                        .put("direction", direction)
                        .put("allowedWeightsKg", JSONArray(weights))
                )
            }
        }

    private fun backup(exercise: JSONObject): JSONObject = JSONObject()
        .put("schemaVersion", 2)
        .put("exercises", JSONArray().put(exercise))
        .put("sessions", JSONArray())
}
