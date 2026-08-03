package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
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

        assertTrue(url.startsWith("https://gymapptracker.com/#workout="))
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
