package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class SharedWorkoutLinkTest {
    @Test
    fun compactLinkMatchesPwaVersionOneContract() {
        val url = SharedWorkoutLink.buildUrl(
            listOf(
                SharedWorkoutExercise(
                    catalogKey = "bench_press",
                    name = "Bench Press",
                    sets = listOf(
                        SharedWorkoutSet(80.0, 8),
                        SharedWorkoutSet(82.5, 6)
                    )
                )
            )
        )

        assertTrue(url.startsWith("https://gymapptracker.com/workout/#workout="))
        val encoded = url.substringAfter("#workout=")
        assertTrue(encoded.length <= SharedWorkoutLink.MAX_ENCODED_LENGTH)
        assertTrue(encoded.matches(Regex("^[A-Za-z0-9_-]+$")))
        val root = JSONObject(
            Base64.getUrlDecoder().decode(encoded).toString(Charsets.UTF_8)
        )
        assertEquals(setOf("v", "e"), root.keys().asSequence().toSet())
        assertEquals(1, root.getInt("v"))
        val exercise = root.getJSONArray("e").getJSONArray(0)
        assertEquals("bench_press", exercise.getString(0))
        assertEquals("Bench Press", exercise.getString(1))
        assertEquals(80.0, exercise.getJSONArray(2).getJSONArray(0).getDouble(0), 0.0)
        assertEquals(8, exercise.getJSONArray(2).getJSONArray(0).getInt(1))
    }

    @Test
    fun canonicalLegacyCustomAndWebFallbackUrlsRemainSeparated() {
        val plan = SharedWorkoutPlan(
            exercises = listOf(
                SharedWorkoutExercise(
                    catalogKey = "bench_press",
                    name = "Bench Press",
                    sets = listOf(SharedWorkoutSet(80.0, 8))
                )
            )
        )
        val encoded = SharedWorkoutLink.encode(plan.exercises)

        listOf(
            "https://gymapptracker.com/workout/#workout=$encoded",
            "https://gymapptracker.com/#workout=$encoded",
            "com.setforge.gymapp://workout/#workout=$encoded"
        ).forEach { url ->
            val result = SharedWorkoutLink.parseIncomingUrl(
                rawUrl = url,
                customScheme = "com.setforge.gymapp"
            )
            assertTrue(result is IncomingSharedWorkoutUrl.Valid)
            assertEquals(plan, (result as IncomingSharedWorkoutUrl.Valid).plan)
        }

        assertEquals(
            "https://gymapptracker.com/#workout=$encoded",
            SharedWorkoutLink.buildWebFallbackUrl(plan)
        )
        assertEquals(
            IncomingSharedWorkoutUrl.NotSharedWorkout,
            SharedWorkoutLink.parseIncomingUrl(
                rawUrl = "https://example.test/workout/#workout=$encoded",
                customScheme = "com.setforge.gymapp"
            )
        )
        assertEquals(
            IncomingSharedWorkoutUrl.NotSharedWorkout,
            SharedWorkoutLink.parseIncomingUrl(
                rawUrl = "com.setforge.gymapp://auth/callback#workout=$encoded",
                customScheme = "com.setforge.gymapp"
            )
        )
    }

    @Test
    fun recognizedShareUrlsFailClosedForMalformedOrAmbiguousPayloads() {
        val validEncoded = SharedWorkoutLink.encode(
            listOf(
                SharedWorkoutExercise(
                    catalogKey = null,
                    name = "Custom",
                    sets = listOf(SharedWorkoutSet(0.5, 10))
                )
            )
        )
        listOf(
            "https://gymapptracker.com/workout/",
            "https://gymapptracker.com/workout/?payload=$validEncoded#workout=$validEncoded",
            "https://gymapptracker.com/workout/#workout=***",
            "https://gymapptracker.com/workout/#workout=$validEncoded&next=evil",
            "com.setforge.gymapp://workout/#other=$validEncoded"
        ).forEach { url ->
            assertEquals(
                IncomingSharedWorkoutUrl.InvalidSharedWorkout,
                SharedWorkoutLink.parseIncomingUrl(url, "com.setforge.gymapp")
            )
        }
    }

    @Test
    fun decoderRejectsUnknownFieldsUnsupportedVersionsAndDuplicateExercises() {
        fun encodeJson(json: String): String =
            Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray(Charsets.UTF_8))

        listOf(
            "{\"v\":2,\"e\":[[\"\",\"Custom\",[[0,10]]]]}",
            "{\"v\":1.5,\"e\":[[\"\",\"Custom\",[[0,10]]]]}",
            "{\"v\":1,\"v\":1,\"e\":[[\"\",\"Custom\",[[0,10]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Custom\",[[0,10]]]],\"extra\":true}",
            "{\"v\":1,\"e\":[[\"\",\"Custom\",[[0,8.5]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Custom\",[[0,10]]],[\"\",\" custom \",[[0,12]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Visible\\u202ename\",[[0,10]]]]}"
        ).forEach { json ->
            assertThrows(IllegalArgumentException::class.java) {
                SharedWorkoutLink.decode(encodeJson(json))
            }
        }

        val invalidUtf8 = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(byteArrayOf(0xC3.toByte(), 0x28))
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.decode(invalidUtf8)
        }
    }

    @Test
    fun controlsFormatsAndLineSeparatorsFailEncodeDecodeAndImportNormalization() {
        val unsafeScalars = listOf(
            "\u0080",
            "\u009f",
            "\u200b",
            "\u2060",
            "\ufeff",
            "\u2028",
            "\u2029"
        )
        fun encodedJson(name: String): String {
            val json = JSONObject()
                .put("v", 1)
                .put(
                    "e",
                    JSONArray().put(
                        JSONArray()
                            .put("")
                            .put(name)
                            .put(JSONArray().put(JSONArray().put(10).put(8)))
                    )
                )
                .toString()
            return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(json.toByteArray(Charsets.UTF_8))
        }

        unsafeScalars.forEach { scalar ->
            val exercise = SharedWorkoutExercise(
                catalogKey = null,
                name = "Visible${scalar}Name",
                sets = listOf(SharedWorkoutSet(10.0, 8))
            )
            assertThrows(IllegalArgumentException::class.java) {
                SharedWorkoutLink.encode(listOf(exercise))
            }
            assertThrows(IllegalArgumentException::class.java) {
                SharedWorkoutLink.decode(encodedJson(exercise.name))
            }
            assertThrows(IllegalArgumentException::class.java) {
                SharedWorkoutLink.normalize(listOf(exercise))
            }
        }
    }

    @Test
    fun decoderRejectsASecondBase64SpellingOfTheSameBytes() {
        val canonical = SharedWorkoutLink.encode(
            listOf(
                SharedWorkoutExercise(
                    catalogKey = null,
                    name = "Custom",
                    sets = listOf(SharedWorkoutSet(0.5, 10))
                )
            )
        )
        val decoded = Base64.getUrlDecoder().decode(canonical)
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        val nonCanonical = alphabet.asSequence()
            .map { candidate -> canonical.dropLast(1) + candidate }
            .firstOrNull { candidate ->
                candidate != canonical && runCatching {
                    Base64.getUrlDecoder().decode(candidate).contentEquals(decoded)
                }.getOrDefault(false)
            }
        requireNotNull(nonCanonical)
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.decode(nonCanonical)
        }
    }

    @Test
    fun inboxOnlyConsumesTheMatchingPendingGeneration() {
        val inbox = SharedWorkoutInbox()
        val plan = SharedWorkoutPlan(
            listOf(SharedWorkoutExercise(null, "Custom", listOf(SharedWorkoutSet(0.0, 10))))
        )

        inbox.offer(plan)
        val first = requireNotNull(inbox.pending.value)
        inbox.consume(first.id + 1)
        assertEquals(first, inbox.pending.value)

        inbox.offer(plan)
        val second = requireNotNull(inbox.pending.value)
        assertTrue(second.id > first.id)
        inbox.consume(first.id)
        assertEquals(second, inbox.pending.value)
        inbox.consume(second.id)
        assertEquals(null, inbox.pending.value)
    }

    @Test
    fun sessionLinkSortsRowsAndExcludesPrivateAndGarminMetadata() {
        val privateNote = "account@example.test Garmin HR=188 calories=900 receipt=private"
        val details = WorkoutSessionDetails(
            session = WorkoutSessionEntity(id = 42, date = 1_750_000_000_000L, note = privateNote),
            workoutExercises = listOf(
                workoutExercise(
                    blockId = 22,
                    exerciseId = 2,
                    order = 1,
                    name = "Squat",
                    sets = listOf(set(222, 22, 1, 105.0, 5))
                ),
                workoutExercise(
                    blockId = 11,
                    exerciseId = 1,
                    order = 0,
                    name = "Bench Press",
                    sets = listOf(
                        set(112, 11, 1, 82.5, 6),
                        set(111, 11, 0, 80.0, 8)
                    )
                ),
                workoutExercise(
                    blockId = 33,
                    exerciseId = 3,
                    order = 2,
                    name = "Crunch",
                    sets = emptyList()
                )
            )
        )

        val url = SharedWorkoutLink.fromSession(details)
        val decoded = Base64.getUrlDecoder()
            .decode(url.substringAfter("#workout="))
            .toString(Charsets.UTF_8)
        val exercises = JSONObject(decoded).getJSONArray("e")

        assertEquals(2, exercises.length())
        assertEquals("bench_press", exercises.getJSONArray(0).getString(0))
        assertEquals(80.0, exercises.getJSONArray(0).getJSONArray(2).getJSONArray(0).getDouble(0), 0.0)
        assertEquals("squat", exercises.getJSONArray(1).getString(0))
        assertFalse(decoded.contains(privateNote))
        assertFalse(decoded.contains("account@example.test"))
        assertFalse(decoded.contains("Garmin"))
        assertFalse(decoded.contains("Crunch"))
    }

    @Test
    fun countsNamesCatalogKeysAndEncodedBytesAreBounded() {
        val valid = SharedWorkoutExercise(null, "Custom", listOf(SharedWorkoutSet(0.0, 1)))
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(emptyList())
        }
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(List(SharedWorkoutLink.MAX_EXERCISES + 1) { valid })
        }
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(
                listOf(valid.copy(sets = List(SharedWorkoutLink.MAX_SETS_PER_EXERCISE + 1) {
                    SharedWorkoutSet(1.0, 1)
                }))
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(
                List(11) {
                    valid.copy(sets = List(11) { SharedWorkoutSet(1.0, 1) })
                }
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(listOf(valid.copy(name = "a".repeat(121))))
        }
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(listOf(valid.copy(catalogKey = "Bench-Press")))
        }
        assertThrows(IllegalArgumentException::class.java) {
            SharedWorkoutLink.encode(
                List(SharedWorkoutLink.MAX_EXERCISES) {
                    valid.copy(name = "🙂".repeat(SharedWorkoutLink.MAX_NAME_CODE_POINTS))
                }
            )
        }
    }

    @Test
    fun weightsAndRepetitionsRejectNonFiniteNegativeAndOutOfRangeValues() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, SharedWorkoutLink.MAX_WEIGHT + 1.0)
            .forEach { weight ->
                assertThrows(IllegalArgumentException::class.java) {
                    SharedWorkoutLink.encode(
                        listOf(
                            SharedWorkoutExercise(
                                catalogKey = null,
                                name = "Custom",
                                sets = listOf(SharedWorkoutSet(weight, 8))
                            )
                        )
                    )
                }
            }
        listOf(0, -1, SharedWorkoutLink.MAX_REPS + 1).forEach { reps ->
            assertThrows(IllegalArgumentException::class.java) {
                SharedWorkoutLink.encode(
                    listOf(
                        SharedWorkoutExercise(
                            catalogKey = null,
                            name = "Custom",
                            sets = listOf(SharedWorkoutSet(20.0, reps))
                        )
                    )
                )
            }
        }
    }

    private fun workoutExercise(
        blockId: Long,
        exerciseId: Long,
        order: Int,
        name: String,
        sets: List<SetEntryEntity>
    ) = WorkoutExerciseWithDetails(
        workoutExercise = WorkoutExerciseEntity(
            id = blockId,
            sessionId = 42,
            exerciseId = exerciseId,
            orderIndex = order
        ),
        exercise = ExerciseEntity(id = exerciseId, name = name),
        sets = sets
    )

    private fun set(
        id: Long,
        blockId: Long,
        order: Int,
        weight: Double,
        reps: Int
    ) = SetEntryEntity(
        id = id,
        workoutExerciseId = blockId,
        weight = weight,
        reps = reps,
        orderIndex = order
    )
}
