package com.example.gymapp.data.repository

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
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
    fun canonicalDigestIgnoresMixedScriptCatalogOrderButRetainsExerciseData() {
        val latin = exercise(
            name = "Lat Pulldown",
            direction = "higherIsHarder",
            weights = listOf(45.0, 50.0, 55.0)
        ).put("catalogKey", "lat_pulldown")
        val cyrillic = exercise(
            name = "Кастомна тяга",
            direction = "lowerIsHarder",
            weights = listOf(20.0, 25.0, 30.0)
        ).put("catalogKey", "custom_pull")
        val original = backup(latin, cyrillic)
        val reordered = backup(
            JSONObject(cyrillic.toString()),
            JSONObject(latin.toString())
        )

        assertEquals(
            canonicalWorkoutPayloadDigest(original),
            canonicalWorkoutPayloadDigest(reordered)
        )
        assertTrue(canonicalWorkoutPayloadMatches(original, reordered))

        val changedProfile = JSONObject(original.toString()).apply {
            getJSONArray("exercises").getJSONObject(0)
                .getJSONObject("loadProfile")
                .put("allowedWeightsKg", JSONArray(listOf(45.0, 50.0, 57.5)))
        }
        val changedName = JSONObject(original.toString()).apply {
            getJSONArray("exercises").getJSONObject(0).put("name", "Wide Lat Pulldown")
        }
        val changedCatalogKey = JSONObject(original.toString()).apply {
            getJSONArray("exercises").getJSONObject(1).put("catalogKey", "custom_pull_v2")
        }

        listOf(changedProfile, changedName, changedCatalogKey).forEach { changed ->
            assertNotEquals(
                canonicalWorkoutPayloadDigest(original),
                canonicalWorkoutPayloadDigest(changed)
            )
        }
    }

    @Test
    fun portableCatalogOrderMatchesSharedUnsignedUtf8Fixture() {
        val fixture = listOf(
            "тяга custom",
            "Присідання custom",
            "deadlift custom",
            "Жим custom",
            "Élévation custom",
            "bench custom",
            "Bench custom",
            "A custom",
            "🏋️ custom"
        ).map { name -> ValidatedBackupExercise(name = name, catalogKey = null) }

        assertEquals(
            listOf(
                "A custom",
                "Bench custom",
                "bench custom",
                "deadlift custom",
                "Élévation custom",
                "Жим custom",
                "Присідання custom",
                "тяга custom",
                "🏋️ custom"
            ),
            canonicalExerciseCatalogOrder(fixture).map { it.name }
        )
    }

    @Test
    fun duplicateTopLevelCanonicalIdentityIsRejected() {
        listOf(
            backup(exercise("Bench Press"), exercise("Bench Press")),
            backup(exercise("Bench Press"), exercise("bench press")),
            backup(exercise("Bench Press"), exercise("Жим лежачи")),
            JSONObject(
                """
                {
                  "schemaVersion": 2,
                  "exercises": [{"name":"Bíceps"},{"name":"Bíceps"}],
                  "sessions": []
                }
                """.trimIndent()
            ),
            JSONObject(
                """
                {
                  "schemaVersion": 2,
                  "exercises": [{"name":"Custom Row"},{"name":"Custom Row"}],
                  "sessions": []
                }
                """.trimIndent()
            )
        ).forEach { duplicateCatalog ->
            assertThrows(IllegalArgumentException::class.java) {
                BackupImportValidator.validate(duplicateCatalog)
            }
            assertNull(canonicalWorkoutPayloadDigest(duplicateCatalog))
        }
    }

    @Test
    fun identityNormalizationKeepsAccentsAndCharacterWidthDistinctInRawJson() {
        val strictDistinct = JSONObject(
            """
            {
              "schemaVersion": 2,
              "exercises": [
                {"name":"Biceps"},
                {"name":"Bíceps"},
                {"name":"Ｂiceps"}
              ],
              "sessions": []
            }
            """.trimIndent()
        )

        val validated = BackupImportValidator.validate(strictDistinct)

        assertEquals(3, validated.exercises.map { it.identityKey }.toSet().size)
        assertNotEquals(
            validated.exercises[0].identityKey,
            validated.exercises[1].identityKey
        )
        assertNotEquals(
            validated.exercises[0].identityKey,
            validated.exercises[2].identityKey
        )
        assertNotEquals(null, canonicalWorkoutPayloadDigest(strictDistinct))
    }

    @Test
    fun signedZeroNormalizesBeforeEqualityAndDigest() {
        val positive = backup(
            exercise("Machine", "higherIsHarder", listOf(0.0, 5.0))
        ).put(
            "sessions",
            JSONArray().put(session("Machine", listOf(0.0 to 8, 5.0 to 6)))
        )
        val negative = JSONObject(positive.toString()).apply {
            getJSONArray("exercises").getJSONObject(0)
                .getJSONObject("loadProfile").getJSONArray("allowedWeightsKg").put(0, -0.0)
            getJSONArray("sessions").getJSONObject(0)
                .getJSONArray("exercises").getJSONObject(0)
                .getJSONArray("sets").getJSONObject(0).put("weight", -0.0)
        }

        assertEquals(BackupImportValidator.validate(positive), BackupImportValidator.validate(negative))
        assertEquals(canonicalWorkoutPayloadDigest(positive), canonicalWorkoutPayloadDigest(negative))
    }

    @Test
    fun paddedWorkoutNoteCanonicalizesLikeRoomAndIosPersistence() {
        val padded = backup(exercise("Machine")).put(
            "sessions",
            JSONArray().put(session("Machine", listOf(10.0 to 8)).put("note", "  Technique  "))
        )
        val trimmed = JSONObject(padded.toString()).apply {
            getJSONArray("sessions").getJSONObject(0).put("note", "Technique")
        }

        assertEquals(
            BackupImportValidator.validate(trimmed),
            BackupImportValidator.validate(padded)
        )
        assertEquals(
            canonicalWorkoutPayloadDigest(trimmed),
            canonicalWorkoutPayloadDigest(padded)
        )
    }

    @Test
    fun sessionBlockAndSetOrderRemainSignificant() {
        val firstSession = session("First", listOf(10.0 to 8, 12.5 to 6)).apply {
            getJSONArray("exercises").put(
                session("Second", listOf(20.0 to 5))
                    .getJSONArray("exercises").getJSONObject(0)
            )
        }
        val baseline = backup(exercise("First"), exercise("Second")).put(
            "sessions",
            JSONArray()
                .put(firstSession)
                .put(session("Second", listOf(20.0 to 5), date = 1_750_000_000_001L))
        )
        val sessionsReordered = JSONObject(baseline.toString()).apply {
            val sessions = getJSONArray("sessions")
            put("sessions", JSONArray().put(sessions.getJSONObject(1)).put(sessions.getJSONObject(0)))
        }
        val blocksReordered = JSONObject(baseline.toString()).apply {
            val session = getJSONArray("sessions").getJSONObject(0)
            val blocks = session.getJSONArray("exercises")
            session.put(
                "exercises",
                JSONArray().put(blocks.getJSONObject(1)).put(blocks.getJSONObject(0))
            )
        }
        val setsReordered = JSONObject(baseline.toString()).apply {
            val sets = getJSONArray("sessions").getJSONObject(0)
                .getJSONArray("exercises").getJSONObject(0).getJSONArray("sets")
            getJSONArray("sessions").getJSONObject(0).getJSONArray("exercises").getJSONObject(0)
                .put("sets", JSONArray().put(sets.getJSONObject(1)).put(sets.getJSONObject(0)))
        }

        listOf(sessionsReordered, blocksReordered, setsReordered).forEach { reordered ->
            assertNotEquals(canonicalWorkoutPayloadDigest(baseline), canonicalWorkoutPayloadDigest(reordered))
        }
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

    private fun session(
        exerciseName: String,
        sets: List<Pair<Double, Int>>,
        date: Long = 1_750_000_000_000L
    ): JSONObject = JSONObject()
        .put("date", date)
        .put(
            "exercises",
            JSONArray().put(
                JSONObject()
                    .put("name", exerciseName)
                    .put(
                        "sets",
                        JSONArray(sets.map { (weight, reps) ->
                            JSONObject().put("weight", weight).put("reps", reps)
                        })
                    )
            )
        )

    private fun backup(vararg exercises: JSONObject): JSONObject = JSONObject()
        .put("schemaVersion", 2)
        .put("exercises", JSONArray(exercises.toList()))
        .put("sessions", JSONArray())
}
